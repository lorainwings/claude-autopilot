# Dispatch 各阶段 Prompt 构造

> 本文件从 `autopilot-dispatch/SKILL.md` 提取，供 dispatch 构造特定 Phase 子 Agent prompt 时按需读取。

## Phase 1（技术调研 — 主线程调度，不含 autopilot-phase 标记）

- Agent: config.phases.requirements.research.agent（默认 Explore）
- 条件：`config.phases.requirements.research.enabled === true`
- 任务：分析与需求相关的现有代码、依赖兼容性、技术可行性
- Prompt 必须注入：RAW_REQUIREMENT + Steering Documents 路径
- 返回：JSON 格式的 impact_analysis / dependency_check / feasibility / risks
- 此 Task 不含 `autopilot-phase` 标记 → 不受 Hook 门禁校验（设计预期）
- 失败两次后标记 `research_status: "skipped"`，不阻断流程

## Phase 1（需求分析 — 主线程调度，不含 autopilot-phase 标记）

- Agent: config.phases.requirements.agent（默认 business-analyst）
- 任务：基于 Steering + Research 上下文分析需求，产出功能清单 + 疑问点
- Prompt 必须注入：RAW_REQUIREMENT + 所有 Steering Documents 路径（供 BA 自行 Read）+ 调研信封摘要（decision_points + tech_constraints + complexity）
- **上下文隔离红线**（v6.0）：主线程**禁止**读取 `research-findings.md` 或 `web-research-findings.md` 正文内容。
  - 主线程仅向 BA prompt 注入：(1) 各调研 Agent 返回的 JSON 信封中的结构化字段（summary、decision_points、tech_constraints、complexity、key_files），(2) 产出文件路径（供 BA 自行 Read）
  - BA Agent 在自己的执行环境中直接 `Read(research-findings.md)` 和 `Read(web-research-findings.md)`
- **联网调研结果注入**（v6.0 修订）：当联网搜索 Agent 返回信封中 `search_decision == "searched"` 时，向 BA prompt 追加以下指令：

  ```
  ## 联网调研结果
  联网搜索 Agent 已完成调研，摘要: {web_research_envelope.summary}
  决策点: {web_research_envelope.decision_points}
  请自行读取完整调研报告: Read(openspec/changes/{change_name}/context/web-research-findings.md)
  基于调研结果，在分析中：
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
  - 引用你自行 Read 的 research-findings.md 中的调研数据支撑推荐
  ```

- 返回值校验：非空，且包含功能清单和疑问点

## Phase 2（创建 OpenSpec）

- Agent: config.phases.openspec.agent（默认 Plan，v3.4.0）
- 运行模式: `run_in_background: true`（不占用主窗口上下文）
- 任务：从需求推导 kebab-case 名称，执行 `openspec new change "<name>"`
- 写入 context 文件（prd.md、discussion.md、ai-prompt.md）
- **返回要求（必须严格遵守）**：执行完毕后，在输出的**最后一行**返回 JSON 信封：

  ```json
  {"status": "ok", "summary": "已创建 OpenSpec change: <name>，包含 N 个文件", "artifacts": ["openspec/changes/<name>/proposal.md", ...]}
  ```

  > Hook 验证要求 `status` 和 `summary` 两个字段都必须存在，缺少任一将被 block。

## Phase 3（FF 生成制品）

- Agent: config.phases.openspec.agent（默认 Plan，v3.4.0）
- 运行模式: `run_in_background: true`（不占用主窗口上下文）
- 任务：按 openspec-ff-change 流程生成 proposal/specs/design/tasks
- **返回要求（必须严格遵守）**：执行完毕后，在输出的**最后一行**返回 JSON 信封：

  ```json
  {"status": "ok", "summary": "已生成 OpenSpec 制品: proposal/design/specs/tasks", "artifacts": ["openspec/changes/<name>/proposal.md", "openspec/changes/<name>/design.md", ...]}
  ```

  > Hook 验证要求 `status` 和 `summary` 两个字段都必须存在，缺少任一将被 block。

## Phase 4（测试用例设计）

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

## Phase 5（循环实施 — 互斥双路径）

**dispatch 自行读取参考文档（v5.7 — 主线程上下文节制化）**:

dispatch skill 在构造 Phase 5 prompt **之前**，自行读取以下参考文档：

1. Read `autopilot/references/phase5-implementation.md` — 串行/并行/TDD 执行细节
2. Read `autopilot/references/parallel-phase5.md` — 域级并行 dispatch 模板
3. Read `autopilot/references/mode-routing-table.md` — 路径选择规则

> 主线程不再读取这些文档。dispatch skill 作为 Skill 调用，上下文独立于主线程。

**Phase 4 测试文件注入（full 模式测试驱动增强）**:

当主线程传入 `phase4_test_files`（非空数组）时，dispatch 在构造子 Agent prompt 时**必须**注入测试驱动开发段落：

1. **Task 级测试映射**（优先）：当主线程同时传入 `phase4_test_traceability`（`[{test, requirement}]`）时，dispatch **必须**按 task 描述与 `requirement` 字段匹配，仅向每个 task 的 prompt 注入与其相关的测试文件：
   - 匹配算法：task 描述/标题中的关键词与 `requirement` 字段做模糊匹配
   - 匹配到 → 仅注入匹配的测试文件
   - 未匹配到（task 描述与所有 requirement 均无交集）→ 不注入测试先行段落（该 task 无 Phase 4 覆盖）
2. **扁平注入**（向后兼容）：当 `phase4_test_traceability` 不可用时，将全部 `phase4_test_files` 注入到 prompt 的 `## 测试驱动开发（Phase 4 测试先行验证）` 段落
3. 串行模式（路径 B）：按 Task Prompt 模板中的 `{if phase4_test_files}` 条件块注入
4. 并行模式（路径 A）：按域 Agent 模板中的 `{if phase4_test_files}` 条件块注入
5. Batch Scheduler 模式：按 Batch 派发模板中的 `{if phase4_test_files}` 条件块注入

> 当 `phase4_test_files` 为空（lite/minimal 模式或 Phase 4 未执行）时，不注入测试驱动段落，子 Agent prompt 与之前行为一致。

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
  - **TDD 进度事件发射（主线程）**: 主线程在每个 TDD 步骤的 Task 派发前后，**必须**发射带 `tdd_step` 参数的进度事件，使 GUI 看板能实时展示 RED/GREEN/REFACTOR 状态：

    ```
    # RED 步骤开始
    Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-task-progress.sh "task-{N}-{slug}" running {N} {total} {mode} "red"')
    → 派发 RED Task → 等待完成 → L2 验证（exit_code ≠ 0）
    Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-task-progress.sh "task-{N}-{slug}" passed {N} {total} {mode} "red"')

    # GREEN 步骤开始
    Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-task-progress.sh "task-{N}-{slug}" running {N} {total} {mode} "green"')
    → 派发 GREEN Task → 等待完成 → L2 验证（exit_code = 0）
    Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-task-progress.sh "task-{N}-{slug}" passed {N} {total} {mode} "green"')

    # REFACTOR 步骤开始（可选）
    Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-task-progress.sh "task-{N}-{slug}" running {N} {total} {mode} "refactor"')
    → 派发 REFACTOR Task → 等待完成 → L2 验证（测试仍通过）
    Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-task-progress.sh "task-{N}-{slug}" passed {N} {total} {mode} "refactor"')
    ```

    > 失败时 status 改为 `failed`，tdd_step 保持当前步骤值。GUI 据此展示 TDD 步骤图标。
  - **并行 TDD**（`parallel.enabled: true`）：域 Agent prompt 注入完整 TDD 纪律文档
    - 域 Agent prompt 中**必须**注入 `emit-task-progress.sh` 调用模板（含 `tdd_step` 参数），要求域 Agent 在每个 task 的 RED/GREEN/REFACTOR 步骤前后发射进度事件
    - 详见 `references/tdd-cycle.md` 并行 TDD 章节中的 prompt 模板

- 项目上下文从 config.project_context + config.test_suites 自动注入（快速校验命令 = test_suites 中 type=typecheck 的套件）
- 可选覆盖：config.phases.implementation.instruction_files（非空时注入）

  Phase 5 并行 Task prompt 完整模板详见 `references/parallel-phase5.md` Step 3。

- **Worktree 隔离模式**（当 config.phases.implementation.worktree.enabled = true）：
  - 主线程按 task 粒度逐个派发，每个 task 使用 `Task(isolation: "worktree")`
  - 子 Agent prompt 中注入当前 task 内容和前序 task 摘要
  - 子 Agent 完成后返回 worktree 路径和分支名，主线程决定合并策略

## Phase 6（测试报告）

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
