---
name: autopilot-checkpoint
description: "Checkpoint read/write protocol for autopilot phases. Manages phase-results directory and JSON checkpoint files."
---

# Autopilot Checkpoint — 状态持久化协议

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
  "artifacts": ["文件路径列表"],
  "risks": ["风险列表"],
  "next_ready": true,
  "timestamp": "ISO-8601",
  "phase": 2
}
```

写入时自动追加 `timestamp` 和 `phase` 字段。

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
