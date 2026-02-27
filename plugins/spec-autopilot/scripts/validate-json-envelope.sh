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

# --- Fast bypass: pure bash marker detection ---
# If the autopilot marker isn't present anywhere in stdin, skip python3 entirely.
# This avoids forking python3 for every non-autopilot Task call (~200-500ms savings).
if ! echo "$STDIN_DATA" | grep -q 'autopilot-phase:[0-9]'; then
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

# Strategy A: Try json.JSONDecoder().raw_decode to find first valid JSON object
decoder = json.JSONDecoder()
# Search for '{' positions and try to decode from each
for i, ch in enumerate(output):
    if ch == '{':
        try:
            obj, end = decoder.raw_decode(output, i)
            if isinstance(obj, dict) and 'status' in obj:
                found_json = obj
                break
        except (json.JSONDecodeError, ValueError):
            continue

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
    4: ['test_counts', 'dry_run_results'],
    5: ['test_results_path', 'tasks_completed', 'zero_skip_check'],
    6: ['pass_rate', 'report_path'],
}

if phase_num in phase_required:
    missing_phase = [f for f in phase_required[phase_num] if f not in found_json]
    if missing_phase:
        print(json.dumps({
            'decision': 'block',
            'reason': f'Phase {phase_num} JSON envelope missing required phase-specific fields: {missing_phase}. The sub-agent must include these fields for gate verification.'
        }))
        sys.exit(0)

# All valid → no output, let PostToolUse proceed normally
print(f'OK: Valid autopilot JSON envelope with status=\"{found_json[\"status\"]}\"', file=sys.stderr)
sys.exit(0)
"
# NOTE: python3 stderr is NOT suppressed — allows observability of INFO messages
# and uncaught exceptions in verbose mode (Ctrl+O).

exit 0
