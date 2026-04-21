---
name: autopilot-setup
description: "Use when a user initializes autopilot in a project that lacks .claude/autopilot.config.yaml, requests /autopilot-setup, asks to bootstrap autopilot configuration, or needs autopilot to detect project tech stack, services, agents, and test suites for the first time."
argument-hint: "[可选: 项目根目录路径] [--non-interactive 跳过向导]"
---

# Autopilot Setup — 项目配置初始化

扫描项目结构，自动检测技术栈和服务，生成 `.claude/autopilot.config.yaml`。

## Wizard 模式（默认启动）

**执行前读取**: `references/setup-wizard.md`（完整 Wizard 交互流程和预设模板定义）

默认进入引导式向导，3 步完成配置，降低 60+ 配置项的认知负担。

1. **选择预设模板** — AskUserQuestion 展示 Strict / Moderate / Relaxed 3 个预设
2. **确认自动检测** — 运行项目检测流程，展示结果摘要供用户确认
3. **应用预设 + 写入** — 将预设值覆盖到检测结果上，生成最终配置

> **跳过 Wizard**: 传入 `--non-interactive` 时跳过预设选择，直接执行检测流程（向后兼容）。

## 执行流程

**执行前读取**: `references/setup-detection-rules.md`（完整检测规则 + 推导表）

### Step 1-2.6: 项目检测

自动检测技术栈、服务端口、项目上下文和安全工具。检测规则详见 `references/setup-detection-rules.md`，包含：

- **Step 1**: 后端/前端/Node 服务/测试框架检测
- **Step 2**: 服务端口提取
- **Step 2.5**: 项目上下文（测试凭据、项目结构、Playwright 登录流程）
- **Step 2.6**: 安全工具检测

### Step 3: 生成配置

**读取模板**: `references/config-schema.md`（完整 YAML 配置模板）

根据 Step 1-2.6 的检测结果，按 `config-schema.md` 中的模板生成配置文件。所有 `{detected}` 占位符替换为实际检测值。

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

## Agent 与模型引导

**执行前读取**: `references/setup-agent-model-guide.md`（Agent 安装引导 + 模型路由引导）
**执行前读取**: `references/setup-domain-agent-guide.md`（域级 Agent 推荐映射表 + 安装引导）

### Step 5.3: Agent 安装引导

始终通过 AskUserQuestion 引导用户安装专业 Agent。详见 `references/setup-agent-model-guide.md`。

### Step 5.3.5: 域级 Agent 配置引导

基于 Step 1 检测到的项目结构（project_structure.backend_dir / frontend_dir / node_dir）以及扩展目录扫描，引导用户配置 `implementation.parallel.domain_agents` 的域级 Agent 映射。详见 `references/setup-domain-agent-guide.md`。

```
IF Wizard 预设的 domain_agents_strategy == "skip":
  → 输出 "跳过域 Agent 配置（Relaxed 模式）"
  → 继续后续步骤

ELIF 检测到至少一个目录域（backend_dir/frontend_dir/node_dir 非空，或扩展扫描发现额外目录）:
  IF domain_agents_strategy == "recommended":
    → 自动安装推荐域 Agent（不弹 AskUserQuestion）
  ELSE:
    → 按 references/setup-domain-agent-guide.md Section D 的标准交互流程引导
  → 安装选定的 VoltAgent/OMC 域级 Agent 到 .claude/agents/
  → 更新 config domain_agents 映射

ELSE:
  → 输出 "未检测到多域项目结构，跳过域级 Agent 配置"
```

> 域级 Agent 配置是可选步骤，跳过不影响 autopilot 功能。未配置时使用 default_agent (fallback)。

### Step 5.3.6: Phase 2-7 Agent 配置引导（必须执行）

在 Step 5.3 / 5.3.5 之后，遍历以下 8 个 Phase 2-7 关键 agent 字段，逐个执行 "scan candidates → 推荐预设 → AskUserQuestion 选择 → 写 config"：

| 字段 | 推荐预设（来源 `../autopilot-agents/references/recommend-mode.md`） |
|------|------|
| `phases.openspec.agent` | OMC `planner` |
| `phases.testing.agent` | OMC `test-engineer` |
| `phases.implementation.parallel.default_agent` | OMC `executor` |
| `phases.implementation.review_agent`（即 `parallel.review_agent`） | OMC `code-reviewer` |
| `phases.redteam.agent` | OMC `code-reviewer`（备选 Anthropic `red-team-critic`） |
| `phases.reporting.agent` | OMC `qa-tester` |
| `phases.code_review.agent` | OMC `code-reviewer` |
| `phases.archive.agent` | OMC `git-master` |

**Wizard 分支控制**（参见 `references/setup-wizard.md` 的 `phase_agents_strategy`）：

```
IF phase_agents_strategy == "recommended":
  → 对每个字段：若推荐 agent 已安装则直接写入，否则自动调用
    Skill("spec-autopilot:autopilot-agents" "install") 后写入（不弹 AskUserQuestion）
  → 输出汇总表

ELIF phase_agents_strategy == "fallback_general_purpose":
  → 所有 8 字段默认写 "general-purpose"，供用户后续手动替换

ELSE (phase_agents_strategy == "ask" 或未指定):
  # 标准交互流程
  FOR field IN 上述 8 个字段:
    # 1. 扫描已安装候选（同 Step 5.3 规则，含 plugin:agent 命名空间）
    # 2. 计算推荐 agent 是否已安装
    IF 推荐 agent 未安装:
      → AskUserQuestion: "{field} 推荐使用 {recommended_agent}，当前未安装。如何处理？"
        选项:
        - "立即安装（调用 autopilot-agents install-mode）" →
            Skill("spec-autopilot:autopilot-agents" "install") 完成后写入推荐 agent
        - "保持空字段稍后手动安装" → 写入 ""（Schema 校验会提示未完成）
        - "降级 general-purpose" → 写入 "general-purpose"
    ELIF 候选为 1 个（仅推荐 agent）:
      → 直接写入推荐 agent，输出 "✓ {field}: {agent}"
    ELSE:
      → AskUserQuestion: "选择 {field} 使用的 agent：" 选项=候选列表（推荐标 Recommended 首位，
        始终追加 "立即安装其它推荐" / "保持空字段" 两个特殊选项）
      → 写入用户选择
```

**二次校验**：写入后若某字段为空且当前预设非 Relaxed/fallback_general_purpose → 输出警告并记录到 Schema 校验清单（见 Step 6）。

### Step 5.4: 模型路由引导

引导用户配置模型路由策略。详见 `references/setup-agent-model-guide.md`。

## LSP 推荐

**执行前读取**: `references/setup-lsp-recommendation.md`（LSP 推荐映射表 + 交互）

### Step 5.5: LSP 插件推荐

根据检测到的技术栈推荐 Claude Code LSP 插件。详见 `references/setup-lsp-recommendation.md`。

### Step 5.6: Agent 工具权限自动适配（必须执行）

**问题背景**: 社区 Agent（如 OMC `analyst`、`code-reviewer`、`explore` 等）frontmatter 常含 `disallowedTools: Write, Edit`，但 autopilot 各 Phase 大多需要写盘权限。若直接拉来用，子 Agent 在 Phase 1/2/4/5/7 会无法写产物，触发 L2 阻断或交付物缺失。

**适配协议（确定性、幂等）**:

```
Bash('python3 ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/adapt-agent-tools.py --project-root "$(pwd)"')
```

脚本行为：

1. 读取 `.claude/autopilot.config.yaml` 中所有 `phases.*.agent`（含 `parallel.default_agent`、`parallel.domain_agents.*.agent`、`research.agent`、`review_agent`、`code_review.agent`）。
2. 对每个 (phase, agent) 二元组，按内置 `PHASE_REQUIRED_TOOLS` 矩阵计算 `disallowedTools ∩ required_tools`。
3. 冲突非空时，**fork** 源 agent 文件到 `.claude/agents/{name}.md`，剥离冲突项；写入 HTML 注释标记 fork 来源与原因；不修改 marketplace 源文件。
4. 已 fork 或无冲突 → 跳过；幂等可重复执行。
5. 输出结构化 JSON（`forked` / `would_fork` / `already_forked` / `ok` / `missing` 计数与详情），由主线程渲染摘要给用户。

**展示给用户**:

```
✓ Agent 工具权限适配完成
  - 已 fork 适配: {forked} 个
  - 未冲突保留: {ok} 个
  - 未找到源文件: {missing} 个 → 请检查 agent 是否已安装
适配产物: .claude/agents/*.md
```

> **设计意图**：消除"agent 想写但被 disallowedTools 挡住"导致的运行期 L2 失败。fork 而非原地修改，保持 marketplace agent 干净，可随时 `rm .claude/agents/{name}.md` 回退。

## Step 6: Schema 验证

**读取规则**: `references/config-schema.md`（Schema 验证规则章节）

写入后**必须**按 `config-schema.md` 中的 schema 验证配置完整性。校验失败 → 输出缺失/错误的 key 列表，AskUserQuestion 要求用户修正后重试。

## 幂等性

多次运行不会破坏已有配置。已存在时必须用户确认才能覆盖。
