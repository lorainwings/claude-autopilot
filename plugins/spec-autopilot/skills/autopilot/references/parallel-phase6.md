# Phase 6 并行调度配置与模板

> 本文件从 `parallel-dispatch.md` 拆分（v5.2），仅在 Phase 6 按需加载。
> 通用并行编排协议（适用条件、Union-Find、模板、结果收集、降级策略）见 `parallel-dispatch.md`。

## Phase 6: 三路并行（v3.2.2 增强）

Phase 6 采用**跨维度三路并行**，不同于 Phase 1/4/5 的阶段内并行：

```yaml
tri_path_parallel:
  # 路径 A: 测试执行（后台 Task，按统一调度模板）
  path_a:
    type: "background"
    parallel_tasks:  # 路径 A 内部可进一步并行（按 test_suites 分组）
      - name: "{suite_name}"
        command: "{suite.command}"
        allure_args: "{suite.allure_args}"
        merge_strategy: "none"

  # 路径 B: 代码审查（后台 Task）
  path_b:
    type: "background"
    condition: "config.phases.code_review.enabled"
    agent: "general-purpose"
    prompt_source: "references/phase6-code-review.md"
    no_phase_marker: true  # 不含 autopilot-phase 标记，Hook 直接放行

  # 路径 C: 质量扫描（多个后台 Task）
  path_c:
    type: "background"
    source: "config.async_quality_scans"
    prompt_source: "references/quality-scans.md"
    no_phase_marker: true
    timeout: "config.async_quality_scans.timeout_minutes"
```

汇合点: Phase 7 步骤 2（收集 A/B/C 全部结果）

## Phase 6 并行调度模板

按 `config.test_suites` 中的套件分组，每个套件派发一个子 Agent 并行执行：

```markdown
{for each suite in config.test_suites}
Task(subagent_type: "qa-expert", run_in_background: true,
  prompt: "<!-- autopilot-phase:6 -->
  你是 autopilot Phase 6 的并行测试执行子 Agent（{suite_name} 专项）。

  ## 你的任务
  执行以下测试套件并收集结果:
  - 命令: `{suite.command}`
  - 类型: {suite.type}

  ## Allure 集成
  {if config.phases.reporting.format === 'allure'}
  确保测试结果输出到 Allure 格式:
  - pytest: 添加 `--alluredir=allure-results/{suite_name}`
  - Playwright: 设置 `ALLURE_RESULTS_DIR=allure-results/{suite_name}`
  - Gradle: 复制 XML 结果到 `allure-results/{suite_name}/`
  {end if}

  ## 返回要求
  {"status": "ok|warning|failed", "summary": "...", "pass_rate": N, "total": N, "passed": N, "failed": N, "skipped": N, "artifacts": [...]}
  "
)
{end for}
```

主线程汇合后:
1. 合并所有套件的测试结果
2. **确定性执行** Allure 报告合并（当 `allure-results/` 存在时）：
   ```
   Bash('
     if [ -d "allure-results" ]; then
       npx allure generate allure-results/ -o allure-report/ --clean
       if [ $? -eq 0 ]; then
         echo "ALLURE_GENERATED"
       else
         echo "ALLURE_GENERATE_FAILED"
       fi
     else
       echo "NO_ALLURE_RESULTS"
     fi
   ')
   ```
   - `ALLURE_GENERATED` → 设置 `report_url` 为 `file:///path/to/allure-report/index.html`
   - `ALLURE_GENERATE_FAILED` → 降级为 custom 格式，输出 `[WARN]`
   - `NO_ALLURE_RESULTS` → 使用 custom 格式
3. 汇总 pass_rate、异常提醒、报告链接
4. 设置 `report_url`：
   - allure-report/ 存在: `file:///path/to/allure-report/index.html`
   - 否则: `file:///path/to/testreport/test-report.html`
   — Phase 7 Step 2.5 启动 Allure 服务后，最终展示链接将更新为 `http://localhost:{port}`
