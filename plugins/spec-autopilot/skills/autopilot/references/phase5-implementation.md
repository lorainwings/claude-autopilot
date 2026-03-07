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

> **参考协议**: `references/parallel-dispatch.md`（通用并行编排）

### 混合模式核心流程

```
1. 解析任务清单 → 构建文件依赖图（Union-Find 或域级快速分区）
2. 主线程一次性提取所有任务的完整文本和上下文
   （关键：子 Agent 不自己读取计划文件，避免上下文重复膨胀）
3. 对每个并行组:
   a. Task(isolation: "worktree", run_in_background: true) × N 并行派发
   b. 每个 subagent 收到: 任务全文 + 文件所有权 + 项目规则
   c. subagent 可通过 AskUserQuestion 提问，主线程回答
   d. 等待全部完成 → 收集 JSON envelope
   e. 按 task 编号顺序合并 worktree
   f. 运行 typecheck 快速验证
   g. 【新增】派发 review subagent 批量审查本组所有变更
      - 规范符合性审查（实现是否符合需求描述）
      - 代码质量审查（是否符合项目规则约束）
      - 跨 task 一致性检查
   h. review 发现问题 → resume 对应 implementer agent 修复
4. 跨域任务串行执行（在所有并行组完成后）
5. 全组完成后运行 full_test
```

### 与 Superpowers subagent-driven 的关键差异

| 维度 | Superpowers | Autopilot v3.2.0 |
|------|-------------|-------------------|
| 实施模式 | 严格串行（每次一个 subagent） | 组内并行 + 组间串行 |
| Review | 每任务双阶段（spec + quality） | 每组批量 review |
| 隔离方式 | 无 worktree | worktree + 文件所有权分区 |
| 冲突处理 | 不涉及 | 3 层检测 + 自动降级 |
| 上下文管理 | 控制器提取全文（借鉴） | 控制器提取全文 |
| 修复策略 | resume 同一 agent（借鉴） | resume 同一 agent |

### 依赖分析

1. 读取 `openspec/changes/<name>/tasks.md`，解析所有 task
2. 构建 task 依赖图（基于 task 描述中的文件引用和显式依赖声明）
3. 识别可并行执行的 task 组（无共享文件修改的 task）

### 文件所有权分区（v3.0 新增）

在依赖图基础上增加文件所有权隔离，从根本上消除合并冲突：

#### 分区算法

```
1. 解析 tasks.md → 提取每个 task 的 affected_files[]
2. 按顶级目录分组：
   - backend_tasks: 仅修改 backend/ 下文件的 task
   - frontend_tasks: 仅修改 frontend/ 下文件的 task
   - node_tasks: 仅修改 node/ 下文件的 task
   - cross_cutting_tasks: 修改多个顶级目录的 task
3. 同组内的 task 可并行执行（文件无重叠保证）
4. cross_cutting_tasks 串行执行（在所有并行组完成后）
5. 每个并行 agent 收到明确的文件所有权列表
```

#### 所有权强制执行

每个并行 agent 的 prompt 中注入：

```
## 文件所有权约束（ENFORCED）
你被分配以下文件的独占所有权：
{task.owned_files}

禁止修改此列表之外的任何文件。
write-edit-constraint-check Hook 会拦截越权修改。
```

#### 与 write-edit-constraint-check 的集成

并行执行期间，主线程将每个 agent 的 owned_files 写入临时文件：
`openspec/changes/<name>/context/phase-results/phase5-ownership/agent-{N}.json`

write-edit-constraint-check.sh 在并行模式下额外检查：
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

### 并行派发策略

```
独立 task 组 = 分析依赖图，找出无交叉文件的 task 集合
max_parallel = config.phases.implementation.parallel.max_agents (默认 3)

for each task_group in 独立 task 组:
  agents = []
  for each task in task_group[:max_parallel]:
    agent = Task(
      subagent_type: "general-purpose",
      isolation: "worktree",          # 每个 agent 独立 worktree
      run_in_background: true,
      prompt: "实施 task: {task.title}, change: {change_name} ..."
    )
    agents.append(agent)

  等待所有 agents 完成
  合并各 worktree 变更到主分支
  解决冲突（如有）
  运行测试验证
```

### 合并策略

- 每组并行 task 完成后，按 task 编号顺序合并 worktree
- 合并冲突 → AskUserQuestion 展示冲突文件，让用户选择处理方式
- 合并成功后运行 quick_check 验证
- 每组完成后写入对应 task 的 checkpoint（`phase5-tasks/task-N.json`）

### Worktree 生命周期管理（v2.4.0 细化）

```
1. 创建: git worktree add .claude/worktrees/task-{N} -b autopilot-task-{N}
2. 子 Agent 在 worktree 中执行实施
3. 子 Agent 完成后：
   a. 主线程切回主分支
   b. git merge --no-ff autopilot-task-{N} -m "autopilot: task {N} - {title}"
   c. 如冲突 → AskUserQuestion:
      - "手动解决冲突后继续"
      - "放弃此 task 的并行结果，稍后串行执行 (Recommended)"
      - "中止并行模式，全部切换为串行"
   d. 合并成功 → git worktree remove .claude/worktrees/task-{N}
   e. 删除临时分支: git branch -d autopilot-task-{N}
```

### 并行 Checkpoint 管理（v2.4.0 细化）

- 每个 task 合并成功后，由**主线程**（非子 Agent）写入 `phase5-tasks/task-N.json`
- 子 Agent 不直接写入 checkpoint（隔离约束）
- 主线程从子 Agent 返回的 JSON 信封提取 artifacts 和 summary

### 降级决策树（v2.4.0 细化）

```
IF worktree 创建失败（磁盘空间/权限） → 立即降级为串行
IF 单组内合并冲突 > 3 个文件 → 回退该组所有 worktree → 串行执行该组
IF 连续 2 组合并失败 → 全面降级为串行（config.parallel.auto_downgrade_threshold）
IF 用户在 AskUserQuestion 选择 "切换串行" → 全面降级
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
> 如果从路径 A 降级到串行模式，本节作为降级后的执行路径。

1. 检查 `.claude/settings.json` 中 `enabledPlugins` 是否包含 `ralph-loop`
2. **检查 worktree 隔离模式**：读取 `config.phases.implementation.worktree.enabled`
   - **启用** → Phase 5 按 task 粒度派发，每个 task 通过 `Task(isolation: "worktree")` 在独立 worktree 中执行
     - 每个 task 完成后，worktree 变更自动合并回主分支
     - 如有合并冲突 → AskUserQuestion 展示冲突文件，让用户选择处理方式
     - 主线程上下文不被实现代码膨胀
   - **禁用**（默认） → 使用下方 ralph-loop / fallback 策略
3. **ralph-loop 可用** → 构造 ralph-loop 调用参数并执行：

   **参数构造**：
   - PROMPT: 从 config.phases.implementation.instruction_files 中读取指令文件内容，
     拼接为完整实施 prompt（包含 change_name、tasks 路径、测试命令等）
   - --max-iterations: 从 config.phases.implementation.ralph_loop.max_iterations 读取
   - --completion-promise: "所有 tasks.md 中的任务标记为完成且所有测试通过"

   **调用**：
   ```
   Skill("ralph-loop:ralph-loop", args: "使用 Skill('openspec-apply-change') 逐个实施 openspec/changes/<change_name>/ 中的任务。<instruction_files内容摘要> --max-iterations <max_iterations> --completion-promise 所有 tasks.md 中的任务标记为完成且所有测试通过")
   ```

   **完成后**：读取 `openspec/changes/<name>/testreport/test-results.json`，
   从中提取 test_results_path、tasks_completed、zero_skip_check 构造 Phase 5 JSON 信封。
4. **不可用但 config.phases.implementation.ralph_loop.fallback_enabled** → 进入手动循环模式
   - 每次迭代执行 Skill(`openspec-apply-change`) 实施一个任务
   - 每任务后运行 quick_check，每 3 任务运行 full_test
   - 遵循 3 次失败暂停策略
   - 最大迭代次数从 config.phases.implementation.ralph_loop.max_iterations 读取
4. **不可用且 fallback 禁用** → AskUserQuestion：
   ```
   "ralph-loop 插件不可用，手动 fallback 也已禁用。请选择处理方式："
   选项:
   - "启用 fallback 模式 (Recommended)" → 修改 config 中 fallback_enabled 为 true，进入手动循环
   - "暂停流水线，手动安装 ralph-loop" → 展示安装命令，暂停等待
   - "跳过实施阶段（仅测试已有代码）" → 标记 Phase 5 为 warning，继续 Phase 6
   ```

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

每个 task 完成后（无论 ralph-loop 还是 fallback 模式），主线程/ralph-loop 应：

1. 确保 `phase5-tasks/` 目录存在
2. 写入 `task-N.json`（N 为 task 编号）
3. 验证写入成功
