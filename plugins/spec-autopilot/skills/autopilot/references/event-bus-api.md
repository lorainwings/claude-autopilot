# Event Bus API Reference (v5.0)

> 本文件定义 autopilot 事件总线的事件格式规范，为 GUI 大盘集成提供标准化接口。

## 事件传输

- **文件系统**: `logs/events.jsonl` (JSON Lines 格式，append-only)
- **实时推送 (v5.0)**: WebSocket (`ws://localhost:8765`) — 双模服务器自动监听 events.jsonl 并推送

## v5.0 通用上下文字段

所有事件类型均包含以下顶层字段，为 GUI 渲染提供充足上下文：

| 字段 | 类型 | 来源 | 说明 |
|------|------|------|------|
| `change_name` | string | 锁文件 `.change` / `AUTOPILOT_CHANGE_NAME` | 当前变更名称 |
| `session_id` | string | 锁文件 `.session_id` / `AUTOPILOT_SESSION_ID` | 会话唯一标识 |
| `phase_label` | string | 静态映射 | Phase 人类可读名称 (e.g. "Implementation") |
| `total_phases` | number | mode 推导 | 当前模式的总阶段数 (full=8, lite=5, minimal=4) |
| `sequence` | number | `logs/.event_sequence` 自增 | 全局事件自增序号，保证 GUI 排序 |

## 事件类型

### PhaseEvent

Phase 生命周期事件，在每个阶段开始和结束时发射。

```typescript
interface PhaseEvent {
  type: 'phase_start' | 'phase_end' | 'error';
  phase: number;             // 0-7
  mode: 'full' | 'lite' | 'minimal';
  timestamp: string;         // ISO-8601
  change_name: string;       // v5.0: 变更名称
  session_id: string;        // v5.0: 会话 ID
  phase_label: string;       // v5.0: "Environment Setup" | "Requirements" | ...
  total_phases: number;      // v5.0: 8 | 5 | 4
  sequence: number;          // v5.0: 全局自增序号
  payload: {
    status?: 'ok' | 'warning' | 'blocked' | 'failed';
    duration_ms?: number;
    error_message?: string;
    artifacts?: string[];
  };
}
```

### GateEvent

门禁判定事件，在 Gate 通过或阻断时发射。

```typescript
interface GateEvent {
  type: 'gate_pass' | 'gate_block';
  phase: number;             // 目标 Phase (即将进入的 Phase)
  mode: 'full' | 'lite' | 'minimal';
  timestamp: string;         // ISO-8601
  change_name: string;       // v5.0: 变更名称
  session_id: string;        // v5.0: 会话 ID
  phase_label: string;       // v5.0: 目标 Phase 标签
  total_phases: number;      // v5.0: 8 | 5 | 4
  sequence: number;          // v5.0: 全局自增序号
  payload: {
    gate_score?: string;     // "8/8"
    status?: 'ok' | 'warning' | 'blocked' | 'failed';
    error_message?: string;
  };
}
```

### TaskProgressEvent (v5.0 规划)

Phase 5 任务粒度进度事件。

```typescript
interface TaskProgressEvent {
  type: 'task_progress';
  phase: 5;
  task_index: number;        // 1-based
  task_total: number;
  task_name: string;
  status: 'running' | 'passed' | 'failed' | 'retrying';
  tdd_step?: 'red' | 'green' | 'refactor';
  retry_count?: number;
  timestamp: string;         // ISO-8601
}
```

## 事件发射脚本

| 脚本 | 事件类型 | 调用时机 |
|------|---------|---------|
| `scripts/emit-phase-event.sh` | `phase_start`, `phase_end`, `error` | SKILL.md 统一调度模板 Step 0 / Step 6.5 |
| `scripts/emit-gate-event.sh` | `gate_pass`, `gate_block` | SKILL.md 统一调度模板 Step 1 (Gate 判定后) |

## 使用示例

### CLI 消费 (实时监听)

```bash
# 实时监听事件流
tail -f logs/events.jsonl | jq .

# 过滤特定事件类型
tail -f logs/events.jsonl | jq 'select(.type == "phase_end")'

# 统计各阶段耗时
cat logs/events.jsonl | jq 'select(.type == "phase_end") | {phase, duration_ms: .payload.duration_ms}'
```

### GUI 消费 (轮询)

```typescript
// 轮询 events.jsonl 获取最新事件
class EventPoller {
  private lastOffset = 0;

  async poll(): Promise<AutopilotEvent[]> {
    const content = await fs.readFile('logs/events.jsonl', 'utf-8');
    const lines = content.split('\n').filter(Boolean);
    const newEvents = lines.slice(this.lastOffset).map(JSON.parse);
    this.lastOffset = lines.length;
    return newEvents;
  }
}
```

## 日志文件管理

- **路径**: `{project_root}/logs/events.jsonl`
- **格式**: 每行一个 JSON 对象 (JSON Lines)
- **旋转**: 每次 autopilot 新会话自动追加（不覆盖）
- **清理**: Phase 7 归档时可选清理旧日志
- **建议**: 将 `logs/` 添加到 `.gitignore`
