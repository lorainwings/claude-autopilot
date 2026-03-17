# Phase 6: 测试报告生成（内置模板）

> 此模板由插件内置提供。项目可通过 config.phases.reporting.instruction_files 覆盖。

## 零跳过验证（第一步，硬阻断）

1. 读取 test-results.json
2. 遍历所有 suites，检查 skipped 字段
3. 检查 zero_skip_check.passed

判定规则：
- test-results.json 不存在 → status: "failed"
- 任何 suite skipped > 0 → status: "failed"
- known_issues 中有用户批准的已知问题 → 不算跳过
- 全部 passed → 继续

## 运行完整测试套件（智能执行）

先读取 test-results.json，仅对以下情况重新运行：
- exit_code != 0 的 suite
- test-results.json 中不存在的 suite
- 距离上次运行超过 30 分钟的 suite

{for each suite in config.test_suites}
- `{suite.command}`
{end for}

## 生成报告

{if config.phases.reporting.report_commands}
{for each cmd in report_commands}
- `{cmd.value} {change_name}`
{end for}
{else}
- 在 testreport/ 目录生成 test-report.md 和 test-report.html
{end if}

## 并行测试执行（v3.2.0 新增）

当以并行模式执行时，你仅负责**一个测试套件**：
- 你的套件：`{suite_name}`（由控制器分配）
- 执行命令：`{suite.command}`
- 其他套件由其他并行子 Agent 负责

### Allure 结果输出

{if config.phases.reporting.format === "allure"}
确保测试结果输出到 Allure 格式（各框架适配方式）：

| 框架 | Allure 参数 |
|------|------------|
| pytest | `--alluredir=allure-results/{suite_name}` |
| Playwright | `ALLURE_RESULTS_DIR=allure-results/{suite_name} --reporter=list,allure-playwright` |
| Gradle/JUnit | 复制 `build/test-results/test/*.xml` 到 `allure-results/{suite_name}/` |
| Vitest | `--reporter=allure --outputDir=allure-results/{suite_name}` |

> Allure 安装检查由主线程预先完成。不可用时自动降级为 custom 格式。
{end if}

## 报告内容要求

### 基础要求
- 测试概览：总用例数、通过数、失败数、跳过数（必须为 0）
- 按类型统计：各类测试通过率
- 失败详情：根因分析、错误消息、堆栈跟踪
- 已知问题：known_issues 列表
- 零跳过验证结果

### v3.2.0 增强要求

**异常提醒**（anomaly_alerts）：
对每个失败或跳过的用例，生成人类可读的异常描述：
```
"API 测试: test_create_user_duplicate 失败 — 预期 409 但返回 500"
"UI 测试: test_login_page_layout 跳过 — 缺少 Playwright 浏览器"
```

**套件级结果**（suite_results）：
```json
[
  { "suite": "backend_unit", "total": 25, "passed": 25, "failed": 0, "skipped": 0 },
  { "suite": "api_test", "total": 12, "passed": 11, "failed": 1, "skipped": 0 }
]
```

**报告访问链接**：
- Allure 格式: `file:///path/to/allure-report/index.html`
- Custom 格式: `file:///path/to/testreport/test-report.html`

**Phase 7 汇总表格**（由主线程根据以下数据生成，子 Agent 提供原始数据即可）：
```markdown
| 套件 | 总数 | 通过 | 失败 | 跳过 | 通过率 |
|------|------|------|------|------|--------|
```

## 返回要求

必须包含 pass_rate、report_path、report_format 字段。
**推荐字段**（缺失时校验器 warn，不阻断）: `suite_results`, `anomaly_alerts`, `red_evidence`, `sample_failure_excerpt`。

```json
{
  "pass_rate": 96.5,
  "report_path": "allure-report/index.html",
  "report_format": "allure",
  "suite_results": [{"suite": "unit", "total": 42, "passed": 40, "failed": 2, "skipped": 0}],
  "anomaly_alerts": [],
  "red_evidence": "FAIL: UserService.login should reject expired token",
  "sample_failure_excerpt": "Expected: 401, Received: 200"
}
```
