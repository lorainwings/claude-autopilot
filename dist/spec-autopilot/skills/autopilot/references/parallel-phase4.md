# Phase 4 并行调度配置与模板

> 本文件从 `parallel-dispatch.md` 拆分（v5.2），仅在 Phase 4 按需加载。
> 通用并行编排协议（适用条件、Union-Find、模板、结果收集、降级策略）见 `parallel-dispatch.md`。

## Phase 4: 测试用例并行生成

```yaml
parallel_tasks:
  - name: "unit-tests"
    agent: "backend-developer"
    domain: "backend"
    test_type: "unit"
  - name: "api-tests"
    agent: "qa-expert"
    domain: "api"
    test_type: "integration"
  - name: "e2e-tests"
    agent: "qa-expert"
    domain: "e2e"
    test_type: "e2e"
  - name: "ui-tests"
    agent: "frontend-developer"
    domain: "frontend"
    test_type: "ui"
```

汇合后: 合并 test_counts → 验证 test_pyramid → 运行 dry-run

## Phase 4 并行调度模板

按 `config.phases.testing.gate.required_test_types` 中的测试类型分组，每种类型派发一个子 Agent：

```markdown
{for each test_type in config.phases.testing.gate.required_test_types}
Task(subagent_type: "{agent_for_type}", run_in_background: true,
  prompt: "<!-- autopilot-phase:4 -->
  你是 autopilot Phase 4 的并行测试设计子 Agent（{test_type} 专项）。

  ## 需求追溯（必须遵守）
  以下是 Phase 1 确认的需求清单，每个测试用例必须关联到至少一个需求点：
  {phase1_requirements_summary}
  {phase1_decisions}

  ## 你的任务
  仅创建 {test_type} 类型的测试用例（≥ {min_test_count_per_type} 个）。
  测试套件配置: {config.test_suites[test_type]}

  ## 测试追溯要求
  每个测试用例必须包含注释，说明其追溯的需求点:
  // Traces: REQ-1.1 用户登录功能

  ## 返回要求
  {"status": "ok|blocked", "summary": "...", "test_counts": {"{test_type}": N}, "artifacts": [...], "test_traceability": [{"test": "...", "requirement": "..."}]}
  "
)
{end for}
```

主线程汇合后合并所有子 Agent 的 `test_counts`、`artifacts`、`test_traceability`，验证 test_pyramid。

### Phase 4 Dispatch 强制指令（非并行和并行通用）

以下指令必须注入到 Phase 4 所有子 Agent prompt 中：

```markdown
## 强制要求（不可违反）

你**必须**创建实际的测试文件，不允许以"后续补充"或"纯 UI 变更不需要"为由跳过。

### 必须创建的测试文件

根据 config.test_suites 中定义的测试套件，为每种 type 创建对应的测试文件：

{for each suite in config.test_suites where suite.type in config.phases.testing.gate.required_test_types}
- **{suite_name}**（≥{config.phases.testing.gate.min_test_count_per_type} 个用例）
  - 命令: `{suite.command}`
  - 目录: {从 config.project_context.project_structure.test_dirs 获取}
{end for}

### 测试凭据（从 config 自动注入，禁止使用假数据）
{自动从 config.project_context.test_credentials 注入}

### Playwright 登录流程（从 config 自动注入）
{自动从 config.project_context.playwright_login 注入}

### 测试计划文档（必须创建）

在 `openspec/changes/{change_name}/context/test-plan.md` 中记录：
- 测试策略概述
- 各类型用例数量统计
- 每个测试文件路径和覆盖范围

### Dry-run 语法验证（必须执行）

创建测试文件后必须执行语法检查：
{for each suite in config.test_suites}
- {suite_name}: 对应的 dry-run 命令
{end for}

### 返回要求

status 只允许 "ok" 或 "blocked"：
- 所有测试文件创建成功 + dry-run 通过 → `"status": "ok"`
- 任何原因无法创建 → `"status": "blocked"`，summary 说明阻塞原因
- **禁止返回 "warning"**：Phase 4 不接受降级通过

### 变更聚焦专项测试（v3.2.5 新增）

测试用例**必须聚焦本次变更点**，不允许只生成泛化测试。

1. 从 tasks.md 或 phase-1-requirements.json 提取本次变更涉及的具体代码单元（函数、端点、组件）
2. 每个变更点至少 1 个专项测试用例
3. 返回信封中必须包含 `change_coverage` 字段：
```json
{
  "change_coverage": {
    "change_points": ["变更点列表"],
    "tested_points": ["已覆盖的变更点"],
    "coverage_pct": 100,
    "untested_points": []
  }
}
```
`coverage_pct` ≥ 80%，否则视为 blocked。

### 测试金字塔比例约束

测试用例分布必须符合金字塔模型（从 `config.test_pyramid` 读取阈值，默认值如下）：
- **单元测试** ≥ 总用例数的 {config.test_pyramid.min_unit_pct}%
- **E2E + UI 测试** ≤ 总用例数的 {config.test_pyramid.max_e2e_pct}%
- **总用例数** ≥ {config.test_pyramid.min_total_cases}

返回信封中必须包含 `test_pyramid` 字段：
```json
{
  "test_pyramid": {
    "total": 25,
    "unit_pct": 60,
    "integration_pct": 24,
    "e2e_pct": 16
  }
}
```
```
