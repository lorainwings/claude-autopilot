#!/usr/bin/env bash
# test_phase1_context_isolation.sh — Phase 1 主上下文隔离黑盒测试
# 验证 Phase 1 的上下文隔离红线和 requirement-packet.json 收敛
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/_test_helpers.sh"

PARALLEL_PHASE1="$PLUGIN_DIR/skills/autopilot/references/parallel-phase1.md"
PHASE1_REQ="$PLUGIN_DIR/skills/autopilot-phase1-requirements/references/phase1-requirements.md"
PHASE1_DETAIL="$PLUGIN_DIR/skills/autopilot-phase1-requirements/references/phase1-requirements-detail.md"
DISPATCH_SKILL="$PLUGIN_DIR/skills/autopilot-dispatch/SKILL.md"
VALIDATE_SCRIPT="$PLUGIN_DIR/runtime/scripts/validate-decision-format.sh"

echo "=== Phase 1 Context Isolation Tests ==="
echo ""

# ============================================================
# 1. 上下文隔离红线：parallel-phase1.md 不再要求主线程读取正文
# ============================================================

echo "--- 1. parallel-phase1.md 上下文隔离 ---"

# 1a. 不再包含"主线程合并 research-findings.md"的正文读取指令
if grep -q '主线程合并 research-findings.md' "$PARALLEL_PHASE1"; then
  red "  FAIL: 1a. parallel-phase1.md 仍包含主线程合并 research 正文指令"
  FAIL=$((FAIL + 1))
else
  green "  PASS: 1a. parallel-phase1.md 不再要求主线程合并 research 正文"
  PASS=$((PASS + 1))
fi

# 1b. 包含上下文隔离红线声明
if grep -q '上下文隔离红线' "$PARALLEL_PHASE1"; then
  green "  PASS: 1b. parallel-phase1.md 包含上下文隔离红线声明"
  PASS=$((PASS + 1))
else
  red "  FAIL: 1b. parallel-phase1.md 缺少上下文隔离红线声明"
  FAIL=$((FAIL + 1))
fi

# 1c. 明确禁止 Read(research-findings.md)
if grep -q '禁止.*Read(research-findings.md)' "$PARALLEL_PHASE1" || grep -q '禁止.*Read.*research-findings' "$PARALLEL_PHASE1"; then
  green "  PASS: 1c. 明确禁止主线程 Read research-findings.md"
  PASS=$((PASS + 1))
else
  red "  FAIL: 1c. 未明确禁止主线程 Read research-findings.md"
  FAIL=$((FAIL + 1))
fi

# 1d. 主线程仅消费信封
if grep -q '仅从各 Agent 返回的 JSON 信封' "$PARALLEL_PHASE1" || grep -q '主线程仅消费信封' "$PARALLEL_PHASE1"; then
  green "  PASS: 1d. 主线程仅消费 JSON 信封"
  PASS=$((PASS + 1))
else
  red "  FAIL: 1d. 未明确主线程仅消费 JSON 信封"
  FAIL=$((FAIL + 1))
fi

echo ""

# ============================================================
# 2. dispatch SKILL.md 中 BA prompt 的上下文隔离
# ============================================================

echo "--- 2. dispatch SKILL.md BA prompt 上下文隔离 ---"

# 2a. BA prompt 不再要求主线程注入正文
if grep -A5 'Phase 1.*需求分析' "$DISPATCH_SKILL" | grep -q 'research-findings.md + web-research-findings.md（如存在）+ complexity'; then
  red "  FAIL: 2a. dispatch SKILL.md 仍要求主线程注入 research 正文"
  FAIL=$((FAIL + 1))
else
  green "  PASS: 2a. dispatch SKILL.md 不再要求主线程注入 research 正文"
  PASS=$((PASS + 1))
fi

# 2b. 包含上下文隔离红线声明
if grep -q '上下文隔离红线' "$DISPATCH_SKILL"; then
  green "  PASS: 2b. dispatch SKILL.md 包含上下文隔离红线声明"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2b. dispatch SKILL.md 缺少上下文隔离红线声明"
  FAIL=$((FAIL + 1))
fi

# 2c. BA 改为自行 Read 调研文件
if grep -q 'BA Agent 在自己的执行环境中直接.*Read' "$DISPATCH_SKILL" || grep -q '供 BA 自行 Read' "$DISPATCH_SKILL"; then
  green "  PASS: 2c. BA Agent 自行 Read 调研文件（非主线程注入）"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2c. BA Agent 未改为自行 Read 调研文件"
  FAIL=$((FAIL + 1))
fi

echo ""

# ============================================================
# 3. 需求成熟度三级分类
# ============================================================

echo "--- 3. 需求成熟度驱动调研方案 ---"

# 3a. phase1-requirements.md 包含成熟度三级分类
MATURITY_FOUND=true
for level in clear partial ambiguous; do
  if ! grep -q "\"$level\"" "$PHASE1_REQ" && ! grep -q "\*\*$level\*\*" "$PHASE1_REQ"; then
    MATURITY_FOUND=false
    break
  fi
done
if [ "$MATURITY_FOUND" = "true" ]; then
  green "  PASS: 3a. 需求成熟度三级 (clear/partial/ambiguous) 定义完整"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3a. 需求成熟度三级定义不完整"
  FAIL=$((FAIL + 1))
fi

# 3b. clear 需求不启动三路调研
if grep -q 'clear.*仅.*Auto-Scan\|clear.*轻量' "$PHASE1_REQ" || grep -q 'clear.*仅 Auto-Scan' "$PARALLEL_PHASE1"; then
  green "  PASS: 3b. clear 需求仅 Auto-Scan（不启动三路调研）"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3b. clear 需求未限制为仅 Auto-Scan"
  FAIL=$((FAIL + 1))
fi

# 3c. partial 需求走双路（Task 18: 2D 矩阵 — partial 对应 research_depth=standard）
if grep -q 'partial.*双路\|partial.*Auto-Scan.*技术调研\|partial.*定向\|partial.*standard' "$PHASE1_REQ" || grep -q 'partial.*Auto-Scan.*tech_research' "$PARALLEL_PHASE1"; then
  green "  PASS: 3c. partial 需求走双路调研"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3c. partial 需求未配置双路调研"
  FAIL=$((FAIL + 1))
fi

# 3d. ambiguous 需求走三路（Task 18: 2D 矩阵 — ambiguous 对应 depth=deep + websearch_subtask）
if grep -q 'ambiguous.*三路\|ambiguous.*全启动\|ambiguous.*Auto-Scan.*技术调研.*联网\|ambiguous.*deep.*true' "$PHASE1_REQ" || grep -q 'ambiguous.*三路' "$PARALLEL_PHASE1"; then
  green "  PASS: 3d. ambiguous 需求走三路调研"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3d. ambiguous 需求未配置三路调研"
  FAIL=$((FAIL + 1))
fi

# 3e. parallel-phase1.md 包含成熟度字段写入信封
if grep -q 'requirement_maturity' "$PARALLEL_PHASE1"; then
  green "  PASS: 3e. parallel-phase1.md 包含 requirement_maturity 字段"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3e. parallel-phase1.md 缺少 requirement_maturity 字段"
  FAIL=$((FAIL + 1))
fi

echo ""

# ============================================================
# 4. requirement-packet.json 唯一输出
# ============================================================

echo "--- 4. requirement-packet.json 唯一输出 ---"

# 4a. phase1-requirements.md 定义了 requirement-packet.json
if grep -q 'requirement-packet.json' "$PHASE1_REQ"; then
  green "  PASS: 4a. phase1-requirements.md 定义了 requirement-packet.json"
  PASS=$((PASS + 1))
else
  red "  FAIL: 4a. phase1-requirements.md 未定义 requirement-packet.json"
  FAIL=$((FAIL + 1))
fi

# 4b. requirement-packet.json 包含必要字段
PACKET_FIELDS_OK=true
for field in requirement_type requirement_maturity complexity goal scope non_goals acceptance_criteria decisions open_questions_closed sha256; do
  if ! grep -q "\"$field\"" "$PHASE1_REQ"; then
    PACKET_FIELDS_OK=false
    red "  (missing packet field: $field in phase1-requirements.md)"
    break
  fi
done
if [ "$PACKET_FIELDS_OK" = "true" ]; then
  green "  PASS: 4b. requirement-packet.json 必要字段完整"
  PASS=$((PASS + 1))
else
  red "  FAIL: 4b. requirement-packet.json 必要字段不完整"
  FAIL=$((FAIL + 1))
fi

# 4c. 唯一事实源约束
if grep -q '唯一事实源\|唯一.*可信\|后续.*只认.*requirement-packet' "$PHASE1_REQ" || grep -q '唯一事实源' "$PHASE1_DETAIL"; then
  green "  PASS: 4c. requirement-packet.json 声明为唯一事实源"
  PASS=$((PASS + 1))
else
  red "  FAIL: 4c. requirement-packet.json 未声明为唯一事实源"
  FAIL=$((FAIL + 1))
fi

# 4d. open_questions_closed 必须为 true 才能推进
if grep -q 'open_questions_closed.*true.*推进\|open_questions_closed.*必须为 true' "$PHASE1_REQ" || grep -q 'open_questions_closed.*true' "$PHASE1_DETAIL"; then
  green "  PASS: 4d. open_questions 必须闭合后才能推进"
  PASS=$((PASS + 1))
else
  red "  FAIL: 4d. open_questions 闭合约束未定义"
  FAIL=$((FAIL + 1))
fi

echo ""

# ============================================================
# 5. phase1-requirements-detail.md BA 上下文隔离
# ============================================================

echo "--- 5. phase1-requirements-detail.md BA 上下文隔离 ---"

# 5a. BA 校验流程不再 Read(ba_envelope.output_file) 正文
if grep -q 'analysis_file = Read(ba_envelope.output_file)' "$PHASE1_DETAIL"; then
  red "  FAIL: 5a. BA 校验流程仍包含 Read(output_file) 正文读取"
  FAIL=$((FAIL + 1))
else
  green "  PASS: 5a. BA 校验流程不再 Read 正文"
  PASS=$((PASS + 1))
fi

# 5b. BA prompt 模板明确 BA 自行 Read 调研文件
if grep -q '自行读取以下文件了解技术可行性' "$PHASE1_DETAIL" || grep -q '由你直接 Read' "$PHASE1_DETAIL"; then
  green "  PASS: 5b. BA prompt 明确自行 Read 调研文件"
  PASS=$((PASS + 1))
else
  red "  FAIL: 5b. BA prompt 未明确自行 Read"
  FAIL=$((FAIL + 1))
fi

# 5c. BA 信封增加了 goal/scope/non_goals 等结构化字段
BA_ENVELOPE_OK=true
for field in goal scope non_goals acceptance_criteria assumptions risks; do
  if ! grep -q "\"$field\"" "$PHASE1_DETAIL"; then
    BA_ENVELOPE_OK=false
    break
  fi
done
if [ "$BA_ENVELOPE_OK" = "true" ]; then
  green "  PASS: 5c. BA 信封包含完整结构化字段"
  PASS=$((PASS + 1))
else
  red "  FAIL: 5c. BA 信封缺少结构化字段"
  FAIL=$((FAIL + 1))
fi

# 5d. requirement-packet.json 完整 schema 定义
if grep -q 'requirement-packet.*Schema\|requirement-packet-v1' "$PHASE1_DETAIL"; then
  green "  PASS: 5d. phase1-requirements-detail.md 包含完整 schema"
  PASS=$((PASS + 1))
else
  red "  FAIL: 5d. phase1-requirements-detail.md 缺少完整 schema"
  FAIL=$((FAIL + 1))
fi

# 5e. open_questions 闭合验证逻辑
if grep -q 'open_questions_closed' "$PHASE1_DETAIL" && grep -q 'unresolved' "$PHASE1_DETAIL"; then
  green "  PASS: 5e. open_questions 闭合验证逻辑存在"
  PASS=$((PASS + 1))
else
  red "  FAIL: 5e. open_questions 闭合验证逻辑缺失"
  FAIL=$((FAIL + 1))
fi

# 5f. hash 计算方法
if grep -q 'compute_packet_hash\|sha256' "$PHASE1_DETAIL"; then
  green "  PASS: 5f. requirement-packet hash 计算方法定义"
  PASS=$((PASS + 1))
else
  red "  FAIL: 5f. requirement-packet hash 计算方法缺失"
  FAIL=$((FAIL + 1))
fi

echo ""

# ============================================================
# 6. validate-decision-format.sh 更新
# ============================================================

echo "--- 6. validate-decision-format.sh 注释更新 ---"

# 6a. 包含 Context Isolation 注释
if grep -q 'Context Isolation' "$VALIDATE_SCRIPT"; then
  green "  PASS: 6a. validate-decision-format.sh 包含 Context Isolation 文档"
  PASS=$((PASS + 1))
else
  red "  FAIL: 6a. validate-decision-format.sh 缺少 Context Isolation 文档"
  FAIL=$((FAIL + 1))
fi

# 6b. 提及 requirement-packet.json
if grep -q 'requirement-packet.json' "$VALIDATE_SCRIPT"; then
  green "  PASS: 6b. validate-decision-format.sh 提及 requirement-packet.json"
  PASS=$((PASS + 1))
else
  red "  FAIL: 6b. validate-decision-format.sh 未提及 requirement-packet.json"
  FAIL=$((FAIL + 1))
fi

# 6c. 提及成熟度
if grep -q 'clear.*partial.*ambiguous\|成熟度' "$VALIDATE_SCRIPT"; then
  green "  PASS: 6c. validate-decision-format.sh 提及需求成熟度"
  PASS=$((PASS + 1))
else
  red "  FAIL: 6c. validate-decision-format.sh 未提及需求成熟度"
  FAIL=$((FAIL + 1))
fi

echo ""

# ============================================================
# 7. 跨文件一致性检查
# ============================================================

echo "--- 7. 跨文件一致性 ---"

# 7a. parallel-phase1.md 和 phase1-requirements.md 都提及成熟度
if grep -q 'requirement_maturity\|成熟度' "$PARALLEL_PHASE1" && grep -q 'requirement_maturity\|成熟度' "$PHASE1_REQ"; then
  green "  PASS: 7a. 成熟度在 parallel-phase1.md 和 phase1-requirements.md 一致"
  PASS=$((PASS + 1))
else
  red "  FAIL: 7a. 成熟度定义跨文件不一致"
  FAIL=$((FAIL + 1))
fi

# 7b. dispatch SKILL.md 和 phase1-requirements-detail.md 都包含上下文隔离
if grep -q '上下文隔离' "$DISPATCH_SKILL" && grep -q '上下文隔离' "$PHASE1_DETAIL"; then
  green "  PASS: 7b. 上下文隔离在 dispatch 和 detail 中均声明"
  PASS=$((PASS + 1))
else
  red "  FAIL: 7b. 上下文隔离跨文件声明不一致"
  FAIL=$((FAIL + 1))
fi

# 7c. requirement-packet.json 在两处核心文档均有定义
if grep -q 'requirement-packet.json' "$PHASE1_REQ" && grep -q 'requirement-packet.json' "$PHASE1_DETAIL"; then
  green "  PASS: 7c. requirement-packet.json 在核心文档中均有定义"
  PASS=$((PASS + 1))
else
  red "  FAIL: 7c. requirement-packet.json 定义跨文件不一致"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=============================="
echo "Phase 1 Context Isolation: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
