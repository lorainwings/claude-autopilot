#!/usr/bin/env bash
# test_validate_config.sh — Section 21: validate-config.sh
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 21. validate-config.sh tests ---"
setup_autopilot_fixture

CONFIG_TEST_DIR=$(mktemp -d)

# 21a. Valid config → valid=true
mkdir -p "$CONFIG_TEST_DIR/valid/.claude"
cat > "$CONFIG_TEST_DIR/valid/.claude/autopilot.config.yaml" << 'YAML'
version: "1.0"
services:
  backend:
    health_url: "http://localhost:8080/health"
phases:
  requirements:
    agent: "business-analyst"
  testing:
    agent: "qa-expert"
    gate:
      min_test_count_per_type: 5
      required_test_types: [unit, api, e2e, ui]
  implementation:
    serial_task:
      max_retries_per_task: 3
  reporting:
    coverage_target: 80
    zero_skip_required: true
test_suites:
  unit:
    command: "npm test"
test_pyramid:
  min_unit_pct: 50
gates:
  user_confirmation:
    after_phase_1: true
context_management:
  git_commit_per_phase: true
YAML

output=$(bash "$SCRIPT_DIR/validate-config.sh" "$CONFIG_TEST_DIR/valid" 2>/dev/null)
valid=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('valid',''))" 2>/dev/null || echo "")
if [ "$valid" = "True" ] || [ "$valid" = "true" ]; then
  green "  PASS: validate-config valid config → valid=true"
  PASS=$((PASS + 1))
else
  red "  FAIL: validate-config valid config (got valid='$valid', output='$output')"
  FAIL=$((FAIL + 1))
fi

# 21b. Missing fields → valid=false with missing_keys
mkdir -p "$CONFIG_TEST_DIR/partial/.claude"
cat > "$CONFIG_TEST_DIR/partial/.claude/autopilot.config.yaml" << 'YAML'
version: "1.0"
phases:
  requirements:
    agent: "business-analyst"
YAML

output=$(bash "$SCRIPT_DIR/validate-config.sh" "$CONFIG_TEST_DIR/partial" 2>/dev/null)
valid=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('valid',''))" 2>/dev/null || echo "")
if [ "$valid" = "False" ] || [ "$valid" = "false" ]; then
  green "  PASS: validate-config partial config → valid=false"
  PASS=$((PASS + 1))
else
  red "  FAIL: validate-config partial config (got valid='$valid', output='$output')"
  FAIL=$((FAIL + 1))
fi

# 21c. Missing_keys contains expected entries
missing=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('missing_keys',[]))" 2>/dev/null || echo "[]")
assert_contains "validate-config missing keys include services" "$missing" "services"

# 21d. No config file → valid=false, missing=file_not_found
output=$(bash "$SCRIPT_DIR/validate-config.sh" "$CONFIG_TEST_DIR/nonexistent" 2>/dev/null)
assert_contains "validate-config no file → file_not_found" "$output" "file_not_found"

rm -rf "$CONFIG_TEST_DIR"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0
