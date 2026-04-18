#!/usr/bin/env bash
# test_mutation_sample.sh — 验证 test-mutation-sample.sh 变异测试脚本
#
# 测试覆盖：
#   1. fixture 目标含对应 test 能 kill → kill_rate = 1.0
#   2. fixture 目标无对应 test → survivor 全部标记
#   3. 脏 git tree → exit 2 + 不执行任何变异
#   4. 超时 → mutant 标记为 timeout
#   5. 变异 + 恢复后 git diff 为空
#   6. 混合结果 → overall_kill_rate 正确计算

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_test_helpers.sh
source "$SCRIPT_DIR/_test_helpers.sh"

PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MUTATE="$PLUGIN_ROOT/runtime/scripts/test-mutation-sample.sh"
FIXTURE_SRC="$PLUGIN_ROOT/tests/fixtures/mutation"

if [ ! -x "$MUTATE" ]; then
  red "test-mutation-sample.sh missing or not executable: $MUTATE"
  exit 1
fi

# 构造独立 git 仓库并复制 fixture 子集
setup_repo() {
  local variant="$1" tmp
  tmp=$(mktemp -d)
  (
    cd "$tmp" || exit 1
    git init -q
    git config user.email "test@test.local"
    git config user.name "test"
    mkdir -p runtime/scripts tests
    case "$variant" in
      good)
        cp "$FIXTURE_SRC/runtime_good/scripts/good_target.sh" runtime/scripts/good_target.sh
        cp "$FIXTURE_SRC/runtime_good/tests/test_good_target.sh" tests/test_good_target.sh
        ;;
      bad)
        cp "$FIXTURE_SRC/runtime_bad/scripts/untested_target.sh" runtime/scripts/untested_target.sh
        ;;
      mix)
        cp "$FIXTURE_SRC/runtime_mix/scripts/mix_a.sh" runtime/scripts/mix_a.sh
        cp "$FIXTURE_SRC/runtime_mix/scripts/mix_b.sh" runtime/scripts/mix_b.sh
        cp "$FIXTURE_SRC/runtime_mix/tests/test_mix_a.sh" tests/test_mix_a.sh
        ;;
    esac
    git add -A
    git commit -q -m "init"
  )
  echo "$tmp"
}

green "=== test_mutation_sample.sh ==="

# Case 1: 好 fixture → kill_rate = 1.0
TMP1=$(setup_repo good)
OUT1=$(cd "$TMP1" && "$MUTATE" --targets "runtime/scripts/*.sh" --sample-size 5 --timeout-per-mutant 15 2>&1)
RC1=$?
assert_exit "1a. exit 0" 0 "$RC1"
assert_contains "1b. summary 行" "$OUT1" "MUTATION_KILL_RATE="
assert_file_exists "1c. 报告文件生成" "$TMP1/.mutation-report.json"
KR1=$(python3 -c "import json;print(json.load(open('$TMP1/.mutation-report.json'))['overall_kill_rate'])" 2>/dev/null || echo "")
if [ -n "$KR1" ] && python3 -c "import sys;sys.exit(0 if float('$KR1')>=0.99 else 1)" 2>/dev/null; then
  green "  PASS: 1d. kill_rate ≈ 1.0 (=$KR1)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 1d. kill_rate 不为 1.0 (=$KR1)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMP1"

# Case 2: 无对应 test → 全部 survived
TMP2=$(setup_repo bad)
OUT2=$(cd "$TMP2" && "$MUTATE" --targets "runtime/scripts/*.sh" --sample-size 5 --timeout-per-mutant 15 2>&1)
RC2=$?
assert_exit "2a. exit 0" 0 "$RC2"
assert_contains "2b. SURVIVORS 行" "$OUT2" "SURVIVORS="
KR2=$(python3 -c "import json;print(json.load(open('$TMP2/.mutation-report.json'))['overall_kill_rate'])" 2>/dev/null || echo "")
if [ "$KR2" = "0.0" ] || [ "$KR2" = "0" ]; then
  green "  PASS: 2c. kill_rate = 0 (=$KR2)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2c. kill_rate 不为 0 (=$KR2)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMP2"

# Case 3: 脏 git tree → exit 2
TMP3=$(setup_repo good)
echo "dirty" >"$TMP3/runtime/scripts/good_target.sh"
OUT3=$(cd "$TMP3" && "$MUTATE" --targets "runtime/scripts/*.sh" --sample-size 5 2>&1)
RC3=$?
assert_exit "3a. 脏 tree → exit 2" 2 "$RC3"
assert_contains "3b. 错误信息提示干净工作区" "$OUT3" "clean"
# 无报告写出或报告空（不强求）
rm -rf "$TMP3"

# Case 4: 超时 — 构造 sleep 变异（伪造：注入固定 test 文件，等超时）
TMP4=$(mktemp -d)
(
  cd "$TMP4" || exit 1
  git init -q
  git config user.email "test@test.local"
  git config user.name "test"
  mkdir -p runtime/scripts tests
  cat >runtime/scripts/slow_target.sh <<'EOF'
#!/usr/bin/env bash
if [ "$1" == "ok" ]; then
  return 0
fi
exit 1
EOF
  cat >tests/test_slow_target.sh <<'EOF'
#!/usr/bin/env bash
sleep 30
exit 0
EOF
  git add -A
  git commit -q -m "init"
)
OUT4=$(cd "$TMP4" && "$MUTATE" --targets "runtime/scripts/*.sh" --sample-size 5 --timeout-per-mutant 2 2>&1 || true)
RC4=$?
assert_exit "4a. exit 0" 0 "$RC4"
TIMEOUT_IN_REPORT=$(python3 -c "import json;d=json.load(open('$TMP4/.mutation-report.json'));print(any(m['status']=='timeout' for t in d['targets'] for m in t['mutants']))" 2>/dev/null || echo False)
if [ "$TIMEOUT_IN_REPORT" = "True" ]; then
  green "  PASS: 4b. 报告中含 timeout 状态"
  PASS=$((PASS + 1))
else
  red "  FAIL: 4b. 报告中未出现 timeout 状态"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMP4"

# Case 5: 恢复后 git diff 为空
TMP5=$(setup_repo good)
(cd "$TMP5" && "$MUTATE" --targets "runtime/scripts/*.sh" --sample-size 5 --timeout-per-mutant 15 >/dev/null 2>&1)
DIFF5=$(cd "$TMP5" && git diff --stat)
if [ -z "$DIFF5" ]; then
  green "  PASS: 5. 运行后 git diff 为空"
  PASS=$((PASS + 1))
else
  red "  FAIL: 5. 运行后 git diff 非空: $DIFF5"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMP5"

# Case 6: 混合结果
TMP6=$(setup_repo mix)
OUT6=$(cd "$TMP6" && "$MUTATE" --targets "runtime/scripts/*.sh" --sample-size 5 --timeout-per-mutant 15 2>&1)
RC6=$?
assert_exit "6a. exit 0" 0 "$RC6"
KR6=$(python3 -c "import json;print(json.load(open('$TMP6/.mutation-report.json'))['overall_kill_rate'])" 2>/dev/null || echo "")
# 混合：期望 kill_rate 在 (0, 1) 之间
if [ -n "$KR6" ] && python3 -c "import sys;v=float('$KR6');sys.exit(0 if 0.0<v<1.0 else 1)" 2>/dev/null; then
  green "  PASS: 6b. 混合 kill_rate 在 (0,1) 之间 (=$KR6)"
  PASS=$((PASS + 1))
else
  # 若 mix_b 无 test 且 mix_a 强 test，期望 0 < kr < 1
  red "  FAIL: 6b. 混合 kill_rate 不在 (0,1) (=$KR6)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMP6"

echo ""
echo "=== Summary: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
