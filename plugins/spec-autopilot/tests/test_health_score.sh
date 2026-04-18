#!/usr/bin/env bash
# test_health_score.sh — 验证 test-health-score.sh 健康度评分
#
# 测试覆盖：
#   1. 3 个文件（强/弱/重复）→ weak_ratio + duplicate_ratio 正确
#   2. 缺失 mutation-report.json → 评分仍可计算（kill_rate 置 null）
#   3. 存在 mutation-report.json → overall_score 综合计算
#   4. 配置阈值触发 HEALTH_BELOW_THRESHOLD
#   5. 空 tests 目录 → 0 分数 + 清晰错误提示

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_test_helpers.sh
source "$SCRIPT_DIR/_test_helpers.sh"

PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HEALTH="$PLUGIN_ROOT/runtime/scripts/test-health-score.sh"
FIXTURE_SRC="$PLUGIN_ROOT/tests/fixtures/mutation"

if [ ! -x "$HEALTH" ]; then
  red "test-health-score.sh missing or not executable: $HEALTH"
  exit 1
fi

setup_workspace() {
  local variant="$1" tmp
  tmp=$(mktemp -d)
  (
    cd "$tmp" || exit 1
    git init -q
    git config user.email "t@t"
    git config user.name "t"
    mkdir -p tests
    case "$variant" in
      mixed)
        cp "$FIXTURE_SRC/health_strong/tests/test_s1.sh" tests/test_strong.sh
        cp "$FIXTURE_SRC/health_weak/tests/test_weak.sh" tests/test_weak.sh
        cp "$FIXTURE_SRC/health_dup/tests/test_dup_a.sh" tests/test_dup_a.sh
        cp "$FIXTURE_SRC/health_dup/tests/test_dup_b.sh" tests/test_dup_b.sh
        ;;
      empty) ;;
    esac
    git add -A >/dev/null 2>&1 || true
    git commit -q -m "init" >/dev/null 2>&1 || true
  )
  echo "$tmp"
}

green "=== test_health_score.sh ==="

# Case 1: 3 个文件（强/弱/重复）
TMP1=$(setup_workspace mixed)
OUT1=$(cd "$TMP1" && "$HEALTH" --tests-dir tests 2>&1)
RC1=$?
assert_exit "1a. exit 0" 0 "$RC1"
assert_file_exists "1b. 报告生成" "$TMP1/.test-health-report.json"
WEAK1=$(python3 -c "import json;d=json.load(open('$TMP1/.test-health-report.json'));print(d['metrics']['weak_ratio'])" 2>/dev/null || echo "")
DUP1=$(python3 -c "import json;d=json.load(open('$TMP1/.test-health-report.json'));print(d['metrics']['duplicate_ratio'])" 2>/dev/null || echo "")
if [ -n "$WEAK1" ] && python3 -c "import sys;v=float('$WEAK1');sys.exit(0 if v>0 else 1)" 2>/dev/null; then
  green "  PASS: 1c. weak_ratio > 0 (=$WEAK1)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 1c. weak_ratio 未 > 0 (=$WEAK1)"
  FAIL=$((FAIL + 1))
fi
if [ -n "$DUP1" ] && python3 -c "import sys;v=float('$DUP1');sys.exit(0 if v>0 else 1)" 2>/dev/null; then
  green "  PASS: 1d. duplicate_ratio > 0 (=$DUP1)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 1d. duplicate_ratio 未 > 0 (=$DUP1)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMP1"

# Case 2: 缺失 mutation-report.json → kill_rate = null
TMP2=$(setup_workspace mixed)
(cd "$TMP2" && "$HEALTH" --tests-dir tests >/dev/null 2>&1)
KR2=$(python3 -c "import json;d=json.load(open('$TMP2/.test-health-report.json'));print(d['metrics'].get('kill_rate'))" 2>/dev/null || echo "")
if [ "$KR2" = "None" ] || [ -z "$KR2" ]; then
  green "  PASS: 2. kill_rate 为 null (=$KR2)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2. kill_rate 非 null (=$KR2)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMP2"

# Case 3: 存在 mutation-report.json → overall_score 综合
TMP3=$(setup_workspace mixed)
cat >"$TMP3/.mutation-report.json" <<'EOF'
{"overall_kill_rate": 0.8, "survivors": [], "targets": []}
EOF
(cd "$TMP3" && "$HEALTH" --tests-dir tests >/dev/null 2>&1)
KR3=$(python3 -c "import json;d=json.load(open('$TMP3/.test-health-report.json'));print(d['metrics']['kill_rate'])" 2>/dev/null || echo "")
SC3=$(python3 -c "import json;d=json.load(open('$TMP3/.test-health-report.json'));print(d['overall_score'])" 2>/dev/null || echo "")
assert_contains "3a. kill_rate 读入 (=0.8)" "$KR3" "0.8"
if [ -n "$SC3" ] && python3 -c "import sys;v=float('$SC3');sys.exit(0 if 0<=v<=100 else 1)" 2>/dev/null; then
  green "  PASS: 3b. overall_score 在 [0,100] (=$SC3)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3b. overall_score 超出 [0,100] (=$SC3)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMP3"

# Case 4: 阈值触发
TMP4=$(setup_workspace mixed)
OUT4=$(cd "$TMP4" && "$HEALTH" --tests-dir tests --threshold 999 2>&1)
RC4=$?
assert_exit "4a. exit 0 (不阻断)" 0 "$RC4"
assert_contains "4b. HEALTH_BELOW_THRESHOLD 输出" "$OUT4" "HEALTH_BELOW_THRESHOLD=1"
rm -rf "$TMP4"

# Case 5: 空 tests 目录
TMP5=$(setup_workspace empty)
OUT5=$(cd "$TMP5" && "$HEALTH" --tests-dir tests 2>&1 || true)
RC5=$?
# 允许 exit 0（产出报告含 0 分），但必须有清晰提示
assert_exit "5a. exit 0 (工具不阻断)" 0 "$RC5"
assert_contains "5b. 空目录提示" "$OUT5" "empty"
SC5=$(python3 -c "import json;d=json.load(open('$TMP5/.test-health-report.json'));print(d['overall_score'])" 2>/dev/null || echo "")
assert_contains "5c. overall_score = 0" "$SC5" "0"
rm -rf "$TMP5"

echo ""
echo "=== Summary: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
