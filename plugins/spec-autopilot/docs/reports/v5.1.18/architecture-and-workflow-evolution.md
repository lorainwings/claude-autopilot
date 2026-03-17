# 全局架构演进与 Vibe Workflow 融合指南

> 汇总日期: 2026-03-17
> 汇总输入:
> - `docs/reports/stability-audit.md`
> - `docs/reports/phase1-benchmark.md`
> - `docs/reports/phase5-codegen-audit.md`
> - `docs/reports/phase6-tdd-audit.md`
> - `docs/reports/performance-benchmark.md`
> - `docs/reports/competitive-analysis.md`

## 执行摘要

spec-autopilot 已经具备一个非常清晰的内核: **状态机 + 三层门禁 + checkpoint 恢复 + 并行文件所有权 + 事件总线**。这套内核不该被重写，真正需要做的是把几个“静默断点”和“观测盲区”补平，并把底层编排能力抽象成更稳定的工作流 API，供未来 Vibe Workflow GUI 直接消费。

本次综合后，建议按两个主轴推进:

1. **先补内核断点**: 根目录解析、阶段快照/进度、构建分发、并行 TDD 证明链。
2. **再做上层解耦**: 事件 schema、只读状态查询、可回放 artifact、旁路 reviewer workers、Repo Map 索引。

## 一、当前最关键的架构问题

### 1. 静默成功但未落盘

问题:

- `save-phase-context.sh`
- `write-phase-progress.sh`

都可能在当前仓库布局下直接 `exit 0`，但什么都没写。

这类问题危险性高于普通失败，因为它会让:

- 崩溃恢复变粗
- GUI 观测变稀
- 审计以为“有机制”，实际上“没证据”

### 2. 构建链路不是降级，而是首选路径直接失败

`build-dist.sh` 当前首选 GUI 构建失败，只有回退到已提交 `gui-dist/` 才能工作。这说明发布架构还没有把“工具链差异”和“运行时兼容性”隔离好。

### 3. 并行 TDD 仍有证明空洞

串行 TDD 很强，但并行 TDD 仍主要依赖 `tdd_cycles` 自报，主线程只能做最终全量测试。对于高价值项目，这仍然不够。

### 4. 上下文工程还是“文档流”，不是“索引流”

Phase 1/5/6 已经有丰富的 Steering Documents，但大仓库场景下还缺少:

- 函数/模块索引
- 复用候选映射
- 影响范围图

这会限制代码生成质量与性能。

## 二、代码级重构方案

### 方案 A: 统一 Project Root Resolver

目标:

- 所有脚本不再直接各自 `git rev-parse --show-toplevel`
- 统一改为共享函数，例如 `resolve_project_root()`

设计要求:

- 优先显式环境变量
- 其次识别 `openspec/changes`
- 兼容“插件目录在 monorepo 子目录”的布局
- 找不到时显式 warning，不允许静默成功

收益:

- 一次修复 `phase-context`、`phase-progress`、未来其他脚本的同类问题

### 方案 B: 引入 `phase-state` 聚合写入器

目标:

- 把 `phase-context-snapshots`、`phase-progress`、checkpoint 附加字段写入收口到统一写入模块

设计要求:

- 原子写
- 标准 schema
- 统一错误处理
- 统一事件发射

收益:

- 避免多个脚本各自维护路径与格式
- GUI/恢复逻辑只需要消费一个稳定接口

### 方案 C: 构建链路分层

目标:

- `build-dist.sh` 不再把 GUI 构建失败直接放大为整包失败

设计要求:

- 显式检测 Bun/Vite/Node 兼容矩阵
- 构建失败时自动回退到已验证 `gui-dist/`
- 报告中标记“使用回退产物”，而不是无声替代

收益:

- 发布成功率提升
- 性能问题与可用性问题解耦

### 方案 D: 并行 TDD 证据增强

目标:

- 把并行 TDD 从“最终通过”提升到“过程可证明”

做法:

- 域 worker 必须回传 RED 失败样本摘要
- 主线程对抽样 task 做二次验证
- 对关键任务支持强制串行 TDD lane

收益:

- 保留并行收益
- 显著降低 `tdd_cycles` 纯自报的信任面

## 三、Vibe Workflow 解耦方案

### 1. 标准化 Workflow API

建议新增三类稳定接口:

- `workflow.snapshot()`
  - 返回当前 phase、mode、gate 状态、active workers、最近事件
- `workflow.timeline()`
  - 返回按 phase/task 整理后的事件流
- `workflow.artifacts()`
  - 返回 checkpoint、报告、回放包、构建产物索引

这些接口应建立在现有事件总线和 checkpoint 之上，而不是另起一套状态源。

### 2. Status Listeners / Event Hooks

现有 `events.jsonl` 已接近工作流事件总线，下一步应做的是稳定 schema，而不是增加新概念。

建议固定以下事件族:

- `workflow_state_changed`
- `phase_progress_changed`
- `gate_decision_requested`
- `gate_decision_resolved`
- `worker_started`
- `worker_completed`
- `artifact_published`

这样 GUI 才能做:

- 时间线
- 看板
- 回放
- 异常告警

而不必深入理解脚本实现细节。

### 3. Replay Artifact

建议把下面内容打包成可回放对象:

- `events.jsonl`
- phase 摘要
- gate 决策
- worker 摘要
- 关键报告索引

这会同时服务:

- GUI 回放
- 故障排查
- 团队协作
- 审计留痕

### 4. Repo Map 作为 Vibe Workflow 的“上下文底座”

GUI 若要显示“为什么这个 worker 被派到这些文件”，仅靠文本摘要不够。需要一个轻量 Repo Map 作为底座，供:

- 影响范围高亮
- 复用建议
- 并行任务冲突预判
- 代码审阅导航

## 四、建议实施顺序

### 第 1 周

- 修复 Project Root Resolver
- 修复 `save-phase-context.sh`
- 修复 `write-phase-progress.sh`

### 第 2 周

- 重构 `build-dist.sh` 为“首选构建 + 显式回退”
- 加入构建兼容性自检

### 第 3 周

- 为并行 TDD 增加过程证据
- 为 Phase 6 增加更强的 suite 级报告要求

### 第 4 周

- 抽象 Workflow API
- 输出 Replay Artifact
- 引入轻量 Repo Map

## 五、最终判断

spec-autopilot 当前最该做的不是“继续加规则”，而是:

- 把已经设计好的规则真正变成稳定证据
- 把已经存在的事件和 checkpoint 变成标准化 API
- 把 GUI 从“看日志”升级为“消费工作流状态”

一旦这三点完成，它就不只是一个严格的 Claude Code 插件，而会成为一个能支撑现代 Vibe Workflow GUI 的底层编排引擎。
