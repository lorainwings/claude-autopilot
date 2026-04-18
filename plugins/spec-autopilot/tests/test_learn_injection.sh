#!/usr/bin/env bash
# test_learn_injection.sh — Phase 0 教训注入测试
# 覆盖：空语料返回 [] / 有历史返回 top-3 / 损坏 JSON 忽略
set -euo pipefail

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_DIR="$TEST_DIR/../runtime/scripts"

# shellcheck source=_test_helpers.sh
source "$TEST_DIR/_test_helpers.sh"

echo "=== learn-inject-top-lessons.sh ==="

TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# ────────────────────────────────────────
# 1. 空语料：root 不存在 → 返回 []
# ────────────────────────────────────────
echo "--- 1. empty corpus → [] ---"
out=$(bash "$SCRIPT_DIR/learn-inject-top-lessons.sh" \
  --raw-requirement "构建新功能" \
  --episodes-root "$TMPDIR_ROOT/no-such-dir" 2>/dev/null)
# 空数组 JSON 字面量比较
trimmed=$(printf '%s' "$out" | tr -d ' \n\r\t')
if [ "$trimmed" = "[]" ]; then
  green "  PASS: 1a. empty corpus returns []"
  PASS=$((PASS + 1))
else
  red "  FAIL: 1a. expected [], got '$out'"
  FAIL=$((FAIL + 1))
fi

# 空目录但存在
mkdir -p "$TMPDIR_ROOT/empty-root"
out=$(bash "$SCRIPT_DIR/learn-inject-top-lessons.sh" \
  --raw-requirement "x" --episodes-root "$TMPDIR_ROOT/empty-root" 2>/dev/null)
trimmed=$(printf '%s' "$out" | tr -d ' \n\r\t')
if [ "$trimmed" = "[]" ]; then
  green "  PASS: 1b. empty dir returns []"
  PASS=$((PASS + 1))
else
  red "  FAIL: 1b. expected [], got '$out'"
  FAIL=$((FAIL + 1))
fi

# ────────────────────────────────────────
# 2. 有历史失败 episode：返回 top-3 教训
# ────────────────────────────────────────
echo "--- 2. with episodes returns top-3 ---"
EPROOT="$TMPDIR_ROOT/reports"
mkdir -p "$EPROOT/v1/episodes" "$EPROOT/v2/episodes"

# 失败模式 A 命中 3 次
for i in 1 2 3; do
  cat >"$EPROOT/v1/episodes/phase5-a$i.json" <<JSON
{
  "version": "1.0",
  "run_id": "r-a-$i",
  "phase": "phase5",
  "phase_name": "implement",
  "mode": "parallel",
  "goal": "g",
  "timestamp_start": "2026-04-1${i}T00:00:00Z",
  "timestamp_end": "2026-04-1${i}T00:01:00Z",
  "duration_ms": 60000,
  "gate_result": "blocked",
  "actions": [],
  "failure_trace": {"root_cause": "file_ownership_overlap", "failed_gate": "merge-guard", "evidence": "x"},
  "reflection": "Observation: overlap\nReasoning: bad plan\nPlan: dry-run dag"
}
JSON
done

# 失败模式 B 命中 1 次
cat >"$EPROOT/v2/episodes/phase4-b.json" <<'JSON'
{
  "version": "1.0",
  "run_id": "r-b",
  "phase": "phase4",
  "phase_name": "testcase",
  "mode": "tdd",
  "goal": "g",
  "timestamp_start": "2026-04-15T00:00:00Z",
  "timestamp_end": "2026-04-15T00:01:00Z",
  "duration_ms": 60000,
  "gate_result": "failed",
  "actions": [],
  "failure_trace": {"root_cause": "tdd_red_skipped", "failed_gate": "verify-test-driven-l2", "evidence": "no red phase"},
  "reflection": "Observation: red skipped\nReasoning: agent shortcut\nPlan: enforce red gate"
}
JSON

out=$(bash "$SCRIPT_DIR/learn-inject-top-lessons.sh" \
  --raw-requirement "新需求" --episodes-root "$EPROOT" --top 3 2>/dev/null)
assert_contains "2a. contains lesson_id field" "$out" "lesson_id"
assert_contains "2b. contains injection_text field" "$out" "injection_text"
assert_contains "2c. file_ownership_overlap appears (top hit)" "$out" "file_ownership_overlap"
assert_contains "2d. tdd_red_skipped appears" "$out" "tdd_red_skipped"
# 验证 evidence_count 排序：file_ownership_overlap 应排前
top_id=$(python3 -c "import json,sys;a=json.loads(sys.argv[1]);print(a[0]['evidence_count'] if a else 0)" "$out" 2>/dev/null || echo 0)
if [ "$top_id" = "3" ]; then
  green "  PASS: 2e. top hit has evidence_count=3"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2e. top evidence_count expected 3, got $top_id"
  FAIL=$((FAIL + 1))
fi

# ────────────────────────────────────────
# 3. 损坏 JSON：忽略不报错
# ────────────────────────────────────────
echo "--- 3. corrupted episode is ignored ---"
EPROOT2="$TMPDIR_ROOT/reports2"
mkdir -p "$EPROOT2/v1/episodes"
echo "this is not json {{{" >"$EPROOT2/v1/episodes/broken.json"
# 添加一个有效失败 episode
cat >"$EPROOT2/v1/episodes/good.json" <<'JSON'
{
  "version": "1.0",
  "run_id": "r-good",
  "phase": "phase5",
  "phase_name": "implement",
  "mode": "serial",
  "goal": "g",
  "timestamp_start": "2026-04-18T00:00:00Z",
  "timestamp_end": "2026-04-18T00:01:00Z",
  "duration_ms": 60000,
  "gate_result": "blocked",
  "actions": [],
  "failure_trace": {"root_cause": "x", "failed_gate": "y", "evidence": "z"},
  "reflection": "r"
}
JSON

set +e
out=$(bash "$SCRIPT_DIR/learn-inject-top-lessons.sh" \
  --raw-requirement "x" --episodes-root "$EPROOT2" 2>/dev/null)
code=$?
set -e
assert_exit "3a. corrupted file does not crash → exit 0" 0 "$code"
assert_contains "3b. valid episode still processed" "$out" "lesson_id"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
