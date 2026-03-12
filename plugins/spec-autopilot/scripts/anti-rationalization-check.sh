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

# --- Common preamble: stdin read, SCRIPT_DIR, _common.sh, Layer 0 bypass ---
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_hook_preamble.sh"

# --- Fast bypass Layer 1: prompt 首行标记检测 ---
has_phase_marker || exit 0

# --- Fast bypass Layer 1.5: background agent skip ---
is_background_agent && exit 0

# --- Dependency check ---
if ! command -v python3 &>/dev/null; then
  # Cannot validate without python3 → allow (this is a secondary check)
  # Primary validation is done by validate-json-envelope.sh which blocks on missing python3
  exit 0
fi

# --- Pattern detection via python3 ---
echo "$STDIN_DATA" | python3 -c "
import json
import os
import re
import sys
import importlib.util

# Import shared envelope parser
_script_dir = os.environ.get('SCRIPT_DIR', '.')
_spec = importlib.util.spec_from_file_location('_ep', os.path.join(_script_dir, '_envelope_parser.py'))
_ep = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_ep)

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
if phase_num not in (4, 5, 6):
    sys.exit(0)

output = _ep.normalize_tool_response(data)
if not output.strip():
    sys.exit(0)

# Extract status from envelope
envelope = _ep.extract_envelope(output)
status = envelope.get('status') if envelope else None
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
    # Chinese rationalization patterns (中文合理化模式)
    # High confidence (weight=3)
    (3, r'(?:测试|任务|功能|用例)\s*(?:被|已)?(?:跳过|省略|忽略)'),
    (3, r'跳过了?|已跳过|被跳过'),
    (3, r'(?:延后|推迟|暂缓)(?:处理|实现|开发)?'),
    (3, r'后续(?:再|补充|处理|实现|完善)'),
    # Medium confidence (weight=2)
    (2, r'(?:超出|不在)(?:范围|scope)'),
    (2, r'(?:以后|后面|后续|下[一个]?(?:阶段|版本|迭代))(?:再|来|处理|实现)'),
    (2, r'(?:暂时|先)?不(?:做|处理|实现|考虑)'),
    # Low confidence (weight=1)
    (1, r'已[经被]?(?:覆盖|测试|处理|实现|验证)'),
    (1, r'(?:不|无)(?:需要|必要|需|必须)'),
    (1, r'(?:太|过于)(?:复杂|困难|耗时)'),
    (1, r'(?:影响|优先级|风险)\s*(?:较?低|不大|很小)'),
]

output_lower = output.lower()
total_score = 0
found_patterns = []
for weight, pattern in WEIGHTED_PATTERNS:
    if re.search(pattern, output_lower):
        total_score += weight
        found_patterns.append((weight, pattern))

_sep = chr(44) + chr(32)

# Extract artifacts from envelope to check for actual output
has_artifacts = False
if envelope:
    arts = envelope.get('artifacts', [])
    has_artifacts = isinstance(arts, list) and len(arts) > 0

# Scoring thresholds:
#   total_score >= 5          → hard block
#   total_score >= 3 + no artifacts → block (suspicious + no output)
#   total_score >= 2          → stderr warning only (no block)
#   total_score < 2           → pass silently
if total_score >= 5:
    print(json.dumps({
        'decision': 'block',
        'reason': f'Anti-rationalization check: Phase {phase_num} output scored {total_score} (threshold 5). Multiple strong skip/rationalization patterns detected. Review and re-dispatch. Patterns: {_sep.join(p for _, p in found_patterns[:3])}'
    }))
    sys.exit(0)

if total_score >= 3 and not has_artifacts:
    print(json.dumps({
        'decision': 'block',
        'reason': f'Anti-rationalization check: Phase {phase_num} output scored {total_score} with no artifacts produced. Suspected rationalization without deliverables. Review and re-dispatch. Patterns: {_sep.join(p for _, p in found_patterns[:3])}'
    }))
    sys.exit(0)

if total_score >= 2:
    print(json.dumps({
        'decision': 'warn',
        'reason': f'Anti-rationalization advisory: Phase {phase_num} output scored {total_score} but has artifacts. Patterns: {_sep.join(p for _, p in found_patterns[:3])}'
    }), file=sys.stderr)
    sys.exit(0)

# Score below threshold → allow
sys.exit(0)
"

exit 0
