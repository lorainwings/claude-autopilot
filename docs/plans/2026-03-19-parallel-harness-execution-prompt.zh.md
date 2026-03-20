# parallel-harness 完整执行提示词

> 日期：2026-03-19
> 目的：这是一份可直接交给 Claude 的完整执行提示词，用于新建 `parallel-harness` 插件。
> 使用方式：直接复制 `## 最终提示词` 下的全部内容，原样交给 Claude。
> 执行要求：按全量完成标准执行，不接受只建骨架、只做 schema、只写文档或只做 MVP 占位。

## 背景说明

当前仓库是一个插件市场仓库，而不是单插件仓库：

- 市场名称：`lorainwings-plugins`
- 当前已有插件：`spec-autopilot`
- 目标新插件：`parallel-harness`

新插件的定位必须明确：

- 它不是 `spec-autopilot vNext`
- 它不是对现有插件的硬重构
- 它是一个全新插件
- 它要与 `spec-autopilot` 共存
- 它最终要进入同一个插件市场

## 新插件的目标定位

`parallel-harness` 的定位是：

- 真正的并行 AI 平台
- AI 软件工程控制面插件
- task-graph-first
- model-routing-aware
- verifier-driven
- CI/PR ready

它要解决的是：

- 如何拆任务
- 如何并行调度
- 如何控制上下文
- 如何约束文件边界
- 如何验证质量
- 如何控制模型成本
- 如何把 AI 工作接入工程闭环

## 为什么必须独立做新插件

当前 `spec-autopilot` 更适合继续承担：

- 规范驱动交付编排
- 8 阶段工作流
- 三层门禁
- recovery 与 dashboard

而 `parallel-harness` 要承接的是完全不同的平台问题域：

- 通用任务图
- 多 Agent 并行调度
- verifier swarm
- 模型路由
- CI/PR 闭环

因此不能把这些能力继续塞进 `spec-autopilot`。

## 你必须参考的本地文档

在开始实现前，你必须阅读并遵循这些文档：

- [总调研报告](docs/plans/2026-03-19-holistic-architecture-research-report.zh.md)
- [新并行 AI 平台插件设计方案](docs/plans/2026-03-19-parallel-ai-platform-plugin-design.zh.md)
- [竞品能力复用矩阵](docs/plans/2026-03-19-competitive-capability-reuse-matrix.zh.md)
- [parallel-harness 实施 Backlog](docs/plans/2026-03-19-parallel-harness-execution-backlog.zh.md)

## 竞品上下文与必须落地的能力

本次新插件不能只做概念设计，必须把竞品能力转化为可落地模块。

### 来自 `superpowers`

要吸收：

- methodology-as-code
- capability 清单化
- 低摩擦能力入口

但不能照搬其弱点：

- 不能只做方法包装，不做运行时约束

### 来自 `claude-code-switch`

要吸收：

- tier 化模型策略
- 模型切换显式化

必须增强：

- 不能只做手工切换
- 必须做任务级自动模型路由

### 来自 `oh-my-claudecode`

要吸收：

- 多 Agent 协作方向

必须增强：

- 不能只多 agent
- 必须 task-graph-first
- 必须 ownership-first

### 来自 `everything-claude-code`

要吸收：

- skills / hooks / runtime / docs/capabilities 的资产化组织

必须增强：

- 不能大而全失控
- 必须清晰插件边界和能力边界

### 来自 `BMAD-METHOD`

要吸收：

- 角色工程化
- workflow 模块化

必须增强：

- planner / worker / verifier / synthesizer 必须落成 contract，而不只是文档角色

### 来自 `claude-task-master`

要吸收：

- task graph
- dependency awareness
- complexity scoring

必须增强：

- 任务系统必须与 ownership / verifier / model router 联动

### 来自 `get-shit-done`

要吸收：

- 最小上下文包
- 低摩擦推进

必须增强：

- 不能只快不稳
- 必须接 verifier 和 metrics

### 来自 Harness

要吸收：

- review / autofix / coverage / CI/PR integration 架构

必须增强：

- 不能只做表层 review
- 必须为 task history、verifier history、risk summary 预留接入位

## 你必须实现的完整范围

本轮目标不是只做空骨架或概念性 MVP，而是尽可能完整交付第一版可运行平台。

## 全量完成原则

本次提示词要求 Claude 尽量按全量完成执行：

1. 不能只建目录不实现核心模块。
2. 不能只写 schema 不实现最小可运行逻辑。
3. 不能只写 README 和设计文档。
4. 不能只完成 task graph 而不做 ownership、model router、verifier、tests。
5. 不能把市场接入准备全部留到下一轮，至少要推进到清晰可判断是否可接入的程度。

如果遇到客观阻塞，必须明确说明，但默认目标是把本文档列出的范围尽可能一次性完整落地。

## 必须完成的事项

### A. 创建独立插件骨架

你必须直接创建：

```text
plugins/parallel-harness/
  .claude-plugin/
  docs/
  runtime/
  skills/
  tests/
  tools/
  README.md
  README.zh.md
```

并补齐：

- `plugin.json`
- 插件定位说明
- 与 `spec-autopilot` 的区别说明
- 最小安装与使用说明

### B. 实现最小平台核心

必须实现以下核心骨架和首版可运行实现：

1. task graph schema
2. intent analyzer
3. task graph builder
4. complexity scorer
5. ownership planner
6. context pack schema
7. context packager
8. scheduler MVP 最小接口
9. model router 的最小 tier 策略
10. verifier result schema

必须保证：

- 所有核心模块有清晰输入输出
- 先立 contract / schema，再立执行器

### C. 角色 contract 化

必须定义四类一等角色：

1. planner
2. worker
3. verifier
4. synthesizer

每类角色必须具备：

- 输入 contract
- 输出 contract
- 失败语义
- 可访问资源边界

### D. 任务图优先

平台必须是 task-graph-first。

你必须定义任务节点至少包含：

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

### E. ownership 与冲突控制

你必须建立 ownership planner 的最小实现，至少支持：

- 为任务分配 `allowed_paths`
- 为任务分配 `forbidden_paths`
- 为后续 merge guard 预留冲突检测接口

### F. model router 最小实现

你必须定义 tier：

- `tier-1`
- `tier-2`
- `tier-3`

至少提供路由规则骨架：

- search / format / low-risk refactor -> `tier-1`
- implementation / general review -> `tier-2`
- planning / design / critical review -> `tier-3`

### G. verifier 架构预留

即使本轮不做全 verifier swarm，也必须为以下 verifier 建好接口，并至少落地其中一部分可运行实现：

- test verifier
- review verifier
- security verifier
- perf verifier

至少先实现：

- verifier result schema
- review verifier 或 test verifier 的最小可运行版本
- result synthesizer 的接口骨架

### H. 测试与文档

至少补齐：

- schema tests
- task graph builder tests
- ownership planner tests
- model router tests
- context packager tests

同时补齐：

- 插件 README
- 架构概览
- MVP 范围说明
- 与现有插件市场的关系说明

### I. 插件市场接入准备

最终目标是进入：

- [marketplace.json](.claude-plugin/marketplace.json)

但本轮规则是：

- 如果 `parallel-harness` 已具备最小可构建结构，则准备市场接入
- 如果仍未达到可安装状态，就不要强行半成品注册
- 至少要把市场接入的下一步清晰准备好
- 不允许完全跳过市场接入评估

## 实施原则

### 必须遵守

1. 直接创建实际插件骨架和核心文件。
2. 不要只写设计文档。
3. 尽量与仓库现有风格兼容。
4. 小步推进，每一块完成后做最小验证。
5. 不要破坏现有 `spec-autopilot`。
6. 不要把新平台能力塞回旧插件。

### 不要做的事情

1. 不要只建空目录不落 contract。
2. 不要只抄竞品描述，不做实际模块化实现。
3. 不要一开始追求全功能 GUI 和全功能 CI。
4. 不要改动旧插件来承接新平台。

## 建议实施顺序

### 第一阶段：建桩

先完成：

- 目录骨架
- plugin.json
- README
- runtime / skills / tests / docs 基本结构

### 第二阶段：核心 schema 与 contract

先做：

- task graph schema
- context pack schema
- verifier result schema
- 角色 contract

### 第三阶段：核心模块 MVP

再做：

- intent analyzer
- task graph builder
- complexity scorer
- ownership planner
- context packager
- scheduler 最小接口
- model router 最小实现

### 第四阶段：最小 verifier 与 tests

然后做：

- 至少一个 verifier
- 对应 tests

### 第五阶段：市场接入准备

最后判断是否满足接入市场的最低条件。

## 验收标准

至少满足：

1. `plugins/parallel-harness/` 目录已真实存在并具备插件骨架。
2. task graph、ownership、context pack、model router、verifier result 至少有 schema 或首版实现。
3. 至少存在一组可运行的测试。
4. README 和架构说明已能说明该插件定位与用法。
5. 与 `spec-autopilot` 的边界清晰。
6. 已能判断是否具备接入插件市场的最低条件。

## 最终提示词

```text
你现在是这个仓库的新产品线架构师兼实现工程师。请在当前代码库中直接创建一个全新的 Claude Code 插件，不要重构替换现有 `spec-autopilot`，而是新建一个真正的并行 AI 平台插件。

仓库根目录：
.

任务对象：
新插件 `parallel-harness`

产品定位：
`parallel-harness` 是一个新的插件，不是 `spec-autopilot vNext`。它要与 `spec-autopilot` 共存，并最终进入同一个插件市场 `lorainwings-plugins`。它的定位是“真正的并行 AI 平台 / AI 软件工程控制面插件”。

你必须先阅读并遵循以下文档：
1. docs/plans/2026-03-19-holistic-architecture-research-report.zh.md
2. docs/plans/2026-03-19-parallel-ai-platform-plugin-design.zh.md
3. docs/plans/2026-03-19-competitive-capability-reuse-matrix.zh.md
4. docs/plans/2026-03-19-parallel-harness-execution-backlog.zh.md

你必须理解以下完整上下文：

一、为什么必须独立做新插件
1. 现有 `spec-autopilot` 适合继续承担规范驱动交付编排能力。
2. 新平台要解决的是 task graph、并行调度、ownership、model routing、verifier swarm、CI/PR integration 等完全不同的问题域。
3. 因此不能把新平台能力继续塞进 `spec-autopilot`，必须独立新建插件。

二、新插件的目标定位
`parallel-harness` 必须具备以下方向：
1. task-graph-first
2. ownership-first
3. model-routing-aware
4. verifier-driven
5. CI/PR ready

三、竞品能力必须如何落地
1. 来自 `superpowers`：
   - 吸收 methodology-as-code、capability 清单化、低摩擦能力入口
   - 但不能只做方法包装，必须绑定 runtime contract
2. 来自 `claude-code-switch`：
   - 吸收 tier 化模型策略
   - 但不能只做手工切换，必须提供自动模型路由基础
3. 来自 `oh-my-claudecode`：
   - 吸收多 Agent 协作方向
   - 但必须 task-graph-first，不能只堆 agent
4. 来自 `everything-claude-code`：
   - 吸收 skills / hooks / runtime / docs/capabilities 的资产化组织
   - 但不能大而全失控
5. 来自 `BMAD-METHOD`：
   - 吸收 planner / worker / verifier / synthesizer 四类角色方法
   - 但必须落实为 contract，而不只是文档角色
6. 来自 `claude-task-master`：
   - 吸收 task graph、dependency、complexity
   - 但必须与 ownership / verifier / model router 联动
7. 来自 `get-shit-done`：
   - 吸收最小上下文包
   - 但必须接 verifier 和 metrics
8. 来自 Harness：
   - 吸收 verifier / CI / PR 闭环架构
   - 但本轮先做接口和结构预留，不必一次性全部实现

四、本轮必须完成的完整事项

A. 创建独立插件骨架
请直接创建：
- `plugins/parallel-harness/.claude-plugin/`
- `plugins/parallel-harness/docs/`
- `plugins/parallel-harness/runtime/`
- `plugins/parallel-harness/skills/`
- `plugins/parallel-harness/tests/`
- `plugins/parallel-harness/tools/`
- `plugins/parallel-harness/README.md`
- `plugins/parallel-harness/README.zh.md`

并补齐：
- `plugin.json`
- 插件定位说明
- 与 `spec-autopilot` 的区别说明
- 最小安装说明

B. 实现最小平台核心
本轮必须实现以下核心骨架及首版可运行实现：
1. task graph schema
2. intent analyzer
3. task graph builder
4. complexity scorer
5. ownership planner
6. context pack schema
7. context packager
8. scheduler MVP 最小接口
9. model router 的最小 tier 策略
10. verifier result schema

要求：
- 先立 contract / schema，再立执行器
- 所有模块都要有清晰输入输出

C. 角色 contract 化
必须定义四类一等角色：
1. planner
2. worker
3. verifier
4. synthesizer

每类角色都要有：
- 输入 contract
- 输出 contract
- 失败语义
- 资源边界

D. task graph-first
任务节点至少包含：
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

E. ownership 与冲突控制
必须建立 ownership planner 的最小实现，支持：
- `allowed_paths`
- `forbidden_paths`
- merge guard 预留接口

F. model router 最小实现
必须定义：
- `tier-1`
- `tier-2`
- `tier-3`

并提供基础路由规则：
- search / format / low-risk refactor -> `tier-1`
- implementation / general review -> `tier-2`
- planning / design / critical review -> `tier-3`

G. verifier 架构预留
即使本轮不做全 verifier swarm，也必须为以下 verifier 建接口：
- test verifier
- review verifier
- security verifier
- perf verifier

至少先实现：
- verifier result schema
- 一个最小 verifier 的可运行实现
- result synthesizer 的接口骨架

H. 测试与文档
至少补齐：
- schema tests
- task graph builder tests
- ownership planner tests
- model router tests
- context packager tests

同时补齐：
- 插件 README
- 架构概览
- MVP 范围说明
- 与现有插件市场的关系说明

I. 插件市场接入准备
最终目标是接入：
- .claude-plugin/marketplace.json

但规则是：
- 如果本轮已具备最小可构建结构，则准备市场接入
- 如果还不够，不要强行半成品注册
- 至少要把市场接入下一步准备清楚
- 不允许完全跳过市场接入评估

五、执行规则
1. 直接创建实际插件骨架和核心文件，不要只写文档。
2. 与仓库现有风格尽量兼容。
3. 小步推进，每一块完成后做最小验证。
4. 不要破坏现有 `spec-autopilot`。
5. 不要把新平台能力塞回旧插件。
6. 不要用“先做 MVP”“后续再补”作为缩减当前范围的默认理由。

六、建议执行顺序
1. 建立插件骨架
2. 建 schema 与 role contracts
3. 建 intent analyzer / task graph builder / complexity scorer / ownership planner
4. 建 context packager / scheduler 最小接口 / model router 最小实现
5. 建一个最小 verifier 和 tests
6. 最后评估是否满足市场接入最低条件

七、最终输出必须包含
1. 你新增了哪些目录和文件
2. 你实现了哪些核心能力
3. 哪些竞品能力已经真正落地
4. 哪些能力目前只完成了接口预留
5. 当前是否具备接入插件市场的最低条件
6. 下一步建议是什么
7. 哪些事项已经全量完成，若确有未完成项，必须说明客观阻塞原因

现在开始直接执行，不要只给计划。
```
