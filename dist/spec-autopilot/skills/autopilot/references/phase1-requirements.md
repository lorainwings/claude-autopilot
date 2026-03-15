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
| 无量化指标 | 不含数字/百分比/时间单位/容量单位 | `no_metric` |
| 动作模糊 | 不含具体动词（创建/迁移/修复/集成/添加/删除/重构/优化/implement/add/fix/migrate） | `vague_action` |

**决策树**：
- **flags >= 3** → 强制进入"需求澄清预循环"（AskUserQuestion 3-5 个澄清问题，完成后更新 RAW_REQUIREMENT）
- **flags >= 2** → 标记 `requirement_clarity: "low"`，调研 Agent 优先范围界定
- **flags < 2** → 正常流程

> **设计意图**: 避免在模糊需求上直接启动三路并行调研，浪费 Token 且调研结果噪音大。

## Step 1.1.6 需求类型分类与路由（v4.2 新增）

对 RAW_REQUIREMENT 执行确定性规则分类（非 AI 判断），将需求路由到差异化流水线：

### 分类规则

| 类别 | 识别规则（按优先级匹配） | 标记 |
|------|------------------------|------|
| **Bugfix** | 含"修复/fix/bug/defect/issue/regression/报错/异常/崩溃/闪退"等关键词 | `requirement_type: "bugfix"` |
| **Refactor** | 含"重构/refactor/优化性能/clean up/migrate/迁移/升级依赖"等关键词 | `requirement_type: "refactor"` |
| **Chore** | 含"配置/CI/CD/文档/lint/format/依赖更新/版本号/changelog"等关键词 | `requirement_type: "chore"` |
| **Feature** | 以上均不匹配（默认） | `requirement_type: "feature"` |

> **v5.2 复合需求路由**: 当需求同时命中多个分类（如"重构登录模块并添加 SSO 支持"同时匹配 Refactor + Feature），
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

**v5.2 复合需求示例**（多类型命中时）：
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

## 1.2 项目上下文扫描（Auto-Scan）— v3.2.0 并行增强

> **后台执行约束**（v3.4.0）：子 Agent 必须 `run_in_background: true`，主线程仅消费 JSON 信封。

> **v5.3 Agent 事件（Belt & Suspenders）**：Hook 自动发射 agent_dispatch/complete 事件。SKILL.md 中的手动发射为双重保障，任一机制工作即可驱动 GUI ParallelKanban 显示 Agent 卡片。

Auto-Scan、技术调研、联网搜索三者**同时并行执行**（参考 `references/parallel-phase1.md` 配置）。

→ 详见 `phase1-requirements-detail.md`（持久化上下文检查、扫描范围、Steering Documents 模板、历史知识注入、返回信封格式）

## 1.3 技术调研（Research Agent）

> **后台执行约束**（v3.4.0）：子 Agent 必须 `run_in_background: true`，主线程仅消费 JSON 信封。

调用 Task(subagent_type = "general-purpose", run_in_background: true) 并行技术调研。此 Task 不含 `autopilot-phase` 标记。

→ 详见 `phase1-requirements-detail.md`（Research Agent Prompt 模板、调研深度配置）

### 1.3.3 联网调研（Web Research）— v3.3.7 搜索策略重构

**核心原则**: 默认执行搜索，仅当规则引擎判定可跳过时才跳过。不依赖 AI 自评置信度。

→ 详见 `phase1-requirements-detail.md`（搜索决策规则引擎完整规则、搜索分类、搜索深度、关键词构造、信任机制、产出格式）

## 1.4 复杂度评估与分路（Complexity Routing）

> 复杂度评估在主线程执行（纯数值比较），数据来自信封中的 `impact_analysis`。

基于 `total_files = len(new_files) + len(modified_files)` 分为 small/medium/large 三级，额外调整因子可升级为 large。

→ 详见 `phase1-requirements-detail.md`（完整评估规则、调整因子、分路策略）

## 1.5 需求分析（增强版）

> **上下文保护**（v3.4.0）：business-analyst 使用 `run_in_background: true`，自行 Write 完整分析，主线程仅消费信封。

调用 Task(subagent_type = "business-analyst", run_in_background: true) 分析需求，注入 Steering Context + 调研结论。

→ 详见 `phase1-requirements-detail.md`（Business-Analyst 完整 Prompt 模板）

## 1.5.5 结构化决策协议（Decision Protocol）

所有决策点**必须**以结构化卡片格式呈现给用户（所有复杂度级别均强制）。

→ 详见 `phase1-requirements-detail.md`（决策卡片完整格式、应用场景、决策记录持久化）

## 1.6 多轮决策循环（LOOP）

**循环条件**: 存在任何未澄清的决策点。

**v5.2: `min_qa_rounds` 强制最低轮数**:
从 `config.phases.requirements.min_qa_rounds`（默认 1）读取强制最低 QA 轮数下限。即使所有决策点已澄清，
如果当前轮数 < `min_qa_rounds`，仍必须继续循环（主动寻找遗漏决策点或触发苏格拉底追问）。

```
current_round = 0
min_rounds = config.phases.requirements.min_qa_rounds || 1

LOOP:
  current_round += 1
  梳理未决策点 → 构造决策卡片 → AskUserQuestion → 收集结果 → 检查新决策点

  IF 所有决策点已澄清 AND current_round >= min_rounds:
    EXIT LOOP
  ELIF 所有决策点已澄清 AND current_round < min_rounds:
    # 强制继续: 主动寻找遗漏的边界条件、错误处理、非功能需求
    执行苏格拉底步骤（即使非 socratic 模式）
    IF 未发现新决策点:
      EXIT LOOP  # 安全阀：确实无遗漏时允许提前退出
```

每轮循环: 梳理未决策点 → 构造决策卡片 → AskUserQuestion → 收集结果 → 检查新决策点 → 重复直到全部澄清。

- **Small**: 合并为一次确认，最多 1 轮
- **Medium**: 标准 2-3 轮
- **Large**: 强制 3+ 轮，含 scope creep 检查

→ 详见 `phase1-requirements-detail.md`（主动讨论协议、各复杂度路径详细流程）

## 1.7 生成结构化提示词

整理所有决策结果，包含：

| 章节 | 内容 |
|------|------|
| 背景与目标 | 需求来源 + 业务目标 |
| 功能清单 | 确认的功能点列表（含优先级） |
| 决策结论 | 每个决策点的最终选择 |
| 技术约束 | 从 tech-constraints.md 提取 |
| 技术方案 | 从 research-findings.md 提取推荐方案 |
| 验收标准 | 可测试的验收条件 |
| 影响范围 | 预估影响文件 + 代码行数 |

## 1.8 最终确认

展示完整提示词，AskUserQuestion:
"以上需求理解是否准确？如有遗漏请补充。"
选项: "确认，开始实施 (Recommended)" / "需要补充修改"
- 选"补充" → 回到 1.6 循环

## 1.9 写入 Phase 1 Checkpoint

需求确认后，调用 Skill(`spec-autopilot:autopilot-gate`) checkpoint 管理写入 `phase-1-requirements.json`。
写入最终 checkpoint 后，删除中间态文件：`rm -f ${phase_results}/phase-1-interim.json`。

> 此 checkpoint 使崩溃恢复能跳过 Phase 1，直接从 Phase 2 继续。
> v5.1: 中间态 `phase-1-interim.json` 在三路调研完成和每轮决策后写入，提供细粒度崩溃恢复点。

## 1.10 可配置用户确认点

如果 `config.gates.user_confirmation.after_phase_1 === true`（默认 true）：
- AskUserQuestion：「需求分析已完成，是否确认进入 OpenSpec 创建阶段？」
- 选"暂停" → 结束当前流水线，用户可后续通过崩溃恢复继续

---

---

## 补充协议

**执行前读取**: `references/phase1-supplementary.md`（苏格拉底模式、崩溃恢复、决策格式 Hook 验证）

| 协议 | 触发条件 | 说明 |
|------|---------|------|
| 苏格拉底模式 | `config.mode == "socratic"` 或 `complexity == "large"` | 7 步挑战性提问深化需求（v5.2: +非功能需求质询） |
| 崩溃恢复 | Phase 1 中途崩溃 | 按已完成步骤跳过重复工作 |
| 决策格式验证 | medium/large 复杂度 | Hook 确定性验证 DecisionPoint 完整性 |
