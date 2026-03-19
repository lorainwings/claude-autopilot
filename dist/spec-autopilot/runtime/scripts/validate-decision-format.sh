#!/usr/bin/env bash
# DEPRECATED: Core logic merged into post-task-validator.sh / _post_task_validator.py (v4.0). This file is retained for reference only and is NOT registered in hooks.json.
# validate-decision-format.sh
# Hook: PostToolUse(Task) — Phase 1 决策格式验证
# Purpose: Validate that Phase 1 JSON envelope contains properly structured
#          DecisionPoint entries with options/pros/cons analysis.
#
# Detection: Only processes Task calls whose prompt contains
#            <!-- autopilot-phase:1 -->. All other Task calls exit 0 immediately.
#
# NOTE (by design): Phase 1 的 research/business-analyst Task 不含 autopilot-phase
#   标记（见 autopilot-dispatch SKILL.md），因此该 Hook 仅在主线程直接使用含
#   Phase 1 标记的 Task 时触发。当前设计下 Phase 1 走主线程交互模式，
#   决策格式由主线程自身保证。此 Hook 作为额外防线存在。
#
# Complexity-aware:
#   - medium/large: Full DecisionPoint validation (options/pros/cons/recommended/choice/rationale)
#   - small: Relaxed validation (old format {point, choice} is acceptable)
#
# Output: Uses PostToolUse `decision: "block"` with `reason` to feed validation
#         errors back to Claude as actionable feedback. Exit is always 0.

# --- Common preamble: stdin read, SCRIPT_DIR, _common.sh, Layer 0 bypass ---
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_hook_preamble.sh"

# --- Fast bypass Layer 1: 仅 Phase 1 ---
has_phase_marker "1" || exit 0

# --- Dependency check ---
if ! require_python3; then
  exit 0
fi

# --- Fast bypass Layer 1.5: background agent skip ---
is_background_agent && exit 0

# --- Decision format validation via python3 ---
echo "$STDIN_DATA" | python3 -c "
import importlib.util
import json
import re
import sys
import os

# Import shared envelope parser
_script_dir = os.environ.get('SCRIPT_DIR', '.')
_spec = importlib.util.spec_from_file_location('_ep', os.path.join(_script_dir, '_envelope_parser.py'))
_ep = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_ep)

try:
    data = json.load(sys.stdin)
except (json.JSONDecodeError, ValueError):
    sys.exit(0)

# 1) Check for Phase 1 marker
prompt = data.get('tool_input', {}).get('prompt', '')
if not re.search(r'autopilot-phase:1\b', prompt):
    sys.exit(0)

# 2) Extract tool_response and envelope using shared module
output = _ep.normalize_tool_response(data)
if not output.strip():
    sys.exit(0)

envelope = _ep.extract_envelope(output)
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
