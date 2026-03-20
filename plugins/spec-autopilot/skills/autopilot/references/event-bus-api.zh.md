> [English](event-bus-api.md) | 中文

# 事件总线 API 参考 (v5.4)

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

### TaskProgressEvent (v5.2 实现)

Phase 5 任务粒度进度事件。v5.2 起由 `emit-task-progress.sh` 脚本发射。

```typescript
interface TaskProgressEvent {
  type: 'task_progress';
  phase: 5;
  mode: 'full' | 'lite' | 'minimal';
  timestamp: string;           // ISO-8601
  change_name: string;         // v5.0: 变更名称
  session_id: string;          // v5.0: 会话 ID
  phase_label: string;         // v5.0: "Implementation"
  total_phases: number;        // v5.0: 8 | 5 | 4
  sequence: number;            // v5.0: 全局自增序号
  payload: {
    task_name: string;         // task 标识 (如 "task-1-add-login")
    status: 'running' | 'passed' | 'failed' | 'retrying';
    task_index: number;        // 1-based
    task_total: number;
    tdd_step?: 'red' | 'green' | 'refactor';
    retry_count?: number;
  };
}
```

### DecisionAckEvent (v5.2 新增)

GUI 决策确认事件。由 `autopilot-server.ts` 在写入决策文件后通过 WebSocket 广播。

```typescript
interface DecisionAckEvent {
  type: 'decision_ack';        // WebSocket-only，不写入 events.jsonl
  data: {
    action: 'retry' | 'fix' | 'override';
    phase: number;
    timestamp: string;         // ISO-8601
  };
}
```

> **注意**: `decision_ack` 仅通过 WebSocket 推送，不追加到 `events.jsonl`，因为它是 GUI 闭环事件。

### ToolUseEvent (v5.3 新增)

工具调用事件。由 PostToolUse catch-all hook (`emit-tool-event.sh`) 在每次工具调用后自动发射。

```typescript
interface ToolUseEvent {
  type: 'tool_use';
  phase: number;               // 从 events.jsonl 最后一条 phase_start 推断
  mode: 'full' | 'lite' | 'minimal';
  timestamp: string;           // ISO-8601
  change_name: string;         // v5.0: 变更名称
  session_id: string;          // v5.0: 会话 ID
  phase_label: string;         // v5.0: Phase 标签
  total_phases: number;        // v5.0: 8 | 5 | 4
  sequence: number;            // v5.0: 全局自增序号
  payload: {
    tool_name: string;         // "Bash" | "Read" | "Write" | "Edit" | "Glob" | "Grep" | "Agent"
    key_param?: string;        // Bash→command前80字符, Read/Write/Edit→file_path, Glob/Grep→pattern
    exit_code?: number;        // Bash only
    output_preview?: string;   // 截取前200字符
  };
}
```

### AgentDispatchEvent / AgentCompleteEvent (v5.3 新增)

Agent 生命周期事件。由 `emit-agent-event.sh` 在 Agent 派发和完成时发射。

```typescript
interface AgentDispatchEvent {
  type: 'agent_dispatch';
  phase: number;
  mode: 'full' | 'lite' | 'minimal';
  timestamp: string;           // ISO-8601
  change_name: string;
  session_id: string;
  phase_label: string;
  total_phases: number;
  sequence: number;
  payload: {
    agent_id: string;          // "phase2-openspec", "phase5-task-3-auth"
    agent_label: string;       // "OpenSpec 生成"
    background: boolean;
  };
}

interface AgentCompleteEvent {
  type: 'agent_complete';
  phase: number;
  mode: 'full' | 'lite' | 'minimal';
  timestamp: string;           // ISO-8601
  change_name: string;
  session_id: string;
  phase_label: string;
  total_phases: number;
  sequence: number;
  payload: {
    agent_id: string;
    agent_label: string;
    status: 'ok' | 'warning' | 'blocked' | 'failed';
    summary?: string;          // JSON 信封摘要（前 120 字符）
    duration_ms?: number;
  };
}
```

### ModelEffectiveEvent / ModelFallbackEvent (v5.4 新增)

模型路由运行时事件。由 `emit-model-routing-event.sh` 在确认实际运行模型或触发降级时发射。

```typescript
interface ModelEffectiveEvent {
  type: 'model_effective';
  phase: number;
  mode: 'full' | 'lite' | 'minimal';
  timestamp: string;           // ISO-8601
  change_name: string;
  session_id: string;
  phase_label: string;
  total_phases: number;
  sequence: number;
  payload: {
    effective_model: string;   // 实际运行的模型 (如 "sonnet-4")
    effective_tier: string;    // 实际运行的 tier (如 "standard")
    inference_source: string;  // 推断来源 ("statusline" | "env" | "config")
    requested_model: string;   // 请求的模型
    match: boolean;            // 请求模型与实际模型是否一致
    agent_id?: string;         // Agent 标识
  };
}

interface ModelFallbackEvent {
  type: 'model_fallback';
  phase: number;
  mode: 'full' | 'lite' | 'minimal';
  timestamp: string;           // ISO-8601
  change_name: string;
  session_id: string;
  phase_label: string;
  total_phases: number;
  sequence: number;
  payload: {
    requested_model: string;   // 原请求模型
    fallback_model: string;    // 降级后使用的模型 (默认 "sonnet")
    fallback_reason: string;   // 降级原因 (如 "model_not_available")
    agent_id?: string;         // Agent 标识
  };
}
```

> **注意**: `emit-model-routing-event.sh` 支持三种事件类型：`model_routing`（路由决策）、`model_effective`（运行时实际模型确认）、`model_fallback`（模型降级触发）。通过第 6 参数 `event_type` 选择。

### ParallelPlanEvent / ParallelBatchEvent / ParallelTaskEvent / ParallelFallbackEvent (v5.4 新增)

并行调度生命周期事件。由 `emit-parallel-event.sh` 在并行计划生成和执行过程中发射。

```typescript
interface ParallelPlanEvent {
  type: 'parallel_plan';
  phase: number;               // 通常为 5
  mode: 'full' | 'lite' | 'minimal';
  timestamp: string;           // ISO-8601
  change_name: string;
  session_id: string;
  phase_label: string;
  total_phases: number;
  sequence: number;
  payload: {
    scheduler_decision: 'batch_parallel' | 'serial';  // 调度决策
    total_tasks: number;       // 任务总数
    batch_count: number;       // batch 数量
    max_parallelism: number;   // 最大并行度
    fallback_to_serial?: boolean;  // 是否降级为串行
    fallback_reason?: string;  // 降级原因
  };
}

interface ParallelBatchStartEvent {
  type: 'parallel_batch_start';
  phase: number;
  mode: 'full' | 'lite' | 'minimal';
  timestamp: string;
  change_name: string;
  session_id: string;
  phase_label: string;
  total_phases: number;
  sequence: number;
  payload: {
    batch_index: number;       // 当前 batch 索引 (0-based)
    batch_total: number;       // batch 总数
    tasks: string[];           // 本 batch 包含的任务名列表
    can_parallel: boolean;     // 本 batch 是否可并行
  };
}

interface ParallelBatchEndEvent {
  type: 'parallel_batch_end';
  phase: number;
  mode: 'full' | 'lite' | 'minimal';
  timestamp: string;
  change_name: string;
  session_id: string;
  phase_label: string;
  total_phases: number;
  sequence: number;
  payload: {
    batch_index: number;       // 当前 batch 索引 (0-based)
    batch_total: number;       // batch 总数
    tasks_completed: string[]; // 完成的任务名列表
    duration_ms?: number;      // batch 执行耗时
  };
}

interface ParallelTaskReadyEvent {
  type: 'parallel_task_ready';
  phase: number;
  mode: 'full' | 'lite' | 'minimal';
  timestamp: string;
  change_name: string;
  session_id: string;
  phase_label: string;
  total_phases: number;
  sequence: number;
  payload: {
    task_name: string;         // 任务名
    batch_index: number;       // 所属 batch 索引
    dependencies_met: string[];// 已满足的依赖
  };
}

interface ParallelTaskBlockedEvent {
  type: 'parallel_task_blocked';
  phase: number;
  mode: 'full' | 'lite' | 'minimal';
  timestamp: string;
  change_name: string;
  session_id: string;
  phase_label: string;
  total_phases: number;
  sequence: number;
  payload: {
    task_name: string;         // 任务名
    blocked_by: string[];      // 阻塞该任务的依赖列表
    reason: string;            // 阻塞原因
  };
}

interface ParallelFallbackEvent {
  type: 'parallel_fallback';
  phase: number;
  mode: 'full' | 'lite' | 'minimal';
  timestamp: string;
  change_name: string;
  session_id: string;
  phase_label: string;
  total_phases: number;
  sequence: number;
  payload: {
    fallback_reason: string;   // 降级原因 (如 "循环依赖" / "线性依赖链")
    original_decision: string; // 原调度决策
    fallback_decision: 'serial';  // 降级后的决策
    total_tasks: number;       // 任务总数
  };
}
```

## 事件发射脚本

| 脚本 | 事件类型 | 调用时机 |
|------|---------|---------|
| `scripts/emit-phase-event.sh` | `phase_start`, `phase_end`, `error` | Phase 0 Step 4.6/10.5 + Phase 1 Step 0/10 + 统一调度模板 Step 0/6.5 (Phase 2-6) + Phase 7 Step -1/6.5 |
| `scripts/emit-gate-event.sh` | `gate_pass`, `gate_block` | SKILL.md 统一调度模板 Step 1 (Gate 判定后) |
| `scripts/emit-task-progress.sh` | `task_progress` | Phase 5 每个 task 完成后 (v5.2) |
| `scripts/emit-tool-event.sh` | `tool_use` | PostToolUse catch-all hook 自动触发 (v5.3) |
| `scripts/emit-agent-event.sh` | `agent_dispatch`, `agent_complete` | 统一调度模板 Step 2.5/4.5 Agent 派发前/完成后 (v5.3) |
| `scripts/emit-model-routing-event.sh` | `model_routing`, `model_effective`, `model_fallback` | dispatch 路由决策时 / 运行时模型确认 / 模型降级触发 (v5.4) |
| `scripts/emit-parallel-event.sh` | `parallel_plan`, `parallel_batch_start`, `parallel_batch_end`, `parallel_task_ready`, `parallel_task_blocked`, `parallel_fallback` | Phase 5 并行计划生成 / batch 生命周期 / 任务就绪或阻塞 / 并行降级 (v5.4) |

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
