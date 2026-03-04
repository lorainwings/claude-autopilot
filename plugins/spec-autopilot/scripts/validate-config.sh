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
  echo "{\"valid\":${valid},\"missing_keys\":${missing_json},\"warnings\":${warnings_json}}"
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
recommended = ['test_pyramid', 'gates', 'context_management']
for key in recommended:
    if not check_key(yaml_data, key):
        warnings.append(f'Recommended key \"{key}\" not found')

valid = len(missing) == 0
print(json.dumps({'valid': valid, 'missing_keys': missing, 'warnings': warnings}))
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
