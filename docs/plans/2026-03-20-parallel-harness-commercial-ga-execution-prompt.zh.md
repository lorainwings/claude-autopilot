# parallel-harness 商业化 GA 执行提示词

> 日期：2026-03-20
> 目的：这是一份基于 `parallel-harness` 当前现状继续推进的商业化执行提示词。
> 使用方式：直接复制 `## 最终提示词` 下的全部内容，原样交给 Claude。
> 执行要求：本轮目标不是再做 Beta/MVP 包装，而是把 `parallel-harness` 提升到可直接商业化接入、可治理、可审计、可集成、可持续运维的 GA 级插件。

## 为什么需要这份新提示词

`parallel-harness` 当前已经比最初版本更完整，完成了：

- 独立插件目录
- 核心 schema、orchestrator、scheduler、router、verifiers
- worker-dispatch / retry / downgrade / cost / escalation
- event-bus / observability / session-state
- PR/CI 格式化模块
- 两个 skill、一个 hook
- `build-dist.sh`
- `dist/parallel-harness`
- marketplace 条目注册
- 119 个测试、482 个断言、类型检查和构建通过

但当前版本仍然没有达到“大而全面、可商业化接入和直接使用”的目标。

经 review，当前版本的核心问题不是“缺几个文件”，而是存在一批平台级假闭环：

- 仍然没有真正的统一 orchestrator 主入口
- `worker-dispatch` 仍是模拟执行，不是真实 worker 进程 / worktree / agent 执行
- ownership 决策没有真正进入 scheduler 和 merge guard
- 自动模型路由仍会被默认 `model_tier` 短路
- PR/CI 模块主要是格式化器，不是真实 provider integration
- coverage 只是 reporter，不是 coverage verifier / coverage ingest / coverage gate
- session / observability / event-bus 仍是内存态，不是可审计、可恢复的持久化控制面
- 缺 policy-as-code、RBAC、approval gates、human-in-the-loop、audit trail
- 缺 GUI 控制面、ops 文档、capability docs、troubleshooting、integration guide
- 缺 install smoke test、provider integration smoke test、end-to-end real workflow test

因此本轮不能再围绕 `docs/mvp-scope.zh.md` 继续轻量迭代，而必须直接切换到商业化 GA 建设模式。

## 当前版本的真实状态判断

### 已完成但仍偏“模块化 Beta”的部分

- 基础 schema
- 任务理解层
- 调度器基础结构
- 模型路由基础结构
- 静态 verifier
- 基础控制面模块
- 基础 PR/CI 输出格式化
- 技能和 hooks 骨架
- 构建脚本和 dist 打包

### 仍未完成的关键 GA 要求

- 真实 worker runtime
- 统一执行主链路
- merge guard enforcement
- policy engine / governance
- audit trail / persistent session history
- actual PR/CI provider integration
- real coverage ingestion and gate
- GUI / control-plane
- operations / capabilities / troubleshooting 文档
- installability / smoke / supportability / commercial readiness

## 你必须参考的本地文档

开始实现前，必须阅读并遵循这些文档：

- [总调研报告](/Users/lorain/Coding/Huihao/claude-autopilot/docs/plans/2026-03-19-holistic-architecture-research-report.zh.md)
- [新并行 AI 平台插件设计方案](/Users/lorain/Coding/Huihao/claude-autopilot/docs/plans/2026-03-19-parallel-ai-platform-plugin-design.zh.md)
- [竞品能力复用矩阵](/Users/lorain/Coding/Huihao/claude-autopilot/docs/plans/2026-03-19-competitive-capability-reuse-matrix.zh.md)
- [parallel-harness 实施 Backlog](/Users/lorain/Coding/Huihao/claude-autopilot/docs/plans/2026-03-19-parallel-harness-execution-backlog.zh.md)
- [上一版全量平台提示词](/Users/lorain/Coding/Huihao/claude-autopilot/docs/plans/2026-03-20-parallel-harness-full-platform-execution-prompt.zh.md)

## 你必须参考的成熟竞品与官方资料

本轮实现必须参考以下成熟产品能力，并以它们的工程闭环标准为最低对标线：

- Harness Agents 官方文档
- GitHub Copilot coding agent 官方文档
- CodeRabbit 官方文档

这些竞品提供的关键参考维度包括：

- pipeline-native / PR-native execution
- approval gates / human-in-the-loop
- audit trail / session tracking / logs
- policy-as-code / RBAC / scoped tools
- PR summary / code review / autofix / coverage
- issue-to-plan / diff-to-review / CI-to-remediation
- provider-native integration

官方参考链接：

- Harness Agents: `https://developer.harness.io/docs/platform/harness-aida/harness-agents`
- GitHub Copilot coding agent: `https://docs.github.com/en/copilot/using-github-copilot/using-copilot-coding-agent-to-work-on-tasks`
- GitHub Copilot coding agent overview: `https://docs.github.com/en/copilot/concepts/agents/coding-agent/about-coding-agent`
- CodeRabbit PR review: `https://docs.coderabbit.ai/overview/pull-request-review`
- CodeRabbit review commands: `https://docs.coderabbit.ai/reference/review-commands`
- CodeRabbit PR summaries: `https://docs.coderabbit.ai/pr-reviews/summaries`
- CodeRabbit review instructions: `https://docs.coderabbit.ai/guides/review-instructions`

## 成熟竞品对标要求

### 对标 Harness Agents

你必须吸收并落地：

- pipeline-native execution
- step/template 化 agent 封装
- BYOM / connector 化模型接入
- policy-as-code
- human-in-the-loop approvals
- full audit trail
- scoped tools / least privilege
- PR/CI/coverage/autofix agents

你必须避免：

- 只有模块，没有运行时
- 没有审批点和治理策略
- 没有可审计日志
- 没有 provider-native API 集成

### 对标 GitHub Copilot coding agent

你必须吸收并落地：

- 后台 agent session
- session tracking
- 任务到 PR 的可追踪闭环
- branch / workflow governance
- integration with MCP-aware tooling

你必须避免：

- 只有本地函数调用，没有 session 概念
- 没有分支策略
- 没有 workflow approval / guard
- 没有 agent execution trace

### 对标 CodeRabbit

你必须吸收并落地：

- 自动 PR summary
- review commands / interactive review loop
- path-based review instructions
- code guidelines / custom checks
- autofix loop
- issue planner / implementation plan
- coverage and review evidence

你必须避免：

- 只有 Markdown formatter，没有真实 review workflow
- 没有 path-based policy
- 没有 config-driven review rules
- 没有 autofix / plan / command loop

## 本轮总目标

本轮目标是把 `parallel-harness` 升级为：

- 可直接商业化接入
- 可直接安装使用
- 可接入 PR / CI / issue workflow
- 可审计
- 可治理
- 可恢复
- 可观测
- 可配置
- 可扩展

换句话说，本轮要完成的是：

1. 真正可执行
2. 真正可集成
3. 真正可运维
4. 真正可商用

## 全量完成原则

1. 不能再把“模拟执行”当成完成。
2. 不能再把“格式化 PR 评论”当成 CI/PR integration 完成。
3. 不能再把“coverage report”当成 coverage gate 完成。
4. 不能再把“内存快照”当成 session persistence / audit trail 完成。
5. 不能再把“有 dist 目录”当成 installable / commercial-ready 完成。
6. 不能再把“有 hooks/skills 文件”当成 capability layer 完成。
7. 不能再把“测试都通过”当成 end-to-end 可商用完成。

## 你必须继续完成的完整范围

### A. 统一主链路与平台运行时

你必须新增真实的统一 orchestrator 主入口，不再只导出零散模块。

至少补齐：

- `runtime/orchestrator/planner.ts`
- `runtime/orchestrator/execution-controller.ts`
- `runtime/orchestrator/platform-orchestrator.ts`
- `runtime/orchestrator/runtime-entry.ts`

主链路必须变成：

```text
User / PR / CI / Issue
  -> Planner
  -> Task Graph Builder
  -> Ownership Planner
  -> Context Packager
  -> Scheduler
  -> Worker Dispatch
  -> Merge Guard
  -> Verifier Runner / Swarm
  -> Result Synthesizer
  -> Session History / Report
  -> PR / CI feedback
```

要求：

- 至少一个可调用入口
- 至少一个能跑通的 end-to-end orchestration path
- skills 必须调用真实 runtime，而不是只写文字流程

### B. 真实 Worker Runtime 与隔离执行

当前 `worker-dispatch` 仍然是模拟执行。你必须把它升级为真实执行器。

至少补齐：

- 子进程 / CLI 执行模式
- git worktree 隔离模式
- sandbox 隔离模式接口
- dispatch artifact 生成
- worker prompt / task packet 生成
- stdout / stderr / exit code / artifact 采集

必须实现：

- 真正启动 worker
- 真正收集变更
- 真正处理 timeout / cancel / failure
- 真正隔离 allowed_paths

必须新增：

- `runtime/dispatch/worker-runtime.ts`
- `runtime/dispatch/worktree-manager.ts`
- `runtime/dispatch/process-runner.ts`
- `runtime/dispatch/dispatch-artifact.ts`

### C. Ownership Enforcement、Merge Guard、Policy Engine

当前 ownership 仍没有进入调度硬约束。你必须把 ownership 升级为真正的治理层。

至少新增：

- `runtime/guard/ownership-enforcer.ts`
- `runtime/guard/merge-guard.ts`
- `runtime/guard/conflict-detector.ts`
- `runtime/guard/policy-engine.ts`
- `runtime/guard/path-boundary-check.ts`

必须实现：

- 冲突任务不能被同一批次调度
- merge guard 必须读取 verifier/gate 结果
- path violation 必须阻断合并
- allowed/forbidden path 必须进入 worker runtime
- policy engine 必须能表达 repo rules、路径规则、敏感目录规则、测试要求、文档要求

### D. Schema 升级到 GA

当前 schema 仍偏 MVP。必须升级：

#### TaskGraph 必须至少包含

- `graph_id`
- `intent`
- `tasks`
- `edges`
- `critical_path`
- `execution_batches`
- `risk_summary`
- `budget_summary`
- `history_id`
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
- `dispatch_artifact_id`
- `status`
- `assigned_role`

#### DispatchArtifact 必须至少包含

- `dispatch_id`
- `task_id`
- `worker_mode`
- `prompt`
- `context_pack`
- `resource_boundary`
- `exit_criteria`
- `fallback_policy`
- `created_at`

#### GateResult / MergeDecision 必须至少包含

- `task_id`
- `blocking_issues`
- `non_blocking_issues`
- `merge_allowed`
- `required_actions`
- `risk_level`
- `confidence`

#### Session / Audit 必须至少包含

- `session_id`
- `task_history`
- `dispatch_history`
- `verifier_history`
- `escalation_history`
- `downgrade_history`
- `cost_history`
- `event_log`
- `report_artifacts`

### E. Task State Machine 与 Failure Taxonomy

当前状态模型仍太粗。你必须实现正式状态机。

至少支持：

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

必须定义：

- 合法状态迁移
- 非法迁移报错
- 哪些失败可重试
- 哪些失败需要降级
- 哪些失败需要升级模型
- 哪些失败需要人工接管

还必须建立 failure taxonomy：

- planner failure
- dispatch failure
- worker runtime failure
- policy violation
- merge conflict
- verifier failure
- budget failure
- provider integration failure
- infrastructure timeout

### F. 模型路由、成本与升级/降级闭环

当前模型路由仍有默认 tier 短路问题，成本控制与升级/降级也还不够闭环。

你必须完成：

- 修复默认 `model_tier` 短路
- 让 routing 真正基于 complexity/risk/budget/failure history/context size 生效
- 让 escalation / downgrade 与真实 worker/verifier/session 联动
- 引入 routing reason logging
- 引入 per-task / per-session / per-batch cost accounting

至少新增或升级：

- `runtime/models/router-reason.ts`
- `runtime/models/budget-policy.ts`
- `runtime/models/routing-history.ts`

### G. Verifier Swarm 升级为真正的 Gate 系统

你必须把 verifier 从“静态扫描器集合”升级为真正 gate。

至少补齐：

- `coverage-verifier`
- `verifier-runner`
- `gate-evaluator`
- `risk-aware-verifier-policy`

必须支持：

- 真实测试执行结果
- coverage 文件输入（如 lcov / cobertura / junit 变体）
- security/perf/test/review 并行运行
- 任务风险分级决定 verifier 组合和阈值
- gate result 输出

不能再接受：

- 只从 test findings 推导 coverage
- 只有 reporter 没有 verifier
- fail/warn 结果不进入合并阻断

### H. PR / CI Provider-Native Integration

当前 `PRReviewer`、`CIRunner`、`CoverageReporter` 主要是格式化层，不是 provider-native integration。

你必须新增真实集成层：

- `runtime/ci/github-provider.ts`
- `runtime/ci/gitlab-provider.ts` 或至少预留 provider interface
- `runtime/ci/check-run-publisher.ts`
- `runtime/ci/pr-comment-publisher.ts`
- `runtime/ci/pr-summary-updater.ts`
- `runtime/ci/ci-failure-ingest.ts`
- `runtime/ci/autofix-dispatch.ts`
- `runtime/ci/coverage-gap-agent.ts`
- `runtime/ci/issue-planner.ts`

至少支持：

- 输入 PR diff
- 输出 PR summary
- 发布 line comments
- 发布 check runs / status checks
- ingest CI failures
- 生成 remediation / autofix plan
- 基于 issue 生成 implementation plan

### I. Session Persistence、Audit Trail、History

当前 session-state 和 event-bus 仍然是内存态。商业化使用要求持久化和审计。

你必须新增：

- `runtime/session/state-store.ts`
- `runtime/history/task-history.ts`
- `runtime/history/verifier-history.ts`
- `runtime/history/dispatch-history.ts`
- `runtime/history/audit-log.ts`
- `runtime/history/risk-summary.ts`
- `runtime/history/report-builder.ts`

必须支持：

- 文件持久化或 sqlite 持久化
- session restore
- task/verifier/dispatch/escalation/downgrade 历史查询
- audit trail
- report artifact 输出

### J. Governance、RBAC、Human-in-the-Loop

要达到商用标准，必须引入治理层。

至少新增：

- `runtime/governance/approval-gate.ts`
- `runtime/governance/rbac-policy.ts`
- `runtime/governance/tool-allowlist.ts`
- `runtime/governance/manual-checkpoint.ts`

必须支持：

- effectful actions 前审批
- 敏感目录/敏感任务人工确认
- 工具 allowlist
- 模型/路径/操作范围的 policy control

### K. GUI / Control Plane

商业化插件不能没有控制面。

至少补齐最小 GUI：

- task graph 视图
- batch / worker 状态面板
- verifier result 面板
- risk / cost 仪表盘
- event timeline
- session history 列表

优先位置：

- `plugins/parallel-harness/gui/`

### L. Skills、Hooks、Capability Assets 全量升级

当前只有两个 skill 和一个几乎无业务价值的 hook，不够。

至少新增：

- `skills/harness/`
- `skills/harness-plan/`
- `skills/harness-dispatch/`
- `skills/harness-verify/`
- `skills/harness-recovery/`
- `skills/harness-pr/`
- `skills/harness-ci/`

并新增：

- `docs/capabilities/`
- `docs/operations/`
- `docs/troubleshooting/`
- `docs/integration/`

每个 capability 至少说明：

- name
- intent
- trigger
- required_context
- worker_policy
- verifier_policy
- failure_mode
- fallback_strategy
- commercial limitations

### M. Commercial Readiness 与发布链路

你必须把“能 build”升级为“能交付、能装、能运维”。

至少补齐：

- `package.json` 中的 `build` / `dist` / `smoke` 脚本
- install smoke test
- provider integration smoke test
- upgrade / migration note
- release checklist
- versioning strategy
- changelog

必须评估：

- marketplace 安装后是否可直接使用
- 没有 README.zh / ops 文档 / integration guide 是否会影响商业交付
- hook/skill/provider 缺失会不会导致“看起来能装，实际上不能用”

### N. 测试体系升级为商用级

你必须把测试升级为：

- `tests/unit/`
- `tests/integration/`
- `tests/e2e/`
- `tests/smoke/`
- `tests/fixtures/`

至少补齐这些测试：

1. planner -> graph -> ownership -> scheduler -> dispatch -> verifier -> gate
2. 冲突任务不能同批执行
3. 模型路由在默认任务下真实生效
4. worker runtime 真正产出变更
5. merge guard 阻断越界和冲突
6. coverage verifier ingest 真实 coverage 文件
7. PR provider 发布 summary / comments / checks
8. session restore / audit trail 可查询
9. install smoke test
10. dist artifact smoke test
11. hook / skill activation smoke test

### O. 文档与商业交付材料

必须补齐：

- README
- README.zh
- architecture
- operations guide
- troubleshooting
- integration guide
- capability docs
- security/governance guide
- marketplace readiness note
- “何时选 parallel-harness / 何时不要选” 文档

## 验收标准

至少满足：

1. 不再存在模拟 worker 作为默认执行路径。
2. 存在统一 orchestrator 主链路。
3. ownership 真正进入 scheduler / dispatch / merge guard。
4. 默认任务不再因默认 `model_tier` 使自动路由失效。
5. verifier 结果形成真正 gate。
6. coverage 具备真实 ingest 和 gate。
7. PR/CI 具备 provider-native integration，而不只是 formatter。
8. session / history / audit 可持久化和恢复。
9. 至少一个最小 GUI 控制面可运行。
10. skills / hooks / capabilities / ops docs 足够支持商业交付。
11. 存在 install smoke test 和 end-to-end smoke test。
12. 当前版本可被清晰判断为是否达到商业接入标准。

## 最终输出必须包含

1. 你在当前版本基础上新增和修改了哪些模块
2. 哪些“假闭环”已被替换为真实闭环
3. 哪些竞品能力已真正落地
4. 还缺哪些商业化要件
5. 你运行了哪些验证命令，结果如何
6. 当前是否已达到 GA / commercial-ready

## 最终提示词

```text
你现在是 `parallel-harness` 的平台负责人和实现工程师。请不要再按 MVP/Beta 思路工作，而是基于当前已有实现，继续把这个插件升级为可商业化接入、可直接使用、可治理、可审计、可运维的 GA 级产品。

仓库根目录：
/Users/lorain/Coding/Huihao/claude-autopilot

目标插件：
plugins/parallel-harness

你必须先阅读这些文档：
1. /Users/lorain/Coding/Huihao/claude-autopilot/docs/plans/2026-03-19-holistic-architecture-research-report.zh.md
2. /Users/lorain/Coding/Huihao/claude-autopilot/docs/plans/2026-03-19-parallel-ai-platform-plugin-design.zh.md
3. /Users/lorain/Coding/Huihao/claude-autopilot/docs/plans/2026-03-19-competitive-capability-reuse-matrix.zh.md
4. /Users/lorain/Coding/Huihao/claude-autopilot/docs/plans/2026-03-19-parallel-harness-execution-backlog.zh.md
5. /Users/lorain/Coding/Huihao/claude-autopilot/docs/plans/2026-03-20-parallel-harness-full-platform-execution-prompt.zh.md
6. /Users/lorain/Coding/Huihao/claude-autopilot/docs/plans/2026-03-20-parallel-harness-commercial-ga-execution-prompt.zh.md

你还必须参考这些成熟竞品与官方资料：
- Harness Agents: https://developer.harness.io/docs/platform/harness-aida/harness-agents
- GitHub Copilot coding agent: https://docs.github.com/en/copilot/using-github-copilot/using-copilot-coding-agent-to-work-on-tasks
- GitHub Copilot coding agent overview: https://docs.github.com/en/copilot/concepts/agents/coding-agent/about-coding-agent
- CodeRabbit PR review: https://docs.coderabbit.ai/overview/pull-request-review
- CodeRabbit review commands: https://docs.coderabbit.ai/reference/review-commands
- CodeRabbit PR summaries: https://docs.coderabbit.ai/pr-reviews/summaries
- CodeRabbit review instructions: https://docs.coderabbit.ai/guides/review-instructions

一、你必须理解当前版本的真实问题
1. 当前 worker-dispatch 仍然是模拟执行，不是真实 worker runtime。
2. 当前没有统一 orchestrator 主入口。
3. 当前 ownership 没有真正影响 scheduler 和 merge guard。
4. 当前自动模型路由仍会被默认 model_tier 短路。
5. 当前 PR/CI 模块主要是 formatter，不是 provider-native integration。
6. 当前 coverage 主要是 reporter，不是 coverage verifier / coverage gate。
7. 当前 session/event-bus/observability 主要是内存态，不是可恢复和可审计的控制面。
8. 当前 skills / hooks / capability docs / ops docs 远远不够商业交付。
9. 当前没有 GUI 控制面。

二、你不能做的事情
1. 不要继续把模拟实现当成完成。
2. 不要只写文档和接口。
3. 不要再以 MVP/Beta 为默认缩减理由。
4. 不要再只补格式化器而不补 provider integration。
5. 不要只补 unit test，不补 integration/e2e/smoke。

三、你必须继续完成的范围

A. 统一 orchestrator 主链路
- 新增 planner、execution-controller、platform-orchestrator、runtime-entry
- 把 skills 接到真实 runtime

B. 真实 worker runtime
- process runner
- git worktree manager
- dispatch artifact
- stdout/stderr/exit code/changed files 收集

C. ownership / merge guard / policy engine
- ownership-enforcer
- conflict-detector
- merge-guard
- policy-engine
- path-boundary-check

D. schema 升级到 GA
- TaskGraph: graph_id/tasks/edges/critical_path/execution_batches/risk_summary/budget_summary/history_id
- TaskNode: retry_policy/timeout_ms/estimated_tokens/estimated_cost/dispatch_artifact_id 等
- DispatchArtifact
- GateResult / MergeDecision
- Session / Audit schema

E. task state machine + failure taxonomy
- 支持 pending/ready/dispatched/running/verifying/completed/failed/blocked/merged/aborted
- 定义合法迁移
- 定义 failure taxonomy

F. model routing / cost / escalation / downgrade 闭环
- 修复默认 model_tier 短路
- 让 routing 真正按 complexity/risk/budget/history 生效
- 增加 routing reason logging

G. verifier swarm 升级为 gate 系统
- coverage-verifier
- verifier-runner
- gate-evaluator
- risk-aware-verifier-policy
- 真实 coverage ingest

H. PR / CI provider-native integration
- github-provider
- check-run-publisher
- pr-comment-publisher
- pr-summary-updater
- ci-failure-ingest
- autofix-dispatch
- coverage-gap-agent
- issue-planner

I. session persistence / audit trail / report
- state-store
- task-history
- verifier-history
- dispatch-history
- audit-log
- risk-summary
- report-builder

J. governance / RBAC / approval gates
- approval-gate
- rbac-policy
- tool-allowlist
- manual-checkpoint

K. GUI / control-plane
- task graph view
- worker panel
- verifier panel
- risk/cost dashboard
- session history

L. skills / hooks / capability / ops docs
- 新增 harness-plan / harness-dispatch / harness-verify / harness-recovery / harness-pr / harness-ci
- 新增 docs/capabilities docs/operations docs/troubleshooting docs/integration

M. commercial readiness
- package.json build/dist/smoke 脚本
- install smoke test
- provider integration smoke test
- release checklist
- changelog
- versioning / migration note

N. testing
- unit / integration / e2e / smoke / fixtures
- planner->dispatch->verifier->gate e2e
- conflict block
- real routing
- real worker result
- provider publish path
- session restore
- dist/install smoke

四、成熟竞品对标要求
1. 对标 Harness：pipeline-native、policy-as-code、RBAC、approval、audit trail。
2. 对标 GitHub Copilot coding agent：background session、session tracking、branch/workflow governance。
3. 对标 CodeRabbit：PR summaries、review commands、path-based review instructions、autofix、issue planner、custom checks。

五、验收标准
1. 默认执行路径中不再有模拟 worker。
2. ownership 真正影响 scheduler / dispatch / merge guard。
3. model router 默认任务下真实生效。
4. gate 真正阻断高风险/失败结果。
5. coverage 为真实 verifier，不是仅 reporter。
6. PR/CI 为 provider-native integration，而不是 formatter。
7. session/history/audit 可持久化与恢复。
8. 至少一个 GUI 控制面可运行。
9. skills/hooks/docs 足以支持商业交付。
10. install smoke 和 e2e smoke 可运行。

六、最终输出必须包含
1. 新增和修改了哪些模块
2. 哪些假闭环已被替换为真实闭环
3. 哪些竞品能力真正落地
4. 剩余商业化缺口
5. 运行了哪些验证命令及结果
6. 当前是否已达到 commercial-ready / GA

现在开始直接执行，不要只给计划。
```
