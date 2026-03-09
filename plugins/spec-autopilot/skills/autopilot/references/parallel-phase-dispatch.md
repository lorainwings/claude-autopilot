# 并行阶段调度模板

> 本文件由 autopilot-dispatch SKILL.md 引用。包含 Phase 1/4/5/6 的并行 Task prompt 构造模板。
> 通用并行编排协议详见 `parallel-dispatch.md`。

## 并行调度协议（v3.2.0 新增）

当阶段支持并行执行时，dispatch 按 `references/parallel-dispatch.md` 协议构造并行 Task prompt。

### 并行调度触发条件

| Phase | 并行条件 | 配置项 |
|-------|---------|--------|
| 1 | 始终并行（Auto-Scan + 调研 + 搜索） | `config.phases.requirements.research.enabled` |
| 4 | `config.phases.testing.parallel.enabled = true` | 按测试类型分组 |
| 5 | `config.phases.implementation.parallel.enabled = true` | 按文件域分组 |
| 6 | `config.phases.reporting.parallel.enabled = true`（默认 true） | 按测试套件分组 |

### Phase 1 并行调度

主线程同时派发 2-3 个 Task（不含 autopilot-phase 标记，不受 Hook 校验）：

```markdown
# Task 1: Auto-Scan（Explore agent）
Task(subagent_type: "Explore", run_in_background: true,
  prompt: "分析项目结构，生成 Steering Documents:
  - project-context.md（技术栈、目录结构）
  - existing-patterns.md（现有代码模式）
  - tech-constraints.md（技术约束）
  输出到: openspec/changes/{change_name}/context/"
)

# Task 2: 技术调研（Explore agent）
Task(subagent_type: "Explore", run_in_background: true,
  prompt: "分析与需求相关的代码:
  需求: {RAW_REQUIREMENT}
  重点: 影响范围、依赖兼容性、技术可行性
  输出到: openspec/changes/{change_name}/context/research-findings.md"
)

# Task 3: 联网搜索（条件派发）
{if config.phases.requirements.web_search.enabled}
Task(subagent_type: "general-purpose", run_in_background: true,
  prompt: "联网搜索与需求相关的最佳实践:
  需求: {RAW_REQUIREMENT}
  搜索不超过 {config.phases.requirements.web_search.max_queries} 个查询
  输出结构化结果到: openspec/changes/{change_name}/context/web-research-findings.md
  注意: 输出到独立文件 web-research-findings.md，不要修改 research-findings.md"
)
{end if}
```

等待全部完成 → 主线程合并 research-findings.md 和 web-research-findings.md（如存在）的内容 → 传递给 business-analyst 分析。

### Phase 4 并行调度

按 `config.phases.testing.gate.required_test_types` 中的测试类型分组，每种类型派发一个子 Agent：

```markdown
{for each test_type in config.phases.testing.gate.required_test_types}
Task(subagent_type: "{agent_for_type}", run_in_background: true,
  prompt: "<!-- autopilot-phase:4 -->
  你是 autopilot Phase 4 的并行测试设计子 Agent（{test_type} 专项）。

  ## 需求追溯（必须遵守）
  以下是 Phase 1 确认的需求清单，每个测试用例必须关联到至少一个需求点：
  {phase1_requirements_summary}
  {phase1_decisions}

  ## 你的任务
  仅创建 {test_type} 类型的测试用例（≥ {min_test_count_per_type} 个）。
  测试套件配置: {config.test_suites[test_type]}

  ## 测试追溯要求
  每个测试用例必须包含注释，说明其追溯的需求点:
  // Traces: REQ-1.1 用户登录功能
  
  ## 返回要求
  {"status": "ok|blocked", "summary": "...", "test_counts": {"{test_type}": N}, "artifacts": [...], "test_traceability": [{"test": "...", "requirement": "..."}]}
  "
)
{end for}
```

主线程汇合后合并所有子 Agent 的 `test_counts`、`artifacts`、`test_traceability`，验证 test_pyramid。

#### Phase 4 Dispatch 强制指令（非并行和并行通用）

以下指令必须注入到 Phase 4 所有子 Agent prompt 中：

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

### 变更聚焦专项测试（v3.2.5 新增）

测试用例**必须聚焦本次变更点**，不允许只生成泛化测试。

1. 从 tasks.md 或 phase-1-requirements.json 提取本次变更涉及的具体代码单元（函数、端点、组件）
2. 每个变更点至少 1 个专项测试用例
3. 返回信封中必须包含 `change_coverage` 字段：
```json
{
  "change_coverage": {
    "change_points": ["变更点列表"],
    "tested_points": ["已覆盖的变更点"],
    "coverage_pct": 100,
    "untested_points": []
  }
}
```
`coverage_pct` ≥ 80%，否则视为 blocked。

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

### Phase 6 并行调度

按 `config.test_suites` 中的套件分组，每个套件派发一个子 Agent 并行执行：

```markdown
{for each suite in config.test_suites}
Task(subagent_type: "qa-expert", run_in_background: true,
  prompt: "<!-- autopilot-phase:6 -->
  你是 autopilot Phase 6 的并行测试执行子 Agent（{suite_name} 专项）。

  ## 你的任务
  执行以下测试套件并收集结果:
  - 命令: `{suite.command}`
  - 类型: {suite.type}

  ## Allure 集成
  {if config.phases.reporting.format === 'allure'}
  确保测试结果输出到 Allure 格式:
  - pytest: 添加 `--alluredir=allure-results/{suite_name}`
  - Playwright: 设置 `ALLURE_RESULTS_DIR=allure-results/{suite_name}`
  - Gradle: 复制 XML 结果到 `allure-results/{suite_name}/`
  {end if}

  ## 返回要求
  {"status": "ok|warning|failed", "summary": "...", "pass_rate": N, "total": N, "passed": N, "failed": N, "skipped": N, "artifacts": [...]}
  "
)
{end for}
```

主线程汇合后:
1. 合并所有套件的测试结果
2. 运行 `npx allure generate allure-results/ -o allure-report/ --clean`
3. 汇总 pass_rate、异常提醒、报告链接

### Phase 5 并行调度

> **触发条件**: `config.phases.implementation.parallel.enabled = true`
> **强制约束**: 进入并行模式后，禁止进入串行模式或调用串行 Task 派发流程

核心增强（v3.2.0）：
1. **混合模式** — 按独立域分组并行 + 每组完成后批量 review
2. **控制器提取全文** — 主线程一次性读取所有任务文本，subagent 不自己读计划文件
3. **subagent 提问机制** — subagent 可通过 AskUserQuestion 向用户提问
4. **同一 agent 修复** — 发现问题后 resume 同一 agent 修复，不切换上下文

#### Step 1: 任务清单解析

```
主线程读取任务清单:
- full 模式: openspec/changes/{change_name}/tasks.md
- lite/minimal 模式: openspec/changes/{change_name}/context/phase5-task-breakdown.md

解析每个 task 的 affected_files 和 depends_on
主线程一次性提取所有 task 的完整文本（子 Agent 禁止自行读取计划文件）
```

#### Step 2: 文件所有权分区（v3.4.0: 三步域检测）

```python
# Step A: 最长前缀匹配
domain_prefixes = config...domain_agents.keys()
domain_tasks, unmatched = {}, []
for task in all_tasks:
    domains = {longest_prefix(f, domain_prefixes) for f in task.affected_files}
    if len(domains) == 1 and None not in domains:
        domain_tasks[domains.pop()].append(task)
    else:
        unmatched.append(task)

# Step B: auto 发现（祖先冲突检测 — 不创建已配置子前缀的祖先域）
cross_cutting = []
for task in unmatched:
    top = common_top_dir(task.affected_files)
    if top and no_child_prefix(top, domain_prefixes):
        domain_tasks[top].append(task)
    else:
        cross_cutting.append(task)

# Step C: 溢出合并（同 Agent 域合并 → 减少并行数）
if len(domain_tasks) > max_agents:
    # 相同 Agent 的域合并为 1 个逻辑域
    # 例: payment/(backend-dev) + notification/(backend-dev)
    #   → 1 个 backend-developer Agent 处理 2 个域的所有 task
    domain_tasks = coalesce_same_agent_domains(domain_tasks, max_agents)

# 为每个逻辑域生成 owned_files（域内所有 task 文件的并集）
写入: phase5-ownership/{domain_name}.json
```

#### Step 3: 域级并行 Task 派发（v3.4.0 — 单 Agent 模式）

> **HARD CONSTRAINT**: 每个域严格 1 个 Agent，禁止同一域内派发多个 Agent。
> 域内多个 tasks 作为批量任务注入到同一 Agent 的 prompt。

对每个非空域（从域检测结果中获取，**不限定为 backend/frontend/node**），主线程**在同一条消息中**同时派发（最多 8 个并行）：

```markdown
{for each non_empty_domain in domain_tasks.keys()}
Task(
  subagent_type: "{resolve_agent(domain)}",  # 从 domain_agents 查找，合并域取原始域的 Agent
  isolation: "worktree",
  run_in_background: true,
  prompt: "<!-- autopilot-phase:5 -->
你是 autopilot Phase 5 的 {domain} 域实施 Agent。

## 你的任务（批量执行，按编号顺序）
{for each task in domain_tasks}
### Task #{task_number}: {task_title}
{task_full_text}
---
{end for}

## 前序 task 摘要（只读参考）
{for each completed_task in predecessors}
- Task #{n}: {summary} — 已合并到主分支
{end for}

## 上下文（由控制器提取，禁止自行读取计划文件）
{context_injection}

## 文件所有权约束（ENFORCED）
你被分配以下文件的独占所有权：
{domain_all_owned_files}
禁止修改此列表之外的任何文件。
write-edit-constraint-check Hook 会拦截越权修改。

## 并发隔离
- 你运行在独立 worktree 中（每域 1 个 worktree）
- 禁止修改 openspec/ 目录下的 checkpoint 文件
- 禁止修改其他域正在修改的文件: {other_domain_files}
- 完成后 artifacts 必须是 domain_all_owned_files 的子集

## 项目规则约束
{rules_scan_result}

## 执行要求
- 按 task 编号顺序逐个实施
- 每个 task 完成后返回中间状态（便于断点恢复）
- 所有 task 完成后返回汇总 JSON 信封

## 返回要求
执行完毕后返回 JSON 信封：
{\"status\": \"ok|warning|blocked|failed\", \"summary\": \"...\", \"artifacts\": [...], \"tasks_completed\": [1,2,3], \"test_result\": \"N/M passed\"}
"
)
{end for}
```

等待 Claude Code 自动完成通知（禁止 TaskOutput 轮询）。最多 max_agents 个域并行（默认 8），域内串行。

#### Step 4: 合并 + 验证

```
按 task 编号顺序合并:
for each agent in sorted(agents, key=task_number):
  git merge --no-ff autopilot-task-{N} -m "autopilot: task {N} - {title}"
  if conflict and conflict_files > 3: rollback group worktree, degrade to serial
  if conflict and conflict_files <= 3: AskUserQuestion show conflicts
  else: git worktree remove + git branch -d

快速验证: 运行 config.test_suites 中 type=typecheck 的命令
主线程写入 checkpoint: phase5-tasks/task-N.json
```

#### Step 5: 批量 Review（每组完成后）

```markdown
Task(
  subagent_type: "general-purpose",
  prompt: "审查以下变更的规范符合性和代码质量:
  
  {for each agent in group}
  ## Task #{N}: {title}
  变更文件: {artifacts}
  摘要: {summary}
  {end for}
  
  请检查:
  1. 实现是否符合原始需求描述
  2. 代码风格是否符合项目规则约束
  3. 各 task 之间是否有冲突或不一致
  4. 是否有遗漏的边界情况
  
  返回: {\"status\": \"ok|warning\", \"summary\": \"...\", \"findings\": [...]}
  "
)
```

review 发现问题 -> resume 对应 implementer agent 修复

#### Step 6: 跨域串行 + 全量测试

```
cross_cutting_tasks 在所有并行组完成后串行执行
全部完成后运行 full_test（config.test_suites 全量）
```

#### 降级到串行模式

```
触发条件:
- worktree 创建失败: 立即降级
- 单组合并冲突 > 3 文件: 回退该组, 串行执行
- 连续 2 组合并失败: 全面降级
- 用户选择 "切换串行": 全面降级

降级后进入 phase5-implementation.md 的串行模式章节
记录: _metrics.parallel_fallback_reason
```

## 代码生成约束增强（v3.2.0 新增）

### 新增配置项

```yaml
code_constraints:
  # 已有
  forbidden_files: [...]
  forbidden_patterns: [...]
  allowed_dirs: [...]
  max_file_lines: 800
  
  # v3.2.0 新增
  required_patterns:
    - pattern: "createWebHashHistory"
      context: "Vue Router 配置文件"
      message: "Must use Hash mode routing"
  style_guide: "rules/frontend/README.md"  # 注入到 Phase 5 prompt
```

### Phase 5 prompt 增强注入

```markdown
## 代码约束（ENFORCED — Hook 确定性拦截）

### 禁止项
{for each p in config.code_constraints.forbidden_patterns}
- ❌ `{p.pattern}` → {p.message}
{end for}

### 必须使用
{for each p in config.code_constraints.required_patterns}
- ✅ `{p.pattern}` — {p.message}（在 {p.context} 中必须出现）
{end for}

### 代码风格指南
{if config.code_constraints.style_guide}
请读取并遵守: {config.code_constraints.style_guide}
{end if}
```

## 需求理解增强（v3.2.0 新增）

### 复杂度自适应调研深度

| 复杂度 | Auto-Scan | 技术调研 | 联网搜索 | 竞品分析 |
|--------|-----------|---------|---------|---------|
| small | ✅ | ❌ | ❌ | ❌ |
| medium | ✅ | ✅（并行） | ❌ | ❌ |
| large | ✅ | ✅（并行） | ✅（并行） | ✅（并行） |

> 注意：复杂度评估发生在第一轮调研（Auto-Scan）完成后。small 不触发额外调研。
> medium/large 的额外调研以并行方式执行，不增加总耗时。

### 主动决策增强

所有复杂度级别均展示决策卡片（v3.2.0 取消 small 豁免）：
- **small**: 仅关键技术决策点（1-2 个卡片）
- **medium**: 所有识别到的决策点 + 调研依据
- **large**: 全部决策点 + 调研依据 + 竞品对比 + 推荐方案

决策卡片增强字段（v3.2.0）：
```json
{
  "point": "决策点描述",
  "options": [...],
  "research_evidence": "来自 research-findings.md 的数据支撑",
  "recommended": "B",
  "recommendation_reason": "基于调研数据的推荐理由"
}
```

`config.phases.requirements.decision_mode`:
- `proactive`（默认）: AI 主动识别决策点并展示
- `reactive`: 仅在用户提问时展示
