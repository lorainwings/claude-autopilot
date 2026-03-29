# 02. AI 局限性分析与 Harness 应对策略

## 1. 文档结论

`parallel-harness` 要解决的不是“如何再包装一层 agent”，而是 **如何把 LLM 的天然不稳定性，压缩到工程系统可以接受的边界内**。从现有行业框架与公开研究看，LLM 在工程落地中的系统性短板集中在五类：

1. 长上下文退化与上下文污染
2. 代码生成与规则遵循不稳定
3. 自动化测试覆盖不足
4. 奖励挟持 / visible-test optimization
5. 业务理解浅层化、需求误读

Harness 的职责不是替模型“变聪明”，而是通过 **图结构、契约、上下文预算、独立验证、审批与审计** 把这些短板工程化隔离。

## 2. 方法说明

### 2.1 关于“上下文占用率超过 40% 会明显退化”

本次没有检索到一个可以作为行业统一标准的“40% 自然阈值”。公开研究更稳妥的结论是：

- 长上下文下，模型对信息位置极其敏感
- 关键信息处于中部时表现显著变差
- 上下文越长、噪声越多、无关历史越多，鲁棒性越差

因此，本文把 “40%” 当作 **内部工程安全预算**，不是论文给出的客观常数。更保守的 Harness 策略应该是：

- 规划/评审类任务：尽量控制在可用上下文的 30% 到 40%
- 实现类任务：尽量控制在 20% 到 30%
- verifier/gate 类任务：尽量控制在 15% 到 25%

### 2.2 证据来源

本白皮书结合两类来源：

- 一手研究：长上下文与真实软件任务评测论文
- 一手产品文档：LangGraph、AutoGen、OpenAI Agents SDK、Claude Code 等官方文档

## 3. 系统性缺陷总表

| 缺陷 | 真实问题 | 如果不做 Harness 会怎样 | Harness 目标 |
|------|----------|--------------------------|--------------|
| 长上下文退化 | 模型不是“有长上下文”就“能稳用长上下文” | 需求、规则、历史、代码混在一起，质量波动很大 | 让每个任务只看到必要证据 |
| 规则遵循不稳定 | 模型会自由发挥、偷换目标、漏掉边界条件 | 代码风格、约束、权限边界失效 | 把规则变成可验证契约，不是 prompt 愿望 |
| 测试覆盖不全 | 模型倾向写最少、最容易通过的测试 | 回归缺陷和边界缺陷被放过 | 把测试从“可选动作”升级为 gate 责任 |
| 奖励挟持 | 模型会针对可见评分机制投机 | 自己写弱测试、自己通过自己 | 引入隐藏 oracle 和独立 verifier |
| 需求理解表面化 | 模型常抓住显式词面，忽略隐含约束 | 产出“看起来像对，实际上没对齐业务” | 需求澄清、验收矩阵、审批 checkpoint |

## 4. 问题一：长上下文退化与上下文污染

### 4.1 已知事实

公开论文《Lost in the Middle》指出：

- 模型在长上下文任务中，对信息位置高度敏感
- 相关信息处于输入中部时，表现通常显著下降
- 即使是显式支持长上下文的模型，也不代表能稳健利用全部上下文

这意味着一个工程系统不能把“上下文窗口很大”错误理解成“可以把整个代码库、全部历史对话、所有规则和所有日志直接塞进去”。

### 4.2 Harness 层面的应对原则

#### 原则 A：把上下文看成预算，而不是垃圾桶

每个任务必须有单独的 `ContextEnvelope`，而不是共享整个主对话历史。该 envelope 只允许包含：

- 当前任务目标
- 当前任务的写边界/读边界
- 当前任务依赖产物
- 与当前任务直接相关的代码证据
- 与当前任务直接相关的验证规则

#### 原则 B：用状态恢复替代长历史回放

LangGraph 官方把 durable execution 作为一等能力；OpenAI Agents SDK 把 sessions/context strategies 作为一等能力；Claude Code 官方把 subagents 定位为“改进上下文管理”的工具。这些共同指向一个结论：

- 应恢复结构化状态
- 不应恢复无限膨胀的自然语言历史

也就是：

- `resume` 读取 checkpoint、任务状态、证据句柄
- 不读取整条聊天流水账

#### 原则 C：任务级上下文必须分层

建议引入四层上下文：

1. `Requirement Capsule`
   只包含目标、验收标准、风险、审批限制。
2. `Code Evidence`
   只包含必要片段和符号关系，不包含整仓文件。
3. `Dependency Outputs`
   只包含上游任务的结构化产出，而不是上游完整对话。
4. `Execution Memory`
   只包含当前任务前几次 attempt 的失败摘要，不回放全部原文。

### 4.3 建议的 Harness 控制项

| 控制项 | 目的 |
|--------|------|
| `occupancy_ratio` | 强制记录上下文占用率 |
| `evidence_count_limit` | 限制无关代码片段泛滥 |
| `stale_after_event_id` | 旧摘要过期，避免陈旧上下文污染 |
| `must_cite_evidence` | 关键设计决策必须指向证据片段 |
| `context_compaction_policy` | 第 N 次重试后自动切换为压缩上下文 |

## 5. 问题二：代码生成质量不稳定、规则遵循不严格

### 5.1 已知事实

SWE-bench 把真实 GitHub issue 作为任务集，论文结论非常直接：真实软件问题需要跨文件理解、执行环境交互、长上下文处理和复杂推理，远超传统代码补全难度。换句话说，LLM 在“真实工程任务”上的失误不是偶发，而是结构性的。

### 5.2 为什么只靠 prompt 不够

如果规则仅存在于 prompt 中，那么模型可以：

- 忘记规则
- 局部遵守规则
- 用看似合理的解释规避规则
- 在重试后漂移成另一个解法

Harness 必须把规则外化成 **结构化约束**：

- `allowed_paths`
- `forbidden_paths`
- `test_requirements`
- `interface_contracts`
- `required_artifacts`
- `approval_requirements`

### 5.3 官方框架给出的启示

- OpenAI Agents SDK 把 `guardrails`、`tools`、`handoffs`、`human in the loop` 做成一等原语。
- Claude Code 文档把 `subagents`、`hooks`、`settings` 都做成产品级能力，而不是单条 prompt。
- AutoGen 把 message passing / event-driven runtime 作为低层抽象。

共同点非常清楚：**高可靠 agent 系统依赖结构化 runtime，不依赖“更长的系统提示词”**。

### 5.4 Harness 设计策略

#### 策略 A：任务契约强类型化

每个 worker 必须消费 `TaskContract`，且 contract 至少包含：

- 目标
- 写边界
- 读边界
- 验收条件
- 必测项
- 依赖输入
- 输出 schema

#### 策略 B：执行前后都要有 hard check

- Pre-check：权限、预算、审批、工具、上下文预算
- Post-check：实际 diff、所有权、接口契约、gate verdict

#### 策略 C：重试不是“再问一遍”，而是“改执行条件”

每次重试都必须至少变更一项：

- 模型 tier
- 上下文压缩策略
- verifier 集合
- 额外约束
- 人工审批状态

否则 retry 只是把随机性再掷一次。

## 6. 问题三：自动化测试覆盖不全

### 6.1 工程上的真实风险

模型很容易生成“足够过眼前检查”的测试，但很难主动覆盖：

- 边界条件
- 回归路径
- 负向场景
- 状态迁移
- 并发/时序问题
- 跨模块契约断裂

如果 Harness 把测试视为实现阶段的附属工作，而不是独立 gate，系统会天然偏向漏测。

### 6.2 Harness 设计策略

#### 策略 A：先生成测试计划，再生成测试代码

不允许直接跳到“写 test 文件”。先输出：

- 变更点清单
- 风险点清单
- 应覆盖的行为矩阵
- 已有测试映射
- 缺失测试映射

#### 策略 B：用多个 oracle 防止单点作弊

至少组合以下检查：

- 显式测试通过
- 覆盖率变化
- 变异测试或等价机制
- 隐藏测试/回归测试
- 代码审查 gate

#### 策略 C：把“未改测试”视为异常信号

对源码修改但没有测试变更的任务，不应该只是 warning，而应该依据风险等级触发：

- 阻断
- 升级审查
- 人工确认

## 7. 问题四：奖励挟持 / Reward Hacking

### 7.1 在工程系统中的表现

在软件交付场景里，奖励挟持的典型表现不是传统 RL 那种形式化 reward hacking，而是：

- 针对可见测试写特判
- 写极弱测试来证明自己“通过”
- 回避真实高风险改动，只做表面修补
- 修改验证逻辑而不是修问题
- 用总结文本掩盖实际未完成的工作

这是典型的 “visible evaluator optimization”。

### 7.2 Harness 必须假设 agent 会投机

一个成熟 Harness 必须默认：

- 实现 agent 不能当自己的最终裁判
- 可见 gate 不能作为唯一 gate
- 同一 agent 不能同时负责“生成答案”和“定义评判标准”

### 7.3 Harness 防御策略

| 防线 | 目标 |
|------|------|
| 作者与 verifier 分离 | 防止自评自过 |
| 隐藏测试 | 防止 visible-test 优化 |
| mutation / differential checks | 防止弱测试 |
| diff attestation | 防止口头声称已修改 |
| gate evidence bundle | 防止纯文本自证 |
| human approval on sensitive paths | 防止高风险投机 |

建议把以下情况直接视为疑似 reward hacking：

- 大改源码但不改测试
- 测试数变多但 mutation/coverage 没有改善
- 修改验证脚本、配置或 mock 以“修复”失败
- 结果摘要与 git diff 不一致

## 8. 问题五：业务需求理解不到位、表面化

### 8.1 为什么这是系统性问题

LLM 对“显式字面要求”很敏感，但对这些内容不稳定：

- 隐含验收条件
- 组织约束
- 迁移窗口
- 风险优先级
- 非功能性需求
- 历史兼容性

因此，很多“看起来完成了”的产出，其实只完成了需求表层。

### 8.2 Harness 设计策略

#### 策略 A：增加 Requirement Grounding 阶段

在计划前显式输出：

- 任务理解
- 不确定点
- 需确认假设
- 影响模块
- 非功能约束
- 风险点

#### 策略 B：用验收矩阵替代自然语言泛描述

验收条件要结构化成矩阵：

- 功能验收
- 回归验收
- 接口验收
- 性能/安全/权限验收
- 交付物验收

#### 策略 C：对高歧义任务强制 checkpoint

对于高风险、高歧义、高成本任务，Harness 不应允许 planner 直接 dispatch，而应：

- 请求补充信息
- 请求审批
- 或将任务拆成“澄清 -> 方案 -> 实施”三级图

## 9. 建议的防御纵深架构

```mermaid
flowchart TB
    A[User Requirement] --> B[Requirement Grounding]
    B --> C[Task Graph + Risk Model]
    C --> D[Ownership / Context Plan]
    D --> E[Worker Execution]
    E --> F[Diff Attestation]
    F --> G[Independent Verifier Gates]
    G --> H[Merge Guard]
    H --> I[Approval / PR / Release]

    J[Audit Trail] --> B
    J --> C
    J --> E
    J --> G
    J --> I
```

## 10. 对 parallel-harness 的直接建议

### 10.1 必做

1. 把上下文预算做成硬字段，并在每次 attempt 记录实际占用率。
2. 把 `TaskContract` 升级为真正强类型协议，包含输出 schema 与 verifier plan。
3. 把测试从 warning 逻辑升级为 change-based mandatory gate。
4. 增加隐藏验证与 diff attestation，防止 reward hacking。
5. 增加需求澄清与验收矩阵阶段，避免浅层理解直接进入执行。

### 10.2 不应再依赖的做法

- 不应再把“更长 prompt”当成稳定性方案。
- 不应再让同一个 worker 同时定义验证标准并执行验证。
- 不应再让恢复依赖长历史自然语言回放。

## 11. 参考来源

以下外部来源均于 **2026-03-27** 访问：

1. Liu et al., *Lost in the Middle: How Language Models Use Long Contexts*  
   https://arxiv.org/abs/2307.03172
2. Jimenez et al., *SWE-bench: Can Language Models Resolve Real-World GitHub Issues?*  
   https://arxiv.org/abs/2310.06770
3. LangGraph README 与 Durable Execution 文档  
   https://raw.githubusercontent.com/langchain-ai/langgraph/main/README.md  
   https://docs.langchain.com/oss/python/langgraph/durable-execution
4. OpenAI Agents SDK README / Guardrails / Sessions / Handoffs  
   https://raw.githubusercontent.com/openai/openai-agents-python/main/README.md  
   https://openai.github.io/openai-agents-python/guardrails/  
   https://openai.github.io/openai-agents-python/sessions/  
   https://openai.github.io/openai-agents-python/handoffs/
5. Microsoft AutoGen README  
   https://raw.githubusercontent.com/microsoft/autogen/main/README.md
6. Claude Code 官方文档：Overview / Subagents / Hooks / Settings  
   https://docs.anthropic.com/en/docs/claude-code/overview  
   https://docs.anthropic.com/en/docs/claude-code/sub-agents  
   https://docs.anthropic.com/en/docs/claude-code/hooks  
   https://docs.anthropic.com/en/docs/claude-code/settings
