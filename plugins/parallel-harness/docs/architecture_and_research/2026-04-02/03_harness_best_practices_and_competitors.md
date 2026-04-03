# 03. Harness 思想、最佳实践与竞品矩阵

## 1. 本项目里的 harness 到底指什么

在 `parallel-harness` 语境里，harness 不是“多开几个 agent”，也不是“把 prompt 写得更长”。它至少要完成八件事：

1. 结构化理解需求
2. 把工作拆成可调度的图
3. 为每个任务分配最小必要上下文
4. 在执行前定义边界、权限和预算
5. 在执行中保证隔离、可追踪和可恢复
6. 在执行后做独立验证，而不是作者自评
7. 把代码、测试、设计、计划和报告沉淀成可追溯工件
8. 允许人类在高风险点审批、介入和恢复

## 2. 社区当前已经收敛的最佳实践

### 2.1 先把单 agent 做稳，再拆多 agent

OpenAI `A practical guide to building agents` 的建议很明确：

- 先最大化单 agent 的工具和结构化指令能力
- 只有在复杂逻辑、工具过载、职责分离确实需要时，再引入多 agent

这意味着：

- “多 agent”不是默认答案
- “图驱动调度 + 明确 handoff 原语”才是多 agent 正确打开方式

### 2.2 多 agent 应被建模为图，而不是聊天树

OpenAI 对 manager pattern / handoff pattern 的描述、Google ADK 对 `SequentialAgent / ParallelAgent / LoopAgent` 与 multi-agent hierarchy 的划分，都指向一个共识：

- 编排必须是显式图
- graph 节点负责职责
- graph 边负责依赖、handoff、并行或串行关系

### 2.3 subagent 的第一价值是切上下文

Anthropic `Claude Code Subagents` 文档明确指出：

- subagent 使用独立 context window
- 可以配置不同工具权限
- 其关键收益是避免主会话被污染

这和 LangGraph / OpenAI handoff 的理念一致：  
agent specialization 首先是上下文隔离，而不是“同时说话的人更多”。

### 2.4 guardrails 必须是阻断式，而不是记日志式

官方资料已很一致：

- OpenAI：guardrails 是 layered defense，需要与权限、鉴权、人审结合
- Anthropic：hooks 可以在 `PreToolUse`、`UserPromptSubmit`、`SubagentStop` 等点位直接 block
- OpenAI Agents SDK：工具级审批与 resume 是一等原语

因此最佳实践不是“事后警告”，而是：

- 在错误动作发生前就阻断
- 把批准 / 拒绝 / 恢复建成正式状态机

### 2.5 durable state 与 resume 是长流程 agent 的基础设施

LangGraph、OpenAI Agents SDK、Google ADK 都把下列能力前置为运行时能力：

- 持久化状态
- 可恢复 run
- human-in-the-loop
- tracing / debugging

这说明生产级 harness 不应该依赖“把历史对话重新塞回去”恢复，而要依赖结构化状态与 checkpoint。

### 2.6 仓库内知识必须成为系统真相源

OpenAI `Harness engineering` 给出的经验非常直接：

- 不要用一个庞大的 `AGENTS.md` 当百科全书
- 把仓库中的 `docs/`、计划、设计、质量说明作为 source of truth
- 用短入口文档做目录，而不是做巨型说明书

对 harness 的含义是：

- 文档不是附属品，而是 agent 能否稳定工作的输入系统
- 计划、设计、测试、质量说明都应版本化并可检查

### 2.7 可观测性必须对 agent 本身也可见

OpenAI `Harness engineering` 还强调：

- agent 需要直接可见 UI、日志、指标、trace
- 最好是 worktree 级隔离环境和 worktree 级 observability stack

OpenHands runtime 文档也强调：

- Docker sandbox、client-server runtime、可复现环境

这说明高可靠 harness 不只是“会写代码”，而是“能在隔离环境里验证代码和观测行为”。

### 2.8 评估和专业报告必须基于证据，不基于 agent 自述

OpenAI agent evals / graders、OpenAI 对 SWE-bench Verified 的退出说明，以及 Cursor Bugbot、Devin Session Insights，都指向同一个趋势：

- 评估结果需要 trace、grader、证据和会后分析
- “模型说自己修好了”不再被当作可信输出

## 3. 对 parallel-harness 最重要的最佳实践提炼

基于上述共识，`parallel-harness` 应明确坚持下面九条路线：

1. 先 graph-first，再 parallel-first。
2. 先把单条运行时主链做稳，再扩多 worker。
3. 多 worker 的第一价值是 context isolation。
4. guardrails 必须 block，而不是只 emit log。
5. 隔离执行环境优先于事后 merge 检查。
6. 文档、计划和规则必须进仓库并可校验。
7. hidden verification 必须成为标准能力。
8. 控制面必须支持 pause / approve / reject / resume。
9. 报告必须引用 evidence，而不是复述成功叙事。

## 4. 竞品与框架能力矩阵

> 口径：以下只记录 `2026-04-02` 能从官方资料明确确认或保守推断的能力。

| 方案 | 类型 | 编排原语 | 上下文隔离 | 状态 / 恢复 | 阻断式治理 | 隔离执行环境 | Repo / PR 工作流 | 评估 / 报告 |
|------|------|----------|------------|-------------|------------|--------------|------------------|-------------|
| OpenAI Agents SDK | 运行时框架 | agents / handoffs / guardrails | 中 | 强 | 强 | 工具级 | 弱 | 强 |
| Claude Code | coding agent 产品 | subagents / hooks / slash commands | 强 | 中 | 强 | 中 | 强 | 中 |
| LangGraph | 底层编排框架 | state graph / nodes / edges | 中 | 强 | 中 | 应用自建 | 弱 | 强 |
| Google ADK | 编排框架 | LLM / Workflow / Custom / Parallel agents | 中 | 中到强 | 中 | 应用自建 | 弱 | 中 |
| Cursor Background Agents | coding agent 产品 | 后台 agent + follow-up | 中到强 | 中 | 中 | 强 | 强 | 中 |
| Cursor Bugbot | PR review 产品 | PR 触发审阅 | 局部 | 中 | 中 | 平台托管 | 强 | 强于 review 场景 |
| Devin | 产品级软件工程代理 | 会话、知识、集成触发 | 中 | 中到强 | 中 | 平台托管 | 强 | 强 |
| OpenHands | 开源工程代理平台 | runtime + actions | 中 | 中 | 中 | 强 | 中 | 中 |
| parallel-harness 当前 | 仓库内插件 | TaskGraph + Ownership + Scheduler | 中 | 强 | 中 | 弱到中 | 中 | 弱到中 |

## 5. 逐项对比摘要

### 5.1 OpenAI Agents SDK

已确认能力：

- `Agents / Handoffs / Guardrails`
- tracing
- HITL tool approvals + resume
- sessions / run state
- agent evals / graders

启示：

- `parallel-harness` 应把审批、resume、guardrail、trace 继续下沉到运行时原语层，而不是停留在外围脚本。

### 5.2 Claude Code

已确认能力：

- subagents 有独立 context window
- 每个 subagent 可配置不同工具权限
- hooks 可在 `PreToolUse` / `UserPromptSubmit` 等点位阻断
- 权限策略可以团队级分发

启示：

- `parallel-harness` 的 worker / verifier / planner 角色应做成真正独立上下文和独立权限面。

### 5.3 LangGraph

已确认能力：

- durable execution
- human-in-the-loop
- persistence
- debugging / tracing with LangSmith
- graph-based orchestration

启示：

- 当前 `parallel-harness` 已经有 graph-first 方向，但生命周期阶段、stateful memory、可视化调试还没有被统一起来。

### 5.4 Google ADK

已确认能力：

- 多 agent hierarchy
- `SequentialAgent / ParallelAgent / LoopAgent`
- model-agnostic、deployment-agnostic
- A2A 协作

启示：

- `parallel-harness` 的下一阶段可以借鉴“确定性 workflow agent + 非确定性 LLM agent”混合建模，而不是让所有阶段都由自由文本 agent 决定。

### 5.5 Cursor Background Agents / Bugbot

已确认能力：

- 后台 agent 在隔离 Ubuntu 机器上运行
- 可编辑和运行代码
- 可接管
- Bugbot 做 PR 审阅，并支持 `.cursor/BUGBOT.md` 作为项目级规则

启示：

- 并行编码如果没有隔离环境，可靠性上限很低。
- PR 审阅上下文应该是 repo-scoped、path-scoped 的文档输入，而不是统一大 prompt。

### 5.6 Devin

已确认能力：

- Knowledge 在所有 session 中可复用
- Session Insights 提供会后分析与改进建议
- 可从历史工单 / PR 生成 Linear Knowledge

启示：

- `parallel-harness` 不应只停留在“运行时正确”，还需要“运行后复盘”和“跨 session 组织知识沉淀”。

### 5.7 OpenHands

已确认能力：

- 默认 Docker runtime
- 本地 runtime 明确警告“无 sandbox 隔离”
- runtime client-server architecture
- remote runtime 用于并行评估，但仍处 beta

启示：

- 当前 `parallel-harness` 应把“隔离执行等级”明确写进产品能力，而不能把软约束包装成强隔离。

## 6. 对 parallel-harness 的竞品差距总结

当前最明显的差距不在“有没有 task graph”，而在下面五件事：

1. **没有把隔离执行做硬**  
   Cursor / OpenHands / OpenAI harness 都把 worktree、isolated runtime、observability 视为核心基础设施。

2. **没有把 repo knowledge 做成系统真相源治理体系**  
   OpenAI harness 和 Devin 都强调 knowledge、plans、docs 的版本化和可持续维护。

3. **没有把 verifier plane 接成独立运行面**  
   当前 still mostly 是执行后 gate，而不是独立 verifier 网络。

4. **没有把专业报告模板接入主链**  
   Devin Session Insights、OpenAI agent evals 都强调 post-run analysis；当前 `parallel-harness` 仍以轻量工程摘要为主。

5. **没有把多阶段工件做成真正的一等对象**  
   当前更像“代码实现 harness”，还不是“产品全流程 harness”。

## 7. 参考资料

以下资料于 `2026-04-02` 核对：

- OpenAI Agents SDK  
  https://openai.github.io/openai-agents-python/
- OpenAI Agents SDK: Human-in-the-loop  
  https://openai.github.io/openai-agents-python/human_in_the_loop/
- OpenAI Agent evals  
  https://platform.openai.com/docs/guides/agent-evals
- OpenAI Graders  
  https://platform.openai.com/docs/guides/graders/
- OpenAI Harness engineering  
  https://openai.com/index/harness-engineering/
- OpenAI A practical guide to building agents  
  https://cdn.openai.com/business-guides-and-resources/a-practical-guide-to-building-agents.pdf
- Anthropic Claude Code Subagents  
  https://docs.anthropic.com/en/docs/claude-code/sub-agents
- Anthropic Claude Code Hooks  
  https://docs.anthropic.com/en/docs/claude-code/hooks
- Anthropic Claude Code Team / IAM  
  https://docs.anthropic.com/en/docs/claude-code/team
- LangGraph overview  
  https://docs.langchain.com/oss/python/langgraph
- Google Agent Development Kit  
  https://google.github.io/adk-docs/
- Google ADK multi-agent systems  
  https://google.github.io/adk-docs/agents/multi-agents/
- Cursor Background Agents  
  https://docs.cursor.com/en/background-agents
- Cursor Bugbot  
  https://docs.cursor.com/en/bugbot
- Devin Knowledge onboarding  
  https://docs.devin.ai/zh/onboard-devin/knowledge-onboarding
- Devin Session Insights  
  https://docs.devin.ai/product-guides/session-insights
- OpenHands runtime overview  
  https://docs.all-hands.dev/usage/runtimes
- OpenHands local runtime  
  https://docs.all-hands.dev/modules/usage/runtimes/local
- OpenHands runtime architecture  
  https://docs.all-hands.dev/openhands/usage/architecture/runtime

## 8. 本文结论

社区现在已经很明确：

**生产级 harness 的关键竞争力，不在“能不能让 agent 写代码”，而在“能不能让 agent 在可恢复、可隔离、可验证、可审计的工程闭环里稳定写代码”。**

这正是 `parallel-harness` 应该继续强化的方向。
