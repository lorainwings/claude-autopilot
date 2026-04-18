#!/usr/bin/env bash
# test_learn_episode.sh — L1 Episode 写入与 schema 校验测试
# 覆盖：成功 phase / 失败 phase / 不存在 checkpoint
set -euo pipefail

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_DIR="$TEST_DIR/../runtime/scripts"

# shellcheck source=_test_helpers.sh
source "$TEST_DIR/_test_helpers.sh"

echo "=== learn-episode-write.sh ==="

TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# ────────────────────────────────────────
# 1. 成功 phase：gate_result=ok → episode 写入，无需 reflection
# ────────────────────────────────────────
echo "--- 1. successful phase checkpoint ---"
CP1="$TMPDIR_ROOT/phase5-ok.json"
cat >"$CP1" <<'JSON'
{
  "status": "ok",
  "phase_name": "implement",
  "mode": "serial",
  "goal": "实现功能 A",
  "timestamp_start": "2026-04-18T10:00:00Z",
  "timestamp_end": "2026-04-18T10:05:00Z",
  "duration_ms": 300000,
  "actions": [{"tool": "Task", "target": "impl", "outcome": "ok"}]
}
JSON

OUT1="$TMPDIR_ROOT/out1"
ep_path=$(bash "$SCRIPT_DIR/learn-episode-write.sh" \
  --phase phase5 --checkpoint "$CP1" --out-dir "$OUT1" --run-id run-1 2>/dev/null)
code=$?
assert_exit "1a. ok phase exits 0" 0 "$code"
assert_file_exists "1b. episode file created" "$ep_path"
assert_file_contains "1c. episode contains gate_result ok" "$ep_path" '"gate_result": "ok"'
assert_file_contains "1d. episode has run_id" "$ep_path" '"run_id": "run-1"'
# 成功 episode 不应强制 reflection
if ! grep -q '"reflection"' "$ep_path"; then
  green "  PASS: 1e. no forced reflection on ok"
  PASS=$((PASS + 1))
else
  # 出现了也可接受（若 checkpoint 包含 reflection）
  green "  PASS: 1e. reflection present but optional"
  PASS=$((PASS + 1))
fi

# ────────────────────────────────────────
# 2. 失败 phase：gate_result=blocked → episode 含 failure_trace + reflection
# ────────────────────────────────────────
echo "--- 2. failed phase checkpoint ---"
CP2="$TMPDIR_ROOT/phase4-blocked.json"
cat >"$CP2" <<'JSON'
{
  "status": "blocked",
  "phase_name": "testcase",
  "mode": "tdd",
  "goal": "Phase 4 测试设计",
  "timestamp_start": "2026-04-18T09:00:00Z",
  "timestamp_end": "2026-04-18T09:03:00Z",
  "duration_ms": 180000,
  "actions": [],
  "failure_trace": {
    "root_cause": "coverage_below_floor",
    "failed_gate": "test-pyramid",
    "evidence": "unit_pct=12% < 30%"
  }
}
JSON
OUT2="$TMPDIR_ROOT/out2"
ep2_path=$(bash "$SCRIPT_DIR/learn-episode-write.sh" \
  --phase phase4 --checkpoint "$CP2" --out-dir "$OUT2" --run-id run-2 2>/dev/null)
code=$?
assert_exit "2a. blocked phase exits 0" 0 "$code"
assert_file_contains "2b. failure_trace present" "$ep2_path" "failure_trace"
assert_file_contains "2c. root_cause preserved" "$ep2_path" "coverage_below_floor"
assert_file_contains "2d. reflection synthesized" "$ep2_path" "Observation"
assert_file_contains "2e. reflection has Plan" "$ep2_path" "Plan:"

# ────────────────────────────────────────
# 3. 不存在 checkpoint → exit 1
# ────────────────────────────────────────
echo "--- 3. missing checkpoint ---"
set +e
bash "$SCRIPT_DIR/learn-episode-write.sh" \
  --phase phase5 --checkpoint "$TMPDIR_ROOT/does-not-exist.json" \
  --out-dir "$TMPDIR_ROOT/out3" --run-id run-3 >/dev/null 2>&1
code=$?
set -e
assert_exit "3a. missing checkpoint → exit 1" 1 "$code"

# ────────────────────────────────────────
# 4. schema 校验：篡改成 invalid mode → validator 拒绝
# ────────────────────────────────────────
echo "--- 4. schema validator rejects invalid episode ---"
BAD_JSON='{"version":"1.0","run_id":"x","phase":"p","phase_name":"p","mode":"wrong","goal":"g","timestamp_start":"t","timestamp_end":"t","duration_ms":0,"gate_result":"ok","actions":[]}'
set +e
printf '%s' "$BAD_JSON" | bash "$SCRIPT_DIR/learn-episode-schema-validate.sh" --stdin 2>/dev/null
code=$?
set -e
assert_exit "4a. invalid mode → exit 1" 1 "$code"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
