# 2026-04-02 parallel-harness 架构、调研与增强文档索引

本目录基于 `2026-04-02` 当前工作区重新完成一轮全量分析，目标不是复述 `2026-03-31` 版本，而是把下面四类事实重新对齐：

1. 当前 `plugins/parallel-harness/runtime/**` 到底已经接线了什么。
2. 当前社区对 harness、agent orchestration、context engineering、独立验证和隔离执行的最佳实践是什么。
3. 当前 `parallel-harness` 在“产品设计 -> UI 设计 -> 技术方案 -> 前后端实现 -> 测试 -> 质量保证 -> 报告生成”目标下还缺哪些硬能力。
4. 基于以上事实，下一版“最强 parallel-harness 编排插件”应该按什么顺序修。

## 文档列表

1. `01_lifecycle_architecture_design.md`
   - 当前 As-Is 架构图
   - 当前真正接线的生命周期主链
   - 已实现模块与“已写代码但未接线模块”的边界
   - 面向全流程产品开发的 To-Be 目标态架构

2. `02_ai_limitations_mitigation_strategy.md`
   - 调研当前 AI 在长上下文、代码生成稳定性、测试覆盖、奖励挟持、需求理解方面的典型缺陷
   - 说明“上下文超过 40% 就急剧下降”不应被当作统一科学定律
   - 给出 harness 级缓解策略和当前项目的落点

3. `03_harness_best_practices_and_competitors.md`
   - 总结社区当前对 harness 的最佳实践
   - 对比 OpenAI Agents SDK、Claude Code、LangGraph、Google ADK、Cursor、Devin、OpenHands 的能力矩阵
   - 提炼对 `parallel-harness` 最有价值的设计启示

4. `04_parallel_harness_implementation_review.md`
   - 对当前实现做审计式评审
   - 优先列出关键问题、设计偏差、死代码和文档偏差
   - 补充最小复现和测试覆盖缺口

5. `05_parallel_harness_enhancement_blueprint.md`
   - 基于前四篇文档收敛修复与增强方案
   - 按 `P0 / P1 / P2` 拆解实施路线、数据契约和验收标准

## 本轮本地验证基线

- `cd plugins/parallel-harness && bun test`
  - 结果：`415 pass / 0 fail / 868 expect() calls / 24 files`
- `cd plugins/parallel-harness && bunx tsc --noEmit`
  - 结果：通过，无输出

## 本轮相对上一轮的关键新增发现

这次不是只更新测试数字，还确认了几类会直接削弱稳定性的结构性问题：

- `ContextPackager` 与 `EvidenceLoader` 的路径语义不一致，`"."` 或绝对根路径场景下会选不到上下文文件。
- `budget_limit / remaining_budget / token_budget / tokens_used` 在主链里发生了语义混用，导致路由、上下文预算和成本统计互相污染。
- task-level `test` / `lint_type` gate 会在并行批次里重复触发全仓命令，默认配置下会放大抖动与成本。
- 生命周期、隐藏验证、证据生产器、专业报告模板等多个模块虽然有代码和测试，但没有接入主运行时。
- 旧 README / marketplace 文档仍沿用 `295 pass / 0 fail / 649 expect()` 和过宽的 `GA` 表述，已经落后于当前工作区事实。

## 建议阅读顺序

如果你只关心“当前项目哪里不可靠、先修什么”，建议顺序：

1. `04_parallel_harness_implementation_review.md`
2. `05_parallel_harness_enhancement_blueprint.md`
3. `01_lifecycle_architecture_design.md`

如果你更关心“行业最佳实践和竞品怎么做”，建议顺序：

1. `03_harness_best_practices_and_competitors.md`
2. `02_ai_limitations_mitigation_strategy.md`
3. `05_parallel_harness_enhancement_blueprint.md`
