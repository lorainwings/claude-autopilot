#!/usr/bin/env bash
# anti-rationalization-check.sh
# Hook: PostToolUse(Task) — runs after validate-json-envelope.sh
# Purpose: Detect rationalization patterns in autopilot sub-agent output
#          that might indicate test/task skipping.
#
# Only fires when ALL conditions are met:
#   1. Phase 4, 5, or 6 (testing/implementation/reporting phases)
#   2. Status is ok or warning (not blocked/failed — those are legitimate stops)
#   3. Output contains rationalization patterns
#
# Output: PostToolUse `decision: "block"` with reason on pattern match.

set -uo pipefail

# --- Read stdin JSON ---
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
if ! echo "$STDIN_DATA" | grep -q '"prompt"[[:space:]]*:[[:space:]]*"<!-- autopilot-phase:[0-9]'; then
  exit 0
fi

# --- Dependency check ---
if ! command -v python3 &>/dev/null; then
  # Cannot validate without python3 → allow (this is a secondary check)
  # Primary validation is done by validate-json-envelope.sh which blocks on missing python3
  exit 0
fi

# --- Pattern detection via python3 ---
echo "$STDIN_DATA" | python3 -c "
import json
import re
import sys

try:
    data = json.load(sys.stdin)
except (json.JSONDecodeError, ValueError):
    sys.exit(0)

# Extract phase number
prompt = data.get('tool_input', {}).get('prompt', '')
phase_match = re.search(r'autopilot-phase:(\d+)', prompt)
if not phase_match:
    sys.exit(0)

phase_num = int(phase_match.group(1))

# Only check phases 4, 5, 6
if phase_num not in (4, 5, 6):
    sys.exit(0)

# Extract tool_response
tool_response = data.get('tool_response', '')
if isinstance(tool_response, dict):
    output = json.dumps(tool_response)
elif isinstance(tool_response, str):
    output = tool_response
else:
    output = str(tool_response) if tool_response else ''

if not output.strip():
    sys.exit(0)

# Try to extract status from JSON envelope
status = None
decoder = json.JSONDecoder()
for i, ch in enumerate(output):
    if ch == '{':
        try:
            obj, end = decoder.raw_decode(output, i)
            if isinstance(obj, dict) and 'status' in obj:
                status = obj['status']
                break
        except (json.JSONDecodeError, ValueError):
            continue

# Only check ok/warning status — blocked/failed are legitimate stops
if status not in ('ok', 'warning'):
    sys.exit(0)

# Weighted rationalization patterns (case-insensitive)
# High confidence (weight=3): strong skip signals
# Medium confidence (weight=2): scope/deferral signals
# Low confidence (weight=1): weak signals that are common in legitimate output
WEIGHTED_PATTERNS = [
    # High confidence (weight=3)
    (3, r'skip(ped|ping)?\s+(this|the|these|because)\s'),
    (3, r'(tests?|tasks?)\s+were\s+skip(ped|ping)'),
    (3, r'(deferred?|postponed?|deprioritized?)\s+(to|for|until)'),
    # Medium confidence (weight=2)
    (2, r'out\s+of\s+scope'),
    (2, r'(will|can|should)\s+(be\s+)?(done|handled|addressed|fixed)\s+(later|separately|in\s+a?\s*future)'),
    # Low confidence (weight=1)
    (1, r'already\s+(covered|tested|handled|addressed)'),
    (1, r'not\s+(needed|necessary|required|relevant|applicable)'),
    (1, r'(works|good)\s+enough'),
    (1, r'too\s+(complex|difficult|risky|time[- ]consuming)'),
    (1, r'(minimal|low)\s+(impact|priority|risk)'),
    (1, r'pre[- ]existing\s+(issue|bug|problem|defect)'),
]

output_lower = output.lower()
total_score = 0
found_patterns = []
for weight, pattern in WEIGHTED_PATTERNS:
    if re.search(pattern, output_lower):
        total_score += weight
        found_patterns.append((weight, pattern))

# Extract artifacts from JSON envelope to check for actual output
has_artifacts = False
for i, ch in enumerate(output):
    if ch == '{':
        try:
            obj, end = decoder.raw_decode(output, i)
            if isinstance(obj, dict) and 'artifacts' in obj:
                arts = obj['artifacts']
                has_artifacts = isinstance(arts, list) and len(arts) > 0
                break
        except (json.JSONDecodeError, ValueError):
            continue

# Scoring thresholds:
#   total_score >= 5          → hard block
#   total_score >= 3 + no artifacts → block (suspicious + no output)
#   total_score >= 2          → stderr warning only (no block)
#   total_score < 2           → pass silently
if total_score >= 5:
    print(json.dumps({
        'decision': 'block',
        'reason': f'Anti-rationalization check: Phase {phase_num} output scored {total_score} (threshold 5). Multiple strong skip/rationalization patterns detected. Review and re-dispatch. Patterns: {[p for _, p in found_patterns[:3]]}'
    }))
    sys.exit(0)

if total_score >= 3 and not has_artifacts:
    print(json.dumps({
        'decision': 'block',
        'reason': f'Anti-rationalization check: Phase {phase_num} output scored {total_score} with no artifacts produced. Suspected rationalization without deliverables. Review and re-dispatch. Patterns: {[p for _, p in found_patterns[:3]]}'
    }))
    sys.exit(0)

if total_score >= 2:
    print(json.dumps({
        'decision': 'warn',
        'reason': f'Anti-rationalization advisory: Phase {phase_num} output scored {total_score} but has artifacts. Patterns: {[p for _, p in found_patterns[:3]]}'
    }), file=sys.stderr)
    sys.exit(0)

# Score below threshold → allow
sys.exit(0)
"

exit 0
