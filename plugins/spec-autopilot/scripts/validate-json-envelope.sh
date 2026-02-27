#!/usr/bin/env bash
# validate-json-envelope.sh
# Hook: PostToolUse(Task)
# Purpose: After a sub-Agent completes, validate its output contains a valid
#          JSON envelope with required fields (status/summary/artifacts/next_ready).
#
# Detection: Only processes Task calls whose prompt contains
#            <!-- autopilot-phase:N -->. All other Task calls are immediately allowed.
#
# Exit codes: Always 0 (PostToolUse cannot undo completed operations).
#             Warnings/errors are emitted to stderr for observability only.

set -euo pipefail

# Read PostToolUse stdin JSON: {"tool_name":"Task","tool_input":{...},"tool_result":"..."}
STDIN_DATA=""
if [ ! -t 0 ]; then
  STDIN_DATA=$(cat)
fi

if [ -z "$STDIN_DATA" ]; then
  exit 0
fi

# Check for <!-- autopilot-phase:N --> marker in tool_input.prompt
HAS_MARKER=$(echo "$STDIN_DATA" | python3 -c "
import json, sys, re
try:
    data = json.load(sys.stdin)
    prompt = data.get('tool_input', {}).get('prompt', '')
    m = re.search(r'<!--\s*autopilot-phase:\d+\s*-->', prompt)
    print('yes' if m else 'no')
except Exception:
    print('no')
" 2>/dev/null || echo "no")

# No marker → not an autopilot Task, skip validation
if [ "$HAS_MARKER" != "yes" ]; then
  exit 0
fi

# --- From here on, this is an autopilot Task result ---

# Extract tool_result from the stdin JSON
AGENT_OUTPUT=$(echo "$STDIN_DATA" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get('tool_result', ''))
except Exception:
    pass
" 2>/dev/null || echo "")

if [ -z "$AGENT_OUTPUT" ]; then
  echo "WARNING: Empty sub-Agent output for autopilot Task" >&2
  exit 0
fi

# Validate JSON envelope (all warnings go to stderr, always exit 0)
echo "$AGENT_OUTPUT" | python3 -c "
import json
import re
import sys

output = sys.stdin.read()

# Try to find JSON block in the output
json_patterns = [
    # Fenced code block
    r'\`\`\`(?:json)?\s*\n({.*?})\s*\n\`\`\`',
    # Raw JSON object
    r'(\{[^{}]*\"status\"[^{}]*\})',
]

found_json = None

for pattern in json_patterns:
    matches = re.findall(pattern, output, re.DOTALL)
    for match in matches:
        try:
            data = json.loads(match)
            if 'status' in data:
                found_json = data
                break
        except json.JSONDecodeError:
            continue
    if found_json:
        break

if not found_json:
    # Try parsing the entire output as JSON
    try:
        found_json = json.loads(output.strip())
    except json.JSONDecodeError:
        pass

if not found_json:
    print('WARNING: No valid JSON envelope found in autopilot sub-Agent output', file=sys.stderr)
    sys.exit(0)

# Validate required fields
required_fields = ['status', 'summary']
missing = [f for f in required_fields if f not in found_json]

if missing:
    print(f'WARNING: JSON envelope missing required fields: {missing}', file=sys.stderr)
    sys.exit(0)

# Validate status value
valid_statuses = ['ok', 'warning', 'blocked', 'failed']
if found_json['status'] not in valid_statuses:
    print(f'WARNING: Invalid status \"{found_json[\"status\"]}\". Must be one of: {valid_statuses}', file=sys.stderr)
    sys.exit(0)

# Info-level notices for optional fields (stderr only)
if 'artifacts' not in found_json:
    print('INFO: JSON envelope missing optional field: artifacts', file=sys.stderr)

if 'next_ready' not in found_json:
    print('INFO: JSON envelope missing optional field: next_ready', file=sys.stderr)

print(f'OK: Valid autopilot JSON envelope with status=\"{found_json[\"status\"]}\"', file=sys.stderr)
sys.exit(0)
" 2>&1 >&2

exit 0
