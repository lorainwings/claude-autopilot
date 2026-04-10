---
name: autopilot-dispatch
description: "[ONLY for autopilot orchestrator] Sub-Agent dispatch protocol for autopilot phases. Constructs Task prompts with JSON envelope contract, explicit path injection, and parameterized templates."
user-invocable: false
---

# Autopilot Dispatch — 子 Agent 调度协议

> **前置条件自检**：本 Skill 仅在 autopilot 编排主线程中使用。如果当前上下文不是 autopilot 编排流程，请立即停止并忽略本 Skill。

从 `autopilot.config.yaml` 读取项目配置，构造标准化 Task prompt 分派子 Agent。

### 共享基础设施依赖

本 Skill 依赖 `scripts/_common.sh` 提供的以下共享函数，**不重复实现**配置/锁文件解析：

| 函数 | 用途 |
|------|------|
| `read_config_value(project_root, key_path, default)` | 读取 `autopilot.config.yaml` 标量配置值（PyYAML → regex 自动降级） |
| `read_lock_json_field(lock_file, field, default)` | 提取锁文件 JSON 字段（mode、change、anchor_sha 等） |
| `parse_lock_file(lock_file_path)` | 解析锁文件获取 change 名称（JSON/legacy 自动兼容） |
| `find_active_change(changes_dir, trailing_slash)` | 按优先级查找活跃 change 目录（锁文件 → checkpoint → mtime） |
| `find_checkpoint(phase_results_dir, phase_number)` | 查找指定阶段的最新 checkpoint 文件 |
| `scan_all_checkpoints(phase_results_dir, mode)` | 按阶段顺序扫描全部 checkpoint，返回 JSON 结果 |

> 上述函数的实现和参数说明详见 `scripts/_common.sh`。

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

**执行前读取**: `autopilot/references/dispatch-prompt-template.md`（完整的 Prompt 构造模板，含 for-each 循环和模型路由注入）

按模板构造子 Agent prompt，注入优先级从高到低：instruction_files → reference_files → Project Rules → project_context → test_suites → services → Phase 1 Steering → 内置规则。

### 模型路由 dispatch 流程（v5.3）

**执行前读取**: `autopilot/references/dispatch-model-routing.md`（完整的 5 步路由流程 + Banner + 事件发射）

**默认 Phase 路由策略**:

| Phase | tier | model | 理由 |
|-------|------|-------|------|
| 1 | deep | opus | 需求分析需要深度推理 |
| 2 | fast | haiku | OpenSpec 创建是机械性操作 |
| 3 | fast | haiku | FF 生成是模板化操作 |
| 4 | deep | opus | 测试设计需要创造力 |
| 5 | deep | opus | 代码实施需要最强推理能力 |
| 6 | fast | haiku | 报告生成是机械性操作 |
| 7 | fast | haiku | 汇总与归档较简单 |

**升级策略**: fast →(失败1次)→ standard →(失败2次)→ deep →(仍失败)→ 人工决策

### 优先级 2.5: Project Rules Auto-Scan（v3.0 增强）

**执行前读取**: `autopilot/references/dispatch-rules-injection.md`（完整的注入模板 + 执行流程）

**触发条件**：所有通过 Task 派发的阶段（Phase 2-6）

**阶段差异化注入**：

| 阶段 | 注入内容 |
|------|---------|
| Phase 2-3 | 紧凑摘要（仅 critical_rules，≤5 条） |
| Phase 4 | 完整规则（测试需验证代码符合约束） |
| Phase 5 | 完整规则 + 实时 Hook 强制执行 |
| Phase 6 | 紧凑摘要（报告中引用约束合规状态） |

## 内置模板解析（v3.0 新增）

当构造 Phase 4/5/6 prompt 时，检查 `config.phases[phase].instruction_files`：

1. **非空** → 使用项目自定义指令文件（覆盖内置模板）
2. **为空（默认）** → 使用插件内置模板（`autopilot/templates/phase{N}-*.md`）

内置模板中的 `{variable}` 占位符在 dispatch 时从 config 动态替换。

### 模板路径映射

| Phase | 内置模板 |
|-------|---------|
| 4 | `autopilot/templates/phase4-testing.md` + `autopilot/templates/shared-test-standards.md` |
| 5 | `autopilot/templates/phase5-serial-task.md` + `autopilot/templates/shared-test-standards.md` |
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
执行以下确定性脚本校验前置 checkpoint，**禁止自行编写 Python/Bash 读取代码**：
Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/check-predecessor-for-subagent.sh "openspec/changes/{change_name}/context/phase-results" "{N}" "{mode}"')
脚本自动通过 mode-aware phase graph 计算正确的前驱阶段（支持 full/lite/minimal + TDD 覆盖）。
解析返回的 JSON（格式: `{"exists": true/false, "status": "ok"/"warning"/..., "predecessor": N}`）：
- 如果 `predecessor` 为 0 → 无前驱，直接继续
- 如果 `exists` 为 false → 立即返回：
  `{"status": "blocked", "summary": "Phase {predecessor} checkpoint 不存在"}`
- 如果 `status` 不是 "ok" 或 "warning" → 立即返回：
  `{"status": "blocked", "summary": "Phase {predecessor} 状态为 {status}"}`
- 校验通过后，继续执行本阶段任务。
```

### 各阶段调度内容

### 子 Agent 进度 emit 协议（v5.7 — 所有 Phase 生效）

dispatch 构造的子 Agent prompt 中**必须**注入以下进度汇报指令：

```markdown
## 进度汇报（强制）
在执行过程中，你**必须**在以下时间点发射进度事件：
1. **开始处理每个子任务时**:
   `Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-task-progress.sh "{task_id}" running {index} {total} {mode} "" "0" {phase}')`
2. **每个子任务完成时**:
   `Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-task-progress.sh "{task_id}" passed {index} {total} {mode} "" "0" {phase}')`
3. **子任务失败时**:
   `Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-task-progress.sh "{task_id}" failed {index} {total} {mode} "" "0" {phase}')`
```

> 这些事件驱动 GUI 仪表盘实时进度显示。未发射进度事件的 Agent 在 GUI 上显示为"静默运行中"。

### 各阶段 dispatch 摘要

**执行前读取**: `autopilot/references/dispatch-phase-prompts.md`（完整的各阶段 prompt 构造逻辑）

**Phase 1**: 技术调研（Agent: general-purpose）+ 需求分析（Agent: business-analyst）。主线程调度，不含 autopilot-phase 标记。上下文隔离红线：主线程禁止 Read 调研正文，BA Agent 在自己的执行环境中直接 Read 调研文件（供 BA 自行 Read）。

**Phase 2**: 创建 OpenSpec（Agent: Plan）。`run_in_background: true`。必须返回含 status + summary 的 JSON 信封。

**Phase 3**: FF 生成制品（Agent: Plan）。`run_in_background: true`。必须返回含 status + summary 的 JSON 信封。

**Phase 4**: 测试用例设计（Agent: qa-expert）。4 类测试全部创建，每类 ≥ min_test_count_per_type。status 只允许 "ok" 或 "blocked"（禁止 "warning"）。TDD 模式下由 Phase 5 吸收。

**Phase 5**: 循环实施 — 互斥三路径。路径 A: 并行（parallel.enabled=true）、路径 B: 串行（parallel.enabled=false 或降级）、路径 C: TDD（tdd_mode=true + full 模式）。dispatch 自行读取 phase5-implementation.md / parallel-phase5.md / mode-routing-table.md。

**Phase 6**: 测试报告（Agent: qa-expert）+ 三路并行（测试 + 代码审查 + 质量扫描）。Allure 统一报告详见 protocol.md。

## 并行调度协议（v3.2.0 新增）

**执行前读取**: `autopilot/references/parallel-dispatch.md`（通用协议）+ 当前 Phase 对应的 `parallel-phase{N}.md`（按需加载，v5.2 拆分）

| Phase | 并行条件 | 配置项 |
|-------|---------|--------|
| 1 | 始终并行（Auto-Scan + 调研 + 搜索） | `config.phases.requirements.research.enabled` |
| 4 | `config.phases.testing.parallel.enabled = true` | 按测试类型分组 |
| 5 | `config.phases.implementation.parallel.enabled = true` | 按文件域分组 |
| 6 | `config.phases.reporting.parallel.enabled = true`（默认 true） | 按测试套件分组 |
