/**
 * 控制面模块统一导出
 *
 * 汇集事件总线、可观测性服务、会话状态管理三大核心组件，
 * 提供插件运行时的控制面基础设施。
 */

// ── 事件总线 ──
export {
  EventBus,
  type EventType,
  type PlatformEvent,
  type EventHandler,
} from './event-bus.js';

// ── 可观测性服务 ──
export {
  ObservabilityService,
  type PlatformMetrics,
  type TaskTiming,
} from './observability.js';

// ── 会话状态管理 ──
export {
  SessionState,
  type SessionSnapshot,
  type TaskResult,
  type SessionConfig,
} from './session-state.js';
