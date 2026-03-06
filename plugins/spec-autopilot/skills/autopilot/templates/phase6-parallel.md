# Phase 6: 并行测试执行模板

> 此模板为**主线程可执行指令**，不是子 Agent prompt。
> Phase 6 子 Agent 读取此模板执行并行测试套件派发。

## 概述

将 `config.test_suites` 中的多个独立测试套件并行执行，显著缩短 Phase 6 总耗时。
Typecheck 类套件不需要隔离，可在主线程串行快速执行。真正耗时的测试套件（unit、api、e2e、ui）并行派发。

## Step 1: 零跳过验证

读取 `test-results.json`（Phase 5 产出），执行零跳过检查：
- test-results.json 不存在 → status: "failed"
- 任何 suite skipped > 0 → status: "failed"
- 全部通过 → 继续

## Step 2: 分类测试套件

从 `config.test_suites` 读取所有套件，分为两类：

```
fast_suites = [suite for suite in test_suites if suite.type == "typecheck"]
heavy_suites = [suite for suite in test_suites if suite.type in ["unit", "integration", "e2e", "ui"]]
```

## Step 3: 串行执行快速套件

在当前进程中直接运行（无需并行，通常 < 30 秒）：

```
for each suite in fast_suites:
  运行 `{suite.command}`
  如果失败 → 记录但不阻断（typecheck 已在 Phase 5 通过）
```

## Step 4: 并行派发重型测试套件

**在一个 response 中发出所有 Task 调用**，实现真正并行：

```
background_agents = []

for each suite in heavy_suites:
  # 根据报告格式构造测试命令
  {if config.phases.reporting.format == "allure"}
    {if suite.allure == "pytest"}
      test_command = '{suite.command} --alluredir="$ALLURE_RESULTS_DIR"'
    {end if}
    {if suite.allure == "playwright"}
      test_command = 'ALLURE_RESULTS_DIR="$ALLURE_RESULTS_DIR" {suite.command} --reporter=list,allure-playwright'
    {end if}
    {if suite.allure == "junit_xml"}
      test_command = '{suite.command}'
      post_command = '{suite.allure_post}'
    {end if}
  {else}
    test_command = '{suite.command}'
  {end if}

  agent = Task(
    subagent_type: "qa-expert",
    run_in_background: true,
    prompt: "<!-- autopilot-phase:6 -->
你是 autopilot Phase 6 的并行测试执行子 Agent。

## 你的任务
仅执行以下单个测试套件：
- 套件名: {suite_name}
- 类型: {suite.type}
- 命令: `{test_command}`
{if post_command}
- 后处理: `{post_command}`
{end if}

## Allure 结果目录
{if config.phases.reporting.format == 'allure'}
export ALLURE_RESULTS_DIR='$(pwd)/allure-results/{suite_name}'
mkdir -p \"$ALLURE_RESULTS_DIR\"
{end if}

## 执行步骤
1. 运行测试命令
2. 收集测试结果（total, passed, failed, skipped）
3. {if post_command}执行后处理命令{end if}
4. 返回 JSON 信封

## 返回要求
```json
{
  'status': 'ok | failed',
  'summary': '套件名: X passed, Y failed, Z skipped',
  'suite_name': '{suite_name}',
  'suite_type': '{suite.type}',
  'test_result': {
    'total': N,
    'passed': N,
    'failed': N,
    'skipped': N,
    'exit_code': 0
  },
  'artifacts': ['结果文件路径']
}
```
"
  )
  background_agents.append(agent)

# 等待所有 background agent 完成
```

## Step 5: 收集并行结果

所有 background agent 完成后：

```
suite_results = {}
all_passed = true

for each agent_result in background_agents:
  解析 JSON 信封
  suite_results[agent_result.suite_name] = agent_result.test_result
  if agent_result.status == "failed":
    all_passed = false
```

## Step 6: 合并 Allure 结果（仅 Allure 模式）

```
{if config.phases.reporting.format == "allure"}
# 将各套件的 allure 结果合并到统一目录
mkdir -p allure-results
for each suite_name in suite_results:
  cp -r allure-results/{suite_name}/* allure-results/ 2>/dev/null || true

# 生成统一 Allure HTML 报告
npx allure generate allure-results -o allure-report --clean
{end if}
```

## Step 7: 生成自定义报告（仅 Custom 模式）

```
{if config.phases.reporting.format == "custom"}
{for each cmd in config.phases.reporting.report_commands}
- `{cmd.value}`（替换 {change_name}）
{end for}
{end if}
```

## Step 8: 写入 test-results.json（更新）

将并行收集的结果写入统一的 `test-results.json`：

```json
{
  "suites": {
    "backend_unit": { "command": "...", "exit_code": 0, "total": 10, "passed": 10, "failed": 0, "skipped": 0 },
    "api_test": { "command": "...", "exit_code": 0, "total": 8, "passed": 8, "failed": 0, "skipped": 0 }
  },
  "zero_skip_check": { "passed": true, "violations": [] },
  "parallel_execution": true,
  "execution_time_seconds": 120
}
```

## Step 9: 构造 Phase 6 JSON 信封

```json
{
  "status": "ok | failed",
  "summary": "N 个测试套件完成，通过率 X%",
  "artifacts": ["allure-report/index.html 或 testreport/test-report.html"],
  "pass_rate": 0.95,
  "report_path": "allure-report/index.html",
  "report_format": "allure | custom",
  "allure_results_dir": "allure-results"
}
```

## 降级：并行失败时

如果任何 background Task 调用失败（非测试失败，而是 Task 执行本身失败）：
1. 将该套件加入 retry_queue
2. 所有并行 Task 完成后，对 retry_queue 中的套件在主线程串行执行
3. 如果串行也失败 → 标记该套件为 failed，继续生成报告

## 超时保护

每个 background Task 应在 10 分钟内完成。
超过 10 分钟仍未返回的套件 → 标记为 "timeout"，继续处理已完成的结果。
