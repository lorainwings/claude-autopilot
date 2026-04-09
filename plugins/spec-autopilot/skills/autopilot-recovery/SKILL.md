---
name: autopilot-recovery
description: "[ONLY for autopilot orchestrator] Crash recovery protocol for autopilot. Scans existing checkpoints and determines resume point."
user-invocable: false
---

# Autopilot Recovery — 崩溃恢复协议（v6.0）

> **前置条件自检**：本 Skill 仅在 autopilot 编排主线程中使用。如果当前上下文不是 autopilot 编排流程，请立即停止并忽略本 Skill。

在 autopilot 启动时（Phase 0.4）扫描已有 checkpoint，决定起始阶段。

### 核心变更（v6.0）

1. `state-snapshot.json` 成为恢复控制面的唯一主工件
2. 恢复前校验 `snapshot_hash` 一致性，hash 不匹配时 fail-closed（拒绝自动继续）
3. 恢复输出包含：`resume_from_phase`、`discarded_artifacts`、`replay_required_tasks`、`recovery_reason`、`recovery_confidence`
4. 不再依赖 Markdown 摘要作为主恢复路径（仅作人类可读 fallback）

### 脚本依赖

| 脚本 | 用途 |
|------|------|
| `scripts/recovery-decision.sh` | 确定性恢复扫描（纯只读，JSON 输出，含 state-snapshot.json 校验） |
| `scripts/clean-phase-artifacts.sh` | 统一清理阶段制品 + 事件过滤 + git 状态回退 + state-snapshot.json 清理 |

### 共享基础设施依赖

本 Skill 通过 `recovery-decision.sh` 间接使用 `scripts/_common.sh` 提供的以下共享函数：

| 函数 | 用途 |
|------|------|
| `scan_all_checkpoints(phase_results_dir, mode)` | 按阶段顺序扫描全部 checkpoint，返回 JSON 结果 |
| `get_last_valid_phase(phase_results_dir, mode)` | 返回最后一个 status=ok/warning 的阶段编号（含 gap 检测） |
| `get_gap_phases(phase_results_dir, mode)` | 返回 gap 阶段列表（v5.6 新增） |
| `get_phase_sequence(mode)` | 返回模式对应的阶段序列 |
| `get_next_phase_in_sequence(current, mode)` | 返回序列中下一阶段编号 |
| `read_phase_commit_sha(project_root, phase, change_name)` | 从 git 历史查找阶段 commit SHA（三级 fallback） |
| `read_lock_json_field(lock_file, field, default)` | 提取锁文件 JSON 字段（mode、anchor_sha 等） |

## 恢复流程

### Step 1: 调用确定性扫描

执行 `recovery-decision.sh`，获取完整的恢复决策数据：

```bash
Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/recovery-decision.sh "${session_cwd}/openspec/changes" "${mode}" --change "${change_name_if_known}"')
```

解析 JSON 输出，后续**所有决策基于此数据**，不再执行任何内联 bash 扫描命令。

JSON 输出包含：
- `has_checkpoints`: 是否存在 checkpoint
- `changes[]`: 每个 change 的完整扫描结果（last_valid_phase、gap 检测、interim、progress、state_snapshot）
- `selected_change`: 预选的 change 名称（可能为 null）
- `recommended_recovery_phase`: 推荐恢复起始阶段
- `recovery_options`: 三种恢复路径选项
- `git_state`: git rebase/merge/worktree 状态
- `lock_file`: 锁文件状态
- `has_fixup_commits`: 当前分支是否存在未 squash 的 autopilot fixup 提交
- `fixup_commit_count`: fixup 提交数量
- `recovery_interaction_required`: 是否需要用户交互
- `auto_continue_eligible`: 是否满足自动继续条件
- `git_risk_level`: "none" | "low" | "medium" | "high" — git 风险级别
- `resume_from_phase`: 恢复起始阶段（v6.0）
- `discarded_artifacts`: 需要丢弃的制品列表（v6.0）
- `replay_required_tasks`: 需要重跑的任务列表（v6.0）
- `recovery_reason`: 恢复原因（v6.0: state_snapshot_resume | checkpoint_resume | progress_resume | snapshot_hash_mismatch | fresh_start | all_complete）
- `recovery_confidence`: 恢复置信度（v6.0: high | medium | low）

### Step 1.5: 自动继续判定

当 `auto_continue_eligible == true` 且配置 `recovery.auto_continue_single_candidate` 允许时：
- **自动执行继续恢复**，不弹 AskUserQuestion，直接进入路径 A
- 输出日志：`Auto-continuing recovery: Phase {continue.phase} ({continue.label})`

**v6.0 Fail-closed 规则**：当 `recovery_confidence == "low"` 时：
- 强制 `auto_continue_eligible = false`，不允许自动继续
- `recovery_interaction_required = true`
- 提示用户：`state-snapshot.json hash 校验失败，恢复置信度为 LOW，需要人工确认`

当 `has_fixup_commits == true` 时：
- 在日志中记录 fixup 状态：`Fixup commits detected: {fixup_commit_count} pending squash`
- fixup 提交不影响恢复流程本身，**仅在 Phase 7 归档时**通过 `git rebase --autosquash` 自动合并
- 恢复阶段**不执行** squash（无论 git 状态如何）

当 `git_risk_level == "high"` 时：
- 强制 `recovery_interaction_required = true`，不允许自动继续
- 提示用户存在危险 git 状态（rebase/merge 冲突）

### Step 2: 多 Change 选择（如需）

若 `selected_change == null` 且 `changes.length > 1`：

```
AskUserQuestion:
"检测到多个活跃 change，请选择要恢复的："
选项:（按 total_checkpoints 降序排列）
- "{name}（Phase {last_valid_phase} 已完成：{last_valid_label}）(Recommended)"
- "{name}（Phase {last_valid_phase} 已完成）"
- "从头开始新 change"
```

若 `selected_change` 已确定（--change 指定或仅一个 change）→ 跳过此步骤。

### Step 3: 用户决策

基于扫描结果中的 `has_checkpoints`：

**无 checkpoint**（`has_checkpoints == false`）→ `recovery_phase = 1`，直接开始。

**Phase 7 已完成**（`phase7_status == "ok"`）→ 提示用户 change 已完全完成（含归档），可清理 change 目录或开始新 change。

**Phase 7 进行中**（`phase7_status == "in_progress"`）→ 归档未完成，提示用户手动执行 `/opsx:archive` 完成归档。

**有 checkpoint（Phase 1-6）**→

{if recovery_confidence == "low"}
> WARNING: state-snapshot.json hash 校验失败。结构化恢复不可用，将使用 checkpoint 扫描恢复。
> 恢复置信度: LOW — 建议人工检查 checkpoint 一致性后再继续。
{end if}

{if has_fixup_commits == true}
> 检测到 {fixup_commit_count} 个 fixup 提交 — 这是 autopilot 运行时产生的中间 checkpoint 提交，
> 将在 Phase 7 归档时通过 `git rebase --autosquash` 自动合并，**无需手动处理**。
{end if}

使用 `recovery_options` 展示三选项：

```
AskUserQuestion:
"检测到 change '{selected_change}' 的阶段 {last_valid_phase} 已完成（{last_valid_label}）。请选择恢复方式："
选项：
- "从断点继续（Phase {recovery_options.continue.phase}: {recovery_options.continue.label}）(Recommended)"
- "从指定阶段恢复"
- "从头开始（清空所有历史）"
```

**选择「从指定阶段恢复」时** → 追加第二轮 AskUserQuestion：

```
"请选择要恢复到的阶段（该阶段之后的所有制品将被清理）："
选项:（仅展示 recovery_options.specify_range 中的阶段）
- "Phase 1: Requirements"
- "Phase 2: OpenSpec"
- ...
```

**Gap 检测警告**：当 `has_gaps == true` 时，在展示恢复选项前输出警告：
```
WARNING: 检测到 checkpoint 断裂（gap phases: {gap_phases}）。建议从断点继续或从头开始。
```

### Step 4: 执行恢复路径

#### 路径 A：从断点继续

- `recovery_phase = recovery_options.continue.phase`
- 编排主线程在 TaskCreate 时将已完成阶段标记为 completed
- 不清理任何制品
- **v6.0 state-snapshot.json 验证**: 当 `recovery_reason == "state_snapshot_resume"` 时：
  1. 输出：`Structured recovery from state-snapshot.json (hash verified)`
  2. 使用 `gate_frontier`、`next_action`、`requirement_packet_hash` 作为恢复控制态
  3. 不再依赖 Markdown 摘要
- **v5.8 worktree 恢复一致性检查**: 当 `recovery_phase == 5` 且 `git_state.uncommitted_changes == true` 时：
  1. 输出警告：`[WARNING] 工作区存在未提交的变更，可能因 Phase 5 崩溃导致部分合并`
  2. 执行 `git diff --stat` 展示变更文件列表
  3. AskUserQuestion：
     - "保留当前变更，继续 Phase 5"
     - "丢弃未提交变更，从最后成功的 task checkpoint 重新开始"
- **v5.8 worktree 残留清理**: 当 `git_state.worktree_residuals` 非空时：
  1. 展示残留 worktree 列表
  2. 自动清理：`git worktree remove --force <path>` 逐个删除

#### 路径 B：从指定阶段恢复

- 用户选择的目标阶段为 `target_phase`
- `recovery_phase = target_phase`
- **Git SHA 查找**：
  ```bash
  TARGET_SHA=$(bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/_common.sh && read_phase_commit_sha "${session_cwd}" ${target_phase} "${change_name}")
  ```
  - **找到 SHA** → 传递给 clean-phase-artifacts.sh 的 `--git-target-sha` 参数
  - **未找到 SHA**（旧版 commit 无标记） → 跳过 git 回退，仅清理文件制品，输出警告
- **调用清理脚本**：
  ```bash
  Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/clean-phase-artifacts.sh ${target_phase} ${mode} "${change_dir}" --git-target-sha ${TARGET_SHA}')
  ```
  清理脚本自动处理：git 回退 → 文件清理 → 事件过滤 → state-snapshot.json 清理（事务性顺序）
- 解析清理脚本的 JSON 输出，向用户展示清理摘要

#### 路径 C：从头开始

- `recovery_phase = 1`
- **调用清理脚本**：
  ```bash
  Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/clean-phase-artifacts.sh 1 ${mode} "${change_dir}"')
  ```
  不传 `--git-target-sha`（不回退 git 状态，仅清理文件 + state-snapshot.json）
- 返回起始阶段号 1

### Step 5: 上下文重建 + Anchor SHA 验证

#### 上下文重建协议

恢复时优先使用 **state-snapshot.json** 中的结构化数据：

```bash
cat openspec/changes/<name>/context/state-snapshot.json 2>/dev/null
```

若 state-snapshot.json 可用且 hash 校验通过：
1. 从 `phase_results` 字段获取各阶段状态
2. 从 `next_action` 字段获取恢复起点
3. 从 `requirement_packet_hash` 验证需求一致性
4. 从 `gate_frontier` 确认门禁边界

若 state-snapshot.json 不可用或 hash 不匹配，fallback 到 phase context snapshots：

```bash
ls openspec/changes/<name>/context/phase-context-snapshots/phase-*-context.json 2>/dev/null
```

对每个存在的 `phase-{P}-context.json`（其中 P < recovery_phase）：
1. 读取 JSON 内容（优先）或 markdown 文件
2. 提取 summary、decisions、next_phase_context
3. 拼接为恢复上下文摘要，注入主线程

恢复时输出格式：
```
=== Phase Context Recovery ===
Phase 1: [摘要...]
Phase 2: [摘要...]
...
=== End Context Recovery ===
```

> **路径 B 注意**: 仅注入 target_phase 之前的上下文快照，不注入被清理阶段的上下文。

#### Anchor SHA 验证

从 `recovery-decision.sh` 输出的 `anchor_needs_rebuild` 和 `anchor_sha` 字段（由 Step 1 JSON 提供）：

1. **`anchor_needs_rebuild` 为 `true`**（有 fixup commits 但无有效 anchor）→ 强制调用确定性脚本重建：
   ```
   Bash('AUTOPILOT_PROJECT_ROOT=$(pwd) bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/rebuild-anchor.sh $(pwd) ${LOCK_FILE}')
   ```
   - 退出码 0 → 使用 stdout 输出的新 anchor SHA，输出 `Anchor SHA rebuilt: ${new_sha}`
   - 退出码非 0 → **报错终止恢复流程**，不静默继续
2. **`anchor_sha` 为空字符串且 `anchor_needs_rebuild` 为 `false`** → 调用同一脚本创建新锚定：
   ```
   Bash('AUTOPILOT_PROJECT_ROOT=$(pwd) bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/rebuild-anchor.sh $(pwd) ${LOCK_FILE}')
   ```
   退出码非 0 → 报错终止
3. **`anchor_sha` 非空但 `git rev-parse ${anchor_sha}^{commit}` 失败** → 同上，调用 `rebuild-anchor.sh` 重建
4. **有效** → 继续使用现有 anchor_sha，输出 `Anchor SHA verified: ${anchor_sha}`

### 5. Mode 恢复

从 `effective_mode` 字段（由 Step 1 JSON 提供）获取实际扫描使用的模式。`recovery-decision.sh` 自动解析锁文件 `${session_cwd}/openspec/changes/.autopilot-active` 中的 mode 并优先使用：

- **锁文件 mode 非空** → 使用锁文件中的 mode（确保与上次会话一致）
- **锁文件 mode 为空或不存在** → 使用 CLI 传入的 mode
- **CLI 也未指定** → 默认 "full"

恢复后的 mode 传递给主线程，用于 Task 系统重建时的阶段选择。

> **v5.6.1 变更**: 之前 mode 仅从 CLI 入参获取，可能与锁文件中记录的 mode 不一致。现在 `recovery-decision.sh` 自动以锁文件 mode 为准。

## Task 系统重建

崩溃恢复时需创建对应模式的阶段任务链，已完成的阶段直接标记为 `completed`，确保 blockedBy 依赖链正确。

> **Fixup Squash 时机**: fixup 提交不在恢复阶段处理。Phase 7 归档时会自动执行 `git rebase --autosquash` 将所有 fixup! 提交合并到对应的目标 commit 中。

| 模式 | 创建的任务 |
|------|-----------|
| full | Phase 1-7（7 个任务） |
| lite | Phase 1, 5, 6, 7（4 个任务） |
| minimal | Phase 1, 5, 7（3 个任务） |

## TDD 恢复逻辑

当 `config.phases.implementation.tdd_mode: true` 时，Phase 5 恢复需额外检查 per-task TDD 状态：

### TDD 恢复协议

1. 扫描 `phase5-tasks/task-N.json` 的 `tdd_cycle` 字段
2. 确定每个 task 的 TDD 阶段：

| tdd_cycle 状态 | 恢复点 |
|----------------|--------|
| 无 tdd_cycle | 从 RED 开始 |
| `red.verified = true`，无 `green` | 从 GREEN 恢复（测试文件已写好） |
| `green.verified = true`，无 `refactor` | 从 REFACTOR 恢复（当 `tdd_refactor: true`） |
| tdd_cycle 完整 | 下一个 task |

3. 恢复时：
   - 验证测试文件存在（GREEN/REFACTOR 恢复时）
   - 验证测试当前状态（运行测试命令确认）
   - 从正确的 TDD step 继续

## SessionStart Hook 集成

`scan-checkpoints-on-start.sh` Hook 在会话启动时自动扫描 checkpoint 目录和 state-snapshot.json，输出摘要信息。本 Skill 在此基础上提供交互式恢复决策。

> **state-snapshot.json Schema 及消费方契约**: 详见 `autopilot/references/state-snapshot-schema.md`
