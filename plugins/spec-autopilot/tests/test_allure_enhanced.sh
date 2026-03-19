#!/usr/bin/env bash
# test_allure_enhanced.sh — Section 20: check-allure-install.sh enhanced
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 20. check-allure-install.sh enhanced tests ---"
setup_autopilot_fixture

# 20a. Run in clean temp dir (no project context) → valid JSON
exit_code=0
output=$(cd /tmp && bash "$SCRIPT_DIR/check-allure-install.sh" 2>/dev/null) || exit_code=$?
assert_exit "allure check in clean dir → exit 0" 0 $exit_code

# 20b. Output must be valid JSON
if echo "$output" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  green "  PASS: allure check output is valid JSON"
  PASS=$((PASS + 1))
else
  red "  FAIL: allure check output is not valid JSON"
  FAIL=$((FAIL + 1))
fi

# 20c. JSON has all 4 component keys with 'installed' field
for comp in allure_cli allure_playwright allure_pytest allure_gradle; do
  has_installed=$(echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
c = data.get('$comp', {})
print('yes' if 'installed' in c else 'no')
" 2>/dev/null || echo "no")
  if [ "$has_installed" = "yes" ]; then
    green "  PASS: allure component '$comp' has 'installed' field"
    PASS=$((PASS + 1))
  else
    red "  FAIL: allure component '$comp' missing 'installed' field"
    FAIL=$((FAIL + 1))
  fi
done

# 20d. JSON has install_commands list
has_commands=$(echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
cmds = data.get('install_commands', None)
print('yes' if isinstance(cmds, list) else 'no')
" 2>/dev/null || echo "no")
if [ "$has_commands" = "yes" ]; then
  green "  PASS: allure install_commands is a list"
  PASS=$((PASS + 1))
else
  red "  FAIL: allure install_commands not a list"
  FAIL=$((FAIL + 1))
fi

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0
