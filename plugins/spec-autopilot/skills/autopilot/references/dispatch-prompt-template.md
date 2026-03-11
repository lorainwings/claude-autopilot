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

## 注入位置

Project Rules Auto-Scan 结果注入在 `## Phase 1 项目分析` 之前、`### Playwright 登录流程` 之后。

> 上下文注入优先级详见 `autopilot-dispatch/SKILL.md` 的优先级表。
