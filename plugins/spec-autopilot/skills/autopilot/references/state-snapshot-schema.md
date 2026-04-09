# State Snapshot Schema (v6.0)

> 本文件由 autopilot-recovery SKILL.md 引用。定义 state-snapshot.json 的完整结构和消费方契约。

## JSON Schema

```json
{
  "schema_version": "6.0",
  "saved_at": "ISO-8601",
  "change_name": "string",
  "execution_mode": "full|lite|minimal",
  "anchor_sha": "string|null",
  "requirement_packet_hash": "string|null (sha256[:16] of phase-1 checkpoint)",
  "gate_frontier": "number (highest passed gate phase)",
  "last_completed_phase": "number",
  "next_action": {
    "phase": "number",
    "type": "resume",
    "description": "string"
  },
  "phase_results": {
    "1": {"status": "ok|warning|blocked|failed|pending", "summary": "string", "file": "string|null", "artifacts": []},
    "2": "...",
    "...": "..."
  },
  "phase_sequence": [1, 2, 3, 4, 5, 6, 7],
  "active_tasks": [{"phase": 5, "step": "gate_passed"}],
  "tasks_progress": {"completed": 3, "remaining": 2},
  "phase5_task_details": [{"number": 1, "status": "ok", "summary": "..."}],
  "progress_entries": [{"phase": 5, "step": "task_3", "status": "in_progress"}],
  "review_status": "null (由 Phase 6/6.5 填充)",
  "fixup_status": "null (由 Phase 7 填充)",
  "archive_status": "null (由 Phase 7 填充)",
  "snapshot_hash": "string (sha256[:16] of all fields except snapshot_hash)"
}
```

## GUI / Server 需要消费的恢复字段

1. `gate_frontier` — GUI 时间轴可标记已通过的 gate 边界
2. `next_action.phase` — GUI 显示"下一步"指示
3. `recovery_confidence` — GUI 恢复面板显示置信度标识
4. `requirement_packet_hash` — GUI 可验证需求一致性
5. `snapshot_hash` — GUI/server 可校验 snapshot 完整性

## 与 Workstream B 的对接要求

1. `archive_status` 字段由 Phase 7（Workstream B）负责填充
2. `fixup_status` 字段由 Phase 7 归档逻辑填充
3. `review_status` 字段由 Phase 6/6.5 填充
4. Workstream B 的 `auto_continue_after_phase1` 配置影响 recovery 的 `auto_continue_eligible` 判定
