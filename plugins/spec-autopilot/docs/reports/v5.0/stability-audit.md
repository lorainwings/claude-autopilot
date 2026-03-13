# 稳定性与状态控制审计报告

**插件**: spec-autopilot
**版本**: v5.0.1 (基于 commit 91d1c48)
**审计日期**: 2026-03-13
**审计方**: 工程审计 Agent (Claude Opus 4.6)

---

## 1. 执行摘要

| 严重度 | 数量 |
|--------|------|
| **Critical (致命)** | 2 |
| **High (高危)** | 4 |
| **Medium (中危)** | 6 |
| **Low (低危)** | 5 |
| **合计** | 17 |

spec-autopilot 插件展现了架构良好的三层门禁系统，在所有执行模式下均有全面覆盖。状态机强制执行逻辑稳健，确定性 Hook 脚本提供了 fail-closed 行为。但存在以下关键问题：文件写入原子性缺失、后台 Agent 对 L2 Hook 的系统性绕过、以及崩溃恢复的若干盲区。并行合并安全机制虽然全面，但依赖输出文本模式匹配，存在脆弱性。

---

## 2. 状态机分析

### 2.1 Full 模式 (Phase 0 → 1 → 2 → 3 → 4 → 5 → 6 → 7)

**执行追踪**:
- Phase 0: `autopilot-phase0/SKILL.md` 步骤 1-10 在主线程执行。不写 checkpoint（SKILL.md:88: "Phase 0 不写 checkpoint"）
- Phase 1: 主线程执行需求循环。checkpoint 写入 `phase-1-requirements.json`
- Phase 2-6: 遵循统一调度模板（SKILL.md:146-200）。每个阶段: Gate 检查(8步) → 派发 → 解析信封 → 写 checkpoint → 下一阶段
- Phase 7: `autopilot-phase7/SKILL.md` 执行汇总、用户确认、归档

**阶段排序强制**:
- L1 (TaskCreate blockedBy): Phase 0 步骤 7 (`autopilot-phase0/SKILL.md:92-96`) 创建带 blockedBy 链的任务。Full 模式创建 7 个任务 (Phase 1-7) 按顺序依赖
- L2 (Hook): `check-predecessor-checkpoint.sh:219-250` 实现 `get_predecessor_phase()`, Full 模式返回 N-1（TDD 例外: Phase 5 要求 Phase 3 而非 Phase 4）
- L3 (AI Gate): `autopilot-gate/SKILL.md:27-39` 8 步检查清单在步骤 6 验证 checkpoint 存在

**发现 [F-01]**: Full 模式阶段排序在三层门禁中均得到完整强制执行。

### 2.2 Lite 模式 (Phase 0 → 1 → 5 → 6 → 7)

**执行追踪**:
- Phase 0: 创建 4 个任务 (Phase 1, 5, 6, 7)，Phase 5 blockedBy Phase 1 (`autopilot-phase0/SKILL.md:94`)
- Phase 2/3/4 不创建任务
- Phase 5 前驱为 Phase 1 (`check-predecessor-checkpoint.sh:224-226`: `5) echo 1 ;;` lite 模式)

**L2 强制**: `check-predecessor-checkpoint.sh:256-258` 在非 Full 模式下显式拒绝 Phase 2 派发: `deny "Phase 2 is skipped in $EXEC_MODE mode."`。Phase 3/4 在 271-275 行同样处理。

**Gate 模式感知**: `autopilot-gate/SKILL.md:196-208` 记录了模式感知的 gate 行为。Lite 模式 Phase 1→5 门禁只检查 Phase 1 checkpoint 存在。

**发现 [F-02]**: Lite 模式阶段排序正确强制执行。对非 Full 模式 Phase 2/3/4 的显式拒绝防止了无效派发。

### 2.3 Minimal 模式 (Phase 0 → 1 → 5 → 7)

**执行追踪**:
- Phase 0: 创建 3 个任务 (Phase 1, 5, 7)，Phase 5 blockedBy Phase 1 (`autopilot-phase0/SKILL.md:95`)
- Phase 6 派发被拒绝: `check-predecessor-checkpoint.sh:360-361`: `deny "Phase 6 is skipped in minimal mode."`
- Phase 7 前驱为 Phase 5 (`check-predecessor-checkpoint.sh:233`: `7) echo 5 ;;` minimal 模式)

**发现 [F-03]**: Minimal 模式阶段排序正确强制执行。

### 2.4 模式切换防护

**模式不可变性**: 模式在 Phase 0 步骤 3 确定 (`autopilot-phase0/SKILL.md:39-49`)，写入锁文件步骤 9 (`autopilot-phase0/SKILL.md:113-115`)，Hook 从锁文件读取 (`check-predecessor-checkpoint.sh:166-182`)。

**发现 [M-01, 中危]**: 模式仅存于锁文件，无 Checkpoint 交叉校验
模式存储在 `.autopilot-active` 锁文件中，但不写入单个阶段 checkpoint 文件。如果锁文件在执行中被手动编辑或损坏，模式理论上可以被篡改。恢复协议 (`autopilot-recovery/SKILL.md:86-91`) 从锁文件读取模式，这是单一事实来源。

**缓解**: 锁文件在 `.gitignore` 中（Phase 0 步骤 8），降低了意外修改风险。但锁文件内容无校验和或签名保护。

---

## 3. 门禁系统覆盖率分析

### 3.1 Layer 1: TaskCreate blockedBy

**覆盖范围**: Phase 0 (`autopilot-phase0/SKILL.md:92-96`) 创建带 blockedBy 依赖的任务链。由 Claude Code 任务系统自身强制执行。

**发现 [C-01, 致命]**: L1 仅覆盖基于 Task 的阶段
Phase 0 通过 Skill 调用执行（非 Task），没有 L1 门禁。Phase 1 在主线程执行，同样无 L1。Phase 7 通过 Skill 执行。仅 Phase 2-6 受益于 L1 TaskCreate blockedBy 强制执行。

**影响**: Phase 1 和 Phase 7 仅依赖 L3 (AI Gate) 和编排器 SKILL.md 中的程序化排序。没有确定性 Hook 阻止 AI 编排器故障时跳过 Phase 1。

**缓解**: Phase 1 是第一个阶段，无前驱可检查。Phase 7 由编排器在所有 gate 通过后显式调用。风险低但架构完整性不足。

### 3.2 Layer 2: Hook 脚本

**PreToolUse(Task)**: `check-predecessor-checkpoint.sh` 在所有 Task 派发时触发。

**发现 [H-01, 高危]**: 后台 Agent L2 绕过
`check-predecessor-checkpoint.sh:57-59` 显式跳过所有 `run_in_background: true` Agent 的验证:
```bash
if echo "$STDIN_DATA" | grep -q '"run_in_background"[[:space:]]*:[[:space:]]*true'; then
  exit 0
fi
```
49-56 行的注释解释这是设计决策: "Phase 2/3/4/6 后台派发绕过所有 L2 检查... 这些验证由 Layer 3 (autopilot-gate Skill) 保证。"

**影响**: 如果 L3 (AI Gate) 未正确执行（如上下文压缩、AI 幻觉或编排器 bug），后台 Agent 可以在无前驱 checkpoint 验证的情况下被派发。影响使用 `run_in_background: true` 的 Phase 2, 3, 4 和 6。

**补偿控制**: L3 在派发前运行且被记录为硬性要求。`post-task-validator.sh` 也在完成后验证输出。但派发前门禁存在缺口。

**PostToolUse(Task)**: `post-task-validator.sh` → `_post_task_validator.py` 运行 5 个验证器:
1. JSON 信封验证（结构 + 阶段特定字段）
2. 反合理化检查（Phase 4/5/6）
3. 代码约束检查（Phase 4/5/6）
4. 并行合并守卫（Phase 5）
5. 决策格式验证（Phase 1）

**发现 [H-02, 高危]**: PostToolUse 后台 Agent 绕过
`post-task-validator.sh:23` 同样跳过后台 Agent: `is_background_agent && exit 0`。这意味着 JSON 信封验证、反合理化检查及所有其他 PostToolUse 验证器对后台 Task 均被绕过。

**影响**: Phase 2, 3, 4 和 6（以后台方式派发时）无 L2 PostToolUse 验证。子 Agent 返回格式错误的 JSON 或合理化输出不会被 L2 捕获。

**补偿控制**: 主线程在统一调度模板步骤 4 (SKILL.md:173-176) 解析 JSON 信封。但这是 L3（AI 执行），非确定性。

**PostToolUse(Write|Edit)**: 注册了三个 Hook:
1. `write-edit-constraint-check.sh` — 代码约束强制（Phase 5）
2. `banned-patterns-check.sh` — TODO/FIXME/HACK 检测
3. `assertion-quality-check.sh` — 恒真断言检测

这些 Hook **不会**被后台 Agent 绕过，因为它们触发于 Write/Edit 工具调用（非 Task），后台 Task 内的子 Agent 仍会调用 Write/Edit 触发这些 Hook。设计正确。

### 3.3 Layer 3: AI Gate (8 步检查清单)

**覆盖范围**: `autopilot-gate/SKILL.md:27-39` 定义了每次阶段切换前执行的 8 步检查清单。

**发现 [M-02, 中危]**: L3 依赖 AI 自律
8 步检查清单是 AI 编排器必须遵循的 Markdown 规范。没有程序化强制保证所有 8 步均被执行。如果 AI 因上下文压力或幻觉跳过步骤，没有确定性兜底。

**补偿控制**: L2 Hook 为最关键的检查提供确定性强制（前驱 checkpoint 存在、JSON 信封结构）。L3 增加补充性验证（语义验证、brownfield 检查、CLAUDE.md 变更检测）。

### 3.4 三层覆盖缺口分析

| 门禁检查项 | L1 | L2 | L3 | 缺口? |
|-----------|----|----|-----|-------|
| 阶段前驱存在 | 是 (blockedBy) | 是 (check-predecessor-checkpoint.sh) | 是 (步骤 5/6) | 前台 Task 无缺口; **后台 Task 有缺口 (L2 被绕过)** |
| JSON 信封合法 | N/A | 是 (post-task-validator.py) | 是 (步骤 1/2) | **后台 Task 有缺口 (L2 被绕过)** |
| Phase 4 拒绝 warning | N/A | 是 (_post_task_validator.py:157-159) | 是 (gate SKILL.md:92-105) | **后台 Phase 4 有缺口** |
| Phase 5 zero_skip_check | N/A | 是 (check-predecessor-checkpoint.sh:367-381) | 是 (gate SKILL.md:107-115) | 无缺口 (L2 在 Phase 6 派发时检查) |
| 反合理化 | N/A | 是 (_post_task_validator.py:315-378) | 否 | **后台 Task 有缺口** |
| 文件所有权 (并行) | N/A | 是 (write-edit-constraint-check.sh) | 是 (prompt 注入) | 无缺口 (Write/Edit Hook 在子 Agent 内触发) |
| TODO/FIXME 禁用模式 | N/A | 是 (banned-patterns-check.sh) | 否 | 无缺口 (Write/Edit Hook 在子 Agent 内触发) |
| 恒真断言 | N/A | 是 (assertion-quality-check.sh) | 否 | 无缺口 (Write/Edit Hook 在子 Agent 内触发) |

---

## 4. 文件完整性分析

### 4.1 Checkpoint 写入机制

Checkpoint 由后台 Checkpoint Agent 写入 (SKILL.md:177-188):
```
Agent(subagent_type: "general-purpose", run_in_background: true, prompt: "
    1. mkdir -p ${session_cwd}/openspec/changes/<name>/context/phase-results/
    2. Write JSON 到 phase-{N}-{slug}.json
    3. Read 文件确认 JSON 有效
    4. git add -A && git commit --fixup
    5. 返回 {status, checkpoint, commit_sha}
")
```

**发现 [C-02, 致命]**: Checkpoint 写入非原子性
Checkpoint 写入使用 Claude Code 的 `Write` 工具，这是标准文件写入操作。没有原子写入模式（先写临时文件再 rename）。如果进程在 Write 操作期间崩溃，checkpoint 文件可能:
1. 部分写入（截断的 JSON）
2. 空文件（文件已创建但内容未刷盘）
3. 缺失（目录已创建但文件未写入）

**证据**: `autopilot-gate/SKILL.md:237-243` 描述写入过程: "将完整 JSON 信封写入 phase-{N}-{slug}.json，验证写入成功: 读回文件并解析 JSON。"步骤 3（读回验证）可在部分写入**发生后**检测到，但无法预防。

**影响**: 崩溃期间的 checkpoint 写入可能留下损坏的 JSON 文件。`_common.sh:124-135` 中的 `read_checkpoint_status()` 函数对无法解析的 JSON 返回 "error"，触发 L2 Hook deny。但这阻断了前进而非优雅恢复。

**建议**: 实现 write-then-rename 模式: 先写入 `phase-{N}-{slug}.json.tmp`，验证后 `mv` 到最终路径。这在 POSIX 文件系统上是原子的。

### 4.2 压缩前状态持久化

`save-state-before-compact.sh` (PreCompact Hook) 将 Markdown 摘要保存到 `context/autopilot-state.md`:
- 扫描所有 checkpoint 文件
- 记录最后完成阶段、下一阶段、模式、anchor_sha
- 记录 Phase 5 任务级进度

**发现 [M-03, 中危]**: 状态文件为信息性质，非权威来源
保存的状态 (`autopilot-state.md`) 是在压缩后重新注入的 Markdown 文档。包含恢复指令但非机器可解析的自动恢复格式。实际恢复依赖磁盘上幸存的 checkpoint JSON 文件。

**评估**: 设计正确。状态文件在压缩后补充 AI 上下文；权威状态始终是 checkpoint JSON 文件。reinject Hook (`reinject-state-after-compact.sh`) 将状态文件内容输出到 stdout，由 Claude Code 添加到会话上下文。

### 4.3 锁文件完整性

锁文件 (`openspec/changes/.autopilot-active`) 由后台 Agent 通过 Read→Write→Verify 流程管理 (`autopilot-phase0/SKILL.md:179-196`)。

**发现 [L-01, 低危]**: 锁文件 PID 竞态条件
PID 冲突检测 (`autopilot-phase0/SKILL.md:199-205`) 使用 `kill -0 ${pid}` 检查进程存活。在检查和覆写之间，PID 可能被操作系统回收。session_id 比较可以缓解但无法完全消除此竞态。

**评估**: 对于开发者工具可接受的风险。锁文件主要用于防止意外并发 autopilot 会话，非安全机制。

---

## 5. 并行安全分析

### 5.1 Worktree 隔离

Phase 5 并行模式使用 `Task(isolation: "worktree")`，在 `.claude/worktrees/` 中创建 git worktree。

**文件所有权强制**: `write-edit-constraint-check.sh` 在 Phase 5 期间验证 Write/Edit 目标在 `owned_files` 范围内。此 Hook 在子 Agent 内触发（不因子 Agent 内部工具调用而绕过）。

**发现 [M-04, 中危]**: 所有权检查依赖阶段检测启发式
`write-edit-constraint-check.sh:29-69` 通过检查哪些 checkpoint 存在来判断是否"处于 Phase 5"。逻辑:
- Full 模式: Phase 4 checkpoint 存在 且 Phase 5 checkpoint 不存在（或非 ok）→ Phase 5
- Lite/minimal: Phase 1 ok 且 无 Phase 4 且 Phase 5 非 ok → Phase 5

此启发式可能在 checkpoint 文件写入延迟时（后台 Checkpoint Agent 尚未提交）产生假阴性。在 Phase 4 完成和 Phase 5 checkpoint 创建之间的间隙，检查可能无法识别当前处于 Phase 5。

**影响**: 低。所有权检查是补充性守卫；主要隔离是 worktree 本身。

### 5.2 合并冲突检测

`parallel-merge-guard.sh`（及 `_post_task_validator.py:410-549` 中的重复实现）执行三项检查:
1. `git diff --check` 检查冲突标记
2. 范围验证（变更文件 vs 预期产物）
3. 类型检查执行

**发现 [H-03, 高危]**: 合并守卫触发依赖文本模式匹配
`parallel-merge-guard.sh:20` 使用 grep 检测合并相关输出:
```bash
echo "$STDIN_DATA" | grep -qi 'worktree.*merge\|merge.*worktree\|git merge.*autopilot-task'
```

如果子 Agent 输出文本不包含这些特定词汇（如使用"已集成变更"或中文文本），合并守卫将静默退出，不执行任何检查。

**影响**: 引入冲突的 worktree 合并可能因子 Agent 输出不匹配预期文本模式而未被检测到。

**建议**: 不依赖输出文本模式，改为直接检查 git 状态: 检测自上一个 checkpoint 以来是否存在合并提交，或使用 Hook 输入中的 `isolation: "worktree"` 元数据。

### 5.3 并行到串行的降级

降级条件记录在 `parallel-dispatch.md:300-307` 和 `phase5-implementation.md:244-252`:
- Worktree 创建失败 → 立即降级
- 合并冲突 > 3 文件 → 降级该组
- 连续 2 组失败 → 全面降级
- 用户选择 → 全面降级

**发现 [L-02, 低危]**: 降级逻辑由 AI 强制执行，非 Hook 强制
降级逻辑描述在 SKILL.md 规范中，依赖 AI 编排器正确实现。没有 L2 Hook 统计合并失败次数并强制降级。

**评估**: 对当前架构可接受。合并守卫 Hook 阻断单个错误合并；编排器决定是否继续或降级。

---

## 6. 崩溃恢复分析

### 6.1 恢复协议

`autopilot-recovery/SKILL.md` 定义恢复流程:
1. 扫描 checkpoint 目录
2. 选择目标变更（多个时用户选择）
3. 确定最后完成阶段
4. 用户决策: 恢复或重启
5. 从锁文件恢复模式
6. Anchor SHA 验证

### 6.2 SessionStart 集成

`scan-checkpoints-on-start.sh`（异步 SessionStart Hook）将 checkpoint 摘要输出到 Claude 上下文，提供恢复感知而不阻塞会话启动。

### 6.3 盲区

**发现 [H-04, 高危]**: Phase 1 完成前无中间 Checkpoint
Phase 1 执行多个子步骤（并行调研、业务分析、多轮用户问答）但仅在步骤 8 (SKILL.md:141) 写入 checkpoint。如果系统在 Phase 1 期间崩溃（涉及大量用户交互时间），所有进度丢失。

**影响**: Phase 1 可能耗时 10-30 分钟的交互讨论。在步骤 7（所有决策已做出但 checkpoint 未写入前）崩溃将要求用户重做所有讨论。

**建议**: 在 Phase 1 内写入中间 checkpoint（如调研完成后、每轮决策后）。

**发现 [M-05, 中危]**: Phase 0 在锁文件创建前崩溃
如果系统在 Phase 0 步骤 1 到步骤 9 之间崩溃，没有锁文件和 anchor commit。恢复将从头开始，这是可接受的。但如果在步骤 9（锁文件已创建）和步骤 10（anchor commit）之间崩溃，锁文件存在但 `anchor_sha` 为空。

**缓解**: 恢复步骤 6 (`autopilot-recovery/SKILL.md:93-99`) 处理了此情况: 空 `anchor_sha` → 创建新 anchor commit。实现正确。

**发现 [M-06, 中危]**: Phase 5 批次调度崩溃丢失重试队列
`autopilot-gate/SKILL.md:305-306` 声明: "非顺序恢复约束: 不跳过失败的任务。"但恢复协议 (`phase5-implementation.md:386-392`) 只查找"最后一个 ok 的任务"并从下一个恢复。如果任务 N 失败而任务 N+1 成功（由于批次调度并行执行），恢复将跳过任务 N。

**影响**: 在批次调度器 (v4.2) 中，一个批次内多个任务并行执行。如果任务 2 失败但任务 3 成功，两个 checkpoint 文件都存在。恢复扫描发现任务 3 为最后 ok 而跳过任务 2。

**缓解**: 批次调度器 (`phase5-implementation.md:470-483`) 将失败任务记录到重试队列。但崩溃后此内存队列丢失。磁盘上的 checkpoint 文件仅显示单个任务状态。

### 6.4 上下文压缩恢复

PreCompact + SessionStart(compact) Hook 对提供:
1. `save-state-before-compact.sh` → 写入 `autopilot-state.md`
2. `reinject-state-after-compact.sh` → 读取并输出状态到上下文

**发现 [L-03, 低危]**: 重注入不验证状态文件时效性
`reinject-state-after-compact.sh` 无论写入时间直接读取并输出状态文件。如果有多次压缩，第一次的状态文件被第二次覆盖，这是正确的。但如果状态文件过时（如使用 `--force` 手动压缩），会重新注入过期信息。

**评估**: 低风险。checkpoint JSON 文件是权威状态；状态文件是补充性上下文。

---

## 7. 反规避分析

### 7.1 反合理化检查

`_post_task_validator.py:316-378` 实现加权模式评分系统:
- 22 个模式（11 英文, 11 中文）权重 1-3
- 分数 ≥ 5 → 硬阻断
- 分数 ≥ 3 + 无产物 → 阻断
- 分数 ≥ 2 → 仅警告

**发现 [L-04, 低危]**: 反合理化可通过改写措辞规避
模式匹配特定短语如 "skipped this because", "out of scope", "deferred to"。AI Agent 可使用同义词或迂回表达:
- 不用 "skipped" → "proceeded without implementing"
- 不用 "out of scope" → "beyond current objectives"
- 不用 "deferred to" → "saved for iteration two"

**评估**: 这是基于模式检测的固有局限。使用多个低权重模式的评分系统提供了纵深防御。Agent 需要同时规避全部 22 个模式才能产生合理化输出，难度较高。

**补偿控制**: `artifacts` 检查（Phase 4/5/6 必须非空）更难规避——Agent 必须产生实际文件，而非仅文本。

### 7.2 禁用模式检查

`banned-patterns-check.sh:47` 扫描 `TODO:`, `FIXME:`, `HACK:`（不区分大小写，带冒号以减少误报）。

**发现 [L-05, 低危]**: 冒号要求允许规避
模式要求冒号: `TODO:`, `FIXME:`, `HACK:`。Agent 可以写:
- `TODO -` 或 `TODO --`
- `// TODO implement this later`
- `# FIXME needs refactoring`

**评估**: 低风险。冒号要求是降低误报的刻意权衡。反合理化检查为检测输出文本中的占位符模式提供了第二层防御。

### 7.3 断言质量检查

`assertion-quality-check.sh:43-66` 检测测试文件中的恒真断言，覆盖 JS/TS, Python, Java/Kotlin。

**覆盖评估**: 模式覆盖了最常见的恒真断言:
- `expect(true).toBe(true)`
- `assert True`
- `assertEquals(1, 1)`
- `assertTrue(true)`

**发现 [M-07, 中危]**: 恒真模式覆盖有限
检查遗漏了若干模式:
- `expect(1+1).toBe(2)`（计算型恒真）
- `assert len([]) == 0`（平凡真）
- `expect(undefined).toBeUndefined()`（无 setup）
- Rust, Go, Swift 或其他语言的断言

**评估**: 检查针对最严重的情况。扩展覆盖会增加误报。L3 代码审查 (Phase 6.5) 提供额外覆盖。

### 7.4 绕过向量汇总

| 绕过向量 | 可行性 | 检测层 | 风险 |
|---------|--------|--------|------|
| AI 完全跳过 L3 gate | 中（上下文压力下） | 无（后台 L2 被绕过） | 高 |
| Agent 返回假 `status: "ok"` | 低（L2 验证字段） | L2 字段验证 | 低 |
| Agent 创建空测试文件 | 低（L2 检查 artifacts + dry_run） | L2 Phase 4 dry_run 检查 | 低 |
| Agent 改写合理化措辞 | 中 | 评分系统部分检测 | 中 |
| 手动篡改锁文件 | 低（仅开发工具） | 无检测 | 低 |
| Agent 写 TODO 不带冒号 | 高 | banned-patterns 不检测 | 低 |

---

## 8. 风险矩阵

| ID | 发现 | 严重度 | 影响 | 组件 | 建议 |
|----|------|--------|------|------|------|
| C-01 | L1 仅覆盖基于 Task 的阶段 (2-6); Phase 1/7 缺少 L1 强制 | 致命 | 编排器故障时 Phase 1 理论上可被跳过 | 门禁系统 | 为 Skill 调用添加 PreToolUse Hook，或在 Phase 1 开始时添加 checkpoint 存在预检查 |
| C-02 | Checkpoint 写入非原子性；崩溃时可产生部分/损坏文件 | 致命 | 损坏的 checkpoint 阻断恢复；需要手动清理 | 文件完整性 | 所有 checkpoint 写入实现 write-to-temp + 原子 rename 模式 |
| H-01 | 所有后台 Agent 绕过 L2 PreToolUse | 高危 | 后台 Phase 2/3/4/6 派发无前驱验证 | 门禁系统 | 为后台 Agent 添加轻量级预检查（验证 checkpoint 文件存在，即使完整验证延迟执行） |
| H-02 | 所有后台 Agent 绕过 L2 PostToolUse | 高危 | 后台 Task 输出无信封验证、反合理化、约束检查 | 门禁系统 | 后台 Agent 完成时运行 PostToolUse 验证（延迟验证） |
| H-03 | 合并守卫触发依赖输出文本模式匹配 | 高危 | 输出文本不匹配的 worktree 合并绕过所有合并验证 | 并行安全 | 使用 git 状态检查（checkpoint 以来的合并提交）替代文本模式匹配 |
| H-04 | Phase 1 无中间 checkpoint；崩溃丢失所有进度 | 高危 | 10-30 分钟用户交互丢失 | 崩溃恢复 | 调研阶段完成后和每轮决策后写入中间 checkpoint |
| M-01 | 模式仅存于锁文件，checkpoint 中无交叉引用 | 中危 | 锁文件损坏可改变运行中的执行模式 | 状态机 | 在每个阶段 checkpoint 中包含 mode 用于交叉验证 |
| M-02 | L3 (8步 gate) 完全依赖 AI 自律 | 中危 | AI 在上下文压力下可能跳过 gate 步骤 | 门禁系统 | 添加确定性 post-gate 验证 Hook 检查 gate 输出格式 |
| M-03 | 压缩状态文件为信息性质，非机器可解析 | 中危 | AI 在压缩后可能误读恢复指令 | 文件完整性 | 在 Markdown 外额外使用结构化 JSON 状态文件 |
| M-04 | 所有权检查依赖阶段检测启发式，可能存在时序间隙 | 中危 | 所有权强制短暂失效窗口 | 并行安全 | 使用锁文件 phase 字段替代 checkpoint 启发式 |
| M-05 | Phase 0 在锁文件和 anchor commit 之间崩溃留下不一致状态 | 中危 | 恢复须处理空 anchor_sha | 崩溃恢复 | 已由恢复步骤 6 缓解；记录为已知行为 |
| M-06 | 批次调度崩溃丢失重试队列；并行任务恢复可能跳过失败任务 | 中危 | 批次中的失败任务可能在恢复时被跳过 | 崩溃恢复 | 派发前将批次元数据写入磁盘；显式标记失败任务 |
| M-07 | 恒真断言检查模式覆盖有限 | 中危 | AI 可以使用未覆盖模式写恒真测试 | 反规避 | 逐步扩展模式；考虑对常用语言使用 AST 分析 |
| L-01 | 锁文件 PID 竞态条件（检查与覆写之间） | 低危 | 理论上的并发会话冲突 | 文件完整性 | 对开发者工具可接受 |
| L-02 | 并行降级逻辑由 AI 强制执行，非 Hook 强制 | 低危 | AI 在满足条件时可能不执行降级 | 并行安全 | 可接受；合并守卫 Hook 阻断单个错误合并 |
| L-03 | 状态文件重注入不验证时效性 | 低危 | 异常压缩场景后的过时上下文 | 崩溃恢复 | 可接受；checkpoint 文件是权威来源 |
| L-04 | 反合理化模式可通过改写措辞规避 | 低危 | Agent 可能产生未被检测的合理化输出 | 反规避 | 固有局限；产物要求是更强的守卫 |
| L-05 | 禁用模式检查要求冒号后缀 | 低危 | 不带冒号的 `TODO` 规避检测 | 反规避 | 降低误报的刻意权衡 |

---

## 9. 综合稳定性评分

### 评分明细

| 类别 | 权重 | 得分 (0-100) | 加权 |
|------|------|-------------|------|
| 状态机正确性 | 25% | 90 | 22.5 |
| 门禁系统覆盖率 | 25% | 72 | 18.0 |
| 文件完整性 | 15% | 65 | 9.75 |
| 并行安全 | 15% | 75 | 11.25 |
| 崩溃恢复 | 10% | 70 | 7.0 |
| 反规避能力 | 10% | 78 | 7.8 |

### **综合稳定性评分: 76 / 100**

### 总体评估

该插件展现了强大的架构设计和纵深防御原则。三层门禁系统设计合理，确定性 L2 Hook 提供了坚实基础。主要弱点:

1. **后台 Agent 绕过** (H-01, H-02) 创造了系统性缺口——最常用的派发模式（后台 Task）获得的 L2 覆盖被削减。这是最具影响力的单一发现。

2. **Checkpoint 写入非原子性** (C-02) 在最关键的数据路径上创造了崩溃漏洞。虽然读回验证可在事后捕获损坏，但无法预防。

3. **Phase 1 缺少中间 checkpoint** (H-04) 使最重视用户交互的阶段面临崩溃时的完整数据丢失。

修复 2 个致命和 4 个高危发现，预计可将评分提升至约 88-90/100。

---

*审计报告结束。*
