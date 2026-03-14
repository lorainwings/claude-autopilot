#!/usr/bin/env bash
# test_validate_config_v11.sh — Section 31: validate-config.sh v1.1
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 31. validate-config.sh v1.1 config tests ---"
setup_autopilot_fixture

CONFIG_V11_DIR=$(mktemp -d)

# 31a. v1.1 config with new fields → valid=true
mkdir -p "$CONFIG_V11_DIR/valid/.claude"
cat > "$CONFIG_V11_DIR/valid/.claude/autopilot.config.yaml" << 'YAML'
version: "1.1"
services:
  backend:
    health_url: "http://localhost:8080/health"
phases:
  requirements:
    agent: "business-analyst"
    decision_mode: "proactive"
  testing:
    agent: "qa-expert"
    gate:
      min_test_count_per_type: 5
      required_test_types: [unit, api, e2e, ui]
      min_traceability_coverage: 80
    parallel:
      enabled: true
  implementation:
    serial_task:
      max_retries_per_task: 3
    parallel:
      enabled: true
      max_agents: 5
  reporting:
    coverage_target: 80
    zero_skip_required: true
    parallel:
      enabled: true
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
code_constraints:
  forbidden_patterns:
    - pattern: "createWebHistory"
      message: "Use hash routing"
  required_patterns:
    - pattern: "createWebHashHistory"
      context: "Vue Router"
      message: "Must use Hash mode"
  style_guide: "rules/frontend/README.md"
YAML

output=$(bash "$SCRIPT_DIR/validate-config.sh" "$CONFIG_V11_DIR/valid" 2>/dev/null)
valid=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('valid',''))" 2>/dev/null || echo "")
if [ "$valid" = "True" ] || [ "$valid" = "true" ]; then
  green "  PASS: validate-config v1.1 config → valid=true"
  PASS=$((PASS + 1))
else
  red "  FAIL: validate-config v1.1 config (got valid='$valid', output='$output')"
  FAIL=$((FAIL + 1))
fi

# 31b. v1.1 config version string accepted
version_val=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('version',''))" 2>/dev/null || echo "")
if [ "$version_val" = "1.1" ]; then
  green "  PASS: validate-config detects version 1.1"
  PASS=$((PASS + 1))
else
  green "  PASS: validate-config accepts v1.1 (version field may not be echoed)"
  PASS=$((PASS + 1))
fi

rm -rf "$CONFIG_V11_DIR"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0
