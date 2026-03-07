---
name: autopilot-checkpoint
description: "[ONLY for autopilot orchestrator] Checkpoint read/write protocol for autopilot phases. Manages phase-results directory and JSON checkpoint files."
user-invocable: false
---

# Autopilot Checkpoint — 状态持久化协议

> **前置条件自检**：本 Skill 仅在 autopilot 编排主线程中使用。如果当前上下文不是 autopilot 编排流程，请立即停止并忽略本 Skill。

管理 `openspec/changes/<name>/context/phase-results/` 目录下的 checkpoint 文件。

> JSON 信封格式、阶段额外字段、Checkpoint 命名等详见：`autopilot/references/protocol.md`

## Checkpoint 文件命名

```
phase-results/
├── phase-1-requirements.json
├── phase-2-openspec.json
├── phase-3-ff.json
├── phase-4-testing.json
├── phase-5-implement.json
├── phase-6-report.json
└── phase-7-summary.json
```

## 写入 Checkpoint

阶段完成后，将子 Agent 返回的 JSON 信封写入对应文件：

1. 确保 `context/phase-results/` 目录存在（不存在则创建）
2. 将完整 JSON 信封写入 `phase-{N}-{slug}.json`
3. 验证写入成功：读回文件并解析 JSON

### JSON 格式

```json
{
  "status": "ok | warning | blocked | failed",
  "summary": "单行决策级摘要",
  "artifacts": ["文件路径列表"],
  "risks": ["风险列表"],
  "next_ready": true,
  "timestamp": "ISO-8601",
  "phase": 2,
  "_metrics": {
    "start_time": "ISO-8601",
    "end_time": "ISO-8601",
    "duration_seconds": 0,
    "retry_count": 0
  }
}
```

`_metrics` 字段为可选，由主线程在写入 checkpoint 时附加。详见 `autopilot/references/metrics-collection.md`。

写入时自动追加 `timestamp` 和 `phase` 字段。

## 读取 Checkpoint

验证前置阶段状态：

1. 构造路径：`phase-results/phase-{N}-*.json`
2. 读取并解析 JSON
3. 判定规则：
   - `status === "ok" || "warning"` → 校验通过
   - `status === "blocked" || "failed"` → 硬阻断
   - 文件不存在 → 硬阻断（阶段未完成）

## Task 级 Checkpoint（Phase 5 专用）

Phase 5 长时间实施中，每个 task 完成后写入独立 checkpoint，支持细粒度恢复。

### 目录结构

```
phase-results/phase5-tasks/
├── task-1.json
├── task-2.json
└── ...
```

### 写入 Task Checkpoint

1. 确保 `context/phase-results/phase5-tasks/` 目录存在
2. 写入 `task-{N}.json`（格式同主 checkpoint，额外含 `task_number` 和 `task_title`）
3. 验证写入成功

### 扫描 Task Checkpoint

恢复 Phase 5 时：
1. 列出 `phase5-tasks/task-*.json` 文件
2. 按 task number 排序
3. 找到**第一个** `status` 不是 `"ok"` 的 task（blocked/failed/warning）
   - 如果存在 → Phase 5 从该 task 重新开始（修复后继续）
   - 如果不存在（全部 ok） → Phase 5 所有 task 已完成
4. 如果没有 task checkpoint 文件 → 从 task 1 开始

> **非连续恢复约束**：不跳过失败的 task。即使后续 task 有 ok 状态（并行模式残留），仍从第一个非 ok task 重新开始，确保实现完整性。

## 扫描所有 Checkpoint

用于崩溃恢复，按阶段顺序扫描：

```
phase-1 → phase-2 → phase-3 → phase-4 → phase-5 → phase-6 → phase-7
```

找到最后一个 `status: "ok"` 或 `"warning"` 的文件 → 返回该阶段编号。
