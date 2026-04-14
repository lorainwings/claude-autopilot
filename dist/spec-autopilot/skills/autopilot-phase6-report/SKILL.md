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

## Allure Results 收集与报告生成（测试完成后）

当 `config.phases.reporting.format === "allure"` 时，测试完成后**必须执行**以下 Allure 流程：

### Step A1: 前置检查

```bash
Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/check-allure-install.sh "$(pwd)"')
```

解析返回 JSON，若 `all_required_installed === false`：

- 展示 `missing` 列表和 `install_commands`
- AskUserQuestion: "Allure 工具链不完整，是否自动安装？"
  - "自动安装 (Recommended)" → 逐个执行 install_commands
  - "跳过 Allure，使用 custom 格式" → 降级为 custom

### Step A2: 统一 ALLURE_RESULTS_DIR

确保所有测试套件的 Allure 结果输出到统一目录：

```bash
ALLURE_RESULTS_DIR="openspec/changes/{change_name}/reports/allure-results"
mkdir -p "$ALLURE_RESULTS_DIR"
```

### Step A3: 执行 allure_post 命令

对每个 `config.test_suites` 中配置了 `allure_post` 的套件：

```bash
# 示例：JUnit XML → Allure Results 转换
ALLURE_RESULTS_DIR="$ALLURE_RESULTS_DIR" eval "{suite.allure_post}"
```

### Step A4: 生成 Allure 报告

```bash
ALLURE_REPORT_DIR="openspec/changes/{change_name}/reports/allure-report"
npx allure generate "$ALLURE_RESULTS_DIR" -o "$ALLURE_REPORT_DIR" --clean
```

验证 `$ALLURE_REPORT_DIR/index.html` 存在。

### Step A5: 写入 checkpoint 附加字段

在 Phase 6 checkpoint (`phase-6-report.json`) 中包含：

```json
{
  "allure_results_dir": "openspec/changes/{change_name}/reports/allure-results",
  "allure_report_dir": "openspec/changes/{change_name}/reports/allure-report",
  "allure_report_generated": true,
  "report_format": "allure"
}
```

`allure_report_generated: false` 时 Phase 7 Step 2.5 会尝试 fallback generate。

> **降级兜底**: Allure 生成失败时降级为 `report_format: "custom"`，不阻断 Phase 6。
