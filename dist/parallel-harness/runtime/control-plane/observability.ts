/**
 * 可观测性服务 — 收集和暴露平台运行指标
 *
 * 负责采集任务执行、Worker 调度、成本消耗、验证结果等核心指标，
 * 提供统一的 getMetrics() 接口供外部查询。
 * 可选注入 EventBus 实现自动化指标收集。
 */

import type { ModelTier } from '../schemas/types.js';
import type { EventBus, PlatformEvent } from './event-bus.js';

// ─── 指标结构 ─────────────────────────────────────────────

/** 平台运行指标：汇总所有可观测维度 */
export interface PlatformMetrics {
  // ── 任务指标 ──
  /** 任务总数 */
  tasks_total: number;
  /** 等待中的任务数 */
  tasks_pending: number;
  /** 执行中的任务数 */
  tasks_in_progress: number;
  /** 已完成的任务数 */
  tasks_completed: number;
  /** 已失败的任务数 */
  tasks_failed: number;

  // ── Worker 指标 ──
  /** 活跃 Worker 数（正在执行任务） */
  workers_active: number;
  /** 空闲 Worker 数 */
  workers_idle: number;

  // ── 成本指标 ──
  /** 累计总成本 */
  total_cost: number;
  /** 按模型层级分类的成本 */
  cost_by_tier: Record<ModelTier, number>;

  // ── 验证指标 ──
  /** 验证总次数 */
  verifications_total: number;
  /** 验证通过次数 */
  verifications_passed: number;
  /** 验证失败次数 */
  verifications_failed: number;
  /** 平均验证评分 */
  average_score: number;

  // ── 性能指标 ──
  /** 平均任务执行时长（毫秒） */
  avg_task_duration_ms: number;
  /** 累计总执行时长（毫秒） */
  total_duration_ms: number;
}

/** 任务时间记录：追踪单个任务的执行时间 */
export interface TaskTiming {
  /** 任务唯一标识 */
  task_id: string;
  /** 开始执行时间（ISO-8601） */
  started_at: string;
  /** 完成时间（ISO-8601，可选） */
  completed_at?: string;
  /** 执行时长（毫秒，可选） */
  duration_ms?: number;
}

// ─── ObservabilityService 类 ──────────────────────────────

/**
 * 可观测性服务
 *
 * 维护平台运行的核心指标，支持手动记录和自动事件订阅两种模式。
 * 手动模式：直接调用 recordXxx 方法上报指标。
 * 自动模式：注入 EventBus 后自动监听事件并更新对应指标。
 */
export class ObservabilityService {
  // ── 内部计数器 ──
  private _tasksPending: number = 0;
  private _tasksInProgress: number = 0;
  private _tasksCompleted: number = 0;
  private _tasksFailed: number = 0;

  private _workersActive: number = 0;
  private _workersIdle: number = 0;

  private _totalCost: number = 0;
  private _costByTier: Record<ModelTier, number> = {
    'tier-1': 0,
    'tier-2': 0,
    'tier-3': 0,
  };

  private _verificationsTotal: number = 0;
  private _verificationsPassed: number = 0;
  private _verificationsFailed: number = 0;
  private _totalScore: number = 0;

  private _totalDurationMs: number = 0;

  /** 任务时间记录表：task_id → TaskTiming */
  private _taskTimings: Map<string, TaskTiming> = new Map();

  /** 事件总线取消订阅函数列表 */
  private _unsubscribers: Array<() => void> = [];

  /**
   * 构造函数
   *
   * @param eventBus - 可选的事件总线实例。传入后将自动订阅相关事件。
   */
  constructor(eventBus?: EventBus) {
    if (eventBus) {
      this._subscribeToEvents(eventBus);
    }
  }

  // ─── 手动记录方法 ──────────────────────────────────────

  /**
   * 记录任务开始执行
   *
   * @param taskId - 任务唯一标识
   */
  recordTaskStart(taskId: string): void {
    // 新任务开始：pending → in_progress
    if (this._tasksPending > 0) {
      this._tasksPending--;
    }
    this._tasksInProgress++;

    // 记录开始时间
    this._taskTimings.set(taskId, {
      task_id: taskId,
      started_at: new Date().toISOString(),
    });
  }

  /**
   * 记录任务执行完成
   *
   * @param taskId - 任务唯一标识
   */
  recordTaskComplete(taskId: string): void {
    // in_progress → completed
    if (this._tasksInProgress > 0) {
      this._tasksInProgress--;
    }
    this._tasksCompleted++;

    // 更新时间记录
    this._finalizeTaskTiming(taskId);
  }

  /**
   * 记录任务执行失败
   *
   * @param taskId - 任务唯一标识
   */
  recordTaskFailure(taskId: string): void {
    // in_progress → failed
    if (this._tasksInProgress > 0) {
      this._tasksInProgress--;
    }
    this._tasksFailed++;

    // 更新时间记录
    this._finalizeTaskTiming(taskId);
  }

  /**
   * 记录模型调用成本
   *
   * @param tier - 模型层级
   * @param cost - 本次调用的成本
   */
  recordCost(tier: ModelTier, cost: number): void {
    this._totalCost += cost;
    this._costByTier[tier] += cost;
  }

  /**
   * 记录验证结果
   *
   * @param passed - 是否通过验证
   * @param score - 验证评分（0-100）
   */
  recordVerification(passed: boolean, score: number): void {
    this._verificationsTotal++;
    if (passed) {
      this._verificationsPassed++;
    } else {
      this._verificationsFailed++;
    }
    this._totalScore += score;
  }

  // ─── 查询方法 ──────────────────────────────────────────

  /**
   * 获取当前平台运行指标快照
   *
   * @returns PlatformMetrics 对象
   */
  getMetrics(): PlatformMetrics {
    const tasksTotal =
      this._tasksPending +
      this._tasksInProgress +
      this._tasksCompleted +
      this._tasksFailed;

    // 计算平均任务执行时长
    const completedTimings = Array.from(this._taskTimings.values()).filter(
      (t) => t.duration_ms !== undefined,
    );
    const avgDuration =
      completedTimings.length > 0
        ? this._totalDurationMs / completedTimings.length
        : 0;

    // 计算平均验证评分
    const avgScore =
      this._verificationsTotal > 0
        ? this._totalScore / this._verificationsTotal
        : 0;

    return {
      tasks_total: tasksTotal,
      tasks_pending: this._tasksPending,
      tasks_in_progress: this._tasksInProgress,
      tasks_completed: this._tasksCompleted,
      tasks_failed: this._tasksFailed,

      workers_active: this._workersActive,
      workers_idle: this._workersIdle,

      total_cost: this._totalCost,
      cost_by_tier: { ...this._costByTier },

      verifications_total: this._verificationsTotal,
      verifications_passed: this._verificationsPassed,
      verifications_failed: this._verificationsFailed,
      average_score: avgScore,

      avg_task_duration_ms: avgDuration,
      total_duration_ms: this._totalDurationMs,
    };
  }

  /**
   * 获取所有任务的时间记录
   *
   * @returns TaskTiming 数组
   */
  getTaskTimings(): TaskTiming[] {
    return Array.from(this._taskTimings.values());
  }

  /**
   * 重置所有指标和时间记录
   *
   * 用于会话重置或测试场景。
   */
  reset(): void {
    this._tasksPending = 0;
    this._tasksInProgress = 0;
    this._tasksCompleted = 0;
    this._tasksFailed = 0;

    this._workersActive = 0;
    this._workersIdle = 0;

    this._totalCost = 0;
    this._costByTier = { 'tier-1': 0, 'tier-2': 0, 'tier-3': 0 };

    this._verificationsTotal = 0;
    this._verificationsPassed = 0;
    this._verificationsFailed = 0;
    this._totalScore = 0;

    this._totalDurationMs = 0;
    this._taskTimings.clear();
  }

  // ─── 内部方法 ──────────────────────────────────────────

  /**
   * 完成任务时间记录：计算执行时长
   *
   * @param taskId - 任务唯一标识
   */
  private _finalizeTaskTiming(taskId: string): void {
    const timing = this._taskTimings.get(taskId);
    if (timing) {
      const completedAt = new Date().toISOString();
      const durationMs =
        new Date(completedAt).getTime() - new Date(timing.started_at).getTime();

      timing.completed_at = completedAt;
      timing.duration_ms = durationMs;

      this._totalDurationMs += durationMs;
    }
  }

  /**
   * 订阅 EventBus 事件，自动更新指标
   *
   * 监听以下事件类别：
   * - task:* → 更新任务计数和时间记录
   * - worker:* → 更新 Worker 活跃/空闲状态
   * - cost:* → 更新成本指标
   * - verifier:* → 更新验证指标
   *
   * @param eventBus - 事件总线实例
   */
  private _subscribeToEvents(eventBus: EventBus): void {
    // ── 任务事件 ──
    this._unsubscribers.push(
      eventBus.on('task:created', (_event: PlatformEvent) => {
        this._tasksPending++;
      }),
    );

    this._unsubscribers.push(
      eventBus.on('task:started', (event: PlatformEvent) => {
        const taskId = event.payload['task_id'] as string;
        if (taskId) {
          this.recordTaskStart(taskId);
        }
      }),
    );

    this._unsubscribers.push(
      eventBus.on('task:completed', (event: PlatformEvent) => {
        const taskId = event.payload['task_id'] as string;
        if (taskId) {
          this.recordTaskComplete(taskId);
        }
      }),
    );

    this._unsubscribers.push(
      eventBus.on('task:failed', (event: PlatformEvent) => {
        const taskId = event.payload['task_id'] as string;
        if (taskId) {
          this.recordTaskFailure(taskId);
        }
      }),
    );

    // ── Worker 事件 ──
    this._unsubscribers.push(
      eventBus.on('worker:dispatched', (_event: PlatformEvent) => {
        this._workersActive++;
        if (this._workersIdle > 0) {
          this._workersIdle--;
        }
      }),
    );

    this._unsubscribers.push(
      eventBus.on('worker:completed', (_event: PlatformEvent) => {
        if (this._workersActive > 0) {
          this._workersActive--;
        }
        this._workersIdle++;
      }),
    );

    this._unsubscribers.push(
      eventBus.on('worker:failed', (_event: PlatformEvent) => {
        if (this._workersActive > 0) {
          this._workersActive--;
        }
        this._workersIdle++;
      }),
    );

    this._unsubscribers.push(
      eventBus.on('worker:timeout', (_event: PlatformEvent) => {
        if (this._workersActive > 0) {
          this._workersActive--;
        }
        this._workersIdle++;
      }),
    );

    // ── 成本事件 ──
    this._unsubscribers.push(
      eventBus.on('cost:recorded', (event: PlatformEvent) => {
        const tier = event.payload['tier'] as ModelTier | undefined;
        const cost = event.payload['cost'] as number | undefined;
        if (tier && cost !== undefined) {
          this.recordCost(tier, cost);
        }
      }),
    );

    // ── 验证事件 ──
    this._unsubscribers.push(
      eventBus.on('verifier:completed', (event: PlatformEvent) => {
        const passed = event.payload['passed'] as boolean | undefined;
        const score = event.payload['score'] as number | undefined;
        if (passed !== undefined && score !== undefined) {
          this.recordVerification(passed, score);
        }
      }),
    );
  }
}
