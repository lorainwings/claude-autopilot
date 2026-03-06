---
name: autopilot-dispatch
description: "[ONLY for autopilot orchestrator] Sub-Agent dispatch protocol for autopilot phases. Constructs Task prompts with JSON envelope contract, explicit path injection, and parameterized templates."
user-invocable: false
---

# Autopilot Dispatch — 子 Agent 调度协议

> **前置条件自检**：本 Skill 仅在 autopilot 编排主线程中使用。如果当前上下文不是 autopilot 编排流程，请立即停止并忽略本 Skill。

从 `autopilot.config.yaml` 读取项目配置，构造标准化 Task prompt 分派子 Agent。

## 共享协议

> JSON 信封契约、阶段额外字段、状态解析规则、结构化标记等公共定义详见：`autopilot/references/protocol.md`。
> 以下仅包含 dispatch 专属的模板和指令。

## 显式路径注入模板

dispatch 子 Agent 时按以下优先级构造项目上下文：

### 上下文注入优先级（高 → 低）

| 优先级 | 来源 | 说明 |
|--------|------|------|
| 1 | `config.phases[phase].instruction_files` | 可选覆盖：项目自定义指令文件（存在则注入，覆盖内置规则） |
| 2 | `config.phases[phase].reference_files` | 可选覆盖：项目自定义参考文件 |
| 2.5 | Project Rules Auto-Scan | 全阶段自动扫描：运行 `rules-scanner.sh` 提取项目规则约束并注入 |
| 3 | `config.project_context` | 自动注入：init 检测的项目结构、测试凭据、Playwright 登录流程 |
| 4 | `config.test_suites` | 自动注入：测试命令、框架类型 |
| 5 | `config.services` | 自动注入：服务健康检查 URL |
| 6 | Phase 1 Steering Documents | 自动注入：Auto-Scan 生成的项目上下文（如存在） |
| 7 | 插件内置规则 | 兜底：dispatch 模板中的通用要求 |

### Prompt 构造模板

```markdown
Task(prompt: "<!-- autopilot-phase:{phase_number} -->
你是 autopilot 阶段 {phase_number} 的子 Agent。

## 项目上下文（从 config 自动注入）

### 服务列表
{for each service in config.services}
- {service.name}: {service.health_url}
{end for}

### 项目结构
- 后端目录: {config.project_context.project_structure.backend_dir}
- 前端目录: {config.project_context.project_structure.frontend_dir}
- 测试目录: {config.project_context.project_structure.test_dirs}

### 测试套件
{for each suite in config.test_suites}
- {suite_name}: `{suite.command}` (type: {suite.type})
{end for}

### 测试凭据
{if config.project_context.test_credentials.username 非空}
- 用户名: {config.project_context.test_credentials.username}
- 密码: {config.project_context.test_credentials.password}
- 登录端点: {config.project_context.test_credentials.login_endpoint}
{else}
- 未配置测试凭据，请从项目的 application.yml / .env 中读取
{end if}

### Playwright 登录流程
{if config.project_context.playwright_login.steps 非空}
{config.project_context.playwright_login.steps}
已知 data-testid: {config.project_context.playwright_login.known_testids}
{else}
- 未配置登录流程，请从 Login 组件中读取 data-testid 属性推导
{end if}

## Phase 1 项目分析（如存在）
读取以下文件获取项目深度上下文（如文件不存在则跳过）：
- openspec/changes/{change_name}/context/project-context.md
- openspec/changes/{change_name}/context/existing-patterns.md
- openspec/changes/{change_name}/context/tech-constraints.md
- openspec/changes/{change_name}/context/research-findings.md

{if config.phases[phase].instruction_files 非空}
## 项目自定义指令（覆盖）
先读取以下指令文件：
{for each file in config.phases[phase].instruction_files}
- {file_path}
{end for}
{end if}

{if config.phases[phase].reference_files 非空}
## 项目自定义参考文件
再读取以下参考文件：
{for each file in config.phases[phase].reference_files}
- {file_path}
{end for}
{end if}

### 模型路由提示注入（v3.0 新增）

dispatch 子 Agent 时，从 `config.model_routing.phase_{N}` 读取模型等级提示，注入到 prompt 中：

{if config.model_routing.phase_{N} == "light"}
## 执行模式：高效模式
本阶段为机械性操作，请聚焦效率：
- 输出简洁，避免过度分析
- 优先使用模板和既有模式
- 减少探索性操作
{end if}

{if config.model_routing.phase_{N} == "heavy"}
## 执行模式：深度分析模式
本阶段需要深度推理：
- 充分考虑边界情况和异常场景
- 提供详细的决策理由
- 进行多角度技术评估
{end if}

> **注意**: 当前 Claude Code 的 Task API 不支持 per-task model 参数。此提示作为行为引导注入。
> 未来 Claude Code 支持 model 参数时，插件将直接映射为 API 参数。

### 动态约束注入（v3.1.0 新增）

Phase 5 dispatch 时，除静态规则注入外，增加动态约束检查注入：

```markdown
{if phase == 5 AND config.phases.implementation.dynamic_constraints.enabled}
## 动态代码约束（自动执行，Hook 级强制）

以下约束由 PostToolUse Hook 实时验证，违反将被拦截：

### 静态约束（从 config/CLAUDE.md/rules 提取）
{rules_scan 结果注入}

### 动态约束（v3.1.0）
- **类型检查**: 每次 Write/Edit 后自动执行 `{typecheck_command}`
- **Import 路径**: 禁止相对路径超过 3 级（`../../../`）
- **文件大小**: 单文件不超过 {max_lines} 行（Hook 实时拦截）
- **ESLint/Checkstyle**: 当项目配置存在时，每个 task 完成后执行 lint 检查

> Hook 拦截时的 block 消息包含具体违规信息和修复建议。
{end if}
```

执行完毕后返回结构化 JSON 结果。")
```

### 优先级 2.5: Project Rules Auto-Scan（全阶段注入，v3.0 增强）

dispatch 任何阶段的子 Agent 时，自动运行 `rules-scanner.sh` 扫描项目 `.claude/rules/` 目录和 `CLAUDE.md`，提取所有约束并注入到子 Agent prompt 中。

**触发条件**：所有通过 Task 派发的阶段（Phase 2-6）

**缓存策略**：Phase 0 首次运行 rules-scanner.sh 后缓存结果，后续阶段复用缓存（同一 autopilot 会话内项目规则不变）。

**阶段差异化注入**：
| 阶段 | 注入内容 |
|------|---------|
| Phase 2-3 | 紧凑摘要（仅 critical_rules，≤5 条） |
| Phase 4 | 完整规则（测试需验证代码符合约束） |
| Phase 5 | 完整规则 + 实时 Hook 强制执行 |
| Phase 6 | 紧凑摘要（报告中引用约束合规状态） |

**执行流程**：

1. 主线程在构造子 Agent prompt 前执行（Phase 0 缓存，后续复用）：
   ```bash
   bash <plugin_scripts>/rules-scanner.sh "$(pwd)"
   ```
2. 解析返回的 JSON，检查 `rules_found === true`
3. 如果有约束，将 `constraints` 数组格式化为 prompt 段落注入

**注入模板**：

```markdown
{if rules_scan.rules_found === true}
## 项目规则约束（自动扫描）

以下约束从项目 `.claude/rules/` 和 `CLAUDE.md` 自动提取，**必须严格遵守**：

### 禁止项
{for each c in constraints where c.type === "forbidden"}
- ❌ `{c.pattern}` → 使用 `{c.replacement}`（来源: {c.source}）
{end for}

### 必须使用
{for each c in constraints where c.type === "required"}
- ✅ `{c.pattern}`（来源: {c.source}）
{end for}

### 命名约定
{for each c in constraints where c.type === "naming"}
- 📝 {c.pattern}（来源: {c.source}）
{end for}

> 违反以上约束将被 PostToolUse Hook 拦截并 block。
{end if}
```

**注入位置**：在 Prompt 模板中，插入在 `## Phase 1 项目分析` 之前、`### Playwright 登录流程` 之后。

## 内置模板解析（v3.0 新增）

当构造 Phase 4/5/6 prompt 时，检查 `config.phases[phase].instruction_files`：

1. **非空** → 使用项目自定义指令文件（覆盖内置模板）
2. **为空（默认）** → 使用插件内置模板（`autopilot/templates/phase{N}-*.md`）

内置模板中的 `{variable}` 占位符在 dispatch 时从 config 动态替换。

### 模板路径映射

| Phase | 内置模板 | 条件 |
|-------|---------|------|
| 4 | `autopilot/templates/phase4-testing.md` + `autopilot/templates/shared-test-standards.md` | 始终 |
| 5（串行） | `autopilot/templates/phase5-ralph-loop.md` + `autopilot/templates/shared-test-standards.md` | `parallel.enabled = false` |
| 5（并行） | `autopilot/templates/phase5-parallel.md` + `autopilot/templates/phase5-review-prompts.md` + `autopilot/templates/shared-test-standards.md` | `parallel.enabled = true`（v3.2.0） |
| 6 | `autopilot/templates/phase6-reporting.md` + `autopilot/templates/phase6-parallel.md` | 始终（v3.2.0：并行测试执行） |

### 域规则全文注入（v3.2.0 新增，Phase 5 并行专用）

当 Phase 5 并行模式启用时，每个 Domain Runner 的 prompt 中除了 rules-scanner 摘要外，**还必须注入对应域的完整规则文件**：

| Domain | 注入文件 | 说明 |
|--------|---------|------|
| backend | `.claude/rules/backend.md` 全文 | Java/Spring Boot/Gradle 规则 |
| frontend | `.claude/rules/frontend.md` 全文 | Vue/TypeScript/pnpm 规则 |
| node | `.claude/rules/nodejs.md` 全文 | Node.js/Fastify/PM2 规则 |
| shared | 所有域规则文件 | 跨域 task 需要全部规则 |

**注入逻辑**：
1. 检测 `.claude/rules/` 下是否存在对应域的规则文件（支持 `backend.md`、`java.md`、`spring.md` 等变体）
2. 存在 → 读取全文注入到 Domain Runner prompt 的 `## 项目规则约束` 段落
3. 不存在 → 仅使用 rules-scanner 摘要

### Agent 类型映射（v3.2.0 新增）

Phase 5 并行模式使用 `config.parallel.agent_mapping` 为不同角色选择最优 agent：

| 角色 | 配置项 | 默认值 | 说明 |
|------|--------|--------|------|
| Backend Implementer | `agent_mapping.backend` | `"general-purpose"` | 后端实施 agent |
| Frontend Implementer | `agent_mapping.frontend` | `"general-purpose"` | 前端实施 agent |
| Node Implementer | `agent_mapping.node` | `"general-purpose"` | Node 实施 agent |
| Spec Reviewer | `agent_mapping.review_spec` | `"general-purpose"` | 需求合规审查 |
| Quality Reviewer | `agent_mapping.review_quality` | `"pr-review-toolkit:code-reviewer"` | 代码质量审查（官方插件） |

> `pr-review-toolkit:code-reviewer` 是 Anthropic 官方 `claude-plugins-official` 中的专业代码审查 agent，
> 内置 CLAUDE.md 合规检查、Bug 检测、代码质量评估，使用 confidence 0-100 评分（仅报告 >= 80）。
> 项目必须启用 `pr-review-toolkit@claude-plugins-official` 插件。
> 如果该插件不可用，自动降级为 `"general-purpose"`。

### 模板变量替换规则

dispatch 主线程在构造 prompt 时执行变量替换：
- `{config.services}` → 从 config.services 展开服务列表
- `{config.test_suites}` → 从 config.test_suites 展开测试套件
- `{config.project_context.*}` → 从 config.project_context 展开凭据/登录流程
- `{config.test_pyramid.*}` → 从 config.test_pyramid 展开金字塔约束
- `{change_name}` → 活跃 change 的 kebab-case 名称

> **向后兼容**: 已有项目的 instruction_files 配置继续生效，优先级高于内置模板。

## 参数化调度模板

### 输入参数

| 参数 | 来源 |
|------|------|
| phase_number | 当前阶段编号 (2-6) |
| agent_name | config.phases[phase].agent 或默认 agent |
| change_name | 活跃 change 的 kebab-case 名称 |
| instruction_files | config.phases[phase].instruction_files |
| reference_files | config.phases[phase].reference_files |

### 子 Agent 前置校验指令（必须包含在 prompt 开头）

```markdown
**前置校验（在执行任何操作之前）**：
1. 读取 `openspec/changes/{change_name}/context/phase-results/phase-{N-1}-*.json`
2. 如果文件不存在 → 立即返回：
   `{"status": "blocked", "summary": "Phase {N-1} checkpoint 不存在"}`
3. 如果 status 不是 "ok" 或 "warning" → 立即返回：
   `{"status": "blocked", "summary": "Phase {N-1} 状态为 {status}"}`
4. 校验通过后，继续执行本阶段任务。
```

### 各阶段调度内容

**Phase 1（技术调研 — 主线程调度，不含 autopilot-phase 标记）**：
- Agent: config.phases.requirements.research.agent（默认 Explore）
- 条件：`config.phases.requirements.research.enabled === true`
- 任务：分析与需求相关的现有代码、依赖兼容性、技术可行性
- Prompt 必须注入：RAW_REQUIREMENT + Steering Documents 路径
- 返回：JSON 格式的 impact_analysis / dependency_check / feasibility / risks
- 此 Task 不含 `autopilot-phase` 标记 → 不受 Hook 门禁校验（设计预期）
- 失败两次后标记 `research_status: "skipped"`，不阻断流程

**Phase 1（需求分析 — 主线程调度，不含 autopilot-phase 标记）**：
- Agent: config.phases.requirements.agent（默认 business-analyst）
- 任务：基于 Steering + Research 上下文分析需求，产出功能清单 + 疑问点
- Prompt 必须注入：RAW_REQUIREMENT + 所有 Steering Documents + research-findings.md + complexity 评估结果
- **联网调研结果注入**（v2.4.0）：当 research-findings.md 中存在 Web Research Findings 章节时，追加以下指令：
  ```
  ## 联网调研结果（如存在）
  读取 research-findings.md 中的 Web Research Findings 章节。
  基于调研结果，在讨论中：
  - 引用具体的最佳实践和数据支撑你的建议
  - 对比不同技术方案的优劣，给出推荐
  - 提醒用户已知的坑点和风险
  ```
- **决策协议注入**（v2.4.0）：当 complexity 为 "medium" 或 "large" 时，追加以下指令：
  ```
  ## 决策输出格式
  对每个不确定的决策点，你必须输出结构化决策卡片：
  - 列出 2-4 个备选方案
  - 每个方案说明优点、缺点和影响范围
  - 标记推荐方案并说明理由
  - 引用 research-findings.md 中的调研数据支撑推荐
  ```
- 返回值校验：非空，且包含功能清单和疑问点

**Phase 2（创建 OpenSpec）**：
- Agent: general-purpose
- 任务：从需求推导 kebab-case 名称，执行 `openspec new change "<name>"`
- 写入 context 文件（prd.md、discussion.md、ai-prompt.md）

**Phase 3（FF 生成制品）**：
- Agent: general-purpose
- 任务：按 openspec-ff-change 流程生成 proposal/specs/design/tasks
- artifacts 列出所有已创建制品路径

**Phase 4（测试用例设计）**：
- Agent: config.phases.testing.agent（默认 qa-expert）
- 项目上下文从 config.project_context + config.test_suites + Phase 1 Steering Documents 自动注入
- 可选覆盖：config.phases.testing.instruction_files / reference_files（非空时注入）
- 门禁：4 类测试全部创建、每类 ≥ min_test_count_per_type
- **Phase 4 不可跳过，不可降级为 warning**

Phase 4 子 Agent prompt 必须包含以下强制指令：

```markdown
## 强制要求（不可违反）

你**必须**创建实际的测试文件，不允许以"后续补充"或"纯 UI 变更不需要"为由跳过。

### 需求追溯（第一步，在创建测试文件之前）

1. 读取 `openspec/changes/{change_name}/proposal.md` 提取所有功能点和验收标准
2. 读取 `openspec/changes/{change_name}/specs/` 下所有 spec 文件提取接口契约和业务规则
3. 读取 `openspec/changes/{change_name}/design.md`（如存在）提取架构约束
4. 将每个功能点/验收标准编号为 REQ-001, REQ-002 ...
5. 在 `openspec/changes/{change_name}/context/test-plan.md` 中生成需求追溯矩阵
6. **每个 REQ 必须至少有 1 个测试用例映射**，否则返回 `status: "blocked"`

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
- 所有测试文件创建成功 + dry-run 通过 + 需求覆盖率 100% → `"status": "ok"`
- 任何原因无法创建或需求覆盖率 < 100% → `"status": "blocked"`，summary 说明阻塞原因
- **禁止返回 "warning"**：Phase 4 不接受降级通过

返回信封中**必须**包含 `traceability_matrix` 和 `coverage` 字段：
```json
{
  "traceability_matrix": [
    { "req_id": "REQ-001", "requirement": "描述", "test_cases": ["test_xxx"], "test_types": ["api"] }
  ],
  "coverage": { "total_requirements": 10, "covered_requirements": 10, "coverage_pct": 100 }
}
```

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

**Phase 5（Subagent-Driven 实施）**：
- 通过 ralph-loop 或 fallback 执行（由编排主线程决策）
- 项目上下文从 config.project_context + config.test_suites 自动注入（快速校验命令 = test_suites 中 type=typecheck 的套件）
- 可选覆盖：config.phases.implementation.instruction_files（非空时注入）
- **Subagent-Driven 并行模式**（当 config.phases.implementation.parallel.enabled = true）：
  - 主线程读取 `templates/phase5-parallel.md`（完整的 10 步可执行指令）
  - **独立域并行**：按顶级目录（backend/frontend/node）分组，每域一个 Domain Runner
  - **同域串行**：Domain Runner 内部逐个执行 task（fresh subagent + self-review）
  - **Domain Runner agent 类型**：从 `config.parallel.agent_mapping` 读取，支持专业 agent
  - **双阶段 review**：所有域合并后派发 spec-reviewer + quality-reviewer（`templates/phase5-review-prompts.md`）
  - **Worktree 自动启用**：并行时 `Task(isolation: "worktree", run_in_background: true)`
  - **降级**：仅 1 个域有 task → 自动切换串行模板

  **Phase 5 Domain Runner Prompt 核心结构**（v3.2.0）：
  ```
  <!-- autopilot-phase:5 -->
  你是 autopilot Phase 5 的 Domain Runner（{domain} 域）。

  ## 你的任务列表（按顺序串行执行）
  {for each task in domain.tasks}
  ### Task #{task.number}: {task.title}
  {task.full_description}
  {end for}

  ## 域文件所有权约束（ENFORCED）
  你只能修改 `{domain}/` 目录下的文件。越权将被 Hook 拦截。

  ## 项目规则约束（域特定规则全文注入）
  {rules_scanner 扫描结果}
  {.claude/rules/{domain}.md 全文}

  ## 执行流程（每个 task）
  1. 理解需求 → 2. 实施 → 3. 快速校验 → 4. Self-Review → 5. 记录

  ## 返回 JSON 信封
  { status, domain, summary, tasks: [{ task_number, status, summary, artifacts, self_review, test_result }] }
  ```

  **Phase 5 Review 流程**（合并后强制执行）：
  1. **Spec Compliance Review**：`Task(subagent_type: "general-purpose")`
     - 逐条对比 proposal 功能点 vs 实际代码
     - 不通过 → 派发 fix agent → 重新 review → 最多 2 轮
  2. **Code Quality Review**：`Task(subagent_type: config.parallel.agent_mapping.review_quality || "pr-review-toolkit:code-reviewer")`
     - 使用 confidence 0-100 评分，只报告 >= 80 的问题
     - Critical (>= 90) → 阻断，Important (80-89) → 记录不阻断
     - 不通过 → 派发 fix agent → 重新 review → 最多 2 轮

**Phase 6（测试报告）**：
- Agent: qa-expert
- 测试命令从 config.test_suites 动态读取
- **并行测试执行**（v3.2.0 新增）：读取 `autopilot/templates/phase6-parallel.md`，将独立测试套件并行派发为 background Task
- 可选覆盖：config.phases.reporting.instruction_files（非空时注入）
- **报告格式选择**（按 `config.phases.reporting.format` 决定）：
  - `"allure"`（推荐）→ 读取 `autopilot/templates/phase6-reporting.md` 路径 1：
    1. `bash <plugin_scripts>/check-allure-install.sh "$(pwd)"` → 安装检查
    2. 设置 `ALLURE_RESULTS_DIR="$(pwd)/allure-results"`
    3. 各 suite 按 allure 类型追加参数（pytest: `--alluredir`，playwright: `--reporter=allure-playwright`，junit_xml: 后处理复制）
    4. `npx allure generate "$ALLURE_RESULTS_DIR" -o allure-report --clean`
    5. 返回 `report_format: "allure"`, `report_path: "allure-report/index.html"`, `allure_results_dir`
  - `"custom"` → 使用 config.phases.reporting.report_commands
  - Allure 安装失败 → 自动降级为 custom
