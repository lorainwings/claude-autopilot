/**
 * parallel-harness: Event Bus
 *
 * 平台可观测性的基础设施。
 * 所有运行时事件通过 EventBus 发布和消费。
 *
 * 来源设计：
 * - everything-claude-code: 资产化组织
 * - spec-autopilot: 事件总线经验
 */

// ============================================================
// 事件类型定义
// ============================================================

export type EventType =
  // Task lifecycle
  | "graph_created"
  | "task_ready"
  | "task_dispatched"
  | "task_completed"
  | "task_failed"
  | "task_retrying"
  // Verification / Gate
  | "verification_started"
  | "verification_passed"
  | "verification_blocked"
  | "gate_evaluation_started"
  | "gate_passed"
  | "gate_blocked"
  // Model routing
  | "model_escalated"
  | "model_downgraded"
  | "downgrade_triggered"
  // Batch lifecycle
  | "batch_started"
  | "batch_completed"
  // Session / Run lifecycle
  | "session_started"
  | "session_completed"
  | "run_created"
  | "run_planned"
  | "run_started"
  | "run_completed"
  | "run_failed"
  | "run_cancelled"
  // Approval / Governance
  | "approval_requested"
  | "approval_granted"
  | "approval_denied"
  // Policy
  | "policy_evaluated"
  | "policy_violated"
  // Ownership
  | "ownership_checked"
  | "ownership_violated"
  // Budget
  | "budget_consumed"
  | "budget_exceeded"
  // PR / CI
  | "pr_created"
  | "pr_reviewed"
  | "pr_merged"
  | "ci_failure_detected"
  // Human
  | "human_feedback_received";

/** 平台事件 */
export interface PlatformEvent {
  /** 事件类型 */
  type: EventType;

  /** 时间戳 (ISO-8601) */
  timestamp: string;

  /** 关联的图 ID */
  graph_id?: string;

  /** 关联的任务 ID */
  task_id?: string;

  /** 关联的批次索引 */
  batch_index?: number;

  /** 事件载荷 */
  payload: Record<string, unknown>;
}

/** 事件监听器 */
export type EventListener = (event: PlatformEvent) => void;

// ============================================================
// EventBus 实现
// ============================================================

export class EventBus {
  private listeners: Map<EventType | "*", EventListener[]> = new Map();
  private eventLog: PlatformEvent[] = [];
  private maxLogSize: number;

  constructor(maxLogSize: number = 10000) {
    this.maxLogSize = maxLogSize;
  }

  /** 订阅特定事件类型 */
  on(type: EventType | "*", listener: EventListener): void {
    const existing = this.listeners.get(type) || [];
    existing.push(listener);
    this.listeners.set(type, existing);
  }

  /** 取消订阅 */
  off(type: EventType | "*", listener: EventListener): void {
    const existing = this.listeners.get(type) || [];
    this.listeners.set(
      type,
      existing.filter((l) => l !== listener)
    );
  }

  /** 发布事件 */
  emit(event: PlatformEvent): void {
    // 记录到日志
    this.eventLog.push(event);
    if (this.eventLog.length > this.maxLogSize) {
      this.eventLog = this.eventLog.slice(-this.maxLogSize);
    }

    // 通知特定类型的监听器
    const typeListeners = this.listeners.get(event.type) || [];
    for (const listener of typeListeners) {
      try {
        listener(event);
      } catch (err) {
        console.error(`事件监听器错误 [${event.type}]:`, err);
      }
    }

    // 通知通配符监听器
    const wildcardListeners = this.listeners.get("*") || [];
    for (const listener of wildcardListeners) {
      try {
        listener(event);
      } catch (err) {
        console.error(`通配符监听器错误:`, err);
      }
    }
  }

  /** 获取事件日志 */
  getEventLog(filter?: { type?: EventType; graph_id?: string; task_id?: string }): PlatformEvent[] {
    if (!filter) return [...this.eventLog];

    return this.eventLog.filter((e) => {
      if (filter.type && e.type !== filter.type) return false;
      if (filter.graph_id && e.graph_id !== filter.graph_id) return false;
      if (filter.task_id && e.task_id !== filter.task_id) return false;
      return true;
    });
  }

  /** 清空日志 */
  clear(): void {
    this.eventLog = [];
  }
}

/** 创建带时间戳的事件 */
export function createEvent(
  type: EventType,
  payload: Record<string, unknown>,
  context?: { graph_id?: string; task_id?: string; batch_index?: number }
): PlatformEvent {
  return {
    type,
    timestamp: new Date().toISOString(),
    graph_id: context?.graph_id,
    task_id: context?.task_id,
    batch_index: context?.batch_index,
    payload,
  };
}
