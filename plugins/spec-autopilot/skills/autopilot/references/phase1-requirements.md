# Phase 1: 需求理解与多轮决策 — 核心流程

> 本文件由 autopilot SKILL.md 引用，执行 Phase 1 时按需读取。
> 详细补充（Agent 模板、搜索规则引擎、Steering Documents 模板）见 `references/phase1-requirements-detail.md`。

**核心原则**: 绝不假设，始终列出选项由用户决策。

---

## 1.1 获取需求来源

- `$ARGUMENTS` 为文件路径 → 读取文件内容
- `$ARGUMENTS` 为文本 → 直接作为需求描述
- `$ARGUMENTS` 为空 → AskUserQuestion 要求输入

获取到的原始需求文本记为 `RAW_REQUIREMENT`。

## 1.1.5 需求信息量评估（主线程执行）

对 RAW_REQUIREMENT 执行规则检测：
- 文本长度 < 20 字符 → flag: brevity
- 不含技术名词（组件/API/模块/库名/框架名）→ flag: no_tech_entity
- 不含量化指标（数字/百分比/时间单位/容量单位）→ flag: no_metric
- 不含具体动词（创建/迁移/修复/集成/添加/删除/重构）→ flag: vague_action

决策：
- flags >= 3 → 强制进入"需求澄清预循环"：
  AskUserQuestion 构造 3-5 个针对性问题，澄清后更新 RAW_REQUIREMENT 再继续
- flags >= 2 → 标记 requirement_clarity: "low"，
  调研 Agent prompt 追加"需求模糊，优先进行范围界定而非方案探索"
- flags < 2 → 正常流程

## 1.2 项目上下文扫描（Auto-Scan）— v3.2.0 并行增强

> **后台执行约束**（v3.4.0）：子 Agent 必须 `run_in_background: true`，主线程仅消费 JSON 信封摘要。

Auto-Scan、技术调研、联网搜索三者**同时并行执行**（参考 `references/parallel-dispatch.md`）：

```
┌─ Auto-Scan → project-context.md + existing-patterns.md + tech-constraints.md
├─ 技术调研 → research-findings.md
└─ 联网搜索 → web-research-findings.md（默认执行/规则跳过）
↓ 全部完成后汇合
复杂度评估 → 需求分析 (business-analyst)
```

> **持久化上下文有效时**: Auto-Scan 跳过全量扫描，直接读取缓存。技术调研和联网搜索仍并行执行。

持久化上下文检查：`openspec/.autopilot-context/` 存在且 < 7 天 → 跳过全量扫描。

> **详细参考**：扫描范围、Steering Documents 模板、历史知识注入、返回信封格式见 `references/phase1-requirements-detail.md`。

## 1.3 技术调研（Research Agent）

> **后台执行约束**（v3.4.0）：`run_in_background: true`，不含 `autopilot-phase` 标记。

调用 Task(subagent_type = config...research.agent, 默认 "general-purpose") 并行技术调研。

调研任务：影响分析 → 依赖检查 → 可行性评估 → 风险识别 → Web 搜索（默认执行）→ 同类对比（deep）→ 依赖深度分析（deep）

> **详细参考**：Research Agent Prompt 模板、搜索决策规则引擎、调研深度配置见 `references/phase1-requirements-detail.md`。

### 产出写入（v3.3.0 上下文保护）

子 Agent 自行 Write 到 `context/research-findings.md`，返回 JSON 信封（仅摘要，禁止全文）。

### 返回值校验

主线程检查：非空 JSON 信封 + `status`/`decision_points`/`feasibility`/`output_file` 字段 + 文件存在。
两次 dispatch 失败 → `research_status: "skipped"`，继续流程。

## 1.4 复杂度评估与分路（Complexity Routing）

> 主线程执行（非子 Agent）。当 `config...complexity_routing.enabled`（默认 true）时执行。

```
total_files = len(new_files) + len(modified_files)
≤ 2 → small | ≤ 5 → medium | > 5 → large
```

额外升级因子（→ large）：`feasibility.score == "low"`、高风险、3+ 新依赖。

| 复杂度 | 讨论深度 | 苏格拉底模式 | 预计 QA 轮数 |
|--------|----------|-------------|-------------|
| small | 快速确认 | 禁用 | 1 轮 |
| medium | 标准讨论 | 遵循 config | 2-3 轮 |
| large | 深度讨论 | 强制启用 | 3+ 轮 |

Research Agent 被跳过时默认 complexity = `"medium"`。

## 1.5 需求分析（增强版）

> **上下文保护**：business-analyst 使用 `run_in_background: true`，自行 Write 到 `context/requirements-analysis.md`。

调用 Task(subagent_type = config...requirements.agent, 默认 "business-analyst")。
Agent prompt 注入 RAW_REQUIREMENT + Steering Documents 路径 + 调研结论路径 + 复杂度。

> **详细参考**：Business-Analyst Prompt 模板见 `references/phase1-requirements-detail.md`。

## 1.5.5 结构化决策协议（Decision Protocol）

所有决策点**必须**以结构化卡片格式呈现（v3.2.0：所有复杂度级别均强制）。

| 场景 | 决策协议行为 |
|------|------------|
| medium/large | 完整决策卡片（含选项/pros/cons/推荐/调研依据） |
| small | 简化模式 — 关键决策点展示卡片，非关键合并确认 |
| Phase 5 冲突 | 简化卡片（仅选项 + 影响范围） |

决策记录持久化到 checkpoint `decisions` 数组，格式为 DecisionPoint（见 protocol.md）。

> **详细参考**：决策卡片完整格式见 `references/phase1-requirements-detail.md`。

## 1.6 多轮决策循环（LOOP）

**循环条件**: 存在任何未澄清的决策点

每轮循环：梳理未决策点 → 构造决策卡片 → AskUserQuestion → 记录 rationale → 检查新决策点 → 重复。

- **Small**: 合并为一次确认，最多 1 轮
- **Large**: 强制 ≥ 3 轮，检查 scope creep

## 1.7 生成结构化提示词

整理所有决策结果，包含：背景与目标、功能清单、决策结论、技术约束、技术方案、验收标准、影响范围。

## 1.8 最终确认

AskUserQuestion: "以上需求理解是否准确？如有遗漏请补充。"
- "确认，开始实施 (Recommended)" / "需要补充修改"
- 选"补充" → 回到 1.6 循环

## 1.9 写入 Phase 1 Checkpoint

调用 Skill(`spec-autopilot:autopilot-gate`) 写入 `phase-1-requirements.json`：

```json
{
  "status": "ok",
  "summary": "需求分析完成，共 N 个功能点，M 个决策已确认",
  "artifacts": ["context/prd.md", "context/discussion.md", "context/project-context.md", "..."],
  "requirements_summary": "功能概要...",
  "decisions": [{"point": "决策点描述", "choice": "用户选择"}],
  "change_name": "<kebab-case>",
  "complexity": "small | medium | large",
  "research": {"status": "completed|skipped", "impact_files": N, "estimated_loc": N, "feasibility_score": "high|medium|low", "new_deps_count": N},
  "steering_artifacts": ["context/project-context.md", "context/existing-patterns.md", "context/tech-constraints.md"]
}
```

## 1.10 可配置用户确认点

如果 `config.gates.user_confirmation.after_phase_1 === true`（默认 true）：
- AskUserQuestion：「需求分析已完成，是否确认进入 OpenSpec 创建阶段？」
- 选"暂停" → 结束流水线，可通过崩溃恢复继续

---

## 补充协议

**执行前读取**: `references/phase1-supplementary.md`（苏格拉底模式、崩溃恢复、决策格式 Hook 验证）

| 协议 | 触发条件 | 说明 |
|------|---------|------|
| 苏格拉底模式 | `config.mode == "socratic"` 或 `complexity == "large"` | 6 步挑战性提问深化需求 |
| 崩溃恢复 | Phase 1 中途崩溃 | 按已完成步骤跳过重复工作 |
| 决策格式验证 | medium/large 复杂度 | Hook 确定性验证 DecisionPoint 完整性 |
