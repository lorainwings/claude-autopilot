# 03. Harness 思想、最佳实践与竞品矩阵

## 1. Harness 在本项目里的准确含义

在 `parallel-harness` 语境里，harness 不是“多开几个 agent”，也不是“把 prompt 写长一点”。它是一套把 AI 约束进真实工程流程的系统，至少要完成七件事：

1. 结构化理解需求
2. 将工作拆成可控任务图
3. 为每个任务分配最小必要上下文
4. 在执行前定义边界、权限和预算
5. 在执行后做独立验证，而不是作者自评
6. 对失败、阻断、审批和恢复有正式状态机
7. 把代码、测试、审计和报告沉淀成可追溯工件

## 2. 本轮调研后的总判断

截至 `2026-03-31`，社区对 harness 的最佳实践已经逐渐收敛到以下共识：

1. 单 agent 能稳做的事，不要急于拆多 agent。
2. 真正需要多 agent 时，必须先建图、再并发。
3. durable state 是长流程 agent 的基础设施，不是可选项。
4. subagent 的核心价值是切上下文，不是堆数量。
5. guardrails / hooks 必须具备阻断语义，否则只是日志。
6. 代码代理必须 repo-native，不能只输出文本。
7. tracing、审计、可回放是生产条件，不是装饰。
8. 没有独立 verifier 和隐藏验证，reward hacking 很难根治。

## 3. 社区最佳实践

### 3.1 graph-first orchestration

最佳实践：

- 先生成任务图、依赖图、风险图
- 再决定哪些任务能并发
- 并发必须由 reservation 或 ownership 证明安全

对 `parallel-harness` 的含义：

- 保持 `TaskGraph + OwnershipPlan + SchedulePlan` 作为主链
- 不要退化成“靠 manager agent 临场决定”

### 3.2 durable execution

LangGraph、OpenAI Agents SDK、Claude Code、Copilot coding agent 都在不同层面强调：

- session
- state
- resume
- tracing
- human-in-the-loop

最佳实践：

- 用结构化 state 恢复，而不是重喂历史对话
- checkpoint 要包含工件引用、审批状态、图状态和证据索引

### 3.3 context minimization

Anthropic 的 Claude Code subagents 明确强调每个 subagent 使用独立上下文窗口；这与 LangGraph、OpenAI handoff 的思想一致。

最佳实践：

- agent specialization 的第一价值是上下文隔离
- author / verifier / planner 使用不同 evidence pack
- 超大上下文优先切任务，不优先扩提示词

### 3.4 hard guardrails

OpenAI Agents SDK 的 guardrails、Anthropic Claude Code hooks、GitHub Copilot agent hooks 都表明：

- guardrail 必须能在危险动作前阻断
- 只在事后“报告危险”并不足够

最佳实践：

- pre-plan 阻断歧义需求
- pre-dispatch 阻断敏感路径、超预算、高风险并发
- pre-merge 阻断证据不足和 release 条件不满足

### 3.5 repo-native delivery

GitHub Copilot coding agent、Cursor background agents、Devin、OpenHands 都说明：

- 代码代理必须工作在真实仓库、真实分支、真实环境里
- PR、diff、review、日志和环境都要进入主流程

最佳实践：

- 输出不是“建议代码”，而是“可审查变更”
- 使用独立工作区或工作树来做安全隔离

### 3.6 independent verification

社区产品和研究都指向同一点：

- 作者与验证者不能是同一条成功叙事
- 测试、评审、安全和发布建议必须由独立链路产出

最佳实践：

- 隐藏测试
- 逆向验证
- tamper detection
- evidence-based reporting

## 4. 竞品矩阵

> 口径：以下只写 `2026-03-31` 能从官方资料明确确认或基于官方资料合理推断的能力。标注“推断”的地方，会在备注里说明。

| 方案 | 官方定位 | 已确认能力 | 强项 | 对 parallel-harness 的启示 |
|------|----------|------------|------|---------------------------|
| LangGraph | 低层长期工作流编排框架 | durable execution、human-in-the-loop、comprehensive memory、debugging with LangSmith | 状态机和恢复 | 借 durable state，不借 UI 形态 |
| OpenAI Agents SDK | 生产级 agent runtime SDK | agents、handoffs、guardrails、sessions、tracing、human-in-the-loop | 原语完整、治理清晰 | 借 handoff、guardrails、tracing、sessions |
| Claude Code | coding agent 产品 | subagents、hooks、slash commands、项目级设置 | 工程交互、上下文隔离、hook 拦截 | 借 subagent context 和 hook 生态 |
| AutoGen | 多 agent framework | event-driven agents、layered runtime、code executors、bench | runtime 分层 | 借 runtime abstraction，不照搬 agent 对话模式 |
| CrewAI | flow / multi-agent / enterprise platform | flows、memory、guardrails、observability、human input、enterprise control plane | 企业控制面 | 借组织级运行与观测能力 |
| GitHub Copilot coding agent | GitHub-native 后台 coding agent | issue/comment 触发、后台执行、临时环境、branch/commit/PR、hooks | repo-native workflow | 借 PR-first、GitHub-native 透明度 |
| Cursor Background Agents | 后台远程 coding agent | 隔离 Ubuntu 机器、repo clone、独立分支、异步接管 | 远程执行与接力 | 借隔离环境与 takeover |
| Devin | AI software engineer 产品 | shell/browser/IDE 工作空间、knowledge、skills、playbooks、session insights | 产品闭环和任务执行体验 | 借 session insights 和可验证完成标准 |
| OpenHands | 开源软件工程 agent 平台 | Docker sandbox runtime、client-server action execution、plugin/runtime system | 可信执行环境 | 借沙箱和环境复现 |

## 5. 产品能力矩阵

| 能力维度 | LangGraph | OpenAI Agents SDK | Claude Code | AutoGen | CrewAI | Copilot Agent | Cursor BG | Devin | OpenHands | parallel-harness 当前 |
|----------|-----------|-------------------|-------------|---------|--------|---------------|-----------|-------|-----------|----------------------|
| 图驱动编排 | 强 | 中 | 弱 | 中 | 中 | 弱 | 弱 | 中 | 中 | 强 |
| durable state | 强 | 强 | 中 | 中 | 强 | 中 | 未确认 | 中 | 中 | 中 |
| subagent / handoff | 中 | 强 | 强 | 强 | 强 | 中 | 中 | 中 | 中 | 中 |
| 阻断式 guardrails | 应用自建 | 强 | 强 | 应用自建 | 强 | 强 | 未确认 | 未确认 | 应用自建 | 中 |
| repo-native 交付 | 弱 | 弱 | 强 | 弱 | 弱 | 强 | 强 | 强 | 中 | 中 |
| 强沙箱执行 | 应用自建 | 工具级，不是 repo 隔离 | 中 | 扩展式 | 扩展式 | 中 | 强 | 中 | 强 | 弱到中 |
| tracing / observability | 强 | 强 | 中 | 中 | 强 | 中 | 中 | 强 | 中 | 中到强 |
| 组织治理 / RBAC | 应用自建 | 中 | 中 | 应用自建 | 强 | 强平台集成 | 未确认 | 企业版强 | 应用自建 | 中 |
| 全流程设计工件 | 弱 | 弱 | 弱 | 弱 | 中 | 弱 | 弱 | 中 | 弱 | 弱 |
| 独立 verifier 平面 | 应用自建 | 可构建 | 部分可构建 | 可构建 | 可构建 | 中 | 中 | 中 | 可构建 | 弱到中 |

## 6. 对竞品的关键事实摘要

### 6.1 LangGraph

LangGraph 官方资料明确把自己放在：

- durable execution
- human-in-the-loop
- comprehensive memory

这说明它真正提供的是“长期可恢复工作流底座”，不是代码仓治理产品。

### 6.2 OpenAI Agents SDK

OpenAI 官方文档已经把以下能力做成一等原语：

- handoffs
- sessions
- tracing
- guardrails
- human-in-the-loop

这对 `parallel-harness` 的启示非常直接：治理能力不能只靠外层脚本，必须进入运行时原语层。

### 6.3 Claude Code

Anthropic 官方文档清楚地把：

- subagents
- hooks
- slash commands

产品化了。它最值得借鉴的是：

- 用 subagent 切 context
- 用 hooks 在工具调用边界拦截风险

### 6.4 GitHub Copilot coding agent

GitHub 官方文档明确：

- coding agent 在 GitHub 上异步执行工作
- 使用临时开发环境
- 自动创建 branch、commit、PR
- 支持 hooks

这说明 repo-native workflow 已经是主流能力，不再是“附加功能”。

### 6.5 Cursor Background Agents

Cursor 的公开资料表明：

- 后台 agent 可在隔离 Ubuntu 环境执行
- clone 仓库、创建独立分支
- 支持用户接管

这对 `parallel-harness` 的直接启发是：并行编码若没有隔离工作区，可靠性上限很低。

### 6.6 Devin

Devin 官方资料里最值得注意的不是“会不会写代码”，而是：

- 有 session insights
- 有 knowledge / skills / playbooks
- 强调 completion criteria 和任务可验证性

这说明“专业化交付闭环”已经成为高阶产品的竞争点。

### 6.7 OpenHands

OpenHands 的公开强项不在 agent persona，而在 runtime：

- Docker sandbox
- runtime server
- action execution

这对 `parallel-harness` 的启示是：执行可信度必须来自运行时，而不是来自 agent 自述。

## 7. 对 parallel-harness 的最佳实践提炼

结合社区和竞品，`parallel-harness` 应该明确坚持以下路线：

1. 用 `TaskGraph + ReservationPlan` 组织并行，而不是 manager chat loop。
2. 用 `ContextEnvelope` 做最小上下文，不做大 prompt 常态化。
3. 用 `ExecutionProxy` 做真实隔离，而不是事后包装。
4. 用 `Verifier Plane` 做独立验证，而不是让 gates 只读作者摘要。
5. 用 `Stage Contracts` 把产品设计、UI 设计、技术方案、测试和报告做成一等对象。
6. 用 `Audit + Trace + Replay` 形成组织级可追责链路。

## 8. 参考资料

以下外部资料于 `2026-03-31` 核对：

- OpenAI Agents SDK  
  https://openai.github.io/openai-agents-python/
- Anthropic Claude Code: Subagents  
  https://docs.anthropic.com/en/docs/claude-code/sub-agents
- Anthropic Claude Code: Hooks  
  https://docs.anthropic.com/en/docs/claude-code/hooks
- LangGraph  
  https://langchain-ai.github.io/langgraphjs/reference/modules/langgraph.html
- AutoGen  
  https://microsoft.github.io/autogen/stable/
- CrewAI  
  https://docs.crewai.com
- GitHub Copilot coding agent  
  https://docs.github.com/en/copilot/concepts/agents/coding-agent/about-coding-agent
- Cursor Background Agents  
  https://cursor.com/features/background-agents
- Devin Docs  
  https://docs.devin.ai
- OpenHands Docs  
  https://docs.all-hands.dev/
