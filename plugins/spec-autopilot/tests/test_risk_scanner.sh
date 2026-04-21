#!/usr/bin/env bash
# test_risk_scanner.sh — autopilot-risk-scanner skill + risk-scan-gate.sh 验收测试
# TEST_LAYER: behavior

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TEST_DIR/.." && pwd)"
GATE_SCRIPT="$PLUGIN_ROOT/runtime/scripts/risk-scan-gate.sh"
RUBRICS_DIR="$PLUGIN_ROOT/skills/autopilot-risk-scanner/references/rubrics"
SCHEMA_DOC="$PLUGIN_ROOT/skills/autopilot-risk-scanner/references/rubric-schema.md"
SKILL_FILE="$PLUGIN_ROOT/skills/autopilot-risk-scanner/SKILL.md"

# shellcheck source=_test_helpers.sh
. "$TEST_DIR/_test_helpers.sh"

echo "=== test_risk_scanner ==="

# --- 1. 静态资产存在性 ---
assert_file_exists "SKILL.md exists" "$SKILL_FILE"
assert_file_exists "rubric-schema.md exists" "$SCHEMA_DOC"
assert_file_exists "gate script exists" "$GATE_SCRIPT"

# --- 2. SKILL.md frontmatter 含必要标识 ---
assert_file_contains "SKILL frontmatter has ONLY for autopilot prefix" "$SKILL_FILE" "ONLY for autopilot orchestrator"
assert_file_contains "SKILL is non-user-invocable" "$SKILL_FILE" "user-invocable: false"

# --- 3. 至少 6 份 rubric YAML ---
RUBRIC_COUNT=$(find "$RUBRICS_DIR" -name '*.yaml' -type f | wc -l | tr -d ' ')
if [ "$RUBRIC_COUNT" -ge 6 ]; then
  green "  PASS: rubric library has >=6 YAML ($RUBRIC_COUNT)"
  PASS=$((PASS + 1))
else
  red "  FAIL: rubric library has only $RUBRIC_COUNT YAML"
  FAIL=$((FAIL + 1))
fi

# --- 4. 每份 YAML 合法且 checks >= 5 ---
for f in "$RUBRICS_DIR"/*.yaml; do
  if python3 -c "import yaml; d=yaml.safe_load(open('$f')); assert 'rubric_version' in d and 'checks' in d and len(d['checks'])>=5" 2>/dev/null; then
    green "  PASS: $(basename "$f") valid (>=5 checks)"
    PASS=$((PASS + 1))
  else
    red "  FAIL: $(basename "$f") invalid or <5 checks"
    FAIL=$((FAIL + 1))
  fi
done

# --- 5. gate 脚本 shellcheck ---
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck "$GATE_SCRIPT" >/dev/null 2>&1; then
    green "  PASS: risk-scan-gate.sh shellcheck clean"
    PASS=$((PASS + 1))
  else
    red "  FAIL: risk-scan-gate.sh shellcheck failed"
    FAIL=$((FAIL + 1))
  fi
fi

# --- 6. gate 行为 3 用例 ---
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

CTX_DIR="$TMPDIR/openspec/changes/test-change/context"
mkdir -p "$CTX_DIR"

# 用例 A: 无报告 → fail-closed
out_a=$("$GATE_SCRIPT" --change-root "$TMPDIR/openspec/changes/test-change" --phase 5 2>&1)
exit_a=$?
assert_exit "Case A: missing report → exit !=0" 2 "$exit_a"
assert_contains "Case A: error mentions missing report" "$out_a" "missing"

# 用例 B: 有 blocking → fail-closed
cat >"$CTX_DIR/risk-report-phase5.json" <<'EOF'
{
  "phase": 5,
  "rubric_version": 1,
  "requirement_type": "feat",
  "scored_rubrics": [
    {"check_id":"P5-FEAT-001","severity":"block","passed":false,"evidence":"x","reasoning":"y"}
  ],
  "blocking_count": 1,
  "warning_count": 0,
  "recommendation": "block_phase_advance",
  "generated_at": "2026-04-18T10:00:00Z"
}
EOF
out_b=$("$GATE_SCRIPT" --change-root "$TMPDIR/openspec/changes/test-change" --phase 5 2>&1)
exit_b=$?
assert_exit "Case B: blocking_count>0 → exit !=0" 1 "$exit_b"
assert_contains "Case B: output mentions blocking" "$out_b" "blocking"

# 用例 C: 全 pass → 放行
cat >"$CTX_DIR/risk-report-phase5.json" <<'EOF'
{
  "phase": 5,
  "rubric_version": 1,
  "requirement_type": "feat",
  "scored_rubrics": [
    {"check_id":"P5-FEAT-001","severity":"block","passed":true,"evidence":"tests/x.sh:1","reasoning":"covered"}
  ],
  "blocking_count": 0,
  "warning_count": 0,
  "recommendation": "proceed",
  "generated_at": "2026-04-18T10:00:00Z"
}
EOF
"$GATE_SCRIPT" --change-root "$TMPDIR/openspec/changes/test-change" --phase 5 >/dev/null 2>&1
exit_c=$?
assert_exit "Case C: all-pass → exit 0" 0 "$exit_c"

# --- Summary ---
echo ""
echo "=== test_risk_scanner: PASS=$PASS FAIL=$FAIL ==="
[ "$FAIL" -eq 0 ]
