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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# --- Try python3 validation via shared module ---
if command -v python3 &>/dev/null; then
  python3 "$SCRIPT_DIR/_config_validator.py" "$CONFIG_FILE"
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
for nested_key in "phases.requirements.agent:agent" "phases.testing.agent:agent" "phases.implementation.serial_task.max_retries_per_task:max_retries_per_task"; do
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
