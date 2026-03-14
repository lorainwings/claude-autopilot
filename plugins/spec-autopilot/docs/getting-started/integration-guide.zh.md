> [English](integration-guide.md) | 中文

# 项目接入指南

> 本指南以一个全新项目为例，详细描述如何接入 spec-autopilot 插件并完成首次全自动交付。

## 前置条件

| 条件 | 要求 | 检查命令 |
|------|------|----------|
| Claude Code | v1.0.0+ | `claude --version` |
| python3 | 3.8+（Hook 脚本依赖） | `python3 --version` |
| git | 任意版本 | `git --version` |
| bash | 4.0+（macOS 需 brew 安装） | `bash --version` |

### 可选依赖

| 依赖 | 用途 | 安装 |
|------|------|------|
| openspec 插件 | Phase 2-3 规范生成（**必需**） | `claude plugin install openspec` |
| PyYAML | 配置验证的精确解析 | `pip3 install pyyaml` |
| Allure | 统一测试报告 | `npm install -g allure-commandline` |

---

## 接入流程

### Step 1: 安装插件

```bash
# 添加市场（仅需一次）
claude plugin marketplace add lorainwings/claude-autopilot

# 安装到项目（推荐）
claude plugin install spec-autopilot@lorainwings-plugins --scope project

# 或安装到用户级别（所有项目共享）
claude plugin install spec-autopilot@lorainwings-plugins --scope user
```

安装 openspec 依赖（如未安装）：

```bash
claude plugin install openspec --scope project
```

验证安装：

```bash
claude plugin list
# 应看到:
#   spec-autopilot@lorainwings-plugins (project)
#   openspec (project)
```

### Step 2: 重启 Claude Code

```bash
# 退出当前会话
exit

# 重新启动
claude
```

### Step 3: 生成项目配置（一步完成）

在 Claude Code 中执行：

```
/spec-autopilot:autopilot-init
```

或直接触发 autopilot（配置不存在时自动调用 init）：

```
启动autopilot
```

Init 会自动检测并生成 `.claude/autopilot.config.yaml`：
- 技术栈（Java/Spring Boot、Vue/React、Python、Go 等）
- 服务端口（从 application.yml / vite.config.ts / .env 提取）
- 测试框架（JUnit、pytest、Playwright、Vitest 等）
- 构建工具（Gradle、Maven、pnpm、npm 等）
- **测试凭据**（从 .env / conftest.py / application.yml 检测）
- **项目结构**（backend/frontend/node/test 目录路径）
- **Playwright 登录流程**（从 Login 组件的 data-testid 推导）

> **无需手动创建指令文件**。dispatch 从 config 的 `project_context` + `test_suites` + `services` 动态构造子 Agent prompt。Phase 1 的 Auto-Scan 在运行时补充未检测到的项目上下文。

### Step 4: 审查配置

确认生成的 config 中以下关键项正确：

```yaml
# 必须确认的核心字段
services:
  backend:
    health_url: "http://localhost:8080/actuator/health"  # 端口是否正确？

test_suites:
  backend_unit:
    command: "cd backend && ./gradlew test"               # 命令是否正确？
  # ... 其他套件

project_context:
  test_credentials:
    username: "dev"        # 测试账号是否正确？空则由 Phase 1 发现
    password: "password"
  project_structure:
    backend_dir: "backend" # 目录是否正确？
```

运行配置验证：

```bash
bash ~/.claude/plugins/cache/lorainwings-plugins/spec-autopilot/*/scripts/validate-config.sh
```

### Step 5:（可选）高级自定义

对于有特殊需求的项目，可以通过 `instruction_files` 覆盖插件内置规则：

```yaml
# autopilot.config.yaml — 仅在插件内置规则不满足时使用
phases:
  testing:
    instruction_files:
      - ".claude/autopilot/custom-testing.md"   # 自定义测试要求
    reference_files:
      - ".claude/autopilot/custom-reference.md" # 自定义参考文件
```

> 大多数项目**不需要**自定义指令文件。config 中的 `project_context` + `test_suites` 已提供足够的项目上下文。

### Step 6: 初始化 OpenSpec 目录

确保项目根目录存在 `openspec/` 结构：

```bash
mkdir -p openspec/changes openspec/archive openspec/specs
```

如果项目使用 OpenSpec 插件，目录通常已自动创建。

### Step 7: 验证安装

在 Claude Code 中执行快速验证：

```
# 1. 检查插件加载
claude plugin list

# 2. 检查配置有效
# （启动 autopilot 时会自动验证）

# 3. 检查 Hook 注册
# 查看 .claude/settings.json 的 hooks 部分应包含 spec-autopilot 相关条目
```

### Step 7.5: 启动 GUI 大盘 (v5.0.8, 可选)

GUI 大盘提供实时可视化执行状态和门禁交互界面。

**前置条件**:
- [Bun](https://bun.sh) 运行时 (`curl -fsSL https://bun.sh/install | bash`)

**启动命令**:

```bash
# 启动双模服务器 (HTTP:9527 + WebSocket:8765)
bun run plugins/spec-autopilot/scripts/autopilot-server.ts
```

打开 `http://localhost:9527` 即可查看三栏布局大盘。当门禁阻断时，GUI 提供 retry / fix / override 决策按钮。

> GUI 为可选组件。不启动 GUI 时，autopilot 完全通过 CLI 交互，功能不受影响。

---

## 首次运行

### 触发方式

在 Claude Code 中使用以下任一触发词：

```
全自动开发流程
一键从需求到交付
启动autopilot
```

或带参数启动：

```
启动autopilot 实现用户登录功能，包含手机号验证码登录和密码登录两种方式
```

或指向 PRD 文件：

```
启动autopilot openspec/prototypes/v1.0.0/PRD-v1.md
```

### 执行流程示意

```
Phase 0: 环境检查
├── 读取 / 生成 autopilot.config.yaml
├── 验证配置 Schema
├── 检查已启用插件列表
├── 扫描已有 checkpoint（崩溃恢复）
├── 创建 8 个阶段任务
└── 创建锚定 commit

Phase 1: 需求理解 (主线程)
├── 📋 项目上下文扫描 → Steering Documents
├── 🔍 技术调研 Agent → research-findings.md
├── 📊 复杂度评估 → small / medium / large
├── 💬 需求分析 Agent（注入 Steering + Research 上下文）
├── 🔄 多轮决策循环（AskUserQuestion）
├── ✅ 用户最终确认
└── 💾 写入 checkpoint

Phase 2-6: 子 Agent 自动执行
├── Phase 2: 创建 OpenSpec change
├── Phase 3: FF 生成所有制品
├── Phase 4: 测试用例设计（TDD 先行）
├── Phase 5: 前台 Task 串行实施
├── Phase 6: 测试报告生成
└── Phase 6.5: AI 代码审查（可选）

Phase 7: 汇总与归档 (主线程)
├── 展示状态汇总表
├── 展示执行指标
├── 收集质量扫描结果
├── AskUser 确认归档
├── Git autosquash → 整洁 commit 历史
└── 清理临时文件
```

---

## 崩溃恢复

如果 Claude Code 会话中断，重新启动后触发 autopilot 即可自动恢复：

```
启动autopilot
```

插件会：
1. 扫描 `openspec/changes/<name>/context/phase-results/` 下的 checkpoint 文件
2. 找到最后一个 `status: ok/warning` 的阶段
3. 询问用户：继续 / 清空重来
4. 从中断点继续执行

Phase 5 支持 **任务级恢复**：从最后一个完成的 task 继续，而非重新执行整个阶段。

---

## 常见配置场景

### 场景 1: 纯前端项目

```yaml
services:
  frontend:
    health_url: "http://localhost:3000/"

phases:
  testing:
    gate:
      required_test_types: [unit, e2e]  # 去掉 api 和 ui
      min_test_count_per_type: 3

test_suites:
  frontend_unit:
    command: "pnpm test"
    type: unit
    allure: none
  e2e:
    command: "npx playwright test"
    type: e2e
    allure: playwright
  typecheck:
    command: "pnpm type-check"
    type: typecheck
    allure: none
```

### 场景 2: Python 后端项目

```yaml
services:
  backend:
    health_url: "http://localhost:8000/health"

phases:
  requirements:
    agent: "business-analyst"
  testing:
    agent: "qa-expert"
    gate:
      required_test_types: [unit, api, e2e]
      min_test_count_per_type: 5
  implementation:
    serial_task:
      max_retries_per_task: 3
  reporting:
    format: "custom"
    report_commands:
      html: "python3 -m pytest --html=report.html --self-contained-html"

test_suites:
  unit:
    command: "python3 -m pytest tests/unit/ -v"
    type: unit
    allure: pytest
  api:
    command: "python3 -m pytest tests/api/ -v"
    type: integration
    allure: pytest
  e2e:
    command: "python3 -m pytest tests/e2e/ -v"
    type: e2e
    allure: pytest
```

### 场景 3: 全栈 Monorepo

```yaml
services:
  backend:
    health_url: "http://localhost:8080/actuator/health"
  frontend:
    health_url: "http://localhost:5173/"
  node:
    health_url: "http://localhost:3001/health/live"

phases:
  requirements:
    auto_scan:
      enabled: true
      max_depth: 3           # monorepo 需要更深扫描
    research:
      enabled: true
    complexity_routing:
      thresholds:
        small: 3              # monorepo 文件更多，调高阈值
        medium: 8
  implementation:
    parallel:
      enabled: true           # 前后端可并行实施
      max_agents: 3

test_suites:
  backend_unit:
    command: "cd backend && ./gradlew test"
    type: unit
    allure: junit_xml
  frontend_unit:
    command: "cd frontend && pnpm test"
    type: unit
    allure: none
  node_typecheck:
    command: "cd node && npx tsc --noEmit"
    type: typecheck
    allure: none
  api_test:
    command: "python3 -m pytest tests/api/ -v"
    type: integration
    allure: pytest
  e2e:
    command: "npx playwright test"
    type: e2e
    allure: playwright
```

### 场景 4: 并行执行（大型项目）

适用于模块间依赖清晰的大型项目，Phase 5 按域分组并行执行：

```yaml
phases:
  implementation:
    parallel:
      enabled: true
      max_agents: 4           # 最大并行 Agent 数（建议 2-4）
      dependency_analysis: true  # 自动分析 task 依赖关系

# 域映射（默认自动从 project_context 推导）
project_context:
  project_structure:
    backend_dir: "backend"
    frontend_dir: "frontend"
    node_dir: "node"
```

并行模式核心规则：
- 每个域严格分配 1 个 Agent，域内串行、跨域并行
- 文件所有权强制 (`unified-write-edit-check.sh` L2 阻断越权写入)
- 合并冲突 > 3 文件自动降级为串行模式

### 场景 5: Event Bus 集成

三种消费 autopilot 事件的方式：

```bash
# 方式 1: 实时监听文件 (最简单)
tail -f logs/events.jsonl | jq .

# 方式 2: WebSocket 消费 (需安装 wscat)
npx wscat -c ws://localhost:8765

# 方式 3: HTTP 查询事件 (需 GUI 服务器运行)
curl http://localhost:9527/api/events
```

事件类型一览: `phase_start`, `phase_end`, `gate_pass`, `gate_block`, `task_progress`, `decision_ack`。

> 详细事件接口定义见 [Event Bus API](../../skills/autopilot/references/event-bus-api.zh.md)。

---

## 项目接入检查清单

- [ ] Claude Code CLI 已安装
- [ ] spec-autopilot 插件已安装
- [ ] openspec 插件已安装
- [ ] `.claude/autopilot.config.yaml` 已生成（`/spec-autopilot:autopilot-init`）
- [ ] 配置验证通过（`valid: true`）
- [ ] `project_context.test_credentials` 已填写（或由 Phase 1 自动发现）
- [ ] `openspec/` 目录结构已存在
- [ ] （可选）并行模式已配置（`parallel.enabled: true`）
- [ ] （可选）`instruction_files` 自定义覆盖已配置
- [ ] （可选）GUI 大盘已启动（`bun run plugins/spec-autopilot/scripts/autopilot-server.ts`）
- [ ] （可选）Event Bus 日志目录已创建（`mkdir -p logs`，或由首次运行自动创建）
- [ ] 首次 `启动autopilot` 或 `/spec-autopilot:autopilot` 测试通过

---

## 现有项目升级指南

### 背景

spec-autopilot 持续迭代，以下为各版本升级要点。

### v4.2+: 需求路由

- Phase 1 自动分类需求为 Feature / Bugfix / Refactor / Chore
- 不同类别动态调整门禁阈值（`routing_overrides`）
- 配置无需修改，路由自动生效

### v5.0+: 并行执行

- 添加 `parallel.enabled: true` 启用 Phase 5 域级并行
- 需确认 `project_context.project_structure` 域目录配置正确
- 建议同时调整 `parallel.max_agents`（默认 8，建议 2-4）

### v5.0.8+: GUI V2 大盘

- 安装 Bun 运行时
- 启动命令: `bun run plugins/spec-autopilot/scripts/autopilot-server.ts`
- 端口: HTTP 9527 + WebSocket 8765

### v2.2: instruction_files 可选化（历史）

### 升级步骤

#### 1. 更新插件

```bash
# 在 Claude Code 中执行
claude plugin update spec-autopilot@lorainwings-plugins
```

或手动更新缓存：

```bash
# 从源码更新
cp -r ~/Coding/Huihao/claude-autopilot/plugins/spec-autopilot/. \
  ~/.claude/plugins/cache/lorainwings-plugins/spec-autopilot/2.2.0/
```

#### 2. 在 config 中添加 `project_context`

在 `autopilot.config.yaml` 的 `context_management` 和 `test_suites` 之间添加：

```yaml
project_context:
  project_structure:
    backend_dir: "backend"                    # 你的后端目录
    frontend_dir: "frontend/web-app"          # 你的前端目录
    node_dir: "node"                          # Node 服务目录（无则留空）
    test_dirs:
      unit: "backend/src/test/java/..."       # 单元测试目录
      api: "tests/api"                        # API 测试目录
      e2e: "tests/e2e"                        # E2E 测试目录
      ui: "tests/ui"                          # UI 测试目录

  test_credentials:
    username: "dev"                           # 从旧 reference/test-credentials.md 迁移
    password: "password"
    login_endpoint: "POST /api/auth/login"

  playwright_login:
    steps: |                                  # 从旧 reference/playwright-standards.md 迁移
      1. goto /#/login
      2. click [data-testid="switch-password-login"]
      3. fill [data-testid="username"]
      4. fill [data-testid="password"]
      5. click [data-testid="login-btn"]
      6. waitForURL /#/dashboard
    known_testids:
      - switch-password-login
      - username
      - password
      - login-btn
```

#### 3. 清空 instruction_files 引用（可选）

旧的指令文件引用现在是可选的。如果你已将内容迁移到 `project_context`，可以清空：

```yaml
phases:
  testing:
    instruction_files: []    # 旧: [".claude/skills/autopilot/phases/testing-requirements.md"]
    reference_files: []      # 旧: ["...test-credentials.md", "...playwright-standards.md"]
  implementation:
    instruction_files: []    # 旧: [".claude/skills/autopilot/phases/implementation-config.md"]
  reporting:
    instruction_files: []    # 旧: [".claude/skills/autopilot/phases/reporting.md"]
```

> 如果保留引用，dispatch 会同时注入 config 内容 + 指令文件内容（instruction_files 优先级更高）。

#### 4. 删除项目侧 SKILL.md 包装器（如有）

如果你之前创建了 `.claude/skills/autopilot/SKILL.md`，删除它以避免与插件命令重复：

```bash
rm .claude/skills/autopilot/SKILL.md
```

> `phases/` 和 `reference/` 目录可保留（作为 instruction_files 的可选覆盖源），也可删除（如已完全迁移到 config）。

#### 5. 验证

```bash
# 验证 config
bash ~/.claude/plugins/cache/lorainwings-plugins/spec-autopilot/*/scripts/validate-config.sh

# 重启 Claude Code 后测试
/spec-autopilot:autopilot
```

---

## 故障排查

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| "Config file not found" | 配置未生成 | 运行 `autopilot-init` 或手动创建 |
| "python3 not found" | Hook 脚本需要 python3 | `brew install python3` 或 `apt install python3` |
| "Phase N checkpoint not found" | 阶段被跳过或崩溃 | 触发 autopilot 重新运行，崩溃恢复会自动处理 |
| "Phase 5 task 连续失败" | 实施遇到阻塞 | 检查错误日志，调整 `serial_task.max_retries_per_task` |
| Hook 脚本超时 | 项目过大导致扫描慢 | 增加 Hook timeout 或减少扫描范围 |
| 测试金字塔不通过 | 测试分布不达标 | 调整测试用例数量或放宽 `test_pyramid` 阈值 |

更多故障排查详见 [troubleshooting.zh.md](../operations/troubleshooting.zh.md)。
