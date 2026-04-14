# Setup 检测规则 — 项目结构自动发现

> 本文件由 `autopilot-setup/SKILL.md` 通过 `**执行前读取**` 引用。
> 包含 Step 1 ~ Step 2.6 的完整检测逻辑和推导规则。

## Step 1: 检测项目结构

使用 Glob 和 Read 扫描以下模式：

```
检测后端:
  - build.gradle / build.gradle.kts → Java/Gradle
  - pom.xml → Java/Maven
  - go.mod → Go
  - Cargo.toml → Rust
  - requirements.txt / pyproject.toml → Python

检测前端:
  - frontend/*/package.json 或 package.json → 读取 scripts 字段
  - 检测框架: vue/react/angular (从 dependencies)
  - 检测包管理器: pnpm-lock.yaml / yarn.lock / package-lock.json

检测 Node 服务:
  - node/package.json → 读取 scripts 字段
  - ecosystem.config.js → PM2 配置

检测测试:
  - tests/ / test/ / __tests__/ 目录结构
  - playwright.config.ts → Playwright
  - pytest.ini / conftest.py → pytest
  - jest.config.* → Jest
  - vitest.config.* → Vitest
```

## Step 2: 检测服务端口

从以下文件提取服务端口:

```
后端:
  - application.yml / application.properties → server.port
  - .env → PORT

前端:
  - vite.config.ts → server.port
  - package.json scripts 中的 --port 参数

Node:
  - .env → PORT
  - ecosystem.config.js → env.PORT
```

## Step 2.5: 检测项目上下文

从项目中提取子 Agent 运行所需的项目特定数据：

### 2.5.1 测试凭据检测

```
检测顺序（找到即停）:
  1. application.yml / application.properties → 提取 spring.datasource 配置
  2. .env / .env.test → 提取 TEST_USERNAME / TEST_PASSWORD
  3. tests/ 目录下搜索 conftest.py / fixtures 中的 login 函数
  4. 前端 Login.vue / login.tsx 组件分析登录流程

产出 test_credentials 配置:
  username: <检测到的测试用户名，未检测到则留空提示用户>
  password: <检测到的测试密码，未检测到则留空提示用户>
  login_endpoint: <从 Router/Controller 注解推导，如 "POST /api/auth/login">
```

### 2.5.2 项目结构检测

```
检测规则:
  backend_dir: 找到 build.gradle/pom.xml 的目录（如 "backend"）
  frontend_dir: 找到前端 package.json 的目录（如 "frontend/web-app"）
  node_dir: 找到 Node 服务 package.json 的目录（如 "node"）
  test_dirs:
    unit: 找到 src/test/ 的路径
    api: 找到 tests/api/ 或 test/api/ 的路径
    e2e: 找到 tests/e2e/ 或 含 playwright.config 的目录
    ui: 找到 tests/ui/ 的路径
```

### 2.5.3 Playwright 登录流程检测（当检测到 Playwright 时）

```
检测规则:
  1. Glob 搜索 Login.vue / LoginPage.tsx / login.* 组件
  2. 提取所有 data-testid 属性值
  3. 分析登录表单结构（是否有 OAuth 切换、密码/验证码模式切换）
  4. 生成 playwright_login_flow 描述

产出: config.project_context.playwright_login 字段
```

**未检测到的字段**：标记为空字符串，Step 4 中通过 AskUserQuestion 提示用户补充。

## Step 2.6: 安全工具检测

运行 `bash <plugin_scripts>/check-security-tools-install.sh "$(pwd)"`，检测已安装的安全扫描工具。

```
检测结果处理:
  IF recommended_scans 非空:
    → 生成 async_quality_scans.security_audit 配置节
    → command 字段根据 recommended_scans 动态拼接
  IF recommended_scans 为空:
    → 不生成 security_audit 节（不强制安装安全工具）
    → 在 Step 4 展示提示："未检测到安全扫描工具，建议安装 gitleaks 和 trivy"
```

## test_suites 自动推导规则

| 检测到 | 生成的 test_suite |
|--------|-------------------|
| `build.gradle` + `src/test/` | `backend_unit: { command: "cd backend && ./gradlew test", type: unit, allure: junit_xml, allure_post: "cp -r backend/build/test-results/test/*.xml \"$ALLURE_RESULTS_DIR/\" 2>/dev/null \|\| true" }` |
| `pytest.ini` 或 `conftest.py` | `api_test: { command: "python3 -m pytest tests/api/ -v", type: integration, allure: pytest }` |
| `playwright.config.ts` | `e2e: { command: "npx playwright test", type: e2e, allure: playwright }` |
| `vitest.config.*` | `unit: { command: "npx vitest run", type: unit, allure: none }` |
| `jest.config.*` | `unit: { command: "npx jest", type: unit, allure: none }` |
| 前端 `package.json` 有 `type-check` | `typecheck: { command: "cd frontend && pnpm type-check", type: typecheck, allure: none }` |
| Node `tsconfig.json` | `node_typecheck: { command: "cd node && npx tsc --noEmit", type: typecheck, allure: none }` |

## report_commands 自动推导规则

| 检测到 | 生成的命令 |
|--------|-----------|
| `tools/report/html_generator.py` | `html: "python tools/report/html_generator.py -i {change_name}"` |
| `tools/report/generator.py` | `markdown: "python tools/report/generator.py -i {change_name}"` |
| 都不存在 | `report_commands: {}` 并提示用户配置 |
