# Phase 1: 需求理解与多轮决策 — 核心流程

> **加载策略**: 本文件为 Phase 1 核心流程（常驻加载）。详细模板和规则引擎请参见 `phase1-requirements-detail.md`（按需加载）。

> 本文件由 autopilot SKILL.md 引用，执行 Phase 1 时按需读取。

**核心原则**: 绝不假设，始终列出选项由用户决策。

---

## 1.1 获取需求来源

- `$ARGUMENTS` 为文件路径 → 读取文件内容
- `$ARGUMENTS` 为文本 → 直接作为需求描述
- `$ARGUMENTS` 为空 → AskUserQuestion 要求输入

获取到的原始需求文本记为 `RAW_REQUIREMENT`。

## Step 1.1.5 需求信息量评估（主线程执行）

对 RAW_REQUIREMENT 执行确定性规则检测（非 AI 判断）：

| 检测维度 | 触发条件 | 标记 |
|---------|---------|------|
| 文本过短 | 长度 < 20 字符 | `brevity` |
| 无技术实体 | 不含组件/API/模块/库名/框架名 | `no_tech_entity` |
| 动作模糊 | 不含具体动词（创建/迁移/修复/集成/添加/删除/重构/优化/implement/add/fix/migrate） | `vague_action` |
| 无范围限定 | 不含边界词 + 不含目标实体（用户/管理员/系统/服务/页面/接口） | `no_scope_boundary` |
| 无验收标准 | 不含验收词 + 不含数字/百分比/时间单位/容量单位 | `no_acceptance_criteria` |

**决策树**：
- **flags >= 3** → 强制进入"需求澄清预循环"（AskUserQuestion 3-5 个澄清问题，完成后更新 RAW_REQUIREMENT）
- **flags >= 2** → 触发"定向澄清预检"（Step 1.1.7），收敛基本方向后再进入调研
- **flags < 2** → 正常流程

> **设计意图**: 避免在模糊需求上直接启动三路并行调研，浪费 Token 且调研结果噪音大。

## Step 1.1.5b 需求成熟度评估

在信息量评估（Step 1.1.5）完成后，立即执行需求成熟度分类，决定调研方案：

| 成熟度 | 判定规则 | 调研方案 |
|--------|---------|---------|
| **clear** | flags == 0 且 RAW_REQUIREMENT 含具体组件 + 具体行为 + 验收条件 | 仅 Auto-Scan（轻量澄清） |
| **partial** | flags == 1 或 (flags == 0 但缺乏验收标准) | Auto-Scan + 定向技术调研（双路） |
| **ambiguous** | flags >= 2 | Auto-Scan + 技术调研 + 联网搜索（三路） |

```
# 成熟度决策规则（确定性，非 AI 判断）
IF flags >= 2:
    maturity = "ambiguous"
ELIF flags == 1:
    maturity = "partial"
ELIF flags == 0:
    # 进一步检查验收标准质量
    has_acceptance = RAW_REQUIREMENT 包含数字/百分比/可测试动词
    has_specific_target = RAW_REQUIREMENT 包含具体组件名或文件路径
    IF has_acceptance AND has_specific_target:
        maturity = "clear"
    ELSE:
        maturity = "partial"
```

### 成熟度驱动的调研方案

- **clear**: 仅派发 Auto-Scan → 直接进入 BA 分析 → 快速完成 Phase 1
- **partial**: 派发 Auto-Scan + 技术调研 → 联网搜索按搜索规则引擎决定
- **ambiguous**: 先走定向澄清/预循环 → 再派发三路调研

> **设计意图**: 不再把所有需求都强制走三路调研。clear 需求无需消耗额外 Token 做技术调研，partial 需求按需补充，ambiguous 需求才全面展开。

## Step 1.1.7 定向澄清预检

**触发条件**: flags >= 2 且 flags < 3（信息不足但未达强制预循环阈值）。

**核心原则**: 先收敛方向，再启动调研。不进入三路并行调研，直到基本方向收敛。

### 澄清规则引擎

```
IF flags >= 3:
    # 保持原逻辑: 强制预循环 3-5 问
    GOTO 需求澄清预循环

IF flags >= 2 AND flags < 3:
    # 定向澄清: 最多 1-3 个最高价值问题
    clarification_questions = []

    IF 'no_scope_boundary' IN active_flags:
        clarification_questions.append("这个需求的范围边界是什么？哪些场景/模块在范围内，哪些明确排除？目标对象是谁/什么？")

    IF 'no_acceptance_criteria' IN active_flags:
        clarification_questions.append("完成后如何验证？期望的验收标准或可观测结果是什么？")

    IF len(clarification_questions) == 0:
        # flags 由 brevity/no_tech_entity/no_metric/vague_action 触发
        # 构造通用澄清问题
        clarification_questions.append("能否补充更多细节？包括：具体要改动的组件、期望的行为、验收条件")

    # 约束: 最多 3 个问题
    clarification_questions = clarification_questions[:3]

    AskUserQuestion(clarification_questions)
    # 用户回答后更新 RAW_REQUIREMENT，重新执行 Step 1.1.5 评估
    UPDATE RAW_REQUIREMENT with user answers
    RE-EVALUATE flags (回到 Step 1.1.5)

    # 安全阀: 定向澄清最多执行 1 轮，避免死循环
    IF still flags >= 2 after re-evaluation:
        标记 requirement_clarity: "low"
        继续流程（进入调研，调研 Agent 优先范围界定）

IF flags < 2:
    # 正常流程
    CONTINUE
```

### 约束

| 约束项 | 规则 |
|--------|------|
| 最大问题数 | 3 个（从 no_scope_boundary / no_acceptance_criteria 优先选取） |
| 交互方式 | AskUserQuestion（轻量，非大段 Prompt 分析） |
| 最大轮数 | 1 轮（问完即走，不反复追问） |
| 与预循环互斥 | flags >= 3 走预循环，flags >= 2 走定向澄清，二者不叠加 |
| 调研阻塞 | 定向澄清未完成前，不启动三路并行调研 |

> **设计意图**: 在 2-flag 灰区用最小成本收敛方向，避免过早进入高 Token 消耗的三路调研。与 flags >= 3 的强制预循环互补。

## Step 1.1.6 需求类型分类与路由

对 RAW_REQUIREMENT 执行确定性规则分类（非 AI 判断），将需求路由到差异化流水线：

### 分类规则

| 类别 | 识别规则（按优先级匹配） | 标记 |
|------|------------------------|------|
| **Bugfix** | 含"修复/fix/bug/defect/issue/regression/报错/异常/崩溃/闪退"等关键词 | `requirement_type: "bugfix"` |
| **Refactor** | 含"重构/refactor/优化性能/clean up/migrate/迁移/升级依赖"等关键词 | `requirement_type: "refactor"` |
| **Chore** | 含"配置/CI/CD/文档/lint/format/依赖更新/版本号/changelog"等关键词 | `requirement_type: "chore"` |
| **Feature** | 以上均不匹配（默认） | `requirement_type: "feature"` |

> **复合需求路由**: 当需求同时命中多个分类（如"重构登录模块并添加 SSO 支持"同时匹配 Refactor + Feature），
> `requirement_type` 使用数组表示（如 `["refactor", "feature"]`），`routing_overrides` 取所有命中类别中**最严格**的阈值。
> 例如 Refactor(change_coverage=100%) + Feature(sad_path=20%) → 合并为 `change_coverage_min_pct: 100, sad_path_min_ratio_pct: 20`。

### 路由策略（差异化流水线严格度）

| 维度 | Feature | Bugfix | Refactor | Chore |
|------|---------|--------|----------|-------|
| **Phase 1 调研深度** | 完整三路并行 | 聚焦复现路径 + 根因分析 | 聚焦影响范围 + 回归风险 | 最小化（仅 Auto-Scan） |
| **Phase 4 sad_path 最低比例** | 20% | **40%**（必须含复现测试） | 20% | 10% |
| **Phase 5 change_coverage 阈值** | 80% | **100%**（修复必须完全覆盖） | **100%**（重构不可丢失行为） | 60% |
| **Phase 6 测试类型要求** | 全量 | 至少含 regression test | 至少含 integration test | typecheck 即可 |
| **强制附加测试** | 无 | 复现测试（验证 bug 已修复） | 行为保持测试（新旧输出一致） | 无 |

### 路由注入

分类结果写入 Phase 1 JSON 信封的 `requirement_type` 字段，传递给后续所有 Phase：

```json
{
  "requirement_type": "bugfix",
  "routing_overrides": {
    "sad_path_min_ratio_pct": 40,
    "change_coverage_min_pct": 100,
    "required_test_types": ["unit", "api", "regression"]
  }
}
```

**复合需求示例**（多类型命中时）：
```json
{
  "requirement_type": ["refactor", "feature"],
  "routing_overrides": {
    "sad_path_min_ratio_pct": 20,
    "change_coverage_min_pct": 100,
    "required_test_types": ["unit", "api", "integration"]
  }
}
```
> 合并策略: 数值型取 `max()`（最严格），列表型取 `union()`（最全面）。

后续 Phase 的 dispatch prompt 中注入路由覆盖值，L2 Hook 从 Phase 1 checkpoint 读取 `routing_overrides` 动态调整门禁阈值。

> **向后兼容**: `requirement_type` 和 `routing_overrides` 为可选字段。未分类时等效 `feature` 默认值。

## 1.2 项目上下文扫描（Auto-Scan）— 并行增强

> **后台执行约束**：子 Agent 必须 `run_in_background: true`，主线程仅消费 JSON 信封。

> **Agent 事件**：Hook 自动发射 agent_dispatch/complete 事件。SKILL.md 中的手动发射为双重保障，任一机制工作即可驱动 GUI ParallelKanban 显示 Agent 卡片。

Auto-Scan、技术调研、联网搜索三者**同时并行执行**（参考 `references/parallel-phase1.md` 配置）。

→ 详见 `phase1-requirements-detail.md`（持久化上下文检查、扫描范围、Steering Documents 模板、历史知识注入、返回信封格式）

## 1.3 技术调研（Research Agent）

> **后台执行约束**：子 Agent 必须 `run_in_background: true`，主线程仅消费 JSON 信封。

调用 Task(subagent_type: config.phases.requirements.research.agent, run_in_background: true) 并行技术调研。此 Task 不含 `autopilot-phase` 标记。

→ 详见 `phase1-requirements-detail.md`（Research Agent Prompt 模板、调研深度配置）

### 1.3.3 联网调研（Web Research）— 搜索策略重构

**核心原则**: 默认执行搜索，仅当规则引擎判定可跳过时才跳过。不依赖 AI 自评置信度。

→ 详见 `phase1-requirements-detail.md`（搜索决策规则引擎完整规则、搜索分类、搜索深度、关键词构造、信任机制、产出格式）

## 1.4 复杂度评估与分路（Complexity Routing）

> 复杂度评估在主线程执行（纯数值比较），数据来自信封中的 `impact_analysis`。

基于 `total_files = len(new_files) + len(modified_files)` 分为 small/medium/large 三级，额外调整因子可升级为 large。

→ 详见 `phase1-requirements-detail.md`（完整评估规则、调整因子、分路策略）

## 1.5 需求分析（增强版）

> **上下文保护**：需求分析 Agent（config.phases.requirements.agent）使用 `run_in_background: true`，自行 Write 完整分析，主线程仅消费信封。

调用 Task(subagent_type: config.phases.requirements.agent, run_in_background: true) 分析需求，注入 Steering Context + 调研结论。

→ 详见 `phase1-requirements-detail.md`（需求分析 Agent 完整 Prompt 模板）

### 1.5.1 `[NEEDS CLARIFICATION]` 协议（Task B9 硬约束）

> **协议来源**：[GitHub Spec Kit](https://github.com/github/spec-kit) 的 `[NEEDS CLARIFICATION: ...]` 标记规范。本 Phase 1 把该协议向上游延伸到 BA Agent 产出层，**不再依赖 Synthesizer 反推歧义**。

**BA Agent 硬约束**（必须写入 `config.phases.requirements.agent` 的 prompt）：

1. **模板唯一**：BA Agent 产出 `context/requirements-analysis.md` 时 **必须** 采用
   `runtime/templates/requirements-template.md` 的骨架（User Stories / Acceptance Criteria / Non-Goals / Open Questions / Review Checklist 五段式）。
2. **NEEDS CLARIFICATION 强制标记**：
   > 任何用户原始 prompt 未覆盖的点**必须**用 `[NEEDS CLARIFICATION: 具体问题]` 标记，**禁止**貌似合理的假设。
   - 未知角色 / 未知权限边界 / 未知性能阈值 / 未知失败策略 / 未知数据来源 / 未知 UI 反馈 — 一律标记，不得猜测。
   - 标记语法必须严格匹配 `^\[NEEDS CLARIFICATION:`，与 `requirement-packet.schema.json#/properties/needs_clarification` 及 `synthesizer-verdict.schema.json#/properties/ambiguities` 的 pattern 对齐。
3. **禁止 HOW**：BA 产出只回答 **WHAT / WHY**，不得出现实现路径、文件名、库选型、SQL 等 HOW 细节（HOW 由 Phase 2 OpenSpec / Phase 3 设计阶段承担）。
4. **Review Checklist 闭环**：进入 1.6 决策 LOOP 前，BA 信封必须附带 `needs_clarification_count`（整数），供主线程在 clarity_score 与决策 LOOP 退出条件中使用。
5. **与 Synthesizer 的职责分工**：BA 主动标记未覆盖点 → Synthesizer 只做跨路合并与去重，不再从语料反推歧义；双路冗余但方向一致，命中即进入决策 LOOP。

> **反模式（L3 AI Gate 抽查）**：若 BA 产出中出现 "assume" / "假设" / "默认" / "通常" 等弱限定词却未伴随 `[NEEDS CLARIFICATION:` 标记，视为违反 spec-kit 协议，Gate 可要求 BA Agent 重新产出。


## 1.5.5 结构化决策协议（Decision Protocol）

所有决策点**必须**以结构化卡片格式呈现给用户（所有复杂度级别均强制）。

→ 详见 `phase1-requirements-detail.md`（决策卡片完整格式、应用场景、决策记录持久化）

## 1.6 多轮决策循环（LOOP）— 弹性收敛重构

**循环退出条件**: 清晰度评分达标 + 所有决策点已澄清 + 满足最低轮数。

**执行前读取**: `autopilot/references/phase1-clarity-scoring.md`（混合评分系统）+ `autopilot/references/phase1-challenge-agents.md`（挑战代理协议）

### 退出条件（三条件 AND）

```
EXIT LOOP WHEN:
  1. clarity_score >= clarity_threshold    # 清晰度达标（见 phase1-clarity-scoring.md）
  2. 所有决策点已澄清                      # 无未闭合 decision_point
  3. current_round >= min_qa_rounds         # 满足最低轮数下限
```

### 安全阀

| 参数 | 默认值 | 行为 |
|------|--------|------|
| `min_qa_rounds` | 1 | 最低轮数下限（保留原有语义） |
| `soft_warning_rounds` | 8 | 软提醒：展示当前清晰度，AskUserQuestion 询问是否继续 |
| `max_rounds` | 15 | 硬上限：强制结束，以当前最佳状态输出 |

### 核心循环

```
current_round = 0
min_rounds = config.phases.requirements.min_qa_rounds || 1
threshold = config...clarity_threshold_overrides[complexity] || config...clarity_threshold || 0.80
challenge_state = {challenge_agents_used: Set(), prev_clarity: null, stagnant_rounds: 0}

LOOP:
  current_round += 1

  # === Step A: 选择提问目标 ===
  IF 挑战代理激活条件满足（见 phase1-challenge-agents.md）:
      执行挑战代理提问（替代本轮常规提问）
  ELIF 存在未决策点:
      # 一次一问原则
      IF complexity == "small":
          合并全部未决策点为一次 AskUserQuestion（保持快速路径）
      ELSE:  # medium / large
          选择与最弱清晰度维度最相关的 1 个未决策点
          构造决策卡片 → AskUserQuestion → 收集结果
  ELSE:
      # 所有决策点已澄清但清晰度未达标
      执行苏格拉底步骤主动寻找遗漏（即使非 socratic 模式）
      IF 未发现新决策点 AND current_round >= min_rounds:
          # 清晰度未达标但无法发现新问题 → 需要用户明确同意才能退出
          AskUserQuestion:
            question: "所有决策点已澄清，但清晰度评分 {clarity_pct}% 低于目标 {threshold_pct}%。无法发现更多遗漏问题。"
            options:
              - "以当前清晰度推进（接受风险）"
              - "补充更多需求细节（回到讨论）"
          IF 用户选择"以当前清晰度推进": EXIT LOOP
          ELSE: CONTINUE  # 用户选择补充 → 继续循环

  # === Step B: 清晰度评分（每轮末尾） ===
  计算 clarity_score（见 phase1-clarity-scoring.md 混合评分公式）
  输出进度展示: Round {n} | Clarity: {pct}% | Target: {threshold_pct}%

  # === Step C: 停滞检测 ===
  stagnation_action = check_stagnation(clarity_score, challenge_state)
  IF stagnation_action == "activate_ontologist": 下一轮激活本体论代理
  IF stagnation_action == "prompt_user_exit": AskUserQuestion 询问是否以当前清晰度推进

  # === Step D: 安全阀检查 ===
  IF current_round == soft_warning_rounds:
      AskUserQuestion: "已讨论 {n} 轮，当前清晰度 {pct}%，是否继续？"
      IF 用户选择"以当前清晰度推进": EXIT LOOP

  IF current_round >= max_rounds:
      输出 [WARN] 达到硬上限，强制推进
      EXIT LOOP

  # === Step E: 退出判定 ===
  IF clarity_score >= threshold AND 所有决策点已澄清 AND current_round >= min_rounds:
      EXIT LOOP
```

### 复杂度对讨论的影响（改为影响阈值而非轮数）

| 复杂度 | 清晰度阈值 | 提问策略 | 苏格拉底/挑战代理 |
|--------|-----------|---------|-----------------|
| small | 0.70（宽松） | 合并决策点一次确认 | 禁用苏格拉底；挑战代理按配置 |
| medium | 0.80（标准） | 一次一问 | 遵循 config |
| large | 0.85（严格） | 一次一问 + scope creep 检查 | 强制苏格拉底；挑战代理按配置 |

→ 详见 `phase1-requirements-detail.md`（主动讨论协议、各复杂度路径详细流程）

## 1.7 生成结构化提示词（上下文隔离增强）

整理所有决策结果，包含：

| 章节 | 内容 | 数据来源 |
|------|------|---------|
| 背景与目标 | 需求来源 + 业务目标 | RAW_REQUIREMENT + BA 信封 summary |
| 功能清单 | 确认的功能点列表（含优先级） | BA 信封 requirements_summary |
| 决策结论 | 每个决策点的最终选择 | 信封 decision_points + 用户确认 |
| 技术约束 | 从 tech-constraints.md 提取 | 调研信封 tech_constraints（非正文） |
| 技术方案 | 推荐方案 | 调研信封 summary + decision_points |
| 验收标准 | 可测试的验收条件 | BA 信封 acceptance_criteria |
| 影响范围 | 预估影响文件 + 代码行数 | 调研信封 impact_analysis |

> **上下文隔离红线**：以上所有数据均来自 JSON 信封中的结构化字段，**禁止**主线程 Read 子 Agent 的正文工件（research-findings.md、web-research-findings.md、requirements-analysis.md）来构造结构化提示词。

## 1.8 最终确认（AskUserQuestion 强制）

**硬约束**: 最终需求确认**必须且只能**通过 `AskUserQuestion` 工具完成，**严禁**通过纯文字输出让用户确认。

具体流程：
1. 将完整结构化提示词（背景、功能清单、决策结论、技术方案、验收标准等）作为 `AskUserQuestion` 的 question 字段内容展示
2. 选项: “确认，开始实施 (Recommended)” / “需要补充修改”
3. 选"补充" → 回到 1.6 循环
4. 选"确认" → **立即**进入 1.9 写入 `requirement-packet.json` 和 Phase 1 checkpoint，除非 `after_phase_1 === true`，否则**不得**再插入任何"下一步做什么"的元问题

**禁止模式**（违反即等同违反状态机硬约束）：
- ❌ 用文字输出需求提示词，然后追问”请确认以上需求是否准确？”
- ❌ 先输出提示词文字，再用 AskUserQuestion 问”是否继续”
- ✅ 唯一正确方式：将提示词完整嵌入 AskUserQuestion 的 question 字段，一次性展示+确认

**禁止示例**：
  - `下一步是 Phase 2（OpenSpec 规范生成）还是需要先审查 Phase 1 的输出？`
  - `Phase 1 已完成，要继续还是暂停？`

## 1.9 生成 requirement-packet.json 并写入 Phase 1 Checkpoint

> **合成方式硬约束（Task 6 重构）**：`requirement-packet.json` 必须由专用 PackagerAgent 基于 **verdict.json + requirements-analysis.md 全文** 合成，**严禁**主线程自行从信封/摘要字段压缩拼装。主线程仅负责派发与 `Read(packet.json)` 消费。

### 1.9 子步骤（四段式）

**Step 1.9.1** 前置 — SynthesizerAgent 已产出 `context/phase1-verdict.json`（含 `merged_decision_points`、`conflicts`、`ambiguities`），schema: `runtime/schemas/synthesizer-verdict.schema.json`。

**Step 1.9.2** 前置 — BA Agent 已产出 `context/requirements-analysis.md` 草稿（结构化 user stories + acceptance criteria + checklist），以及对应的 JSON 信封。

> **文件名约定**：BA Agent 实际产出文件名为 `context/requirements-analysis.md`（沿用仓库既有约定）；spec 文档中偶尔出现的 `requirements.md` 为其抽象称呼，二者指同一文件，以 `requirements-analysis.md` 为准。

**Step 1.9.3** 主线程派发 PackagerAgent（**复用 `phases.requirements.synthesizer.agent` 配置**作为 `subagent_type`，不新增 agent 字段）：
- 输入：
  - `openspec/changes/{change_name}/context/phase1-verdict.json`（verdict.json 全文）
  - `openspec/changes/{change_name}/context/requirements-analysis.md`（BA 草稿全文）
  - 用户澄清答复（来自 1.6-1.8 决策 LOOP 的最终确认）
- 职责边界：**只做最终结构化打包**；不做需求撰写（属 BA 职责），不做跨路仲裁（属 Synthesizer 职责）。
- 输出文件：`openspec/changes/{change_name}/context/requirement-packet.json`
- Schema 校验：`runtime/schemas/requirement-packet.schema.json`（Schema 作为契约参考，L2 Hook 运行时校验在 Task B11 接入；当前由 `runtime/scripts/validate-requirement-packet.sh` 做字段级校验）；必填字段 `goal / scope / non_goals / acceptance_criteria / risks / decisions / needs_clarification / sha256` 全部存在，否则硬阻断。
- 信息无损要求：`acceptance_criteria` 数量 ≥ `requirements-analysis.md` 与 `research-findings.md` 中可测试动词（MUST/SHOULD/SHALL）数，禁止隐式压缩。

**Step 1.9.4** 主线程**仅 Read `requirement-packet.json`**（**不读原始 markdown**，即不 Read `requirements-analysis.md` / `research-findings.md` 正文），基于 packet 字段写入 `phase-1-requirements.json` checkpoint。

---

### 参考 packet 结构

```json
{
  "version": "1.0",
  "raw_requirement": "原始需求文本",
  "requirement_type": "feature|bugfix|refactor|chore",
  "requirement_maturity": "clear|partial|ambiguous",
  "complexity": "small|medium|large",
  "goal": "业务目标（1-3 句）",
  "scope": ["功能范围条目"],
  "non_goals": ["明确排除项"],
  "acceptance_criteria": [
    {"text": "可测试的验收标准", "testable": true, "source_ref": "requirements-analysis.md#AC1"}
  ],
  "decisions": [
    {
      "point": "决策点描述",
      "choice": "最终选择",
      "rationale": "选择理由",
      "options": [...]
    }
  ],
  "assumptions": ["实施前提假设"],
  "risks": [{"category": "...", "severity": "...", "mitigation": "..."}],
  "routing_overrides": {
    "sad_path_min_ratio_pct": 20,
    "change_coverage_min_pct": 80,
    "required_test_types": ["unit", "api"]
  },
  "research_plan": {
    "maturity": "clear|partial|ambiguous",
    "dispatched": ["auto_scan", "tech_research"],
    "skipped": ["web_search"]
  },
  "open_questions_closed": true,
  "sha256": "sha256 of canonical JSON (excluding sha256/hash field itself)",
  "timestamp": "ISO-8601"
}
```

**写入路径**: `openspec/changes/{change_name}/context/requirement-packet.json`

**同时写入 checkpoint**: 调用 Skill(`spec-autopilot:autopilot-gate`) checkpoint 管理写入 `phase-1-requirements.json`。
写入最终 checkpoint 后，删除中间态文件：`rm -f ${phase_results}/phase-1-interim.json`。

### requirement-packet.json 约束

1. **唯一事实源**：后续 Phase 2-7 只认 `requirement-packet.json`，不再读取散落的决策文本
2. **open_questions 必须闭合**：`open_questions_closed` 必须为 `true` 才能写入最终 checkpoint
3. **hash 校验**：后续 Phase 可通过 hash 验证 requirement packet 未被篡改
4. **由 PackagerAgent 全文合成**：requirement-packet.json 由 PackagerAgent 基于 verdict.json + requirements-analysis.md 全文产出；主线程仅 Read packet.json 消费（不读 markdown 原文、不做任何字段压缩拼装）

> 此 checkpoint 使崩溃恢复能跳过 Phase 1，直接从 Phase 2 继续。
> 中间态 `phase-1-interim.json` 在三路调研完成和每轮决策后写入，提供细粒度崩溃恢复点。
> **连续执行要求**: 当 `config.gates.user_confirmation.after_phase_1 !== true` 时，1.9 完成后主线程必须继续进入下一执行阶段，不得先回到“请用户决定是否继续”的闲置状态。

## 1.10 可配置用户确认点

如果 `config.gates.user_confirmation.after_phase_1 === true`（**默认 false**，需求评审后默认自动推进）：
- AskUserQuestion：「需求分析已完成，是否确认进入 OpenSpec 创建阶段？」
- 选"暂停" → 结束当前流水线，用户可后续通过崩溃恢复继续

---

---

## 补充协议

**执行前读取**: `references/phase1-supplementary.md`（苏格拉底模式、崩溃恢复、决策格式 Hook 验证）

| 协议 | 触发条件 | 说明 |
|------|---------|------|
| 苏格拉底模式 | `config.mode == "socratic"` 或 `complexity == "large"` | 7 步挑战性提问深化需求（+非功能需求质询） |
| 崩溃恢复 | Phase 1 中途崩溃 | 按已完成步骤跳过重复工作 |
| 决策格式验证 | medium/large 复杂度 | Hook 确定性验证 DecisionPoint 完整性 |
