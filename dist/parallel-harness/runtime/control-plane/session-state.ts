/**
 * 会话状态管理 — 持久化任务图和执行状态
 *
 * 负责管理整个执行会话的生命周期，包括：
 * - 创建和跟踪会话
 * - 保存和加载快照
 * - 记录每个任务的执行结果
 * - 维护任务图状态
 *
 * 快照存储在内存中，最多保留 max_snapshots 份。
 */

import type { ModelTier, TaskStatus, VerifierType } from '../schemas/types.js';
import type { TaskGraph } from '../schemas/task-graph.js';
import type { PlatformMetrics } from './observability.js';

// ─── 会话快照 ─────────────────────────────────────────────

/** 会话快照：某一时刻的完整会话状态 */
export interface SessionSnapshot {
  /** 会话唯一标识 */
  session_id: string;
  /** 任务图 */
  graph: TaskGraph;
  /** 各任务的执行结果映射 */
  task_results: Map<string, TaskResult>;
  /** 平台运行指标 */
  metrics: PlatformMetrics;
  /** 快照创建时间（ISO-8601） */
  timestamp: string;
}

// ─── 任务执行结果 ─────────────────────────────────────────

/** 任务执行结果：记录单个任务的完整执行信息 */
export interface TaskResult {
  /** 任务唯一标识 */
  task_id: string;
  /** 最终任务状态 */
  status: TaskStatus;
  /** 被修改的文件路径列表 */
  changed_files: string[];
  /** 各验证器的评分 */
  verifier_scores: Record<VerifierType, number>;
  /** 实际使用的模型层级 */
  model_tier_used: ModelTier;
  /** 执行成本 */
  cost: number;
  /** 执行时长（毫秒） */
  duration_ms: number;
}

// ─── 会话配置 ─────────────────────────────────────────────

/** 会话配置选项 */
export interface SessionConfig {
  /** 是否启用自动保存快照 */
  auto_save: boolean;
  /** 自动保存间隔（毫秒） */
  save_interval_ms: number;
  /** 最大快照保留数 */
  max_snapshots: number;
  /** 快照存储路径 */
  storage_path: string;
}

/** 默认会话配置 */
const DEFAULT_CONFIG: SessionConfig = {
  auto_save: true,
  save_interval_ms: 30000,
  max_snapshots: 10,
  storage_path: '.parallel-harness/sessions',
};

// ─── 工具函数 ─────────────────────────────────────────────

/**
 * 生成简易 UUID（v4 格式）
 * 用于为每个会话分配唯一标识
 */
function generateSessionId(): string {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

// ─── SessionState 类 ─────────────────────────────────────

/**
 * 会话状态管理器
 *
 * 管理单个执行会话的完整生命周期：
 * - 创建会话并关联任务图
 * - 跟踪各任务的执行结果
 * - 定期保存快照供回溯查看
 * - 提供加载和查询功能
 *
 * 注意：当前版本快照仅存储在内存中。
 */
export class SessionState {
  /** 会话配置 */
  private config: SessionConfig;
  /** 当前会话 ID */
  private sessionId: string | null = null;
  /** 当前任务图 */
  private graph: TaskGraph | null = null;
  /** 任务执行结果映射：task_id → TaskResult */
  private taskResults: Map<string, TaskResult> = new Map();
  /** 快照列表（按时间排序） */
  private snapshots: SessionSnapshot[] = [];
  /** 自动保存定时器句柄 */
  private autoSaveTimer: ReturnType<typeof setInterval> | null = null;

  /**
   * 构造函数
   *
   * @param config - 可选的会话配置覆盖。未指定的字段使用默认值。
   */
  constructor(config?: Partial<SessionConfig>) {
    this.config = { ...DEFAULT_CONFIG, ...config };
  }

  /**
   * 创建新会话
   *
   * 初始化会话状态，关联任务图，并在启用自动保存时启动定时器。
   *
   * @param graph - 要执行的任务图
   * @returns 新创建的会话 ID
   */
  createSession(graph: TaskGraph): string {
    // 清理旧会话状态
    this._stopAutoSave();
    this.taskResults.clear();

    // 初始化新会话
    this.sessionId = generateSessionId();
    this.graph = graph;

    // 启用自动保存时启动定时器
    if (this.config.auto_save) {
      this._startAutoSave();
    }

    return this.sessionId;
  }

  /**
   * 获取当前会话 ID
   *
   * @returns 当前会话 ID，未创建会话时返回 null
   */
  getSessionId(): string | null {
    return this.sessionId;
  }

  /**
   * 保存当前会话快照
   *
   * 将当前会话的完整状态（任务图、执行结果、指标）
   * 序列化为快照并存储。超出最大快照数时删除最旧的。
   *
   * @returns 保存的 SessionSnapshot 对象
   * @throws 当无活动会话或任务图时抛出错误
   */
  saveSnapshot(): SessionSnapshot {
    if (!this.sessionId || !this.graph) {
      throw new Error('无法保存快照：没有活动的会话');
    }

    // 构建空指标（实际指标应由 ObservabilityService 提供）
    const metrics: PlatformMetrics = this._buildCurrentMetrics();

    const snapshot: SessionSnapshot = {
      session_id: this.sessionId,
      graph: this.graph,
      task_results: new Map(this.taskResults),
      metrics,
      timestamp: new Date().toISOString(),
    };

    // 追加快照，超出上限则删除最旧的
    this.snapshots.push(snapshot);
    if (this.snapshots.length > this.config.max_snapshots) {
      this.snapshots = this.snapshots.slice(-this.config.max_snapshots);
    }

    return snapshot;
  }

  /**
   * 加载指定会话的快照（从内存）
   *
   * @param sessionId - 要加载的会话 ID
   * @returns 匹配的最新快照，未找到返回 null
   */
  loadSnapshot(sessionId: string): SessionSnapshot | null {
    // 查找该会话 ID 的最新快照
    const matching = this.snapshots.filter((s) => s.session_id === sessionId);
    if (matching.length === 0) {
      return null;
    }
    return matching[matching.length - 1];
  }

  /**
   * 记录任务执行结果
   *
   * @param result - 任务执行结果
   */
  recordTaskResult(result: TaskResult): void {
    this.taskResults.set(result.task_id, result);
  }

  /**
   * 获取指定任务的执行结果
   *
   * @param taskId - 任务唯一标识
   * @returns TaskResult 对象，不存在返回 null
   */
  getTaskResult(taskId: string): TaskResult | null {
    return this.taskResults.get(taskId) ?? null;
  }

  /**
   * 获取所有任务执行结果
   *
   * @returns TaskResult 数组
   */
  getAllResults(): TaskResult[] {
    return Array.from(this.taskResults.values());
  }

  /**
   * 获取当前任务图
   *
   * @returns 当前 TaskGraph 对象，未设置返回 null
   */
  getGraph(): TaskGraph | null {
    return this.graph;
  }

  /**
   * 更新当前任务图
   *
   * 用于在执行过程中反映任务状态变化（如节点状态更新）。
   *
   * @param graph - 更新后的任务图
   */
  updateGraph(graph: TaskGraph): void {
    this.graph = graph;
  }

  /**
   * 获取所有保存的快照
   *
   * @returns SessionSnapshot 数组
   */
  getSnapshots(): SessionSnapshot[] {
    return [...this.snapshots];
  }

  /**
   * 重置会话状态
   *
   * 清除会话 ID、任务图、结果和快照，停止自动保存。
   * 用于完全重新开始。
   */
  reset(): void {
    this._stopAutoSave();
    this.sessionId = null;
    this.graph = null;
    this.taskResults.clear();
    this.snapshots = [];
  }

  // ─── 内部方法 ──────────────────────────────────────────

  /**
   * 根据当前任务结果构建指标快照
   *
   * @returns PlatformMetrics 对象
   */
  private _buildCurrentMetrics(): PlatformMetrics {
    const results = Array.from(this.taskResults.values());

    const completed = results.filter((r) => r.status === 'completed').length;
    const failed = results.filter((r) => r.status === 'failed').length;
    const inProgress = results.filter((r) => r.status === 'in_progress').length;
    const pending = results.filter(
      (r) => r.status === 'pending' || r.status === 'ready',
    ).length;

    const totalCost = results.reduce((sum, r) => sum + r.cost, 0);
    const costByTier: Record<ModelTier, number> = {
      'tier-1': 0,
      'tier-2': 0,
      'tier-3': 0,
    };
    for (const r of results) {
      costByTier[r.model_tier_used] += r.cost;
    }

    const durations = results.filter((r) => r.duration_ms > 0).map((r) => r.duration_ms);
    const totalDuration = durations.reduce((sum, d) => sum + d, 0);
    const avgDuration = durations.length > 0 ? totalDuration / durations.length : 0;

    // 从 verifier_scores 汇总验证指标
    let verificationsTotal = 0;
    let verificationsPassed = 0;
    let totalScore = 0;
    for (const r of results) {
      const scores = Object.values(r.verifier_scores);
      for (const score of scores) {
        verificationsTotal++;
        totalScore += score;
        // 评分 >= 70 视为通过
        if (score >= 70) {
          verificationsPassed++;
        }
      }
    }

    return {
      tasks_total: results.length,
      tasks_pending: pending,
      tasks_in_progress: inProgress,
      tasks_completed: completed,
      tasks_failed: failed,
      workers_active: 0,
      workers_idle: 0,
      total_cost: totalCost,
      cost_by_tier: costByTier,
      verifications_total: verificationsTotal,
      verifications_passed: verificationsPassed,
      verifications_failed: verificationsTotal - verificationsPassed,
      average_score: verificationsTotal > 0 ? totalScore / verificationsTotal : 0,
      avg_task_duration_ms: avgDuration,
      total_duration_ms: totalDuration,
    };
  }

  /**
   * 启动自动保存定时器
   */
  private _startAutoSave(): void {
    this._stopAutoSave();
    this.autoSaveTimer = setInterval(() => {
      try {
        this.saveSnapshot();
      } catch {
        // 自动保存失败时静默处理（可能会话已重置）
      }
    }, this.config.save_interval_ms);
  }

  /**
   * 停止自动保存定时器
   */
  private _stopAutoSave(): void {
    if (this.autoSaveTimer !== null) {
      clearInterval(this.autoSaveTimer);
      this.autoSaveTimer = null;
    }
  }
}
