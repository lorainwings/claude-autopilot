/**
 * Worker 分发器
 *
 * 负责将可执行任务分发给具体 Worker 实例，
 * 管理 Worker 生命周期（启动、监控、超时、终止），
 * 并收集 Worker 执行结果。
 */

import type { TaskNode } from '../schemas/task-graph.js';
import type { ContextPack } from '../schemas/context-pack.js';
import type { FileChange } from '../schemas/role-contracts.js';

// ─── 分发器配置 ─────────────────────────────────────────

/** Worker 分发配置 */
export interface DispatchConfig {
  /** 最大并发 Worker 数 */
  max_workers: number;
  /** 单个 Worker 超时（毫秒） */
  worker_timeout_ms: number;
  /** 隔离模式：进程级 / git worktree / 沙箱 */
  isolation_mode: 'process' | 'worktree' | 'sandbox';
}

/** 默认分发配置 */
const DEFAULT_DISPATCH_CONFIG: DispatchConfig = {
  max_workers: 4,
  worker_timeout_ms: 300_000, // 5 分钟
  isolation_mode: 'worktree',
};

// ─── Worker 实例状态 ────────────────────────────────────

/** Worker 实例运行时状态 */
export interface WorkerInstance {
  /** Worker 唯一标识 */
  id: string;
  /** 正在执行的任务 id */
  task_id: string;
  /** Worker 当前状态 */
  status: 'idle' | 'running' | 'completed' | 'failed' | 'timeout';
  /** 启动时间（ISO 8601） */
  started_at?: string;
  /** 完成时间（ISO 8601） */
  completed_at?: string;
  /** 执行结果（完成后填充） */
  result?: WorkerResult;
}

// ─── Worker 执行结果 ────────────────────────────────────

/** Worker 执行完毕后返回的结果 */
export interface WorkerResult {
  /** 关联的任务 id */
  task_id: string;
  /** 本次执行产生的文件变更列表 */
  changed_files: FileChange[];
  /** 标准输出 */
  stdout: string;
  /** 标准错误 */
  stderr: string;
  /** 退出码（0 表示成功） */
  exit_code: number;
  /** 执行耗时（毫秒） */
  duration_ms: number;
}

// ─── Worker 分发器实现 ──────────────────────────────────

/** 自增 Worker ID 计数器 */
let workerIdCounter = 0;

/** 生成唯一 Worker ID */
function generateWorkerId(): string {
  workerIdCounter += 1;
  return `worker-${Date.now()}-${workerIdCounter}`;
}

export class WorkerDispatch {
  /** 当前生效的配置 */
  private readonly config: DispatchConfig;

  /** 活跃 Worker 映射：worker_id → WorkerInstance */
  private readonly workers: Map<string, WorkerInstance> = new Map();

  /** 已完成的 Worker 历史记录 */
  private readonly history: WorkerInstance[] = [];

  constructor(config?: Partial<DispatchConfig>) {
    this.config = { ...DEFAULT_DISPATCH_CONFIG, ...config };
  }

  // ── 核心分发 ────────────────────────────────────────────

  /**
   * 将任务分发给一个新 Worker 执行。
   *
   * 流程：
   *   1. 检查是否有空闲槽位
   *   2. 创建 WorkerInstance 并标记为 running
   *   3. 模拟执行（记录启动时间、上下文、超时监控）
   *   4. 返回执行结果
   *
   * @param node - 待执行的任务节点
   * @param contextPack - 为该任务准备的上下文包
   * @returns Worker 执行结果
   * @throws 当没有空闲槽位时抛出错误
   */
  async dispatch(node: TaskNode, contextPack: ContextPack): Promise<WorkerResult> {
    // 检查槽位
    if (!this.isSlotAvailable()) {
      throw new Error(
        `无可用 Worker 槽位：当前 ${this.workers.size}/${this.config.max_workers} 已占满`,
      );
    }

    const workerId = generateWorkerId();
    const startedAt = new Date().toISOString();

    // 创建 Worker 实例并注册
    const worker: WorkerInstance = {
      id: workerId,
      task_id: node.id,
      status: 'running',
      started_at: startedAt,
    };
    this.workers.set(workerId, worker);

    try {
      // 模拟 Worker 执行过程
      const result = await this.executeWorker(node, contextPack, worker);

      // 标记完成
      worker.status = 'completed';
      worker.completed_at = new Date().toISOString();
      worker.result = result;

      // 归档到历史记录
      this.archiveWorker(workerId);

      return result;
    } catch (error) {
      // 判断是否为超时
      const isTimeout =
        error instanceof Error && error.message.includes('timeout');
      worker.status = isTimeout ? 'timeout' : 'failed';
      worker.completed_at = new Date().toISOString();

      // 归档到历史记录
      this.archiveWorker(workerId);

      throw error;
    }
  }

  // ── Worker 查询 ─────────────────────────────────────────

  /** 获取当前所有活跃（running 状态）的 Worker 实例 */
  getActiveWorkers(): WorkerInstance[] {
    return Array.from(this.workers.values()).filter(
      (w) => w.status === 'running',
    );
  }

  /** 获取当前 Worker 总数（含所有状态） */
  getWorkerCount(): number {
    return this.workers.size;
  }

  /** 是否还有空闲槽位 */
  isSlotAvailable(): boolean {
    return this.workers.size < this.config.max_workers;
  }

  // ── Worker 生命周期管理 ─────────────────────────────────

  /** 终止指定 Worker */
  terminateWorker(workerId: string): void {
    const worker = this.workers.get(workerId);
    if (!worker) {
      return; // Worker 不存在，静默忽略
    }

    worker.status = 'failed';
    worker.completed_at = new Date().toISOString();
    this.archiveWorker(workerId);
  }

  /** 终止所有正在运行的 Worker */
  terminateAll(): void {
    const now = new Date().toISOString();
    for (const [id, worker] of this.workers) {
      if (worker.status === 'running') {
        worker.status = 'failed';
        worker.completed_at = now;
      }
      this.history.push(worker);
    }
    this.workers.clear();
  }

  // ── 只读访问器 ──────────────────────────────────────────

  /** 获取当前配置（只读副本） */
  getConfig(): Readonly<DispatchConfig> {
    return { ...this.config };
  }

  /** 获取 Worker 历史记录 */
  getHistory(): readonly WorkerInstance[] {
    return this.history;
  }

  // ── 内部辅助 ────────────────────────────────────────────

  /**
   * 模拟 Worker 执行
   *
   * 在 MVP 阶段，此方法不会真正启动子进程或 worktree，
   * 而是模拟执行过程并返回一个空结果。
   * 后续版本将根据 isolation_mode 选择实际执行策略。
   */
  private async executeWorker(
    node: TaskNode,
    _contextPack: ContextPack,
    _worker: WorkerInstance,
  ): Promise<WorkerResult> {
    // 模拟执行延迟（通过 Promise.resolve 保持异步语义）
    const startTime = Date.now();

    // 将来根据 isolation_mode 分支：
    //   - 'process': 启动子进程执行
    //   - 'worktree': 在 git worktree 中隔离执行
    //   - 'sandbox': 在沙箱容器中执行

    await Promise.resolve();

    const endTime = Date.now();

    return {
      task_id: node.id,
      changed_files: [],
      stdout: `[模拟执行] 任务 "${node.title}" 已完成`,
      stderr: '',
      exit_code: 0,
      duration_ms: endTime - startTime,
    };
  }

  /** 将 Worker 从活跃映射移入历史记录 */
  private archiveWorker(workerId: string): void {
    const worker = this.workers.get(workerId);
    if (worker) {
      this.history.push(worker);
      this.workers.delete(workerId);
    }
  }
}
