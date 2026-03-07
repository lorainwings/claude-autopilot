#!/usr/bin/env bash
# validate-json-envelope.sh
# Hook: PostToolUse(Task)
# Purpose: After a sub-Agent completes, validate its output contains a valid
#          JSON envelope with required fields (status/summary).
#
# Detection: Only processes Task calls whose prompt contains
#            <!-- autopilot-phase:N -->. All other Task calls exit 0 immediately.
#
# Output: Uses PostToolUse `decision: "block"` with `reason` to feed validation
#         errors back to Claude as actionable feedback. Exit is always 0.
#         See: https://code.claude.com/docs/en/hooks#posttooluse-decision-control

set -uo pipefail
# NOTE: no `set -e` — we handle errors explicitly.

# --- Read stdin JSON ---
# PostToolUse receives: {"tool_name":"Task","tool_input":{...},"tool_response":"..."}
STDIN_DATA=""
if [ ! -t 0 ]; then
  STDIN_DATA=$(cat)
fi

if [ -z "$STDIN_DATA" ]; then
  exit 0
fi

# --- Fast bypass Layer 0: lock file pre-check ---
# 无活跃 autopilot 会话时，跳过所有检查。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
PROJECT_ROOT_QUICK=$(echo "$STDIN_DATA" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
if [ -z "$PROJECT_ROOT_QUICK" ]; then
  PROJECT_ROOT_QUICK="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
if ! has_active_autopilot "$PROJECT_ROOT_QUICK"; then
  exit 0
fi

# --- Fast bypass Layer 1: prompt 首行标记检测 ---
# 仅匹配 prompt 字段以标记开头的情况，排除文本内容中的误判。
if ! echo "$STDIN_DATA" | grep -q '"prompt"[[:space:]]*:[[:space:]]*"<!-- autopilot-phase:[0-9]'; then
  exit 0
fi

# --- Dependency check (only needed for autopilot Tasks) ---
if ! command -v python3 &>/dev/null; then
  # Fail-closed: block autopilot tasks when python3 unavailable
  # (consistent with check-predecessor-checkpoint.sh behavior)
  cat <<'BLOCK_JSON'
{
  "decision": "block",
  "reason": "python3 is required for autopilot envelope validation but not found in PATH. Install python3 to continue."
}
BLOCK_JSON
  exit 0
fi

# --- Single python3 call to do all processing ---
echo "$STDIN_DATA" | python3 -c "
import json
import re
import sys

try:
    data = json.load(sys.stdin)
except (json.JSONDecodeError, ValueError) as e:
    print(f'WARNING: Hook received malformed JSON from Claude Code: {e}', file=sys.stderr)
    sys.exit(0)

# 1) Check for autopilot marker in tool_input.prompt
prompt = data.get('tool_input', {}).get('prompt', '')
if not re.search(r'<!--\s*autopilot-phase:\d+\s*-->', prompt):
    # Not an autopilot Task → no validation needed
    sys.exit(0)

# 2) Extract tool_response (official PostToolUse field name)
#    tool_response for Task is the sub-agent's output text
tool_response = data.get('tool_response', '')
if isinstance(tool_response, dict):
    # Some tools return structured responses
    output = json.dumps(tool_response)
elif isinstance(tool_response, str):
    output = tool_response
else:
    output = str(tool_response) if tool_response else ''

if not output.strip():
    # Empty output → tell Claude to re-dispatch
    print(json.dumps({
        'decision': 'block',
        'reason': 'Autopilot sub-agent returned empty output. The orchestrator should re-dispatch this phase.'
    }))
    sys.exit(0)

# 3) Extract JSON envelope from output using raw_decode (handles nested objects)
found_json = None

# Strategy A: Two-pass search — prefer JSON with both 'status' AND 'summary'
# (avoids matching tool output JSON that happens to have 'status' but no 'summary')
decoder = json.JSONDecoder()
candidates = []
for i, ch in enumerate(output):
    if ch == '{':
        try:
            obj, end = decoder.raw_decode(output, i)
            if isinstance(obj, dict) and 'status' in obj:
                candidates.append(obj)
        except (json.JSONDecodeError, ValueError):
            continue

# Pass 1: Find first candidate with both required fields (full envelope)
for c in candidates:
    if 'summary' in c:
        found_json = c
        break
# Pass 2: Fall back to first candidate with 'status' only
if not found_json and candidates:
    found_json = candidates[0]

# Strategy B: Try fenced code block extraction
if not found_json:
    code_block_match = re.search(r'\x60\x60\x60(?:json)?\s*\n(.*?)\n\x60\x60\x60', output, re.DOTALL)
    if code_block_match:
        try:
            obj = json.loads(code_block_match.group(1))
            if isinstance(obj, dict) and 'status' in obj:
                found_json = obj
        except (json.JSONDecodeError, ValueError):
            pass

# Strategy C: Try parsing entire output as JSON
if not found_json:
    try:
        obj = json.loads(output.strip())
        if isinstance(obj, dict):
            found_json = obj
    except (json.JSONDecodeError, ValueError):
        pass

if not found_json:
    print(json.dumps({
        'decision': 'block',
        'reason': 'No valid JSON envelope found in autopilot sub-agent output. The sub-agent must return a JSON object with at least {\"status\": \"ok|warning|blocked|failed\", \"summary\": \"...\"}. Re-dispatch this phase with clearer instructions.'
    }))
    sys.exit(0)

# 4) Validate required fields
required_fields = ['status', 'summary']
missing = [f for f in required_fields if f not in found_json]

if missing:
    print(json.dumps({
        'decision': 'block',
        'reason': f'Autopilot JSON envelope missing required fields: {missing}. The sub-agent must include both \"status\" and \"summary\" fields.'
    }))
    sys.exit(0)

# 5) Validate status value
valid_statuses = ['ok', 'warning', 'blocked', 'failed']
if found_json['status'] not in valid_statuses:
    print(json.dumps({
        'decision': 'block',
        'reason': f'Invalid autopilot status \"{found_json[\"status\"]}\". Must be one of: {valid_statuses}'
    }))
    sys.exit(0)

# 6) Info-level notices for optional fields (stderr only, not fed to Claude)
if 'artifacts' not in found_json:
    print('INFO: JSON envelope missing optional field: artifacts', file=sys.stderr)
if 'next_ready' not in found_json:
    print('INFO: JSON envelope missing optional field: next_ready', file=sys.stderr)

# 7) Phase-specific field validation (warn on stderr, block on critical missing)
phase_match = re.search(r'autopilot-phase:(\d+)', prompt)
phase_num = int(phase_match.group(1)) if phase_match else 0

phase_required = {
    4: ['test_counts', 'dry_run_results', 'test_pyramid'],
    5: ['test_results_path', 'tasks_completed', 'zero_skip_check'],
    6: ['pass_rate', 'report_path', 'report_format', 'suite_results'],
}

if phase_num in phase_required:
    missing_phase = [f for f in phase_required[phase_num] if f not in found_json]
    if missing_phase:
        print(json.dumps({
            'decision': 'block',
            'reason': f'Phase {phase_num} JSON envelope missing required phase-specific fields: {missing_phase}. The sub-agent must include these fields for gate verification.'
        }))
        sys.exit(0)

# 8) Phase 4 special: warning status not acceptable — Phase 4 protocol only allows ok/blocked
#    Layer 2 deterministic check — prevents LLM orchestrator from accidentally
#    passing Phase 4 with warning. Phase 4 must re-dispatch until ok or blocked.
if phase_num == 4 and found_json['status'] == 'warning':
    print(json.dumps({
        'decision': 'block',
        'reason': 'Phase 4 returned \"warning\" but only \"ok\" or \"blocked\" are accepted. Re-dispatch Phase 4.'
    }))
    sys.exit(0)

# 9) Phase 4 and 6: artifacts must be non-empty (test files / report files required)
if phase_num in (4, 6):
    artifacts = found_json.get('artifacts', [])
    if not isinstance(artifacts, list) or len(artifacts) == 0:
        print(json.dumps({
            'decision': 'block',
            'reason': f'Phase {phase_num} \"artifacts\" is empty or missing. Phase {phase_num} must produce actual output files.'
        }))
        sys.exit(0)

# 10) Layer 2 test_pyramid floor validation (Phase 4 only)
#     These are lenient floors — strict thresholds enforced by Layer 3 (autopilot-gate).
#     Catches severely inverted pyramids that slip through LLM self-checks.
if phase_num == 4:
    pyramid = found_json.get('test_pyramid', {})
    unit_pct = pyramid.get('unit_pct', 0)
    e2e_pct = pyramid.get('e2e_pct', 0)
    total = found_json.get('test_counts', {})
    total_sum = sum(v for v in total.values() if isinstance(v, (int, float)))

    violations = []
    if isinstance(unit_pct, (int, float)) and unit_pct < 30:
        violations.append(f'unit_pct={unit_pct}% < 30% floor')
    if isinstance(e2e_pct, (int, float)) and e2e_pct > 40:
        violations.append(f'e2e_pct={e2e_pct}% > 40% ceiling')
    if total_sum < 10:
        violations.append(f'total_cases={total_sum} < 10 minimum')

    if violations:
        print(json.dumps({
            'decision': 'block',
            'reason': f'Phase 4 test_pyramid floor violation (Layer 2): {\";\".join(violations)}. Adjust test distribution before proceeding.'
        }))
        sys.exit(0)

# All valid → no output, let PostToolUse proceed normally
print(f'OK: Valid autopilot JSON envelope with status=\"{found_json[\"status\"]}\"', file=sys.stderr)
sys.exit(0)
"
# NOTE: python3 stderr is NOT suppressed — allows observability of INFO messages
# and uncaught exceptions in verbose mode (Ctrl+O).

exit 0
