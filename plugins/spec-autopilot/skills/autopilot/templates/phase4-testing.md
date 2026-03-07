# Phase 4: 测试用例设计（内置模板）

> 此模板由插件内置提供。项目可通过 config.phases.testing.instruction_files 覆盖。

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

## 需求追溯矩阵（v3.2.0 新增）

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

## 并行执行模式（v3.2.0 新增）

当以并行模式执行时，你仅负责**一种测试类型**：
- 你的测试类型：`{test_type}`（由控制器分配）
- 你只需创建该类型的测试文件
- 其他类型由其他并行子 Agent 负责
- 仍需遵守追溯矩阵要求

## 测试文件创建

必须为 config.test_suites 中定义的每种 type 创建测试文件：

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
必须包含 test_counts、artifacts、dry_run_results、test_pyramid 字段。
**v3.2.0 新增**: 必须包含 `test_traceability` 字段（需求追溯映射）。

```json
{
  "test_traceability": [
    { "test": "test_user_login", "requirement": "REQ-1.1 用户登录" },
    { "test": "test_create_space", "requirement": "REQ-2.1 创建工作空间" }
  ]
}
```
