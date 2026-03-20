# 新并行 AI 平台插件设计方案

> 日期：2026-03-19
> 目标：基于当前仓库和插件市场，新开发一个独立插件，构建真正的并行 AI 平台。
> 核心原则：新平台插件独立演进，不重构替代 `spec-autopilot`；两者共同发布到同一个插件市场。

## 1. 文档目标

本文档定义一个全新的插件产品线，暂定名：

- `parallel-harness`

命名含义：

- `parallel`：突出并行调度能力
- `harness`：突出工程控制面、验证闭环、质量约束

此插件不是 `spec-autopilot vNext`，而是新的产品：

- `spec-autopilot`：规范驱动交付编排
- `parallel-harness`：通用并行 AI 工程平台

## 2. 产品定位

### 2.1 产品定义

`parallel-harness` 是一个 Claude Code 插件，提供：

- 任务图拆解
- 多 Agent 并行调度
- 文件所有权隔离
- 成本感知模型路由
- 验证 swarm
- 质量门禁
- CI / PR 闭环
- 可观测性控制面

它不只是工作流包，而是一个“AI 软件工程控制面插件”。

### 2.2 目标用户

- 多模块、多文件、多任务的真实软件工程项目
- 需要通过多 Agent 提升开发吞吐的团队
- 希望兼顾速度、质量和成本控制的高级用户
- 需要把 AI 工作纳入工程治理的团队

### 2.3 核心价值

相比单线程 autopilot 类插件，它提供：

- 更高的并行度
- 更明确的任务边界
- 更严格的结果验证
- 更低的上下文浪费
- 更强的 CI/PR 集成

## 3. 为什么必须独立做新插件

原因不是“当前插件不好”，而是产品边界已经不同。

### 3.1 `spec-autopilot` 的主问题

`spec-autopilot` 的价值在于：

- 8 阶段交付流程
- 三层门禁
- checkpoint 与恢复
- 规范驱动

它更像：

- 交付编排产品

### 3.2 新插件的主问题域

`parallel-harness` 要解决的是：

- 怎么拆任务
- 怎么并行执行
- 怎么控制上下文
- 怎么控制质量
- 怎么控制成本
- 怎么接入 PR/CI

它更像：

- AI 工程平台

因此不适合把这套能力强塞进 `spec-autopilot`。

## 4. 产品能力矩阵

### 4.1 第一层：任务理解与图建模

新插件的第一能力不是直接开 agent，而是先建图。

模块：

- `intent-analyzer`
- `task-graph-builder`
- `complexity-scorer`
- `ownership-planner`

输出：

- 任务 DAG
- 每个任务的目标、依赖、输入、输出、风险等级
- 每个任务的文件所有权候选范围

### 4.2 第二层：调度与执行

模块：

- `scheduler`
- `worker-dispatch`
- `retry-manager`
- `downgrade-manager`

能力：

- 并行执行无依赖任务
- 限流并发 worker 数
- 当冲突或失败率高时自动降级串行
- 对失败任务局部重试而非整体回滚

### 4.3 第三层：模型路由

模块：

- `model-router`
- `cost-controller`
- `escalation-policy`

能力：

- 简单重写、grep、格式化任务用低成本模型
- 规划、设计、复杂 review 用高能力模型
- 连续失败时自动升级模型
- 根据 token 预算动态限制上下文大小

### 4.4 第四层：验证 swarm

模块：

- `test-verifier`
- `review-verifier`
- `security-verifier`
- `perf-verifier`
- `coverage-verifier`

能力：

- 实现 agent 与验证 agent 隔离
- 多类验证并行执行
- 聚合为统一质量报告

### 4.5 第五层：工程控制面

模块：

- `event-bus`
- `observability-server`
- `session-state`
- `reporting`

能力：

- 实时展示任务图执行情况
- 展示 agent 占用、模型成本、失败重试、验证结果
- 输出 session 级工程报告

## 5. 核心架构设计

### 5.1 总体架构

```text
User Intent
  -> Planner
  -> Task Graph Builder
  -> Ownership Planner
  -> Scheduler
  -> Worker Agents
  -> Merge Guard
  -> Verifier Swarm
  -> Result Synthesizer
  -> Report / PR / CI feedback
```

### 5.2 控制流

1. 用户给出需求或目标
2. 系统做意图分析
3. 生成任务图与依赖关系
4. 生成文件所有权和上下文包
5. 调度器决定并发批次
6. worker 并行执行
7. merge guard 检查冲突和越界
8. verifier swarm 并行验证
9. synthesize 汇总结果
10. 成功则结束，失败则局部重试或降级

### 5.3 最小上下文包设计

并行效率的关键不是更多 agent，而是更小上下文。

每个 worker 只收到：

- 任务合同
- 明确输入输出
- 文件所有权
- 最小相关代码片段
- 相关测试要求
- 不超过预算的上下文摘要

任务合同示例字段：

- `task_id`
- `goal`
- `dependencies`
- `allowed_paths`
- `forbidden_paths`
- `acceptance_criteria`
- `test_requirements`
- `preferred_model_tier`
- `retry_policy`

## 6. 插件目录与代码结构设计

建议新增插件目录：

```text
plugins/parallel-harness/
  .claude-plugin/
  README.md
  README.zh.md
  docs/
  gui/
  hooks/
  runtime/
    scheduler/
    orchestrator/
    verifiers/
    observability/
    models/
    session/
    scripts/
  skills/
    harness/
    harness-plan/
    harness-dispatch/
    harness-verify/
    harness-recovery/
  tests/
    unit/
    integration/
    e2e/
  tools/
```

运行时结构：

```text
runtime/
  orchestrator/
    planner.ts
    task-graph.ts
    ownership.ts
  scheduler/
    scheduler.ts
    retry-manager.ts
    downgrade-manager.ts
  models/
    model-router.ts
    budget-policy.ts
  verifiers/
    review-verifier.ts
    test-verifier.ts
    security-verifier.ts
    perf-verifier.ts
  observability/
    server.ts
    event-bus.ts
    metrics.ts
  session/
    state-store.ts
    context-packager.ts
  scripts/
    emit-event.sh
    collect-metrics.sh
    validate-contract.sh
```

## 7. 新插件的功能设计

### 7.1 功能一：任务图驱动调度

不同于 `spec-autopilot` 的 phase 流程，新插件以 DAG 为核心。

要点：

- 任务不是按 phase 固定前进
- 任务按依赖满足情况动态激活
- 任务可以拆成多轮并行批次

调度策略：

- 优先执行关键路径上的阻塞任务
- 对低冲突任务优先并行
- 对高风险任务要求 verifier 提前介入

### 7.2 功能二：文件所有权与冲突预防

每个 worker 执行前必须拿到 `allowed_paths`。

系统在调度时做三类校验：

- 路径重叠检查
- 接口依赖检查
- merge 风险评分

当冲突风险高时：

- 自动拆分更细任务
- 或直接降级为串行执行

### 7.3 功能三：模型路由与成本控制

模型路由应是平台一级能力，而不是脚本补丁。

建议采用三级模型层：

- `tier-1`：低成本执行模型
- `tier-2`：中成本通用模型
- `tier-3`：高能力规划/审查模型

路由输入：

- 任务复杂度
- 代码面大小
- 风险等级
- token 预算
- 历史失败率

路由输出：

- 推荐模型 tier
- 上下文预算
- 最大重试次数

### 7.4 功能四：Verifier Swarm

新平台必须避免“自己实现、自己裁判”。

并行验证器：

- `test-verifier`
  - 检查测试是否补齐
  - 检查失败日志

- `review-verifier`
  - 检查实现偏差
  - 检查设计一致性

- `security-verifier`
  - 扫描敏感模式和依赖风险

- `perf-verifier`
  - 对关键路径做性能回归检查

- `coverage-verifier`
  - 检查变更覆盖率与断言质量

### 7.5 功能五：CI / PR 闭环

平台必须能走到工程闭环，而不是只停留在本地交互。

能力：

- PR 创建后自动 review
- CI 失败后自动分析并尝试修复
- 输出质量报告
- 生成变更摘要和风险摘要

## 8. GUI 与可观测性设计

新插件的 GUI 不应再只是事件流面板，而应是任务控制面。

建议四大视图：

- Task Graph View
- Worker Pool View
- Verification View
- Cost & Context View

### 8.1 Task Graph View

展示：

- DAG 任务节点
- 当前依赖状态
- 关键路径
- 重试状态

### 8.2 Worker Pool View

展示：

- 当前活跃 worker
- 所有权范围
- 当前模型 tier
- 任务耗时

### 8.3 Verification View

展示：

- review/test/security/perf 状态
- 哪个 verifier 阻断了合并
- 可操作的修复建议

### 8.4 Cost & Context View

展示：

- token 使用量
- 模型 tier 切换轨迹
- 上下文包大小
- 降级与升级历史

## 9. 与当前插件市场的关系

### 9.1 市场策略

当前市场 [marketplace.json](.claude-plugin/marketplace.json) 已经承载 `spec-autopilot`。

后续应统一变成多插件市场：

```json
{
  "name": "lorainwings-plugins",
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

### 9.2 市场定位

- `spec-autopilot`
  - 面向规范驱动、流程明确、阶段式交付

- `parallel-harness`
  - 面向复杂工程、多 Agent 并行、治理优先

两者不是替代关系，而是产品分层关系。

### 9.3 安装方式

用户可以按项目特征选择安装：

```bash
claude plugin install spec-autopilot@lorainwings-plugins --scope project
claude plugin install parallel-harness@lorainwings-plugins --scope project
```

未来也可支持同项目共存，但默认建议二选一。

## 10. 版本与发布策略

### 10.1 版本策略

- `spec-autopilot` 继续沿用现有版本线
- `parallel-harness` 从 `0.1.0` 或 `1.0.0-beta.1` 起步

### 10.2 发布节奏

建议三阶段：

- Alpha
  - 本地并行调度可跑通
  - 核心 verifier 可用

- Beta
  - 模型路由可用
  - GUI 基本可观测
  - CI/PR 初步接通

- GA
  - 调度降级成熟
  - 成本控制成熟
  - 市场文档、示例、测试体系完善

## 11. 实施路线图

### Phase 0：产品建桩

周期：1 到 2 周

交付：

- 插件目录骨架
- `.claude-plugin/plugin.json`
- 基础 README
- 最小运行时入口
- 市场注册占位

### Phase 1：任务图与调度 MVP

周期：3 到 4 周

交付：

- intent analyzer
- task graph builder
- scheduler MVP
- 文件所有权 enforcement
- 基础 worker dispatch

验收：

- 能在小型多模块仓库中完成并行任务

### Phase 2：验证与可观测性

周期：3 周

交付：

- verifier swarm 第一版
- observability server
- GUI task graph 视图
- 基础 cost metrics

验收：

- 能展示执行状态和验证阻断原因

### Phase 3：模型路由与 CI/PR 闭环

周期：3 到 5 周

交付：

- model router
- escalation policy
- PR review integration
- CI autofix loop

验收：

- 平台具备真正的工程闭环能力

## 12. 风险与规避

### 风险一：新插件和旧插件职责混淆

规避：

- 市场说明、README、文档明确分工
- 不把 `parallel-harness` 的能力回灌进 `spec-autopilot`

### 风险二：过早追求全能平台导致首版过重

规避：

- 先做 DAG + ownership + verifier MVP
- 模型路由和 CI 闭环分阶段进入

### 风险三：并行度高但质量下降

规避：

- verifier 独立于 worker
- 默认启用 merge guard
- 失败自动降级

## 13. 最终结论

你现在最合理的产品策略不是把 `spec-autopilot` 强行重构成新平台，而是双线并行：

- 一条线修好并稳住 `spec-autopilot`
- 一条线独立孵化 `parallel-harness`
- 两者统一进入 `lorainwings-plugins` 市场

这样做的收益最大：

- 现有用户不被打断
- 新平台不被旧架构拖累
- 市场层形成插件矩阵，而不是单产品赌注

这是当前仓库最专业、也最现实的产品与工程路径。
