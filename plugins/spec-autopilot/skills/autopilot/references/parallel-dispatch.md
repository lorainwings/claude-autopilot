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
  task.domain = 推断所属域（backend/frontend/node/cross-cutting）
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

```
backend_tasks  = [t for t in tasks if all(f.startswith("backend/") for f in t.affected_files)]
frontend_tasks = [t for t in tasks if all(f.startswith("frontend/") for f in t.affected_files)]
node_tasks     = [t for t in tasks if all(f.startswith("node/") for f in t.affected_files)]
cross_cutting  = [t for t in tasks if t not in backend ∪ frontend ∪ node]
```

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

### Worktree 隔离模板（Phase 5 实施专用）

```markdown
Task(
  subagent_type: "general-purpose",
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
    agent: "Explore"
    prompt_template: "分析项目结构和现有代码模式..."
    merge_strategy: "none"
  - name: "tech-research"
    agent: "Explore"
    prompt_template: "分析与需求相关的代码、依赖兼容性..."
    merge_strategy: "none"
  - name: "web-search"
    agent: "general-purpose"
    prompt_template: "联网搜索最佳实践和竞品方案..."
    merge_strategy: "none"
    condition: "config.phases.requirements.web_search.enabled"
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
> **完整 dispatch 模板**: 见 `references/parallel-phase-dispatch.md` Phase 5 并行调度章节。

```yaml
parallel_config:
  dependency_analysis: "union-find"  # 或 "domain-partition"（按顶级目录快速分区）
  merge_strategy: "worktree"
  review_after: true               # 每组完成后批量 review
  max_agents: 5                    # 从 config.phases.implementation.parallel.max_agents 读取
  agent_mapping:
    backend: "backend-developer"
    frontend: "frontend-developer"
    node: "fullstack-developer"
  cross_cutting_strategy: "serial_after_parallel"  # 跨域任务在所有并行组完成后串行
  degrade_threshold: 3             # 合并冲突文件数超过此值则降级
```

执行流程概要:
```
1. 解析任务清单 -> 提取 affected_files
2. 按顶级目录分组（backend/frontend/node/cross_cutting）
3. 生成 owned_files -> 写入 phase5-ownership/agent-{N}.json
4. 对每个并行组: Task(isolation:"worktree", run_in_background:true) x N
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
