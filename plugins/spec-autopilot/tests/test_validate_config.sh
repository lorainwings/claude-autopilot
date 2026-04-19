#!/usr/bin/env bash
# test_validate_config.sh — Section 21: validate-config.sh
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
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
    agent: "general-purpose"
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

# === Enum validation tests ===

# 21e. Invalid default_mode enum → enum_errors non-empty
mkdir -p "$CONFIG_TEST_DIR/bad_enum/.claude"
cat > "$CONFIG_TEST_DIR/bad_enum/.claude/autopilot.config.yaml" << 'YAML'
version: "1.0"
default_mode: "turbo"
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
YAML

output=$(bash "$SCRIPT_DIR/validate-config.sh" "$CONFIG_TEST_DIR/bad_enum" 2>/dev/null)
valid=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('valid',''))" 2>/dev/null || echo "")
if [ "$valid" = "False" ] || [ "$valid" = "false" ]; then
  green "  PASS: 21e. invalid enum value → valid=false"
  PASS=$((PASS + 1))
else
  red "  FAIL: 21e. invalid enum value (got valid='$valid', output='$output')"
  FAIL=$((FAIL + 1))
fi
assert_contains "21e. enum_errors mentions turbo" "$output" "turbo"

# 21f. Valid default_mode enum → no enum_errors
mkdir -p "$CONFIG_TEST_DIR/good_enum/.claude"
cat > "$CONFIG_TEST_DIR/good_enum/.claude/autopilot.config.yaml" << 'YAML'
version: "1.0"
default_mode: "lite"
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
YAML

output=$(bash "$SCRIPT_DIR/validate-config.sh" "$CONFIG_TEST_DIR/good_enum" 2>/dev/null)
enum_errors=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('enum_errors',[]))" 2>/dev/null || echo "[]")
if [ "$enum_errors" = "[]" ]; then
  green "  PASS: 21f. valid enum value → no enum_errors"
  PASS=$((PASS + 1))
else
  red "  FAIL: 21f. valid enum value (enum_errors='$enum_errors')"
  FAIL=$((FAIL + 1))
fi

rm -rf "$CONFIG_TEST_DIR"

# === Cross-reference validation tests ===

XREF_TEST_DIR=$(mktemp -d)

# 21g. required_test_types without matching test_suites → cross_ref_warning
mkdir -p "$XREF_TEST_DIR/type_mismatch/.claude"
cat > "$XREF_TEST_DIR/type_mismatch/.claude/autopilot.config.yaml" << 'YAML'
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
      required_test_types: [unit, api, e2e, visual]
  implementation:
    serial_task:
      max_retries_per_task: 3
  reporting:
    coverage_target: 80
    zero_skip_required: true
test_suites:
  unit:
    command: "npm test"
  api:
    command: "npm run test:api"
YAML

output=$(bash "$SCRIPT_DIR/validate-config.sh" "$XREF_TEST_DIR/type_mismatch" 2>/dev/null)
assert_contains "21g. required_test_types mismatch warns about visual" "$output" "visual"

# 21h. domain_agents with parallel.enabled=false → warning
mkdir -p "$XREF_TEST_DIR/domain_no_par/.claude"
cat > "$XREF_TEST_DIR/domain_no_par/.claude/autopilot.config.yaml" << 'YAML'
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
      required_test_types: [unit]
  implementation:
    serial_task:
      max_retries_per_task: 3
    parallel:
      enabled: false
      domain_agents:
        frontend:
          agent: "ui-expert"
  reporting:
    coverage_target: 80
    zero_skip_required: true
test_suites:
  unit:
    command: "npm test"
YAML

output=$(bash "$SCRIPT_DIR/validate-config.sh" "$XREF_TEST_DIR/domain_no_par" 2>/dev/null)
assert_contains "21h. domain_agents+parallel.enabled=false" "$output" "domain_agents"

# 21h2. domain_agents with quoted slash keys (real schema format) → per-domain warnings
mkdir -p "$XREF_TEST_DIR/domain_slash/.claude"
cat > "$XREF_TEST_DIR/domain_slash/.claude/autopilot.config.yaml" << 'YAML'
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
      required_test_types: [unit]
  implementation:
    serial_task:
      max_retries_per_task: 3
    parallel:
      enabled: true
      default_agent: "custom-fallback"
      domain_agents:
        "backend/":
          agent: "java-architect"
        "frontend/":
          agent: "react-specialist"
  reporting:
    coverage_target: 80
    zero_skip_required: true
test_suites:
  unit:
    command: "npm test"
YAML

output=$(bash "$SCRIPT_DIR/validate-config.sh" "$XREF_TEST_DIR/domain_slash" 2>/dev/null)
assert_contains "21h2a. quoted slash key backend/ agent warned" "$output" "java-architect"
assert_contains "21h2b. quoted slash key frontend/ agent warned" "$output" "react-specialist"
assert_contains "21h2c. default_agent also warned" "$output" "custom-fallback"

# 21h3. inline mapping format (schema multi-stack example) → per-domain warnings
mkdir -p "$XREF_TEST_DIR/domain_inline/.claude"
cat > "$XREF_TEST_DIR/domain_inline/.claude/autopilot.config.yaml" << 'YAML'
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
      required_test_types: [unit]
  implementation:
    serial_task:
      max_retries_per_task: 3
    parallel:
      enabled: true
      default_agent: "general-purpose"
      domain_agents:
        "services/auth/":           { agent: "java-architect" }
        "apps/web/":               { agent: "react-specialist" }
  reporting:
    coverage_target: 80
    zero_skip_required: true
test_suites:
  unit:
    command: "npm test"
YAML

output=$(bash "$SCRIPT_DIR/validate-config.sh" "$XREF_TEST_DIR/domain_inline" 2>/dev/null)
assert_contains "21h3a. inline mapping services/auth/ agent warned" "$output" "java-architect"
assert_contains "21h3b. inline mapping apps/web/ agent warned" "$output" "react-specialist"

# 21i. tdd_mode=true with empty test_suites → warning
mkdir -p "$XREF_TEST_DIR/tdd_no_suites/.claude"
cat > "$XREF_TEST_DIR/tdd_no_suites/.claude/autopilot.config.yaml" << 'YAML'
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
      required_test_types: [unit]
  implementation:
    serial_task:
      max_retries_per_task: 3
    tdd_mode: true
  reporting:
    coverage_target: 80
    zero_skip_required: true
test_suites: {}
YAML

output=$(bash "$SCRIPT_DIR/validate-config.sh" "$XREF_TEST_DIR/tdd_no_suites" 2>/dev/null)
assert_contains "21i. tdd_mode with empty test_suites" "$output" "tdd_mode"

# 21j. hook_floors.min_change_coverage_pct > coverage_target → warning
mkdir -p "$XREF_TEST_DIR/floor_cov/.claude"
cat > "$XREF_TEST_DIR/floor_cov/.claude/autopilot.config.yaml" << 'YAML'
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
      required_test_types: [unit]
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
  min_unit_pct: 30
  hook_floors:
    min_change_coverage_pct: 95
YAML

output=$(bash "$SCRIPT_DIR/validate-config.sh" "$XREF_TEST_DIR/floor_cov" 2>/dev/null)
assert_contains "21j. hook_floors coverage > gate coverage" "$output" "min_change_coverage_pct"

# 21k. research.agent="Explore" → HARD BLOCK (valid=false, enum_errors)
# P1 fail-closed: Explore agents are read-only and cannot write research files
mkdir -p "$XREF_TEST_DIR/explore_deprecated/.claude"
cat > "$XREF_TEST_DIR/explore_deprecated/.claude/autopilot.config.yaml" << 'YAML'
version: "1.0"
services:
  backend:
    health_url: "http://localhost:8080/health"
phases:
  requirements:
    agent: "general-purpose"
    research:
      enabled: true
      agent: "Explore"
  testing:
    agent: "general-purpose"
    gate:
      min_test_count_per_type: 5
      required_test_types: [unit]
  implementation:
    serial_task:
      max_retries_per_task: 3
  reporting:
    coverage_target: 80
    zero_skip_required: true
test_suites:
  unit:
    command: "npm test"
YAML

output=$(bash "$SCRIPT_DIR/validate-config.sh" "$XREF_TEST_DIR/explore_deprecated" 2>/dev/null)
valid=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('valid',''))" 2>/dev/null || echo "")
if [ "$valid" = "False" ] || [ "$valid" = "false" ]; then
  green "  PASS: 21k. research.agent=Explore → valid=false (hard block)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 21k. research.agent=Explore → expected valid=false, got '$valid'"
  FAIL=$((FAIL + 1))
fi
assert_contains "21k. error lists Explore in enum_errors" "$output" "Explore"
assert_contains "21k. error field is research.agent" "$output" "research.agent"
assert_contains "21k. error suggests general-purpose" "$output" "general-purpose"
# Verify it's NOT in cross_ref_warnings (must be a hard error)
enum_count=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len([e for e in d.get('enum_errors',[]) if 'research.agent' in e]))" 2>/dev/null || echo "0")
if [ "$enum_count" -ge "1" ]; then
  green "  PASS: 21k. Explore error is in enum_errors (not soft warning)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 21k. Explore error not found in enum_errors"
  FAIL=$((FAIL + 1))
fi

# 21k2. case insensitive — lowercase "explore" also blocked
mkdir -p "$XREF_TEST_DIR/explore_lowercase/.claude"
cat > "$XREF_TEST_DIR/explore_lowercase/.claude/autopilot.config.yaml" << 'YAML'
version: "1.0"
services:
  backend:
    health_url: "http://localhost:8080/health"
phases:
  requirements:
    agent: "general-purpose"
    research:
      enabled: true
      agent: "explore"
  testing:
    agent: "general-purpose"
    gate:
      min_test_count_per_type: 5
      required_test_types: [unit]
  implementation:
    serial_task:
      max_retries_per_task: 3
  reporting:
    coverage_target: 80
    zero_skip_required: true
test_suites:
  unit:
    command: "npm test"
YAML

output=$(bash "$SCRIPT_DIR/validate-config.sh" "$XREF_TEST_DIR/explore_lowercase" 2>/dev/null)
valid=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('valid',''))" 2>/dev/null || echo "")
if [ "$valid" = "False" ] || [ "$valid" = "false" ]; then
  green "  PASS: 21k2. research.agent=explore (lowercase) → valid=false"
  PASS=$((PASS + 1))
else
  red "  FAIL: 21k2. lowercase explore → expected valid=false, got '$valid'"
  FAIL=$((FAIL + 1))
fi

# 21l. research.agent="general-purpose" → valid=true (happy path)
mkdir -p "$XREF_TEST_DIR/explore_ok/.claude"
cat > "$XREF_TEST_DIR/explore_ok/.claude/autopilot.config.yaml" << 'YAML'
version: "1.0"
services:
  backend:
    health_url: "http://localhost:8080/health"
phases:
  requirements:
    agent: "general-purpose"
    research:
      enabled: true
      agent: "general-purpose"
  testing:
    agent: "general-purpose"
    gate:
      min_test_count_per_type: 5
      required_test_types: [unit]
  implementation:
    serial_task:
      max_retries_per_task: 3
  reporting:
    coverage_target: 80
    zero_skip_required: true
test_suites:
  unit:
    command: "npm test"
YAML

output=$(bash "$SCRIPT_DIR/validate-config.sh" "$XREF_TEST_DIR/explore_ok" 2>/dev/null)
valid=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('valid',''))" 2>/dev/null || echo "")
if [ "$valid" = "True" ] || [ "$valid" = "true" ]; then
  green "  PASS: 21l. research.agent=general-purpose → valid=true"
  PASS=$((PASS + 1))
else
  red "  FAIL: 21l. general-purpose → expected valid=true, got '$valid'"
  FAIL=$((FAIL + 1))
fi
# Verify no Explore-related error
assert_not_contains "21l. general-purpose → no Explore error" "$output" "Explore"

# 21m. Phase 1 三路独立 agent 字段：auto_scan.agent="Explore" → HARD BLOCK
mkdir -p "$XREF_TEST_DIR/autoscan_explore/.claude"
cat > "$XREF_TEST_DIR/autoscan_explore/.claude/autopilot.config.yaml" << 'YAML'
version: "1.0"
services:
  backend:
    health_url: "http://localhost:8080/health"
phases:
  requirements:
    agent: "general-purpose"
    auto_scan:
      enabled: true
      agent: "Explore"
    research:
      enabled: true
      agent: "general-purpose"
  testing:
    agent: "general-purpose"
    gate:
      min_test_count_per_type: 5
      required_test_types: [unit]
  implementation:
    serial_task:
      max_retries_per_task: 3
  reporting:
    coverage_target: 80
    zero_skip_required: true
test_suites:
  unit:
    command: "npm test"
YAML

output=$(bash "$SCRIPT_DIR/validate-config.sh" "$XREF_TEST_DIR/autoscan_explore" 2>/dev/null)
valid=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('valid',''))" 2>/dev/null || echo "")
if [ "$valid" = "False" ] || [ "$valid" = "false" ]; then
  green "  PASS: 21m. auto_scan.agent=Explore → valid=false"
  PASS=$((PASS + 1))
else
  red "  FAIL: 21m. auto_scan.agent=Explore → expected valid=false, got '$valid'"
  FAIL=$((FAIL + 1))
fi
assert_contains "21m. error cites auto_scan.agent" "$output" "auto_scan.agent"

# 21n. web_search.agent="Explore" → HARD BLOCK
mkdir -p "$XREF_TEST_DIR/websearch_explore/.claude"
cat > "$XREF_TEST_DIR/websearch_explore/.claude/autopilot.config.yaml" << 'YAML'
version: "1.0"
services:
  backend:
    health_url: "http://localhost:8080/health"
phases:
  requirements:
    agent: "general-purpose"
    research:
      enabled: true
      agent: "general-purpose"
      web_search:
        enabled: true
        agent: "Explore"
  testing:
    agent: "general-purpose"
    gate:
      min_test_count_per_type: 5
      required_test_types: [unit]
  implementation:
    serial_task:
      max_retries_per_task: 3
  reporting:
    coverage_target: 80
    zero_skip_required: true
test_suites:
  unit:
    command: "npm test"
YAML

output=$(bash "$SCRIPT_DIR/validate-config.sh" "$XREF_TEST_DIR/websearch_explore" 2>/dev/null)
valid=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('valid',''))" 2>/dev/null || echo "")
if [ "$valid" = "False" ] || [ "$valid" = "false" ]; then
  green "  PASS: 21n. web_search.agent=Explore → valid=false"
  PASS=$((PASS + 1))
else
  red "  FAIL: 21n. web_search.agent=Explore → expected valid=false, got '$valid'"
  FAIL=$((FAIL + 1))
fi
assert_contains "21n. error cites web_search.agent" "$output" "web_search.agent"

# 21o. redteam.agent="Explore" → HARD BLOCK (Phase 5.5 Red Team 需 Write 反例)
mkdir -p "$XREF_TEST_DIR/redteam_explore/.claude"
cat > "$XREF_TEST_DIR/redteam_explore/.claude/autopilot.config.yaml" << 'YAML'
version: "1.0"
services:
  backend:
    health_url: "http://localhost:8080/health"
phases:
  requirements:
    agent: "general-purpose"
    research:
      enabled: true
      agent: "general-purpose"
  testing:
    agent: "general-purpose"
    gate:
      min_test_count_per_type: 5
      required_test_types: [unit]
  implementation:
    serial_task:
      max_retries_per_task: 3
  reporting:
    coverage_target: 80
    zero_skip_required: true
  redteam:
    enabled: true
    agent: "Explore"
test_suites:
  unit:
    command: "npm test"
YAML

output=$(bash "$SCRIPT_DIR/validate-config.sh" "$XREF_TEST_DIR/redteam_explore" 2>/dev/null)
valid=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('valid',''))" 2>/dev/null || echo "")
if [ "$valid" = "False" ] || [ "$valid" = "false" ]; then
  green "  PASS: 21o. redteam.agent=Explore → valid=false"
  PASS=$((PASS + 1))
else
  red "  FAIL: 21o. redteam.agent=Explore → expected valid=false, got '$valid'"
  FAIL=$((FAIL + 1))
fi
assert_contains "21o. error cites redteam.agent" "$output" "redteam.agent"

# 21p. 三路 + redteam 全部合法值 → valid=true (happy path)
mkdir -p "$XREF_TEST_DIR/threepaths_ok/.claude"
cat > "$XREF_TEST_DIR/threepaths_ok/.claude/autopilot.config.yaml" << 'YAML'
version: "1.0"
services:
  backend:
    health_url: "http://localhost:8080/health"
phases:
  requirements:
    agent: "general-purpose"
    auto_scan:
      enabled: true
      agent: "general-purpose"
    research:
      enabled: true
      agent: "general-purpose"
      web_search:
        enabled: true
        agent: "general-purpose"
  testing:
    agent: "general-purpose"
    gate:
      min_test_count_per_type: 5
      required_test_types: [unit]
  implementation:
    serial_task:
      max_retries_per_task: 3
  reporting:
    coverage_target: 80
    zero_skip_required: true
  redteam:
    enabled: true
    agent: "general-purpose"
test_suites:
  unit:
    command: "npm test"
YAML

output=$(bash "$SCRIPT_DIR/validate-config.sh" "$XREF_TEST_DIR/threepaths_ok" 2>/dev/null)
valid=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('valid',''))" 2>/dev/null || echo "")
if [ "$valid" = "True" ] || [ "$valid" = "true" ]; then
  green "  PASS: 21p. 三路+redteam 合法 → valid=true"
  PASS=$((PASS + 1))
else
  red "  FAIL: 21p. 三路合法 → expected valid=true, got '$valid'"
  FAIL=$((FAIL + 1))
fi

rm -rf "$XREF_TEST_DIR"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0
