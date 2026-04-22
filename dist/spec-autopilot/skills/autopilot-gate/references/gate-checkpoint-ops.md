# Gate Checkpoint 管理操作

> 本文件从 `autopilot-gate/SKILL.md` 提取，供 checkpoint 读写时按需读取。
> JSON 信封格式、阶段额外字段等详见：autopilot skill 的 `protocol.md` 章节

## Contents

- [Checkpoint 文件命名](#checkpoint-文件命名)
- [写入 Checkpoint](#写入-checkpoint)
  - [JSON 格式](#json-格式)
  - [写入确认输出](#写入确认输出)
- [读取 Checkpoint](#读取-checkpoint)
- [Task 级 Checkpoint（Phase 5 专用）](#task-级-checkpointphase-5-专用)
- [扫描所有 Checkpoint](#扫描所有-checkpoint)

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
2. **原子性写入**: 将完整 JSON 信封写入临时文件 `phase-{N}-{slug}.json.tmp`
3. 验证临时文件 JSON 格式合法（读回并解析）
4. 执行原子重命名：`mv phase-{N}-{slug}.json.tmp phase-{N}-{slug}.json`
5. 验证最终文件存在且可解析

**写入流程**（所有 checkpoint 写入必须遵循此原子模式）：

```bash
# Step 1: Write to temp file
Write JSON → phase-{N}-{slug}.json.tmp

# Step 2: Validate temp file
python3 -c "import json; json.load(open('phase-{N}-{slug}.json.tmp'))"
# If validation fails → delete .tmp, report error, do NOT overwrite existing checkpoint

# Step 3: Atomic rename
mv phase-{N}-{slug}.json.tmp phase-{N}-{slug}.json

# Step 4: Final verification
Read phase-{N}-{slug}.json → parse JSON → confirm status field exists
```

**断电/崩溃安全**：

- 写入 `.tmp` 时崩溃 → 正式文件不受影响，恢复时忽略 `.tmp` 文件
- `mv` 是文件系统原子操作 → 不会产生半写的 checkpoint
- 恢复时：扫描并删除所有 `.tmp` 残留文件

### JSON 格式

> 完整的 JSON 信封格式定义详见 autopilot skill 的 `protocol.md` 章节。

核心字段：`status`（ok/warning/blocked/failed）、`summary`、`artifacts`、`risks`、`next_ready`。
`_metrics` 和 `timestamp` 由主线程写入时附加。

### 写入确认输出

Checkpoint 写入成功后，**必须**输出以下格式化日志（遵循 autopilot skill 的 `log-format.md` 章节）：

```
[CP] phase-{N}-{slug}.json | commit: {short_sha}
```

写入失败时输出：

```
[ERROR] Checkpoint write failed: phase-{N}-{slug}.json — {reason}
```

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

```
phase-results/phase5-tasks/
├── task-1.json
├── task-2.json
└── ...
```

- 确保 `context/phase-results/phase5-tasks/` 目录存在
- 写入 `task-{N}.json`（格式同主 checkpoint，额外含 `task_number` 和 `task_title`）
- 恢复 Phase 5 时：扫描 `phase5-tasks/task-*.json`，找到第一个非 `"ok"` 的 task 重新开始
- **非连续恢复约束**：不跳过失败的 task

## 扫描所有 Checkpoint

用于崩溃恢复，调用 `scan_all_checkpoints(phase_results_dir, mode)` 按阶段顺序扫描 phase-1 → phase-7。调用 `get_last_valid_phase(phase_results_dir, mode)` 返回最后一个 `status: "ok"` 或 `"warning"` 的阶段编号。
