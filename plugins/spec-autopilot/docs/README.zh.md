> [English](README.md) | 中文

# spec-autopilot 文档导航

> 本索引覆盖 spec-autopilot v5.1 全部文档，按用途分类。含事件总线、GUI V2 大盘、并行调度、需求路由等新特性。

## 入门指南 (`getting-started/`)

| 文档 | 说明 |
|------|------|
| [quick-start.zh.md](getting-started/quick-start.zh.md) | 5 分钟快速开始：安装到首次交付 |
| [integration-guide.zh.md](getting-started/integration-guide.zh.md) | 项目接入指南：全新项目完整接入流程 |
| [configuration.zh.md](getting-started/configuration.zh.md) | 配置参考：YAML 字段完整说明 |

## 架构参考 (`architecture/`)

| 文档 | 说明 |
|------|------|
| [overview.zh.md](architecture/overview.zh.md) | 架构总览：8 阶段流水线、三层门禁、事件总线、GUI V2、并行调度、需求路由 |
| [phases.zh.md](architecture/phases.zh.md) | 阶段详解：输入输出、checkpoint 格式、需求路由、TDD 循环、事件发射 |
| [gates.zh.md](architecture/gates.zh.md) | 门禁系统：三层门禁、反合理化 (16 种模式)、routing_overrides、decision_ack 闭环 |

## 运维指南 (`operations/`)

| 文档 | 说明 |
|------|------|
| [config-tuning-guide.zh.md](operations/config-tuning-guide.zh.md) | 配置调优：按项目类型优化配置 |
| [troubleshooting.zh.md](operations/troubleshooting.zh.md) | 故障排查：常见错误、调试技巧、恢复方案 |

## 迁移指南 (`migration/`)

| 文档 | 说明 |
|------|------|
| [v4-to-v5.zh.md](migration/v4-to-v5.zh.md) | v4 → v5 迁移：配置 Schema 变更、Hook 协议、Event Bus、兼容性矩阵 |

## 审计报告 (`reports/`)

> 按插件版本分子目录存放，逆序排列（最新版本在上）。

### v5.0.10

| 文档 | 说明 |
|------|------|
| [v5.3-evaluation-dashboard.md](reports/v5.0.10/v5.3-evaluation-dashboard.md) | v5.3 满血版 7-Agent 并行评估仪表盘 |
| [compliance-audit-v5.3.md](reports/v5.0.10/compliance-audit-v5.3.md) | 合规性审计 |
| [performance-benchmark-v5.3.md](reports/v5.0.10/performance-benchmark-v5.3.md) | 性能基准测试 |
| [holistic-simulation-benchmark-v5.3.md](reports/v5.0.10/holistic-simulation-benchmark-v5.3.md) | 全局仿真基准 |
| [competitive-analysis-v5.3.md](reports/v5.0.10/competitive-analysis-v5.3.md) | 竞品对比分析 |
| [gui-interaction-audit-v5.3.md](reports/v5.0.10/gui-interaction-audit-v5.3.md) | GUI 交互审计 |
| [infrastructure-audit-v5.3.md](reports/v5.0.10/infrastructure-audit-v5.3.md) | 基础设施审计 |
| [routing-socratic-benchmark-v5.3.md](reports/v5.0.10/routing-socratic-benchmark-v5.3.md) | 路由 + Socratic 基准 |

### v5.0.7

| 文档 | 说明 |
|------|------|
| [regression-report.md](reports/v5.0.7/regression-report.md) | 回归测试报告 |

### v5.0.5

| 文档 | 说明 |
|------|------|
| [v5.1.1-evaluation-dashboard.md](reports/v5.0.5/v5.1.1-evaluation-dashboard.md) | v5.1.1 评估仪表盘 |
| [compliance-audit-v5.1.1.md](reports/v5.0.5/compliance-audit-v5.1.1.md) | 合规性审计 |
| [stability-audit-v5.1.1.md](reports/v5.0.5/stability-audit-v5.1.1.md) | 稳定性审计 |
| [performance-benchmark-v5.1.1.md](reports/v5.0.5/performance-benchmark-v5.1.1.md) | 性能基准 |
| [phase1-benchmark-v5.1.1.md](reports/v5.0.5/phase1-benchmark-v5.1.1.md) | Phase 1 基准 |
| [competitive-analysis-v5.1.1.md](reports/v5.0.5/competitive-analysis-v5.1.1.md) | 竞品分析 |
| [gui-interaction-audit-v5.1.1.md](reports/v5.0.5/gui-interaction-audit-v5.1.1.md) | GUI 交互审计 |
| [holistic-simulation-benchmark-v5.1.1.md](reports/v5.0.5/holistic-simulation-benchmark-v5.1.1.md) | 全局仿真基准 |
| [hotfix-verification.md](reports/v5.0.5/hotfix-verification.md) | 热修复验证 |

### v5.0.4

| 文档 | 说明 |
|------|------|
| [v5.0.4-evaluation-dashboard.md](reports/v5.0.4/v5.0.4-evaluation-dashboard.md) | v5.0.4 评估仪表盘 |
| [compliance-audit.md](reports/v5.0.4/compliance-audit.md) | 合规性审计 |
| [stability-audit.md](reports/v5.0.4/stability-audit.md) | 稳定性审计 |
| [performance-benchmark.md](reports/v5.0.4/performance-benchmark.md) | 性能基准 |
| [phase1-benchmark.md](reports/v5.0.4/phase1-benchmark.md) | Phase 1 基准 |
| [competitive-analysis.md](reports/v5.0.4/competitive-analysis.md) | 竞品分析 |
| [gui-interaction-audit.md](reports/v5.0.4/gui-interaction-audit.md) | GUI 交互审计 |
| [holistic-simulation-benchmark.md](reports/v5.0.4/holistic-simulation-benchmark.md) | 全局仿真基准 |

### v5.0

| 文档 | 说明 |
|------|------|
| [v5.0.2-evaluation-dashboard.md](reports/v5.0/v5.0.2-evaluation-dashboard.md) | v5.0.2 评估仪表盘 |
| [compliance-audit.md](reports/v5.0/compliance-audit.md) | 合规性审计 |
| [stability-audit.md](reports/v5.0/stability-audit.md) | 稳定性审计 |
| [performance-benchmark.md](reports/v5.0/performance-benchmark.md) | 性能基准 |
| [phase1-benchmark.md](reports/v5.0/phase1-benchmark.md) | Phase 1 基准 |
| [competitive-analysis.md](reports/v5.0/competitive-analysis.md) | 竞品分析 |
| [gui-interaction-audit.md](reports/v5.0/gui-interaction-audit.md) | GUI 交互审计 |
| [holistic-simulation-benchmark.md](reports/v5.0/holistic-simulation-benchmark.md) | 全局仿真基准 |

### v4.2

| 文档 | 说明 |
|------|------|
| [competitive-analysis.md](reports/v4.2/competitive-analysis.md) | 竞品对比分析 |

### v4.1

| 文档 | 说明 |
|------|------|
| [iteration-v1-impact.md](reports/v4.1/iteration-v1-impact.md) | 迭代 v1 影响分析 |

### v4.0

| 文档 | 说明 |
|------|------|
| [stability-audit.md](reports/v4.0/stability-audit.md) | 全模式稳定性与链路闭环审计 |
| [phase1-benchmark.md](reports/v4.0/phase1-benchmark.md) | Phase 1 需求质量 Benchmark |
| [phase5-codegen-audit.md](reports/v4.0/phase5-codegen-audit.md) | Phase 5 代码生成质量评审 |
| [phase6-tdd-audit.md](reports/v4.0/phase6-tdd-audit.md) | Phase 6 TDD 流程评审 |
| [performance-benchmark.md](reports/v4.0/performance-benchmark.md) | 全阶段性能评估 |
| [competitive-analysis.md](reports/v4.0/competitive-analysis.md) | 竞品深度对比 |
| [architecture-evolution.md](reports/v4.0/architecture-evolution.md) | 架构演进指南 |

### v3.6

| 文档 | 说明 |
|------|------|
| [ecosystem-analysis.md](reports/v3.6/ecosystem-analysis.md) | 综合生态分析 |

## 规划 (`roadmap/`)

| 文档 | 说明 |
|------|------|
| [2026-03-18-scripts-engineering-refactor-blueprint.md](roadmap/2026-03-18-scripts-engineering-refactor-blueprint.md) | scripts 工程化重构蓝图：运行时契约、manifest 构建、server 分层、遗留脚本淘汰策略 |
| [v5.1.0-execution-plan.md](roadmap/v5.1.0-execution-plan.md) | v5.1.0 执行计划 |
| [v5.0.10-analysis-report.md](roadmap/v5.0.10-analysis-report.md) | v5.0.10 分析报告 |
| [v5.0.8/ui-upgrade.md](roadmap/v5.0.8/ui-upgrade.md) | v5.0.8 GUI V2 升级 |
| [v5.0.8/ui-redesign-prd.md](roadmap/v5.0.8/ui-redesign-prd.md) | v5.0.8 UI 重设计 PRD |
| [v5.0.8/v5.3-ui-refactor.md](roadmap/v5.0.8/v5.3-ui-refactor.md) | v5.3 UI 重构 |
| [v5.0.7-excellence-refactor.md](roadmap/v5.0.7-excellence-refactor.md) | v5.0.7 卓越重构 |
| [v5.0.6-sprint-to-90.md](roadmap/v5.0.6-sprint-to-90.md) | v5.0.6 冲刺至 90 分 |
| [v5.0.5-execution-plan.md](roadmap/v5.0.5-execution-plan.md) | v5.0.5 执行计划 |
| [v5.0.5-full-evaluation.md](roadmap/v5.0.5-full-evaluation.md) | v5.0.5 全面评估 |
| [v5.0.5-hotfix-verification.md](roadmap/v5.0.5-hotfix-verification.md) | v5.0.5 热修复验证 |
| [v5.0.4-execution-plan.md](roadmap/v5.0.4-execution-plan.md) | v5.0.4 执行计划 |
| [v5.0.3-execution-plan.md](roadmap/v5.0.3-execution-plan.md) | v5.0.3 执行计划 |
| [v5.0.2-execution-plan.md](roadmap/v5.0.2-execution-plan.md) | v5.0.2 执行计划 |
| [v5.0.1-execution-plan.md](roadmap/v5.0.1-execution-plan.md) | v5.0.1 执行计划 |
| [v5.0-execution-plan.md](roadmap/v5.0-execution-plan.md) | v5.0 执行计划 |
| [v4.3-execution-plan.md](roadmap/v4.3-execution-plan.md) | v4.3 执行计划 |
| [v4.2-execution-plan.md](roadmap/v4.2-execution-plan.md) | v4.2 执行计划 |
| [v4.1-execution-plan.md](roadmap/v4.1-execution-plan.md) | v4.1 执行计划 |
| [v4.1-post-iteration-impact-analysis.md](roadmap/v4.1-post-iteration-impact-analysis.md) | v4.1 迭代后影响分析 |
| [v4.0-upgrade-blueprint.md](roadmap/v4.0-upgrade-blueprint.md) | v4.0 升级蓝图 |

## 审计工具 (`benchmark/`)

| 文档 | 说明 |
|------|------|
| [prompt.md](benchmark/prompt.md) | 审计编排元提示：全方位评估任务模板 |
| [validate.md](benchmark/validate.md) | 重构执行元提示：报告驱动的重构任务模板 |

## 历史归档 (`archive/`)

| 文档 | 原始版本 |
|------|----------|
| [evaluation-report-v2.0.0.md](archive/evaluation-report-v2.0.0.md) | v2.0.0 评估报告 |
| [self-evaluation-report-v3.6.0.md](archive/self-evaluation-report-v3.6.0.md) | v3.6.0 自评报告 |
| [v3.6.0-qa-report.md](archive/v3.6.0-qa-report.md) | v3.6.0 QA 报告 |
| [v3.6.0-final-report.md](archive/v3.6.0-final-report.md) | v3.6.0 终版报告 |
| [competitive-analysis-v1.0.md](archive/competitive-analysis-v1.0.md) | 竞品分析 v1.0 |
| [product-analysis-v3.2.0.md](archive/product-analysis-v3.2.0.md) | 产品分析 v3.2.0 |
| [enhancement-roadmap-v3.2.0.md](archive/enhancement-roadmap-v3.2.0.md) | 增强路线图 v3.2.0 |
| [comprehensive-analysis-v3.2.2.md](archive/comprehensive-analysis-v3.2.2.md) | 综合分析 v3.2.2 |
| [deep-analysis-v3.4.3.md](archive/deep-analysis-v3.4.3.md) | 深度分析 v3.4.3 |
| [v3.2.0-design.md](archive/v3.2.0-design.md) | v3.2.0 设计文档 |
| [v3.5.0-iteration-plan.md](archive/v3.5.0-iteration-plan.md) | v3.5.0 迭代计划 |
