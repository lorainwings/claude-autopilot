# Architecture And Research

本目录沉淀 `parallel-harness` 在 `2026-03-29` 的架构基线、行业调研、实现评审和增强蓝图。

文档顺序建议按以下顺序阅读：

1. [01_lifecycle_architecture_design.md](01_lifecycle_architecture_design.md)
   当前项目的真实全流程架构、模块关系图、状态机和实现原理。
2. [02_ai_limitations_mitigation_strategy.md](02_ai_limitations_mitigation_strategy.md)
   现有 AI 在长上下文、代码生成、测试、reward hacking、需求理解方面的局限，以及 harness 化缓解策略。
3. [03_harness_best_practices_and_competitors.md](03_harness_best_practices_and_competitors.md)
   社区最佳实践与竞品能力矩阵，对标 OpenAI、Claude Code、Devin、Cursor、Factory、OpenHands、Continue、Sweep、Amp。
4. [04_parallel_harness_implementation_review.md](04_parallel_harness_implementation_review.md)
   对当前 `parallel-harness` 的实现评审，包含高优先级风险与文档偏差。
5. [05_parallel_harness_enhancement_blueprint.md](05_parallel_harness_enhancement_blueprint.md)
   面向“最强 parallel-harness 编排插件”的修复与增强方案。
6. [06_full_remediation_execution_manual.md](06_full_remediation_execution_manual.md)
   全量修复执行手册，面向真正的施工过程，不做优先级取舍。
7. [07_claude_full_remediation_prompt.md](07_claude_full_remediation_prompt.md)
   可直接交给 Claude 的全量修复提示词。

建议使用方式：

- 架构讨论先读 `01`
- 做方案评审前结合 `02 + 03`
- 做当前版本风险判断时读 `04`
- 做执行规划和版本路线时读 `05`
- 真正开始全量修复时先读 `06`，再把 `07` 直接交给执行型 AI
