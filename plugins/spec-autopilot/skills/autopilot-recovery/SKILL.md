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
| phase-2-openspec.json | Phase 2 完成 |
| phase-3-ff.json | Phase 3 完成 |
| phase-4-testing.json | Phase 4 完成 |
| phase-5-implement.json | Phase 5 完成 |
| phase-6-report.json | Phase 6 完成 |

对每个文件：读取 JSON → 验证 `status` 为 `ok` 或 `warning`。

找到最后一个有效 checkpoint → 记录阶段号 N。

### 3. 用户决策

**无 checkpoint**：从 Phase 1 正常开始。

**有 checkpoint**：展示恢复信息，通过 AskUserQuestion 询问：

```
"检测到 change '{name}' 的阶段 {N} 已完成。是否从阶段 {N+1} 继续？"
选项：
- "从断点继续 (Recommended)"
- "从头开始（清空历史）"
```

### 4. 执行恢复

**从断点继续**：
- 返回起始阶段号 N+1
- 编排主线程在 TaskCreate 时将已完成阶段标记为 completed

**从头开始**：
- 删除 `phase-results/` 目录
- 返回起始阶段号 1

## Task 系统重建

崩溃恢复时仍需创建完整的 8 个阶段任务链（TaskCreate × 8），但已完成的阶段直接标记为 `completed`，确保 blockedBy 依赖链正确。

## SessionStart Hook 集成

`scan-checkpoints-on-start.sh` Hook 在会话启动时自动扫描 checkpoint 目录，输出摘要信息。本 Skill 在此基础上提供交互式恢复决策。
