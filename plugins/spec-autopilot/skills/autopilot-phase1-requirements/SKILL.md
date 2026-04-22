---
name: autopilot-phase1-requirements
description: "Use when autopilot orchestrator enters Phase 1 to understand requirements, drive multi-round clarification, and produce the structured requirement packet checkpoint."
user-invocable: false
---

# Autopilot Phase 1 — 需求理解与多轮决策（主线程）

> **前置条件自检**：本 Skill 仅在 autopilot 编排主线程中使用。如果当前上下文不是 autopilot 编排流程，请立即停止并忽略本 Skill。

**核心原则**: 绝不假设，始终列出选项由用户决策。

**跳过规则**: 当 `recovery_phase > 1` 时，Phase 1 已完成，跳过整个 Phase 1 流程。直接从 `recovery_phase` 对应的阶段继续。跳过时不发射 Phase 1 事件。

## References 按需读取清单

为避免二级跳转，下表显式列出本 Skill 全部 references 及其消费时机。**只读取与当前步骤匹配的文件**，不要从 reference 内部继续下钻。

| 文件 | 何时读取 | 主要内容 |
|------|---------|---------|
| `references/phase1-requirements.md` | Phase 1 启动前必读 | 完整 10 步主流程、决策循环骨架、退出条件 |
| `references/phase1-requirements-detail.md` | 需要扫描/调研/分析 Agent Prompt 模板、规则引擎细则、决策卡片格式时按需读取 | Steering Documents 模板、Research Prompt、搜索决策规则、复杂度分路、需求分析 Agent Prompt、决策卡片格式 |
| `references/phase1-clarity-scoring.md` | 进入多轮决策 LOOP（步骤 7）前读取 | 混合清晰度评分公式、维度权重、停滞检测、退出条件 |
| `references/phase1-challenge-agents.md` | 进入多轮决策 LOOP（步骤 7）前读取 | 反面论证 / 简化者 / 本体论 三种挑战代理触发轮次与停滞干预 |
| `references/phase1-supplementary.md` | 启用苏格拉底模式、处理崩溃恢复或决策格式校验时读取 | 苏格拉底 7 步提问、崩溃恢复矩阵、decisions 数组 Hook 验证 |

> **读取规则**：references 内部不强制 Read 其他 reference；遇到"详见同目录 xxx.md"字样时，按上表自行判断是否需要补读，禁止形成二级跳转链。

## Step 0: 发射 Phase 1 开始事件

```
Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-phase-event.sh phase_start 1 {mode}')
```

## 概要流程

1. **获取需求来源**：解析 `$ARGUMENTS`。详见 references/phase1-requirements.md § 1.1。
2. **前置决策：Requirement Lint + 复杂度路由**
   - 执行 requirement lint（详见 references/phase1-requirements.md § 1.1.7）
   - 如 `flags >= 2` → 先进入澄清预检
   - 复杂度分级路由：参见 autopilot skill 的 parallel-phase1 章节，决定调研 agent 数量（低=单路 / 中=双路 / 高=三路）
3. **并行调研 + 串行汇总**：派发 ScanAgent + ResearchAgent + SynthesizerAgent。详见 references/phase1-requirements.md § 1.2-1.4 与 references/phase1-requirements-detail.md § 1.3.5。要点：
   - Sub-Agent 名称硬解析（详见 skills/autopilot-dispatch/SKILL.md）
   - 进度写入：`bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/write-phase-progress.sh 1 research_dispatched in_progress`
   - **maturity 退化分支**（Step 1.2.2）：当 `verdict.maturity == "mature"` 或 ScanAgent envelope `maturity != "fresh"` 时，**mature 仅跑 ScanAgent**（跳过 ResearchAgent 派发，直接进入 SynthesizerAgent）
   - **早停 interrupt 协议**：ScanAgent / ResearchAgent envelope 可携带可选字段 `interrupt: { severity, reason }`：
     - 当 `severity == "blocker"` 时：**立即中断未完成路**（对剩余 `run_in_background: true` 任务执行 Task abort），跳过 SynthesizerAgent，直接 AskUserQuestion 使用 `interrupt.reason` 原文询问用户
     - 当 `severity == "warning"` 时：**仅记录**到 SynthesizerAgent 输入与最终 `verdict.rationale`，不中断流程
     - **禁止行为**：禁止忽略 interrupt 字段、禁止 blocker interrupt 收到后继续派发 SynthesizerAgent
   - verdict 中间 checkpoint 等其他细节均在 references/phase1-requirements.md
4. **派发 Synthesizer 并汇合 verdict**：写入 `context/phase1-verdict.json` 是 BA 输入的唯一权威源。详见 references/phase1-requirements.md § 1.4。
   - **verdict-driven AskUserQuestion 分支**：基于 `verdict.requires_human` 与 `verdict.ambiguities` 判定是否进入用户澄清；`requires_human=true` 必须通过 AskUserQuestion 询问，禁止主线程自行假设
5. **复杂度评估与分路**：基于 `verdict.merged_decision_points` 数量 + ScanAgent envelope `complexity` 字段自动分类为 small/medium/large。
6. **派发需求分析 Agent**（`config.phases.requirements.agent`）：
   - 进度写入：`bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/write-phase-progress.sh 1 ba_dispatched in_progress`
   - BA 输入唯一权威源 = `verdict.merged_decision_points` + `verdict.conflicts(resolution=adopted)` + 用户澄清答复
   - 主线程**不读取** `requirements-analysis.md` 全文
   - 详见 references/phase1-requirements.md § 1.5
6.5. **主动讨论协议** — 基于 verdict + BA 产出，构造决策卡片（方案/优劣/推荐），通过 AskUserQuestion 由用户决策。详见 references/phase1-requirements.md § 1.6。
7. **多轮决策 LOOP**（弹性收敛） — 以混合清晰度评分（规则×0.6 + AI×0.4）作为退出条件。Medium/Large 遵循一次一问原则。挑战代理在第 4/6/8 轮自动激活视角转换。安全阀：soft=8 轮提醒，hard=15 轮上限。详见 references/phase1-clarity-scoring.md 与 references/phase1-challenge-agents.md。每轮决策完成后写入中间态 checkpoint（详见 references/phase1-requirements.md § 1.7）。
8. **生成结构化提示词** → 必须通过 AskUserQuestion 工具展示提示词并让用户确认（严禁纯文字输出确认，详见 references/phase1-requirements.md § 1.8）。
9. **派发 PackagerAgent**（`subagent_type` 复用 `phases.requirements.synthesizer.agent`）基于 `verdict.json + requirements-analysis.md` 全文合成 `requirement-packet.json`（schema: `runtime/schemas/requirement-packet.schema.json`，必填 `goal/scope/non_goals/acceptance_criteria/risks/decisions/needs_clarification/sha256`）；主线程仅 Read packet.json 后写入 `phase-1-requirements.json` checkpoint + git fixup（后台 Checkpoint Agent）。严禁主线程自行压缩信封合成 packet。详见 references/phase1-requirements.md § 1.9。
   写入最终 checkpoint 后，删除中间态文件：`Bash('rm -f ${phase_results}/phase-1-interim.json')`
10. **可配置用户确认点**（`config.gates.user_confirmation.after_phase_1`，**默认 false**）：
    - 当配置为 `false` 时，Phase 1 checkpoint 写入成功后**必须直接进入后续 Phase**
    - **禁止**追加"是否继续 OpenSpec/是否先审查输出"之类的元问题
    - 允许输出一句状态提示，例如：`Phase 1 ✓ checkpoint persisted, continuing to Phase 2`

### Step 11: 发射 Phase 1 结束事件

```
Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-phase-event.sh phase_end 1 {mode} \'{"status":"{envelope.status}","duration_ms":{elapsed},"artifacts":["phase-1-requirements.json"],"requirement_packet_hash":"{requirement_packet.hash}","clarity_score":{clarity_score},"discussion_rounds":{discussion_rounds},"challenge_agents_activated":{challenge_agents_json}}\'')
```

**注意**: `{requirement_packet.hash}` 必须从步骤 9 写入的 `requirement-packet.json` 的 `hash` 字段获取。若未生成 requirement-packet.json，使用 `null`。`{clarity_score}` 为浮点数（如 0.85），`{discussion_rounds}` 为整数，`{challenge_agents_json}` 为 JSON 数组字符串（如 `["contrarian","simplifier"]`）。若未使用清晰度系统，使用 `null`。

---

## 输出

Phase 1 完成后，主编排器获得：

| 数据 | 用途 |
|------|------|
| requirement_packet | 结构化需求包（含 hash） |
| change_name | kebab-case 变更名称 |
| complexity | small/medium/large |
| decisions | 用户决策列表 |
