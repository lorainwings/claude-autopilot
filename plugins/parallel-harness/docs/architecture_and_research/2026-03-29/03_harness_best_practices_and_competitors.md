# 03. Harness 思想、最佳实践与竞品能力矩阵

## 1. Harness 的本质

在本项目语境里，AI harness 不是“多开几个 agent”，也不是“再包一层 prompt workflow”。

它本质上是一套 **把随机模型行为工程化约束为可交付、可回放、可治理、可审计系统行为的控制层**。

一个成熟 harness 至少要回答九个问题：

1. 任务怎么拆
2. 哪些任务能并行
3. 每个任务看什么上下文
4. 每个任务能改什么
5. 谁负责验证
6. 失败后怎么恢复
7. 成本怎么管
8. 人类在什么点介入
9. 整个过程如何留下可审计证据

## 2. 对 `parallel-harness` 的目标映射

你们的插件目标不是通用 agent framework，而是：

**面向产品研发全生命周期的高稳定编排插件。**

这意味着你们真正要对标和吸收的是两类能力：

- 基础 agent primitive：OpenAI Agents/Codex、Claude Code、OpenHands、Continue
- 企业级治理与控制面：Factory、Devin、Cursor、Amp

## 3. 社区最佳实践

### 3.1 Graph-first，而不是自由对话式 loop

最稳的模式不是“一个大 agent 从头做到尾”，而是：

- manager + specialists
- handoff
- DAG / workflow
- explicit dependencies

对代码与产品交付场景，推荐拆成：

- 需求澄清与 grounding
- 产品/架构设计
- 实现
- 验证
- 集成与发布
- 报告

### 3.2 Context stack，而不是全量历史共享

业界主流都在做分层上下文：

- Claude Code：`CLAUDE.md` / memory
- Cursor：rules + memories
- Factory：`AGENTS.md`
- Devin：knowledge + playbooks
- Continue：rules + context providers

建议你们的 harness 标准化成：

1. `L0` 组织规则层
2. `L1` 仓库/目录层
3. `L2` 任务合同层
4. `L3` 动态 evidence 层

### 3.3 Contract-first delegation

最佳实践不是“开更多 agent”，而是“开边界明确的 agent”。

每个被派发任务都应有：

- objective
- input evidence
- output schema
- read-set / write-set
- verifier set
- done condition

### 3.4 Layered guardrails

可靠的 agent 产品都不是只有一个 gate，而是分层 guardrails：

- prompt / rule guardrails
- tool / permission guardrails
- workflow / eval guardrails
- human approval guardrails

### 3.5 Async execution + durable state

长链路任务必然需要：

- background execution
- checkpoint
- polling / resume / cancel
- partial replay

### 3.6 Observability 是一等能力

商业级 harness 和“提示词工作流”的最大区别，是有没有：

- full trace
- step timeline
- cost ledger
- gate evidence
- approval trail

### 3.7 Independent verification

作者不能做自己的最终裁判。最少应有：

- task author
- reviewer / verifier
- release decision layer

### 3.8 并行必须绑定 ownership

可靠并行的前提不是线程数，而是：

- dependency graph
- ownership partition
- conflict detection
- rollback / serialize fallback

### 3.9 成本控制必须内建

最优方案不是简单限 token，而是：

- model routing
- context compaction
- impacted-scope validation
- asynchronous execution
- run-level cost decomposition

## 4. 竞品能力矩阵

以下矩阵基于 `2026-03-29` 的公开资料与官方文档归纳，`强/中/弱` 为工程视角判断，不是官方评级。

| 产品/方案 | 任务分解/子代理 | 上下文分层 | 验证/门禁 | 并行/后台 | 模型路由 | 可观测/审计 | 人机协同 | 恢复/继续 | 成本控制 | 主要启发 |
|---|---|---|---|---|---|---|---|---|---|---|
| OpenAI Codex + Responses + Agents SDK | 强 | 中-强 | 强 | 强 | 强 | 强 | 中-强 | 强 | 强 | 平台原语最完整，trace/evals/background 很强 |
| Claude Code | 强 | 强 | 中-强 | 中-强 | 中 | 中 | 强 | 强 | 中-强 | 本地协作、hooks、memory、subagents 最成熟 |
| Devin | 中-强 | 强 | 中 | 强 | 中 | 中 | 强 | 中-强 | 中 | 长任务自主执行、知识与 playbooks 强 |
| Cursor | 中 | 强 | 中 | 强 | 中 | 中 | 强 | 中 | 中 | IDE 原生、rules/memories、background agents 强 |
| Factory | 强 | 强 | 强 | 强 | 强 | 强 | 强 | 中-强 | 强 | 企业治理、审计、模型无关和 control plane 很强 |
| OpenHands | 中 | 中 | 弱-中 | 中-强 | 中 | 中 | 中 | 中 | 中 | 开源、自托管、sandbox/runtime/事件流强 |
| Continue | 弱-中 | 强 | 弱 | 弱 | 强 | 弱-中 | 中 | 弱 | 中 | 高可配置 agent shell / IDE 编排层 |
| Sweep | 中 | 中 | 中 | 中 | 中 | 弱 | 中 | 弱 | 中 | IDE 静态分析与自动修复结合 |
| Amp | 中-强 | 中-强 | 强 | 中-强 | 强 | 中 | 中-强 | 中-强 | 中 | code review、hooks、skills、handoff 方向明确 |

## 5. 分产品分析

### 5.1 OpenAI Codex / Responses / Agents SDK

优势：

- 官方原语最完整：tools、handoffs、guardrails、background mode、webhooks、evals、trace graders
- Codex 已覆盖 app / CLI / IDE / cloud 协作形态
- 适合构建底层 agent runtime 与 workflow versioning

对 `parallel-harness` 的启发：

- `trace + eval + versioned workflow` 应成为核心骨架
- execution 与 verification 应分成两个独立产品面
- 背景执行、异步恢复、事件回收必须是一等能力

### 5.2 Claude Code

优势：

- subagents 天然适合 specialist delegation
- hooks 能在 pre/post tool use、subagent stop、compact 等节点插入确定性约束
- memory / `CLAUDE.md` 的分层上下文治理非常成熟

启发：

- 任务分工和上下文治理可以直接借鉴
- Hook 点位设计值得吸收进 execution proxy

### 5.3 Devin

优势：

- 长任务自主执行与并行任务能力强
- team knowledge / playbooks 适合跨任务复用经验
- 适合承接“复杂、长时间、需要工具和浏览器交互”的工作

启发：

- `parallel-harness` 的多阶段报告、知识沉淀和标准作业流可以借鉴 Devin 的 knowledge / playbooks 思路

### 5.4 Cursor

优势：

- IDE 原生体验强
- background agents、rules、memories 形成稳定的上下文控制模型
- GitHub 权限与接管体验较成熟

启发：

- 目录级规则、记忆与后台 agent 的组合值得吸收
- 但需要加强安全与 prompt injection 防护

### 5.5 Factory

优势：

- 企业治理、审计、身份与访问控制、OTEL、air-gapped 能力突出
- `AGENTS.md`、custom droids、organization-level control 很适合平台化治理

启发：

- 如果 `parallel-harness` 要走商用插件路线，Factory 是最值得研究的治理向标杆之一

### 5.6 OpenHands

优势：

- 开源、自托管、runtime/sandbox/事件流可控
- 非常适合做执行层、研究层或评测层

启发：

- 可以借鉴其 sandbox/runtime 与 websocket 事件流思路
- 但审批、审计、治理还需要上层产品化补齐

### 5.7 Continue

优势：

- 模型、rules、context providers、MCP 高度可配置
- 适合做 agent shell / IDE 编排前端

启发：

- `parallel-harness` 的能力层可以借鉴 Continue 的可配置上下文和 provider 设计

### 5.8 Sweep

优势：

- 强 IDE 集成
- 更贴近“搜索代码 -> 修改代码 -> 跑检查”的闭环体验

启发：

- 适合参考其开发者工作流整合方式，但不宜把它当作企业治理标杆

### 5.9 Amp

优势：

- code review、hooks、skills、subagents、handoff 的组合思路很清晰
- 更强调“轻量 harness + 组织工作流”

启发：

- 适合借鉴其 review-first、workflow-first 的产品方向

## 6. 对 `parallel-harness` 的最直接启发

### 6.1 不要再把重点放在“更多 agent”

需要补的是：

- graph quality
- contract quality
- ownership quality
- verification quality
- trace quality

### 6.2 形成完整的平台能力矩阵

最强 harness 不是一个 prompt，而是一套能力组合：

- planning
- routing
- context governance
- execution proxy
- gates
- evidence
- approvals
- replay
- reporting

### 6.3 差异化路径

`parallel-harness` 真正有机会做出差异化的位置，不是通用 agent framework，而是：

**面向软件研发全流程的治理型编排插件。**

也就是：

- 产品设计可编排
- UI 设计可编排
- 技术方案可编排
- 前后端实现可编排
- 测试与质量门禁可编排
- 报告与发布可编排

## 7. 建议的最佳实践清单

建议将以下十条固化为 `parallel-harness` 的设计准则：

1. 复杂任务必须 graph-first
2. 所有 delegation 都必须 contract-first
3. 上下文必须 layer-first
4. 执行必须 ownership-first
5. 验证必须 independent-first
6. 恢复必须 checkpoint-first
7. 控制必须 guardrail-first
8. 发布必须 evidence-first
9. 报告必须 trace-first
10. 成本必须 ledger-first

## 8. 参考来源

以下来源于 `2026-03-29` 检索和核对：

1. OpenAI practical guide to building agents  
   https://openai.com/business/guides-and-resources/a-practical-guide-to-building-ai-agents/
2. OpenAI Agents SDK / agent evals / agent builder / background mode / Codex  
   https://developers.openai.com/api/docs/guides/agents-sdk  
   https://developers.openai.com/api/docs/guides/agent-evals  
   https://developers.openai.com/api/docs/guides/agent-builder  
   https://developers.openai.com/api/docs/guides/background  
   https://openai.com/index/introducing-codex/  
   https://openai.com/index/codex-now-generally-available/
3. Claude Code docs  
   https://code.claude.com/docs/en/sub-agents  
   https://code.claude.com/docs/en/hooks  
   https://code.claude.com/docs/en/memory  
   https://code.claude.com/docs/en/costs
4. Devin docs  
   https://docs.devin.ai/get-started/devin-intro  
   https://docs.devin.ai/fr/product-guides/knowledge  
   https://docs.devin.ai/zh/product-guides/creating-playbooks
5. Cursor docs  
   https://docs.cursor.com/en/background-agents  
   https://docs.cursor.com/context/rules  
   https://docs.cursor.com/en/context/memories  
   https://docs.cursor.com/en/github
6. Factory docs  
   https://docs.factory.ai/  
   https://docs.factory.ai/cli/getting-started/overview  
   https://docs.factory.ai/cli/configuration/agents-md  
   https://docs.factory.ai/cli/configuration/custom-droids  
   https://docs.factory.ai/enterprise/compliance-audit-and-monitoring
7. OpenHands docs  
   https://docs.openhands.dev/openhands/usage/sandboxes/overview  
   https://docs.openhands.dev/openhands/usage/developers/websocket-connection
8. Continue docs  
   https://docs.continue.dev/reference  
   https://docs.continue.dev/customize/custom-providers
9. Sweep docs  
   https://docs.sweep.dev/
10. Amp official site and product updates  
   https://ampcode.com/  
   https://ampcode.com/news/liberating-code-review  
   https://ampcode.com/news/hooks  
   https://ampcode.com/news/handoff  
   https://ampcode.com/news/the-coding-agent-is-dead
