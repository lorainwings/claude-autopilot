# Phase 5 并行调度配置与模板

> 本文件从 `parallel-dispatch.md` 拆分，仅在 Phase 5 按需加载。
> 通用并行编排协议（适用条件、Union-Find、模板、结果收集、降级策略）见 `parallel-dispatch.md`。

## Phase 5: 实施并行（混合模式）

> **强制约束**: 当 `config.phases.implementation.parallel.enabled = true` 时，Phase 5 **必须**走并行模式。
> **禁止**: 在并行模式下进入串行模式或调用串行 Task 派发流程。
> **完整 dispatch 模板**: 见下方 Phase 5 并行调度章节。

```yaml
parallel_config:
  split_strategy: "domain-single-agent"   # 域级单 Agent（废弃旧 "domain-partition" 域内多 Agent）
  merge_strategy: "worktree"
  review_after: true                      # 每组完成后批量 review

  domain_detection: "auto"                 # auto: 自动发现域 | explicit: 仅用配置的前缀
  default_agent: config.phases.implementation.parallel.default_agent  # 默认 "general-purpose"
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
  max_parallel_domains: 8                 # 最多 8 个域同时并行
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

## Phase 5 并行调度模板

> **触发条件**: `config.phases.implementation.parallel.enabled = true`
> **强制约束**: 进入并行模式后，禁止进入串行模式或调用串行 Task 派发流程

核心增强：
1. **混合模式** — 按独立域分组并行 + 每组完成后批量 review
2. **控制器提取全文** — 主线程一次性读取所有任务文本，subagent 不自己读计划文件
3. **subagent 提问机制** — subagent 可通过 AskUserQuestion 向用户提问
4. **同一 agent 修复** — 发现问题后 resume 同一 agent 修复，不切换上下文

### Step 1: 任务清单解析

```
主线程读取任务清单:
- full 模式: openspec/changes/{change_name}/tasks.md
- lite/minimal 模式: openspec/changes/{change_name}/context/phase5-task-breakdown.md

解析每个 task 的 affected_files 和 depends_on
主线程一次性提取所有 task 的完整文本（子 Agent 禁止自行读取计划文件）
```

### Step 1.3: affected_files 元数据校验

在传入 `generate-parallel-plan.sh` 之前，主线程**必须**校验每个 task 的 `affected_files` 字段：

```
for each task in tasks:
  if task.affected_files 为空或缺失:
    1. 扫描 task_full_text 中出现的文件路径（匹配 *.ts/*.py/*.vue/*.go/*.java 等后缀模式）
    2. 非空 → 注入 task.affected_files
    3. 仍为空 → 输出诊断: "[WARN] Task {task_name} 缺少 affected_files，并行分组可能不精确"
       标记 task.affected_files_inferred = false
```

> **设计意图**: generate-parallel-plan.sh 依赖 affected_files 进行文件冲突检测和域分组。
> 缺失时脚本无法有效分组，导致 fallback_to_serial。

### Step 1.5: 生成并行计划（确定性 batch 调度）

> **HARD CONSTRAINT**: 主线程在 dispatch 前**必须**调用 `generate-parallel-plan.sh` 生成 `parallel_plan.json`。
> Scheduler 必须消费 `parallel_plan.json` 的 `batches`，而非模型自行决定并行策略。

```bash
# 将任务清单转为 JSON 数组格式后传入
echo "$TASKS_JSON" | bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/generate-parallel-plan.sh > parallel_plan.json

# 发射 parallel_plan 事件
bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-parallel-event.sh \
  "$PROJECT_ROOT" 5 "$MODE" parallel_plan \
  '{"scheduler_decision":"batch_parallel","total_tasks":N,"batch_count":M,"max_parallelism":K}'
```

**并行计划输出 (`parallel_plan.json`)**:
- `batches[]`: 拓扑排序后的执行批次，每个 batch 含 `tasks[]` 和 `can_parallel` 标志
- `dependency_graph`: 任务间依赖关系（显式 depends_on + 文件冲突隐式依赖）
- `scheduler_decision`: `batch_parallel` 或 `serial`
- `fallback_to_serial`: 当所有任务形成线性依赖链时为 true，**必须**附带结构化 `fallback_reason`

**规则**:
- 单域项目只要文件 ownership 不冲突也能 batch 并行
- 如果所有任务都有依赖链，则 `fallback_to_serial=true` + 结构化 reason
- fallback 时**必须**有结构化 reason（不允许空字符串）

### Step 2: 文件所有权分区（三步域检测）

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

### Step 3: 域级并行 Task 派发（单 Agent 模式）

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

{if phase4_test_files}
## 测试驱动开发（Phase 4 测试先行验证）
Phase 4 已设计以下测试用例，与本域的 task 相关：

### 测试文件
{for each test_file in phase4_test_files}
- {test_file}
{end for}

### 执行流程（每个 task 均需遵循 RED→GREEN）
对每个 task，在实施前后执行验证：
1. **RED 验证**（实施前）：运行相关测试，确认测试**失败**（exit_code ≠ 0），记录 red_output_excerpt
   - 如果测试已通过（exit_code = 0）：设置 red_verified=false, red_skipped_reason="test_already_passing"，继续实施
2. **实施 task**：按任务描述实现功能代码
3. **GREEN 验证**（实施后）：运行相同测试，确认测试**通过**（exit_code = 0）
   - 如果仍失败，修复实现代码（禁止修改测试用例）

在汇总 JSON 信封中增加 \"test_driven_evidence\" 字段，记录所有 task 的 RED→GREEN 证据。
red_verified 仅在测试确实失败时为 true；测试已通过时为 false + red_skipped_reason。
{end if}

## 上下文（由控制器提取，禁止自行读取计划文件）
{context_injection}

## 文件所有权约束（ENFORCED）
你被分配以下文件的独占所有权：
{domain_all_owned_files}
禁止修改此列表之外的任何文件。
unified-write-edit-check Hook 会拦截越权修改。

## 并发隔离
- 你运行在独立 worktree 中（每域 1 个 worktree）
- 禁止修改 openspec/ 目录下的 checkpoint 文件
- 禁止修改其他域正在修改的文件: {other_domain_files}
- 完成后 artifacts 必须是 domain_all_owned_files 的子集

## 项目规则约束
{rules_scan_result}

## 执行要求
- 按 task 编号顺序逐个实施
- **每个 task 开始和完成时必须发射进度事件**（见上方进度汇报协议）
- 每个 task 完成后返回中间状态（便于断点恢复）
- 所有 task 完成后返回汇总 JSON 信封

## 返回要求
执行完毕后返回 JSON 信封：
{\"status\": \"ok|warning|blocked|failed\", \"summary\": \"...\", \"artifacts\": [...], \"tasks_completed\": [1,2,3], \"test_result\": \"N/M passed\", \"test_driven_evidence\": {...}}
"
)
{end for}
```

等待 Claude Code 自动完成通知（禁止 TaskOutput 轮询）。最多 max_agents 个域并行（默认 8），域内串行。

### 串行模式 Batch Scheduler（默认并行引擎）

当 `parallel.enabled = false`（串行模式）时，自动启用 Batch Scheduler：

> **变更**: Batch Scheduler 必须消费 `parallel_plan.json` 的 `batches` 字段，
> 而非模型自行决定 batch 分组。调用 `generate-parallel-plan.sh` 生成计划后，
> 严格按 `batches[].tasks` 顺序和 `can_parallel` 标志执行。

```
算法:
1. 调用 generate-parallel-plan.sh 生成 parallel_plan.json
2. 读取 parallel_plan.json 的 batches 字段
3. 对每个 batch:
   - can_parallel=false 或单 task → 前台 Task 同步执行
   - can_parallel=true 且多 task → Task(run_in_background: true) 全部后台派发
   - 等待完成通知 → 收集 envelope → 按顺序写 checkpoint
4. fallback_to_serial=true 时，所有 task 纯串行执行
5. 失败处理: 失败 task 降级串行重试，>50% 失败则全面回退纯串行
```

禁用条件: `config.serial_task.allow_background_parallel = false` 或 TDD 模式。
详见 `phase5-implementation.md` "串行模式优化：无依赖 task 后台并行引擎" 章节。

### Step 4: 合并 + 验证

```
按 task 编号顺序合并:
for each agent in sorted(agents, key=task_number):
  # 合并前发射 task running 事件
  Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-task-progress.sh "task-{N}-{slug}" running {N} {total} {mode}')

  # L2 per-task TDD 验证（仅 tdd_mode 时）
  IF tdd_mode:
    l2_result = Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/verify-parallel-tdd-l2.sh --worktree-path <wt-path> --test-command "{test_command}" --task-checkpoint <cp-path>')
    IF l2_result.status == "blocked": skip merge, degrade to serial for this task

  git merge --no-ff autopilot-task-{N} -m "autopilot: task {N} - {title}"
  if conflict and conflict_files > 3: rollback group worktree, degrade to serial
  if conflict and conflict_files <= 3: AskUserQuestion show conflicts
  else: git worktree remove + git branch -d

  # 合并成功后发射 task passed 事件
  Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-task-progress.sh "task-{N}-{slug}" passed {N} {total} {mode}')

快速验证: 运行 config.test_suites 中 type=typecheck 的命令
主线程写入 checkpoint: phase5-tasks/task-N.json
```

### Step 5: 批量 Review（每组完成后）

```markdown
Task(
  subagent_type: config.phases.implementation.review_agent,
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

### Step 6: 跨域串行 + 全量测试

```
cross_cutting_tasks 在所有并行组完成后串行执行
全部完成后运行 full_test（config.test_suites 全量）
```

### 降级到串行模式

```
触发条件:
- worktree 创建失败: 立即降级
- 单组合并冲突 > 3 文件: 回退该组, 串行执行
- 连续 2 组合并失败: 全面降级
- 用户选择 "切换串行": 全面降级

降级后进入 phase5-implementation.md 的串行模式章节
记录: _metrics.parallel_fallback_reason
```

## 代码生成约束增强

### 新增配置项

```yaml
code_constraints:
  # 已有
  forbidden_files: [...]
  forbidden_patterns: [...]
  allowed_dirs: [...]
  max_file_lines: 800

  # 新增
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
