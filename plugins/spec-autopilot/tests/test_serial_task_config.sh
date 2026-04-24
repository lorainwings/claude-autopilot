#!/usr/bin/env bash
# test_serial_task_config.sh — Section 42: Serial task config validation
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 42. Serial task config validation ---"
setup_autopilot_fixture

SERIAL_TEST_DIR=$(mktemp -d)

# 42a. Config with serial_task.max_retries_per_task → valid=true
mkdir -p "$SERIAL_TEST_DIR/valid/.claude"
cat >"$SERIAL_TEST_DIR/valid/.claude/autopilot.config.yaml" <<'YAML'
version: "1.2"
services:
  backend:
    health_url: "http://localhost:8080/health"
phases:
  requirements:
    agent: "general-purpose"
  testing:
    agent: "general-purpose"
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
YAML

output=$(bash "$SCRIPT_DIR/validate-config.sh" "$SERIAL_TEST_DIR/valid" 2>/dev/null)
valid=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('valid',''))" 2>/dev/null || echo "")
if [ "$valid" = "True" ] || [ "$valid" = "true" ]; then
  green "  PASS: config with serial_task.max_retries_per_task → valid"
  PASS=$((PASS + 1))
else
  red "  FAIL: config with serial_task.max_retries_per_task rejected (valid='$valid', output='$output')"
  FAIL=$((FAIL + 1))
fi

# 42b. Config missing serial_task.max_retries_per_task → missing_keys
mkdir -p "$SERIAL_TEST_DIR/missing/.claude"
cat >"$SERIAL_TEST_DIR/missing/.claude/autopilot.config.yaml" <<'YAML'
version: "1.2"
services:
  backend:
    health_url: "http://localhost:8080/health"
phases:
  requirements:
    agent: "general-purpose"
  testing:
    agent: "general-purpose"
    gate:
      min_test_count_per_type: 5
      required_test_types: [unit, api, e2e, ui]
  implementation:
    parallel:
      enabled: false
  reporting:
    coverage_target: 80
    zero_skip_required: true
test_suites:
  unit:
    command: "npm test"
test_pyramid:
  min_unit_pct: 50
YAML

output=$(bash "$SCRIPT_DIR/validate-config.sh" "$SERIAL_TEST_DIR/missing" 2>/dev/null)
missing=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('missing_keys',[]))" 2>/dev/null || echo "[]")
assert_contains "missing serial_task → reported in missing_keys" "$missing" "serial_task.max_retries_per_task"

# 42c. max_retries_per_task out of range (too high) → range_errors (requires PyYAML)
HAS_PYYAML=$(python3 -c "import yaml; print('yes')" 2>/dev/null || echo "no")
if [ "$HAS_PYYAML" = "yes" ]; then
  mkdir -p "$SERIAL_TEST_DIR/range/.claude"
  cat >"$SERIAL_TEST_DIR/range/.claude/autopilot.config.yaml" <<'YAML'
version: "1.2"
services:
  backend:
    health_url: "http://localhost:8080/health"
phases:
  requirements:
    agent: "general-purpose"
  testing:
    agent: "general-purpose"
    gate:
      min_test_count_per_type: 5
      required_test_types: [unit, api, e2e, ui]
  implementation:
    serial_task:
      max_retries_per_task: 50
  reporting:
    coverage_target: 80
    zero_skip_required: true
test_suites:
  unit:
    command: "npm test"
test_pyramid:
  min_unit_pct: 50
YAML

  output=$(bash "$SCRIPT_DIR/validate-config.sh" "$SERIAL_TEST_DIR/range" 2>/dev/null)
  range_err=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('range_errors',[]))" 2>/dev/null || echo "[]")
  assert_contains "max_retries_per_task=50 → range error" "$range_err" "max_retries_per_task"

  # 42d. max_retries_per_task=0 (below min) → range_errors
  mkdir -p "$SERIAL_TEST_DIR/range_low/.claude"
  cat >"$SERIAL_TEST_DIR/range_low/.claude/autopilot.config.yaml" <<'YAML'
version: "1.2"
services:
  backend:
    health_url: "http://localhost:8080/health"
phases:
  requirements:
    agent: "general-purpose"
  testing:
    agent: "general-purpose"
    gate:
      min_test_count_per_type: 5
      required_test_types: [unit, api, e2e, ui]
  implementation:
    serial_task:
      max_retries_per_task: 0
  reporting:
    coverage_target: 80
    zero_skip_required: true
test_suites:
  unit:
    command: "npm test"
test_pyramid:
  min_unit_pct: 50
YAML

  output=$(bash "$SCRIPT_DIR/validate-config.sh" "$SERIAL_TEST_DIR/range_low" 2>/dev/null)
  range_err=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('range_errors',[]))" 2>/dev/null || echo "[]")
  assert_contains "max_retries_per_task=0 → range error" "$range_err" "max_retries_per_task"
else
  green "  SKIP: range validation requires PyYAML (not installed)"
  PASS=$((PASS + 2))
fi

# 42e. max_retries_per_task=3 (valid) → no range error
output=$(bash "$SCRIPT_DIR/validate-config.sh" "$SERIAL_TEST_DIR/valid" 2>/dev/null)
range_err=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('range_errors',[]))" 2>/dev/null || echo "[]")
assert_not_contains "max_retries_per_task=3 → no range error" "$range_err" "max_retries_per_task"

# 42f. Config with old ralph_loop keys → should report missing serial_task
mkdir -p "$SERIAL_TEST_DIR/old_config/.claude"
cat >"$SERIAL_TEST_DIR/old_config/.claude/autopilot.config.yaml" <<'YAML'
version: "1.0"
services:
  backend:
    health_url: "http://localhost:8080/health"
phases:
  requirements:
    agent: "general-purpose"
  testing:
    agent: "general-purpose"
    gate:
      min_test_count_per_type: 5
      required_test_types: [unit, api, e2e, ui]
  implementation:
    ralph_loop:
      enabled: true
      max_iterations: 20
      fallback_enabled: true
  reporting:
    coverage_target: 80
    zero_skip_required: true
test_suites:
  unit:
    command: "npm test"
test_pyramid:
  min_unit_pct: 50
YAML

output=$(bash "$SCRIPT_DIR/validate-config.sh" "$SERIAL_TEST_DIR/old_config" 2>/dev/null)
valid=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('valid',''))" 2>/dev/null || echo "")
if [ "$valid" = "False" ] || [ "$valid" = "false" ]; then
  green "  PASS: old ralph_loop config → valid=false (migration needed)"
  PASS=$((PASS + 1))
else
  red "  FAIL: old ralph_loop config accepted as valid (should require serial_task)"
  FAIL=$((FAIL + 1))
fi
missing=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('missing_keys',[]))" 2>/dev/null || echo "[]")
assert_contains "old config → missing serial_task key" "$missing" "serial_task"

rm -rf "$SERIAL_TEST_DIR"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
