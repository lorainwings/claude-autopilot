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
| ralph-loop 插件 | Phase 5 自主迭代实现 | `claude plugin install ralph-loop` |
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

### Step 3: 生成项目配置

在 Claude Code 中执行：

```
启动autopilot
```

> 如果 `.claude/autopilot.config.yaml` 不存在，插件会自动调用 `autopilot-init` 扫描项目并生成配置。

或者手动触发配置生成：

```
/spec-autopilot:autopilot-init
```

插件会自动检测：
- 技术栈（Java/Spring Boot、Vue/React、Python、Go 等）
- 服务端口（从 application.yml / vite.config.ts / .env 提取）
- 测试框架（JUnit、pytest、Playwright、Vitest 等）
- 构建工具（Gradle、Maven、pnpm、npm 等）

生成的配置文件位于 `.claude/autopilot.config.yaml`。

### Step 4: 审查并调整配置

打开生成的配置文件，确认以下关键项：

```yaml
version: "1.0"

# === 服务健康检查 ===
services:
  backend:
    health_url: "http://localhost:8080/actuator/health"  # 根据实际端口调整
  frontend:
    health_url: "http://localhost:5173/"                  # 根据实际端口调整

# === 各阶段配置 ===
phases:
  requirements:
    agent: "business-analyst"        # 需求分析 Agent 类型
    min_qa_rounds: 1                 # 最少 QA 轮数
    mode: "structured"               # structured | socratic
    # Phase 1 增强功能（v2.1 新增）
    auto_scan:
      enabled: true                  # 自动扫描项目结构生成 Steering Documents
      max_depth: 2                   # 目录扫描深度
    research:
      enabled: true                  # 自动技术调研
      agent: "Explore"               # 调研 Agent 类型（Explore 快速只读）
    complexity_routing:
      enabled: true                  # 自动复杂度评估
      thresholds:
        small: 2                     # ≤2 文件 → 快速确认模式
        medium: 5                    # 3-5 文件 → 标准讨论

  testing:
    agent: "qa-expert"
    instruction_files: []            # 测试指令文件路径（可选）
    reference_files: []              # 测试参考文件路径（可选）
    gate:
      min_test_count_per_type: 5     # 每类测试最少用例数
      required_test_types:           # 要求的测试类型
        - unit
        - api
        - e2e
        - ui

  implementation:
    instruction_files: []
    ralph_loop:
      enabled: true                  # 使用 ralph-loop 自主迭代
      max_iterations: 30             # 最大迭代次数
      fallback_enabled: true         # ralph-loop 不可用时降级
    worktree:
      enabled: false                 # git worktree 隔离
    parallel:
      enabled: false                 # 并行 Agent Team
      max_agents: 3

  reporting:
    instruction_files: []
    format: "allure"                 # allure | custom
    report_commands:
      html: ""                       # 自定义 HTML 报告命令
      markdown: ""                   # 自定义 Markdown 报告命令
    coverage_target: 80              # 覆盖率目标 (%)
    zero_skip_required: true         # 零跳过要求

  code_review:
    enabled: true                    # Phase 6.5 代码审查
    block_on_critical: true          # critical findings 阻断

# === 测试金字塔 ===
test_pyramid:
  min_unit_pct: 50                   # 单元测试 ≥ 50%
  max_e2e_pct: 20                    # E2E 测试 ≤ 20%
  min_total_cases: 20                # 总用例数 ≥ 20

# === 用户确认点 ===
gates:
  user_confirmation:
    after_phase_1: true              # 需求分析后确认
    after_phase_3: false             # 设计生成后确认
    after_phase_4: false             # 测试设计后确认

# === 上下文管理 ===
context_management:
  git_commit_per_phase: true         # 每阶段自动 fixup commit
  squash_on_archive: true            # 归档时自动 squash

# === 测试套件 ===
# 根据你的项目实际情况配置
test_suites:
  backend_unit:
    command: "cd backend && ./gradlew test"
    type: unit
    allure: junit_xml
    allure_post: 'cp -r backend/build/test-results/test/*.xml "$ALLURE_RESULTS_DIR/"'
  api_test:
    command: "python3 -m pytest tests/api/ -v"
    type: integration
    allure: pytest
  e2e:
    command: "npx playwright test"
    type: e2e
    allure: playwright
  frontend_typecheck:
    command: "cd frontend && pnpm type-check"
    type: typecheck
    allure: none
```

运行配置验证：

```bash
bash ~/.claude/plugins/marketplaces/lorainwings-plugins/plugins/spec-autopilot/scripts/validate-config.sh
```

确认输出 `"valid": true`。

### Step 5: 创建项目侧 Skill 入口

创建 `.claude/skills/autopilot/SKILL.md`：

```markdown
---
name: autopilot
description: "Full autopilot orchestrator: requirements → OpenSpec → implementation → testing → reporting → archive. Triggers: '全自动开发流程', '一键从需求到交付', '启动autopilot'."
argument-hint: "[需求描述或 PRD 文件路径]"
---

调用 Skill("spec-autopilot:autopilot", args="$ARGUMENTS") 启动编排器。
```

### Step 6:（可选）添加项目特定阶段指令

创建 `.claude/skills/autopilot/phases/` 目录，按需添加项目特定指令：

**测试指令** — `.claude/skills/autopilot/phases/testing-requirements.md`：

```markdown
# 测试要求

## 登录凭据
- 测试账号: test / test123
- API Base URL: http://localhost:8080/api

## 测试框架规范
- 后端单元测试: JUnit 5 + Mockito
- API 测试: pytest + requests
- E2E 测试: Playwright (TypeScript)
- 必须使用 data-testid 属性定位元素
```

**实施指令** — `.claude/skills/autopilot/phases/ralph-loop-config.md`：

```markdown
# 实施约束

## 编码规范
- 代码风格遵循项目 CLAUDE.md 中的约束
- 单次修改不超过 3 个文件

## 测试策略
- 每个 task 完成后必须运行相关测试
- 测试失败优先修复实现代码，禁止修改测试
```

**报告指令** — `.claude/skills/autopilot/phases/reporting.md`：

```markdown
# 报告要求

## 测试套件执行顺序
1. 后端单元测试
2. API 集成测试
3. 前端类型检查
4. E2E 测试

## 零跳过门禁
所有测试必须通过或明确标记失败原因，禁止跳过。
```

然后在 `autopilot.config.yaml` 中引用：

```yaml
phases:
  testing:
    instruction_files:
      - ".claude/skills/autopilot/phases/testing-requirements.md"
  implementation:
    instruction_files:
      - ".claude/skills/autopilot/phases/ralph-loop-config.md"
  reporting:
    instruction_files:
      - ".claude/skills/autopilot/phases/reporting.md"
```

### Step 7: 初始化 OpenSpec 目录

确保项目根目录存在 `openspec/` 结构：

```bash
mkdir -p openspec/changes openspec/archive openspec/specs
```

如果项目使用 OpenSpec 插件，目录通常已自动创建。

### Step 8: 验证安装

在 Claude Code 中执行快速验证：

```
# 1. 检查插件加载
claude plugin list

# 2. 检查配置有效
# （启动 autopilot 时会自动验证）

# 3. 检查 Hook 注册
# 查看 .claude/settings.json 的 hooks 部分应包含 spec-autopilot 相关条目
```

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
├── 检查 ralph-loop 插件
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
├── Phase 5: Ralph-loop 循环实施
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
    ralph_loop:
      enabled: true
      max_iterations: 20
      fallback_enabled: true
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

---

## 项目接入检查清单

- [ ] Claude Code CLI 已安装
- [ ] spec-autopilot 插件已安装
- [ ] openspec 插件已安装
- [ ] `.claude/autopilot.config.yaml` 已生成并审查
- [ ] 配置验证通过（`valid: true`）
- [ ] `.claude/skills/autopilot/SKILL.md` 入口已创建
- [ ] `openspec/` 目录结构已存在
- [ ] （可选）ralph-loop 插件已安装
- [ ] （可选）阶段指令文件已配置
- [ ] （可选）测试套件命令已验证可运行
- [ ] 首次 `启动autopilot` 测试通过

---

## 故障排查

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| "Config file not found" | 配置未生成 | 运行 `autopilot-init` 或手动创建 |
| "python3 not found" | Hook 脚本需要 python3 | `brew install python3` 或 `apt install python3` |
| "Phase N checkpoint not found" | 阶段被跳过或崩溃 | 触发 autopilot 重新运行，崩溃恢复会自动处理 |
| "ralph-loop not available" | 插件未安装 | 安装 ralph-loop 或设置 `fallback_enabled: true` |
| Hook 脚本超时 | 项目过大导致扫描慢 | 增加 Hook timeout 或减少扫描范围 |
| 测试金字塔不通过 | 测试分布不达标 | 调整测试用例数量或放宽 `test_pyramid` 阈值 |

更多故障排查详见 [troubleshooting.md](troubleshooting.md)。
