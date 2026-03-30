# 03. Harness 核心思想、最佳实践与竞品调研

## 1. 什么是 AI Harness

在本项目语境里，AI Harness 不是单纯的 agent framework，也不是多开几个子 agent。它本质上是一层 **约束、编排、验证、审计和恢复机制**，目标是让本来高度随机的 LLM 行为，在工程交付场景中变成：

- 可拆解
- 可并行
- 可验证
- 可恢复
- 可审计
- 可治理

因此，一个优秀的 Harness 至少要回答六个问题：

1. 任务如何拆？
2. 任务如何并行且不互相踩？
3. 每个任务该看哪些上下文？
4. 谁来验证结果而不是让作者自评？
5. 出错以后如何恢复，而不是重跑整局？
6. 整个过程如何对人类和控制面可见？

## 2. parallel-harness 的目标定位

从 README 与代码设计看，`parallel-harness` 的独特目标不是“通用 agent 开发框架”，而是面向 **研发交付全生命周期** 的并行控制平面，尤其强调：

- task graph
- ownership isolation
- gate system
- RBAC / approval
- audit trail
- PR/CI integration

这意味着它与 LangGraph / AutoGen / OpenAI Agents SDK 并非完全同类竞争关系。更准确地说：

- 那些框架更像“搭系统的基础设施”
- `parallel-harness` 想成为“面向代码交付的治理型 harness 产品”

## 3. 社区最佳实践提炼

### 3.1 Graph-First Orchestration

最佳实践来源：

- LangGraph 把 stateful, long-running workflow 作为核心定位。
- AutoGen 提供 message-passing / event-driven runtime。

可提炼的原则：

- 复杂任务必须先建图，不应直接进入自由对话式 agent loop。
- 图里必须包含依赖、风险、边界、恢复点，而不只是任务标题。

### 3.2 Durable Execution / Session State

最佳实践来源：

- LangGraph 明确主打 durable execution。
- OpenAI Agents SDK 把 sessions/context strategies 作为一等能力。

可提炼的原则：

- 恢复应该基于结构化状态，而不是“重新喂完整历史”。
- 长流程必须天然支持 checkpoint、resume、interrupt。

### 3.3 Specialist Delegation / Handoffs / Subagents

最佳实践来源：

- OpenAI Agents SDK 把 handoffs 和 agents-as-tools 作为核心概念。
- Claude Code 官方提供 subagents。
- CrewAI 将 Crews 和 Flows 分离，强调自治与流程控制并存。

可提炼的原则：

- 专家分工是必要的，但必须以明确边界为前提。
- delegation 不是越多越好，关键是 write-set、输入合同和 completion condition。

### 3.4 Guardrails / Hooks / Human-in-the-Loop

最佳实践来源：

- OpenAI Agents SDK 提供 blocking/parallel guardrails 和 tripwires。
- Claude Code 提供 hooks 与 settings。
- LangGraph 提供 human-in-the-loop / interrupts。

可提炼的原则：

- 真正可靠的系统要能在执行前、执行中、执行后介入。
- 守卫不应只是日志，而应具备阻断和审批语义。

### 3.5 Observability / Tracing / Control Plane

最佳实践来源：

- OpenAI Agents SDK 提供 tracing。
- LangGraph 与 LangSmith 组合强调可视化和调试。
- CrewAI README 明确把 tracing / unified control plane 当成企业卖点。

可提炼的原则：

- 多 agent 系统没有 trace 就没有生产可维护性。
- 控制面必须能回答：谁在做什么、为什么被阻断、花了多少钱、证据是什么。

### 3.6 Codebase-Native Constraints

在代码交付场景里，通用 agent framework 的通病是“会 orchestration，但不会真正约束写边界”。这正是 `parallel-harness` 最有机会建立差异化的位置：

- 文件所有权
- diff attestation
- PR/CI 原生集成
- 审批与审计

## 4. 竞品矩阵

| 方案 | 核心定位 | 状态/恢复 | 多 agent / delegation | Guardrails / 审批 | 观测 / tracing | 代码交付约束 | 对 parallel-harness 的启示 |
|------|----------|-----------|-----------------------|-------------------|----------------|--------------|---------------------------|
| LangGraph | 低层 stateful orchestration framework | 强，官方强调 durable execution | 强，适合复杂图编排 | 有 HITL/interrupts，但不是代码治理产品 | 强，通常与 LangSmith 配合 | 弱到中，需自建代码边界 | 最值得借鉴的是 durable state machine |
| AutoGen | 多 agent 应用框架，偏 runtime / message passing | 中到强，具备 runtime 分层 | 强，AgentChat/Core/Ext 都支持 | 有人机协作与扩展，但治理需自建 | 中 | 弱，代码写边界不是核心能力 | 最值得借鉴的是 event-driven runtime 与分层设计 |
| OpenAI Agents SDK | 轻量多 agent workflow SDK | 强，sessions/context/tracing 明确 | 强，handoffs/agents as tools | 强，guardrails/human in the loop 是一等能力 | 强，tracing 内建 | 弱到中，需要业务方补写边界 | 最值得借鉴的是 guardrails 与 handoff 原语 |
| Claude Code | 代码代理产品 | 中，偏交互式工作流 | 强，subagents 原生 | 强，hooks/settings/permissions 完整 | 中 | 中到强，天然代码库上下文友好 | 最值得借鉴的是 subagents + hooks + 本地工具体验 |
| CrewAI | 多 agent automation + enterprise control plane | 中 | 强，Crews + Flows | 中，更多强调平台控制 | 强，README 强调 tracing/control plane | 弱到中 | 最值得借鉴的是“自治 + 流程控制”双轨模型 |
| parallel-harness（当前） | 并行 AI 工程控制平面插件 | 中，checkpoint/resume 已有骨架 | 中，主要是 batch+worker，不是完整专家网络 | 中到强，审批/RBAC/gates 骨架齐全 | 中到强，审计/控制面已存在 | 强目标、弱落地：ownership 思路好，但执行硬约束未闭环 | 若补齐执行边界和独立验证，有机会形成差异化 |

## 5. 各方案的关键事实

### 5.1 LangGraph

官方 README 把它定义为 “low-level orchestration framework for building stateful agents”，并明确强调：

- durable execution
- human-in-the-loop
- memory
- debugging / observability

这说明 LangGraph 的强项是 **状态机与长流程可靠性**，而不是面向代码交付的强治理。

### 5.2 AutoGen

官方 README 明确写出：

- multi-agent AI applications
- layered and extensible design
- Core API implements message passing, event-driven agents, local and distributed runtime

这说明 AutoGen 的核心竞争力是 **runtime 设计与多 agent 抽象**。

### 5.3 OpenAI Agents SDK

官方 README 与文档表明其核心原语包括：

- agents
- tools
- handoffs
- guardrails
- human in the loop
- sessions
- tracing

这是一套非常清晰的“生产级 agent runtime primitive”集合，尤其值得借鉴的是：

- guardrails 不只是建议，而是有 blocking / tripwire 语义
- sessions/tracing 是系统内建，不是外挂

### 5.4 Claude Code

Claude Code 官方文档显示：

- Overview：它是能读代码、改文件、跑命令、接开发工具的 coding agent
- Subagents：用于任务特定工作流和改进上下文管理
- Hooks：有完整 hook events / I/O / exit codes / MCP hooks 说明
- Settings：支持全局和项目级配置

这说明 Claude Code 的优势是 **本地开发体验、工具接入、subagent 工作流和策略化扩展点**。

### 5.5 CrewAI

官方 README 强调：

- Crews：自治协作
- Flows：生产级事件驱动工作流
- AMP / Control Plane：tracing、unified control plane、security、analytics

这说明 CrewAI 的产品思路非常明确：把“自治 agent 团队”与“企业流程控制面”拆开。

## 6. 对 parallel-harness 最重要的启发

### 6.1 应该借鉴的，不是“多 agent 数量”，而是“状态与约束模型”

从这些竞品看，真正成熟的方案都不是靠“开更多 agent”取胜，而是靠：

- 明确状态对象
- 明确边界对象
- 明确恢复机制
- 明确 guardrail 语义

### 6.2 parallel-harness 的差异化机会

如果只做一般性的 orchestration，`parallel-harness` 会与 LangGraph / AutoGen / OpenAI Agents SDK 正面竞争，胜算不大。它真正的差异化在于：

- 面向代码库写边界的 ownership
- 面向交付质量的 gate system
- 面向研发组织的审批与审计
- 面向提交产物的 PR/CI 原生对接

### 6.3 当前短板

目前 `parallel-harness` 的短板不在“想法”，而在“把想法落实成硬约束”：

- 任务图还不够 repo-aware
- worker 约束仍偏 prompt-based
- merge guard 尚未真正进入执行主链
- gate 里有一部分还是启发式代理项

## 7. 对最佳实践的综合判断

一个面向代码交付的最强 Harness，应该吸收如下组合：

| 来源 | 应吸收能力 |
|------|------------|
| LangGraph | durable execution, state machine, resume |
| AutoGen | event-driven runtime, layered architecture |
| OpenAI Agents SDK | guardrails, handoffs, sessions, tracing |
| Claude Code | subagents, hooks, project-level settings, coding-native UX |
| CrewAI | control plane, event-driven flow, enterprise governance |

换言之，`parallel-harness` 的正确方向不是“再发明一个通用 agent framework”，而是：

**把上述能力压缩进一个面向工程交付、以治理和高保真为中心的 code-delivery harness。**

## 8. 参考来源

以下外部来源均于 **2026-03-27** 访问：

1. LangGraph README  
   https://raw.githubusercontent.com/langchain-ai/langgraph/main/README.md
2. LangGraph Durable Execution 文档  
   https://docs.langchain.com/oss/python/langgraph/durable-execution
3. Microsoft AutoGen README  
   https://raw.githubusercontent.com/microsoft/autogen/main/README.md
4. OpenAI Agents SDK README  
   https://raw.githubusercontent.com/openai/openai-agents-python/main/README.md
5. OpenAI Agents SDK 文档索引 / Guardrails  
   https://openai.github.io/openai-agents-python/llms-full.txt  
   https://openai.github.io/openai-agents-python/guardrails/
6. Claude Code 官方文档  
   https://docs.anthropic.com/en/docs/claude-code/overview  
   https://docs.anthropic.com/en/docs/claude-code/sub-agents  
   https://docs.anthropic.com/en/docs/claude-code/hooks  
   https://docs.anthropic.com/en/docs/claude-code/settings
7. CrewAI README  
   https://raw.githubusercontent.com/crewAIInc/crewAI/main/README.md
