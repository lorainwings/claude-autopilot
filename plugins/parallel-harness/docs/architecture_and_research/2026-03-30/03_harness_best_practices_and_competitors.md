# 03. Harness 思想、最佳实践与竞品矩阵

## 1. 本项目语境下的 Harness 是什么

在 `parallel-harness` 语境里，harness 不是“多开几个 agent”，也不是“给模型套一个更长的 prompt”。它是一层 **约束、编排、验证、恢复、审计和治理系统**，核心目标是让 AI 在产品开发全流程中做到：

- 任务可拆解
- 并行可控
- 上下文最小化
- 结果可验证
- 失败可恢复
- 过程可审计

因此，一个面向研发交付的 harness，至少要回答八个问题：

1. 需求如何结构化？
2. 任务如何拆图并安全并行？
3. 每个任务该看哪些上下文？
4. 谁来验证结果，而不是让作者自评？
5. 如何限制工具、路径、仓库和预算？
6. 如何阻断、审批、恢复、继续执行？
7. 如何形成 PR、报告、审计链？
8. 如何证明系统没有被 reward hacking 或“看起来完成”欺骗？

## 2. 调研结论

从官方框架和 coding-agent 产品看，社区已经形成比较稳定的共识：

1. **不是所有问题都该上多 agent。** 复杂度不够时，单 agent + 明确工具链通常更稳。
2. **一旦上多 agent，必须 graph-first。** 否则你只是在放大随机性。
3. **长流程必须有 durable state。** 恢复结构化状态，而不是重喂长对话。
4. **上下文管理必须任务级化。** subagent / handoff 的真正价值是切 context，不是堆 agent 数。
5. **guardrails 和 hooks 必须能阻断。** 只做日志没有治理价值。
6. **代码交付场景需要 repo-native 约束。** PR、branch、diff、测试、审计不能是外挂。
7. **没有 tracing / observability，就没有生产可维护性。**
8. **没有独立 verifier 和隐藏验证，reward hacking 迟早会发生。**

## 3. 社区最佳实践提炼

### 3.1 先简后繁，而不是默认多 agent

OpenAI 的 agent 实践指南明确建议：只有在单 agent 无法稳定完成任务时，再引入 handoff、manager、specialist 等编排结构。否则系统复杂度、调试成本和上下文污染会一起上升。

对 `parallel-harness` 的含义是：

- 不要把每个阶段都拆成 agent 角色
- 先让 task graph 成为主语，再让 agent 成为执行体

### 3.2 Graph-first orchestration

LangGraph 和 AutoGen 都把状态化编排、事件驱动和长期工作流当成底座能力，而不是“聊天技巧”。

最佳实践：

- 先建图，再执行
- 图里必须显式表达依赖、边界、风险、恢复点
- “任务标题列表”不等于真正的任务图

### 3.3 Durable execution 与结构化恢复

LangGraph 官方把 durable execution 放在首页核心卖点；OpenAI Agents SDK 把 sessions/context/tracing 做成一等原语；Cline 则把 checkpoints/restore 做成显式工作流。

最佳实践：

- 恢复要基于状态快照、工件引用、审计事件
- 不应依赖长历史自然语言回放

### 3.4 专家分工的真正价值是切上下文

Claude Code subagents 和 Cline subagents 都明确强调了“每个 subagent 使用自己的 context window”。这说明社区已经逐步形成共识：

- delegation 的价值不只是分工
- 更关键的价值是 **把上下文切小**

最佳实践：

- specialist 必须有明确输入、输出、权限与完成条件
- subagent 不是越多越好，越多越需要边界

### 3.5 Guardrails / Hooks / Human-in-the-loop 必须是阻断型能力

OpenAI Agents SDK 的 guardrails 支持 tripwire 触发后立即中断执行；Claude Code 和 GitHub Copilot coding agent 都把 hooks 做成可介入工具调用的产品能力。

最佳实践：

- pre-plan: 澄清需求、阻断歧义
- pre-dispatch: 校验权限、预算、敏感路径
- pre-tool / pre-merge: 阻止危险动作
- post-tool / post-run: 产出审计与度量

### 3.6 代码交付必须 repo-native

GitHub Copilot coding agent、Cursor background agents、Bugbot、Devin 都已经把 PR、branch、测试、diff、IDE、后台环境纳入产品主流程，而不是外接插件。

最佳实践：

- agent 不应只返回文本
- agent 应产生可审查的代码变更、PR、日志、测试结果、审计记录

### 3.7 可观测性不是加分项，而是生产前提

OpenAI Agents SDK 强调 tracing；LangGraph 借助 LangSmith 强调可视化和调试；CrewAI 直接把 observability 和 control plane 写在产品首页。

最佳实践：

- 每个 run 都要能追到 task、attempt、tool、gate、成本、审批链
- 没有 trace，就很难做 SLO、回放、归因和组织治理

### 3.8 anti-gaming 需要独立验证链

新近 reward hacking benchmark 说明，仅有 visible tests 或单一评分器并不可靠。对代码交付 harness 来说，最佳实践不是“多加一句不要作弊”，而是：

- verifier 与 author 分离
- hidden suite
- tamper detection
- trusted attestation
- 分层 gate

## 4. 产品分层

| 分层 | 产品 | 主要角色 |
|------|------|----------|
| 编排底座 | LangGraph、AutoGen、OpenAI Agents SDK | 给开发者提供工作流、状态和运行时原语 |
| coding agent 产品 | Claude Code、GitHub Copilot coding agent、Cursor、Devin、OpenHands、Cline | 直接面向代码库执行、修改、评审或协作 |
| 企业控制平面 / 自动化平台 | CrewAI、Devin 企业能力、GitHub / Cursor 平台层 | 强调流程治理、集成、监控、组织级能力 |
| 治理型交付 harness | `parallel-harness` 目标态 | 把代码交付、验证、审批、审计和并发治理压到一个系统里 |

## 5. 竞品与参考方案矩阵

> 口径说明：下表只写 **官方资料已明确确认** 的能力；没有在官方资料中明确看到的，一律写“未确认”或“不以内建能力出现”。

| 方案 | 官方定位 | 已确认能力 | 治理/Guardrails | 状态/恢复 | 代码执行/隔离 | 观测/控制面 | 对 parallel-harness 的启示 |
|------|----------|------------|-----------------|-----------|---------------|-------------|---------------------------|
| LangGraph | 低层、长期、状态化 agent/workflow 编排框架 | durable execution、human-in-the-loop、memory、LangSmith 调试/可视化 | 有 interrupts/HITL；代码治理需自建 | 强 | 不以内建代码隔离为核心 | 强，常与 LangSmith 配合 | 最该借鉴 durable state machine，而不是 UI |
| AutoGen | 分层、可扩展的多 agent 生态 | Core API 的 message passing、event-driven agents、local/distributed runtime；AgentChat；Ext；Bench | 可扩展，但治理多为应用层自建 | 中到强 | 支持 code execution 能力扩展；强隔离未确认 | 中，Bench/Studio 可辅助 | 借鉴 runtime 分层与事件驱动抽象 |
| OpenAI Agents SDK | 生产级 agent runtime SDK | agents、tools、handoffs、sessions、context management、tracing、guardrails、human-in-the-loop | 强，guardrails/tripwires 为一等能力 | 强 | 内建 shell/computer 等工具，但 repo 治理不是主定位 | 强 | 借鉴 guardrails、sessions、tracing、handoff 原语 |
| Claude Code | coding agent 产品 | 读代码、改文件、跑命令；subagents；hooks；settings | 强，hooks 可 block tool call；subagent 有独立权限 | 中，项目级会话能力明确； durable workflow 细节未确认 | 工具/权限可配置；强 worktree 隔离未在公开文档中明确 | 中 | 借鉴 subagent 的 context 管理与 hook 生态 |
| GitHub Copilot coding agent | PR-first 的后台 coding agent | 后台完成任务、修 bug/增量特性/补测试/改文档；GitHub Actions 临时开发环境；自动 branch/commit/PR；custom agents | 强，hooks 支持 approve/deny tool executions、审计、校验 | 中，session start/resume hook 已确认；更强 durable state 未确认 | 临时环境明确；仓库和 PR 原生 | 强，GitHub PR 日志与使用指标 | 借鉴 PR-first workflow 和 GitHub-native 透明度 |
| Cursor Background Agents | 远程异步编码 agent | 远程后台 agent、隔离 Ubuntu 机器、Internet access、clone repo、独立分支、可跟进/接管 | 审批/guardrail 细节未确认 | 未确认 | 隔离执行环境明确 | 中，Sidebar/agent status 已确认 | 借鉴远程执行、分支级交接与 takeover |
| Cursor BugBot | PR AI review 产品 | 自动/手动 PR diff review、评论修复建议、`.cursor/BUGBOT.md` 分层规则 | 规则文件明确；审批/阻断语义未确认 | 不适用 | 不以执行代码为主 | 中，PR 评论与 verbose log | 借鉴评审规则分层和 PR 增量 review |
| Devin | “AI software engineer” 产品 | 写/跑/测代码；Shell/IDE/Browser；Slack/GitHub/Jira/Linear 等集成；Session Tools、Knowledge、Skills、Playbooks、Session Insights | 审批/硬 hook 能力公开资料中未充分确认 | 中到强，session/workspace 是核心概念 | 具备工作空间与开发工具；强隔离细节未充分公开 | 强，Session Insights/集成明显 | 借鉴“任务明确 + 易验证 + 会话可追踪”的产品化闭环 |
| OpenHands | 开源软件工程 agent 平台 | Docker sandbox runtime、client-server action execution、插件系统、镜像/环境复现 | 治理和审批需上层自建 | 中 | 强，Docker 沙箱与运行时架构公开明确 | 中 | 借鉴可信 runtime 和插件式环境管理 |
| Cline | IDE/CLI coding agent | Plan/Act 模式、Checkpoints Compare/Restore、Subagents 并行研究、Auto-Approve | 有 auto-approve；更强组织级 policy 未确认 | 强于多数 IDE agent，checkpoints 显式可恢复 | 本地执行；subagent 只读受限 | 中 | 借鉴 plan/act 分离、checkpoint、并行只读研究子代理 |
| CrewAI | 生产级多 agent / flow 平台 | agents、crews、flows、guardrails、memory、knowledge、observability、persist/resume、human-in-the-loop triggers、RBAC/enterprise console | 强 | 强 | 代码仓原生隔离不是主定位 | 强 | 借鉴 control plane 和企业级运维能力 |
| parallel-harness（当前） | 并行 AI 编码编排插件 / 治理型 orchestrator | run lifecycle、task graph、ownership、scheduler、checkpoint/resume、gates、MergeGuard、audit、PR integration、control plane | 中到强，但很多是骨架 | 中 | 弱到中，仍偏 prompt + CLI + 后验检查 | 中到强 | 差异化方向正确，关键在把骨架做成硬约束 |

## 6. 对各方案的关键事实摘要

### 6.1 LangGraph

官方 README 直接把 LangGraph 定义为：

- low-level orchestration framework
- long-running, stateful agents
- durable execution
- human-in-the-loop

这说明它最强的是 **状态机与持久化工作流**，不是代码仓治理。

### 6.2 AutoGen

官方 README 明确写到：

- layered and extensible design
- message passing
- event-driven agents
- local and distributed runtime

它更像多 agent runtime 工程底座，而不是交付治理产品。

### 6.3 OpenAI Agents SDK

官方文档明确提供：

- handoffs
- sessions
- context management
- tracing
- guardrails
- tripwires

这是最接近“生产级原语集合”的官方 SDK 之一。对 `parallel-harness` 最有参考价值的是：

- guardrails 必须具备中断语义
- tracing/sessions 必须是内建能力

### 6.4 Claude Code

Claude Code 的官方文档已经把以下能力产品化：

- subagents
- hooks
- settings
- 独立权限和上下文窗口

它最值得借鉴的不是“模型是谁”，而是：

- subagent context 隔离
- hooks 能前置拦截工具调用
- 项目级配置可直接影响 agent 行为

### 6.5 GitHub Copilot coding agent

GitHub 已经把 coding agent 做成：

- GitHub Actions 临时环境中的后台 agent
- 直接从 issue/comment 触发
- 自动 branch/commit/PR
- hooks 可以 approve/deny tool execution

这说明 PR-first 和 repo-native workflow 已经是主流产品方向。

### 6.6 Cursor Background Agents / BugBot

Cursor 的公开文档和官方 docs snippet 已确认：

- Background Agents 在隔离 Ubuntu 机器中运行
- clone repo、走独立分支、可接管
- BugBot 直接围绕 PR diff 评审工作
- `.cursor/BUGBOT.md` 用于分层规则注入

这说明 Cursor 正在把“异步后台执行”和“PR 审查”拆成两条独立产品线。

### 6.7 Devin

Devin 官方文档表明它的强项是：

- 端到端执行软件任务
- Shell/IDE/Browser 三合一工作空间
- 丰富的外部集成
- Session Insights、Knowledge、Skills、Playbooks

更重要的是，Devin 公开写出“明确 completion criteria、易验证、复杂任务拆步”这些最佳实践，这对 harness 设计非常关键。

### 6.8 OpenHands

OpenHands 的最强公共信号不是 agent persona，而是 runtime：

- Docker sandbox
- action execution server
- runtime client
- plugin system
- 镜像与环境可复现

对 `parallel-harness` 来说，这是一条非常值得吸收的执行硬化路线。

### 6.9 Cline

Cline 明确把：

- Plan / Act
- checkpoints
- restore
- subagents

做成了一条清晰工作流。这对减少需求误读、降低上下文污染、控制 risky edits 很有效。

### 6.10 CrewAI

CrewAI 首页就写明：

- crews
- flows
- guardrails
- observability
- persist / resume
- RBAC / enterprise console

这表明“自治 agent 团队 + 企业控制面”已经是一条成熟产品路线。

## 7. 对 parallel-harness 的综合判断

### 7.1 真正的差异化机会

`parallel-harness` 如果去做“通用 agent framework”，很难在 LangGraph、AutoGen、OpenAI Agents SDK 这些基础设施前取得明显优势。

它真正有机会建立差异化的位置在于：

- 代码仓写边界治理
- 并行冲突管理
- gate / approval / audit 一体化
- PR / 报告 / 交付链路专业化

### 7.2 应该借鉴什么，不该盲目复制什么

应吸收：

- LangGraph 的 durable execution
- AutoGen 的 runtime 分层
- OpenAI Agents SDK 的 guardrails / tracing / sessions
- Claude Code 的 subagents / hooks / settings
- GitHub Copilot 的 PR-first workflow
- Cursor 的后台隔离执行与 PR review 分层
- OpenHands 的 sandbox runtime
- Cline 的 plan/act 与 checkpoints
- CrewAI 的 enterprise control plane

不应盲目复制：

- “多 agent 越多越强”
- “上下文窗口越大越安全”
- “有 9 个 gate 名字就等于有 9 个可靠门禁”

## 8. 对当前项目的最佳实践清单

结合上述竞品和官方文档，`parallel-harness` 下一阶段应把以下实践产品化：

1. 默认单图编排，必要时才引入 specialist task。
2. 强制 `Requirement Grounding -> Task Graph -> TaskContract -> Gate` 真相链。
3. 引入 `Plan / Execute / Verify / Merge / PR` 五段式可追踪状态。
4. 每个 task 使用独立 `ContextEnvelope`，记录实际占用率。
5. 在执行层实现真正的 `ExecutionProxy`，统一承接 model/tool/fs/repo policy。
6. 正式区分 `Hard Gates` 与 `Signal Gates`。
7. 把 PR provider 做成 repo-aware、identity-aware 的安全输出层。
8. 把 hooks / instructions / skills 从“注册表”升级成“可消费决策输入”。

## 9. 参考来源

1. LangGraph README  
   https://raw.githubusercontent.com/langchain-ai/langgraph/main/README.md
2. Microsoft AutoGen README  
   https://raw.githubusercontent.com/microsoft/autogen/main/README.md
3. OpenAI Agents SDK 文档  
   https://openai.github.io/openai-agents-python/  
   https://openai.github.io/openai-agents-python/guardrails/
4. OpenAI, *A practical guide to building agents*  
   https://cdn.openai.com/business-guides-and-resources/a-practical-guide-to-building-agents.pdf
5. Claude Code Docs  
   https://code.claude.com/docs/en/sub-agents  
   https://docs.anthropic.com/en/docs/claude-code/hooks  
   https://docs.anthropic.com/en/docs/claude-code/overview
6. GitHub Copilot coding agent Docs  
   https://docs.github.com/en/copilot/concepts/agents/coding-agent/about-coding-agent  
   https://docs.github.com/en/copilot/concepts/agents/coding-agent/about-hooks
7. Cursor Docs / Official Docs Snippets  
   https://docs.cursor.com/en/background-agents  
   https://docs.cursor.com/bugbot
8. Devin Docs  
   https://docs.devin.ai/get-started/devin-intro
9. OpenHands Runtime Docs  
   https://docs.openhands.dev/openhands/usage/architecture/runtime
10. Cline Docs  
   https://docs.cline.bot/core-workflows/plan-and-act  
   https://docs.cline.bot/core-workflows/checkpoints  
   https://docs.cline.bot/features/subagents
11. CrewAI Docs  
   https://docs.crewai.com/
