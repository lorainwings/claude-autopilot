---
name: autopilot-checkpoint
description: "[ONLY for autopilot orchestrator] Checkpoint read/write protocol for autopilot phases. Manages phase-results directory and JSON checkpoint files."
---

# Autopilot Checkpoint — 状态持久化协议

> **前置条件自检**：本 Skill 仅在 autopilot 编排主线程中使用。如果当前上下文不是 autopilot 编排流程，请立即停止并忽略本 Skill。

管理 `openspec/changes/<name>/context/phase-results/` 目录下的 checkpoint 文件。

## Checkpoint 文件命名

```
phase-results/
├── phase-2-openspec.json
├── phase-3-ff.json
├── phase-4-testing.json
├── phase-5-implement.json
└── phase-6-report.json
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
  "context_summary": "3-5 行核心决策与产出摘要，供契约链注入",
  "artifacts": ["文件路径列表"],
  "risks": ["风险列表"],
  "next_ready": true,
  "model_used": "opus | sonnet | haiku",
  "timestamp": "ISO-8601",
  "phase": 2
}
```

写入时自动追加 `timestamp`、`phase` 和 `model_used` 字段。

### context_summary 字段规范

- 由子 Agent 返回，3-5 行结构化摘要，包含核心决策与关键产出
- 子 Agent 未返回 `context_summary` 时，主线程从 `summary` + `artifacts` 自动生成（格式：`"[auto] {summary}. Artifacts: {artifacts[0..2]}"`）
- `model_used` 由主线程写入 checkpoint 时根据 dispatch 使用的模型自动追加

## 读取 Checkpoint

验证前置阶段状态：

1. 构造路径：`phase-results/phase-{N}-*.json`
2. 读取并解析 JSON
3. 判定规则：
   - `status === "ok" || "warning"` → 校验通过
   - `status === "blocked" || "failed"` → 硬阻断
   - 文件不存在 → 硬阻断（阶段未完成）

## 扫描所有 Checkpoint

用于崩溃恢复，按阶段顺序扫描：

```
phase-2 → phase-3 → phase-4 → phase-5 → phase-6
```

找到最后一个 `status: "ok"` 或 `"warning"` 的文件 → 返回该阶段编号。

## 并行结果合并

当一个阶段由多个并行子 Agent 执行时，主线程负责合并：

1. 收集所有子 Agent 的 JSON 信封
2. 合并规则:
   - `status`: 全部 ok → ok; 任一 blocked/failed → 整体 blocked/failed; 含 warning 无 blocked/failed → warning
   - `artifacts`: 连接所有子 Agent 的 artifacts 列表
   - `risks`: 连接所有 risks 列表（去重）
   - `context_summary`: 汇总各子 Agent 的摘要（按 sub 类型分行）
   - 阶段特殊字段: 按字段语义合并（如 `test_counts` 各字段取自对应子 Agent）
3. 合并后的统一信封写入 checkpoint
4. `model_used` 取子 Agent 中使用的最高级模型（opus > sonnet > haiku）
