# Phase 5: Subagent-Driven 并行实施模板

> 当 `config.phases.implementation.parallel.enabled = true` 时，主线程读取此模板执行。
> 此模板为**主线程可执行指令**，融合 subagent-driven-development 三角色模式与独立域并行派发。

## 核心原则

1. **独立域并行**：不同顶级目录（backend/frontend/node）的 task 可同时执行
2. **同域串行**：同一目录内的 task 串行执行，避免文件冲突
3. **Fresh subagent per task**：每个 task 一个全新 implementer，防止上下文污染
4. **双阶段 review**：每批并行 task 合并后，强制 spec-review + quality-review
5. **Worktree 隔离**：并行时自动启用，串行降级后关闭

## 前置准备

1. Git 安全检查点：`git tag -f autopilot-phase5-start HEAD`
2. 记录启动时间戳到 `phase-results/phase5-start-time.txt`
3. 读取 `openspec/changes/{change_name}/tasks.md`，解析所有 task
4. 读取 `openspec/changes/{change_name}/proposal.md`（供 review 阶段使用）

## Step 1: 依赖分析与域分组

主线程执行以下分析（不派发子 Agent）：

```
1. 解析 tasks.md 中每个 task（格式: ### Task N.M: title）
2. 对每个 task 提取信息：
   a. affected_files[]：显式文件路径引用
   b. domain：根据 affected_files 推断顶级目录（backend/frontend/node/shared）
   c. depends_on[]：显式 depends_on 标记或文件交集推断
3. 按 domain 分组：
   - backend_tasks[]
   - frontend_tasks[]
   - node_tasks[]
   - shared_tasks[]（跨多个 domain 的 task）
4. 域内按 task 编号排序（串行执行顺序）
5. shared_tasks 排入最后，串行执行
```

**输出**：`domain_groups: { backend: Task[], frontend: Task[], node: Task[], shared: Task[] }`

## Step 2: 动态并行度计算

```
active_domains = 非空 domain 的数量（不含 shared）
max_agents = config.phases.implementation.parallel.max_agents (默认 5)

IF active_domains <= 1 → 无并行价值，降级为串行模板
IF active_domains == 2 → actual_parallel = 2
IF active_domains >= 3 → actual_parallel = min(active_domains, max_agents)
```

> 如果只有 1 个 domain 有 task，自动降级读取 `templates/phase5-ralph-loop.md` 串行执行。

## Step 3: 文件锁注册

对即将并行执行的每个 domain runner：

1. 为该 domain 的所有 task 生成 `owned_files` 列表（该 domain 目录下的所有文件）
2. 写入 `phase-results/phase5-ownership/domain-{name}.json`
3. 写入 `phase-results/phase5-ownership/file-locks.json`：
   ```json
   {
     "backend/": "domain-backend",
     "frontend/": "domain-frontend",
     "node/": "domain-node"
   }
   ```

## Step 4: 并行派发 Domain Runner（核心）

每个 domain 派发一个 "Domain Runner" subagent，该 subagent **串行执行** domain 内所有 task。

**在一个 response 中发出所有 Domain Runner 的 Task 调用**，实现跨域并行：

```
domain_runners = []

for each domain in [backend, frontend, node] where domain.tasks is not empty:
  runner = Task(
    subagent_type: config.parallel.agent_mapping[domain] || "general-purpose",
    isolation: "worktree",
    run_in_background: true,
    prompt: → 见下方 Domain Runner Prompt 模板
  )
  domain_runners.append(runner)

# 等待所有 domain runner 完成
# （Claude Code 会自动通知 background task 完成，无需 sleep 轮询）
```

### Domain Runner Prompt 模板

```markdown
<!-- autopilot-phase:5 -->
你是 autopilot Phase 5 的 Domain Runner（{domain} 域）。

## 你的任务列表（按顺序串行执行）

{for each task in domain.tasks}
### Task #{task.number}: {task.title}
{task.full_description}
{end for}

## 域文件所有权约束（ENFORCED）

你只能修改 `{domain}/` 目录下的文件。修改其他目录的文件将被 Hook 拦截。
允许读取任何文件作为参考，但禁止写入 owned 范围之外的文件。

## 项目规则约束（自动注入）

{rules_scanner 扫描结果——完整规则}

{if domain == "backend"}
{.claude/rules/backend.md 全文}
{end if}
{if domain == "frontend"}
{.claude/rules/frontend.md 全文}
{end if}
{if domain == "node"}
{.claude/rules/nodejs.md 全文}
{end if}

## 执行流程（每个 task 严格遵循）

对每个 task 依次执行：

### 1. 理解需求
- 读取 task 描述，确认理解
- 如有疑问，在 report 中标注 "QUESTION: ..."（不阻断执行）

### 2. 实施
- 按 task 描述实现功能
- 遵循项目规则约束（上方注入的规则）
- 只修改 owned 范围内的文件

### 3. 快速校验
每完成一个 task 后运行快速校验：
{for each suite in config.test_suites where suite.type in ['typecheck', 'unit']}
- `{suite.command}`
{end for}

### 4. Self-Review（每个 task 完成后）
- 完整性：是否实现了 task 描述的所有要求？
- 质量：代码是否清晰、可维护？
- 纪律：是否避免了过度工程？是否遵循了现有模式？
- 规则：是否遵守了上方注入的项目规则？

如果 self-review 发现问题，立即修复后再继续下一个 task。

### 5. 记录 task 完成情况
记录已完成 task 的摘要，供后续 review 使用。

## 返回要求

返回 JSON 信封：
```json
{
  "status": "ok | blocked | failed",
  "domain": "{domain}",
  "summary": "域内 N 个 task 全部完成",
  "tasks": [
    {
      "task_number": "N.M",
      "status": "ok | failed",
      "summary": "单行摘要",
      "artifacts": ["修改的文件路径列表"],
      "self_review": "self-review 发现并修复的问题（如有）",
      "test_result": "快速校验结果"
    }
  ],
  "quick_check_passed": true
}
```

如果任何 task 失败且无法恢复，将该 task 标记为 failed 并继续下一个 task。
```

## Step 5: 结果收集与合并

所有 domain runner 完成后：

```
merge_order = [backend, frontend, node]  # 固定合并顺序

for each runner_result in domain_runners (按 merge_order):
  1. 解析返回的 JSON 信封
  2. 如果 status == "ok":
     a. Worktree 自动合并（Agent tool with isolation: "worktree" 自动处理）
     b. 运行 quick_check 验证合并后代码：
        {for each suite in config.test_suites where suite.type == "typecheck"}
        - `{suite.command}`
        {end for}
     c. 写入 checkpoint: phase5-domains/{domain}.json
  3. 如果 status == "blocked" 或 "failed":
     a. 记录失败原因和失败 task 列表
     b. 将失败 task 加入 retry_queue
  4. 释放该 domain 的文件锁条目
```

## Step 6: Spec Compliance Review（硬阻断）

> 参考 `templates/phase5-review-prompts.md` 中的 spec-reviewer 模板。

合并完成后，派发 **spec-reviewer subagent**：

```
Task(
  subagent_type: "general-purpose",
  prompt: → phase5-review-prompts.md 中的 Spec Reviewer Prompt
         → 注入 proposal.md 全文 + 所有 task 的 implementer report
)
```

处理 spec-reviewer 结果：
- 所有 task 通过 → 继续 Step 7
- 有 task 不符合 spec → 派发 fix subagent 修复 → 重新 spec-review → 最多 2 轮
- 2 轮后仍不通过 → status: "blocked"

## Step 7: Code Quality Review

> 参考 `templates/phase5-review-prompts.md` 中的 quality-reviewer 模板。

spec-review 通过后，派发 **quality-reviewer subagent**：

```
Task(
  subagent_type: config.parallel.agent_mapping.review_quality
               || "pr-review-toolkit:code-reviewer",
  prompt: → phase5-review-prompts.md 中的 Quality Reviewer Prompt
         → 注入 git diff autopilot-phase5-start..HEAD
)
```

处理 quality-reviewer 结果：
- 无 critical/important issues → 继续 Step 8
- 有 critical issues（confidence >= 90）→ 派发 fix subagent → 重新 review → 最多 2 轮
- 有 important issues（confidence 80-89）→ 记录到 checkpoint，不阻断
- 2 轮后仍有 critical → status: "blocked"

## Step 8: 串行处理 shared_tasks + retry_queue

```
serial_queue = shared_tasks + retry_queue

for each task in serial_queue:
  Task(
    subagent_type: "general-purpose",
    prompt: "<!-- autopilot-phase:5 -->
    你是 autopilot Phase 5 的串行实施子 Agent。
    [单个 task prompt，含失败原因（如果是 retry）]
    [项目规则约束注入]
    "
  )
  # 每个 task 完成后立即 quick_check
```

## Step 9: 全量测试

所有 task 完成后，运行完整测试套件：

```
{for each suite in config.test_suites}
- `{suite.command}`
{end for}
```

写入 `test-results.json`（含 zero_skip_check）。

## Step 10: 构造 Phase 5 JSON 信封

```json
{
  "status": "ok",
  "summary": "N 个 task 全部完成，双阶段 review 通过，M 个测试套件全部通过",
  "artifacts": ["所有 task 的 artifacts 合并"],
  "test_results_path": "testreport/test-results.json",
  "tasks_completed": N,
  "zero_skip_check": { "passed": true },
  "parallel_metrics": {
    "mode": "parallel",
    "domains_used": ["backend", "frontend"],
    "max_agents_used": A,
    "fallback_reason": null,
    "file_conflicts_count": 0
  },
  "review_results": {
    "spec_review": { "status": "passed", "rounds": 1 },
    "quality_review": {
      "status": "passed",
      "rounds": 1,
      "critical_issues": 0,
      "important_issues": 2,
      "issues_fixed": 0
    }
  }
}
```

## 降级决策树

```
IF 仅 1 个 domain 有 task → 直接读取 templates/phase5-ralph-loop.md 串行执行
IF worktree 创建失败 → 降级为串行，fallback_reason: "worktree_creation_failed"
IF 任一 domain 合并冲突 > config.parallel.conflict_threshold 个文件 → 回退该 domain → 串行
IF spec-review 2 轮未通过 → status: "blocked"，不继续
IF quality-review 2 轮仍有 critical → status: "blocked"
降级原因写入 checkpoint: parallel_metrics.fallback_reason
```

## Wall-clock 超时

每个 Step 开始前检查：当前时间 - phase5-start-time > 2 小时
→ AskUserQuestion: "继续执行" / "保存进度并暂停" / "回退到起始点"
