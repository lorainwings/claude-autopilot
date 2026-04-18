#!/usr/bin/env bash
# test_learn_promotion.sh — L3 晋升候选扫描测试
# 覆盖：无候选 / 3 次命中晋升 / 有反例不晋升
set -euo pipefail

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_DIR="$TEST_DIR/../runtime/scripts"

# shellcheck source=_test_helpers.sh
source "$TEST_DIR/_test_helpers.sh"

echo "=== learn-promote-candidate.sh ==="

TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

mk_ep() {
  # mk_ep <file> <phase> <gate> <root_cause> <failed_gate> <timestamp>
  local file="$1" phase="$2" gate="$3" rc="$4" fg="$5" ts="$6"
  if [ "$gate" = "ok" ]; then
    cat >"$file" <<JSON
{
  "version": "1.0",
  "run_id": "r-${RANDOM}",
  "phase": "$phase",
  "phase_name": "$phase",
  "mode": "serial",
  "goal": "g",
  "timestamp_start": "$ts",
  "timestamp_end": "$ts",
  "duration_ms": 1000,
  "gate_result": "ok",
  "actions": [],
  "success_fingerprint": "$rc"
}
JSON
  else
    cat >"$file" <<JSON
{
  "version": "1.0",
  "run_id": "r-${RANDOM}",
  "phase": "$phase",
  "phase_name": "$phase",
  "mode": "serial",
  "goal": "g",
  "timestamp_start": "$ts",
  "timestamp_end": "$ts",
  "duration_ms": 1000,
  "gate_result": "$gate",
  "actions": [],
  "failure_trace": {"root_cause": "$rc", "failed_gate": "$fg", "evidence": "e"},
  "reflection": "Observation: o\nReasoning: r\nPlan: p"
}
JSON
  fi
}

# ────────────────────────────────────────
# 1. 无候选：仅 2 次命中 → 不晋升
# ────────────────────────────────────────
echo "--- 1. below threshold → no candidate ---"
EP1="$TMPDIR_ROOT/scn1/docs/reports"
OUT1="$TMPDIR_ROOT/scn1/candidates"
mkdir -p "$EP1/v1/episodes"
mk_ep "$EP1/v1/episodes/a.json" phase5 blocked "overlap" "merge-guard" "2026-04-18T00:00:01Z"
mk_ep "$EP1/v1/episodes/b.json" phase5 blocked "overlap" "merge-guard" "2026-04-18T00:00:02Z"

out=$(bash "$SCRIPT_DIR/learn-promote-candidate.sh" \
  --episodes-root "$EP1" --out-dir "$OUT1" --threshold 3 2>/dev/null)
promoted=$(python3 -c "import json,sys;print(json.loads(sys.argv[1])['promoted'])" "$out")
if [ "$promoted" = "0" ]; then
  green "  PASS: 1a. 2 hits < threshold 3 → promoted=0"
  PASS=$((PASS + 1))
else
  red "  FAIL: 1a. expected promoted=0, got $promoted"
  FAIL=$((FAIL + 1))
fi

# ────────────────────────────────────────
# 2. 3 次命中 → 晋升候选生成
# ────────────────────────────────────────
echo "--- 2. 3 hits → promoted candidate ---"
EP2="$TMPDIR_ROOT/scn2/docs/reports"
OUT2="$TMPDIR_ROOT/scn2/candidates"
mkdir -p "$EP2/v1/episodes" "$EP2/v2/episodes"
mk_ep "$EP2/v1/episodes/a.json" phase5 blocked "overlap" "merge-guard" "2026-04-18T00:00:01Z"
mk_ep "$EP2/v1/episodes/b.json" phase5 blocked "overlap" "merge-guard" "2026-04-18T00:00:02Z"
mk_ep "$EP2/v2/episodes/c.json" phase5 failed "overlap" "merge-guard" "2026-04-18T00:00:03Z"

out=$(bash "$SCRIPT_DIR/learn-promote-candidate.sh" \
  --episodes-root "$EP2" --out-dir "$OUT2" --threshold 3 2>/dev/null)
promoted=$(python3 -c "import json,sys;print(json.loads(sys.argv[1])['promoted'])" "$out")
if [ "$promoted" = "1" ]; then
  green "  PASS: 2a. 3 hits → promoted=1"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2a. expected promoted=1, got $promoted"
  FAIL=$((FAIL + 1))
fi
# 候选文件存在
cand_count=$(find "$OUT2" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
if [ "$cand_count" = "1" ]; then
  green "  PASS: 2b. exactly 1 candidate markdown written"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2b. expected 1 candidate file, got $cand_count"
  FAIL=$((FAIL + 1))
fi
# 候选包含关键字段
cand_file=$(find "$OUT2" -maxdepth 1 -name '*.md' | head -1)
assert_file_contains "2c. candidate has status pending_review" "$cand_file" "pending_review"
assert_file_contains "2d. candidate has root_cause" "$cand_file" "overlap"
assert_file_contains "2e. candidate has hit_count" "$cand_file" "hit_count: 3"

# ────────────────────────────────────────
# 3. 有反例：3 次失败 + 同 phase 成功 fingerprint → 抵消不晋升
# ────────────────────────────────────────
echo "--- 3. counter-evidence blocks promotion ---"
EP3="$TMPDIR_ROOT/scn3/docs/reports"
OUT3="$TMPDIR_ROOT/scn3/candidates"
mkdir -p "$EP3/v1/episodes"
mk_ep "$EP3/v1/episodes/f1.json" phase5 blocked "overlap" "merge-guard" "2026-04-18T00:00:01Z"
mk_ep "$EP3/v1/episodes/f2.json" phase5 blocked "overlap" "merge-guard" "2026-04-18T00:00:02Z"
mk_ep "$EP3/v1/episodes/f3.json" phase5 blocked "overlap" "merge-guard" "2026-04-18T00:00:03Z"
# 3 次成功 fingerprint 含 root_cause 抵消
mk_ep "$EP3/v1/episodes/s1.json" phase5 ok "overlap" "" "2026-04-18T00:00:04Z"
mk_ep "$EP3/v1/episodes/s2.json" phase5 ok "overlap" "" "2026-04-18T00:00:05Z"
mk_ep "$EP3/v1/episodes/s3.json" phase5 ok "overlap" "" "2026-04-18T00:00:06Z"

out=$(bash "$SCRIPT_DIR/learn-promote-candidate.sh" \
  --episodes-root "$EP3" --out-dir "$OUT3" --threshold 3 2>/dev/null)
promoted=$(python3 -c "import json,sys;print(json.loads(sys.argv[1])['promoted'])" "$out")
if [ "$promoted" = "0" ]; then
  green "  PASS: 3a. counter-evidence cancels → promoted=0"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3a. expected promoted=0, got $promoted"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
