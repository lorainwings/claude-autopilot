#!/usr/bin/env bash
# validate-json-envelope.sh
# Hook: SubagentStop
# Purpose: After a sub-Agent completes, validate its output contains a valid
#          JSON envelope with required fields (status/summary/artifacts/next_ready).
# Exit codes: 0=valid, 1=warning (invalid but non-blocking)

set -euo pipefail

# Read agent output from stdin or AGENT_OUTPUT env var
AGENT_OUTPUT="${AGENT_OUTPUT:-}"

if [ -z "$AGENT_OUTPUT" ]; then
  if [ -t 0 ]; then
    # No input available
    exit 0
  fi
  AGENT_OUTPUT=$(cat)
fi

if [ -z "$AGENT_OUTPUT" ]; then
  exit 0
fi

# Try to extract JSON from the output (may be embedded in markdown or text)
validate_envelope() {
  python3 -c "
import json
import re
import sys

output = '''$AGENT_OUTPUT'''

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
    print('WARNING: No valid JSON envelope found in sub-Agent output', file=sys.stderr)
    sys.exit(1)

# Validate required fields
required_fields = ['status', 'summary']
missing = [f for f in required_fields if f not in found_json]

if missing:
    print(f'WARNING: JSON envelope missing required fields: {missing}', file=sys.stderr)
    sys.exit(1)

# Validate status value
valid_statuses = ['ok', 'warning', 'blocked', 'failed']
if found_json['status'] not in valid_statuses:
    print(f'WARNING: Invalid status \"{found_json[\"status\"]}\". Must be one of: {valid_statuses}', file=sys.stderr)
    sys.exit(1)

# Validate optional but expected fields
if 'artifacts' not in found_json:
    print('INFO: JSON envelope missing optional field: artifacts', file=sys.stderr)

if 'next_ready' not in found_json:
    print('INFO: JSON envelope missing optional field: next_ready', file=sys.stderr)

print(f'OK: Valid JSON envelope with status=\"{found_json[\"status\"]}\"')
sys.exit(0)
" 2>&1
}

validate_envelope
