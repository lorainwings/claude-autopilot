---
name: autopilot-setup
description: "Initialize autopilot config by scanning project structure. Auto-detects tech stack, services, and test suites to generate .claude/autopilot.config.yaml."
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

**读取模板**: `autopilot/references/config-schema.md`（完整 YAML 配置模板）

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

### Step 5.3: Agent 安装引导

始终通过 AskUserQuestion 引导用户安装专业 Agent。详见 `references/setup-agent-model-guide.md`。

### Step 5.4: 模型路由引导

引导用户配置模型路由策略。详见 `references/setup-agent-model-guide.md`。

## LSP 推荐

**执行前读取**: `references/setup-lsp-recommendation.md`（LSP 推荐映射表 + 交互）

### Step 5.5: LSP 插件推荐

根据检测到的技术栈推荐 Claude Code LSP 插件。详见 `references/setup-lsp-recommendation.md`。

## Step 6: Schema 验证

**读取规则**: `autopilot/references/config-schema.md`（Schema 验证规则章节）

写入后**必须**按 `config-schema.md` 中的 schema 验证配置完整性。校验失败 → 输出缺失/错误的 key 列表，AskUserQuestion 要求用户修正后重试。

## 幂等性

多次运行不会破坏已有配置。已存在时必须用户确认才能覆盖。
