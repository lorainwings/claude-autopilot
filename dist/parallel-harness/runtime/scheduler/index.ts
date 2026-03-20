/**
 * 调度器模块统一导出
 */
export {
  Scheduler,
  type SchedulerConfig,
  type SchedulerEvent,
  type TaskExecution,
} from './scheduler.js';

export { WorkerDispatch } from './worker-dispatch.js';
export type { DispatchConfig, WorkerInstance, WorkerResult } from './worker-dispatch.js';

export { RetryManager } from './retry-manager.js';
export type { RetryPolicy, RetryRecord } from './retry-manager.js';

export { DowngradeManager } from './downgrade-manager.js';
export type {
  DowngradePolicy,
  DowngradeTrigger,
  DowngradeAction,
  DowngradeRecord,
} from './downgrade-manager.js';
