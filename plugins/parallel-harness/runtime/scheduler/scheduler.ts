/**
 * 最小调度器 MVP
 *
 * 负责从任务图 (TaskGraph) 中提取可执行任务，按策略排序，
 * 控制并发度，并生成分层执行计划。
 */

import type { TaskStatus, RiskLevel } from '../schemas/types.js';
import type { TaskNode, TaskGraph } from '../schemas/task-graph.js';

// ─── 调度器配置 ─────────────────────────────────────────────

/** 调度器配置项 */
export interface SchedulerConfig {
  /** 最大并发任务数 */
  max_concurrent: number;
  /** 优先级策略：先进先出 / 按复杂度 / 按风险等级 */
  priority_strategy: 'fifo' | 'complexity' | 'risk';
  /** 单个任务超时毫秒数 */
  timeout_ms: number;
}

/** 默认调度器配置 */
const DEFAULT_CONFIG: SchedulerConfig = {
  max_concurrent: 4,
  priority_strategy: 'risk',
  timeout_ms: 300_000, // 5 分钟
};

// ─── 调度器事件 ─────────────────────────────────────────────

/** 调度器产出的事件类型 */
export interface SchedulerEvent {
  type: 'task_started' | 'task_completed' | 'task_failed' | 'task_timeout';
  task_id: string;
  timestamp: string;
  details?: unknown;
}

// ─── 任务执行记录 ───────────────────────────────────────────

/** 单个任务的执行状态记录 */
export interface TaskExecution {
  task_id: string;
  status: TaskStatus;
  started_at?: string;
  completed_at?: string;
  result?: unknown;
  error?: string;
}

// ─── 风险等级权重映射 ───────────────────────────────────────

/** 风险越高，优先级越高（数值越大越优先） */
const RISK_WEIGHT: Record<RiskLevel, number> = {
  critical: 4,
  high: 3,
  medium: 2,
  low: 1,
};

// ─── 调度器实现 ─────────────────────────────────────────────

export class Scheduler {
  /** 当前生效的配置 */
  private readonly config: SchedulerConfig;

  /** 正在执行中的任务映射：task_id → TaskExecution */
  private readonly running: Map<string, TaskExecution> = new Map();

  /** 已完成的任务执行记录 */
  private readonly history: TaskExecution[] = [];

  /** 事件日志 */
  private readonly events: SchedulerEvent[] = [];

  constructor(config?: Partial<SchedulerConfig>) {
    this.config = { ...DEFAULT_CONFIG, ...config };
  }

  // ── 核心查询 ────────────────────────────────────────────

  /**
   * 获取可执行任务列表
   *
   * 条件：
   *   1. 任务自身状态为 pending
   *   2. 所有依赖任务都已 completed
   */
  getReadyTasks(graph: TaskGraph): TaskNode[] {
    // 构建已完成任务的 id 集合，方便 O(1) 查询
    const completedIds = new Set<string>(
      graph.nodes
        .filter((n) => n.status === 'completed')
        .map((n) => n.id),
    );

    return graph.nodes.filter((node) => {
      // 只关注 pending 状态的任务
      if (node.status !== 'pending') return false;

      // 排除正在执行中的任务
      if (this.running.has(node.id)) return false;

      // 所有依赖都必须已完成
      return node.dependencies.every((depId) => completedIds.has(depId));
    });
  }

  /**
   * 按策略对任务列表进行优先级排序（降序：最高优先级在前）
   */
  prioritize(tasks: TaskNode[]): TaskNode[] {
    const sorted = [...tasks];

    switch (this.config.priority_strategy) {
      case 'fifo':
        // 先进先出：保持原始顺序不变
        break;

      case 'complexity':
        // 复杂度优先：复杂度高的先执行（尽早暴露风险）
        sorted.sort(
          (a, b) => (b.complexity_score ?? 0) - (a.complexity_score ?? 0),
        );
        break;

      case 'risk':
        // 风险优先：高风险任务先执行
        sorted.sort(
          (a, b) => RISK_WEIGHT[b.risk_level] - RISK_WEIGHT[a.risk_level],
        );
        break;
    }

    return sorted;
  }

  /**
   * 调度一轮：从图中选取可执行任务，排序后启动（不超过最大并发）
   *
   * 返回本轮新启动的执行记录列表。
   */
  schedule(graph: TaskGraph): TaskExecution[] {
    // 计算剩余可用并发槽位
    const availableSlots = this.config.max_concurrent - this.running.size;
    if (availableSlots <= 0) return [];

    // 获取并排序就绪任务
    const ready = this.prioritize(this.getReadyTasks(graph));

    // 取出本轮要启动的任务（不超过可用槽位数）
    const toStart = ready.slice(0, availableSlots);
    const executions: TaskExecution[] = [];

    for (const node of toStart) {
      const now = new Date().toISOString();
      const execution: TaskExecution = {
        task_id: node.id,
        status: 'in_progress',
        started_at: now,
      };

      // 更新图中节点状态
      node.status = 'in_progress';

      // 记录到运行中映射
      this.running.set(node.id, execution);

      // 发出事件
      this.emitEvent({
        type: 'task_started',
        task_id: node.id,
        timestamp: now,
      });

      executions.push(execution);
    }

    return executions;
  }

  /**
   * 任务完成回调：标记完成，检查是否有新任务因此变为可调度
   *
   * @returns 新变为 ready 的任务列表
   */
  onTaskComplete(taskId: string, graph: TaskGraph): TaskNode[] {
    const now = new Date().toISOString();

    // 从运行中移除
    const execution = this.running.get(taskId);
    if (execution) {
      execution.status = 'completed';
      execution.completed_at = now;
      this.history.push(execution);
      this.running.delete(taskId);
    }

    // 更新图中节点状态
    const node = graph.nodes.find((n) => n.id === taskId);
    if (node) {
      node.status = 'completed';
    }

    // 发出完成事件
    this.emitEvent({
      type: 'task_completed',
      task_id: taskId,
      timestamp: now,
    });

    // 返回因本次完成而新变为可执行的任务
    return this.getReadyTasks(graph);
  }

  /**
   * 生成分层执行计划
   *
   * 将任务图分解为多个「层级」，同一层内的任务互不依赖、可完全并行；
   * 后续层级依赖于前面层级的完成。
   *
   * 算法：拓扑排序的分层变体（Kahn's algorithm with level tracking）
   *
   * @returns 二维数组，外层下标是执行层级，内层是该层的 TaskExecution
   */
  getExecutionPlan(graph: TaskGraph): TaskExecution[][] {
    // 构建入度表和邻接表
    const inDegree = new Map<string, number>();
    const dependents = new Map<string, string[]>(); // 某任务完成后，哪些任务的入度可以减少

    for (const node of graph.nodes) {
      inDegree.set(node.id, node.dependencies.length);
      for (const depId of node.dependencies) {
        if (!dependents.has(depId)) {
          dependents.set(depId, []);
        }
        dependents.get(depId)!.push(node.id);
      }
    }

    const layers: TaskExecution[][] = [];
    const processed = new Set<string>();

    // 逐层剥离入度为 0 的节点
    while (processed.size < graph.nodes.length) {
      // 收集当前层：入度为 0 且尚未处理的节点
      const currentLayer: TaskNode[] = [];
      for (const node of graph.nodes) {
        if (!processed.has(node.id) && (inDegree.get(node.id) ?? 0) === 0) {
          currentLayer.push(node);
        }
      }

      // 如果没有新节点可处理，说明存在循环依赖，中断
      if (currentLayer.length === 0) break;

      // 排序当前层
      const sorted = this.prioritize(currentLayer);

      // 转换为 TaskExecution
      const layerExecutions: TaskExecution[] = sorted.map((node) => ({
        task_id: node.id,
        status: 'pending' as TaskStatus,
      }));

      layers.push(layerExecutions);

      // 标记当前层已处理，并减少后继节点入度
      for (const node of currentLayer) {
        processed.add(node.id);
        for (const depId of dependents.get(node.id) ?? []) {
          inDegree.set(depId, (inDegree.get(depId) ?? 1) - 1);
        }
      }
    }

    return layers;
  }

  // ── 内部辅助 ────────────────────────────────────────────

  /** 记录事件 */
  private emitEvent(event: SchedulerEvent): void {
    this.events.push(event);
  }

  // ── 只读访问器 ──────────────────────────────────────────

  /** 获取当前正在运行的任务数 */
  get runningCount(): number {
    return this.running.size;
  }

  /** 获取所有历史事件 */
  getEvents(): readonly SchedulerEvent[] {
    return this.events;
  }

  /** 获取所有历史执行记录 */
  getHistory(): readonly TaskExecution[] {
    return this.history;
  }

  /** 获取当前配置（只读副本） */
  getConfig(): Readonly<SchedulerConfig> {
    return { ...this.config };
  }
}
