---
name: autopilot-setup
description: "Initialize autopilot config by scanning project structure. Auto-detects tech stack, services, and test suites to generate .claude/autopilot.config.yaml."
argument-hint: "[可选: 项目根目录路径]"
---

# Autopilot Setup — 项目配置初始化

扫描项目结构，自动检测技术栈和服务，生成 `.claude/autopilot.config.yaml`。

## 快速启动模式（Interactive Wizard）

当用户首次使用或传入 `--interactive` / `interactive` 参数时，启用引导式向导。
降低 60+ 配置项的认知负担，3 步完成配置。

### Wizard Step 1: 选择预设模板

通过 AskUserQuestion 展示 3 个预设：

```
"欢迎使用 autopilot！请选择质量门禁级别："

选项:
- "Strict (推荐生产项目)" →
    门禁严格：测试金字塔 unit≥50%/e2e≤20%，TDD 模式，Phase 4 必须 ok（不接受 warning），
    代码审查启用且 critical 阻断，零跳过强制，覆盖率 80%

- "Moderate (推荐日常开发)" →
    门禁适中：测试金字塔 unit≥30%/e2e≤40%，无 TDD，Phase 4 标准门禁，
    代码审查启用但不阻断，覆盖率 60%

- "Relaxed (快速原型)" →
    门禁宽松：minimal 执行模式，无测试金字塔强制，无代码审查，
    覆盖率 40%，适合 PoC/原型验证
```

### Wizard Step 2: 确认自动检测

运行标准 Step 1-2.6 的自动检测流程（同下方"执行流程"），展示检测结果摘要。
用户确认或调整后继续。

### Wizard Step 3: 应用预设 + 写入

将预设模板值覆盖到自动检测结果上，生成最终配置。

预设模板映射：

```yaml
# --- Strict 预设 ---
strict:
  default_mode: "full"
  model_strategy: "quality_max"  # 质量优先模型路由
  phases.implementation.tdd_mode: true
  phases.implementation.tdd_refactor: true
  phases.reporting.coverage_target: 80
  phases.reporting.zero_skip_required: true
  phases.code_review.enabled: true
  phases.code_review.block_on_critical: true
  test_pyramid.min_unit_pct: 50
  test_pyramid.max_e2e_pct: 20
  test_pyramid.min_total_cases: 20
  gates.user_confirmation.after_phase_1: false
  gates.user_confirmation.after_phase_3: false
  gates.auto_continue_after_requirement: true
  gates.archive_auto_on_readiness: true

# --- Moderate 预设 ---
moderate:
  default_mode: "full"
  model_strategy: "balanced"     # 平衡模型路由
  phases.implementation.tdd_mode: false
  phases.reporting.coverage_target: 60
  phases.reporting.zero_skip_required: true
  phases.code_review.enabled: true
  phases.code_review.block_on_critical: false
  test_pyramid.min_unit_pct: 30
  test_pyramid.max_e2e_pct: 40
  test_pyramid.min_total_cases: 10
  gates.user_confirmation.after_phase_1: false
  gates.user_confirmation.after_phase_3: false
  gates.auto_continue_after_requirement: true
  gates.archive_auto_on_readiness: true

# --- Relaxed 预设 ---
relaxed:
  default_mode: "minimal"
  model_strategy: "cost_optimized"  # 省钱优先模型路由
  phases.implementation.tdd_mode: false
  phases.reporting.coverage_target: 40
  phases.reporting.zero_skip_required: false
  phases.code_review.enabled: false
  phases.code_review.block_on_critical: false
  test_pyramid.min_unit_pct: 20
  test_pyramid.max_e2e_pct: 60
  test_pyramid.min_total_cases: 5
  gates.user_confirmation.after_phase_1: false
  gates.user_confirmation.after_phase_3: false
  gates.auto_continue_after_requirement: true
  gates.archive_auto_on_readiness: true
```

### Wizard 完成后输出

```
✓ autopilot 配置已生成: .claude/autopilot.config.yaml
  预设: {preset_name} | 模式: {default_mode} | TDD: {on/off}
  Agent: {agent_summary} | 模型策略: {model_strategy}
  测试套件: {N} 个 | 服务: {N} 个

  快速开始: 输入 /autopilot <需求描述>
  调整 Agent: /autopilot-agents [install|list|swap|recommend]
  调整模型: /autopilot-models [cost|balanced|quality]
  调整配置: 编辑 .claude/autopilot.config.yaml
```

> **非 Wizard 模式**: 不传 `--interactive` 时，行为与原有 Step 1-6 完全一致（向后兼容）。

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

**读取模板**: `autopilot/references/config-schema.md`（完整 YAML 配置模板）

根据 Step 1-2 的检测结果，按 `config-schema.md` 中的模板生成配置文件。所有 `{detected}` 占位符替换为实际检测值。

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

### Step 5.3: Agent 安装引导

检查 `.claude/agents/` 是否已安装 autopilot 推荐的专业 Agent：

```
IF .claude/agents/ 下存在 analyst.md / executor.md / code-reviewer.md 等:
  → 输出 "✓ 已检测到 {N} 个专业 Agent"
  → 跳过本步骤

ELSE:
  AskUserQuestion: "autopilot 支持安装专业 Agent 以提升各阶段效果。是否安装？"
  选项:
  - "安装推荐 Agent (Recommended)" → 调用 Skill("spec-autopilot:autopilot-agents" "install")
  - "跳过，稍后手动安装" → 继续后续步骤
```

> Agent 安装是可选步骤，跳过不影响 autopilot 功能。未安装专业 Agent 时使用内置 general-purpose。

### Step 5.4: 模型路由引导

检查 config 中 `model_routing` 是否已有完整的 per-phase 配置：

```
IF config.model_routing.phases 已有 7 个 phase 配置:
  → 输出当前策略摘要
  → 跳过本步骤

ELSE:
  AskUserQuestion: "是否配置模型路由策略？（影响成本和质量）"
  选项:
  - "配置模型路由 (Recommended)" → 调用 Skill("spec-autopilot:autopilot-models")
  - "使用默认路由" → 跳过（使用 resolve-model-routing.sh 的内置默认值）
```

> 模型路由配置是可选步骤。跳过时使用内置默认路由（Phase 1/5: opus, Phase 4: sonnet, 其余: haiku）。

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

**读取规则**: `autopilot/references/config-schema.md`（Schema 验证规则章节）

写入后**必须**按 `config-schema.md` 中的 schema 验证配置完整性。校验失败 → 输出缺失/错误的 key 列表，AskUserQuestion 要求用户修正后重试。

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
