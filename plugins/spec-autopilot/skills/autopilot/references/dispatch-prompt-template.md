# Dispatch Prompt 构造模板

> 本文件从 `autopilot-dispatch/SKILL.md` 提取，供 dispatch 构造子 Agent prompt 时引用。

## Prompt 构造模板

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
- openspec/changes/{change_name}/context/web-research-findings.md（如存在）
- openspec/changes/{change_name}/context/requirements-analysis.md（v3.4.0, 如存在）

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

### 模型路由（v5.3 升级为执行级路由）

dispatch 子 Agent 前，主线程先调用 `resolve-model-routing.sh` 获取模型路由决策：

```bash
ROUTING_JSON=$(bash <plugin_scripts>/resolve-model-routing.sh "$PROJECT_ROOT" {phase_number} {complexity} {requirement_type} {retry_count} {critical})
```

返回 JSON 包含：`selected_tier` / `selected_model` / `selected_effort` / `routing_reason` / `escalated_from` / `fallback_applied`

#### 三层 subagent 模型分层

| 概念名 | tier | model | effort | 适用场景 |
|--------|------|-------|--------|----------|
| `autopilot-fast` | fast | haiku | low | 机械性操作（OpenSpec、FF、报告、归档） |
| `autopilot-standard` | standard | sonnet | medium | 代码实施、常规分析 |
| `autopilot-deep` | deep | opus | high | 需求分析、测试设计、关键重试 |

#### 路由结果注入 prompt

根据 `selected_tier` 注入对应执行模式提示：

{if selected_tier == "fast"}
## 执行模式：高效模式 (autopilot-fast / haiku)
本阶段为机械性操作，请聚焦效率：
- 输出简洁，避免过度分析
- 优先使用模板和既有模式
- 减少探索性操作
> 模型路由: {routing_reason}
{end if}

{if selected_tier == "standard"}
## 执行模式：标准模式 (autopilot-standard / sonnet)
本阶段为常规实施任务：
- 在质量与效率间取得平衡
- 关注边界情况但不过度展开
- 遵循项目既有模式
> 模型路由: {routing_reason}
{end if}

{if selected_tier == "deep"}
## 执行模式：深度分析模式 (autopilot-deep / opus)
本阶段需要深度推理：
- 充分考虑边界情况和异常场景
- 提供详细的决策理由
- 进行多角度技术评估
> 模型路由: {routing_reason}
{end if}

#### subagent model 参数传递

当 Claude Code 支持 Task `model` 参数时，dispatch 直接传递：

```
Task(prompt: "...", model: "{selected_model}")
```

> 如果 Claude Code 尚未支持 per-task model 参数，则退化为行为提示注入 + 环境变量 `CLAUDE_CODE_SUBAGENT_MODEL={selected_model}`。

#### 升级重试

当子 Agent 返回 `status: "failed"` 或 `status: "blocked"` 时：
1. 递增 `retry_count`
2. 重新调用 `resolve-model-routing.sh` 获取升级后的路由
3. 升级链: fast → standard → deep
4. deep 仍失败时不继续自动升级，转人工决策或串行回退

#### 运行时模型不可用 fallback

resolver 输出中包含 `fallback_model` 字段（默认 `sonnet`）。dispatch 层必须实现以下运行时 fallback 协议：

1. dispatch 发起 Task 时，记录 `selected_model` 和 `fallback_model`
2. 如果 Task 因**模型不可用**失败（错误信息包含 `model_not_available`、`overloaded`、`capacity` 等关键词），则：
   - 用 `fallback_model` 重新发起同一 Task
   - 在路由事件中标记 `fallback_applied: true`
   - routing_reason 追加 `, 模型不可用, fallback 至 {fallback_model}`
3. 如果 `fallback_model` 也不可用，转人工决策
4. 如果 Task 因**非模型原因**失败（代码错误、测试不通过等），走正常升级重试链，不触发 fallback

> 注意：resolver 是静态预分析，无法在解析时检测模型可用性。运行时 fallback 由 dispatch 主线程在 Task 执行失败后判断错误类型并决定是否使用 `fallback_model`。

执行完毕后返回结构化 JSON 结果。")
```

## TDD 模式 Prompt 模板（Phase 5 专属）

当 `tdd_mode: true` 时，Phase 5 的每个 task 派发 3 个 sequential Task：

### RED Task Prompt

```markdown
Task(prompt: "<!-- autopilot-phase:5 -->
你是 autopilot Phase 5 TDD RED 子 Agent。

## The Iron Law
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST.

## 任务
为 task-{N} 编写失败测试。

### 任务描述
{task.description}

### 约束
- 仅写测试文件，**禁止写任何实现代码**
- 测试必须验证尚不存在的新行为
- 测试运行后必须因断言失败而失败（非语法/编译错误）

### 反模式检查（自查）
- 测试验证的是真实行为，不是 mock 行为
- Mock 仅用于外部 I/O
- 每个测试只验证一件事

{project_context}

返回 JSON：{\"status\": \"ok\", \"test_file\": \"<path>\", \"test_command\": \"<cmd>\", \"summary\": \"...\"}
")
```

### GREEN Task Prompt

```markdown
Task(prompt: "<!-- autopilot-phase:5 -->
你是 autopilot Phase 5 TDD GREEN 子 Agent。

## 任务
为 task-{N} 编写最小实现让测试通过。

### 测试文件
Read: {red_task.test_file}

### 测试命令
{red_task.test_command}

### 约束
- 写最小代码让测试通过（YAGNI）
- **禁止修改测试文件**
- 如果测试失败 → 修复实现代码，不修改测试

{project_context}

返回 JSON：{\"status\": \"ok\", \"impl_files\": [...], \"summary\": \"...\"}
")
```

### REFACTOR Task Prompt（当 `tdd_refactor: true`）

```markdown
Task(prompt: "<!-- autopilot-phase:5 -->
你是 autopilot Phase 5 TDD REFACTOR 子 Agent。

## 任务
清理 task-{N} 的实现代码。

### 约束
- 删除重复、改善命名、提取辅助函数
- **禁止修改测试文件**
- **禁止改变行为**（测试必须继续通过）
- 运行 {test_command} 确认测试通过

{project_context}

返回 JSON：{\"status\": \"ok\", \"refactored_files\": [...], \"summary\": \"...\"}
")
```

## 注入位置

Project Rules Auto-Scan 结果注入在 `## Phase 1 项目分析` 之前、`### Playwright 登录流程` 之后。

> 上下文注入优先级详见 `autopilot-dispatch/SKILL.md` 的优先级表。
