---
name: autopilot-recovery
description: "[ONLY for autopilot orchestrator] Crash recovery protocol for autopilot. Scans existing checkpoints and determines resume point."
user-invocable: false
---

# Autopilot Recovery — 崩溃恢复协议

> **前置条件自检**：本 Skill 仅在 autopilot 编排主线程中使用。如果当前上下文不是 autopilot 编排流程，请立即停止并忽略本 Skill。

在 autopilot 启动时（Phase 0.4）扫描已有 checkpoint，决定起始阶段。

## 恢复流程

### 1. 扫描 Checkpoint

扫描 `openspec/changes/` 目录，找到所有含 checkpoint 的 change：

```bash
ls openspec/changes/*/context/phase-results/*.json 2>/dev/null
```

### 2. 选择目标 Change

**仅一个 change** → 自动选中。

**多个 change 有 checkpoint** → 通过 AskUserQuestion 让用户明确选择：
```
"检测到多个活跃 change，请选择要恢复的："
选项:（按最近修改时间排序，最新在前）
- "feature-a（Phase 4 已完成）(Recommended)"
- "feature-b（Phase 2 已完成）"
- "从头开始新 change"
```

**`$ARGUMENTS` 包含 change 名称** → 直接匹配该 change，跳过选择。

### 2. 确定最后完成阶段

按顺序检查 checkpoint 文件：

| 文件 | 含义 |
|------|------|
| phase-1-requirements.json | Phase 1 完成（需求已确认） |
| phase-2-openspec.json | Phase 2 完成（仅 full 模式） |
| phase-3-ff.json | Phase 3 完成（仅 full 模式） |
| phase-4-testing.json | Phase 4 完成（仅 full 模式） |
| phase-5-implement.json | Phase 5 完成 |
| phase-6-report.json | Phase 6 完成（仅 full/lite 模式） |
| phase-7-summary.json | Phase 7 完成（归档完毕） |

对每个文件：读取 JSON → 验证 `status` 为 `ok` 或 `warning`。

找到最后一个有效 checkpoint → 记录阶段号 N。

### 3. 用户决策

**无 checkpoint**：从 Phase 1 正常开始。

**有 checkpoint（Phase 1-6）**：展示恢复信息，通过 AskUserQuestion 询问：

```
"检测到 change '{name}' 的阶段 {N} 已完成。是否从阶段 {N+1} 继续？"
选项：
- "从断点继续 (Recommended)"
- "从头开始（清空历史）"
```

**Phase 7 checkpoint 存在**：

- `status === "in_progress"` → 归档未完成，提示用户手动执行 `/opsx:archive` 完成归档
- `status === "ok"` → change 已完全完成（含归档），提示用户可清理 change 目录或开始新 change

### 4. 执行恢复

**从断点继续**：
- 返回起始阶段号 N+1
- 编排主线程在 TaskCreate 时将已完成阶段标记为 completed

**从头开始**：
- 删除 `phase-results/` 目录
- 返回起始阶段号 1

### 5. Mode 恢复

从锁文件 `${session_cwd}/openspec/changes/.autopilot-active` 读取 `mode` 字段（full/lite/minimal）。注意使用绝对路径。

- **mode 字段存在** → 使用锁文件中的 mode
- **mode 字段不存在**（旧版兼容） → 默认 "full"

恢复后的 mode 传递给主线程，用于 Task 系统重建时的阶段选择。

### Step 6: Anchor SHA 验证

从锁文件读取 `anchor_sha` 字段：

1. **空字符串** → 创建新锚定 commit：`Bash("git commit --allow-empty -m 'autopilot: anchor (recovery)'")`，将新 SHA 写回锁文件的 `anchor_sha` 字段
2. **非空但 `git rev-parse ${anchor_sha}^{commit}` 失败** → 同上，创建新锚定 commit 并更新锁文件
3. **有效** → 继续使用现有 anchor_sha，输出 `Anchor SHA verified: ${anchor_sha}`

## Task 系统重建

崩溃恢复时需创建对应模式的阶段任务链，已完成的阶段直接标记为 `completed`，确保 blockedBy 依赖链正确。

| 模式 | 创建的任务 |
|------|-----------|
| full | Phase 1-7（7 个任务） |
| lite | Phase 1, 5, 6, 7（4 个任务） |
| minimal | Phase 1, 5, 7（3 个任务） |

## SessionStart Hook 集成

`scan-checkpoints-on-start.sh` Hook 在会话启动时自动扫描 checkpoint 目录，输出摘要信息。本 Skill 在此基础上提供交互式恢复决策。

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
