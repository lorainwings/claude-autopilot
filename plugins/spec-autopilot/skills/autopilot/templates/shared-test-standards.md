# 共享测试标准（内置模板）

> 此模板由插件内置提供，Phase 4 和 Phase 5 子 Agent 共同引用。

## 测试凭据使用规范

{if config.project_context.test_credentials}
所有测试必须使用配置中的凭据：
- 用户名: {test_credentials.username}
- 密码: {test_credentials.password}
- 登录端点: {test_credentials.login_endpoint}

禁止使用不存在的占位用户。
{end if}

## Playwright 登录流程

{if config.project_context.playwright_login.steps}
登录流程必须按如下步骤：
{playwright_login.steps}

已知 data-testid: {playwright_login.known_testids}
{end if}

## 测试金字塔约束

{if config.test_pyramid}
- 单元测试 ≥ 总用例数的 {min_unit_pct}%
- E2E+UI ≤ 总用例数的 {max_e2e_pct}%
- 总用例数 ≥ {min_total_cases}
{end if}
