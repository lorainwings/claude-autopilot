# Phase 5: 循环实施 — 详细流程

> 本文件由 autopilot SKILL.md 引用，执行 Phase 5 时按需读取。

## 启动前安全准备

1. **Git 安全检查点**：在实施任何代码变更前，创建 git tag `autopilot-phase5-start` 标记当前状态
   ```
   git tag -f autopilot-phase5-start HEAD
   ```
   如果 Phase 5 实施失败需要回退，可通过 `git diff autopilot-phase5-start..HEAD` 查看所有变更，或通过 `git stash` 暂存后 `git checkout autopilot-phase5-start` 回退。
2. **记录启动时间戳**：在 `openspec/changes/<name>/context/phase-results/phase5-start-time.txt` 写入 ISO-8601 时间戳，供 wall-clock 超时检查使用。

## Wall-clock 超时机制

- 每次迭代开始时检查已用时间 = 当前时间 - phase5-start-time
- 超过 **2 小时** → 强制暂停，AskUserQuestion：「Phase 5 已运行 {elapsed} 分钟，是否继续？」
- 选项："继续执行" / "保存进度并暂停" / "回退到 Phase 5 起始点"

## 无 tasks.md 场景（lite/minimal 模式）

当 Phase 2/3 被跳过（lite/minimal 模式）时，不存在 `tasks.md`。Phase 5 需要从 Phase 1 的需求分析结果自动生成任务分组。

### 任务自动生成流程

```
1. 读取 openspec/changes/<name>/context/phase-results/phase-1-requirements.json
2. 提取 requirements_summary 和 decisions[]
3. 读取 openspec/changes/<name>/context/ 下的 Steering Documents：
   - project-context.md（项目结构和技术栈）
   - existing-patterns.md（现有代码模式）
   - research-findings.md（技术调研结论）
4. 基于需求功能清单 + 项目结构，按域拆分任务：
   - backend 域：API 接口、数据库变更、业务逻辑
   - frontend 域：页面组件、路由、状态管理
   - node 域：Node 服务变更（如有）
   - cross-cutting：跨域集成任务
5. 生成临时任务清单，写入 openspec/changes/<name>/context/phase5-task-breakdown.md
6. 格式与 tasks.md 完全一致（## Group + - [ ] task 编号格式）
```

### 任务清单格式

```markdown
# Tasks: <change-name> (auto-generated from Phase 1 requirements)

## 1. Backend Changes
- [ ] 1.1 [从需求功能点推导的后端任务]
- [ ] 1.2 [...]

## 2. Frontend Changes
- [ ] 2.1 [从需求功能点推导的前端任务]
- [ ] 2.2 [...]

## 3. Integration & Testing
- [ ] 3.1 [集成验证任务]
```

### 质量要求

- 自动生成的任务必须**引用 Phase 1 决策结论**，不得凭空假设
- 每个任务必须明确涉及的文件路径（基于 existing-patterns.md 和 research-findings.md）
- 任务粒度遵循项目规则：每个任务 ≤3 个文件，≤800 行代码
- 生成完成后，通过 AskUserQuestion 展示任务清单让用户确认

> **注意**：自动生成的任务清单不写入 `tasks.md`（那是 OpenSpec 制品），而是写入 `context/phase5-task-breakdown.md`，避免与 OpenSpec 流程产生歧义。

---

## 并行执行模式（v3.2.0 混合模式增强）

当 `config.phases.implementation.parallel.enabled = true` 时，Phase 5 使用**混合模式**：
按独立域分组并行 + 每组完成后批量 review，兼顾速度和质量。

> **参考协议**: `references/parallel-dispatch.md`（通用并行编排）+ `references/parallel-phase5.md`（Phase 5 专属配置与模板）

### 并行模式核心流程（v3.4.0: 域级单 Agent）

> **v3.4.0 变更**: 每个域（backend/frontend/node）严格只分配 1 个 Agent，
> 该 Agent 批量处理域内所有 tasks。跨域并行（backend ‖ frontend ‖ node），域内串行。
>
> **v5.8 强制约束**: `parallel.enabled = true` 时，**主线程禁止自行编码实施任何 task**。
> 所有实施工作必须通过子 Agent（Task 工具）完成。主线程角色严格限于编排：
> 解析任务清单、分域、dispatch Task、等待结果、合并 worktree、写 checkpoint。

```
1. 解析任务清单 → 按域分组（从 config.domain_agents 路径前缀匹配 + auto 自动发现）
2. 主线程一次性提取所有任务的完整文本和上下文
   （关键：子 Agent 不自己读取计划文件，避免上下文重复膨胀）
3. 对每个非空域同时并行派发（最多 max_agents 个，默认 8）:
   a. 每域 1 个 Task(isolation: "worktree", run_in_background: true)
   b. 域 Agent 收到: 该域所有 task 全文 + 域级文件所有权 + 项目规则
   c. 域 Agent 按 task 编号逐个实施（域内串行）
   d. 等待全部域完成 → 收集 JSON envelope
   e. 按域顺序合并 worktree（最多 3 次 merge）
   f. 运行 typecheck 快速验证
   g. 派发 review subagent 批量审查所有域的变更
   h. review 发现问题 → resume 对应域 agent 修复
4. 跨域任务串行执行（在所有并行域完成后）
5. 全部完成后运行 full_test
```

### 与 Superpowers subagent-driven 的关键差异

| 维度 | Superpowers | Autopilot v3.4.0 |
|------|-------------|-------------------|
| 实施模式 | 严格串行（每次一个 subagent） | 域间并行 + 域内串行（每域 1 Agent） |
| 并行粒度 | 独立问题域 | 域级单 Agent（backend ‖ frontend ‖ node） |
| Review | 每任务双阶段（spec + quality） | 全域批量 review |
| 隔离方式 | 无 worktree | 每域 1 个 worktree + 域级文件所有权 |
| 冲突处理 | 不涉及 | 域间合并冲突检测 + 自动降级 |
| 上下文管理 | 控制器提取全文（借鉴） | 控制器提取全文 |
| 修复策略 | resume 同一 agent（借鉴） | resume 同一域 agent |

### 依赖分析

1. 读取 `openspec/changes/<name>/tasks.md`，解析所有 task
2. 构建 task 依赖图（基于 task 描述中的文件引用和显式依赖声明）
3. 识别可并行执行的 task 组（无共享文件修改的 task）

> **v5.5**: 依赖分析已下沉到 `generate-parallel-plan.sh` 确定性脚本。
> 主线程调用脚本生成 `parallel_plan.json`，其中 `dependency_graph` 字段
> 包含完整的依赖关系（显式 depends_on + 文件冲突隐式依赖）。

### 文件所有权分区（v3.0 新增）

在依赖图基础上增加文件所有权隔离，从根本上消除合并冲突：

#### 分区算法（v3.4.0: 通用路径前缀匹配）

```
1. 解析 tasks.md → 提取每个 task 的 affected_files[]
2. 从 config.phases.implementation.parallel.domain_agents 读取路径前缀列表
3. 对每个 task，用最长前缀匹配确定所属域：
   - 匹配到 domain_agents 中的前缀 → 归入该域
   - domain_detection == "auto" 且未匹配 → 自动以顶级目录为域
   - 跨多个域 → 归入 cross_cutting
4. cross_cutting_tasks 串行执行（在所有并行域完成后）
5. 每个域的 Agent 收到明确的文件所有权列表
```

> **不硬编码目录名**：域由配置的 `domain_agents` 路径前缀决定。
> 默认配置为 `backend/`、`frontend/`、`node/`，可自由添加任意路径前缀。
>
> **溢出策略**：当域数超过 `max_agents`（默认 8）时，自动将使用相同 Agent 的域
> 合并为一个逻辑域。例如 3 个 `backend-developer` 域合并为 1 个 Agent 批量处理。
> 合并后仍超标 → 将 auto 发现的域降级到 cross_cutting 串行执行。

#### 所有权强制执行

每个并行 agent 的 prompt 中注入：

```
## 文件所有权约束（ENFORCED）
你被分配以下文件的独占所有权：
{task.owned_files}

禁止修改此列表之外的任何文件。
unified-write-edit-check Hook 会拦截越权修改。
```

#### 与 unified-write-edit-check 的集成

并行执行期间，主线程将每个 agent 的 owned_files 写入临时文件：
`openspec/changes/<name>/context/phase-results/phase5-ownership/agent-{N}.json`

unified-write-edit-check.sh 在并行模式下额外检查：
- 读取当前 agent 的 ownership 文件
- 验证 Write/Edit 目标文件在 owned_files 范围内
- 越权 → block

> **降级**：如果 ownership 文件不存在（非并行模式），跳过此检查（向后兼容）。

### 依赖图构建算法（v2.4.0 细化）

```
1. 解析 tasks.md 中每个 task 的描述
2. 对每个 task 提取 affected_files[]：
   a. 显式文件路径引用（如 "修改 backend/src/.../Controller.java"）
   b. 显式 depends_on 标记（如 "依赖 Task 1.1"）
   c. 目录级推断（如 "实现用户模块" → backend/src/.../user/）
3. 构建邻接矩阵：task_i → task_j 有边，当且仅当 affected_files 有交集
4. 使用连通分量算法（Union-Find）将 task 分为独立组
5. 每组内的 task 可并行执行
6. 组间按 task 编号最小值排序，顺序执行
```

### 并行派发策略（v3.4.0: 域级单 Agent）

```
域分区: 三步检测 → 前缀匹配 + auto 发现 + 同 Agent 合并
max_parallel_domains = config.max_agents (默认 8)

domain_agents = []
for each domain in [backend, frontend, node] where domain_tasks 非空:
  agent = Task(
    subagent_type: config.phases.implementation.parallel.domain_agents[domain].agent,
    isolation: "worktree",          # 每域 1 个 worktree
    run_in_background: true,
    prompt: "批量实施 {domain} 域所有 tasks: {domain_tasks} ..."
  )
  domain_agents.append(agent)

等待所有域 agents 完成（最多 8 个并行）
按域顺序合并 worktree（最多 3 次 merge）
运行测试验证
cross_cutting 串行执行
```

### 合并策略（v3.4.0: 简化为域级合并）

- 每个域完成后，合并该域 worktree（最多 3 次 merge，而非每 task 1 次）
- 合并冲突 → AskUserQuestion 展示冲突文件，让用户选择处理方式
- 合并成功后运行 quick_check 验证
- 域 Agent 返回的信封中含 `tasks_completed` 数组，主线程为每个 task 写入 checkpoint

### Worktree 生命周期管理（v3.4.0: 每域 1 个 worktree）

```
1. 创建（每域 1 个）: git worktree add .claude/worktrees/{domain} -b autopilot-{domain}
   - 最多 3 个 worktree（backend + frontend + node）
2. 域 Agent 在 worktree 中批量实施域内所有 task
3. 域 Agent 完成后：
   a. 主线程切回主分支
   b. git merge --no-ff autopilot-{domain} -m "autopilot: {domain} domain — tasks #{task_list}"
   c. 如冲突 → AskUserQuestion:
      - "手动解决冲突后继续"
      - "放弃此域的并行结果，串行执行 (Recommended)"
      - "中止并行模式，全部切换为串行"
   d. 合并成功 → git worktree remove .claude/worktrees/{domain}
   e. 删除临时分支: git branch -d autopilot-{domain}
```

### 并行 TDD 后置审计（仅 tdd_mode=true 时执行）

主线程在合并所有域 Agent 的 worktree 后，逐 task 执行：
1. 检查每个 task 的 checkpoint JSON（`phase5-tasks/task-N.json`）中 `tdd_cycle` 字段完整性
2. 验证 `tdd_metrics` 存在且 `red_violations === 0`
3. 如果 task checkpoint 缺少 `tdd_cycle`，标记该 task 为 `tdd_unverified`
4. `tdd_unverified` 的 task 数 > 0 → 警告（stderr 输出），但不阻断（v4.1 宽松策略）
5. 全量测试验证通过后继续

> **设计意图**: 并行模式下域 Agent 以 `run_in_background: true` 运行，L2 Hook 被跳过。
> 此后置审计作为补偿机制，在合并后验证 TDD 循环完整性。未来版本可升级为阻断策略。

### 并行 Checkpoint 管理（v2.4.0 细化）

- 每个 task 合并成功后，由**主线程**（非子 Agent）写入 `phase5-tasks/task-N.json`
- 子 Agent 不直接写入 checkpoint（隔离约束）
- 主线程从子 Agent 返回的 JSON 信封提取 artifacts 和 summary

### 降级决策树（v5.8 更新）

> **关键约束**: `parallel.enabled = true` 时，降级目标为"子 Agent 串行模式"（路径 B），
> **绝不允许**主线程自行编码实施任务。降级仅改变 Task 的 `run_in_background` 参数（改为 false），
> 主线程始终通过 Task 工具派发子 Agent。

```
IF worktree 创建失败（磁盘空间/权限）
  → AskUserQuestion: "worktree 创建失败，是否切换到前台串行子 Agent 模式（路径 B）？"
  → 用户确认后：每域改用 Task(run_in_background: false) 逐个前台执行
  → 禁止主线程直接实施任务
IF 域级合并冲突 > 3 个文件
  → 回退该域 worktree → 改用 Task(run_in_background: false) 串行重执行该域所有 task
IF 2 个域合并失败 → AskUserQuestion → 用户确认后全域改用前台 Task 串行执行
IF 用户在 AskUserQuestion 选择 "切换串行" → 全域改用前台 Task 串行执行
降级原因记录到 checkpoint: _metrics.parallel_fallback_reason
```

## 并行合并验证 (Hook 级保障)

`parallel-merge-guard.sh` 作为 PostToolUse(Task) hook，在每次 worktree merge 后自动触发，提供确定性的合并质量验证。

### 触发条件

- Phase 5 Task 调用（prompt 包含 `<!-- autopilot-phase:5 -->`）
- tool_response 中包含 worktree merge 相关内容

### 三层验证

| 检查项 | 方法 | 说明 |
|--------|------|------|
| 合并冲突检测 | `git diff --check` + `git diff --cached --check` | 确定性检测，不依赖 AI 判断。检查工作区和暂存区是否残留冲突标记 |
| Task scope 校验 | 对比 `git diff --name-only HEAD~1 HEAD` 与 envelope artifacts | 确保合并引入的文件变更在预期 task 范围内，防止跨 task 污染 |
| 快速类型检查 | 读取 `config.test_suites` 中 `type: typecheck` 的命令并执行 | 每次 merge 后立即运行，尽早捕获集成类型错误，避免问题累积到 Phase 6 |

### 合并冲突检测的确定性保障

- `git diff --check` 是 Git 原生命令，输出完全确定性
- 不依赖 LLM 判断冲突是否存在，消除 AI 幻觉风险
- 同时检查工作区（unstaged）和暂存区（staged）两个层面

### 快速类型检查的早期拦截

- 从 `autopilot.config.yaml` 的 `test_suites` 中动态读取所有 `type: typecheck` 的套件命令
- 每次 worktree merge 后立即执行，而非等到所有 task 完成
- 单次 typecheck 超时限制 120 秒，避免阻塞流水线

### merge guard 阻断时的处理流程

当 hook 输出 `decision: "block"` 时，主线程应：

1. **展示冲突详情**：将 hook reason 中的具体 violation 信息呈现给用户，包括冲突文件列表、scope 外文件、typecheck 错误输出
2. **提供回滚选项**：
   - "回退此次 merge，串行重新执行该 task"（推荐）
   - "手动修复后继续"
   - "放弃并行模式，全部切换为串行"
3. **记录阻断事件**：在 `phase5-tasks/` checkpoint 中记录 `_metrics.merge_guard_blocked: true` 及阻断原因

---

## 实施流程（串行模式 — 仅当 parallel.enabled = false）

> **条件检查**：仅当 `config.phases.implementation.parallel.enabled = false`（默认值）且未从路径 A 降级时才执行本节。
> 如果 `parallel.enabled = true`，必须执行上方「并行执行模式」章节，**禁止进入本节**。
> 如果从路径 A 降级，降级后的执行路径依然通过 Task 工具派发子 Agent（见路径 A 降级决策树），
> **主线程不在任何路径下直接编码实施任务**。

### 前台 Task 逐个派发（串行模式）

主线程通过**前台 Task**（同步阻塞）逐个派发每个 task 给子 Agent 执行。子 Agent 的内部工具调用（Read/Write/Edit/Bash 等）不会灌入主线程上下文，实现上下文隔离。

#### 核心流程

```
主线程编排:
1. 解析任务清单（tasks.md 或 phase5-task-breakdown.md）
2. 扫描 phase5-tasks/ 确定恢复点（跳过已完成 task）
3. for each remaining_task:
   a. 构造 task prompt（任务描述 + 前序摘要 + 项目规则 + 验证命令）
   b. domain = longest_prefix_match(task.affected_files, domain_prefixes)
      agent = resolve_agent(domain) || config...default_agent
      result = Task(subagent_type: agent,
                    prompt: "<!-- autopilot-phase:5 --> 实施 task #{N}...")
      → 主线程同步阻塞等待子 Agent 完成
   c. 解析 result 中的 JSON 信封
   d. 写入 phase5-tasks/task-N.json checkpoint
   e. git add -A && git commit --fixup=$ANCHOR_SHA -m "fixup! autopilot: start <change_name> — task #{N}"
   f. 如果 status == "failed" 且连续失败 3 次 → AskUserQuestion 决策
   g. 继续下一个 task
4. 全部完成后运行 full_test（config.test_suites 全量）
5. 写入 test-results.json
```

#### 前台 Task 串行模式的优势

| 维度 | 说明 |
|------|------|
| 上下文影响 | 子 Agent 内部输出隔离，仅 JSON 信封回传 |
| 确定性 | Task 调用，同步阻塞 |
| 崩溃恢复 | task 级 checkpoint，扫描恢复 |
| 工具可用性 | 完整（主线程） | Read/Write/Edit/Bash/Glob/Grep（子 Agent 无 Task 工具，但单 task 不需要嵌套） |
| Hook 集成 | 主线程 Hook | 子 Agent 工具调用仍触发 Hook |

#### Task Prompt 模板

```markdown
Task(
  subagent_type: resolve_agent(longest_prefix_match(task.affected_files, domain_prefixes)) || default_agent,
  prompt: "<!-- autopilot-phase:5 -->
你是 autopilot Phase 5 的串行实施子 Agent。

## 你的任务
仅实施以下单个 task（禁止实施其他 task）：
- Task #{task_number}: {task_title}
- Task 内容: {task_full_text}

## 前序 task 摘要（只读参考）
{for each completed_task}
- Task #{n}: {summary} — 已完成
{end for}

## 上下文（由控制器提取，禁止自行读取计划文件）
{context_injection}

## 项目规则约束
{rules_scan_result}

## 验证要求
每个任务完成后运行快速校验：
{for each suite in config.test_suites where suite.type in ['typecheck', 'unit']}
- `{suite.command}`
{end for}

## 返回要求
执行完毕后返回 JSON 信封：
{\"status\": \"ok|warning|blocked|failed\", \"summary\": \"...\", \"artifacts\": [...], \"test_result\": \"N/M passed\"}
"
)
```

#### 失败处理

- 单个 task 失败：主线程解析 JSON 信封中的错误信息，retry 同一 task（最多 3 次）
- 连续 3 次失败：AskUserQuestion 展示错误详情，选项：
  - "查看错误详情并手动修复"
  - "跳过此 task，继续下一个（标记 warning）"
  - "中止 Phase 5"
- 跳过的 task 记录到 checkpoint：`status: "warning"`, `skip_reason: "user_skipped_after_3_failures"`

#### 恢复协议

Phase 5 启动时（含压缩后恢复），扫描 `phase5-tasks/` 目录：

1. 列出所有 `task-N.json` 文件，按 N 排序
2. 找到最后一个 `status: "ok"` 或 `status: "warning"` 的 task
3. 从下一个 task 继续执行
4. 如果没有 task checkpoint → 从 task 1 开始

### 串行模式优化：无依赖 task 后台并行引擎（v4.2 — Concurrency Engine）

> **v4.2 升级**: 从 v4.1 可选优化升级为**默认行为**。串行模式下自动检测无依赖 task 并批量后台派发，
> 显著降低 Phase 5 总耗时。仅在显式禁用或 TDD 模式下回退到纯串行。

**启用条件**（默认全部满足）：
1. `config.serial_task.allow_background_parallel !== false`（默认 true）
2. 不处于 TDD 模式（TDD 必须严格串行以保障 RED-GREEN 顺序）

**核心算法：Batch Scheduler（v5.5 — 确定性计划驱动）**

> **v5.5 变更**: 主线程在 dispatch 前**必须**调用 `generate-parallel-plan.sh` 生成 `parallel_plan.json`。
> Scheduler 消费 `parallel_plan.json` 的 `batches` 字段，而非模型自行决定 batch 分组。
> fallback 时**必须**有结构化 `fallback_reason`。

```
0. 调用 generate-parallel-plan.sh 生成 parallel_plan.json
   - 输入: 任务列表 JSON 数组 [{task_name, affected_files, depends_on, domain}]
   - 输出: parallel_plan.json (含 batches[], dependency_graph, scheduler_decision)
   - 发射 parallel_plan 事件到 events.jsonl
1. 读取 parallel_plan.json:
   - fallback_to_serial=true → 纯串行执行所有 task
   - 否则按 batches[] 顺序执行
2. 对每个 batch (从 parallel_plan.json 的 batches 字段):
   发射 parallel_batch_start 事件
   if can_parallel=false 或 len(tasks)==1:
     → 前台 Task 同步执行（零开销）
   else:
     → 全部 Task(run_in_background: true) 后台并行派发
     → 等待 Claude Code 自动完成通知
     → 收集所有 JSON 信封
     → 按 task 编号顺序写入 checkpoint + git fixup
   发射 parallel_batch_end 事件
3. 继续下一个 batch
```

**Batch 派发模板**

```markdown
# 在同一条消息中同时发起 batch 内所有 task
{for each task in batch}
Task(
  subagent_type: "{resolve_agent(task.domain)}",
  run_in_background: true,
  prompt: "<!-- autopilot-phase:5 -->
你是 autopilot Phase 5 的并行实施子 Agent（Batch #{batch_id}, Task #{task_number}）。

## 你的任务
仅实施以下单个 task（禁止实施其他 task）：
- Task #{task_number}: {task_title}
- Task 内容: {task_full_text}

## 前序 task 摘要（只读参考）
{completed_task_summaries}

## 上下文（由控制器提取，禁止自行读取计划文件）
{context_injection}

## 文件所有权约束（ENFORCED — batch 内互斥）
你被分配以下文件的独占所有权：
{task.affected_files}
禁止修改此列表之外的任何文件。同 batch 其他 task 正在修改: {sibling_task_files}

## 项目规则约束
{rules_scan_result}

## 返回要求
执行完毕后返回 JSON 信封：
{\"status\": \"ok|warning|blocked|failed\", \"summary\": \"...\", \"artifacts\": [...], \"test_result\": \"N/M passed\"}
"
)
{end for}
```

**Batch 结果汇总（Wait & Merge）**

```
for each completed_agent in batch:
  envelope = parse JSON 信封
  if envelope.status == "failed":
    # 记录失败，后续 batch 可能需要降级
    failed_tasks.append(task)
  else:
    # 按 task 编号顺序写入 checkpoint
    write phase5-tasks/task-{N}.json
    git add -A && git commit --fixup

if len(failed_tasks) > 0:
  # 失败 task 降级为下一 batch 首个纯串行执行
  retry_queue.extend(failed_tasks)
```

**降级条件**：
- batch 中 > 50% task 失败 → 剩余所有 task 回退到纯串行
- 任何 task 修改了非 owned_files 范围的文件 → 后续 batch 回退到纯串行
- 用户通过 AskUserQuestion 选择 "切换纯串行"

**预期收益**: Phase 5 串行耗时减少 40-60%（取决于 task 间依赖度）。
10 个 task 中若有 3 个 batch（3+4+3），总耗时 ≈ 3×max(batch_time) 而非 10×task_time。

## Phase 5→6 特殊门禁

autopilot-gate 额外验证：
- `test-results.json` 存在
- `zero_skip_check.passed === true`
- `tasks.md` 中所有任务标记为 `[x]`

---

## Task 级 Checkpoint

为支持 Phase 5 长时间运行中的崩溃恢复，每个 task 完成后写入独立 checkpoint。

### Checkpoint 目录

```
openspec/changes/<name>/context/phase-results/phase5-tasks/
├── task-1.json
├── task-2.json
├── task-3.json
└── ...
```

### Checkpoint 格式

```json
{
  "task_number": 1,
  "task_title": "实现用户登录 API",
  "status": "ok",
  "summary": "完成登录接口，通过 3 个单元测试",
  "artifacts": ["backend/src/main/java/.../LoginController.java"],
  "test_result": "3/3 passed",
  "_metrics": {
    "start_time": "2026-01-15T10:30:00Z",
    "end_time": "2026-01-15T10:45:00Z",
    "duration_seconds": 900,
    "retry_count": 0
  }
}
```

### 恢复协议

Phase 5 启动时，扫描 `phase5-tasks/` 目录：

1. 列出所有 `task-N.json` 文件，按 N 排序
2. 找到最后一个 `status: "ok"` 的 task
3. 从下一个 task 继续执行
4. 如果没有 task checkpoint → 从 task 1 开始

### 写入时机

每个 task 完成后（无论串行 Task 还是并行模式），主线程应：

1. 确保 `phase5-tasks/` 目录存在
2. 写入 `task-N.json`（N 为 task 编号）
3. 验证写入成功
4. **v5.2: 发射 task_progress 事件**（GUI 实时看板消费）：
   ```
   Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-task-progress.sh "task-{N}-{slug}" {status} {N} {total} {mode} [tdd_step]')
   ```
   status 映射: ok/warning → "passed", failed/blocked → "failed"

---

## TDD Mode（当 `tdd_mode: true` 且模式为 `full`）

> 详细协议见 `references/tdd-cycle.md`。本节为 Phase 5 集成概述。

### 概述

TDD 模式将 Phase 4（测试设计）的职责吸收到 Phase 5，对每个 task 执行 RED-GREEN-REFACTOR 确定性循环。

### 串行 TDD 流程

对每个 task：
1. **RED**: 派发子 Agent 仅写测试 → 主线程 Bash() 验证测试失败
2. **GREEN**: 派发子 Agent 写最小实现 → 主线程 Bash() 验证测试通过
3. **REFACTOR**（可选）: 派发子 Agent 重构 → 主线程 Bash() 验证测试仍通过

每个步骤之间由主线程执行确定性验证（L2）。

### 并行 TDD 流程

域 Agent prompt 注入完整 TDD 纪律文档，Agent 内部自主执行 RED-GREEN-REFACTOR。
主线程在合并后验证 `tdd_cycles` 完整性。

### TDD Task Checkpoint 格式

```json
{
  "task_number": 1,
  "task_title": "实现用户登录 API",
  "status": "ok",
  "tdd_cycle": {
    "red": { "verified": true, "test_file": "tests/test_login.py", "test_command": "pytest tests/test_login.py" },
    "green": { "verified": true, "impl_files": ["src/login.py"], "retries": 0 },
    "refactor": { "verified": true, "reverted": false }
  },
  "artifacts": ["src/login.py", "tests/test_login.py"],
  "_metrics": { "start_time": "...", "end_time": "...", "duration_seconds": 900 }
}
```

### TDD 崩溃恢复

扫描 `phase5-tasks/task-N.json` 的 `tdd_cycle` 字段确定恢复点：
- 无 `tdd_cycle` → 从 RED 开始
- `red.verified = true`，无 `green` → 从 GREEN 恢复
- `green.verified = true`，无 `refactor` → 从 REFACTOR 恢复
- `tdd_cycle` 完整 → 下一个 task
