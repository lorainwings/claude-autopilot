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

# --- Fast bypass: pure bash marker detection ---
if ! echo "$STDIN_DATA" | grep -q 'autopilot-phase:[0-9]'; then
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

# Rationalization patterns (case-insensitive)
PATTERNS = [
    r'out\s+of\s+scope',
    r'pre[- ]existing\s+(issue|bug|problem|defect)',
    r'skip(ped|ping)?\s+(this|the|these)\s+(test|task|check|step|item)',
    r'not\s+(needed|necessary|required|relevant|applicable)',
    r'already\s+(covered|tested|handled|addressed)',
    r'too\s+(complex|difficult|risky|time[- ]consuming)',
    r'(will|can|should)\s+(be\s+)?(done|handled|addressed|fixed)\s+(later|separately|in\s+a?\s*future)',
    r'(deferred?|postponed?|deprioritized?)\s+(to|for|until)',
    r'(minimal|low)\s+(impact|priority|risk)',
    r'(works|good)\s+enough',
]

output_lower = output.lower()
found_patterns = []
for pattern in PATTERNS:
    if re.search(pattern, output_lower):
        found_patterns.append(pattern)

if found_patterns:
    print(json.dumps({
        'decision': 'block',
        'reason': f'Anti-rationalization check: Phase {phase_num} output contains {len(found_patterns)} potential skip/rationalization pattern(s). Detected patterns suggest the sub-agent may be rationalizing skipping work. Review the output and re-dispatch if needed. Patterns found: {found_patterns[:3]}'
    }))
    sys.exit(0)

# No patterns found → allow
sys.exit(0)
"

exit 0
