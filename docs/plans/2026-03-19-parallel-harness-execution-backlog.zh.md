# parallel-harness 实施 Backlog

> 日期：2026-03-19
> 目标：将 `parallel-harness` 从概念方案推进到可执行工程计划。
> 原则：足够细，能够直接拆 Sprint、拆任务、拆模块。

## 1. 目标状态

交付一个新的 Claude Code 插件：

- 名称：`parallel-harness`
- 位置：`plugins/parallel-harness`
- 发布路径：`dist/parallel-harness`
- 市场归属：`lorainwings-plugins`

首个可用版本定义：

- 能做任务图拆解
- 能做基础并行调度
- 能做文件所有权约束
- 能做至少 2 类 verifier
- 能形成基础可观测性

## 2. 产品分期

### Phase 0：建桩期

目标：

- 建立插件骨架
- 明确运行时主入口
- 明确 skills、runtime、gui、tests、docs 的骨架

交付件：

- `plugins/parallel-harness/.claude-plugin/plugin.json`
- `plugins/parallel-harness/README.md`
- `plugins/parallel-harness/README.zh.md`
- `plugins/parallel-harness/runtime/`
- `plugins/parallel-harness/skills/`
- `plugins/parallel-harness/tests/`

完成标准：

- 插件目录可构建
- 最小 install 路径可预备接入市场

### Phase 1：任务图 MVP

目标：

- 让插件先具备“理解复杂任务并拆图”的能力

交付件：

- `intent-analyzer`
- `task-graph-builder`
- `complexity-scorer`
- `ownership-planner`

完成标准：

- 输入一段需求，可输出结构化 task graph JSON

### Phase 2：调度 MVP

目标：

- 让插件可以并行执行无冲突任务

交付件：

- `scheduler`
- `worker-dispatch`
- `merge-guard`
- `retry-manager`

完成标准：

- 能并发调度多个 worker
- 能限制路径越界
- 能对失败任务局部重试

### Phase 3：验证 MVP

目标：

- 让“实现”和“验证”分离

交付件：

- `test-verifier`
- `review-verifier`
- `result-synthesizer`

完成标准：

- 每个任务完成后至少经过一类独立 verifier
- 汇总形成质量报告

### Phase 4：模型路由与成本控制

目标：

- 引入真正的平台级成本控制

交付件：

- `model-router`
- `budget-policy`
- `escalation-policy`

完成标准：

- 不同任务能自动选择不同 tier
- 失败时能自动升级模型策略

### Phase 5：可观测性与 GUI

目标：

- 让平台具备控制面

交付件：

- `observability-server`
- `event-bus`
- GUI 的 task graph、worker、verifier、cost 面板

完成标准：

- 能可视化执行批次、失败点、成本与状态

### Phase 6：CI / PR 闭环

目标：

- 接通工程闭环

交付件：

- `pr-review-agent`
- `ci-failure-analyzer`
- `autofix-dispatch`
- `coverage-gap-agent`

完成标准：

- 能接收 PR / CI 事件并返回结构化建议或修复结果

## 3. 模块 Backlog

## 3.1 插件骨架

### BH-001 初始化插件目录

目标：

- 创建 `plugins/parallel-harness` 目录骨架

文件：

- `.claude-plugin/plugin.json`
- `README.md`
- `README.zh.md`
- `docs/`
- `runtime/`
- `skills/`
- `tests/`
- `tools/`

验收：

- 目录结构符合设计文档

### BH-002 增加市场注册占位

目标：

- 为后续市场接入准备第二个插件条目

文件：

- `.claude-plugin/marketplace.json`

注意：

- 只有当 `dist/parallel-harness` 构建链路存在时才正式接入

验收：

- 市场文档准备完成

## 3.2 任务图模块

### PH-101 定义 task graph schema

目标：

- 给调度核心建立统一数据结构

输出 schema 字段：

- `graph_id`
- `tasks`
- `edges`
- `critical_path`
- `metadata`

任务字段：

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

验收：

- 形成 JSON Schema 文档

### PH-102 实现 intent analyzer

目标：

- 从用户目标中提取任务意图和工作域

输出：

- work domains
- change scope
- risk estimation

验收：

- 对同类输入输出稳定结构

### PH-103 实现 task graph builder

目标：

- 从意图分析结果构建任务 DAG

验收：

- 小型任务能正确拆图
- 依赖关系无环

### PH-104 实现 complexity scorer

目标：

- 给任务分配复杂度和执行风险

复杂度维度：

- 文件数量
- 涉及模块数
- 是否包含 schema / infra / critical logic

验收：

- 输出复杂度等级与解释

### PH-105 实现 ownership planner

目标：

- 为每个任务生成最小文件所有权边界

验收：

- 对不同任务能输出不重叠或最小重叠路径集合

## 3.3 调度模块

### PH-201 实现 scheduler MVP

目标：

- 基于 DAG 和复杂度进行批次调度

策略：

- 优先调度无依赖节点
- 限制高风险任务并发
- 优先处理关键路径阻塞节点

验收：

- 输出执行批次

### PH-202 实现 worker dispatch

目标：

- 将任务合同派发给 worker

输入：

- task contract
- context pack
- model tier

输出：

- worker result
- artifact summary

验收：

- worker 接口可重复调用

### PH-203 实现 merge guard

目标：

- 合并前检查越界和冲突

检查项：

- allowed path violation
- overlapping write paths
- interface conflict risk

验收：

- 越界任务会被拦截

### PH-204 实现 retry manager

目标：

- 对局部失败任务做重试

策略：

- 限制最大重试次数
- 重试前可升级模型 tier
- 重试前压缩上下文

验收：

- 局部失败不触发全局回滚

### PH-205 实现 downgrade manager

目标：

- 当并行风险过高时自动降级

触发条件：

- 冲突率过高
- verifier 连续失败
- 关键路径任务阻塞严重

验收：

- 系统可从并行自动降级为串行或半串行

## 3.4 上下文包模块

### PH-301 定义 context pack schema

字段：

- `task_summary`
- `relevant_files`
- `relevant_snippets`
- `constraints`
- `test_requirements`
- `budget`

### PH-302 实现 context packager

目标：

- 只打包任务所需最小上下文

规则：

- 默认不注入全仓
- 默认不注入无关 transcript
- 超预算自动摘要

验收：

- 平均上下文大小可控

## 3.5 模型路由模块

### PH-401 定义 tier 策略

层级：

- `tier-1`
- `tier-2`
- `tier-3`

字段：

- `max_context_budget`
- `max_retry`
- `task_types`

### PH-402 实现 model router

输入：

- task complexity
- risk level
- token budget
- retry history

输出：

- model tier
- budget policy

### PH-403 实现 escalation policy

目标：

- 失败后自动升级策略

策略：

- `tier-1 -> tier-2`
- `tier-2 -> tier-3`

## 3.6 Verifier 模块

### PH-501 实现 test verifier

目标：

- 检查测试是否存在、是否通过、是否覆盖关键路径

### PH-502 实现 review verifier

目标：

- 检查实现是否满足任务目标和边界

### PH-503 实现 security verifier

目标：

- 扫描敏感模式、危险操作和配置风险

### PH-504 实现 perf verifier

目标：

- 对关键性能任务做回归检查

### PH-505 实现 result synthesizer

目标：

- 汇总多 verifier 结论，形成统一结果

结果类型：

- pass
- retry
- downgrade
- block

## 3.7 可观测性模块

### PH-601 实现 event bus

事件类型：

- `graph_created`
- `task_ready`
- `task_dispatched`
- `task_completed`
- `task_failed`
- `verification_passed`
- `verification_blocked`
- `downgrade_triggered`
- `model_escalated`

### PH-602 实现 observability server

目标：

- 提供 API 和 WS 实时状态输出

### PH-603 实现 metrics collector

指标：

- total_tasks
- active_workers
- retry_count
- downgrade_count
- model_tier_distribution
- token_cost
- verifier_fail_rate

## 3.8 GUI 模块

### PH-701 Task Graph View

### PH-702 Worker Pool View

### PH-703 Verification View

### PH-704 Cost View

验收总目标：

- 用户能看懂系统现在在并行做什么

## 3.9 CI / PR 模块

### PH-801 PR review agent

### PH-802 CI failure analyzer

### PH-803 autofix dispatch

### PH-804 coverage gap agent

验收总目标：

- 平台能进入实际工程流水线

## 4. 测试 Backlog

### T-001 schema tests

- task graph schema
- context pack schema
- verifier result schema

### T-002 scheduling tests

- DAG batch correctness
- conflict downgrade
- retry behavior

### T-003 ownership tests

- allowed path enforcement
- forbidden path block

### T-004 model routing tests

- complexity to tier mapping
- escalation behavior

### T-005 verifier tests

- verifier result aggregation
- block / retry / pass semantics

### T-006 observability tests

- event stream correctness
- snapshot consistency

### T-007 e2e tests

- 多模块并行任务
- verifier 阻断再重试
- 自动降级

## 5. 文档 Backlog

### D-001 插件 README

- 定位
- 适用场景
- 与 `spec-autopilot` 的区别

### D-002 架构文档

- DAG
- ownership
- verifier
- model router

### D-003 市场文档

- 何时选 `spec-autopilot`
- 何时选 `parallel-harness`

## 6. 市场接入 Backlog

### M-001 准备 `dist/parallel-harness`

### M-002 为新插件准备 build 脚本

### M-003 更新根市场配置

最终目标：

```json
{
  "plugins": [
    {
      "name": "spec-autopilot",
      "source": "./dist/spec-autopilot"
    },
    {
      "name": "parallel-harness",
      "source": "./dist/parallel-harness"
    }
  ]
}
```

## 7. Sprint 建议

### Sprint A

- BH-001
- PH-101
- PH-102
- PH-103
- PH-104
- PH-105

### Sprint B

- PH-201
- PH-202
- PH-203
- PH-301
- PH-302

### Sprint C

- PH-204
- PH-205
- PH-401
- PH-402
- PH-403

### Sprint D

- PH-501
- PH-502
- PH-505
- PH-601
- PH-602

### Sprint E

- PH-603
- PH-701
- PH-702
- PH-703
- PH-704

### Sprint F

- PH-801
- PH-802
- PH-803
- PH-804
- M-001
- M-002
- M-003

## 8. 最终结论

这份 backlog 的目的不是让你一次性做完所有模块，而是把 `parallel-harness` 从“一个好想法”变成“可以按 Sprint 直接推进的新插件产品”。

你现在最稳的路线是：

1. 先修 `spec-autopilot`
2. 同时启动 `parallel-harness` 骨架与任务图 MVP
3. 等新插件具备最小可用能力后，再正式接入插件市场

这样你会得到一个真正可扩展的插件矩阵，而不是一个越来越重的单插件。
