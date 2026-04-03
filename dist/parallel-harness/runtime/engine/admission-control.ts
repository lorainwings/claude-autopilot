/**
 * parallel-harness: Admission Control
 *
 * 批前预算预留与准入控制。
 * 在调度批次执行前预估成本，余额不足时拒绝执行。
 */

import type { CostLedger, CostBudget } from "../schemas/ga-schemas";
import type { TaskNode, ModelTier } from "../orchestrator/task-graph";

/** 默认每 task 预估 token 消耗 */
const DEFAULT_ESTIMATED_TOKENS_PER_TASK = 2000;

/** tier 费率映射（与 orchestrator-runtime.ts recordCost 保持一致） */
const TIER_COST_RATE: Record<ModelTier, number> = {
  "tier-1": 1,
  "tier-2": 5,
  "tier-3": 25,
};

export interface AdmissionResult {
  admitted: boolean;
  estimated_cost: number;
  remaining_budget: number;
  reason?: string;
}

/**
 * 预估一个 batch 的成本
 */
export function estimateBatchCost(
  batch: TaskNode[],
  estimatedTokensPerTask: number = DEFAULT_ESTIMATED_TOKENS_PER_TASK
): number {
  let totalCost = 0;
  for (const task of batch) {
    const tier = task.model_tier || "tier-2";
    const rate = TIER_COST_RATE[tier] || TIER_COST_RATE["tier-2"];
    totalCost += (estimatedTokensPerTask / 1000) * rate;
  }
  return totalCost;
}

/**
 * 批前准入检查：余额是否足够执行此 batch
 */
export function admitBatch(
  ledger: CostLedger,
  estimatedCost: number
): AdmissionResult {
  const remaining = ledger.remaining_budget;

  if (remaining <= 0) {
    return {
      admitted: false,
      estimated_cost: estimatedCost,
      remaining_budget: remaining,
      reason: `预算已耗尽: 余额 ${remaining.toFixed(2)}，无法执行任何批次`,
    };
  }

  if (estimatedCost > remaining) {
    return {
      admitted: false,
      estimated_cost: estimatedCost,
      remaining_budget: remaining,
      reason: `预算不足: 预估成本 ${estimatedCost.toFixed(2)}，余额 ${remaining.toFixed(2)}`,
    };
  }

  return {
    admitted: true,
    estimated_cost: estimatedCost,
    remaining_budget: remaining,
  };
}

/**
 * 检查单个任务是否可准入
 */
export function admitTask(
  ledger: CostLedger,
  task: TaskNode,
  estimatedTokens: number = DEFAULT_ESTIMATED_TOKENS_PER_TASK
): AdmissionResult {
  return admitBatch(ledger, estimateBatchCost([task], estimatedTokens));
}

/**
 * P0-2: 使用 CostBudget 进行准入检查（替代 CostLedger 的结构化方式）
 */
export function admitBatchWithCostBudget(
  costBudget: CostBudget,
  estimatedCost: number
): AdmissionResult {
  const remaining = costBudget.remaining_cost_units;

  if (remaining <= 0) {
    return {
      admitted: false,
      estimated_cost: estimatedCost,
      remaining_budget: remaining,
      reason: `成本预算已耗尽: 余额 ${remaining.toFixed(2)} 单位，无法执行任何批次`,
    };
  }

  if (estimatedCost > remaining) {
    return {
      admitted: false,
      estimated_cost: estimatedCost,
      remaining_budget: remaining,
      reason: `成本预算不足: 预估成本 ${estimatedCost.toFixed(2)} 单位，余额 ${remaining.toFixed(2)} 单位`,
    };
  }

  return {
    admitted: true,
    estimated_cost: estimatedCost,
    remaining_budget: remaining,
  };
}

/**
 * P0-2: 使用 CostBudget 检查单个任务是否可准入
 */
export function admitTaskWithCostBudget(
  costBudget: CostBudget,
  task: TaskNode,
  estimatedTokens: number = DEFAULT_ESTIMATED_TOKENS_PER_TASK
): AdmissionResult {
  return admitBatchWithCostBudget(costBudget, estimateBatchCost([task], estimatedTokens));
}
