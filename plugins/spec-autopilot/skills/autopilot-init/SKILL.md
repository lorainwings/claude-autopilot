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
  testing:
    agent: "qa-expert"
    instruction_files: []    # 用户按需添加
    reference_files: []      # 用户按需添加
    gate:
      min_test_count_per_type: 5
      required_test_types: [unit, api, e2e, ui]
  implementation:
    instruction_files: []    # 用户按需添加
    ralph_loop:
      enabled: true
      max_iterations: 30
      fallback_enabled: true
    worktree:
      enabled: false         # 设为 true 启用 Phase 5 worktree 隔离
  reporting:
    instruction_files: []    # 用户按需添加
    format: "allure"         # allure | custom
    report_commands:
      html: "python tools/report/html_generator.py -i {change_name}"
      markdown: "python tools/report/generator.py -i {change_name}"
      allure_generate: "npx allure generate allure-results -o allure-report --clean"
    coverage_target: 80
    zero_skip_required: true

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

async_quality_scans:
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

test_suites:
  # 自动检测到的测试套件
```

### Step 4: 用户确认

通过 AskUserQuestion 展示生成的配置摘要：

```
"已检测到以下项目结构，生成了 autopilot 配置:"

检测结果:
- 后端: {tech_stack} (port {port})
- 前端: {framework} (port {port})
- 测试: {test_frameworks}

选项:
- "确认写入 (Recommended)" → 写入 .claude/autopilot.config.yaml
- "需要调整" → 展示完整 YAML 让用户修改后再写入
```

### Step 5: 写入配置

将配置写入 `.claude/autopilot.config.yaml`。

如果文件已存在 → AskUserQuestion 确认是否覆盖。

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
```

如果校验失败 → 输出缺失/错误的 key 列表，AskUserQuestion 要求用户修正后重试。

## 检测规则

### test_suites 自动推导

| 检测到 | 生成的 test_suite |
|--------|-------------------|
| `build.gradle` + `src/test/` | `backend_unit: { command: "cd backend && ./gradlew test", type: unit }` |
| `pytest.ini` 或 `conftest.py` | `api_test: { command: "python3 -m pytest tests/api/ -v", type: integration }` |
| `playwright.config.ts` | `e2e: { command: "npx playwright test", type: e2e }` |
| `vitest.config.*` | `unit: { command: "npx vitest run", type: unit }` |
| `jest.config.*` | `unit: { command: "npx jest", type: unit }` |
| 前端 `package.json` 有 `type-check` | `typecheck: { command: "cd frontend && pnpm type-check", type: typecheck }` |
| Node `tsconfig.json` | `node_typecheck: { command: "cd node && npx tsc --noEmit", type: typecheck }` |

### report_commands 自动推导

| 检测到 | 生成的命令 |
|--------|-----------|
| `tools/report/html_generator.py` | `html: "python tools/report/html_generator.py -i {change_name}"` |
| `tools/report/generator.py` | `markdown: "python tools/report/generator.py -i {change_name}"` |
| 都不存在 | `report_commands: {}` 并提示用户配置 |

## 幂等性

多次运行不会破坏已有配置。已存在时必须用户确认才能覆盖。
