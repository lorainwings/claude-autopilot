---
name: autopilot-recovery
description: "Use when the autopilot orchestrator restarts after a crash or interruption and must scan existing checkpoints, detect partial state, and determine the safe resume point. Not for direct user invocation; skip outside the orchestrator main thread."
user-invocable: false
---

# Autopilot Recovery — 崩溃恢复协议

> **前置条件自检**：本 Skill 仅在 autopilot 编排主线程中使用。如果当前上下文不是 autopilot 编排流程，请立即停止并忽略本 Skill。

在 autopilot 启动时（Phase 0.4）扫描已有 checkpoint，决定起始阶段。

### 核心变更

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
| `get_gap_phases(phase_results_dir, mode)` | 返回 gap 阶段列表 |
| `get_phase_sequence(mode)` | 返回模式对应的阶段序列 |
| `get_next_phase_in_sequence(current, mode)` | 返回序列中下一阶段编号 |
| `read_phase_commit_sha(project_root, phase, change_name)` | 从 git 历史查找阶段 commit SHA（三级 fallback） |
| `read_lock_json_field(lock_file, field, default)` | 提取锁文件 JSON 字段（mode、anchor_sha 等） |

## 恢复流程概览

| Step | 职责 | 详细协议 |
|------|------|----------|
| 1 | 调用确定性扫描 | `references/recovery-flow.md#step-1` |
| 1.5 | 自动继续判定 | `references/recovery-flow.md#step-15` |
| 2 | 多 Change 选择 | `references/recovery-flow.md#step-2` |
| 3 | 用户决策 | `references/recovery-flow.md#step-3` |
| 4 | 执行恢复路径（路径 A/B/C） | `references/recovery-flow.md#step-4` |
| 5 | 上下文重建 + Anchor SHA 验证 | `references/recovery-flow.md#step-5` |
| 5.Mode | Mode 恢复 | `references/recovery-flow.md#mode-恢复` |

**执行前必须读取 `references/recovery-flow.md` 获取完整协议。** 所有 Step、决策分支、JSON schema 字段、脚本调用、AskUserQuestion 文案、Anchor SHA 验证四分支等均以该文件为准。

## Task 系统重建

崩溃恢复时需创建对应模式的阶段任务链，已完成的阶段直接标记为 `completed`，确保 blockedBy 依赖链正确。

> **Fixup Squash 时机**: fixup 提交不在恢复阶段处理。Phase 7 归档时会自动执行 `git rebase --autosquash` 将所有 fixup! 提交合并到对应的目标 commit 中。

| 模式 | 创建的任务 |
|------|-----------|
| full | Phase 1-7（7 个任务） |
| lite | Phase 1, 5, 6, 7（4 个任务） |
| minimal | Phase 1, 5, 7（3 个任务） |

## TDD 恢复逻辑

当 `config.phases.implementation.tdd_mode: true` 时，Phase 5 恢复需扫描 `phase5-tasks/task-N.json` 的 `tdd_cycle` 字段，按状态映射到 RED/GREEN/REFACTOR 恢复点。完整协议（含状态映射表与恢复时验证步骤）详见 `references/tdd-recovery.md`。

## SessionStart Hook 集成

`scan-checkpoints-on-start.sh` Hook 在会话启动时自动扫描 checkpoint 目录和 state-snapshot.json，输出摘要信息。本 Skill 在此基础上提供交互式恢复决策。

> **state-snapshot.json Schema 及消费方契约**: 详见 `references/state-snapshot-schema.md`
