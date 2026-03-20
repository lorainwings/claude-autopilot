/**
 * 复杂度评分器
 *
 * 对单个任务或整个图进行复杂度评分，推荐模型层级
 */

import type { ModelTier } from '../schemas/types.js';
import type { TaskNode, TaskGraph } from '../schemas/task-graph.js';

/** 风险权重映射 */
const RISK_WEIGHTS: Record<string, number> = {
  low: 1,
  medium: 2,
  high: 3,
  critical: 5,
};

/**
 * 对单个任务进行复杂度评分（0-10 范围）
 */
export function scoreComplexity(task: TaskNode): number {
  let score = 0;

  // 依赖数量影响复杂度
  score += Math.min(task.dependencies.length * 0.5, 2);

  // 允许路径数量
  score += Math.min(task.allowed_paths.length * 0.3, 2);

  // 验收条件和测试数量
  score += Math.min(task.acceptance_criteria.length * 0.2, 1);
  score += Math.min(task.required_tests.length * 0.2, 1);

  // 风险等级
  score += RISK_WEIGHTS[task.risk_level] ?? 1;

  // 验证器数量
  score += Math.min(task.verifier_set.length * 0.3, 1.5);

  // 限制在 0-10 范围
  return Math.min(Math.max(score, 0), 10);
}

/**
 * 根据复杂度评分推荐模型层级
 */
export function recommendModelTier(complexityScore: number): ModelTier {
  if (complexityScore >= 6) return 'tier-3';
  if (complexityScore >= 3) return 'tier-2';
  return 'tier-1';
}

/**
 * 对整个任务图进行评分
 */
export function scoreTaskGraph(graph: TaskGraph): {
  total: number;
  average: number;
  max: number;
  scores: Map<string, number>;
} {
  const scores = new Map<string, number>();
  let total = 0;
  let max = 0;

  for (const node of graph.nodes) {
    const s = scoreComplexity(node);
    scores.set(node.id, s);
    total += s;
    max = Math.max(max, s);
  }

  return {
    total,
    average: graph.nodes.length > 0 ? total / graph.nodes.length : 0,
    max,
    scores,
  };
}
