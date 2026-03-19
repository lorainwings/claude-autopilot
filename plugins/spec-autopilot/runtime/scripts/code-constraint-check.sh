#!/usr/bin/env bash
# ┌──────────────────────────────────────────────────────────────────┐
# │ DEPRECATED since v4.0                                            │
# │ Replaced by: post-task-validator.sh / _post_task_validator.py    │
# │ Planned removal: next major version                              │
# │ NOT registered in hooks.json — retained for compatibility        │
# └──────────────────────────────────────────────────────────────────┘
# code-constraint-check.sh
# Hook: PostToolUse(Task) — Phase 4/5/6 代码约束检查
# 检查生成的 artifacts 是否违反项目约束（禁止文件/模式/行数/目录范围）。
# 约束来源: autopilot.config.yaml code_constraints > CLAUDE.md 禁止项 > 无约束放行
# Output: PostToolUse decision: "block" on violation.

# --- Common preamble: stdin read, SCRIPT_DIR, _common.sh, Layer 0 bypass ---
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_hook_preamble.sh"

# --- Fast bypass Layer 1.5: background agent skip ---
is_background_agent && exit 0

# --- Fast bypass Layer 1: Phase 4/5/6 代码约束检查 ---
has_phase_marker "[456]" || exit 0

# --- Dependency check ---
command -v python3 &>/dev/null || exit 0

# --- Constraint detection via python3 (shared modules) ---
echo "$STDIN_DATA" | python3 -c "
import importlib.util, json, os, re, sys

# Import shared modules
_script_dir = os.environ.get('SCRIPT_DIR', '.')
_spec = importlib.util.spec_from_file_location('_ep', os.path.join(_script_dir, '_envelope_parser.py'))
_ep = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_ep)

_spec2 = importlib.util.spec_from_file_location('_cl', os.path.join(_script_dir, '_constraint_loader.py'))
_cl = importlib.util.module_from_spec(_spec2)
_spec2.loader.exec_module(_cl)

try:
    data = json.load(sys.stdin)
except (json.JSONDecodeError, ValueError):
    sys.exit(0)

prompt = data.get('tool_input', {}).get('prompt', '')
pm = re.search(r'autopilot-phase:(\d+)', prompt)
if not pm or int(pm.group(1)) not in (4, 5, 6):
    sys.exit(0)

output = _ep.normalize_tool_response(data)
if not output.strip():
    sys.exit(0)

envelope = _ep.extract_envelope(output)
if not envelope or envelope.get('status') not in ('ok', 'warning'):
    sys.exit(0)

artifacts = envelope.get('artifacts', [])
if not isinstance(artifacts, list) or not artifacts:
    sys.exit(0)

# Find project root
root = _ep.find_project_root(data)

# Load constraints
constraints = _cl.load_constraints(root)
if not constraints['found'] and not constraints['forbidden_files'] and not constraints['forbidden_patterns']:
    sys.exit(0)

# Check artifacts
violations = []
for art in artifacts:
    if not isinstance(art, str):
        continue
    violations.extend(_cl.check_file_violations(art, root, constraints))

if violations:
    shown = violations[:5]
    extra = f' (+{len(violations)-5} more)' if len(violations) > 5 else ''
    _ep.output_block(
        f'Code constraint violations ({len(violations)}): ' + '; '.join(shown) + extra + '. Fix before proceeding.'
    )

sys.exit(0)
"

exit 0
