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

| Phase | 内置模板 |
|-------|---------|
| 4 | `autopilot/templates/phase4-testing.md` + `autopilot/templates/shared-test-standards.md` |
| 5 | `autopilot/templates/phase5-ralph-loop.md` + `autopilot/templates/shared-test-standards.md` |
| 6 | `autopilot/templates/phase6-reporting.md` |

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
- 所有测试文件创建成功 + dry-run 通过 → `"status": "ok"`
- 任何原因无法创建 → `"status": "blocked"`，summary 说明阻塞原因
- **禁止返回 "warning"**：Phase 4 不接受降级通过

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

**Phase 5（循环实施）**：
- 通过 ralph-loop 或 fallback 执行（由编排主线程决策）
- 项目上下文从 config.project_context + config.test_suites 自动注入（快速校验命令 = test_suites 中 type=typecheck 的套件）
- 可选覆盖：config.phases.implementation.instruction_files（非空时注入）
- **并行执行模式**（当 config.phases.implementation.parallel.enabled = true）：
  - 主线程分析 tasks.md 构建依赖图，识别可并行的 task 组
  - 每组内的 task 使用 `Task(isolation: "worktree", run_in_background: true)` 并行派发
  - 最大并行数 = config.phases.implementation.parallel.max_agents（默认 3）
  - 每组完成后按 task 编号顺序合并 worktree，冲突时 AskUserQuestion 处理
  - 合并后运行测试验证，失败则降级为串行模式

  **Phase 5 并行 Task Prompt 模板**（v2.4.0 新增）：
  ```
  <!-- autopilot-phase:5 -->
  你是 autopilot Phase 5 的并行实施子 Agent。

  ## 你的任务
  仅实施以下单个 task（禁止实施其他 task）：
  - Task #{task_number}: {task_title}
  - Task 内容: {task_description}

  ## 前序 task 摘要（只读参考）
  {for each completed_task in group_predecessors}
  - Task #{n}: {summary} — 已合并到主分支
  {end for}

  ## 并行隔离约束（v3.0 增强：文件所有权分区）
  - 你运行在独立 worktree 中
  - **文件所有权**：你只能修改以下文件（越权将被 Hook 拦截）：
    {task.owned_files}
  - 禁止修改 openspec/ 目录下的 checkpoint 文件
  - 禁止修改其他 task 正在修改的文件（列表: {concurrent_task_files}）
  - 完成后返回 JSON 信封（artifacts 必须是 owned_files 的子集）

  {标准项目上下文注入}
  ```
- **Worktree 隔离模式**（当 config.phases.implementation.worktree.enabled = true）：
  - 主线程按 task 粒度逐个派发，每个 task 使用 `Task(isolation: "worktree")`
  - 子 Agent prompt 中注入当前 task 内容和前序 task 摘要
  - 子 Agent 完成后返回 worktree 路径和分支名，主线程决定合并策略

**Phase 6（测试报告）**：
- Agent: qa-expert
- 测试命令从 config.test_suites 动态读取（全量运行所有 suite）
- 报告命令从 config.phases.reporting.report_commands 读取
- 可选覆盖：config.phases.reporting.instruction_files（非空时注入）
- **Allure 统一报告**（当 `config.phases.reporting.format === "allure"` 时）：
  - **前置检查**：子 Agent prompt 中注入 Allure 安装检测指令：
    ```
    运行 Allure 安装检查: bash <plugin_scripts>/check-allure-install.sh "$(pwd)"
    如果 all_required_installed === false → 按 install_commands 逐个安装
    安装后重新运行检查 → 仍失败 → 降级为 report_format: "custom"
    ```
  - 所有测试套件使用 `ALLURE_RESULTS_DIR="$(pwd)/allure-results"` 环境变量统一输出
  - pytest: `--alluredir="$ALLURE_RESULTS_DIR"`
  - Playwright: `ALLURE_RESULTS_DIR="$ALLURE_RESULTS_DIR" --reporter=list,allure-playwright`
  - JUnit/Gradle: 手动复制 `backend/build/test-results/test/*.xml` 到 `$ALLURE_RESULTS_DIR/`
  - 生成统一报告: `npx allure generate "$ALLURE_RESULTS_DIR" -o allure-report --clean`
  - 返回 `report_format: "allure"` 和 `allure_results_dir` 路径
- **降级模式**（Allure 安装失败时）：
  - 使用 config.phases.reporting.report_commands 中的 html/markdown 命令
  - 返回 `report_format: "custom"`
