> **[中文版](event-bus-api.zh.md)** | English (default)

# Event Bus API Reference

> 本文件定义 autopilot 事件总线的事件格式规范，为 GUI 大盘集成提供标准化接口。

## Contents

- [事件传输](#事件传输)
- [通用上下文字段](#通用上下文字段)
- [事件类型](#事件类型)
- [事件发射脚本](#事件发射脚本)
- [使用示例](#使用示例)
- [日志文件管理](#日志文件管理)

## 事件传输

- **文件系统**: `logs/events.jsonl` (JSON Lines 格式，append-only)
- **实时推送**: WebSocket (`ws://localhost:8765`) — 双模服务器自动监听 events.jsonl 并推送

## 通用上下文字段

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
  change_name: string;       // 变更名称
  session_id: string;        // 会话 ID
  phase_label: string;       // "Environment Setup" | "Requirements" | ...
  total_phases: number;      // 8 | 5 | 4
  sequence: number;          // 全局自增序号
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
  change_name: string;       // 变更名称
  session_id: string;        // 会话 ID
  phase_label: string;       // 目标 Phase 标签
  total_phases: number;      // 8 | 5 | 4
  sequence: number;          // 全局自增序号
  payload: {
    gate_score?: string;     // "8/8"
    status?: 'ok' | 'warning' | 'blocked' | 'failed';
    error_message?: string;
  };
}
```

### TaskProgressEvent

Phase 5 任务粒度进度事件。由 `emit-task-progress.sh` 脚本发射。

```typescript
interface TaskProgressEvent {
  type: 'task_progress';
  phase: 5;
  mode: 'full' | 'lite' | 'minimal';
  timestamp: string;           // ISO-8601
  change_name: string;         // 变更名称
  session_id: string;          // 会话 ID
  phase_label: string;         // "Implementation"
  total_phases: number;        // 8 | 5 | 4
  sequence: number;            // 全局自增序号
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

### DecisionAckEvent

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

### ToolUseEvent

工具调用事件。由 PostToolUse catch-all hook (`emit-tool-event.sh`) 在每次工具调用后自动发射。

```typescript
interface ToolUseEvent {
  type: 'tool_use';
  phase: number;               // 从 events.jsonl 最后一条 phase_start 推断
  mode: 'full' | 'lite' | 'minimal';
  timestamp: string;           // ISO-8601
  change_name: string;         // 变更名称
  session_id: string;          // 会话 ID
  phase_label: string;         // Phase 标签
  total_phases: number;        // 8 | 5 | 4
  sequence: number;            // 全局自增序号
  payload: {
    tool_name: string;         // "Bash" | "Read" | "Write" | "Edit" | "Glob" | "Grep" | "Agent"
    key_param?: string;        // Bash→command前80字符, Read/Write/Edit→file_path, Glob/Grep→pattern
    exit_code?: number;        // Bash only
    output_preview?: string;   // 截取前200字符
  };
}
```

### AgentDispatchEvent / AgentCompleteEvent

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

### SubStepEvent

Phase 0-4 子步骤进度事件。由 `emit-sub-step-event.sh` 在各阶段关键步骤执行时发射。

```typescript
interface SubStepEvent {
  type: 'sub_step';
  phase: number;               // 0-4
  mode: 'full' | 'lite' | 'minimal';
  timestamp: string;           // ISO-8601
  change_name: string;
  session_id: string;
  phase_label: string;
  total_phases: number;
  sequence: number;
  payload: {
    step_id: string;           // "env-check", "config-load", "crash-scan"
    step_label: string;        // 人类可读步骤名称
    step_index?: number;       // 当前步骤序号 (0-based)
    total_steps?: number;      // 本 Phase 总步骤数
    [key: string]: unknown;    // 额外自定义字段
  };
}
```

### GateStepEvent

Gate 8-step 逐步检查结果事件。由 `emit-gate-event.sh gate_step` 在每个检查步骤完成时发射。

```typescript
interface GateStepEvent {
  type: 'gate_step';
  phase: number;               // 目标 Phase
  mode: 'full' | 'lite' | 'minimal';
  timestamp: string;           // ISO-8601
  change_name: string;
  session_id: string;
  phase_label: string;
  total_phases: number;
  sequence: number;
  payload: {
    step_index: number;        // 0-7, 当前检查步骤
    step_name: string;         // "predecessor_check", "hook_l2", ...
    step_result: string;       // "pass" | "fail" | "skip" | "warning"
    step_detail?: string;      // 可选详情
  };
}
```

### GateDecisionEvent

Gate 决策生命周期事件。由 `emit-phase-event.sh gate_decision_pending|gate_decision_received` 发射。

```typescript
interface GateDecisionPendingEvent {
  type: 'gate_decision_pending';
  phase: number;
  mode: 'full' | 'lite' | 'minimal';
  timestamp: string;
  change_name: string;
  session_id: string;
  phase_label: string;
  total_phases: number;
  sequence: number;
  payload: {
    gate_score?: string;       // "5/8"
    blocking_steps?: string[]; // 失败的步骤名
  };
}

interface GateDecisionReceivedEvent {
  type: 'gate_decision_received';
  phase: number;
  mode: 'full' | 'lite' | 'minimal';
  timestamp: string;
  change_name: string;
  session_id: string;
  phase_label: string;
  total_phases: number;
  sequence: number;
  payload: {
    action: 'retry' | 'fix' | 'override';
  };
}
```

### ParallelEvent

并行调度事件。由 SKILL.md 统一调度模板在并行计划/批次执行时发射。

```typescript
interface ParallelPlanEvent {
  type: 'parallel_plan';
  phase: number;
  mode: 'full' | 'lite' | 'minimal';
  timestamp: string;
  change_name: string;
  session_id: string;
  phase_label: string;
  total_phases: number;
  sequence: number;
  payload: {
    total_tasks: number;
    batch_count: number;
    batch_sizes: number[];
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
    batch_index: number;       // 0-based
    batch_size: number;
    task_names: string[];
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
    batch_index: number;
    passed: number;
    failed: number;
    duration_ms?: number;
  };
}
```

### ParallelTaskEvent

并行任务状态事件。由调度模板在任务就绪/阻断/降级时发射。

```typescript
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
    task_name: string;
    batch_index: number;
    owned_files: string[];
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
    task_name: string;
    reason: string;
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
    from: 'parallel';
    to: 'serial';
    reason: string;            // "merge_conflict_exceeded" | "consecutive_batch_failure" | "user_override"
  };
}
```

### ModelRoutingEvent

模型路由事件。由 `emit-model-routing-event.sh` 在模型选择/降级时发射。

```typescript
interface ModelRoutingEvent {
  type: 'model_routing';
  phase: number;
  mode: 'full' | 'lite' | 'minimal';
  timestamp: string;
  change_name: string;
  session_id: string;
  phase_label: string;
  total_phases: number;
  sequence: number;
  payload: {
    requested_model: string;
    resolved_model: string;
    strategy: string;          // "cost-optimized" | "balanced" | "quality-max" | "custom"
  };
}

interface ModelEffectiveEvent {
  type: 'model_effective';
  phase: number;
  mode: 'full' | 'lite' | 'minimal';
  timestamp: string;
  change_name: string;
  session_id: string;
  phase_label: string;
  total_phases: number;
  sequence: number;
  payload: {
    model: string;
    phase_config: Record<string, string>;
  };
}

interface ModelFallbackEvent {
  type: 'model_fallback';
  phase: number;
  mode: 'full' | 'lite' | 'minimal';
  timestamp: string;
  change_name: string;
  session_id: string;
  phase_label: string;
  total_phases: number;
  sequence: number;
  payload: {
    from_model: string;
    to_model: string;
    reason: string;
  };
}
```

### TddAuditEvent

TDD 审计事件。由 `emit-tdd-audit-event.sh` 在 Phase 5 完成后发射。

```typescript
interface TddAuditEvent {
  type: 'tdd_audit';
  phase: 5;
  mode: 'full' | 'lite' | 'minimal';
  timestamp: string;
  change_name: string;
  session_id: string;
  phase_label: string;
  total_phases: number;
  sequence: number;
  payload: {
    cycle_count: number;
    red_violations: number;
    green_violations: number;
    refactor_rollbacks: number;
    red_commands: string[];
    green_commands: string[];
  };
}
```

### ReportReadyEvent

报告就绪事件。由 `emit-report-ready-event.sh` 在 Phase 6 完成时发射。

```typescript
interface ReportReadyEvent {
  type: 'report_ready';
  phase: 6;
  mode: 'full' | 'lite' | 'minimal';
  timestamp: string;
  change_name: string;
  session_id: string;
  phase_label: string;
  total_phases: number;
  sequence: number;
  payload: {
    report_format: string;     // "allure" | "junit" | "custom" | "none"
    report_path: string;
    report_url: string;
    allure_results_dir: string;
    allure_preview_url: string;
    suite_results: {
      total: number;
      passed: number;
      failed: number;
      skipped: number;
      error: number;
    };
    anomaly_alerts: unknown[];
  };
}
```

## 事件发射脚本

| 脚本 | 事件类型 | 调用时机 |
|------|---------|---------|
| `scripts/emit-phase-event.sh` | `phase_start`, `phase_end`, `error`, `gate_decision_pending`, `gate_decision_received` | Phase 0 Step 4.6/10.5 + Phase 1 Step 0/10 + 统一调度模板 Step 0/6.5 (Phase 2-6) + Phase 7 Step -1/6.5 |
| `scripts/emit-gate-event.sh` | `gate_pass`, `gate_block`, `gate_step` | SKILL.md 统一调度模板 Step 1 (Gate 判定后)；`gate_step` 在每个 8-step 检查完成后 |
| `scripts/emit-sub-step-event.sh` | `sub_step` | Phase 0-4 各关键子步骤执行时 |
| `scripts/emit-task-progress.sh` | `task_progress` | Phase 5 每个 task 完成后 |
| `scripts/emit-tool-event.sh` | `tool_use` | PostToolUse catch-all hook 自动触发 |
| `scripts/emit-agent-event.sh` | `agent_dispatch`, `agent_complete` | 统一调度模板 Step 2.5/4.5 Agent 派发前/完成后 |
| `scripts/emit-model-routing-event.sh` | `model_routing`, `model_effective`, `model_fallback` | 模型路由解析时 |
| `scripts/emit-tdd-audit-event.sh` | `tdd_audit` | Phase 5 TDD 审计完成后 |
| `scripts/emit-report-ready-event.sh` | `report_ready` | Phase 6 报告生成完成后 |
| `scripts/emit-phase-event.sh` | `gate_decision_pending`, `gate_decision_received` | Gate 阻断后等待用户决策 / 收到决策时 |

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
