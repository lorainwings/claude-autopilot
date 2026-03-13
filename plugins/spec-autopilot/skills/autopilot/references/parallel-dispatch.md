# 通用并行编排协议

> 本文件由 autopilot SKILL.md 引用，提供跨阶段可复用的并行编排能力。
> Phase 1/4/5/6 的并行执行均基于本协议实现。

## 适用条件判断

并行执行前**必须**验证以下条件：

| 条件 | 检查方式 | 不满足时行为 |
|------|---------|-------------|
| 任务间无文件依赖 | 依赖图分析（Union-Find） | 有依赖的任务串行执行 |
| 无共享状态修改 | affected_files 无交集 | 合并到串行组 |
| 并行模式已启用 | config 检查 | 降级为串行 |

## 核心流程

```
┌─────────────────────────────────────────────────────┐
│                  主线程（控制器）                      │
│                                                      │
│  1. 解析任务列表 → 提取 affected_files               │
│  2. 依赖图分析 → Union-Find 分组                     │
│  3. 主线程提取所有任务完整文本和上下文                  │
│     （子 Agent 不自己读取计划文件）                    │
│  4. 对每个并行组:                                     │
│     ┌─ Task(run_in_background: true, ...)            │
│     ├─ Task(run_in_background: true, ...)            │
│     └─ Task(run_in_background: true, ...)            │
│     ↓ 等待全部完成                                    │
│  5. 收集 JSON envelope                               │
│  6. 合并验证（如需 worktree merge）                   │
│  7. 批量 review（可选）                               │
│  8. 写入 checkpoint                                  │
└─────────────────────────────────────────────────────┘
```

## 输入参数

| 参数 | 类型 | 说明 |
|------|------|------|
| tasks | Task[] | 待并行执行的任务列表 |
| max_parallel | number | 最大并行数（默认 3，上限 10） |
| merge_strategy | "worktree" \| "none" | 是否需要 worktree 隔离和代码合并 |
| review_after | boolean | 组完成后是否执行 review |
| context_injection | string | 注入到每个子 Agent 的公共上下文 |
| phase_marker | string | autopilot-phase 标记（如 `<!-- autopilot-phase:5 -->`） |
| timeout_minutes | number | 后台 Agent 硬超时（默认 30 分钟，从 `config.background_agent_timeout_minutes` 读取） |

## 依赖图分析算法

### Step 1: 任务解析

从任务清单中提取每个 task 的元数据：

```
for each task in tasks:
  task.affected_files = 提取文件路径引用
  task.depends_on = 提取显式依赖声明
  task.domain = 推断所属域（从 affected_files 顶级目录自动发现，或匹配 config.domain_agents 路径前缀）
```

### Step 2: Union-Find 分组

```
初始化: 每个 task 为独立集合
for each (task_i, task_j) in tasks × tasks:
  if task_i.affected_files ∩ task_j.affected_files ≠ ∅:
    union(task_i, task_j)
  if task_j in task_i.depends_on:
    union(task_i, task_j)

独立组 = 所有连通分量
```

### Step 3: 分组排序

```
对每个独立组:
  组优先级 = min(task.number for task in group)
按组优先级升序排列

特殊处理:
  cross_cutting_tasks → 移入最后一个组（串行执行）
```

### Step 4: 域级快速分区（Phase 5 专用）

当 tasks.md 中的 task 按顶级目录自然分离时，可跳过 Union-Find，直接按域分组：

```python
# v3.4.0: 通用域检测（三步算法）

# ---- Step A: 路径前缀匹配（最长优先）----
domain_prefixes = config...domain_agents.keys()
domain_tasks = {}
unmatched = []

for t in tasks:
    # 对 task 全部文件做最长前缀匹配
    domains = set(longest_prefix(f, domain_prefixes) for f in t.affected_files)
    if len(domains) == 1 and None not in domains:
        domain_tasks[domains.pop()].append(t)
    else:
        unmatched.append(t)  # 跨域或无匹配

# ---- Step B: auto 发现（带祖先冲突检测）----
cross_cutting = []
if config...domain_detection == "auto":
    for t in unmatched:
        top_dir = common_top_dir(t.affected_files)  # 例如 "infra/"
        if top_dir and no_child_prefix(top_dir, domain_prefixes):
            # 安全：无已配置的子前缀冲突
            domain_tasks[top_dir].append(t)
        else:
            # 不安全：祖先目录下有子前缀 → 视为跨域
            cross_cutting.append(t)

# ---- Step C: 溢出合并（同 Agent 域合并）----
if len(domain_tasks) > config...max_agents:
    # 将使用相同 Agent 的域合并为逻辑组
    # 例如: payment/(backend-dev) + notification/(backend-dev) + gateway/(backend-dev)
    #     → 合并为 1 个 backend-developer Agent 处理 3 个域
    agent_groups = group_by(domain_tasks, key=get_agent)
    merged = {}
    for agent, groups in agent_groups:
        if len(groups) == 1:
            merged[groups[0]] = domain_tasks[groups[0]]
        else:
            combined = merge_domains(groups)  # 合并同 Agent 域
            merged[combined.name] = combined.tasks
    domain_tasks = merged
    # 仍超标 → 将 auto 发现的域降级到 cross_cutting
```

> **最长前缀匹配**：`"frontend/web-app/"` 优先于 `"frontend/"`。
> **祖先冲突检测**：Task 跨 `services/auth/` 和 `services/payment/` 时，
> 不会被 auto 发现为 `services/`（因为 `services/` 有已配置的子前缀）。
> **同 Agent 合并**：使用相同 Agent 类型的域自动合并，减少并行数，
> 例如 3 个 backend-developer 域 → 1 个 Agent 批量处理。

## 并行派发模板

### 基础模板（无 worktree）

适用于 Phase 1（调研）、Phase 4（测试用例生成）、Phase 6（测试执行）。

```markdown
Task(
  subagent_type: "{agent_type}",
  run_in_background: true,
  prompt: "{phase_marker}
你是 autopilot 并行执行子 Agent（{group_id}/{task_id}）。

## 你的任务
{task_full_text}

## 上下文（由控制器提取，禁止自行读取计划文件）
{context_injection}

## 项目规则约束
{rules_scan_result}

## 产出写入（v3.3.0 上下文保护）
将完整产出 Write 到指定的 output_file 路径。禁止在返回信封中包含产出全文。

## 返回要求
执行完毕后返回 JSON 信封（仅摘要，不含全文）：
{\"status\": \"ok|warning|blocked|failed\", \"summary\": \"简明摘要（3-5句）\", \"output_file\": \"写入的文件路径\", \"artifacts\": [...]}
"
)
```

> **v3.3.0 上下文保护**：Phase 1 调研 Agent 必须自行 Write 产出文件，返回信封仅包含结构化摘要和 `decision_points`。详见各调研 Agent 的信封格式定义。

### Worktree 隔离模板（Phase 5 实施专用 — 基础模板）

> **注意**：此为通用基础模板。Phase 5 实际 dispatch 时 `subagent_type` 由域检测动态决定，
> 详见本文档 Step 3 的 `resolve_agent(domain)`。

```markdown
Task(
  subagent_type: "{resolve_agent(domain) || default_agent}",
  isolation: "worktree",
  run_in_background: true,
  prompt: "<!-- autopilot-phase:5 -->
你是 autopilot Phase 5 的并行实施子 Agent。

## 你的任务
仅实施以下单个 task（禁止实施其他 task）：
- Task #{task_number}: {task_title}
- Task 内容: {task_full_text}

## 前序 task 摘要（只读参考）
{completed_task_summaries}

## 文件所有权约束（ENFORCED）
你被分配以下文件的独占所有权：
{owned_files}
禁止修改此列表之外的任何文件。
write-edit-constraint-check Hook 会拦截越权修改。

## 并发隔离
- 你运行在独立 worktree 中
- 禁止修改 openspec/ 目录下的 checkpoint 文件
- 禁止修改其他 task 正在修改的文件: {concurrent_task_files}
- 完成后 artifacts 必须是 owned_files 的子集

## 项目规则约束
{rules_scan_result}

## 执行模式
{model_routing_hint}

## 返回要求
执行完毕后返回 JSON 信封：
{\"status\": \"ok|warning|blocked|failed\", \"summary\": \"...\", \"artifacts\": [...], \"test_result\": \"N/M passed\"}
"
)
```

## 结果收集与验证

### Step 1: 等待所有后台 Agent 完成

> **重要工具约束**：后台 Agent（`run_in_background: true`）完成时，Claude Code 会**自动发送通知**。
> - **禁止**使用 `TaskOutput` 检查后台 Agent 进度 — `TaskOutput` 仅适用于 `Bash(run_in_background)` 命令，对 Agent/Task 后台任务无效。
> - **正确做法**：派发所有后台 Agent 后，直接等待 Claude Code 的自动完成通知，收到通知后处理结果。
> - 如确需提前查看进度，使用 `Read` 工具读取 Agent 返回的 `output_file` 路径。

```
for each agent in running_agents:
  等待 Claude Code 自动完成通知（禁止 TaskOutput 轮询）
  envelope = 解析 agent 返回的 JSON 信封
  envelopes.append(envelope)
```

### Step 2: 状态聚合

```
if any(e.status == "failed" for e in envelopes):
  group_status = "failed"
  → 展示失败详情给用户
elif any(e.status == "blocked" for e in envelopes):
  group_status = "blocked"
  → 展示阻塞原因
elif any(e.status == "warning" for e in envelopes):
  group_status = "warning"
else:
  group_status = "ok"
```

### Step 3: Worktree 合并（仅 merge_strategy="worktree"）

```
按 task 编号顺序合并:
for each agent in sorted(agents, key=task_number):
  git merge --no-ff autopilot-task-{N} -m "autopilot: task {N} - {title}"
  if 冲突:
    if 冲突文件 ≤ 3:
      AskUserQuestion 展示冲突，用户选择处理方式
    else:
      回退该组所有 worktree → 降级为串行
  else:
    git worktree remove .claude/worktrees/task-{N}
    git branch -d autopilot-task-{N}

快速验证:
  运行 config.test_suites 中 type=typecheck 的命令
  超时 120s → 警告但不阻断
```

### Step 4: 批量 Review（仅 review_after=true）

```
Task(
  subagent_type: "general-purpose",
  prompt: "审查以下变更的规范符合性和代码质量:
  
  {for each agent in group}
  ## Task #{N}: {title}
  变更文件: {artifacts}
  摘要: {summary}
  {end for}
  
  请检查:
  1. 每个 task 的实现是否符合原始需求描述
  2. 代码风格是否符合项目规则约束
  3. 各 task 之间是否有冲突或不一致
  4. 是否有遗漏的边界情况
  
  返回: {\"status\": \"ok|warning\", \"summary\": \"...\", \"findings\": [...]}
  "
)
```

## 降级策略

| 触发条件 | 降级行为 |
|---------|---------|
| worktree 创建失败 | 立即降级为串行 |
| 单组合并冲突 > 3 文件 | 回退该组 → 串行执行 |
| 连续 2 组合并失败 | 全面降级为串行 |
| 用户选择 "切换串行" | 全面降级 |
| 依赖图无独立组 | 全部串行 |

降级原因记录到 checkpoint: `_metrics.parallel_fallback_reason`

## 各 Phase 并行配置

### Phase 1: 需求调研并行

```yaml
parallel_tasks:
  - name: "auto-scan"
    agent: "general-purpose"
    prompt_template: "分析项目结构和现有代码模式..."
    merge_strategy: "none"
  - name: "tech-research"
    agent: "general-purpose"
    prompt_template: "分析与需求相关的代码、依赖兼容性..."
    merge_strategy: "none"
  - name: "web-search"
    agent: "general-purpose"
    prompt_template: "联网搜索最佳实践和竞品方案..."
    merge_strategy: "none"
    condition: "search_policy.default: search — 规则判定跳过时不派发此 Agent"
```

**子 Agent 自写入约束**（v3.3.0）：每个调研 Agent 必须自行 Write 产出到指定路径，返回 JSON 信封仅包含摘要。

调研 Agent 返回信封格式：
```json
{
  "status": "ok",
  "summary": "简明摘要（3-5句）",
  "decision_points": [
    {"topic": "决策点标题", "options": ["方案A", "方案B"], "recommendation": "推荐方案", "rationale": "推荐理由"}
  ],
  "tech_constraints": ["约束1", "约束2"],
  "complexity": "small|medium|large",
  "key_files": ["关键文件路径"],
  "output_file": "context/research-findings.md"
}
```

> **禁止**：在信封的 summary 或其他字段中返回调研全文。全文必须 Write 到 output_file。
> **主线程仅消费信封**，不 Read 产出文件。产出文件由 business-analyst 和 Phase 2-6 子 Agent 直接 Read。

汇合后: 主线程从信封提取 decision_points + tech_constraints → 注入到 business-analyst 的 dispatch prompt

### Phase 4: 测试用例并行生成

```yaml
parallel_tasks:
  - name: "unit-tests"
    agent: "backend-developer"
    domain: "backend"
    test_type: "unit"
  - name: "api-tests"
    agent: "qa-expert"
    domain: "api"
    test_type: "integration"
  - name: "e2e-tests"
    agent: "qa-expert"
    domain: "e2e"
    test_type: "e2e"
  - name: "ui-tests"
    agent: "frontend-developer"
    domain: "frontend"
    test_type: "ui"
```

汇合后: 合并 test_counts → 验证 test_pyramid → 运行 dry-run

### Phase 5: 实施并行（混合模式）

> **强制约束**: 当 `config.phases.implementation.parallel.enabled = true` 时，Phase 5 **必须**走并行模式。
> **禁止**: 在并行模式下进入串行模式或调用串行 Task 派发流程。

```yaml
parallel_config:
  split_strategy: "domain-single-agent"   # v3.4.0: 域级单 Agent（废弃旧 "domain-partition" 域内多 Agent）
  merge_strategy: "worktree"
  review_after: true                      # 每组完成后批量 review

  domain_detection: "auto"                 # auto: 自动发现域 | explicit: 仅用配置的前缀
  default_agent: "general-purpose"          # 未匹配任何前缀的默认 Agent
  domain_agents:                            # 路径前缀 → Agent 映射（每域严格 1 Agent）
    "backend/":                             # 匹配 backend/ 下所有文件
      agent: "backend-developer"
      max_tasks_per_batch: 10
    "frontend/":                            # 匹配 frontend/ 下所有文件
      agent: "frontend-developer"
      max_tasks_per_batch: 10
    "node/":                                # 匹配 node/ 下所有文件
      agent: "fullstack-developer"
      max_tasks_per_batch: 10
    # 用户可自由扩展任意路径前缀：
    # "android/":
    #   agent: "mobile-developer"
    # "packages/core/":
    #   agent: "backend-developer"

  cross_cutting_strategy: "serial_after_parallel"
  max_parallel_domains: 8                 # 最多 8 个域同时并行（v3.4.0 扩大）
  degrade_threshold: 3                    # 合并冲突文件数超过此值则降级
```

执行流程概要:
```
1. 解析任务清单 -> 提取 affected_files
2. 按域分组（从 domain_agents 路径前缀匹配 + auto 自动发现）
3. 生成 owned_files -> 写入 phase5-ownership/agent-{N}.json
4. 对每个域: Task(isolation:"worktree", run_in_background:true) — 最多 8 并行
5. 等待完成 -> 按编号合并 worktree -> quick_check
6. 批量 review -> 问题则 resume agent 修复
7. cross_cutting 串行执行
8. full_test 全量验证
```

### Phase 6: 三路并行（v3.2.2 增强）

Phase 6 采用**跨维度三路并行**，不同于 Phase 1/4/5 的阶段内并行：

```yaml
tri_path_parallel:
  # 路径 A: 测试执行（后台 Task，按统一调度模板）
  path_a:
    type: "background"
    parallel_tasks:  # 路径 A 内部可进一步并行（按 test_suites 分组）
      - name: "{suite_name}"
        command: "{suite.command}"
        allure_args: "{suite.allure_args}"
        merge_strategy: "none"

  # 路径 B: 代码审查（后台 Task）
  path_b:
    type: "background"
    condition: "config.phases.code_review.enabled"
    agent: "general-purpose"
    prompt_source: "references/phase6-code-review.md"
    no_phase_marker: true  # 不含 autopilot-phase 标记，Hook 直接放行

  # 路径 C: 质量扫描（多个后台 Task）
  path_c:
    type: "background"
    source: "config.async_quality_scans"
    prompt_source: "references/quality-scans.md"
    no_phase_marker: true
    timeout: "config.async_quality_scans.timeout_minutes"
```

汇合点: Phase 7 步骤 2（收集 A/B/C 全部结果）

## 与 Superpowers 的关键差异

| 维度 | Superpowers | Autopilot parallel-dispatch |
|------|-------------|----------------------------|
| 并行粒度 | 仅 dispatching-parallel-agents（独立问题域） | 跨阶段通用（Phase 1/4/5/6） |
| 实施并行 | 禁止（subagent-driven 严格串行） | 支持（worktree 隔离 + 文件所有权） |
| Review | 每任务双阶段（spec + quality） | 每组批量 review |
| 冲突处理 | 不涉及（串行无冲突） | 3 层冲突检测 + 自动降级 |
| 上下文管理 | 控制器提取全文 | 控制器提取全文（借鉴） |

---

## 阶段调度模板（详细 Prompt 构造）

> 以下为各阶段的并行 Task prompt 构造模板。

### 并行调度触发条件

| Phase | 并行条件 | 配置项 |
|-------|---------|--------|
| 1 | 始终并行（Auto-Scan + 调研 + 搜索） | `config.phases.requirements.research.enabled` |
| 4 | `config.phases.testing.parallel.enabled = true` | 按测试类型分组 |
| 5 | `config.phases.implementation.parallel.enabled = true` | 按文件域分组 |
| 6 | `config.phases.reporting.parallel.enabled = true`（默认 true） | 按测试套件分组 |

### Phase 1 调度模板

主线程同时派发 2-3 个 Task（不含 autopilot-phase 标记，不受 Hook 校验）：

```markdown
# Task 1: Auto-Scan（general-purpose agent）
Task(subagent_type: "general-purpose", run_in_background: true,
  prompt: "分析项目结构，生成 Steering Documents:
  - project-context.md（技术栈、目录结构）
  - existing-patterns.md（现有代码模式）
  - tech-constraints.md（技术约束）
  输出到: openspec/changes/{change_name}/context/"
)

# Task 2: 技术调研（general-purpose agent）
Task(subagent_type: "general-purpose", run_in_background: true,
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

### Phase 4 调度模板

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

#### Phase 4 Dispatch 强制指令

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

1. 从 tasks.md 或 phase-1-requirements.json 提取本次变更涉及的具体代码单元
2. 每个变更点至少 1 个专项测试用例
3. 返回信封中必须包含 `change_coverage` 字段

### 测试金字塔比例约束

测试用例分布必须符合金字塔模型（从 `config.test_pyramid` 读取阈值）。
返回信封中必须包含 `test_pyramid` 字段。
```

### Phase 5 调度模板

> **触发条件**: `config.phases.implementation.parallel.enabled = true`
> **强制约束**: 进入并行模式后，禁止进入串行模式

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

# Step B: auto 发现（祖先冲突检测）
cross_cutting = []
for task in unmatched:
    top = common_top_dir(task.affected_files)
    if top and no_child_prefix(top, domain_prefixes):
        domain_tasks[top].append(task)
    else:
        cross_cutting.append(task)

# Step C: 溢出合并（同 Agent 域合并）
if len(domain_tasks) > max_agents:
    domain_tasks = coalesce_same_agent_domains(domain_tasks, max_agents)

写入: phase5-ownership/{domain_name}.json
```

#### Step 3: 域级并行 Task 派发（v3.4.0 — 单 Agent 模式）

> **HARD CONSTRAINT**: 每个域严格 1 个 Agent，禁止同一域内派发多个 Agent。

```markdown
{for each non_empty_domain in domain_tasks.keys()}
Task(
  subagent_type: "{resolve_agent(domain)}",
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

## 文件所有权约束（ENFORCED）
你被分配以下文件的独占所有权：
{domain_all_owned_files}
禁止修改此列表之外的任何文件。

## 返回要求
{\"status\": \"ok|warning|blocked|failed\", \"summary\": \"...\", \"artifacts\": [...], \"tasks_completed\": [1,2,3], \"test_result\": \"N/M passed\"}
"
)
{end for}
```

#### Step 4-6: 合并 + Review + 全量测试

```
按域顺序合并 worktree → quick_check → 批量 review → cross_cutting 串行 → full_test
```

### Phase 6 调度模板

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

  ## 返回要求
  {"status": "ok|warning|failed", "summary": "...", "pass_rate": N, "total": N, "passed": N, "failed": N, "skipped": N, "artifacts": [...]}
  "
)
{end for}
```

主线程汇合后合并所有套件测试结果。

## 代码生成约束增强（v3.2.0 新增）

### 新增配置项

```yaml
code_constraints:
  forbidden_files: [...]
  forbidden_patterns: [...]
  allowed_dirs: [...]
  max_file_lines: 800
  required_patterns:
    - pattern: "createWebHashHistory"
      context: "Vue Router 配置文件"
      message: "Must use Hash mode routing"
  style_guide: "rules/frontend/README.md"
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
```

## 需求理解增强（v3.2.0 新增）

### 复杂度自适应调研深度

| 复杂度 | Auto-Scan | 技术调研 | 联网搜索 | 竞品分析 |
|--------|-----------|---------|---------|---------|
| small | ✅ | ❌ | ❌ | ❌ |
| medium | ✅ | ✅（并行） | ❌ | ❌ |
| large | ✅ | ✅（并行） | ✅（并行） | ✅（并行） |

### 主动决策增强

所有复杂度级别均展示决策卡片（v3.2.0 取消 small 豁免）。

`config.phases.requirements.decision_mode`:
- `proactive`（默认）: AI 主动识别决策点并展示
- `reactive`: 仅在用户提问时展示
