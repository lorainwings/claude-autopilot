#!/usr/bin/env bash
# test_phase1_clarification.sh — Section 15: Phase 1 定向澄清 + BA 输出约束 + 复杂度多维度
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/_test_helpers.sh"

PHASE1_REQ="$PLUGIN_DIR/skills/autopilot/references/phase1-requirements.md"
PHASE1_DETAIL="$PLUGIN_DIR/skills/autopilot/references/phase1-requirements-detail.md"

echo "--- 15. Phase 1 定向澄清 + BA 约束 + 复杂度多维度 ---"

# ============================================================
# 15a-c: 定向澄清触发规则 (flags >= 2)
# ============================================================

# 15a. flags >= 2 触发定向澄清预检
if grep -q 'flags >= 2.*定向澄清' "$PHASE1_REQ"; then
  green "  PASS: 15a. flags >= 2 triggers 定向澄清预检"
  PASS=$((PASS + 1))
else
  red "  FAIL: 15a. flags >= 2 定向澄清预检 trigger rule not found"
  FAIL=$((FAIL + 1))
fi

# 15b. 新检测维度: no_scope_boundary
if grep -q 'no_scope_boundary' "$PHASE1_REQ"; then
  green "  PASS: 15b. detection dimension no_scope_boundary exists"
  PASS=$((PASS + 1))
else
  red "  FAIL: 15b. detection dimension no_scope_boundary missing"
  FAIL=$((FAIL + 1))
fi

# 15c. 检测维度: no_acceptance_criteria 存在（v5.7: no_target_entity 已合并入 no_scope_boundary）
if grep -q 'no_acceptance_criteria' "$PHASE1_REQ"; then
  green "  PASS: 15c. detection dimension no_acceptance_criteria exists"
  PASS=$((PASS + 1))
else
  red "  FAIL: 15c. detection dimension no_acceptance_criteria missing"
  FAIL=$((FAIL + 1))
fi

# 15d. 定向澄清最多 3 个问题约束
if grep -q 'clarification_questions\[:3\]' "$PHASE1_REQ" || grep -q '最大问题数.*3' "$PHASE1_REQ"; then
  green "  PASS: 15d. clarification limited to max 3 questions"
  PASS=$((PASS + 1))
else
  red "  FAIL: 15d. max 3 questions constraint not found"
  FAIL=$((FAIL + 1))
fi

# 15e. flags >= 3 强制预循环仍保留
if grep -q 'flags >= 3.*强制.*预循环' "$PHASE1_REQ"; then
  green "  PASS: 15e. flags >= 3 forced pre-loop preserved"
  PASS=$((PASS + 1))
else
  red "  FAIL: 15e. flags >= 3 forced pre-loop rule not found"
  FAIL=$((FAIL + 1))
fi

# ============================================================
# 15f-h: BA 输出约束
# ============================================================

# 15f. BA 强制输出字段完整性
BA_FIELDS_OK=true
for field in goal scope non_goals acceptance_criteria decision_points assumptions risks; do
  if ! grep -q "\`$field\`" "$PHASE1_DETAIL"; then
    BA_FIELDS_OK=false
    break
  fi
done
if [ "$BA_FIELDS_OK" = "true" ]; then
  green "  PASS: 15f. BA mandatory output fields complete (goal/scope/non_goals/acceptance_criteria/decision_points/assumptions/risks)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 15f. BA mandatory output fields incomplete"
  FAIL=$((FAIL + 1))
fi

# 15g. open_questions → decision_points 映射规则
if grep -q 'open_question.*未映射.*decision_point' "$PHASE1_DETAIL" || grep -q 'open_questions.*decision_points.*映射' "$PHASE1_DETAIL"; then
  green "  PASS: 15g. open_questions → decision_points mapping rule exists"
  PASS=$((PASS + 1))
else
  red "  FAIL: 15g. open_questions → decision_points mapping rule not found"
  FAIL=$((FAIL + 1))
fi

# 15h. 缺失字段时拒绝放行
if grep -q '拒绝放行\|BLOCK.*BA.*不完整\|RE-DISPATCH.*补充' "$PHASE1_DETAIL"; then
  green "  PASS: 15h. missing fields block gate enforced"
  PASS=$((PASS + 1))
else
  red "  FAIL: 15h. missing fields block gate not found"
  FAIL=$((FAIL + 1))
fi

# ============================================================
# 15i-k: 复杂度多维度评估
# ============================================================

# 15i. 复杂度不能只依赖 total_files
if grep -q '不能仅依赖 total_files\|不能只依赖 total_files' "$PHASE1_DETAIL"; then
  green "  PASS: 15i. complexity assessment not solely based on total_files"
  PASS=$((PASS + 1))
else
  red "  FAIL: 15i. total_files sole dependency warning not found"
  FAIL=$((FAIL + 1))
fi

# 15j. 新维度: cross_module, high_risk_domain, new_dependency, non_functional_constraint, multi_decision
COMPLEXITY_DIMS_OK=true
for dim in cross_module high_risk_domain new_dependency non_functional_constraint multi_decision; do
  if ! grep -q "$dim" "$PHASE1_DETAIL"; then
    COMPLEXITY_DIMS_OK=false
    red "  (missing dimension: $dim)"
    break
  fi
done
if [ "$COMPLEXITY_DIMS_OK" = "true" ]; then
  green "  PASS: 15j. all 5 complexity dimensions present (cross_module/high_risk_domain/new_dependency/non_functional_constraint/multi_decision)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 15j. complexity dimensions incomplete"
  FAIL=$((FAIL + 1))
fi

# 15k. 高风险域单独命中 small→medium 规则
if grep -q 'high_risk_domain.*small.*medium\|高风险域.*不允许 small\|high_risk_domain.*complexity == "small"' "$PHASE1_DETAIL"; then
  green "  PASS: 15k. high_risk_domain prevents small classification"
  PASS=$((PASS + 1))
else
  red "  FAIL: 15k. high_risk_domain → small prevention rule not found"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0
