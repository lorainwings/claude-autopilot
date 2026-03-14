#!/usr/bin/env bash
# test_allure_install.sh — Section 16: check-allure-install.sh
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 16. check-allure-install.sh ---"
setup_autopilot_fixture

# 16a. Syntax check
if bash -n "$SCRIPT_DIR/check-allure-install.sh" 2>/dev/null; then
  green "  PASS: check-allure-install.sh syntax OK"
  PASS=$((PASS + 1))
else
  red "  FAIL: check-allure-install.sh syntax error"
  FAIL=$((FAIL + 1))
fi

# 16b. Returns valid JSON
exit_code=0
output=$(bash "$SCRIPT_DIR/check-allure-install.sh" /tmp/nonexistent-project-allure-test 2>/dev/null) || exit_code=$?
assert_exit "check-allure-install → exit 0" 0 $exit_code

if echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'all_required_installed' in d; assert 'missing' in d; print('ok')" 2>/dev/null | grep -q "ok"; then
  green "  PASS: check-allure-install returns valid JSON with required fields"
  PASS=$((PASS + 1))
else
  red "  FAIL: check-allure-install JSON missing required fields"
  FAIL=$((FAIL + 1))
fi

# 16c. JSON has all 4 component keys
if echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
required = ['allure_cli', 'allure_playwright', 'allure_pytest', 'allure_gradle']
for key in required:
    assert key in d, f'Missing key: {key}'
    assert 'installed' in d[key], f'Missing installed field in {key}'
print('ok')
" 2>/dev/null | grep -q "ok"; then
  green "  PASS: check-allure-install has all 4 component keys with installed field"
  PASS=$((PASS + 1))
else
  red "  FAIL: check-allure-install missing component keys"
  FAIL=$((FAIL + 1))
fi

# 16d. install_commands is an array (even if empty)
if echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert isinstance(d.get('install_commands'), list), 'install_commands is not a list'
print('ok')
" 2>/dev/null | grep -q "ok"; then
  green "  PASS: install_commands is a list"
  PASS=$((PASS + 1))
else
  red "  FAIL: install_commands is not a list"
  FAIL=$((FAIL + 1))
fi

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0
