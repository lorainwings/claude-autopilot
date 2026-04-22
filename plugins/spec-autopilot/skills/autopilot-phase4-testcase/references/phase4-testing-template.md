# Phase 4: 测试用例设计模板

> 本文件由 `skills/autopilot/templates/phase4-testing.md` 拷贝而来，供 Phase 4 子 SKILL 直接引用，避免跨 SKILL 路径硬编码。
> 项目可通过 `config.phases.testing.instruction_files` 覆盖。
> **TDD 模式说明**: 当 `config.phases.implementation.tdd_mode: true` 且模式为 `full` 时，
> Phase 4 被跳过（标记 `skipped_tdd`）。测试在 Phase 5 per-task TDD RED step 创建。
> 此模板在 TDD 模式下不使用。

## 环境前置检查

在创建测试文件之前，必须验证以下服务可达：

{for each service in config.services}
```bash
curl -sf {service.health_url} || echo "BLOCKED: {service.name} 未启动"
```
{end for}

处理规则：

- 全部可达 → 继续
- 任一不可达 → 返回 `status: "blocked"`，`risks` 中列出不可达的服务
- 子 Agent 禁止自行启动服务

## 测试矩阵

基于 proposal/specs/design 逐一分析，生成测试矩阵：

| 维度 | 必须覆盖内容 | 最低用例数 |
|------|------------|-----------|
| 后端 API 接口 | 每个端点的正常/异常/边界场景 | 每端点 ≥3 个 |
| 前端页面和组件 | 渲染、交互、状态变化、错误态 | 每组件 ≥3 个 |
| 完整业务流程 | 主流程 + 分支流程 + 异常中断 | ≥5 个完整流程 |
| 边界条件和异常 | 空值、超长、并发、权限、网络异常 | ≥8 个边界用例 |

## 变更聚焦专项测试

测试用例**必须聚焦本次变更**，而非泛化生成。流程如下：

### 1. 提取变更清单

从任务来源文件中提取本次变更涉及的**具体代码变更点**：

- **full 模式**: 读取 `openspec/changes/{change_name}/tasks.md`，提取每个 task 的目标文件和函数/方法
- **lite/minimal 模式**: 读取 `context/phase5-task-breakdown.md`（Phase 5 启动时生成）或 `phase-1-requirements.json` 中的 `requirements_summary`

### 2. 为每个变更点设计专项测试

**每个被修改/新增的代码单元（函数、方法、端点、组件）必须有至少 1 个专项测试**。

```text
变更点示例                          → 专项测试示例
─────────────────────────────── → ──────────────────────────────
POST /api/claude/config (新增)    → test_claude_config_create_success
                                  → test_claude_config_invalid_params
ClaudeService.sendMessage (修改)  → test_send_message_with_new_agent_param
ChatPanel.vue drag (修复 BUG)     → test_chat_panel_drag_persistence
```

### 3. 变更覆盖率验证

返回信封中**必须**包含 `change_coverage` 字段：

```json
{
  "change_coverage": {
    "change_points": ["POST /api/claude/config", "ClaudeService.sendMessage", "ChatPanel.vue:handleDrag"],
    "tested_points": ["POST /api/claude/config", "ClaudeService.sendMessage", "ChatPanel.vue:handleDrag"],
    "coverage_pct": 100,
    "untested_points": []
  }
}
```

**门禁**: `coverage_pct` ≥ 80%。未覆盖的变更点必须在 `untested_points` 中说明原因。

## 需求追溯矩阵

每个测试用例**必须**追溯到 Phase 1 确认的具体需求点：

1. 读取 `phase-1-requirements.json` 中的 `requirements_summary` 和 `decisions[]`
2. 为每个需求点分配唯一标识（REQ-N.M 格式）
3. 每个测试用例必须包含追溯注释：

```python
# pytest 格式
@allure.link("REQ-1.1", name="用户登录功能")
def test_user_login():
    ...

# Playwright 格式
test('用户登录', async ({ page }) => {
  // Traces: REQ-1.1 用户登录功能
  ...
});
```

4. 追溯覆盖率要求：≥ 80%（每个需求点至少有 1 个测试用例）

## 并行执行模式

当以并行模式执行时，子 Agent 仅负责**一种测试类型**：

- 测试类型：`{test_type}`（由控制器分配）
- 只创建该类型的测试文件
- 其他类型由其他并行子 Agent 负责
- 仍需遵守追溯矩阵要求

## 测试文件创建

必须为 `config.test_suites` 中定义的每种 type 创建测试文件：

{for each suite in config.test_suites where suite.type in config.phases.testing.gate.required_test_types}

- **{suite_name}**（≥{min_test_count_per_type} 个用例）
  - 命令: `{suite.command}`
  - 目录: {从 project_structure.test_dirs 获取}
{end for}

## 测试凭据

{if config.project_context.test_credentials.username 非空}

- 用户名: {test_credentials.username}
- 密码: {test_credentials.password}
- 登录端点: {test_credentials.login_endpoint}
{else}
- 未配置，请从项目的 application.yml / .env 中读取
{end if}

## Playwright 登录流程

{if config.project_context.playwright_login.steps 非空}
{playwright_login.steps}
已知 data-testid: {playwright_login.known_testids}
{else}

- 未配置，请从 Login 组件中读取 data-testid 属性推导
{end if}

## Dry-run 验证

创建测试文件后必须执行语法检查：
{for each suite in config.test_suites}

- {suite_name}: 对应的 dry-run / --collect-only / --list 命令
{end for}

## 不可变原则

1. 测试创建后绝对禁止修改以通过测试
2. 测试失败仅修改实现代码
3. 发现测试设计缺陷 → 新增补充测试，不修改原有

## 返回要求

status 只允许 "ok" 或 "blocked"（Phase 4 不接受 warning）。
必须包含 `test_counts`、`artifacts`、`dry_run_results`、`test_pyramid` 字段。

- 必须包含 `test_traceability` 字段（需求追溯映射）
- 必须包含 `change_coverage` 字段（变更聚焦覆盖率）
- 必须包含 `sad_path_counts` 字段（异常分支用例统计）

```json
{
  "test_counts": { "unit": 10, "api": 6, "e2e": 4, "ui": 3 },
  "sad_path_counts": { "unit": 4, "api": 3, "e2e": 2, "ui": 1 },
  "test_traceability": [
    { "test": "test_user_login", "requirement": "REQ-1.1 用户登录" },
    { "test": "test_create_space", "requirement": "REQ-2.1 创建工作空间" }
  ],
  "change_coverage": {
    "change_points": ["POST /api/claude/config", "ChatPanel.vue:handleDrag"],
    "tested_points": ["POST /api/claude/config", "ChatPanel.vue:handleDrag"],
    "coverage_pct": 100,
    "untested_points": []
  }
}
```

**Sad Path 门禁规则**: `sad_path_counts` 中每种测试类型的异常分支用例数 ≥ `test_counts` 同类型总数的 20%。
异常分支包括：错误输入、权限不足、资源不存在、超时、并发冲突、网络异常等场景。
