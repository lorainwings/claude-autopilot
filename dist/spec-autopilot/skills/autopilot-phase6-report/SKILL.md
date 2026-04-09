---
name: autopilot-phase6-report
description: "[ONLY for autopilot orchestrator] Phase 6: Test report generation with tri-path parallel execution (testing + code review + quality scans) and Allure integration."
user-invocable: false
---

# Autopilot Phase 6 — 测试报告与三路并行

> **前置条件自检**：本 Skill 仅在 autopilot 编排主线程中使用。如果当前上下文不是 autopilot 编排流程，请立即停止并忽略本 Skill。

Phase 6 执行测试报告生成，支持三路并行（测试 + 代码审查 + 质量扫描）和 Allure 集成。

**执行前读取**: `autopilot/references/parallel-phase6.md` + `autopilot/references/phase6-code-review.md` + `autopilot/references/quality-scans.md`

## Phase 5→6 特殊门禁

> **仅 full 和 lite 模式执行**。minimal 模式跳过 Phase 6。

autopilot-gate 额外验证：
- `test-results.json` 存在
- `zero_skip_check.passed === true`
- 任务清单中所有任务标记为 `[x]`

## 测试执行

- 并行测试执行按 `config.test_suites` 分套件派发（详见 `autopilot/references/parallel-phase6.md`）
- Agent: qa-expert
- 测试命令从 config.test_suites 动态读取（全量运行所有 suite���
- 报告命令从 config.phases.reporting.report_commands 读取
- 可选覆盖：config.phases.reporting.instruction_files（非空时注入）

## Allure 统一报告

当 `config.phases.reporting.format === "allure"` 时：
- 前置检查 Allure 安装
- 统一 `ALLURE_RESULTS_DIR` 输出
- 生成报告
- 降级兜底为 `report_format: "custom"`

详见 `autopilot/references/protocol.md` Allure 报告章节。

## Phase 6 三路并行（v3.2.2 增强）

> 详见 `autopilot/references/mode-routing-table.md` § 7。

Phase 5→6 Gate 通过后，主线程**在同一条消息中**同时派发路径 A / B / C，全部 `run_in_background: true`：

| 路径 | 内容 | 阻断性 |
|------|------|--------|
| **路径 A** | Phase 6 测试执行 | 主路径 |
| **路径 B** | Phase 6.5 代码审查（`config.phases.code_review.enabled = true` 时） | 不阻断路径 A |
| **路径 C** | 质量扫描（契约/性能/视觉/变异/安全测试） | 不阻断路径 A |

路径 B/C 不含 `autopilot-phase` 标记（不受 Hook 门禁校验）。

**Phase 7 步骤 2 统一收集三路结果。**

## Phase 6 路径 A（测试）dispatch 说明

- 也必须使用 `run_in_background: true`：测试执行不需要交互，主线程等待完成通知后写入 checkpoint
- 与路径 B/C 在同一消息中全部后台派发
