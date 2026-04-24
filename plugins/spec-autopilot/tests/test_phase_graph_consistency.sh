#!/usr/bin/env bash
# test_phase_graph_consistency.sh — 验证 _phase_graph.py 与 _common.sh 的 phase 推断一致
# Codex 评审步骤 6: 确保 scan-checkpoints, save-state, recovery-decision 统一使用 _phase_graph.py

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$TEST_DIR/../runtime/scripts"
source "$TEST_DIR/_test_helpers.sh"

echo "=== Phase Graph Consistency Tests ==="
echo ""

# --- Test 1: _phase_graph.py self-test ---
echo "1. _phase_graph.py 内置自测"
python3 "$SCRIPT_DIR/_phase_graph.py" --test 2>&1
code=$?
assert_exit "1. _phase_graph.py --test" 0 "$code"

# --- Test 2: Gap-aware 语义一致性 ---
echo ""
echo "2. Gap-aware 语义: P1=ok P2=failed P3=ok → last_valid=1"
TMP=$(mktemp -d)
echo '{"status":"ok","summary":"test"}' >"$TMP/phase-1-req.json"
echo '{"status":"failed","summary":"test"}' >"$TMP/phase-2-spec.json"
echo '{"status":"ok","summary":"test"}' >"$TMP/phase-3-ff.json"

# _phase_graph.py
PG_RESULT=$(python3 "$SCRIPT_DIR/_phase_graph.py" get_last_valid "$TMP" full)
assert_exit "2a. _phase_graph.py get_last_valid exit" 0 $?

# _common.sh::get_last_valid_phase
source "$SCRIPT_DIR/_common.sh"
COMMON_RESULT=$(get_last_valid_phase "$TMP" full)

if [ "$PG_RESULT" = "$COMMON_RESULT" ]; then
  green "  PASS: 2b. _phase_graph ($PG_RESULT) == _common.sh ($COMMON_RESULT)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2b. _phase_graph ($PG_RESULT) != _common.sh ($COMMON_RESULT)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMP"

# --- Test 3: Mode-aware phase sequence 一致性 ---
echo ""
echo "3. Mode-aware phase sequence"
for mode in full lite minimal; do
  SEQ=$(python3 "$SCRIPT_DIR/_phase_graph.py" get_phase_sequence "$mode" 2>/dev/null)
  assert_not_contains "3. $mode sequence non-empty" "$SEQ" '^\[\]$'
done

# --- Test 4: next_phase 边界 ---
echo ""
echo "4. next_phase 边界"
NP=$(python3 "$SCRIPT_DIR/_phase_graph.py" get_next_phase 7 full)
if [ "$NP" = "done" ]; then
  green "  PASS: 4a. next_phase after 7 (full) = done"
  PASS=$((PASS + 1))
else
  red "  FAIL: 4a. next_phase after 7 (full) expected 'done', got '$NP'"
  FAIL=$((FAIL + 1))
fi

NP_LITE=$(python3 "$SCRIPT_DIR/_phase_graph.py" get_next_phase 1 lite)
if [ "$NP_LITE" = "5" ]; then
  green "  PASS: 4b. next_phase after 1 (lite) = 5"
  PASS=$((PASS + 1))
else
  red "  FAIL: 4b. next_phase after 1 (lite) expected '5', got '$NP_LITE'"
  FAIL=$((FAIL + 1))
fi

# --- Test 5: scan-checkpoints 引用 _phase_graph ---
echo ""
echo "5. scan-checkpoints-on-start.sh 引用 _phase_graph.py"
if grep -q "_phase_graph.py" "$SCRIPT_DIR/scan-checkpoints-on-start.sh"; then
  green "  PASS: 5a. scan-checkpoints references _phase_graph.py"
  PASS=$((PASS + 1))
else
  red "  FAIL: 5a. scan-checkpoints does NOT reference _phase_graph.py"
  FAIL=$((FAIL + 1))
fi

# --- Test 6: save-state 引用 _phase_graph ---
echo ""
echo "6. save-state-before-compact.sh 引用 _phase_graph"
if grep -q "import _phase_graph" "$SCRIPT_DIR/save-state-before-compact.sh"; then
  green "  PASS: 6a. save-state imports _phase_graph"
  PASS=$((PASS + 1))
else
  red "  FAIL: 6a. save-state does NOT import _phase_graph"
  FAIL=$((FAIL + 1))
fi

# --- Test 7: recovery-decision 引用 _phase_graph ---
echo ""
echo "7. recovery-decision.sh 引用 _phase_graph"
if grep -q "import _phase_graph" "$SCRIPT_DIR/recovery-decision.sh"; then
  green "  PASS: 7a. recovery-decision imports _phase_graph"
  PASS=$((PASS + 1))
else
  red "  FAIL: 7a. recovery-decision does NOT import _phase_graph"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=============================="
echo "Phase Graph Consistency: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
