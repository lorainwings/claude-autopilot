/**
 * 重试管理器
 *
 * 管理任务失败后的重试策略，包括：
 * - 根据错误类型判断是否可重试
 * - 基于退避策略（固定/线性/指数）计算重试延迟
 * - 维护每个任务的重试历史记录
 */

// ─── 重试策略配置 ───────────────────────────────────────

/** 重试策略 */
export interface RetryPolicy {
  /** 最大重试次数 */
  max_retries: number;
  /** 退避策略 */
  backoff_strategy: 'fixed' | 'exponential' | 'linear';
  /** 基础延迟（毫秒），用于退避计算 */
  base_delay_ms: number;
  /** 最大延迟上限（毫秒），防止退避时间过长 */
  max_delay_ms: number;
  /** 可重试的错误模式列表（子串匹配） */
  retryable_errors: string[];
}

/** 默认重试策略 */
const DEFAULT_RETRY_POLICY: RetryPolicy = {
  max_retries: 3,
  backoff_strategy: 'exponential',
  base_delay_ms: 1_000,
  max_delay_ms: 30_000,
  retryable_errors: ['timeout', 'rate_limit', 'temporary', 'ECONNRESET'],
};

// ─── 重试记录 ───────────────────────────────────────────

/** 单次重试记录 */
export interface RetryRecord {
  /** 关联的任务 id */
  task_id: string;
  /** 当前是第几次重试 */
  attempt: number;
  /** 导致重试的错误信息 */
  error: string;
  /** 记录时间（ISO 8601） */
  timestamp: string;
  /** 下次重试的预计时间（ISO 8601）；如果不再重试则为 undefined */
  next_retry_at?: string;
}

// ─── 重试管理器实现 ─────────────────────────────────────

export class RetryManager {
  /** 当前生效的重试策略 */
  private readonly policy: RetryPolicy;

  /** 每个任务的重试历史：task_id → RetryRecord[] */
  private readonly records: Map<string, RetryRecord[]> = new Map();

  constructor(policy?: Partial<RetryPolicy>) {
    this.policy = { ...DEFAULT_RETRY_POLICY, ...policy };
  }

  // ── 重试决策 ────────────────────────────────────────────

  /**
   * 判断指定任务是否应该重试。
   *
   * 条件同时满足才返回 true：
   *   1. 错误类型属于可重试范围
   *   2. 当前重试次数未达到上限
   *
   * @param taskId - 任务 id
   * @param error  - 错误信息
   */
  shouldRetry(taskId: string, error: string): boolean {
    // 错误类型必须可重试
    if (!this.isRetryable(error)) {
      return false;
    }

    // 重试次数必须未达上限
    const count = this.getRetryCount(taskId);
    return count < this.policy.max_retries;
  }

  /**
   * 判断错误信息是否匹配可重试模式。
   *
   * 采用不区分大小写的子串匹配：只要错误信息中
   * 包含 retryable_errors 列表中的任意一个模式即可。
   *
   * @param error - 错误信息
   */
  isRetryable(error: string): boolean {
    const lowerError = error.toLowerCase();
    return this.policy.retryable_errors.some((pattern) =>
      lowerError.includes(pattern.toLowerCase()),
    );
  }

  // ── 记录管理 ────────────────────────────────────────────

  /**
   * 记录一次任务失败。
   *
   * 自动递增重试计数，计算下次重试延迟，
   * 并将记录追加到该任务的重试历史中。
   *
   * @param taskId - 任务 id
   * @param error  - 错误信息
   * @returns 本次创建的重试记录
   */
  recordFailure(taskId: string, error: string): RetryRecord {
    const history = this.records.get(taskId) ?? [];
    const attempt = history.length + 1;
    const now = new Date();

    // 如果还能重试，计算下次重试时间
    let nextRetryAt: string | undefined;
    if (attempt < this.policy.max_retries && this.isRetryable(error)) {
      const delay = this.computeDelay(attempt);
      nextRetryAt = new Date(now.getTime() + delay).toISOString();
    }

    const record: RetryRecord = {
      task_id: taskId,
      attempt,
      error,
      timestamp: now.toISOString(),
      next_retry_at: nextRetryAt,
    };

    history.push(record);
    this.records.set(taskId, history);

    return record;
  }

  /**
   * 计算指定任务下次重试的延迟（毫秒）。
   *
   * 如果该任务没有重试记录，返回基础延迟。
   *
   * @param taskId - 任务 id
   */
  getRetryDelay(taskId: string): number {
    const count = this.getRetryCount(taskId);
    // 用当前重试次数计算下一次的延迟
    return this.computeDelay(count + 1);
  }

  /** 获取指定任务当前的重试次数 */
  getRetryCount(taskId: string): number {
    return this.records.get(taskId)?.length ?? 0;
  }

  /** 获取指定任务的完整重试历史 */
  getRetryHistory(taskId: string): RetryRecord[] {
    return [...(this.records.get(taskId) ?? [])];
  }

  /**
   * 清除指定任务的重试记录。
   *
   * 通常在任务成功完成后调用，
   * 以便该任务未来如果被重新执行时从零开始计数。
   *
   * @param taskId - 任务 id
   */
  resetRetries(taskId: string): void {
    this.records.delete(taskId);
  }

  // ── 只读访问器 ──────────────────────────────────────────

  /** 获取当前策略（只读副本） */
  getPolicy(): Readonly<RetryPolicy> {
    return { ...this.policy };
  }

  // ── 内部辅助 ────────────────────────────────────────────

  /**
   * 根据退避策略计算第 n 次重试的延迟。
   *
   * 三种策略：
   * - fixed:       始终返回 base_delay_ms
   * - linear:      base_delay_ms * attempt
   * - exponential: base_delay_ms * 2^(attempt-1)
   *
   * 结果不会超过 max_delay_ms。
   *
   * @param attempt - 第几次重试（从 1 开始）
   */
  private computeDelay(attempt: number): number {
    let delay: number;

    switch (this.policy.backoff_strategy) {
      case 'fixed':
        delay = this.policy.base_delay_ms;
        break;

      case 'linear':
        delay = this.policy.base_delay_ms * attempt;
        break;

      case 'exponential':
        // 2^(attempt-1) 的指数退避
        delay = this.policy.base_delay_ms * Math.pow(2, attempt - 1);
        break;
    }

    // 限制上限
    return Math.min(delay, this.policy.max_delay_ms);
  }
}
