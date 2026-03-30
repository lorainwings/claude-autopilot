# 2026-03-30 架构与研究文档索引

本目录汇总了 `parallel-harness` 在 `2026-03-30` 的一轮完整架构分析、行业调研、实现评审和增强蓝图。

建议阅读顺序如下。

## 核心主线

1. `01_lifecycle_architecture_design.md`  
   当前实现的 As-Is 生命周期、模块边界、架构图、数据流与主链事实。

2. `02_ai_limitations_mitigation_strategy.md`  
   AI 在真实软件交付中的核心缺陷，以及 harness 应如何用上下文治理、独立验证、审批与审计来缓解。

3. `03_harness_best_practices_and_competitors.md`  
   Harness 方法论、社区最佳实践，以及 LangGraph、AutoGen、OpenAI Agents SDK、Claude Code、Copilot、Cursor、Devin、OpenHands、Cline、CrewAI 等能力矩阵。

4. `04_parallel_harness_implementation_review.md`  
   基于当前源码与本地验证的实现评审，聚焦问题与风险，不复述理想态。

5. `05_parallel_harness_enhancement_blueprint.md`  
   基于前四篇文档收敛出的修复与增强蓝图，按 P0 / P1 / P2 路线拆解。

## 后续 remediation 文档

- `08_claude_followup_remediation_execution_plan.md`
- `09_claude_followup_remediation_prompt.md`
- `10_claude_remediation_review.md`
- `11_claude_precision_remediation_prompt.md`
- `12_claude_latest_remediation_execution_plan.md`

其中：

- `12_claude_latest_remediation_execution_plan.md` 是当前最新、可直接交给 Claude 的执行施工单
- `08-11` 更适合作为历史 remediation 轨迹，不应再作为唯一执行依据

这些文档可作为后续修复执行和复审的补充材料，但不替代 `01-05` 这组主文档。

## 本轮结论

这组文档的统一判断是：

- 当前项目已经具备完整 orchestrator 骨架。
- `Requirement Grounding`、`MergeGuard`、`run-level gates`、`evidence-loader`、报告聚合与 PR 集成均已进入真实主链。
- 但 execution hardening、context budget 闭环、hard gate 分层、repo-aware PR 隔离、扩展层 effect 化、类型/测试/文档一致性闭环仍未完成。

因此，后续工作应优先围绕 `05` 的 P0 路线推进，而不是继续增加更多未受控的 agent 数量。
