---
name: autopilot-phase1-requirements
description: "Use when autopilot orchestrator enters Phase 1 to understand requirements, dispatch parallel research (ScanAgent / ResearchAgent / SynthesizerAgent), drive multi-round clarification decisions with hybrid clarity scoring and challenge agents, and produce the structured requirement packet checkpoint."
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

## Step 0: 发射 Phase 1 开始事件（Event Bus 补全）

```
Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-phase-event.sh phase_start 1 {mode}')
```

## 概要流程

1. 获取需求来源（$ARGUMENTS 解析）
2. **前置决策：Requirement Lint + 复杂度路由**（策略统一）
   - 执行 requirement lint（参见 `references/phase1-requirements.md` Step 1.1.7）
   - 如 `flags >= 2` → 先进入澄清预检（Step 1.1.7），完成后再派发调研
   - 按 `../autopilot/references/parallel-phase1.md:85-93` 复杂度分级路由决定调研 agent 数量：
     - 低复杂度（纯 bugfix/chore）→ 单路调研（Auto-Scan only）
     - 中复杂度 → 双路调研（Auto-Scan + 技术调研）
     - 高复杂度 → 三路调研（Auto-Scan + 技术调研 + 联网搜索）
3. **并行调研 + 串行汇总** → 读取 `../autopilot/references/parallel-phase1.md` 并行配置 + SynthesizerAgent 四要素契约。
   > **Agent 事件**: Hook `auto-emit-agent-dispatch.sh` 自动为每个含 phase marker 的 Task 发射 `agent_dispatch` 事件，无需手动调用。
   > **Sub-Agent 名称硬解析协议（强制，三路独立）**: 派发前必须将 `config.phases.requirements.auto_scan.agent` / `.research.agent` / `.synthesizer.agent` 三个字段分别替换为实际已注册 Agent 名（不得留 `{{...}}` 或 `config.phases.` 字面量），并各自调用 `bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/validate-agent-registry.sh "<resolved_name>"` 校验；任一失败立即返回 blocked 信封。详见 `skills/autopilot-dispatch/SKILL.md` 之 "Sub-Agent 名称硬解析"。
   **进度写入**: Bash('AUTOPILOT_PROJECT_ROOT=$(pwd) bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/write-phase-progress.sh 1 research_dispatched in_progress')

   **Step 1.2.1** 并行派发 ScanAgent + ResearchAgent，**同一条消息内**同时发起两个 `Task(run_in_background=true)`（按复杂度路由可降级为单路 ScanAgent，详见 `../autopilot/references/parallel-phase1.md` 成熟度路由）：

   ```
   ┌─ ScanAgent (config.phases.requirements.auto_scan.agent) → Steering Documents      ← 始终执行
   └─ ResearchAgent (config.phases.requirements.research.agent) → research-findings.md  ← maturity ∈ {partial, ambiguous} 时执行
   ```

   **Step 1.2.2** 等待两路完成（Claude Code Hook 自动通知 `agent_complete`），主线程**仅消费 JSON 信封**：
   - 验证产出文件存在（按 maturity 条件分支）：
     ```
     if [[ "$maturity" != "mature" ]]; then
       Bash("test -s context/project-context.md && test -s context/research-findings.md && echo ok")
     else
       Bash("test -s context/project-context.md && echo ok")  # mature 仅跑 ScanAgent
     fi
     ```
   - 不 Read 任何调研正文（上下文隔离红线）

   **Step 1.2.3** 串行派发 SynthesizerAgent（前台 Task，**不与前两路并行**），传入两路 envelope 摘要 + 产出文件路径：
   - **退化分支（mature 单路）**：当 `maturity == "mature"` 仅派发了 ScanAgent 时，**跳过 SynthesizerAgent**，主线程直接消费 ScanAgent envelope 的 `decision_points` 作为后续 BA 输入；不写 `phase1-verdict.json`，Step 1.2.4-1.2.6 改为消费 ScanAgent envelope（`requires_human` / `ambiguities` 字段直接来自 ScanAgent envelope）
   - **正常分支（partial / ambiguous）**：派发 SynthesizerAgent
     - SynthesizerAgent 自行 Read context/*.md 全文
     - 跨路冲突检测 + 语义去重 + ambiguities 标注
     - Write `context/phase1-verdict.json`（schema: `runtime/schemas/synthesizer-verdict.schema.json`）

   **Step 1.2.4** 主线程 `Read(openspec/changes/<name>/context/phase1-verdict.json)`（**仅 verdict，不读 raw 全文**）。

   **Step 1.2.5** if `verdict.requires_human == true` OR `len(verdict.ambiguities) > 0` → 通过 AskUserQuestion 把每条 ambiguity 转换为决策卡片，收集用户澄清答复。

   **Step 1.2.6** 进入 1.5 BA Agent 派发：BA Agent 输入 = `verdict.merged_decision_points + verdict.conflicts(resolution=adopted) + 用户澄清答复`（不再注入两路调研原始 envelope）。

   **Step 1.2.7 早停 interrupt 协议（D11 单路 interrupt 早停）**：
   主线程在 Step 1.2.2 wait 期间，**每完成一路 envelope 接收即立刻** `jq -e '.interrupt'` 解析；不得延迟到双路全部归集。两个 envelope schema (phase1-scan-envelope / phase1-research-envelope) 已新增可选字段 `interrupt: { severity: "blocker"|"warning", reason: string(>=5) }`。

   - 当 `.interrupt.severity == "blocker"` 时：
     1. **立即中断未完成路**：对所有仍在 `run_in_background: true` 状态的并行 Task abort（KillShell 后台任务句柄；若 Task tool 提供中断信号则优先使用其原生 abort）
     2. **跳过 SynthesizerAgent 派发**：不进入 Step 1.2.3，不写 `phase1-verdict.json`
     3. **直接 AskUserQuestion**：问题正文使用 `.interrupt.reason` 原文，选项至少包含：
        - (a) 提供澄清后重启 Phase 1（重新派发 ScanAgent + ResearchAgent，携带新澄清入参）
        - (b) 接受 blocker 并降级为 partial verdict
        - (c) 中止流水线（exit Phase 1，写 abort checkpoint）
     4. 若用户选 (b)：主线程合成最小 `phase1-verdict.json`，包含 `requires_human=true`、`confidence=0.0`、`ambiguities=["[NEEDS CLARIFICATION: " + interrupt.reason + "]"]`，并标注 `degraded_from_interrupt=true`，跳过 Step 1.2.3 直接进入 Step 1.2.4
   - 当 `.interrupt.severity == "warning"` 时：**仅记录**到 SynthesizerAgent 输入 + 最终 `verdict.rationale`，**不中断流程**，不影响并行另一路继续执行
   - **禁止行为**：
     - ❌ **禁止**：忽略 interrupt 字段（不解析 / 不分流处理）
     - ❌ **禁止**：blocker interrupt 收到后继续派发 SynthesizerAgent
     - ❌ **禁止**：blocker interrupt 收到后等待另一路自然完成再处理（必须立即 Task abort）

   **联网搜索决策**：默认执行搜索（`search_policy.default: search`），仅当任务**同时满足所有跳过条件**时才跳过：
   - ✓ 纯内部代码变更（重构、bug 修复、样式微调）
   - ✓ 不引入新概念、新模式、新交互
   - ✓ 项目 `rules/` 或 `specs/` 已有明确规范覆盖
   - ✓ codebase 中已有同类实现可参照
   判定由规则引擎执行（非 AI 自评），详见 `references/phase1-requirements.md` 1.3.3 节；联网调研以 ResearchAgent 子任务方式执行（depth=deep 时）。
   **强制并行约束**：Step 1.2.1 中 ScanAgent + ResearchAgent **必须在同一条消息中**同时发起（全部 `run_in_background: true`）；SynthesizerAgent 仅在 Step 1.2.3 单独派发。
   - ❌ **禁止**：逐个发起 ScanAgent / ResearchAgent，等前一个完成再发下一个
   - ❌ **禁止**：将 SynthesizerAgent 与前两路一起派发（必须串行等待）
   - ❌ **禁止**：使用 TaskOutput 检查后台 Agent 进度（TaskOutput 仅适用于 Bash 后台命令）
   - ✅ **正确**：一条消息含 2 个 `Task(run_in_background: true)` 派发 ScanAgent + ResearchAgent；下一条消息含 1 个 `Task` 派发 SynthesizerAgent
   优先读取持久化上下文（`openspec/.autopilot-context/`），7 天内有效则跳过 ScanAgent 仅做增量
4. **派发 Synthesizer 并汇合 verdict**（串行汇总，唯一权威源）→ 子 Agent 自行 Write 产出文件 + 返回结构化 JSON 信封，主线程**不读取调研正文**：
   > **Agent 事件**: Hook `auto-emit-agent-complete.sh` 自动为每个完成的 autopilot Task 发射 `agent_complete` 事件，无需手动调用。
   - 验证产出文件存在（按 maturity 分支，参见 Step 1.2.2）
   - 派发 SynthesizerAgent 完成跨路冲突检测 + 语义去重 + ambiguities 标注（参见 Step 1.2.3）
   - 主线程仅 Read `context/phase1-verdict.json`（**verdict.json 是 BA 输入的唯一权威源**），不再消费各路 envelope 的 `decision_points`
   - 退化分支（maturity=mature）：跳过 Synthesizer，直接消费 ScanAgent envelope 字段（参见 Step 1.2.3 退化分支）
   产出文件列表（子 Agent 自行写入）：
   - `context/project-context.md` + `existing-patterns.md` + `tech-constraints.md`（ScanAgent）
   - `context/research-findings.md`（ResearchAgent，已合并联网搜索；maturity=mature 时不产出）
   - `context/phase1-verdict.json`（SynthesizerAgent，schema: `runtime/schemas/synthesizer-verdict.schema.json`；maturity=mature 时不产出）
   **中间 Checkpoint — verdict 落盘后**: SynthesizerAgent 完成且 `phase1-verdict.json` 落盘后立即写入中间态 checkpoint，防止崩溃丢失汇合进度：

   ```
   Agent(run_in_background: true, prompt: "<!-- checkpoint-writer -->
     Write JSON to ${phase_results}/phase-1-interim.json:
     {\"status\":\"in_progress\",\"stage\":\"verdict_complete\",
      \"verdict_path\":\"context/phase1-verdict.json\",
      \"merged_decision_points_count\":N,\"conflicts_count\":M,
      \"ambiguities_count\":K,\"requires_human\":true|false,
      \"timestamp\":\"ISO-8601\"}
     Then: git add -A && git commit --fixup=$ANCHOR_SHA -m 'fixup! autopilot: Phase 1 interim (verdict)'")
   ```

5. **复杂度评估与分路** → 基于 `verdict.merged_decision_points` 数量 + ScanAgent envelope `complexity` 字段（mature 退化时直接消费 envelope `decision_points` 数量）自动分类为 small/medium/large，决定讨论深度
6. Task 调度需求分析 Agent（`config.phases.requirements.agent`，默认 general-purpose；可通过 `/autopilot-agents install` 安装专业 Agent）分析需求（`run_in_background: true`）：
   > **Agent 事件**: Hook 自动发射 agent_dispatch/complete，无需手动调用。
   **进度写入**: Bash('AUTOPILOT_PROJECT_ROOT=$(pwd) bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/write-phase-progress.sh 1 ba_dispatched in_progress')
   - **BA 输入唯一权威源 = `verdict.merged_decision_points` + `verdict.conflicts(resolution=adopted)` + 用户澄清答复**（mature 退化时改为 ScanAgent envelope `decision_points` + 用户澄清答复）
   - 子 Agent 自行 Read context/ 全部文件，将完整分析 Write 到 `context/requirements-analysis.md`
   - 等待 Claude Code 自动完成通知
   - 从 JSON 信封提取：`decision_points`、`requirements_summary`、`open_questions`
   - 主线程**不读取** `requirements-analysis.md` 全文
5.5. **主动讨论协议** — 基于 `verdict.merged_decision_points`（mature 退化时为 ScanAgent envelope `decision_points`） + 需求分析 Agent（`config.phases.requirements.agent`）产出，构造决策卡片（方案/优劣/推荐），通过 AskUserQuestion 由用户决策
7. **多轮决策 LOOP**（弹性收敛重构） — 以混合清晰度评分（规则×0.6 + AI×0.4）作为退出条件，而非硬性轮数上限。Medium/Large 遵循一次一问原则。挑战代理在第 4/6/8 轮自动激活视角转换（反面论证/简化/本体论）。停滞检测在连续 2 轮波动 ≤5% 时干预。安全阀: soft=8轮提醒, hard=15轮上限。`min_qa_rounds` 保留为下限。
   **执行前读取**: `references/phase1-clarity-scoring.md` + `references/phase1-challenge-agents.md`

   **中间 Checkpoint — 每轮决策后**: 每轮决策 LOOP 完成后，覆盖写入中间态 checkpoint，防止崩溃丢失用户决策：

   ```
   Agent(run_in_background: true, prompt: "<!-- checkpoint-writer -->
     Write JSON to ${phase_results}/phase-1-interim.json:
     {\"status\":\"in_progress\",\"stage\":\"decision_round_N\",
      \"round\":N,\"decisions_resolved\":[...],\"decisions_pending\":[...],
      \"timestamp\":\"ISO-8601\"}
     Then: git add -A && git commit --fixup=$ANCHOR_SHA -m 'fixup! autopilot: Phase 1 interim (decision round N)'")
   ```

8. 生成结构化提示词 → **必须通过 AskUserQuestion 工具**展示提示词并让用户确认（严禁纯文字输出确认，详见 `references/phase1-requirements.md` 1.8 节）
9. 派发 **PackagerAgent**（`subagent_type` 复用 `phases.requirements.synthesizer.agent`）基于 `verdict.json + requirements-analysis.md` 全文合成 `requirement-packet.json`（schema: `runtime/schemas/requirement-packet.schema.json`，必填 `goal/scope/non_goals/acceptance_criteria/risks/decisions/needs_clarification/sha256`）；主线程仅 Read packet.json 后写入 `phase-1-requirements.json` checkpoint + git fixup（后台 Checkpoint Agent）。严禁主线程自行压缩信封合成 packet。详见 `references/phase1-requirements.md` Step 1.9.1–1.9.4。
   写入最终 checkpoint 后，删除中间态文件：`Bash('rm -f ${phase_results}/phase-1-interim.json')`
10. 可配置用户确认点（`config.gates.user_confirmation.after_phase_1`，**默认 false**——需求评审完成后默认自动推进）

- 当该配置为 `false` 时，Phase 1 checkpoint 写入成功后**必须直接进入后续 Phase**
- **禁止**在此处追加"是否继续 OpenSpec/是否先审查输出"之类的元问题
- 允许输出一句状态提示，例如：`Phase 1 ✓ checkpoint persisted, continuing to Phase 2`

1. **发射 Phase 1 结束事件**:
    `Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-phase-event.sh phase_end 1 {mode} \'{"status":"{envelope.status}","duration_ms":{elapsed},"artifacts":["phase-1-requirements.json"],"requirement_packet_hash":"{requirement_packet.hash}","clarity_score":{clarity_score},"discussion_rounds":{discussion_rounds},"challenge_agents_activated":{challenge_agents_json}}\'')`
    **注意**: `{requirement_packet.hash}` 必须从步骤 8 写入的 `requirement-packet.json` 的 `hash` 字段获取。若未生成 requirement-packet.json，使用 `null`。`{clarity_score}` 为浮点数（如 0.85），`{discussion_rounds}` 为整数，`{challenge_agents_json}` 为 JSON 数组字符串（如 `["contrarian","simplifier"]`）。若未使用清晰度系统，使用 `null`。

---

## 输出

Phase 1 完成后，主编排器获得：

| 数据 | 用途 |
|------|------|
| requirement_packet | 结构化需求包（含 hash） |
| change_name | kebab-case 变更名称 |
| complexity | small/medium/large |
| decisions | 用户决策列表 |
