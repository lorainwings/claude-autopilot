/**
 * 成本控制与升级策略测试
 *
 * 覆盖 CostController（成本控制器）和 EscalationPolicy（升级策略）
 * 的核心逻辑，包括预算管理、预警触发、模型层级升级等。
 */

import { describe, it, expect } from 'bun:test';
import { CostController } from '../runtime/models/cost-controller';
import { EscalationPolicy } from '../runtime/models/escalation-policy';

// ─────────────────────────────────────────────────────────────
// CostController
// ─────────────────────────────────────────────────────────────

describe('CostController', () => {
  it('记录使用后更新状态', () => {
    const controller = new CostController({
      max_total_cost: 100,
      warning_threshold: 0.8,
      hard_limit: true,
    });

    // 记录一次使用
    const record = controller.recordUsage({
      task_id: 'task-1',
      model_tier: 'tier-2',
      input_tokens: 1000,
      output_tokens: 500,
      cost: 0.05,
    });

    // 验证记录结构
    expect(record.task_id).toBe('task-1');
    expect(record.cost).toBe(0.05);
    expect(typeof record.timestamp).toBe('string');

    // 验证状态更新
    const status = controller.getStatus();
    expect(status.total_spent).toBe(0.05);
    expect(status.remaining).toBeCloseTo(99.95);
    expect(status.total_budget).toBe(100);
    expect(status.is_exceeded).toBe(false);
    expect(status.is_warning).toBe(false);
  });

  it('超预算时 canAfford 返回 false', () => {
    const controller = new CostController({
      max_total_cost: 1.0,
      hard_limit: true,
    });

    // 消耗 0.8
    controller.recordUsage({
      task_id: 'task-1',
      model_tier: 'tier-2',
      input_tokens: 5000,
      output_tokens: 3000,
      cost: 0.8,
    });

    // 还能承担 0.15（剩余 0.2）
    expect(controller.canAfford(0.15)).toBe(true);

    // 无法承担 0.25（超过剩余的 0.2）
    expect(controller.canAfford(0.25)).toBe(false);
  });

  it('获取单任务成本正确', () => {
    const controller = new CostController({ max_total_cost: 100 });

    // 为同一任务记录多次使用
    controller.recordUsage({
      task_id: 'task-a',
      model_tier: 'tier-1',
      input_tokens: 100,
      output_tokens: 50,
      cost: 0.01,
    });
    controller.recordUsage({
      task_id: 'task-a',
      model_tier: 'tier-2',
      input_tokens: 200,
      output_tokens: 100,
      cost: 0.03,
    });
    controller.recordUsage({
      task_id: 'task-b',
      model_tier: 'tier-3',
      input_tokens: 500,
      output_tokens: 300,
      cost: 0.10,
    });

    // task-a 累计 0.01 + 0.03 = 0.04
    expect(controller.getTaskCost('task-a')).toBeCloseTo(0.04);
    // task-b 累计 0.10
    expect(controller.getTaskCost('task-b')).toBeCloseTo(0.10);
    // 不存在的任务返回 0
    expect(controller.getTaskCost('task-nonexistent')).toBe(0);
  });

  it('预警阈值正确触发', () => {
    const controller = new CostController({
      max_total_cost: 10.0,
      warning_threshold: 0.8,
      hard_limit: false,
    });

    // 消耗 7.5（75%），未触发预警
    controller.recordUsage({
      task_id: 'task-1',
      model_tier: 'tier-2',
      input_tokens: 5000,
      output_tokens: 3000,
      cost: 7.5,
    });
    let status = controller.getStatus();
    expect(status.utilization).toBeCloseTo(0.75);
    expect(status.is_warning).toBe(false);
    expect(status.is_exceeded).toBe(false);

    // 再消耗 1.0（总计 85%），触发预警
    controller.recordUsage({
      task_id: 'task-2',
      model_tier: 'tier-2',
      input_tokens: 2000,
      output_tokens: 1000,
      cost: 1.0,
    });
    status = controller.getStatus();
    expect(status.utilization).toBeCloseTo(0.85);
    expect(status.is_warning).toBe(true);
    expect(status.is_exceeded).toBe(false);

    // 再消耗 2.0（总计 105%），超预算
    controller.recordUsage({
      task_id: 'task-3',
      model_tier: 'tier-3',
      input_tokens: 3000,
      output_tokens: 2000,
      cost: 2.0,
    });
    status = controller.getStatus();
    expect(status.is_exceeded).toBe(true);
    expect(status.remaining).toBe(0);
  });

  it('reset 清除所有记录', () => {
    const controller = new CostController({ max_total_cost: 50 });

    // 记录若干使用
    controller.recordUsage({
      task_id: 'task-1',
      model_tier: 'tier-1',
      input_tokens: 100,
      output_tokens: 50,
      cost: 5.0,
    });
    controller.recordUsage({
      task_id: 'task-2',
      model_tier: 'tier-2',
      input_tokens: 200,
      output_tokens: 100,
      cost: 10.0,
    });

    // 重置前验证有记录
    expect(controller.getStatus().total_spent).toBe(15.0);
    expect(controller.getStatus().records.length).toBe(2);

    // 重置
    controller.reset();

    // 重置后验证状态归零
    const status = controller.getStatus();
    expect(status.total_spent).toBe(0);
    expect(status.remaining).toBe(50);
    expect(status.records).toEqual([]);
    expect(status.is_warning).toBe(false);
    expect(status.is_exceeded).toBe(false);
  });

  it('非硬性限制模式下 canAfford 始终返回 true', () => {
    const controller = new CostController({
      max_total_cost: 1.0,
      hard_limit: false,
    });

    // 即使已超预算，非硬性限制下也允许
    controller.recordUsage({
      task_id: 'task-1',
      model_tier: 'tier-3',
      input_tokens: 10000,
      output_tokens: 5000,
      cost: 100.0,
    });

    expect(controller.canAfford(50.0)).toBe(true);
  });

  it('getRemainingBudget 返回正确的剩余预算', () => {
    const controller = new CostController({ max_total_cost: 20 });

    controller.recordUsage({
      task_id: 'task-1',
      model_tier: 'tier-2',
      input_tokens: 1000,
      output_tokens: 500,
      cost: 8.0,
    });

    expect(controller.getRemainingBudget()).toBeCloseTo(12.0);

    // 超支时剩余为 0
    controller.recordUsage({
      task_id: 'task-2',
      model_tier: 'tier-3',
      input_tokens: 5000,
      output_tokens: 3000,
      cost: 15.0,
    });

    expect(controller.getRemainingBudget()).toBe(0);
  });
});

// ─────────────────────────────────────────────────────────────
// EscalationPolicy
// ─────────────────────────────────────────────────────────────

describe('EscalationPolicy', () => {
  it('tier-1 失败时升级到 tier-2', () => {
    const policy = new EscalationPolicy();

    const result = policy.evaluate('task-1', {
      current_tier: 'tier-1',
      trigger: 'verification_failed',
    });

    expect(result).toBe('tier-2');
  });

  it('tier-2 失败时升级到 tier-3', () => {
    const policy = new EscalationPolicy();

    const result = policy.evaluate('task-2', {
      current_tier: 'tier-2',
      trigger: 'verification_failed',
    });

    expect(result).toBe('tier-3');
  });

  it('tier-3 无法继续升级', () => {
    const policy = new EscalationPolicy();

    // tier-3 是最高层级，canEscalate 返回 false
    expect(policy.canEscalate('tier-3')).toBe(false);

    // evaluate 也应返回 null
    const result = policy.evaluate('task-3', {
      current_tier: 'tier-3',
      trigger: 'verification_failed',
    });

    expect(result).toBeNull();
  });

  it('低分数触发升级', () => {
    const policy = new EscalationPolicy();

    // 默认规则：tier-1 质量低于 60 分 → 升级到 tier-2
    const result = policy.evaluate('task-quality', {
      current_tier: 'tier-1',
      trigger: 'quality_below_threshold',
      score: 45,
    });

    expect(result).toBe('tier-2');
  });

  it('高分数不触发升级', () => {
    const policy = new EscalationPolicy();

    // 分数 >= 60 不应触发 quality_below_threshold 升级
    const result = policy.evaluate('task-quality-ok', {
      current_tier: 'tier-1',
      trigger: 'quality_below_threshold',
      score: 75,
    });

    expect(result).toBeNull();
  });

  it('记录升级历史', () => {
    const policy = new EscalationPolicy();

    // 记录一次升级
    const record = policy.recordEscalation(
      'task-esc-1',
      'tier-1',
      'tier-2',
      '验证失败导致升级',
    );

    expect(record.task_id).toBe('task-esc-1');
    expect(record.from_tier).toBe('tier-1');
    expect(record.to_tier).toBe('tier-2');
    expect(record.trigger).toBe('验证失败导致升级');
    expect(typeof record.timestamp).toBe('string');

    // 再记录一次
    policy.recordEscalation(
      'task-esc-1',
      'tier-2',
      'tier-3',
      '二次验证失败',
    );

    // 查询历史记录
    const history = policy.getEscalationHistory('task-esc-1');
    expect(history.length).toBe(2);
    expect(history[0].from_tier).toBe('tier-1');
    expect(history[1].from_tier).toBe('tier-2');
  });

  it('canEscalate 和 getNextTier 一致', () => {
    const policy = new EscalationPolicy();

    // tier-1 → tier-2
    expect(policy.canEscalate('tier-1')).toBe(true);
    expect(policy.getNextTier('tier-1')).toBe('tier-2');

    // tier-2 → tier-3
    expect(policy.canEscalate('tier-2')).toBe(true);
    expect(policy.getNextTier('tier-2')).toBe('tier-3');

    // tier-3 → null（无更高层级）
    expect(policy.canEscalate('tier-3')).toBe(false);
    expect(policy.getNextTier('tier-3')).toBeNull();
  });

  it('task_failed 需满足重试次数条件', () => {
    const policy = new EscalationPolicy();

    // 默认规则：tier-1 task_failed 需要重试 >= 2 次
    // 重试次数不足时不应升级
    const noUpgrade = policy.evaluate('task-retry', {
      current_tier: 'tier-1',
      trigger: 'task_failed',
      retries: 1,
    });
    expect(noUpgrade).toBeNull();

    // 重试次数达到阈值时应升级
    const upgrade = policy.evaluate('task-retry', {
      current_tier: 'tier-1',
      trigger: 'task_failed',
      retries: 2,
    });
    expect(upgrade).toBe('tier-2');
  });
});
