# parallel-harness 全量平台执行提示词

> 日期：2026-03-20
> 目的：这是一份用于继续建设 `parallel-harness` 的高标准执行提示词。
> 使用方式：直接复制 `## 最终提示词` 下的全部内容，原样交给 Claude。
> 执行要求：本轮目标不是 MVP，也不是补几个模块，而是把 `parallel-harness` 推进为一个大而全面、具备工程闭环能力的新插件产品。

## 为什么要有这份新提示词

上一轮交付完成了以下部分：

- 独立插件目录
- 核心 schema
- intent analyzer / task graph builder / complexity scorer
- ownership planner / scheduler MVP / model router MVP
- test / review / security / perf verifier
- README、架构文档、基础测试

但上一轮仍然停留在“可类型检查、可单测的模块集合”，没有形成成熟 harness 应有的完整工程闭环。

经 review，当前缺口集中在：

- 没有真正串起 `planner -> dispatch -> worker -> merge guard -> verifier -> synthesize -> report`
- 自动模型路由被默认值短路，无法形成真实 routing loop
- ownership 冲突没有真正传导到调度与合并阶段
- 缺 worker dispatch、retry、downgrade、escalation 等执行治理
- 缺 event bus、session state、task history、verifier history、risk summary
- 缺 PR/CI integration、autofix、coverage、failure analysis
- 缺 capabilities / skills / hooks / policy assets
- 缺 build/dist/install/marketplace 的产品化链路

因此本轮不能再以“MVP 先放一放”为默认理由，而必须按平台型插件来实施。

## 背景说明

当前仓库是一个插件市场仓库，而不是单插件仓库：

- 市场名称：`lorainwings-plugins`
- 当前已有插件：`spec-autopilot`
- 目标插件：`parallel-harness`

`parallel-harness` 必须保持独立产品线定位：

- 它不是 `spec-autopilot vNext`
- 它不是把旧插件硬重构成新平台
- 它是一个新的并行 AI 工程平台插件
- 它要与 `spec-autopilot` 共存
- 它最终要进入同一个插件市场

## 新插件的产品定位

`parallel-harness` 必须被建设为：

- 真正的并行 AI 平台
- AI 软件工程控制面插件
- task-graph-first
- ownership-first
- model-routing-aware
- verifier-driven
- event-driven
- recovery-aware
- CI/PR native
- installable / buildable / observable

它必须解决的不只是“拆任务”，还包括：

- 如何把用户目标转成稳定的任务图
- 如何把任务图转成可执行的 worker dispatch
- 如何在并行执行中防止路径冲突和合并污染
- 如何根据复杂度、风险、预算自动路由模型
- 如何对失败任务重试、降级、升级、人工接管
- 如何把 verifier 结果变成正式 gate
- 如何把 task history / verifier history / risk summary 接入 PR/CI
- 如何把整个系统产品化为可安装插件

## 你必须参考的本地文档

在开始实现前，你必须阅读并遵循这些文档：

- [总调研报告](/Users/lorain/Coding/Huihao/claude-autopilot/docs/plans/2026-03-19-holistic-architecture-research-report.zh.md)
- [新并行 AI 平台插件设计方案](/Users/lorain/Coding/Huihao/claude-autopilot/docs/plans/2026-03-19-parallel-ai-platform-plugin-design.zh.md)
- [竞品能力复用矩阵](/Users/lorain/Coding/Huihao/claude-autopilot/docs/plans/2026-03-19-competitive-capability-reuse-matrix.zh.md)
- [parallel-harness 实施 Backlog](/Users/lorain/Coding/Huihao/claude-autopilot/docs/plans/2026-03-19-parallel-harness-execution-backlog.zh.md)
- [上一轮执行提示词](/Users/lorain/Coding/Huihao/claude-autopilot/docs/plans/2026-03-19-parallel-harness-execution-prompt.zh.md)

## 你必须参考的竞品与官方产品文档

本轮实现必须参考多维度竞品，不允许只做仓库内部自洽设计。

至少参考这些方向：

- Harness AI Agents：review / autofix / PR checks / CI integration 架构
- GitHub Copilot coding agent：后台 agent session、check runs、可审计执行轨迹
- CodeRabbit：PR review、autofix suggestions、coverage / review evidence
- claude-task-master：task graph / dependency / complexity
- claude-code-switch：tier 化模型路由
- oh-my-claudecode：多 Agent 协作
- everything-claude-code：skills / hooks / capability assets 资产化组织
- BMAD-METHOD：角色工程化和 workflow 模块化
- get-shit-done：最小上下文包与低摩擦推进
- superpowers：methodology-as-code 与 capability catalog

官方参考链接：

- Harness AI Agents: `https://developer.harness.io/docs/code-repository/pull-requests/ai-agents/`
- GitHub Copilot coding agent: `https://docs.github.com/en/copilot/concepts/coding-agent/coding-agent`
- CodeRabbit PR review: `https://docs.coderabbit.ai/overview/pull-request-review`

## 竞品能力必须如何落地

### 来自 `superpowers`

要吸收：

- capability catalog
- methodology-as-code
- 低摩擦入口

必须增强：

- capability 不是文档清单，而是可执行资产
- 每个 capability 都要有 contract、policy、降级策略、测试

### 来自 `claude-code-switch`

要吸收：

- tier 化模型分层
- 显式 routing policy

必须增强：

- routing 必须接复杂度、风险、预算、失败次数、上下文大小
- routing 不能被默认值短路
- 需要 escalation / downgrade / budget control

### 来自 `oh-my-claudecode`

要吸收：

- 多 Agent 协作方向

必须增强：

- 不能只做 agent fan-out
- 必须 task-graph-first
- 必须 ownership-first
- 必须 merge-guard-first

### 来自 `everything-claude-code`

要吸收：

- skills / hooks / runtime / docs/capabilities 的资产化组织

必须增强：

- 资产必须有边界、用途、风险和启用条件
- 不能堆积成不可治理的能力合集

### 来自 `BMAD-METHOD`

要吸收：

- planner / worker / verifier / synthesizer 角色化
- 工作流模块化

必须增强：

- 角色必须是 contract，不只是提示词角色名
- 要有 failure semantics、resource boundaries、state transitions

### 来自 `claude-task-master`

要吸收：

- task graph
- dependency awareness
- complexity scoring

必须增强：

- graph 必须接 dispatch、ownership、verifier、reporting
- 必须具备 critical path、batch plan、risk summary

### 来自 `get-shit-done`

要吸收：

- 最小上下文包
- 低摩擦推进

必须增强：

- 不能只快不稳
- 必须接 verifier、metrics、budget

### 来自 Harness / GitHub Copilot / CodeRabbit

要吸收：

- PR / CI 原生接入
- review / autofix / coverage / checks 闭环
- execution history 和 evidence-driven reporting

必须增强：

- 不能只做表层 review
- 必须把 task graph、worker output、verifier report、risk summary 作为 PR/CI 输入
- 必须形成可审计的工程闭环

## 本轮总目标

本轮目标不是“补几个空接口”，而是把 `parallel-harness` 建成一个真正具备下列能力的全栈插件：

1. 可规划
2. 可调度
3. 可执行
4. 可验证
5. 可恢复
6. 可观察
7. 可集成到 PR/CI
8. 可构建和安装
9. 可进入市场

## 全量完成原则

本次提示词要求 Claude 尽量按全量完成执行：

1. 不能只建目录不实现运行时主链路。
2. 不能只补 schema 或 contract，不补执行器。
3. 不能只做静态 verifier，不做真实 gate。
4. 不能只做 scheduler，不做 dispatch / merge guard / retry。
5. 不能只做本地模块，不做 build / dist / install path。
6. 不能只做 docs，不做产品化链路。
7. 不能把 PR/CI integration 全部留到“下一轮”。
8. 不能再用“MVP 先不做”作为默认缩减理由。

如果确有阻塞，必须精确说明阻塞点、影响范围、替代方案和未完成清单。

## 你必须实现的完整范围

### A. 插件产品骨架与目录升级

你必须将插件骨架升级到至少如下结构：

```text
plugins/parallel-harness/
  .claude-plugin/
    plugin.json
  docs/
    architecture.zh.md
    roadmap.zh.md
    operations/
    capabilities/
  gui/
  hooks/
  runtime/
    orchestrator/
    scheduler/
    dispatch/
    guard/
    recovery/
    models/
    verifiers/
    observability/
    session/
    history/
    ci/
    scripts/
    schemas/
  skills/
    harness/
    harness-plan/
    harness-dispatch/
    harness-verify/
    harness-recovery/
    harness-pr/
  tests/
    unit/
    integration/
    e2e/
    fixtures/
  tools/
  README.md
  README.zh.md
  package.json
  tsconfig.json
```

并补齐：

- 插件定位说明
- 与 `spec-autopilot` 的边界说明
- build / dist 说明
- install / smoke test 说明
- 何时选用 `parallel-harness`
- capability catalog 文档

### B. 核心运行时主链路

你必须实现并串起以下主链路：

```text
User Intent
  -> Planner
  -> Intent Analyzer
  -> Task Graph Builder
  -> Complexity Scorer
  -> Ownership Planner
  -> Context Packager
  -> Scheduler
  -> Worker Dispatch
  -> Merge Guard
  -> Verifier Swarm
  -> Result Synthesizer
  -> Risk Summary / Session Report
  -> PR / CI Feedback
```

要求：

- 不接受只存在模块，不存在主链路 orchestrator
- 必须提供至少一个统一入口函数或运行脚本，能驱动这条链路

### C. Schema 与 Contract 全量升级

你必须升级 schema，不再停留在最小字段集合。

#### TaskGraph 必须至少包含

- `graph_id`
- `intent`
- `tasks`
- `edges`
- `critical_path`
- `execution_batches`
- `risk_summary`
- `budget_summary`
- `created_at`
- `updated_at`
- `metadata`

#### TaskNode 必须至少包含

- `id`
- `title`
- `goal`
- `dependencies`
- `risk_level`
- `allowed_paths`
- `forbidden_paths`
- `acceptance_criteria`
- `required_tests`
- `model_tier`
- `verifier_set`
- `retry_policy`
- `timeout_ms`
- `estimated_tokens`
- `estimated_cost`
- `status`
- `assigned_role`
- `dispatch_artifact_id`

#### DispatchArtifact 必须至少包含

- `dispatch_id`
- `task_id`
- `prompt`
- `context_pack`
- `resource_boundary`
- `exit_criteria`
- `fallback_policy`
- `created_at`

#### SessionState 必须至少包含

- `session_id`
- `graph_id`
- `task_states`
- `dispatches`
- `retries`
- `downgrades`
- `escalations`
- `verifier_history`
- `risk_summary`
- `cost_summary`
- `events`

#### GateResult / MergeDecision 必须至少包含

- `task_id`
- `blocking_issues`
- `non_blocking_issues`
- `merge_allowed`
- `required_actions`
- `risk_level`

### D. 角色系统与状态机

必须定义四类一等角色：

1. planner
2. worker
3. verifier
4. synthesizer

每类角色必须具备：

- 输入 contract
- 输出 contract
- failure semantics
- resource boundary
- retry policy
- escalation rule

另外，你必须实现 task state machine，至少包含：

- `pending`
- `ready`
- `dispatched`
- `running`
- `verifying`
- `completed`
- `failed`
- `blocked`
- `merged`
- `aborted`

必须明确：

- 合法状态迁移
- 非法状态迁移如何报错
- 哪些状态会触发 retry
- 哪些状态会触发 downgrade / escalation / human handoff

### E. Planner 与 Task Graph 系统

你必须实现：

- `planner.ts`
- `intent-analyzer.ts`
- `task-graph-builder.ts`
- `complexity-scorer.ts`
- `critical-path-analyzer.ts`
- `ownership-planner.ts`

必须支持：

- 将自然语言目标转成结构化 planning input
- 生成 DAG
- 生成 edge 列表
- 推导 critical path
- 生成 execution batches
- 生成 risk summary
- 生成 budget hint
- 生成 verifier policy hint
- 生成 dispatch prerequisites

必须增强的点：

- task graph 不能只是一组节点
- ownership、model router、verifier policy 必须由 planner 联动产出

### F. Context Packager 升级

你必须实现最小上下文包系统，不是简单文件列表。

每个 context pack 至少包含：

- relevant files
- relevant excerpts
- ownership boundary
- acceptance criteria
- required tests
- constraints
- token budget
- references

必须支持：

- relevance scoring
- chunk selection
- hard token budget
- soft token budget
- forbidden path stripping
- docs/tests/config inclusion policy
- 失败时自动降级上下文大小

### G. Scheduler、Dispatch 与执行治理

你必须实现：

- `scheduler.ts`
- `worker-dispatch.ts`
- `batch-planner.ts`
- `retry-manager.ts`
- `downgrade-manager.ts`
- `escalation-policy.ts`

必须支持：

- 根据依赖图生成并行批次
- respect ownership 与 conflict constraints
- respect max concurrency
- dispatch artifact 生成
- 失败任务局部重试
- 冲突或失败率升高时自动降级到串行
- 连续失败时自动升级模型或人工接管

必须避免：

- 两个冲突任务同批并行
- 没有 dispatch artifact 就直接执行
- verifier fail 后没有后续动作

### H. Ownership Enforcement 与 Merge Guard

你必须实现：

- `ownership-enforcer.ts`
- `merge-guard.ts`
- `policy-engine.ts`
- `conflict-detector.ts`

必须支持：

- 路径重叠检查
- forbidden path 越界检查
- policy violation 检查
- merge risk scoring
- 冲突任务串行化或阻断
- verifier 结果进入 merge decision

必须做到：

- ownership 决策要真正影响 scheduler 和 merge
- 不能只把冲突路径从 `allowed_paths` 列表里拿掉
- 不能让冲突任务继续被同一批次调度

### I. 模型路由、预算与升级/降级闭环

你必须实现：

- `model-router.ts`
- `cost-controller.ts`
- `budget-policy.ts`
- `escalation-policy.ts`
- `downgrade-manager.ts`

必须定义 tier：

- `tier-1`
- `tier-2`
- `tier-3`

并明确：

- `tier-1`：低成本、轻任务、搜索/格式化/简单验证
- `tier-2`：通用实现、一般 review、测试生成
- `tier-3`：规划、设计、关键 review、复杂修复

必须接入：

- complexity score
- risk level
- token budget
- required verifier set
- failure count
- retry history

必须实现：

- 默认 tier 推荐
- 自动模型路由
- 失败升级
- 超预算降级
- routing reason logging

### J. Verifier Swarm 全量升级

你必须实现并串起至少以下 verifier：

- `test-verifier`
- `review-verifier`
- `security-verifier`
- `perf-verifier`
- `coverage-verifier`

必须实现：

- verifier contracts
- verifier runner
- parallel verifier execution
- verifier result normalization
- result synthesizer
- gate result

必须支持：

- 静态规则审查
- 真实测试执行结果接入
- 覆盖率证据接入
- 阻断 issue 抽取
- risk-aware verifier policy

要求：

- critical / high 风险任务不能只跑单一 verifier
- coverage 不能只看文件命名，需要看真实 coverage 证据或至少可接入位

### K. Session、History、Observability、Reporting

你必须实现：

- `event-bus.ts`
- `observability-server.ts`
- `session-state.ts`
- `task-history.ts`
- `verifier-history.ts`
- `risk-summary.ts`
- `report-builder.ts`

至少支持这些事件：

- `intent_received`
- `graph_created`
- `task_ready`
- `task_dispatched`
- `task_started`
- `task_completed`
- `task_failed`
- `retry_triggered`
- `downgrade_triggered`
- `escalation_triggered`
- `verifier_started`
- `verifier_completed`
- `merge_blocked`
- `session_completed`

必须产出：

- session report
- task history
- verifier history
- cost summary
- risk summary
- blocking issues list

### L. PR / CI Integration

你必须实现平台集成层，不再只做本地 orchestrator。

至少新增：

- `pr-review-agent.ts`
- `ci-failure-analyzer.ts`
- `autofix-dispatch.ts`
- `coverage-gap-agent.ts`
- `check-run-publisher.ts`

至少支持：

- PR diff 输入
- CI failure 输入
- 将 diff / failure 反向映射为 task graph
- 基于 verifier 和风险摘要生成 review 输出
- 对可修复问题派发 autofix
- 对 coverage 缺口生成建议

必须保证：

- PR/CI agent 读取 task graph、worker output、verifier report、risk summary
- 不能只输出表层 review comment

### M. Skills、Hooks、Capabilities 资产层

你必须创建真实能力资产，而不是空目录。

至少补齐：

- `skills/harness/`
- `skills/harness-plan/`
- `skills/harness-dispatch/`
- `skills/harness-verify/`
- `skills/harness-recovery/`
- `skills/harness-pr/`

每个 skill 至少包含：

- 用途
- 触发条件
- 输入输出
- 风险和降级策略
- 与 runtime 的关系

并建立：

- `docs/capabilities/`

每个 capability 至少说明：

- `name`
- `intent`
- `required_context`
- `worker_policy`
- `verifier_policy`
- `failure_mode`
- `fallback_strategy`

如果需要 hooks，也必须给出真实文件，而不是只建目录。

### N. GUI 与控制面

本轮不要求做完整高级前端，但既然目标是“大而全面的插件”，你至少要交付最小控制面：

- task graph 状态视图
- current batch / running tasks 视图
- verifier result 面板
- risk / cost summary 面板
- event timeline

可以先做最小可运行 GUI，但不能完全跳过控制面。

### O. Build、Dist、Install、Marketplace

你必须将插件推进到可构建和可安装状态。

至少完成：

- `build` 脚本
- `dist/parallel-harness`
- 安装 smoke test
- 与市场接入的准备文档

如果具备最低条件，则更新：

- [marketplace.json](/Users/lorain/Coding/Huihao/claude-autopilot/.claude-plugin/marketplace.json)

如果仍未达到最低条件，则必须明确给出：

- 为什么不能接入
- 离接入还差哪些硬条件
- 每一项的完成标准

### P. 测试体系升级

测试不能只停留在 unit test。

你必须至少建立：

- `tests/unit/`
- `tests/integration/`
- `tests/e2e/`
- `tests/fixtures/`

至少覆盖以下场景：

1. intent -> graph -> ownership -> scheduler
2. worker dispatch -> verifier -> synthesize
3. 冲突任务被 merge guard 阻断
4. verifier fail -> retry / escalate
5. budget exceeded -> downgrade
6. PR diff -> task graph -> review report
7. session report / history / events 正常产出
8. build + dist + install smoke test

要求：

- 不能只测 schema
- 不能只测 happy path
- 至少有 sad path / failure path / conflict path / budget path

### Q. 文档与运营材料

你必须补齐：

- 插件 README
- 中文 README
- 架构概览
- roadmap
- capability docs
- operations guide
- troubleshooting
- integration guide
- marketplace readiness note

并明确：

- 与 `spec-autopilot` 的边界
- 何时使用 `parallel-harness`
- 何时不要使用它
- 风险与降级机制

## 建议实施顺序

### 第一阶段：补齐平台骨架与主链路

先完成：

- 目录升级
- schema 升级
- planner / orchestrator 主入口
- task state machine

### 第二阶段：执行闭环

再完成：

- scheduler
- worker dispatch
- ownership enforcement
- merge guard
- retry / downgrade / escalation

### 第三阶段：质量闭环

然后完成：

- verifier swarm
- coverage verifier
- gate result
- risk summary / report

### 第四阶段：观测与历史

继续完成：

- event bus
- session state
- task history
- verifier history
- observability / GUI

### 第五阶段：PR / CI 与产品化

最后完成：

- PR review integration
- CI failure analyzer
- autofix dispatch
- build / dist / install
- marketplace readiness

## 验收标准

至少满足：

1. `parallel-harness` 具备真实完整插件目录与能力资产。
2. 存在统一 orchestrator 主链路，而不是只有散落模块。
3. task graph 包含图级结构，不是仅有节点数组。
4. ownership 决策真正影响 scheduler 与 merge guard。
5. 模型路由具备自动闭环，不被默认 tier 短路。
6. verifier swarm 至少包含 test/review/security/perf/coverage。
7. verifier 结果能够形成正式 gate，而不是纯展示。
8. 存在 session history、verifier history、risk summary、cost summary。
9. 存在 PR/CI integration 基础实现。
10. 存在 skills、capabilities、hooks 或相应资产文件。
11. 存在 build 产物与 `dist/parallel-harness`。
12. 至少一组 integration/e2e 测试可运行。
13. README、架构文档、集成文档能够指导实际使用。
14. 可以清晰判断是否已满足市场接入条件。

## 最终输出必须包含

1. 你新增或修改了哪些目录与文件
2. 你完成了哪些平台级能力
3. 哪些竞品能力已真正落地为 runtime / assets / tests / integration
4. 哪些环节仍未完成，为什么
5. 当前是否已经具备 build / dist / install / marketplace readiness
6. 你运行了哪些验证命令，结果是什么
7. 当前插件距离“大而全面的全栈平台”还差哪些收尾

## 最终提示词

```text
你现在是这个仓库中新产品线 `parallel-harness` 的平台架构师兼实现工程师。你的目标不是补一个 MVP，也不是补几个空接口，而是把 `parallel-harness` 推进成一个真正大而全面、具备工程闭环能力的新插件产品。

仓库根目录：
/Users/lorain/Coding/Huihao/claude-autopilot

任务对象：
新插件 `parallel-harness`

产品定位：
`parallel-harness` 是一个新的插件，不是 `spec-autopilot vNext`。它要与 `spec-autopilot` 共存，并最终进入同一个插件市场 `lorainwings-plugins`。它的定位是“真正的并行 AI 平台 / AI 软件工程控制面插件”。

你必须先阅读并遵循以下文档：
1. /Users/lorain/Coding/Huihao/claude-autopilot/docs/plans/2026-03-19-holistic-architecture-research-report.zh.md
2. /Users/lorain/Coding/Huihao/claude-autopilot/docs/plans/2026-03-19-parallel-ai-platform-plugin-design.zh.md
3. /Users/lorain/Coding/Huihao/claude-autopilot/docs/plans/2026-03-19-competitive-capability-reuse-matrix.zh.md
4. /Users/lorain/Coding/Huihao/claude-autopilot/docs/plans/2026-03-19-parallel-harness-execution-backlog.zh.md
5. /Users/lorain/Coding/Huihao/claude-autopilot/docs/plans/2026-03-19-parallel-harness-execution-prompt.zh.md
6. /Users/lorain/Coding/Huihao/claude-autopilot/docs/plans/2026-03-20-parallel-harness-full-platform-execution-prompt.zh.md

你还必须参考这些竞品和官方产品方向：
- Harness AI Agents: https://developer.harness.io/docs/code-repository/pull-requests/ai-agents/
- GitHub Copilot coding agent: https://docs.github.com/en/copilot/concepts/coding-agent/coding-agent
- CodeRabbit PR review: https://docs.coderabbit.ai/overview/pull-request-review
- claude-task-master
- claude-code-switch
- oh-my-claudecode
- everything-claude-code
- BMAD-METHOD
- get-shit-done
- superpowers

一、你必须理解本轮目标
1. 这不是 MVP 提示词。
2. 这不是只补 schema、README、空目录的任务。
3. 这是把 `parallel-harness` 推进成大而全面平台插件的任务。
4. 你必须优先补齐执行闭环、治理闭环、PR/CI 闭环、产品化链路。

二、你必须解决当前版本的关键缺口
1. 当前没有真正主链路 orchestrator。
2. 当前 ownership 没有真正约束 scheduler 和 merge。
3. 当前自动模型路由被默认 tier 短路。
4. 当前没有 worker dispatch / retry / downgrade / escalation。
5. 当前没有 event bus / session history / verifier history / risk summary。
6. 当前没有 PR / CI integration。
7. 当前没有 build / dist / installable path。
8. 当前 skills / capabilities / hooks 资产层不完整。

三、你必须建设的目录与模块
请将插件升级到至少如下结构：
- `plugins/parallel-harness/.claude-plugin/`
- `plugins/parallel-harness/docs/`
- `plugins/parallel-harness/docs/operations/`
- `plugins/parallel-harness/docs/capabilities/`
- `plugins/parallel-harness/gui/`
- `plugins/parallel-harness/hooks/`
- `plugins/parallel-harness/runtime/orchestrator/`
- `plugins/parallel-harness/runtime/scheduler/`
- `plugins/parallel-harness/runtime/dispatch/`
- `plugins/parallel-harness/runtime/guard/`
- `plugins/parallel-harness/runtime/recovery/`
- `plugins/parallel-harness/runtime/models/`
- `plugins/parallel-harness/runtime/verifiers/`
- `plugins/parallel-harness/runtime/observability/`
- `plugins/parallel-harness/runtime/session/`
- `plugins/parallel-harness/runtime/history/`
- `plugins/parallel-harness/runtime/ci/`
- `plugins/parallel-harness/runtime/scripts/`
- `plugins/parallel-harness/runtime/schemas/`
- `plugins/parallel-harness/skills/harness/`
- `plugins/parallel-harness/skills/harness-plan/`
- `plugins/parallel-harness/skills/harness-dispatch/`
- `plugins/parallel-harness/skills/harness-verify/`
- `plugins/parallel-harness/skills/harness-recovery/`
- `plugins/parallel-harness/skills/harness-pr/`
- `plugins/parallel-harness/tests/unit/`
- `plugins/parallel-harness/tests/integration/`
- `plugins/parallel-harness/tests/e2e/`
- `plugins/parallel-harness/tests/fixtures/`
- `plugins/parallel-harness/tools/`

四、你必须实现的平台主链路
请直接实现并尽量跑通：
User Intent
-> Planner
-> Intent Analyzer
-> Task Graph Builder
-> Complexity Scorer
-> Ownership Planner
-> Context Packager
-> Scheduler
-> Worker Dispatch
-> Merge Guard
-> Verifier Swarm
-> Result Synthesizer
-> Session Report / Risk Summary
-> PR / CI Feedback

五、你必须实现的核心模块
1. planner
2. task graph schema 升级（包含 graph_id/tasks/edges/critical_path/execution_batches/risk_summary/budget_summary）
3. task state machine
4. dispatch artifact schema
5. session state schema
6. gate result / merge decision schema
7. critical-path-analyzer
8. worker-dispatch
9. batch-planner
10. ownership-enforcer
11. merge-guard
12. conflict-detector
13. policy-engine
14. retry-manager
15. downgrade-manager
16. escalation-policy
17. cost-controller
18. budget-policy
19. coverage-verifier
20. verifier-runner
21. event-bus
22. observability-server
23. task-history
24. verifier-history
25. risk-summary
26. report-builder
27. pr-review-agent
28. ci-failure-analyzer
29. autofix-dispatch
30. coverage-gap-agent

六、你必须遵守的实现要求
1. ownership 决策必须真正影响 scheduler 和 merge guard。
2. 自动模型路由不能被默认值短路。
3. verifier 结果必须形成 gate，而不是仅展示。
4. critical/high 风险任务必须提升 verifier 强度。
5. retry / downgrade / escalation 必须有清晰触发条件。
6. 所有核心模块都必须有清晰输入输出和测试。
7. 至少一个统一 orchestrator 主入口能够驱动完整链路。

七、你必须实现的资产层
1. capability catalog
2. 至少 5 个真实 skill
3. capability docs
4. operations guide
5. troubleshooting
6. PR/CI integration guide

每个 capability 至少描述：
- name
- intent
- required_context
- worker_policy
- verifier_policy
- failure_mode
- fallback_strategy

八、你必须完成的产品化链路
1. build 脚本
2. dist/parallel-harness
3. install smoke test
4. 市场接入评估
5. 如果满足条件则更新 marketplace.json

九、你必须补齐的测试层次
1. unit
2. integration
3. e2e
4. fixtures

至少覆盖这些场景：
- intent -> graph -> ownership -> scheduler
- worker dispatch -> verifier -> synthesize
- conflict -> merge guard block
- verifier fail -> retry / escalate
- budget exceeded -> downgrade
- PR diff -> task graph -> review output
- session history / event bus / report output
- build + dist + install smoke test

十、你不能做的事情
1. 不要只建空目录。
2. 不要只写 schema 不写执行器。
3. 不要只写 README 和设计文档。
4. 不要把所有困难模块都标成“预留”。
5. 不要把平台能力塞回 `spec-autopilot`。
6. 不要再用“先做 MVP”作为默认缩减理由。

十一、建议执行顺序
1. 先升级 schema、state machine、主链路 orchestrator
2. 再补 scheduler / dispatch / merge guard / recovery
3. 再补 verifier swarm / coverage / gate
4. 再补 event bus / session / history / report
5. 再补 PR/CI integration
6. 最后完成 build / dist / install / marketplace readiness

十二、验收标准
至少满足：
1. 插件目录和能力资产完整存在。
2. 主链路可运行，不只是模块集合。
3. ownership 真正约束调度和合并。
4. model router 真正自动生效。
5. verifier swarm 和 gate 可运行。
6. session/report/history/events 可产出。
7. 存在 PR/CI integration 基础实现。
8. 存在 build/dist/installable path。
9. 至少一组 integration/e2e 测试可运行。
10. 可以明确判断是否已满足 marketplace 接入条件。

十三、最终输出必须包含
1. 你新增或修改了哪些目录和文件
2. 你实现了哪些平台级能力
3. 哪些竞品能力已真正落地
4. 哪些环节仍未完成以及客观原因
5. 当前是否具备 build / dist / install / marketplace readiness
6. 你运行了哪些验证命令，结果是什么
7. 当前距离全栈平台目标还差什么

现在开始直接执行，不要只给计划，不要只补几个文件。
```
