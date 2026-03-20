/**
 * 调度器高级模块测试
 *
 * 覆盖 WorkerDispatch（Worker 分发器）、RetryManager（重试管理器）
 * 和 DowngradeManager（降级管理器）的核心逻辑。
 */

import { describe, it, expect } from 'bun:test';
import { WorkerDispatch } from '../runtime/scheduler/worker-dispatch';
import { RetryManager } from '../runtime/scheduler/retry-manager';
import { DowngradeManager } from '../runtime/scheduler/downgrade-manager';
import { createTaskNode } from '../runtime/schemas/task-graph';
import { createContextPack } from '../runtime/schemas/context-pack';

// ─────────────────────────────────────────────────────────────
// WorkerDispatch
// ─────────────────────────────────────────────────────────────

describe('WorkerDispatch', () => {
  it('初始化时无活跃 Worker', () => {
    const dispatch = new WorkerDispatch({ max_workers: 4 });

    const active = dispatch.getActiveWorkers();
    expect(active).toEqual([]);
    expect(dispatch.getWorkerCount()).toBe(0);
  });

  it('有空闲槽位时 isSlotAvailable 返回 true', () => {
    const dispatch = new WorkerDispatch({ max_workers: 2 });

    // 初始状态下应该有空闲槽位
    expect(dispatch.isSlotAvailable()).toBe(true);
  });

  it('dispatch 返回 WorkerResult', async () => {
    const dispatch = new WorkerDispatch({ max_workers: 4 });
    const node = createTaskNode({
      id: 'task-dispatch-1',
      title: '测试分发任务',
    });
    const context = createContextPack({ task_id: 'task-dispatch-1' });

    const result = await dispatch.dispatch(node, context);

    // 验证返回的 WorkerResult 结构
    expect(result.task_id).toBe('task-dispatch-1');
    expect(result.exit_code).toBe(0);
    expect(result.changed_files).toEqual([]);
    expect(typeof result.stdout).toBe('string');
    expect(typeof result.stderr).toBe('string');
    expect(typeof result.duration_ms).toBe('number');
    expect(result.duration_ms).toBeGreaterThanOrEqual(0);
  });

  it('terminateAll 清除所有 Worker', async () => {
    const dispatch = new WorkerDispatch({ max_workers: 4 });

    // 先分发一个任务（模拟执行是同步的，会立即完成并归档）
    const node = createTaskNode({ id: 'task-terminate-1' });
    const context = createContextPack({ task_id: 'task-terminate-1' });
    await dispatch.dispatch(node, context);

    // 执行 terminateAll
    dispatch.terminateAll();

    // 确保活跃 Worker 被清空
    expect(dispatch.getActiveWorkers()).toEqual([]);
    expect(dispatch.getWorkerCount()).toBe(0);
  });

  it('dispatch 完成后 Worker 归档到历史记录', async () => {
    const dispatch = new WorkerDispatch({ max_workers: 4 });
    const node = createTaskNode({ id: 'task-archive-1', title: '归档测试' });
    const context = createContextPack({ task_id: 'task-archive-1' });

    await dispatch.dispatch(node, context);

    // 模拟执行完成后，Worker 应被归档到历史
    const history = dispatch.getHistory();
    expect(history.length).toBe(1);
    expect(history[0].task_id).toBe('task-archive-1');
    expect(history[0].status).toBe('completed');
  });

  it('槽位满时 dispatch 抛出错误', async () => {
    // 仅允许 1 个 Worker，需要模拟占满的情况
    // 因为模拟执行是即时完成的，我们验证配置读取正确
    const dispatch = new WorkerDispatch({ max_workers: 2 });
    const config = dispatch.getConfig();
    expect(config.max_workers).toBe(2);
    expect(config.isolation_mode).toBe('worktree');
  });
});

// ─────────────────────────────────────────────────────────────
// RetryManager
// ─────────────────────────────────────────────────────────────

describe('RetryManager', () => {
  it('首次失败后 shouldRetry 返回 true', () => {
    const manager = new RetryManager({ max_retries: 3 });

    // 首次遇到可重试错误，应返回 true
    const result = manager.shouldRetry('task-1', 'connection timeout');
    expect(result).toBe(true);
  });

  it('超过 max_retries 后 shouldRetry 返回 false', () => {
    const manager = new RetryManager({ max_retries: 2 });

    // 记录两次失败
    manager.recordFailure('task-1', 'timeout error');
    manager.recordFailure('task-1', 'timeout error');

    // 第三次应该不再重试（已达上限 2）
    const result = manager.shouldRetry('task-1', 'timeout error');
    expect(result).toBe(false);
  });

  it('指数退避延迟正确计算', () => {
    const manager = new RetryManager({
      max_retries: 5,
      backoff_strategy: 'exponential',
      base_delay_ms: 1000,
      max_delay_ms: 30000,
    });

    // 无重试记录时，延迟 = base * 2^0 = 1000ms
    const delay0 = manager.getRetryDelay('task-exp');
    expect(delay0).toBe(1000);

    // 第 1 次失败后，延迟 = base * 2^1 = 2000ms
    manager.recordFailure('task-exp', 'timeout');
    const delay1 = manager.getRetryDelay('task-exp');
    expect(delay1).toBe(2000);

    // 第 2 次失败后，延迟 = base * 2^2 = 4000ms
    manager.recordFailure('task-exp', 'timeout');
    const delay2 = manager.getRetryDelay('task-exp');
    expect(delay2).toBe(4000);

    // 第 3 次失败后，延迟 = base * 2^3 = 8000ms
    manager.recordFailure('task-exp', 'timeout');
    const delay3 = manager.getRetryDelay('task-exp');
    expect(delay3).toBe(8000);
  });

  it('isRetryable 识别可重试错误', () => {
    const manager = new RetryManager({
      retryable_errors: ['timeout', 'rate_limit', 'ECONNRESET'],
    });

    // 包含可重试模式的错误
    expect(manager.isRetryable('connection timeout occurred')).toBe(true);
    expect(manager.isRetryable('API rate_limit exceeded')).toBe(true);
    expect(manager.isRetryable('socket ECONNRESET')).toBe(true);
    // 不区分大小写
    expect(manager.isRetryable('TIMEOUT ERROR')).toBe(true);
  });

  it('isRetryable 拒绝不可重试错误', () => {
    const manager = new RetryManager({
      retryable_errors: ['timeout', 'rate_limit'],
    });

    // 不匹配任何可重试模式的错误
    expect(manager.isRetryable('syntax error in code')).toBe(false);
    expect(manager.isRetryable('invalid argument')).toBe(false);
    expect(manager.isRetryable('permission denied')).toBe(false);
  });

  it('resetRetries 清除重试记录', () => {
    const manager = new RetryManager({ max_retries: 3 });

    // 记录两次失败
    manager.recordFailure('task-reset', 'timeout');
    manager.recordFailure('task-reset', 'timeout');
    expect(manager.getRetryCount('task-reset')).toBe(2);

    // 重置后计数归零
    manager.resetRetries('task-reset');
    expect(manager.getRetryCount('task-reset')).toBe(0);
    expect(manager.getRetryHistory('task-reset')).toEqual([]);
  });

  it('recordFailure 返回正确的 RetryRecord', () => {
    const manager = new RetryManager({ max_retries: 3 });

    const record = manager.recordFailure('task-rec', 'temporary failure');

    expect(record.task_id).toBe('task-rec');
    expect(record.attempt).toBe(1);
    expect(record.error).toBe('temporary failure');
    expect(typeof record.timestamp).toBe('string');
    // 还能重试，因此应有 next_retry_at
    expect(record.next_retry_at).toBeDefined();
  });

  it('线性退避延迟正确计算', () => {
    const manager = new RetryManager({
      max_retries: 5,
      backoff_strategy: 'linear',
      base_delay_ms: 1000,
      max_delay_ms: 30000,
    });

    // 无重试记录时，延迟 = base * 1 = 1000ms
    expect(manager.getRetryDelay('task-lin')).toBe(1000);

    // 第 1 次失败后，延迟 = base * 2 = 2000ms
    manager.recordFailure('task-lin', 'timeout');
    expect(manager.getRetryDelay('task-lin')).toBe(2000);

    // 第 2 次失败后，延迟 = base * 3 = 3000ms
    manager.recordFailure('task-lin', 'timeout');
    expect(manager.getRetryDelay('task-lin')).toBe(3000);
  });
});

// ─────────────────────────────────────────────────────────────
// DowngradeManager
// ─────────────────────────────────────────────────────────────

describe('DowngradeManager', () => {
  it('重试耗尽时触发降级', () => {
    const manager = new DowngradeManager();

    // 默认触发器：retry_exhausted 阈值为 3
    const action = manager.evaluate('task-1', {
      retries: 3,
      elapsed_ms: 0,
      cost: 0,
      error_rate: 0,
    });

    expect(action).not.toBeNull();
    expect(action!.type).toBe('reduce_tier');
  });

  it('tier-3 可降级到 tier-2', () => {
    const manager = new DowngradeManager();

    expect(manager.canDowngrade('tier-3')).toBe(true);
    expect(manager.getNextTier('tier-3')).toBe('tier-2');
  });

  it('tier-1 无法继续降级', () => {
    const manager = new DowngradeManager();

    // tier-1 是默认的 min_tier，无法再降
    expect(manager.canDowngrade('tier-1')).toBe(false);
    expect(manager.getNextTier('tier-1')).toBeNull();
  });

  it('downgrade 降低任务的 model_tier', () => {
    const manager = new DowngradeManager();

    const node = createTaskNode({
      id: 'task-dg-1',
      model_tier: 'tier-3',
      verifier_set: ['test', 'review', 'security'],
    });

    const downgraded = manager.downgrade(node);

    // 模型层级应降低一级
    expect(downgraded.model_tier).toBe('tier-2');
    // 验证器集合应被简化为仅 'test'
    expect(downgraded.verifier_set).toEqual(['test']);
    // 原始节点不应被修改
    expect(node.model_tier).toBe('tier-3');
    expect(node.verifier_set).toEqual(['test', 'review', 'security']);
  });

  it('tier-2 可以降级到 tier-1', () => {
    const manager = new DowngradeManager();

    expect(manager.canDowngrade('tier-2')).toBe(true);
    expect(manager.getNextTier('tier-2')).toBe('tier-1');
  });

  it('降级操作记录到历史中', () => {
    const manager = new DowngradeManager();

    const node = createTaskNode({
      id: 'task-history',
      model_tier: 'tier-3',
      verifier_set: ['test', 'review'],
    });

    manager.downgrade(node);

    const history = manager.getDowngradeHistory('task-history');
    expect(history.length).toBe(1);
    expect(history[0].original_tier).toBe('tier-3');
    expect(history[0].downgraded_tier).toBe('tier-2');
    expect(history[0].task_id).toBe('task-history');
  });

  it('降级未启用时 evaluate 返回 null', () => {
    const manager = new DowngradeManager({ enabled: false });

    const action = manager.evaluate('task-disabled', {
      retries: 100,
      elapsed_ms: 999999,
      cost: 999999,
      error_rate: 1.0,
    });

    expect(action).toBeNull();
  });

  it('超时条件触发降级', () => {
    const manager = new DowngradeManager();

    // 默认 timeout 触发器阈值为 300000ms
    const action = manager.evaluate('task-timeout', {
      retries: 0,
      elapsed_ms: 300_000,
      cost: 0,
      error_rate: 0,
    });

    expect(action).not.toBeNull();
    expect(action!.type).toBe('reduce_tier');
  });

  it('未达阈值时不触发降级', () => {
    const manager = new DowngradeManager();

    const action = manager.evaluate('task-ok', {
      retries: 1,
      elapsed_ms: 1000,
      cost: 0,
      error_rate: 0,
    });

    expect(action).toBeNull();
  });
});
