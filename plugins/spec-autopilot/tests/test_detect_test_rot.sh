#!/usr/bin/env bash
# test_detect_test_rot.sh — 验证 detect-test-rot.sh 测试过期检测
#
# 测试覆盖：
#   1. 删除 runtime 脚本但 tests/ 仍引用 → 报 rot (R1)
#   2. 无引用 → 无 rot
#   3. 弱断言模式 (assert_exit "x" 0 0) → 报告 (R4)
#   4. 重复 case 名称跨文件 → 报告 (R5)
#   5. hook 文件修改 → 标注相关 test 需回归 (R3)
#   6. 空 staging → exit 0, ROT_CANDIDATES=0

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_test_helpers.sh
source "$SCRIPT_DIR/_test_helpers.sh"

PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DETECT="$PLUGIN_ROOT/runtime/scripts/detect-test-rot.sh"

if [ ! -x "$DETECT" ]; then
  red "detect-test-rot.sh missing or not executable: $DETECT"
  exit 1
fi

setup_repo() {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/plugins/spec-autopilot/runtime/scripts"
  mkdir -p "$tmp/plugins/spec-autopilot/tests"
  mkdir -p "$tmp/plugins/spec-autopilot/hooks"
  cat >"$tmp/plugins/spec-autopilot/runtime/scripts/foo-runner.sh" <<'EOF'
#!/usr/bin/env bash
foo_bar() { echo "foo"; }
EOF
  cat >"$tmp/plugins/spec-autopilot/tests/test_foo.sh" <<'EOF'
#!/usr/bin/env bash
# calls foo-runner.sh
bash foo-runner.sh
foo_bar
EOF
  echo "$tmp"
}

green "=== test_detect_test_rot.sh ==="

# Case 1: runtime script deleted but tests still reference
TMP1=$(setup_repo)
rm "$TMP1/plugins/spec-autopilot/runtime/scripts/foo-runner.sh"
# Simulate `git diff --diff-filter=D` via env var; detector uses --deleted-files
OUT1=$(AUTOPILOT_PROJECT_ROOT="$TMP1" "$DETECT" --changed-files "" --deleted-files "plugins/spec-autopilot/runtime/scripts/foo-runner.sh" 2>&1 || true)
RC1=$?
assert_exit "1a. R1 detected → exit 0" 0 $RC1
assert_contains "1b. summary line" "$OUT1" "ROT_CANDIDATES="
assert_contains "1c. mentions foo-runner" "$OUT1" "foo-runner"
assert_file_exists "1d. test-rot-candidates.json written" "$TMP1/.cache/spec-autopilot/test-rot-candidates.json"
rm -rf "$TMP1"

# Case 2: no references → no rot
TMP2=$(setup_repo)
rm "$TMP2/plugins/spec-autopilot/tests/test_foo.sh"
rm "$TMP2/plugins/spec-autopilot/runtime/scripts/foo-runner.sh"
OUT2=$(AUTOPILOT_PROJECT_ROOT="$TMP2" "$DETECT" --changed-files "" --deleted-files "plugins/spec-autopilot/runtime/scripts/foo-runner.sh" 2>&1 || true)
RC2=$?
assert_exit "2a. no refs → exit 0" 0 $RC2
assert_contains "2b. zero candidates" "$OUT2" "ROT_CANDIDATES=0"
rm -rf "$TMP2"

# Case 3: weak assertion pattern
TMP3=$(setup_repo)
cat >"$TMP3/plugins/spec-autopilot/tests/test_weak.sh" <<'EOF'
#!/usr/bin/env bash
assert_exit "x" 0 0
[ "a" = "a" ]
grep -q . .
EOF
OUT3=$(AUTOPILOT_PROJECT_ROOT="$TMP3" "$DETECT" --changed-files "plugins/spec-autopilot/tests/test_weak.sh" 2>&1 || true)
RC3=$?
assert_exit "3a. R4 weak-assert → exit 0" 0 $RC3
assert_contains "3b. mentions R4" "$OUT3" "R4"
rm -rf "$TMP3"

# Case 4: duplicate case names cross-file
TMP4=$(setup_repo)
cat >"$TMP4/plugins/spec-autopilot/tests/test_a.sh" <<'EOF'
#!/usr/bin/env bash
assert_exit "dup-case" 0 0
EOF
cat >"$TMP4/plugins/spec-autopilot/tests/test_b.sh" <<'EOF'
#!/usr/bin/env bash
assert_exit "dup-case" 0 0
EOF
OUT4=$(AUTOPILOT_PROJECT_ROOT="$TMP4" "$DETECT" --changed-files "plugins/spec-autopilot/tests/test_a.sh plugins/spec-autopilot/tests/test_b.sh" 2>&1 || true)
RC4=$?
assert_exit "4a. R5 duplicate → exit 0" 0 $RC4
assert_contains "4b. mentions R5" "$OUT4" "R5"
rm -rf "$TMP4"

# Case 5: hook file modified → R3 info
TMP5=$(setup_repo)
echo "#!/usr/bin/env bash" >"$TMP5/plugins/spec-autopilot/hooks/sample-hook.sh"
OUT5=$(AUTOPILOT_PROJECT_ROOT="$TMP5" "$DETECT" --changed-files "plugins/spec-autopilot/hooks/sample-hook.sh" 2>&1 || true)
RC5=$?
assert_exit "5a. R3 hook → exit 0" 0 $RC5
assert_contains "5b. mentions R3" "$OUT5" "R3"
rm -rf "$TMP5"

# Case 6: empty staging
TMP6=$(setup_repo)
OUT6=$(AUTOPILOT_PROJECT_ROOT="$TMP6" "$DETECT" --changed-files "" 2>&1 || true)
RC6=$?
assert_exit "6a. empty → exit 0" 0 $RC6
assert_contains "6b. zero candidates" "$OUT6" "ROT_CANDIDATES=0"
rm -rf "$TMP6"

echo
green "Results: $PASS passed, $FAIL failed"

[ "$FAIL" -eq 0 ] || exit 1
exit 0
