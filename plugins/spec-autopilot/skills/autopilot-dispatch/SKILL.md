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

### 模型路由 dispatch 流程（v5.3 新增）

dispatch 子 Agent **之前**，主线程必须执行模型路由解析：

1. **调用 resolver**:
   ```bash
   ROUTING_JSON=$(bash <plugin_scripts>/resolve-model-routing.sh "$PROJECT_ROOT" "$PHASE" "$COMPLEXITY" "$REQUIREMENT_TYPE" "$RETRY_COUNT" "$CRITICAL")
   ```

2. **提取路由结果**:
   ```bash
   SELECTED_TIER=$(echo "$ROUTING_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['selected_tier'])")
   SELECTED_MODEL=$(echo "$ROUTING_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['selected_model'])")
   ```

3. **选择 subagent 层级**:
   - `autopilot-fast` → haiku (tier=fast)
   - `autopilot-standard` → sonnet (tier=standard)
   - `autopilot-deep` → opus (tier=deep)

4. **注入 prompt + 传递 model 参数**:
   - 将路由结果注入 prompt 的"执行模式"段落
   - 当 Claude Code 支持 `model` 参数时直接传递
   - 否则退化为 `CLAUDE_CODE_SUBAGENT_MODEL` 环境变量

5. **发射路由事件**（`$AGENT_ID` 为必填参数，并行场景下用于精确归因）:
   ```bash
   bash <plugin_scripts>/emit-model-routing-event.sh "$PROJECT_ROOT" "$PHASE" "$MODE" "$ROUTING_JSON" "$AGENT_ID"
   ```
   - `$AGENT_ID` 格式为 `phase{N}-{slug}`，与 auto-emit-agent-dispatch.sh 生成的一致
   - 缺少 agent_id 的路由事件在并行场景下会被 statusline-collector 拒绝匹配
   - statusline-collector.sh 会自动比较观测模型与请求模型，发射 `model_effective` 事件
   - 当 Task 因模型不可用失败并使用 fallback 重试时，发射 `model_fallback` 事件:
   ```bash
   bash <plugin_scripts>/emit-model-routing-event.sh "$PROJECT_ROOT" "$PHASE" "$MODE" \
     '{"requested_model":"opus","fallback_model":"sonnet","fallback_reason":"Rate limit"}' "$AGENT_ID" "model_fallback"
   ```

5.5. **主线程醒目输出模型路由 Banner**（v5.7）:
   解析 `ROUTING_JSON` 后，主线程 stdout 直接打印以下内容（用户可见）：
   ```
   ╔══════════════════════════════════════════════════╗
   ║ 🤖 Phase {N} Model: {SELECTED_MODEL} ({SELECTED_TIER})
   ║    Effort: {SELECTED_EFFORT} | Reason: {routing_reason}
   ╚══════════════════════════════════════════════════╝
   ```
   - `escalated_from` 非 null → 追加: `║    ⬆️ Escalated from: {escalated_from}`
   - `fallback_applied == true` → 追加: `║    ⚠️ Fallback to: {fallback_model}`
   - **实现**: 主线程 print 即可，无需新脚本。

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

{if config.code_constraints.semantic_rules 非空}
### 语义规则（项目特定，必须遵守）
{for each rule in config.code_constraints.semantic_rules where rule.scope matches current_phase_domain}
- **[{rule.severity}]** {rule.rule}（适用范围: `{rule.scope}`）
{end for}

> required/naming 类规则已通过 `_constraint_loader.py:load_scanner_constraints()` 合并进 L2 Hook 检测链。
> `semantic_rules` 中若有路径可限定的规则，建议转为 `code_constraints.required_patterns` 以获得 L2 确定性检测。
> 纯语义规则仍依赖 AI 遵守 + Phase 6.5 审查。
{end if}
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
1. 读取 `openspec/changes/{change_name}/context/phase-results/phase-{N-1}-*.json`
2. 如果文件不存在 → 立即返回：
   `{"status": "blocked", "summary": "Phase {N-1} checkpoint 不存在"}`
3. 如果 status 不是 "ok" 或 "warning" → 立即返回：
   `{"status": "blocked", "summary": "Phase {N-1} 状态为 {status}"}`
4. 校验通过后，继续执行本阶段任务。
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
- Prompt 必须注入：RAW_REQUIREMENT + 所有 Steering Documents + research-findings.md + web-research-findings.md（如存在）+ complexity 评估结果
- **联网调研结果注入**（v2.4.0 → v3.2.1 独立文件）：当 `web-research-findings.md` 存在时，追加以下指令：
  ```
  ## 联网调研结果（如存在）
  读取 web-research-findings.md（独立文件，由并行联网搜索 Agent 生成）。
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
- Agent: config.phases.openspec.agent（默认 Plan，v3.4.0）
- 运行模式: `run_in_background: true`（不占用主窗口上下文）
- 任务：从需求推导 kebab-case 名称，执行 `openspec new change "<name>"`
- 写入 context 文件（prd.md、discussion.md、ai-prompt.md）
- **返回要求（必须严格遵守）**：执行完毕后，在输出的**最后一行**返回 JSON 信封：
  ```json
  {"status": "ok", "summary": "已创建 OpenSpec change: <name>，包含 N 个文件", "artifacts": ["openspec/changes/<name>/proposal.md", ...]}
  ```
  > Hook 验证要求 `status` 和 `summary` 两个字段都必须存在，缺少任一将被 block。

**Phase 3（FF 生成制品）**：
- Agent: config.phases.openspec.agent（默认 Plan，v3.4.0）
- 运行模式: `run_in_background: true`（不占用主窗口上下文）
- 任务：按 openspec-ff-change 流程生成 proposal/specs/design/tasks
- **返回要求（必须严格遵守）**：执行完毕后，在输出的**最后一行**返回 JSON 信封：
  ```json
  {"status": "ok", "summary": "已生成 OpenSpec 制品: proposal/design/specs/tasks", "artifacts": ["openspec/changes/<name>/proposal.md", "openspec/changes/<name>/design.md", ...]}
  ```
  > Hook 验证要求 `status` 和 `summary` 两个字段都必须存在，缺少任一将被 block。

**Phase 4（测试用例设计）**：
- Agent: config.phases.testing.agent（默认 qa-expert）
- 项目上下文从 config.project_context + config.test_suites + Phase 1 Steering Documents 自动注入
- 可选覆盖：config.phases.testing.instruction_files / reference_files（非空时注入）
- 门禁：4 类测试全部创建、每类 ≥ min_test_count_per_type
- **Phase 4 在 full 模式下不可跳过，不可降级为 warning**（TDD 模式除外：当 `tdd_mode: true` 且 `mode: full` 时，Phase 4 由 Phase 5 吸收，标记 `skipped_tdd`）

Phase 4 子 Agent prompt 构造详见以下参考文件（dispatch 时读取并注入）：
- 内置模板：`autopilot/templates/phase4-testing.md`（测试标准 + dry-run + 金字塔）
- 并行 dispatch：`autopilot/references/parallel-phase4.md`（Phase 4 并行模板）

**关键约束摘要**（完整指令在参考文件中）：
- 必须创建实际测试文件，禁止以任何理由跳过
- 每种 test_type ≥ `min_test_count_per_type` 个用例
- `change_coverage.coverage_pct` ≥ 80%，否则 blocked
- 测试金字塔: unit ≥ `min_unit_pct`%，e2e ≤ `max_e2e_pct`%
- 每个测试用例必须追溯到 Phase 1 需求点（traceability matrix）
- status 只允许 "ok" 或 "blocked"（禁止 "warning"）


**Phase 5（循环实施 — 互斥双路径）**：

**dispatch 自行读取参考文档（v5.7 — 主线程上下文节制化）**:

dispatch skill 在构造 Phase 5 prompt **之前**，自行读取以下参考文档：
1. Read `autopilot/references/phase5-implementation.md` — 串行/并行/TDD 执行细节
2. Read `autopilot/references/parallel-phase5.md` — 域级并行 dispatch 模板
3. Read `autopilot/references/mode-routing-table.md` — 路径选择规则

> 主线程不再读取这些文档。dispatch skill 作为 Skill 调用，上下文独立于主线程。

Phase 5 有两条**互斥**的执行路径，由 `config.phases.implementation.parallel.enabled` 决定。
当 `config.phases.implementation.tdd_mode: true` 且模式为 `full` 时，进入 **TDD 模式**（路径 C）。

- **路径 A: 并行模式**（当 `parallel.enabled = true` 时，**优先执行**）：
  - **禁止进入路径 B 或使用串行 Task 派发流程**
  - 执行前读取: `references/parallel-phase5.md`（Phase 5 完整 dispatch 模板）
  - 主线程解析任务清单 -> 按 config.domain_agents 路径前缀分域 -> 生成 owned_files -> 并行派发 Task(isolation: "worktree", run_in_background: true)
  - 最大并行数 = config.phases.implementation.parallel.max_agents（默认 8）
  - 每组完成后: 按 task 编号合并 worktree -> 快速验证 -> 批量 review -> checkpoint
  - 降级: 合并失败超过 3 文件 -> 切换到路径 B

- **路径 B: 串行模式**（当 `parallel.enabled = false` 时执行，或从路径 A 降级后以前台 Task 形式执行）：
  > **v5.8 约束**: 从路径 A 降级时，路径 B 仍通过 `Task(run_in_background: false)` 派发子 Agent，
  > **主线程不直接编码实施任何 task**。
  - 主线程逐个派发**前台 Task**（同步阻塞），按域动态选择 Agent（v3.4.0）：
    ```
    # 三步域检测（与并行模式相同算法）：前缀匹配 → auto 发现 → fallback
    domain = longest_prefix_match(task.affected_files, config...domain_agents.keys())
    agent = resolve_agent(domain) || config...default_agent
    ```
  - 子 Agent 内部工具调用不灌入主线程上下文（上下文隔离）
  - 每个 task 完成后写入 `phase5-tasks/task-N.json` checkpoint
  - 连续 3 次失败 → AskUserQuestion 决策
  - Task prompt 模板详见 `references/phase5-implementation.md` 串行模式章节

- **路径 C: TDD 模式**（当 `tdd_mode: true` 且模式为 `full`）：
  - **执行前读取**: `references/tdd-cycle.md` + `references/testing-anti-patterns.md`
  - **串行 TDD**（`parallel.enabled: false`）：每个 task 派发 3 个 sequential Task：
    - **RED Task**: `Task(prompt: "TDD RED — 写失败测试 for task-N")`
      - prompt 注入 Iron Law + 反合理化清单 + 反模式指南
      - prompt 注入任务描述 + 项目上下文
      - 必须返回: `{ test_file, test_command }`
      - 禁止写实现代码
    - **GREEN Task**: `Task(prompt: "TDD GREEN — 写最小实现 for task-N")`
      - prompt 注入测试文件路径 + "fix implementation, never modify test"
      - 必须返回: `{ impl_files, summary }`
    - **REFACTOR Task**（当 `tdd_refactor: true`）: `Task(prompt: "TDD REFACTOR — 清理代码 for task-N")`
      - prompt 注入 "keep tests green, don't add behavior"
      - 禁止修改测试文件
  - **并行 TDD**（`parallel.enabled: true`）：域 Agent prompt 注入完整 TDD 纪律文档
    - 详见 `references/tdd-cycle.md` 并行 TDD 章节中的 prompt 模板

- 项目上下文从 config.project_context + config.test_suites 自动注入（快速校验命令 = test_suites 中 type=typecheck 的套件）
- 可选覆盖：config.phases.implementation.instruction_files（非空时注入）

  Phase 5 并行 Task prompt 完整模板详见 `references/parallel-phase5.md` Step 3。

- **Worktree 隔离模式**（当 config.phases.implementation.worktree.enabled = true）：
  - 主线程按 task 粒度逐个派发，每个 task 使用 `Task(isolation: "worktree")`
  - 子 Agent prompt 中注入当前 task 内容和前序 task 摘要
  - 子 Agent 完成后返回 worktree 路径和分支名，主线程决定合并策略

**Phase 6（测试报告）**：
- Agent: qa-expert
- 测试命令从 config.test_suites 动态读取（全量运行所有 suite）
- 报告命令从 config.phases.reporting.report_commands 读取
- 可选覆盖：config.phases.reporting.instruction_files（非空时注入）
- **三路并行**（v3.2.2）：Phase 6 测试执行与 Phase 6.5 代码审查、质量扫描在同一消息中同时派发
  - 路径 A：Phase 6 测试（前台 Task）
  - 路径 B：Phase 6.5 代码审查（`run_in_background: true`，不含 autopilot-phase 标记）
  - 路径 C：质量扫描（多个 `run_in_background: true`，不含 autopilot-phase 标记）
  - Phase 7 统一收集三路结果
- **Allure 统一报告**（当 `config.phases.reporting.format === "allure"` 时）：
  > 详见 `autopilot/references/protocol.md` Allure 报告章节。
  前置检查 Allure 安装 → 统一 `ALLURE_RESULTS_DIR` 输出 → 生成报告 → 降级为 `report_format: "custom"`。

## 并行调度协议（v3.2.0 新增）

**执行前读取**: `autopilot/references/parallel-dispatch.md`（通用协议）+ 当前 Phase 对应的 `parallel-phase{N}.md`（按需加载，v5.2 拆分）

概要：当阶段支持并行执行时，dispatch 按 `references/parallel-dispatch.md`（通用协议）+ `references/parallel-phase{N}.md`（阶段模板）构造并行 Task prompt。

| Phase | 并行条件 | 配置项 |
|-------|---------|--------|
| 1 | 始终并行（Auto-Scan + 调研 + 搜索） | `config.phases.requirements.research.enabled` |
| 4 | `config.phases.testing.parallel.enabled = true` | 按测试类型分组 |
| 5 | `config.phases.implementation.parallel.enabled = true` | 按文件域分组 |
| 6 | `config.phases.reporting.parallel.enabled = true`（默认 true） | 按测试套件分组 |
