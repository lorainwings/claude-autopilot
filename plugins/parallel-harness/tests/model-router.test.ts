/**
 * 模型路由器测试
 *
 * 覆盖 ModelRouter 的风险等级路由、复杂度路由、
 * 任务类型路由、成本估算和默认配置。
 */

import { describe, it, expect } from 'bun:test';
import { ModelRouter } from '../runtime/models/model-router';
import { createTaskNode, createTaskGraph } from '../runtime/schemas/task-graph';

describe('ModelRouter', () => {
  const router = new ModelRouter();

  it('低风险任务路由到 tier-1', () => {
    const node = createTaskNode({
      id: 'low-risk',
      title: 'search for unused imports',
      risk_level: 'low',
      // 清除 model_tier 以测试路由逻辑（使用无 model_tier 的 node）
      model_tier: undefined as any,
    });
    // 直接测试 routeByRiskLevel
    const tier = router.routeByRiskLevel('low');
    expect(tier).toBe('tier-1');
  });

  it('中等复杂度路由到 tier-2', () => {
    const tier = router.routeByComplexity(4);
    expect(tier).toBe('tier-2');

    // 边界值测试
    const tier3 = router.routeByComplexity(3);
    expect(tier3).toBe('tier-2');
  });

  it('高复杂度/关键任务路由到 tier-3', () => {
    // 高风险 → tier-3
    const tierHigh = router.routeByRiskLevel('high');
    expect(tierHigh).toBe('tier-3');

    // 关键风险 → tier-3
    const tierCritical = router.routeByRiskLevel('critical');
    expect(tierCritical).toBe('tier-3');

    // 复杂度评分高 → tier-3
    const tierComplex = router.routeByComplexity(8);
    expect(tierComplex).toBe('tier-3');
  });

  it('根据任务类型路由', () => {
    // 搜索任务 → tier-1
    expect(router.routeByTaskType('search')).toBe('tier-1');
    expect(router.routeByTaskType('format')).toBe('tier-1');

    // 实现/测试 → tier-2
    expect(router.routeByTaskType('implement')).toBe('tier-2');
    expect(router.routeByTaskType('test')).toBe('tier-2');

    // 规划/设计 → tier-3
    expect(router.routeByTaskType('plan')).toBe('tier-3');
    expect(router.routeByTaskType('architecture')).toBe('tier-3');

    // 未知类型 → 默认 tier-2
    expect(router.routeByTaskType('unknown-type')).toBe('tier-2');
  });

  it('estimateCost 返回合理估算', () => {
    const graph = createTaskGraph({
      nodes: [
        createTaskNode({
          id: 'task-1',
          model_tier: 'tier-1',
          risk_level: 'low',
        }),
        createTaskNode({
          id: 'task-2',
          model_tier: 'tier-2',
          risk_level: 'medium',
        }),
        createTaskNode({
          id: 'task-3',
          model_tier: 'tier-3',
          risk_level: 'high',
        }),
      ],
    });

    const cost = router.estimateCost(graph);

    // 总成本为正数
    expect(cost.total).toBeGreaterThan(0);
    // 各层级成本都存在
    expect(cost.breakdown['tier-1']).toBeGreaterThan(0);
    expect(cost.breakdown['tier-2']).toBeGreaterThan(0);
    expect(cost.breakdown['tier-3']).toBeGreaterThan(0);
    // tier-3 成本应高于 tier-1（旗舰模型更贵）
    expect(cost.breakdown['tier-3']).toBeGreaterThan(cost.breakdown['tier-1']);
    // 总成本等于各层之和
    expect(cost.total).toBeCloseTo(
      cost.breakdown['tier-1'] + cost.breakdown['tier-2'] + cost.breakdown['tier-3'],
      5,
    );
  });

  it('默认模型配置完整', () => {
    // 三个层级的配置都能获取
    const t1 = router.getModelConfig('tier-1');
    const t2 = router.getModelConfig('tier-2');
    const t3 = router.getModelConfig('tier-3');

    // tier-1 配置
    expect(t1.tier).toBe('tier-1');
    expect(t1.model_id).toBeTruthy();
    expect(t1.max_tokens).toBeGreaterThan(0);
    expect(t1.cost_per_1k_tokens).toBeGreaterThan(0);
    expect(t1.capabilities.length).toBeGreaterThan(0);

    // tier-2 配置
    expect(t2.tier).toBe('tier-2');
    expect(t2.model_id).toBeTruthy();
    expect(t2.max_tokens).toBeGreaterThan(t1.max_tokens);

    // tier-3 配置
    expect(t3.tier).toBe('tier-3');
    expect(t3.model_id).toBeTruthy();
    expect(t3.max_tokens).toBeGreaterThan(t2.max_tokens);
    expect(t3.cost_per_1k_tokens).toBeGreaterThan(t2.cost_per_1k_tokens);
  });
});
