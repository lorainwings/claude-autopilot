# 2026-03-31 parallel-harness 架构、调研与增强文档索引

本目录是基于 `2026-03-31` 当前工作区重新完成的一轮全量分析，目标不是复述旧文档，而是把三类事实重新对齐：

1. 当前 `parallel-harness` 源码到底已经实现了什么。
2. 当前社区与竞品在 harness、agent orchestration、治理和工程交付上的最佳实践是什么。
3. 为了满足“产品设计 -> UI 设计 -> 技术方案 -> 前后端实现 -> 测试 -> 质量保证 -> 专业报告”全流程稳定性，当前项目还缺什么。

建议阅读顺序如下。

## 主文档

1. `01_lifecycle_architecture_design.md`  
   当前实现的 As-Is 架构、生命周期主链、关键模块边界、Mermaid 架构图，以及面向全流程产品开发的目标态架构图。

2. `02_ai_limitations_mitigation_strategy.md`  
   对当前 AI 在上下文压缩、代码生成稳定性、测试覆盖、奖励挟持、需求理解等方面缺陷的调研，以及 harness 级缓解策略。

3. `03_harness_best_practices_and_competitors.md`  
   对 harness 思想、社区最佳实践和主要竞品能力矩阵的调研，含官方资料链接。

4. `04_parallel_harness_implementation_review.md`  
   基于当前源码、测试和文档的实现评审，聚焦问题、不可靠实现和文档偏差。

5. `05_parallel_harness_enhancement_blueprint.md`  
   基于前四篇文档收敛出的修复与增强方案，按 P0 / P1 / P2 路线拆解。

## 本轮本地验证基线

- `cd plugins/parallel-harness && bun test`
  - 结果：`268 pass / 0 fail / 601 expect() calls`
- `cd plugins/parallel-harness && bunx tsc --noEmit`
  - 结果：通过，无输出

## 本轮结论摘要

截至 `2026-03-31`，`parallel-harness` 已经具备：

- graph-first 规划主链
- requirement grounding 接线
- ownership planning + batch scheduling
- attempt 级动态 model routing
- context packing 与 occupancy 记录
- task/run 两级 gate
- MergeGuard
- 审批、恢复、持久化、审计、控制面、PR 集成

但距离“最强的全流程 parallel-harness 编排插件”还有几道关键缺口：

- 设计阶段工件还不是一等对象
- 执行隔离仍偏后验校验，不是强沙箱
- context packing 仍偏路径过滤和静态截断，缺少语义检索与阶段化策略
- gate 体系中仍有大量启发式信号，缺少独立 verifier、隐藏验证和专业设计评审
- 专业报告生成还未形成强模板、强证据、强引用闭环

因此，后续工作不应继续泛化“多 agent 数量”，而应优先把：

- 生命周期工件合同
- 执行硬隔离
- 独立验证链
- 上下文预算闭环
- 设计与报告专业化

这五条主线补强到位。
