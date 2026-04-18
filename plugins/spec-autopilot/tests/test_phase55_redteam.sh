#!/usr/bin/env bash
# test_phase55_redteam.sh — autopilot-phase5.5-redteam skill + feedback-loop-inject.sh 验收测试
# TEST_LAYER: behavior

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TEST_DIR/.." && pwd)"
INJECT_SCRIPT="$PLUGIN_ROOT/runtime/scripts/feedback-loop-inject.sh"
SKILL_FILE="$PLUGIN_ROOT/skills/autopilot-phase5.5-redteam/SKILL.md"
PROMPT_DOC="$PLUGIN_ROOT/skills/autopilot-phase5.5-redteam/references/redteam-prompts.md"
VAULT_README="$PLUGIN_ROOT/docs/regression-vault/README.md"

# shellcheck source=_test_helpers.sh
. "$TEST_DIR/_test_helpers.sh"

echo "=== test_phase55_redteam ==="

# --- 1. 静态资产 ---
assert_file_exists "phase5.5 SKILL.md" "$SKILL_FILE"
assert_file_exists "redteam-prompts.md" "$PROMPT_DOC"
assert_file_exists "regression-vault README.md" "$VAULT_README"
assert_file_exists "feedback-loop-inject.sh" "$INJECT_SCRIPT"

# --- 2. SKILL frontmatter 标识 ---
assert_file_contains "SKILL has ONLY for autopilot prefix" "$SKILL_FILE" "ONLY for autopilot orchestrator"
assert_file_contains "SKILL declares phase 5.5" "$SKILL_FILE" "5.5"
assert_file_contains "redteam-prompts has all 5 categories" "$PROMPT_DOC" "boundary"
assert_file_contains "redteam-prompts mentions concurrency" "$PROMPT_DOC" "concurrency"
assert_file_contains "redteam-prompts mentions state-pollution" "$PROMPT_DOC" "state-pollution"
assert_file_contains "redteam-prompts mentions dependency-regression" "$PROMPT_DOC" "dependency-regression"
assert_file_contains "redteam-prompts mentions backward-incompat" "$PROMPT_DOC" "backward-incompat"

# --- 3. regression-vault README 含命名规范与必备章节 ---
assert_file_contains "vault README has naming convention" "$VAULT_README" "YYYYMMDD"
assert_file_contains "vault README requires Reproducer" "$VAULT_README" "Reproducer"

# --- 4. shellcheck inject script ---
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck "$INJECT_SCRIPT" >/dev/null 2>&1; then
    green "  PASS: feedback-loop-inject.sh shellcheck clean"
    PASS=$((PASS + 1))
  else
    red "  FAIL: feedback-loop-inject.sh shellcheck failed"
    FAIL=$((FAIL + 1))
  fi
fi

# --- 5. inject 行为 3 用例 ---
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

CTX_DIR="$TMPDIR/openspec/changes/c1/context"
mkdir -p "$CTX_DIR"

# 用例 A: 无报告 → 输出空数组 []
out_a=$("$INJECT_SCRIPT" --change-root "$TMPDIR/openspec/changes/c1" --phase 5 2>/dev/null)
exit_a=$?
assert_exit "Case A: missing report → exit 0 + []" 0 "$exit_a"
if [ "$(echo "$out_a" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")" = "0" ]; then
  green "  PASS: Case A returns empty array"
  PASS=$((PASS + 1))
else
  red "  FAIL: Case A non-empty output: $out_a"
  FAIL=$((FAIL + 1))
fi

# 用例 B: 有 warn + block → 都进入 prior_risks
cat >"$CTX_DIR/risk-report-phase5.json" <<'EOF'
{
  "phase": 5,
  "rubric_version": 1,
  "requirement_type": "feat",
  "scored_rubrics": [
    {"check_id":"P5-FEAT-001","severity":"block","passed":false,"evidence":"x","reasoning":"missing test"},
    {"check_id":"P5-FEAT-004","severity":"warn","passed":false,"evidence":"y","reasoning":"no type ann"},
    {"check_id":"P5-FEAT-005","severity":"block","passed":true,"evidence":"z","reasoning":"ok"}
  ],
  "blocking_count": 1,
  "warning_count": 1,
  "recommendation": "block_phase_advance",
  "generated_at": "2026-04-18T10:00:00Z"
}
EOF
out_b=$("$INJECT_SCRIPT" --change-root "$TMPDIR/openspec/changes/c1" --phase 5 2>/dev/null)
exit_b=$?
assert_exit "Case B: report parsed → exit 0" 0 "$exit_b"
count_b=$(echo "$out_b" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
if [ "$count_b" = "2" ]; then
  green "  PASS: Case B returns 2 risks (block+warn, skip passed)"
  PASS=$((PASS + 1))
else
  red "  FAIL: Case B expected 2 got $count_b: $out_b"
  FAIL=$((FAIL + 1))
fi
assert_contains "Case B contains P5-FEAT-001" "$out_b" "P5-FEAT-001"
assert_contains "Case B contains P5-FEAT-004" "$out_b" "P5-FEAT-004"

# 用例 C: 全 pass → 输出空数组
cat >"$CTX_DIR/risk-report-phase5.json" <<'EOF'
{
  "phase": 5,
  "rubric_version": 1,
  "requirement_type": "feat",
  "scored_rubrics": [
    {"check_id":"P5-FEAT-001","severity":"block","passed":true,"evidence":"x","reasoning":"ok"}
  ],
  "blocking_count": 0,
  "warning_count": 0,
  "recommendation": "proceed",
  "generated_at": "2026-04-18T10:00:00Z"
}
EOF
out_c=$("$INJECT_SCRIPT" --change-root "$TMPDIR/openspec/changes/c1" --phase 5 2>/dev/null)
count_c=$(echo "$out_c" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
if [ "$count_c" = "0" ]; then
  green "  PASS: Case C returns empty array"
  PASS=$((PASS + 1))
else
  red "  FAIL: Case C expected 0 got $count_c"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=== test_phase55_redteam: PASS=$PASS FAIL=$FAIL ==="
[ "$FAIL" -eq 0 ]
