#!/usr/bin/env bash
# TEST_LAYER: docs_consistency
# test_explore_protection_contracts.sh — Explore agent multi-layer protection contract tests
# Verifies that the three-layer fail-closed defense against research.agent="Explore"
# is maintained across SKILL.md, dispatch references, and the config validator.
#
# Layer 1: _config_validator.py → enum_errors → valid=false (tested in test_validate_config.sh:21k)
# Layer 2: autopilot-phase0-init/SKILL.md → hard-block on valid=false + surfaces enum_errors
# Layer 3: dispatch-phase-prompts.md → runtime forced fallback Explore→general-purpose
#
# This test ensures the protective language in Layers 2 and 3 is not accidentally removed.
set -uo pipefail
TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"

echo "=== Explore protection contracts (docs_consistency) ==="

PHASE0_SKILL="$SCRIPT_DIR/../../skills/autopilot-phase0-init/SKILL.md"
DISPATCH_REF="$SCRIPT_DIR/../../skills/autopilot/references/dispatch-phase-prompts.md"
VALIDATOR_PY="$SCRIPT_DIR/_config_validator.py"

# ────────────────────────────────────────
# Layer 2 contracts: Phase 0 SKILL.md hard-block semantics
# ────────────────────────────────────────
echo "--- Layer 2: Phase 0 hard-block contracts ---"

# L2a. Phase 0 mentions enum_errors (not just missing_keys)
line=$(grep 'enum_errors' "$PHASE0_SKILL" || true)
assert_contains "L2a. Phase 0 SKILL.md mentions enum_errors" "$line" "enum_errors"

# L2b. Phase 0 has hard-block semantics on valid=false
# Checks for both "硬阻断" (hard-block) and "禁止" (forbidden) in the same file
hard_block=$(grep -c '硬阻断' "$PHASE0_SKILL" || echo "0")
if [ "$hard_block" -ge "1" ]; then
  green "  PASS: L2b. Phase 0 mentions 硬阻断 (hard-block)"
  PASS=$((PASS + 1))
else
  red "  FAIL: L2b. Phase 0 missing 硬阻断 hard-block language"
  FAIL=$((FAIL + 1))
fi
forbid=$(grep -c '禁止.*进入\|禁止.*继续' "$PHASE0_SKILL" || echo "0")
if [ "$forbid" -ge "1" ]; then
  green "  PASS: L2b2. Phase 0 explicitly forbids continuing on valid=false"
  PASS=$((PASS + 1))
else
  red "  FAIL: L2b2. Phase 0 missing 禁止进入/继续 language"
  FAIL=$((FAIL + 1))
fi

# L2c. Phase 0 mentions all error categories (missing_keys, type_errors, enum_errors)
for category in missing_keys type_errors enum_errors; do
  line=$(grep "$category" "$PHASE0_SKILL" || true)
  if [ -n "$line" ]; then
    green "  PASS: L2c. Phase 0 mentions $category"
    PASS=$((PASS + 1))
  else
    red "  FAIL: L2c. Phase 0 missing error category: $category"
    FAIL=$((FAIL + 1))
  fi
done

# ────────────────────────────────────────
# Layer 3 contracts: dispatch forced fallback
# ────────────────────────────────────────
echo "--- Layer 3: dispatch forced fallback contracts ---"

# ────────────────────────────────────────
# Layer 3 contracts: dispatch hard-block (was: forced fallback, upgraded to runtime hook block)
# ────────────────────────────────────────
echo "--- Layer 3: dispatch hard-block contracts ---"

# L3a. dispatch-phase-prompts.md mentions runtime hook block via auto-emit-agent-dispatch.sh
line=$(grep -E 'auto-emit-agent-dispatch\.sh' "$DISPATCH_REF" | head -1 || true)
assert_contains "L3a. dispatch mentions runtime hook block" "$line" "auto-emit-agent-dispatch.sh"

# L3b. dispatch mentions both _config_validator.py and runtime hook (defense-in-depth)
line=$(grep -E '_config_validator\.py' "$DISPATCH_REF" | head -1 || true)
assert_contains "L3b. dispatch mentions config validator layer" "$line" "_config_validator.py"

# L3c. dispatch mentions config-driven enforcement (not hardcoded agent name)
line=$(grep -E 'autopilot\.config\.yaml|完全一致|配置一致' "$DISPATCH_REF" | head -1 || true)
assert_contains "L3c. dispatch mentions config-driven runtime check" "$line" "autopilot.config.yaml"

# L3d. runtime hook script reads config (not hardcoded agent name)
HOOK_SCRIPT="$SCRIPT_DIR/auto-emit-agent-dispatch.sh"
line=$(grep -E 'read_config_value|autopilot\.config\.yaml' "$HOOK_SCRIPT" | head -1 || true)
assert_contains "L3d. runtime hook reads config" "$line" "config"

# ────────────────────────────────────────
# Layer 1 contracts: validator produces enum_errors (not cross_ref_warnings)
# ────────────────────────────────────────
echo "--- Layer 1: validator contract ---"

# L1a. _config_validator.py has Explore detection using enum_errors (not cross_ref_warnings)
# The append is multi-line: enum_errors.append( on one line, then "Explore" string on next lines
# Check that enum_errors.append appears near 'Explore' in the same file
explore_in_enum=$(python3 -c "
import re
with open('$VALIDATOR_PY') as f:
    content = f.read()
# Find all enum_errors.append(...) blocks and check if any contain 'Explore'
matches = re.findall(r'enum_errors\.append\([^)]*Explore[^)]*\)', content, re.DOTALL)
print(len(matches))
" 2>/dev/null || echo "0")
if [ "$explore_in_enum" -ge "1" ]; then
  green "  PASS: L1a. validator blocks Explore via enum_errors.append"
  PASS=$((PASS + 1))
else
  red "  FAIL: L1a. Explore detection not in enum_errors.append"
  FAIL=$((FAIL + 1))
fi
# Also verify "Explore" is NOT in cross_ref_warnings.append (would be a regression)
explore_in_xref=$(python3 -c "
import re
with open('$VALIDATOR_PY') as f:
    content = f.read()
matches = re.findall(r'cross_ref_warnings\.append\([^)]*Explore[^)]*\)', content, re.DOTALL)
print(len(matches))
" 2>/dev/null || echo "0")
if [ "$explore_in_xref" = "0" ]; then
  green "  PASS: L1a2. Explore NOT in cross_ref_warnings (no soft-warning regression)"
  PASS=$((PASS + 1))
else
  red "  FAIL: L1a2. Explore leaked into cross_ref_warnings (regression)"
  FAIL=$((FAIL + 1))
fi

# L1b. End-to-end: validate-config.sh with Explore → valid=false (behavioral)
TMPDIR_EC=$(mktemp -d)
trap 'rm -rf "$TMPDIR_EC"' EXIT
mkdir -p "$TMPDIR_EC/.claude"
cat > "$TMPDIR_EC/.claude/autopilot.config.yaml" <<'YAML'
version: "1.0"
services:
  backend:
    health_url: "http://localhost:8080/health"
phases:
  requirements:
    agent: "general-purpose"
    research:
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

output=$(bash "$SCRIPT_DIR/validate-config.sh" "$TMPDIR_EC" 2>/dev/null)
valid=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('valid',''))" 2>/dev/null || echo "")
if [ "$valid" = "False" ] || [ "$valid" = "false" ]; then
  green "  PASS: L1b. validate-config.sh Explore → valid=false"
  PASS=$((PASS + 1))
else
  red "  FAIL: L1b. Explore should make valid=false, got '$valid'"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0
