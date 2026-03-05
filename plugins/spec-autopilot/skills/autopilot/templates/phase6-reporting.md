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

## 报告内容要求

- 测试概览：总用例数、通过数、失败数、跳过数（必须为 0）
- 按类型统计：各类测试通过率
- 失败详情：根因分析、错误消息、堆栈跟踪
- 已知问题：known_issues 列表
- 零跳过验证结果

## 返回要求

必须包含 pass_rate、report_path、report_format 字段。
