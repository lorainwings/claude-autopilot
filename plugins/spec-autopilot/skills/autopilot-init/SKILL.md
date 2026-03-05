---
name: autopilot-init
description: "Initialize autopilot config by scanning project structure. Auto-detects tech stack, services, and test suites to generate .claude/autopilot.config.yaml."
argument-hint: "[可选: 项目根目录路径]"
---

# Autopilot Init — 项目配置初始化

扫描项目结构，自动检测技术栈和服务，生成 `.claude/autopilot.config.yaml`。

## 执行流程

### Step 1: 检测项目结构

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

### Step 2: 检测服务端口

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

### Step 2.5: 检测项目上下文（新增）

从项目中提取子 Agent 运行所需的项目特定数据：

#### 2.5.1 测试凭据检测

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

#### 2.5.2 项目结构检测

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

#### 2.5.3 Playwright 登录流程检测（当检测到 Playwright 时）

```
检测规则:
  1. Glob 搜索 Login.vue / LoginPage.tsx / login.* 组件
  2. 提取所有 data-testid 属性值
  3. 分析登录表单结构（是否有 OAuth 切换、密码/验证码模式切换）
  4. 生成 playwright_login_flow 描述

产出: config.project_context.playwright_login 字段
```

**未检测到的字段**：标记为空字符串，Step 4 中通过 AskUserQuestion 提示用户补充。

### Step 2.6: 安全工具检测（v2.4.0 新增）

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

### Step 3: 生成配置

根据检测结果生成 YAML 配置，模板如下:

```yaml
version: "1.0"

services:
  # 自动检测到的服务
  backend:
    health_url: "http://localhost:{detected_port}/actuator/health"
    name: "后端服务"
  frontend:
    health_url: "http://localhost:{detected_port}/"
    name: "前端服务"

phases:
  requirements:
    agent: "business-analyst"
    min_qa_rounds: 1
    mode: "structured"         # structured | socratic (苏格拉底模式深化需求)
    auto_scan:
      enabled: true
      max_depth: 2
    research:
      enabled: true
      agent: "Explore"
      web_search:
        enabled: true            # standard/deep depth 默认 true，basic 自动跳过
        max_queries: 5           # 最大搜索次数
        focus_areas:             # 搜索聚焦领域
          - best_practices
          - similar_implementations
          - dependency_evaluation
    complexity_routing:
      enabled: true
      thresholds:
        small: 2
        medium: 5
  testing:
    agent: "qa-expert"
    instruction_files: []      # 可选：项目自定义指令覆盖插件内置规则
    reference_files: []        # 可选：项目自定义参考文件
    gate:
      min_test_count_per_type: 5
      required_test_types: [unit, api, e2e, ui]
  implementation:
    instruction_files: []      # 可选：项目自定义指令覆盖插件内置规则
    ralph_loop:
      enabled: true
      max_iterations: 30
      fallback_enabled: true
    worktree:
      enabled: false         # 设为 true 启用 Phase 5 worktree 隔离
    parallel:
      enabled: false         # 设为 true 启用 Phase 5 并行 Agent Team 执行
      max_agents: 3          # 最大并行 Agent 数量（建议 2-4）
      dependency_analysis: true  # 自动分析 task 依赖关系
  reporting:
    instruction_files: []      # 可选：项目自定义指令覆盖插件内置规则
    format: "allure"         # allure | custom
    report_commands:
      html: "python tools/report/html_generator.py -i {change_name}"
      markdown: "python tools/report/generator.py -i {change_name}"
      allure_generate: "npx allure generate allure-results -o allure-report --clean"
    coverage_target: 80
    zero_skip_required: true
  code_review:
    enabled: true              # Phase 6.5 代码审查（默认启用）
    auto_fix_minor: false      # 是否自动修复 minor findings
    block_on_critical: true    # critical findings 是否阻断
    skip_patterns:             # 跳过审查的文件模式
      - "*.md"
      - "*.json"
      - "openspec/**"

test_pyramid:
  min_unit_pct: 50           # 单元测试最低占比（金字塔底层）
  max_e2e_pct: 20            # E2E+UI 测试最高占比（金字塔顶层）
  min_total_cases: 20        # 最少总用例数

gates:
  user_confirmation:
    after_phase_1: true      # 需求确认后暂停，让用户审查
    after_phase_3: false     # 设计生成后自动继续
    after_phase_4: false     # 测试设计后自动继续

context_management:
  git_commit_per_phase: true # 每 Phase 完成后自动 git commit checkpoint
  autocompact_pct: 80        # 建议设置 CLAUDE_AUTOCOMPACT_PCT_OVERRIDE
  squash_on_archive: true    # Phase 7 归档时 autosquash fixup commits 为单一 commit

brownfield_validation:
  enabled: false               # 存量项目手动开启漂移检测
  strict_mode: false           # true: block; false: warning only
  ignore_patterns: ["*.test.*", "*.spec.*", "__mocks__/**"]

async_quality_scans:
  timeout_minutes: 10          # 硬超时（分钟），超时后标记 timeout 继续后续步骤
  contract_testing:
    check_command: ""            # 工具检测命令（缺失则自动安装）
    install_command: ""          # 自动安装命令
    command: ""                  # 执行命令
    threshold: "all_pass"
  performance_audit:
    check_command: "npx lhci --version"
    install_command: "pnpm add -D @lhci/cli"
    command: "npx lhci autorun"
    threshold: 80
  visual_regression:
    check_command: ""
    install_command: ""
    command: ""
    threshold: "0_diff"
  mutation_testing:
    check_command: ""
    install_command: ""
    command: ""
    threshold: 60
  security_audit:                    # v2.4.0 新增：安全审计扫描
    check_command: "bash ${CLAUDE_PLUGIN_ROOT}/scripts/check-security-tools-install.sh"
    install_command: ""              # 由检测脚本的 install_commands 动态提供
    command: ""                      # 由检测脚本的 recommended_scans 动态决定
    threshold: "0_critical"          # 0 个 critical 漏洞
    block_on_critical: false         # true: critical 发现阻断归档

# === 代码约束（v2.4.0 新增，可选）===
# code_constraints:
#   forbidden_files: []              # 禁止创建的文件（如 vite.config.js）
#   forbidden_patterns: []           # 禁止出现在代码中的模式
#   max_file_lines: 800              # 单文件最大行数
#   allowed_dirs: []                 # 允许修改的目录范围

test_suites:
  # 自动检测到的测试套件

# === 项目上下文（自动检测，dispatch 动态注入子 Agent prompt） ===
project_context:
  project_structure:
    backend_dir: "{detected}"      # 如 "backend"
    frontend_dir: "{detected}"     # 如 "frontend/web-app"
    node_dir: "{detected}"         # 如 "node"，无则为空
    test_dirs:
      unit: "{detected}"           # 如 "backend/src/test/java"
      api: "{detected}"            # 如 "tests/api"
      e2e: "{detected}"            # 如 "tests/e2e"
      ui: "{detected}"             # 如 "tests/ui"

  test_credentials:                # 测试凭据（dispatch 自动注入，无需 reference 文件）
    username: "{detected}"         # 从 .env/conftest.py/fixtures 检测
    password: "{detected}"         # 未检测到则提示用户填写
    login_endpoint: "{detected}"   # 如 "POST /api/auth/login"

  playwright_login:                # Playwright 登录流程（检测到 Playwright 时生成）
    steps: |
      # 自动检测的登录步骤（从 Login 组件的 data-testid 推导）
      # 示例:
      # 1. goto /#/login
      # 2. click [data-testid="switch-password-login"]
      # 3. fill [data-testid="username"]
      # 4. fill [data-testid="password"]
      # 5. click [data-testid="login-btn"]
      # 6. waitForURL /#/dashboard
    known_testids: []              # 从 Login 组件扫描到的 data-testid 列表
```

### Step 4: 用户确认

通过 AskUserQuestion 展示生成的配置摘要：

```
"已检测到以下项目结构，生成了 autopilot 配置:"

检测结果:
- 后端: {tech_stack} (port {port})
- 前端: {framework} (port {port})
- 测试: {test_frameworks}
- 测试凭据: {username}/{检测状态}
- 项目结构: {backend_dir}, {frontend_dir}, {node_dir}

选项:
- "确认写入 (Recommended)" → 写入 .claude/autopilot.config.yaml
- "需要调整" → 展示完整 YAML 让用户修改后再写入
```

#### 4.1 未检测到的字段补充

对 `project_context` 中值为空的字段，逐个通过 AskUserQuestion 提示用户补充：

```
IF test_credentials.username 为空:
  AskUserQuestion: "未检测到测试凭据。请提供测试账号用户名（或跳过，后续由 Phase 1 自动发现）："
  选项: "输入凭据" / "跳过，由 Phase 1 自动发现 (Recommended)"

IF playwright_login.steps 为空 且检测到 Playwright:
  AskUserQuestion: "未检测到 Playwright 登录流程。请选择处理方式："
  选项: "由 Phase 1 Auto-Scan 自动发现 (Recommended)" / "手动描述登录流程"
```

> **降级策略**：所有 `project_context` 字段均为可选。未填写的字段由 Phase 1 的 Auto-Scan + Research Agent 在运行时自动发现，不阻断 init 流程。

### Step 5: 写入配置

将配置写入 `.claude/autopilot.config.yaml`。

如果文件已存在 → AskUserQuestion 确认是否覆盖。

### Step 5.5: LSP 插件推荐

根据检测到的技术栈，推荐安装对应的 Claude Code LSP 插件以提升代码编辑质量。

#### 推荐映射表

| 检测到的技术栈 | 推荐的 LSP 插件 | 安装命令 |
|---------------|---------------|---------|
| Java/Gradle 或 Java/Maven | `jdtls-lsp` | `claude plugin install jdtls-lsp@claude-plugins-official` |
| TypeScript/Vue/React | `typescript-lsp` | `claude plugin install typescript-lsp@claude-plugins-official` |
| Python | `pyright-lsp` | `claude plugin install pyright-lsp@claude-plugins-official` |
| Rust | `rust-analyzer-lsp` | `claude plugin install rust-analyzer-lsp@claude-plugins-official` |
| Go | `gopls-lsp` | `claude plugin install gopls-lsp@claude-plugins-official` |
| Kotlin | `kotlin-lsp` | `claude plugin install kotlin-lsp@claude-plugins-official` |
| PHP | `php-lsp` | `claude plugin install php-lsp@claude-plugins-official` |
| Swift | `swift-lsp` | `claude plugin install swift-lsp@claude-plugins-official` |
| C/C++ | `clangd-lsp` | `claude plugin install clangd-lsp@claude-plugins-official` |

#### 检测逻辑

```
detected_stacks = []  # 从 Step 1 的检测结果中获取

LSP_MAP = {
  "java": {"name": "jdtls-lsp", "desc": "Java 语言服务支持"},
  "typescript": {"name": "typescript-lsp", "desc": "实时类型检查和自动补全"},
  "python": {"name": "pyright-lsp", "desc": "Python 类型检查和智能提示"},
  "rust": {"name": "rust-analyzer-lsp", "desc": "Rust 语言服务"},
  "go": {"name": "gopls-lsp", "desc": "Go 语言服务"},
  ...
}

lsp_recommendations = []
for stack in detected_stacks:
  if stack in LSP_MAP:
    lsp = LSP_MAP[stack]
    # 检查 .claude/settings.json 中 enabledPlugins 是否已包含该 LSP
    installed = check_plugin_installed(lsp["name"])
    if not installed:
      lsp_recommendations.append(lsp)
```

#### 用户交互

如果有推荐的 LSP 插件且未安装，通过 AskUserQuestion 展示：

```
"检测到以下技术栈可以安装 LSP 插件以提升代码编辑质量："

推荐列表:
- TypeScript LSP — 提供实时类型检查和自动补全
- Java JDTLS — 提供 Java 语言服务支持

选项:
- "全部安装 (Recommended)" → 逐个执行安装命令
- "选择性安装" → 展示多选列表
- "跳过，稍后手动安装" → 继续后续步骤
```

#### 写入配置

安装的 LSP 插件信息记录到配置的 `lsp_plugins` 字段（信息性，不影响功能）：

```yaml
lsp_plugins:                    # 信息性字段，记录已推荐的 LSP 插件
  - name: typescript-lsp
    status: installed            # installed | skipped | failed
  - name: jdtls-lsp
    status: skipped
```

> LSP 推荐是可选步骤，跳过不影响配置生成和 autopilot 功能。

### Step 6: Schema 验证

写入后**必须**验证配置完整性，检查以下必须存在的 key：

```
必须的顶级 key:
  - version (string)
  - services (object, 至少一个服务)
  - phases (object)
  - test_suites (object, 至少一个套件)

phases 内必须的 key:
  - phases.requirements.agent (string)
  - phases.testing.agent (string)
  - phases.testing.gate.min_test_count_per_type (number, >= 1)
  - phases.testing.gate.required_test_types (array, non-empty)
  - phases.implementation.ralph_loop.enabled (boolean)
  - phases.implementation.ralph_loop.max_iterations (number, >= 1)
  - phases.implementation.ralph_loop.fallback_enabled (boolean)
  - phases.reporting.coverage_target (number, 0-100)
  - phases.reporting.zero_skip_required (boolean)

每个 service 必须有:
  - health_url (string, 以 http:// 或 https:// 开头)

每个 test_suite 必须有:
  - command (string, non-empty)
  - type (string, one of: unit, integration, e2e, ui, typecheck)
  - allure (string, one of: pytest, playwright, junit_xml, none)
  - allure_post (string, optional, only when allure=junit_xml)
```

如果校验失败 → 输出缺失/错误的 key 列表，AskUserQuestion 要求用户修正后重试。

## 检测规则

### test_suites 自动推导

| 检测到 | 生成的 test_suite |
|--------|-------------------|
| `build.gradle` + `src/test/` | `backend_unit: { command: "cd backend && ./gradlew test", type: unit, allure: junit_xml, allure_post: "cp -r backend/build/test-results/test/*.xml \"$ALLURE_RESULTS_DIR/\" 2>/dev/null \|\| true" }` |
| `pytest.ini` 或 `conftest.py` | `api_test: { command: "python3 -m pytest tests/api/ -v", type: integration, allure: pytest }` |
| `playwright.config.ts` | `e2e: { command: "npx playwright test", type: e2e, allure: playwright }` |
| `vitest.config.*` | `unit: { command: "npx vitest run", type: unit, allure: none }` |
| `jest.config.*` | `unit: { command: "npx jest", type: unit, allure: none }` |
| 前端 `package.json` 有 `type-check` | `typecheck: { command: "cd frontend && pnpm type-check", type: typecheck, allure: none }` |
| Node `tsconfig.json` | `node_typecheck: { command: "cd node && npx tsc --noEmit", type: typecheck, allure: none }` |

### report_commands 自动推导

| 检测到 | 生成的命令 |
|--------|-----------|
| `tools/report/html_generator.py` | `html: "python tools/report/html_generator.py -i {change_name}"` |
| `tools/report/generator.py` | `markdown: "python tools/report/generator.py -i {change_name}"` |
| 都不存在 | `report_commands: {}` 并提示用户配置 |

## 幂等性

多次运行不会破坏已有配置。已存在时必须用户确认才能覆盖。
