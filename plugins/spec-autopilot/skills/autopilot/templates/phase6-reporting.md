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

## 报告生成策略

根据 `config.phases.reporting.format` 选择报告生成路径：

### 路径 1: Allure 报告（推荐，format: "allure"）

**Step 1: 安装检查**

```bash
bash <plugin_scripts>/check-allure-install.sh "$(pwd)"
```

解析返回 JSON：
- `all_required_installed === true` → 继续 Step 2
- `all_required_installed === false` → 按 `install_commands` 逐个安装：
  - allure-cli: `npm install -g allure-commandline` 或 `brew install allure`
  - allure-pytest: `pip3 install allure-pytest`
  - allure-playwright: `pnpm add -D allure-playwright`（在 tests/e2e 或项目根目录）
  - 安装后重新检查 → 仍失败 → 自动降级为路径 2（custom）

**Step 2: 设置统一输出目录**

```bash
export ALLURE_RESULTS_DIR="$(pwd)/allure-results"
rm -rf "$ALLURE_RESULTS_DIR" && mkdir -p "$ALLURE_RESULTS_DIR"
```

**Step 3: 运行测试套件并收集 Allure 结果**

{for each suite in config.test_suites where suite.allure != "none"}

Suite: {suite_name} (allure: {suite.allure})

{if suite.allure == "pytest"}
- 命令: `{suite.command} --alluredir="$ALLURE_RESULTS_DIR"`
  （在原命令基础上追加 `--alluredir` 参数）
{end if}

{if suite.allure == "playwright"}
- 命令: `ALLURE_RESULTS_DIR="$ALLURE_RESULTS_DIR" {suite.command} --reporter=list,allure-playwright`
  （追加 allure-playwright reporter）
{end if}

{if suite.allure == "junit_xml"}
- 命令: `{suite.command}`
- 后处理: `{suite.allure_post}`
  （将 JUnit XML 结果复制到 ALLURE_RESULTS_DIR）
{end if}

{end for}

对 allure == "none" 的套件（如 typecheck），仅正常运行不收集 Allure 结果。

**Step 4: 生成 Allure HTML 报告**

```bash
npx allure generate "$ALLURE_RESULTS_DIR" -o allure-report --clean
```

报告路径: `allure-report/index.html`

**Step 5: 可选 — 启动临时预览服务器**

```bash
npx allure open allure-report --port 0
```

> 端口设为 0 自动分配空闲端口，避免冲突。

### 路径 2: 自定义报告（format: "custom"）

使用项目配置的 report_commands：

{if config.phases.reporting.report_commands}
{for each cmd in report_commands}
- `{cmd.value}`（将 `{change_name}` 替换为实际 change 名称）
{end for}
{else}
- 在 testreport/ 目录生成 test-report.md 和 test-report.html
{end if}

### 路径选择决策树

```
config.phases.reporting.format === "allure"
  → Allure 安装检查通过 → 路径 1
  → Allure 安装失败 → 自动降级为路径 2，report_format 返回 "custom"
config.phases.reporting.format === "custom"
  → 路径 2
config.phases.reporting.format 未设置
  → 默认路径 2
```

## 报告内容要求

无论使用哪种报告路径，最终报告必须包含：

- 测试概览：总用例数、通过数、失败数、跳过数（必须为 0）
- 按类型统计：各类测试通过率
- 失败详情：根因分析、错误消息、堆栈跟踪
- 已知问题：known_issues 列表
- 零跳过验证结果
- 需求追溯覆盖率（从 Phase 4 的 test-plan.md 读取）

## 返回要求

必须包含 pass_rate、report_path、report_format 字段。

Allure 模式额外返回：
```json
{
  "report_format": "allure",
  "report_path": "allure-report/index.html",
  "allure_results_dir": "allure-results"
}
```

Custom 模式返回：
```json
{
  "report_format": "custom",
  "report_path": "testreport/test-report.html"
}
```
