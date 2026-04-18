#!/usr/bin/env bash
# test_allure_enhanced.sh — check-allure-install.sh enhanced
#   合并自:
#     - 原 Section 20 (enhanced tests): 本文件原内容
#     - 原 test_allure_install.sh §16: 除 syntax check（已被 test_syntax.sh 覆盖）外，
#       独有 case 16b（接受 project path 参数）已并入 Section C
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- check-allure-install.sh enhanced tests ---"
setup_autopilot_fixture

# === Section A: clean-dir invocation (原 §20a-d) ===

# A1 (原 20a). Run in clean temp dir (no project context) → valid JSON
exit_code=0
output=$(cd /tmp && bash "$SCRIPT_DIR/check-allure-install.sh" 2>/dev/null) || exit_code=$?
assert_exit "A1: allure check in clean dir → exit 0" 0 $exit_code

# A2 (原 20b). Output must be valid JSON
if echo "$output" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  green "  PASS: A2: allure check output is valid JSON"
  PASS=$((PASS + 1))
else
  red "  FAIL: A2: allure check output is not valid JSON"
  FAIL=$((FAIL + 1))
fi

# A3 (原 20c). JSON has all 4 component keys with 'installed' field
for comp in allure_cli allure_playwright allure_pytest allure_gradle; do
  has_installed=$(echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
c = data.get('$comp', {})
print('yes' if 'installed' in c else 'no')
" 2>/dev/null || echo "no")
  if [ "$has_installed" = "yes" ]; then
    green "  PASS: A3: allure component '$comp' has 'installed' field"
    PASS=$((PASS + 1))
  else
    red "  FAIL: A3: allure component '$comp' missing 'installed' field"
    FAIL=$((FAIL + 1))
  fi
done

# A4 (原 20d). JSON has install_commands list
has_commands=$(echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
cmds = data.get('install_commands', None)
print('yes' if isinstance(cmds, list) else 'no')
" 2>/dev/null || echo "no")
if [ "$has_commands" = "yes" ]; then
  green "  PASS: A4: allure install_commands is a list"
  PASS=$((PASS + 1))
else
  red "  FAIL: A4: allure install_commands not a list"
  FAIL=$((FAIL + 1))
fi

# === Section C: project-path argument invocation (并入自原 test_allure_install.sh §16b) ===

# C1 (原 16b). Accepts project-path argument (nonexistent dir) → valid JSON with required fields
exit_code=0
output_c=$(bash "$SCRIPT_DIR/check-allure-install.sh" /tmp/nonexistent-project-allure-test 2>/dev/null) || exit_code=$?
assert_exit "C1: check-allure-install with path arg → exit 0" 0 $exit_code

if echo "$output_c" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'all_required_installed' in d; assert 'missing' in d; print('ok')" 2>/dev/null | grep -q "ok"; then
  green "  PASS: C1b: path-arg invocation returns JSON with all_required_installed + missing"
  PASS=$((PASS + 1))
else
  red "  FAIL: C1b: path-arg invocation JSON missing required fields"
  FAIL=$((FAIL + 1))
fi

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
