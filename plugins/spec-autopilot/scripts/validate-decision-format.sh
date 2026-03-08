#!/usr/bin/env bash
# validate-decision-format.sh
# Hook: PostToolUse(Task) — Phase 1 决策格式验证
# Purpose: Validate that Phase 1 JSON envelope contains properly structured
#          DecisionPoint entries with options/pros/cons analysis.
#
# Detection: Only processes Task calls whose prompt contains
#            <!-- autopilot-phase:1 -->. All other Task calls exit 0 immediately.
#
# Complexity-aware:
#   - medium/large: Full DecisionPoint validation (options/pros/cons/recommended/choice/rationale)
#   - small: Relaxed validation (old format {point, choice} is acceptable)
#
# Output: Uses PostToolUse `decision: "block"` with `reason` to feed validation
#         errors back to Claude as actionable feedback. Exit is always 0.

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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
PROJECT_ROOT_QUICK=$(echo "$STDIN_DATA" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
if [ -z "$PROJECT_ROOT_QUICK" ]; then
  PROJECT_ROOT_QUICK="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
if ! has_active_autopilot "$PROJECT_ROOT_QUICK"; then
  exit 0
fi

# --- Fast bypass Layer 1: 仅 Phase 1 ---
echo "$STDIN_DATA" | grep -q '"prompt"[[:space:]]*:[[:space:]]*"<!-- autopilot-phase:1' || exit 0

# --- Dependency check ---
if ! command -v python3 &>/dev/null; then
  cat <<'BLOCK_JSON'
{
  "decision": "block",
  "reason": "python3 is required for decision format validation but not found in PATH. Install python3 to continue."
}
BLOCK_JSON
  exit 0
fi

# --- Fast bypass Layer 1.5: background agent skip ---
if echo "$STDIN_DATA" | grep -q '"run_in_background"[[:space:]]*:[[:space:]]*true'; then
  exit 0
fi

# --- Decision format validation via python3 ---
echo "$STDIN_DATA" | python3 -c "
import json
import re
import sys

try:
    data = json.load(sys.stdin)
except (json.JSONDecodeError, ValueError):
    sys.exit(0)

# 1) Check for Phase 1 marker
prompt = data.get('tool_input', {}).get('prompt', '')
if not re.search(r'autopilot-phase:1\b', prompt):
    sys.exit(0)

# 2) Extract tool_response
tool_response = data.get('tool_response', '')
if isinstance(tool_response, dict):
    output = json.dumps(tool_response)
elif isinstance(tool_response, str):
    output = tool_response
else:
    output = str(tool_response) if tool_response else ''

if not output.strip():
    sys.exit(0)

# 3) Find JSON envelope via raw_decode
envelope = None
decoder = json.JSONDecoder()
for i, ch in enumerate(output):
    if ch == '{':
        try:
            obj, _ = decoder.raw_decode(output, i)
            if isinstance(obj, dict) and 'status' in obj:
                envelope = obj
                break
        except (json.JSONDecodeError, ValueError):
            continue

if not envelope:
    sys.exit(0)

# Only validate ok/warning envelopes
if envelope.get('status') not in ('ok', 'warning'):
    sys.exit(0)

# 4) Check decisions array exists and is non-empty
decisions = envelope.get('decisions')
if not isinstance(decisions, list) or len(decisions) == 0:
    print(json.dumps({
        'decision': 'block',
        'reason': 'Phase 1 envelope missing or empty \"decisions\" array. '
                  'At least one DecisionPoint is required.'
    }))
    sys.exit(0)

# 5) Determine complexity from envelope or config
complexity = envelope.get('complexity', 'medium')
if complexity not in ('small', 'medium', 'large'):
    complexity = 'medium'

# 6) For small complexity: relaxed validation (old format acceptable)
if complexity == 'small':
    errors = []
    for idx, d in enumerate(decisions):
        if not isinstance(d, dict):
            errors.append(f'decisions[{idx}]: not an object')
            continue
        if not d.get('point') and not d.get('choice'):
            errors.append(f'decisions[{idx}]: missing both \"point\" and \"choice\"')
    if errors:
        print(json.dumps({
            'decision': 'block',
            'reason': f'Phase 1 decision format errors (small complexity): {'; '.join(errors)}'
        }))
    else:
        print(f'OK: Phase 1 decisions validated (small complexity, {len(decisions)} decisions)', file=sys.stderr)
    sys.exit(0)

# 7) For medium/large: full DecisionPoint validation
REQUIRED_OPTION_FIELDS = ['label', 'description', 'pros', 'cons']
errors = []

for idx, d in enumerate(decisions):
    prefix = f'decisions[{idx}]'
    if not isinstance(d, dict):
        errors.append(f'{prefix}: not an object')
        continue

    # Must have choice and rationale
    if not d.get('choice'):
        errors.append(f'{prefix}: missing \"choice\"')
    if not d.get('rationale'):
        errors.append(f'{prefix}: missing \"rationale\"')

    # Must have options array with >= 2 options
    options = d.get('options')
    if not isinstance(options, list):
        errors.append(f'{prefix}: missing \"options\" array')
        continue
    if len(options) < 2:
        errors.append(f'{prefix}: \"options\" must have >= 2 entries, got {len(options)}')
        continue

    # Validate each option
    has_recommended = False
    for oi, opt in enumerate(options):
        if not isinstance(opt, dict):
            errors.append(f'{prefix}.options[{oi}]: not an object')
            continue
        missing = [f for f in REQUIRED_OPTION_FIELDS if not opt.get(f)]
        if missing:
            errors.append(f'{prefix}.options[{oi}]: missing fields: {missing}')
        if opt.get('recommended') is True:
            has_recommended = True

    if not has_recommended:
        errors.append(f'{prefix}: no option marked \"recommended\": true')

if errors:
    shown = errors[:5]
    extra = f' (+{len(errors)-5} more)' if len(errors) > 5 else ''
    print(json.dumps({
        'decision': 'block',
        'reason': f'Phase 1 decision format violations ({len(errors)}, {complexity} complexity): '
                  + '; '.join(shown) + extra
                  + '. Each decision must have options (>=2) with label/description/pros/cons, '
                  + 'at least one recommended, plus choice and rationale.'
    }))
else:
    print(f'OK: Phase 1 decisions validated ({complexity} complexity, {len(decisions)} decisions)', file=sys.stderr)

sys.exit(0)
"

exit 0
