# L1 Episode Schema

> L1 Episode 记录单次 Phase 执行轨迹，是所有上层聚类与晋升的原始数据。

## 字段定义

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `version` | string | ✅ | schema 版本，当前固定 `"1.0"` |
| `run_id` | string | ✅ | 单次 autopilot 运行的唯一 ID（通常复用 lockfile 中的 anchor_sha 或 UUID） |
| `phase` | string | ✅ | Phase 编号，如 `"phase5"` |
| `phase_name` | string | ✅ | Phase 名称，如 `"implement"` |
| `mode` | string | ✅ | `"parallel" \| "serial" \| "tdd"` |
| `goal` | string | ✅ | 该 Phase 目标摘要（从 phase-results.summary 或 requirement_packet 派生） |
| `timestamp_start` | string | ✅ | ISO-8601 起始时间 |
| `timestamp_end` | string | ✅ | ISO-8601 结束时间 |
| `duration_ms` | integer | ✅ | 执行耗时（毫秒） |
| `gate_result` | string | ✅ | `"ok" \| "warning" \| "blocked" \| "failed"` |
| `actions` | array<object> | ✅ | 关键动作序列：`[{tool, target, outcome}]`（可为空数组） |
| `failure_trace` | object | ❌ | 当 `gate_result ∈ {blocked, failed}` 时必填，结构 `{root_cause, failed_gate, evidence}` |
| `reflection` | string | ❌ | Reflexion 风格自然语言反思（失败时强制生成） |
| `success_fingerprint` | string | ❌ | 当 `gate_result == "ok"` 时可选，结构化成功指纹用于抵消失败模式 |

## 失败时必须生成 reflection

格式参考 Reflexion 论文：

```
Observation: {gate 输出的关键错误}
Reasoning: {AI 对失败根因的自我归因}
Plan: {下次遇到相同模式时的可复用策略}
```

## 示例

```json
{
  "version": "1.0",
  "run_id": "anchor-abc123",
  "phase": "phase5",
  "phase_name": "implement",
  "mode": "parallel",
  "goal": "实现并行派发调度器",
  "timestamp_start": "2026-04-18T10:00:00Z",
  "timestamp_end": "2026-04-18T10:12:30Z",
  "duration_ms": 750000,
  "gate_result": "blocked",
  "actions": [
    {"tool": "Task", "target": "implementer-a", "outcome": "ok"},
    {"tool": "Task", "target": "implementer-b", "outcome": "merge_conflict"}
  ],
  "failure_trace": {
    "root_cause": "file_ownership_overlap",
    "failed_gate": "parallel-merge-guard",
    "evidence": "2 agents wrote to same path src/dispatcher.ts"
  },
  "reflection": "Observation: 两个并行 agent 写入同一文件\nReasoning: plan 阶段未正确隔离 owned_files\nPlan: 下次并行任务前强制 dry-run DAG 冲突检测"
}
```
