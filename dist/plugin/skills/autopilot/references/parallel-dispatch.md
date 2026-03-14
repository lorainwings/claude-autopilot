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
> 详见本文件下方 Phase 5 并行调度章节 Step 3 的 `resolve_agent(domain)`。

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

## 各 Phase 并行配置（v5.2 按需加载）

> **v5.2 Token 优化**: 各 Phase 的并行配置和 dispatch 模板已拆分为独立文件，各阶段按需加载，避免全量注入。

| Phase | 按需加载文件 | 内容 |
|-------|-------------|------|
| 1 | `references/parallel-phase1.md` | 需求调研并行配置 + dispatch 模板 + 决策增强（search_policy.default: search） |
| 4 | `references/parallel-phase4.md` | 测试用例并行生成 + 金字塔约束 + 变更覆盖 |
| 5 | `references/parallel-phase5.md` | 实施并行（域检测 + worktree 隔离 + 串行 Batch Scheduler）+ 代码生成约束 |
| 6 | `references/parallel-phase6.md` | 三路并行（测试执行 + 代码审查 + 质量扫描）+ Allure 集成 |

各阶段执行前**仅加载本文件（通用协议）+ 对应的 Phase 文件**，不加载其他 Phase 的文件。

## 与 Superpowers 的关键差异

| 维度 | Superpowers | Autopilot parallel-dispatch |
|------|-------------|----------------------------|
| 并行粒度 | 仅 dispatching-parallel-agents（独立问题域） | 跨阶段通用（Phase 1/4/5/6） |
| 实施并行 | 禁止（subagent-driven 严格串行） | 支持（worktree 隔离 + 文件所有权） |
| Review | 每任务双阶段（spec + quality） | 每组批量 review |
| 冲突处理 | 不涉及（串行无冲突） | 3 层冲突检测 + 自动降级 |
| 上下文管理 | 控制器提取全文 | 控制器提取全文（借鉴） |

---

## 并行调度协议总览（v3.2.0 新增，v5.2 拆分）

> 以下为并行调度触发条件总览。各 Phase 的完整 dispatch 模板已拆分至独立文件（见上方索引表）。

### 并行调度触发条件

| Phase | 并行条件 | 配置项 | 按需加载文件 |
|-------|---------|--------|-------------|
| 1 | 始终并行（Auto-Scan + 调研 + 搜索） | `config.phases.requirements.research.enabled` | `parallel-phase1.md` |
| 4 | `config.phases.testing.parallel.enabled = true` | 按测试类型分组 | `parallel-phase4.md` |
| 5 | `config.phases.implementation.parallel.enabled = true` | 按文件域分组 | `parallel-phase5.md` |
| 6 | `config.phases.reporting.parallel.enabled = true`（默认 true） | 按测试套件分组 | `parallel-phase6.md` |
