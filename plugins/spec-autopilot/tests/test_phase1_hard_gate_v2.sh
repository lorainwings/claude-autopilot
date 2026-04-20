#!/usr/bin/env bash
# test_phase1_hard_gate_v2.sh — Phase 1→2 三重校验 (check-phase1-gate.sh)
# 任务 B10: clarification + confidence + conflicts 跨路硬约束

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

GATE="$SCRIPT_DIR/check-phase1-gate.sh"

echo "=== Phase 1→2 Hard Gate v2 (triple validation) ==="
echo ""
setup_autopilot_fixture

# --- 临时工件目录 ---
WORK_DIR=$(mktemp -d -t phase1-gate-v2.XXXXXX)
trap 'rm -rf "$WORK_DIR"; teardown_autopilot_fixture' EXIT

REQ_MD="$WORK_DIR/requirements.md"
VERDICT_JSON="$WORK_DIR/verdict.json"
PACKET_JSON="$WORK_DIR/packet.json"

# helper: 写入一组 baseline clean 工件（每个 case 可按需覆盖）
write_clean_fixture() {
  cat >"$REQ_MD" <<'EOF'
# Requirements Analysis
所有需求点已澄清，无遗留模糊项。
EOF
  cat >"$VERDICT_JSON" <<'EOF'
{
  "coverage_ok": true,
  "conflicts": [],
  "confidence": 0.85,
  "requires_human": false,
  "ambiguities": [],
  "rationale": "所有维度均一致",
  "merged_decision_points": []
}
EOF
  cat >"$PACKET_JSON" <<'EOF'
{
  "requirement_type": "feature",
  "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
}
EOF
}

# --- Test 0: 脚本可执行 ---
echo "0. 脚本存在且可执行"
if [ -x "$GATE" ]; then
  green "  PASS: 0a. check-phase1-gate.sh 可执行"
  PASS=$((PASS + 1))
else
  red "  FAIL: 0a. check-phase1-gate.sh 不存在或不可执行 ($GATE)"
  FAIL=$((FAIL + 1))
fi

# --- Test 1: requirements.md 含 [NEEDS CLARIFICATION → 阻断 ---
echo ""
echo "1. requirements.md 含 [NEEDS CLARIFICATION] → block"
write_clean_fixture
cat >"$REQ_MD" <<'EOF'
# Requirements Analysis
- 用户登录方式 [NEEDS CLARIFICATION: SSO 还是密码？]
EOF
exit_code=0
output=$("$GATE" --requirements "$REQ_MD" --verdict "$VERDICT_JSON" --packet "$PACKET_JSON" 2>&1) || exit_code=$?
assert_exit "1a. clarification 残留 → exit 1" 1 $exit_code
assert_contains "1b. 报错提及 clarification" "$output" "CLARIFICATION"

# --- Test 2: confidence 低于阈值 → 阻断 ---
echo ""
echo "2. verdict.confidence=0.4 (< 0.7) → block"
write_clean_fixture
cat >"$VERDICT_JSON" <<'EOF'
{
  "coverage_ok": true,
  "conflicts": [],
  "confidence": 0.4,
  "requires_human": false,
  "ambiguities": [],
  "rationale": "信心不足",
  "merged_decision_points": []
}
EOF
exit_code=0
output=$("$GATE" --requirements "$REQ_MD" --verdict "$VERDICT_JSON" --packet "$PACKET_JSON" 2>&1) || exit_code=$?
assert_exit "2a. low confidence → exit 1" 1 $exit_code
assert_contains "2b. 报错提及 confidence" "$output" "confidence"

# --- Test 3: conflicts 含 irreconcilable → 阻断 ---
echo ""
echo "3. verdict.conflicts 含 resolution=irreconcilable → block"
write_clean_fixture
cat >"$VERDICT_JSON" <<'EOF'
{
  "coverage_ok": true,
  "conflicts": [
    {
      "topic": "存储方案",
      "positions": [
        {"source": "scan", "claim": "用 Postgres"},
        {"source": "research", "claim": "用 Mongo"}
      ],
      "resolution": "irreconcilable"
    }
  ],
  "confidence": 0.9,
  "requires_human": true,
  "ambiguities": [],
  "rationale": "存储方案对立，需人裁",
  "merged_decision_points": []
}
EOF
exit_code=0
output=$("$GATE" --requirements "$REQ_MD" --verdict "$VERDICT_JSON" --packet "$PACKET_JSON" 2>&1) || exit_code=$?
assert_exit "3a. irreconcilable conflict → exit 1" 1 $exit_code
assert_contains "3b. 报错提及 conflict" "$output" "conflict"

# --- Test 4: clean state → 通过 ---
echo ""
echo "4. clean state (no clarification + confidence 0.85 + 无 conflicts + sha256 存在) → pass"
write_clean_fixture
exit_code=0
output=$("$GATE" --requirements "$REQ_MD" --verdict "$VERDICT_JSON" --packet "$PACKET_JSON" 2>&1) || exit_code=$?
assert_exit "4a. clean state → exit 0" 0 $exit_code
assert_not_contains "4b. clean state 不含 BLOCK" "$output" "BLOCK"

# --- Test 5: packet.sha256 缺失 → 阻断 ---
echo ""
echo "5. packet 缺 sha256 → block"
write_clean_fixture
cat >"$PACKET_JSON" <<'EOF'
{
  "requirement_type": "feature"
}
EOF
exit_code=0
output=$("$GATE" --requirements "$REQ_MD" --verdict "$VERDICT_JSON" --packet "$PACKET_JSON" 2>&1) || exit_code=$?
assert_exit "5a. packet 缺 sha256 → exit 1" 1 $exit_code
assert_contains "5b. 报错提及 sha256" "$output" "sha256"

# --- Test 6: 自定义阈值 ---
echo ""
echo "6. --threshold 0.5 时 confidence=0.6 → pass"
write_clean_fixture
cat >"$VERDICT_JSON" <<'EOF'
{
  "coverage_ok": true,
  "conflicts": [],
  "confidence": 0.6,
  "requires_human": false,
  "ambiguities": [],
  "rationale": "中等置信",
  "merged_decision_points": []
}
EOF
exit_code=0
output=$("$GATE" --requirements "$REQ_MD" --verdict "$VERDICT_JSON" --packet "$PACKET_JSON" --threshold 0.5 2>&1) || exit_code=$?
assert_exit "6a. confidence 0.6 vs threshold 0.5 → exit 0" 0 $exit_code

# --- Test 7: confidence 恰好等于阈值（边界）→ 通过 ---
echo ""
echo "7. confidence==threshold (0.7==0.7) → pass"
write_clean_fixture
cat >"$VERDICT_JSON" <<'EOF'
{
  "coverage_ok": true,
  "conflicts": [],
  "confidence": 0.7,
  "requires_human": false,
  "ambiguities": [],
  "rationale": "刚好达到阈值",
  "merged_decision_points": []
}
EOF
exit_code=0
output=$("$GATE" --requirements "$REQ_MD" --verdict "$VERDICT_JSON" --packet "$PACKET_JSON" 2>&1) || exit_code=$?
assert_exit "7a. confidence == threshold → exit 0" 0 $exit_code

# --- Test 8: conflicts 含 adopted/deferred 但无 irreconcilable → 通过 ---
echo ""
echo "8. conflicts 仅含 adopted/deferred → pass"
write_clean_fixture
cat >"$VERDICT_JSON" <<'EOF'
{
  "coverage_ok": true,
  "conflicts": [
    {"topic": "x", "positions": [{"source":"scan","claim":"a"},{"source":"research","claim":"b"}], "resolution": "adopted", "chosen": "a"},
    {"topic": "y", "positions": [{"source":"scan","claim":"c"},{"source":"user","claim":"d"}], "resolution": "deferred_to_user"}
  ],
  "confidence": 0.85,
  "requires_human": false,
  "ambiguities": [],
  "rationale": "已解决或挂起",
  "merged_decision_points": []
}
EOF
exit_code=0
output=$("$GATE" --requirements "$REQ_MD" --verdict "$VERDICT_JSON" --packet "$PACKET_JSON" 2>&1) || exit_code=$?
assert_exit "8a. resolved conflicts → exit 0" 0 $exit_code

# --- Test 9: 缺失输入文件 → 阻断 ---
echo ""
echo "9. verdict 文件不存在 → block"
write_clean_fixture
exit_code=0
output=$("$GATE" --requirements "$REQ_MD" --verdict "$WORK_DIR/missing.json" --packet "$PACKET_JSON" 2>&1) || exit_code=$?
assert_exit "9a. missing verdict → exit 1" 1 $exit_code

# --- Test 10: --threshold 非法值 → exit 2 + stderr ---
echo ""
echo "10. --threshold abc → exit 2 (silent failure 防御)"
write_clean_fixture
exit_code=0
output=$("$GATE" --requirements "$REQ_MD" --verdict "$VERDICT_JSON" --packet "$PACKET_JSON" --threshold abc 2>&1) || exit_code=$?
assert_exit "10a. invalid threshold → exit 2" 2 $exit_code
assert_contains "10b. stderr 含 'invalid threshold'" "$output" "invalid threshold"

# --- Test 11: config 阈值生效 ---
echo ""
echo "11. config phases.requirements.gate.confidence_threshold=0.95, verdict.confidence=0.85 → block"
write_clean_fixture
CFG_DIR="$WORK_DIR/.claude"
mkdir -p "$CFG_DIR"
CFG="$CFG_DIR/autopilot.config.yaml"
cat >"$CFG" <<'EOF'
phases:
  requirements:
    gate:
      confidence_threshold: 0.95
EOF
exit_code=0
output=$("$GATE" --requirements "$REQ_MD" --verdict "$VERDICT_JSON" --packet "$PACKET_JSON" --config "$CFG" 2>&1) || exit_code=$?
assert_exit "11a. config 0.95 vs confidence 0.85 → exit 1" 1 $exit_code
assert_contains "11b. stderr 提及阈值 0.95" "$output" "0.95"

# --- Test 12: CLI 覆写 config ---
echo ""
echo "12. config 0.95 + CLI --threshold 0.7 + confidence 0.85 → pass"
write_clean_fixture
exit_code=0
output=$("$GATE" --requirements "$REQ_MD" --verdict "$VERDICT_JSON" --packet "$PACKET_JSON" --config "$CFG" --threshold 0.7 2>&1) || exit_code=$?
assert_exit "12a. CLI 0.7 覆写 config 0.95 → exit 0" 0 $exit_code
assert_contains "12b. PASSED 标记 source=cli" "$output" "source=cli"

# --- Test 13: 无 config → 用默认 0.7 ---
echo ""
echo "13. 无 config (--config 指向不存在的文件), confidence 0.85 → pass"
write_clean_fixture
exit_code=0
output=$("$GATE" --requirements "$REQ_MD" --verdict "$VERDICT_JSON" --packet "$PACKET_JSON" --config "$WORK_DIR/no-such-config.yaml" 2>&1) || exit_code=$?
assert_exit "13a. missing config → exit 0 (默认 0.7)" 0 $exit_code

# --- Test 14: config 中阈值非法 → exit 2 ---
echo ""
echo "14. config confidence_threshold=abc → exit 2"
write_clean_fixture
cat >"$CFG" <<'EOF'
phases:
  requirements:
    gate:
      confidence_threshold: abc
EOF
exit_code=0
output=$("$GATE" --requirements "$REQ_MD" --verdict "$VERDICT_JSON" --packet "$PACKET_JSON" --config "$CFG" 2>&1) || exit_code=$?
assert_exit "14a. config 非法阈值 → exit 2" 2 $exit_code
assert_contains "14b. stderr 含 'invalid threshold'" "$output" "invalid threshold"

echo ""
echo "=============================="
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
