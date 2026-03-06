#!/usr/bin/env bash
# validate-config.sh
# Validates .claude/autopilot.config.yaml for required fields.
# Called from autopilot SKILL.md Phase 0.
#
# Usage: bash validate-config.sh [project_root]
# Output: JSON on stdout: {"valid": true/false, "missing_keys": [...], "warnings": [...]}

set -uo pipefail

PROJECT_ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
CONFIG_FILE="$PROJECT_ROOT/.claude/autopilot.config.yaml"

# --- Output JSON result ---
output_result() {
  local valid="$1"
  local missing_json="$2"
  local warnings_json="$3"
  local type_errors="${4:-[]}"
  local range_errors="${5:-[]}"
  local cross_ref="${6:-[]}"
  echo "{\"valid\":${valid},\"missing_keys\":${missing_json},\"type_errors\":${type_errors},\"range_errors\":${range_errors},\"cross_ref_warnings\":${cross_ref},\"warnings\":${warnings_json}}"
}

# --- Check file exists ---
if [ ! -f "$CONFIG_FILE" ]; then
  output_result "false" "[\"file_not_found\"]" "[\"Config file not found: $CONFIG_FILE\"]"
  exit 0
fi

# --- Try python3 YAML parsing first ---
if command -v python3 &>/dev/null; then
  python3 -c "
import sys, json

config_path = sys.argv[1]
missing = []
warnings = []

# Try PyYAML first, fallback to basic parsing
yaml_data = None
try:
    import yaml
    with open(config_path) as f:
        yaml_data = yaml.safe_load(f)
except ImportError:
    warnings.append('PyYAML not installed, using basic parser')
except Exception as e:
    print(json.dumps({'valid': False, 'missing_keys': [f'yaml_parse_error: {e}'], 'warnings': []}))
    sys.exit(0)

if yaml_data is None:
    # Basic YAML parser using regex - reads key: value pairs
    import re
    yaml_data = {}
    try:
        with open(config_path) as f:
            content = f.read()
        # Extract top-level keys
        for m in re.finditer(r'^(\w[\w_]*):', content, re.MULTILINE):
            yaml_data[m.group(1)] = True
        # Extract nested keys (indented)
        lines = content.split('\n')
        path = []
        indent_stack = [-1]
        for line in lines:
            stripped = line.lstrip()
            if not stripped or stripped.startswith('#'):
                continue
            indent = len(line) - len(stripped)
            key_match = re.match(r'([\w][\w_.]*):\s*(.*)', stripped)
            if key_match:
                key = key_match.group(1)
                while indent_stack and indent <= indent_stack[-1]:
                    indent_stack.pop()
                    if path:
                        path.pop()
                path.append(key)
                indent_stack.append(indent)
                full_key = '.'.join(path)
                yaml_data[full_key] = key_match.group(2).strip() or True
    except Exception as e:
        print(json.dumps({'valid': False, 'missing_keys': [f'parse_error: {e}'], 'warnings': warnings}))
        sys.exit(0)

# --- Required top-level keys ---
required_top = ['version', 'services', 'phases', 'test_suites']
# --- Required nested keys ---
required_nested = [
    'phases.requirements.agent',
    'phases.testing.agent',
    'phases.testing.gate.min_test_count_per_type',
    'phases.testing.gate.required_test_types',
    'phases.implementation.ralph_loop.enabled',
    'phases.implementation.ralph_loop.max_iterations',
    'phases.implementation.ralph_loop.fallback_enabled',
    'phases.reporting.coverage_target',
    'phases.reporting.zero_skip_required',
]

def check_key(data, key_path):
    \"\"\"Check if a key exists in nested dict or flat key dict.\"\"\"
    # Try nested dict access
    if isinstance(data, dict):
        parts = key_path.split('.')
        current = data
        for part in parts:
            if isinstance(current, dict) and part in current:
                current = current[part]
            else:
                # Try flat key
                return key_path in data
        return True
    return False

for key in required_top:
    if not check_key(yaml_data, key):
        missing.append(key)

for key in required_nested:
    if not check_key(yaml_data, key):
        missing.append(key)

# --- Warnings for recommended fields ---
recommended = ['test_pyramid', 'gates', 'context_management', 'project_context']
for key in recommended:
    if not check_key(yaml_data, key):
        warnings.append(f'Recommended key \"{key}\" not found')

# --- 类型验证 ---
def get_value(data, key_path):
    \"\"\"从嵌套 dict 中获取值，不存在返回 None。\"\"\"
    if not isinstance(data, dict):
        return None
    parts = key_path.split('.')
    current = data
    for part in parts:
        if isinstance(current, dict) and part in current:
            current = current[part]
        else:
            return None
    return current

TYPE_RULES = {
    'version': str,
    'phases.requirements.min_qa_rounds': (int, float),
    'phases.requirements.auto_scan.enabled': bool,
    'phases.requirements.auto_scan.max_depth': (int, float),
    'phases.requirements.research.enabled': bool,
    'phases.requirements.research.agent': str,
    'phases.requirements.complexity_routing.enabled': bool,
    'phases.requirements.complexity_routing.thresholds.small': (int, float),
    'phases.requirements.complexity_routing.thresholds.medium': (int, float),
    'project_context.test_credentials.username': str,
    'project_context.test_credentials.password': str,
    'project_context.test_credentials.login_endpoint': str,
    'project_context.project_structure.backend_dir': str,
    'project_context.project_structure.frontend_dir': str,
    'phases.testing.gate.min_test_count_per_type': (int, float),
    'phases.implementation.ralph_loop.enabled': bool,
    'phases.implementation.ralph_loop.max_iterations': (int, float),
    'phases.implementation.ralph_loop.fallback_enabled': bool,
    'phases.reporting.coverage_target': (int, float),
    'phases.reporting.zero_skip_required': bool,
    'test_pyramid.min_unit_pct': (int, float),
    'test_pyramid.max_e2e_pct': (int, float),
    'test_pyramid.min_total_cases': (int, float),
    'phases.code_review.enabled': bool,
    'phases.implementation.parallel.enabled': bool,
    'phases.implementation.parallel.max_agents': (int, float),
}

type_errors = []
for key_path, expected_type in TYPE_RULES.items():
    val = get_value(yaml_data, key_path)
    if val is None:
        continue  # key 不存在，跳过类型检查（由 missing_keys 处理）
    if not isinstance(val, expected_type):
        if isinstance(expected_type, tuple):
            type_name = '|'.join(t.__name__ for t in expected_type)
        else:
            type_name = expected_type.__name__
        type_errors.append(f'{key_path}: expected {type_name}, got {type(val).__name__}')

# --- 范围验证 ---
RANGE_RULES = {
    'phases.testing.gate.min_test_count_per_type': (1, 100),
    'phases.implementation.ralph_loop.max_iterations': (1, 200),
    'phases.reporting.coverage_target': (0, 100),
    'test_pyramid.min_unit_pct': (0, 100),
    'test_pyramid.max_e2e_pct': (0, 100),
    'test_pyramid.min_total_cases': (1, 1000),
    'phases.implementation.parallel.max_agents': (1, 20),
    'async_quality_scans.timeout_minutes': (1, 120),
    'phases.requirements.auto_scan.max_depth': (1, 5),
    'phases.requirements.complexity_routing.thresholds.small': (1, 20),
    'phases.requirements.complexity_routing.thresholds.medium': (2, 50),
}

range_errors = []
for key_path, (min_val, max_val) in RANGE_RULES.items():
    val = get_value(yaml_data, key_path)
    if val is not None and isinstance(val, (int, float)):
        if val < min_val or val > max_val:
            range_errors.append(f'{key_path}: value {val} out of range [{min_val}, {max_val}]')

# --- 交叉引用验证 ---
cross_ref_warnings = []

# test_pyramid 总和检查
min_unit = get_value(yaml_data, 'test_pyramid.min_unit_pct')
max_e2e = get_value(yaml_data, 'test_pyramid.max_e2e_pct')
if min_unit is not None and max_e2e is not None:
    if isinstance(min_unit, (int, float)) and isinstance(max_e2e, (int, float)):
        if min_unit + max_e2e > 100:
            cross_ref_warnings.append('test_pyramid: min_unit_pct + max_e2e_pct > 100%, impossible distribution')

# ralph_loop enabled 但 max_iterations < 1
rl_enabled = get_value(yaml_data, 'phases.implementation.ralph_loop.enabled')
rl_max = get_value(yaml_data, 'phases.implementation.ralph_loop.max_iterations')
if rl_enabled and rl_max is not None and isinstance(rl_max, (int, float)) and rl_max < 1:
    cross_ref_warnings.append('ralph_loop.enabled=true but max_iterations<1, effectively disabled')

# parallel 启用但 max_agents < 2
par_enabled = get_value(yaml_data, 'phases.implementation.parallel.enabled')
par_max = get_value(yaml_data, 'phases.implementation.parallel.max_agents')
if par_enabled and par_max is not None and isinstance(par_max, (int, float)) and par_max < 2:
    cross_ref_warnings.append('parallel.enabled=true but max_agents<2, no parallelism benefit')

# coverage_target 为 0 但 zero_skip_required 为 true（可能是误配置）
cov_target = get_value(yaml_data, 'phases.reporting.coverage_target')
zero_skip = get_value(yaml_data, 'phases.reporting.zero_skip_required')
if cov_target is not None and zero_skip is not None:
    if isinstance(cov_target, (int, float)) and cov_target == 0 and zero_skip:
        cross_ref_warnings.append('coverage_target=0 but zero_skip_required=true, may be misconfigured')

# complexity_routing thresholds 一致性
cr_small = get_value(yaml_data, 'phases.requirements.complexity_routing.thresholds.small')
cr_medium = get_value(yaml_data, 'phases.requirements.complexity_routing.thresholds.medium')
if cr_small is not None and cr_medium is not None:
    if isinstance(cr_small, (int, float)) and isinstance(cr_medium, (int, float)):
        if cr_small >= cr_medium:
            cross_ref_warnings.append('complexity_routing: thresholds.small >= thresholds.medium, routing ineffective')

valid = len(missing) == 0 and len(type_errors) == 0
print(json.dumps({
    'valid': valid,
    'missing_keys': missing,
    'type_errors': type_errors,
    'range_errors': range_errors,
    'cross_ref_warnings': cross_ref_warnings,
    'warnings': warnings
}))
" "$CONFIG_FILE"
  exit 0
fi

# --- Fallback: pure bash/grep validation ---
# Check for required top-level keys using grep
MISSING_KEYS="["
WARNINGS="[]"
first=true

for key in version services phases test_suites; do
  if ! grep -q "^${key}:" "$CONFIG_FILE" 2>/dev/null; then
    if [ "$first" = "true" ]; then
      MISSING_KEYS="${MISSING_KEYS}\"${key}\""
      first=false
    else
      MISSING_KEYS="${MISSING_KEYS},\"${key}\""
    fi
  fi
done

# Check nested keys with indentation-aware grep
for nested_key in "phases.requirements.agent:agent" "phases.testing.agent:agent" "phases.implementation.ralph_loop.enabled:enabled"; do
  leaf="${nested_key#*:}"
  if ! grep -q "^[[:space:]]*${leaf}:" "$CONFIG_FILE" 2>/dev/null; then
    full="${nested_key%:*}"
    if [ "$first" = "true" ]; then
      MISSING_KEYS="${MISSING_KEYS}\"${full}\""
      first=false
    else
      MISSING_KEYS="${MISSING_KEYS},\"${full}\""
    fi
  fi
done

MISSING_KEYS="${MISSING_KEYS}]"

if [ "$MISSING_KEYS" = "[]" ]; then
  output_result "true" "[]" "$WARNINGS"
else
  output_result "false" "$MISSING_KEYS" "[\"bash fallback mode - validation is approximate\"]"
fi

exit 0
