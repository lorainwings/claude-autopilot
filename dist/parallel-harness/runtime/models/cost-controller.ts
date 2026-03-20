/**
 * 成本控制器
 *
 * 追踪和控制模型使用成本，提供预算管理、预警和成本估算能力。
 * 确保并行任务执行不会无限消耗 API 额度。
 */

import type { ModelTier } from '../schemas/types.js';
import type { TaskNode } from '../schemas/task-graph.js';
import type { ModelConfig } from './model-router.js';

// ─── 预算策略 ───────────────────────────────────────────

/** 预算策略配置 */
export interface BudgetPolicy {
  /** 总预算上限（美元） */
  max_total_cost: number;
  /** 单任务预算上限（美元） */
  max_per_task_cost: number;
  /** 预警阈值比例 0-1（如 0.8 表示使用 80% 时触发预警） */
  warning_threshold: number;
  /** 是否硬性限制（true = 超预算拒绝执行，false = 仅发出警告） */
  hard_limit: boolean;
}

// ─── 成本记录 ───────────────────────────────────────────

/** 单次模型调用的成本记录 */
export interface CostRecord {
  /** 关联的任务 id */
  task_id: string;
  /** 使用的模型层级 */
  model_tier: ModelTier;
  /** 输入 token 数 */
  input_tokens: number;
  /** 输出 token 数 */
  output_tokens: number;
  /** 本次调用的实际费用（美元） */
  cost: number;
  /** 记录时间戳（ISO 8601 格式） */
  timestamp: string;
}

// ─── 预算状态 ───────────────────────────────────────────

/** 当前预算状态快照 */
export interface BudgetStatus {
  /** 已消费总额（美元） */
  total_spent: number;
  /** 总预算上限（美元） */
  total_budget: number;
  /** 剩余可用额度（美元） */
  remaining: number;
  /** 预算使用率 0-1 */
  utilization: number;
  /** 是否已触发预警 */
  is_warning: boolean;
  /** 是否已超出预算 */
  is_exceeded: boolean;
  /** 所有成本记录 */
  records: CostRecord[];
}

// ─── 默认策略 ───────────────────────────────────────────

/** 默认预算策略 */
const DEFAULT_POLICY: BudgetPolicy = {
  max_total_cost: 50,
  max_per_task_cost: 10,
  warning_threshold: 0.8,
  hard_limit: false,
};

// ─── 成本控制器实现 ─────────────────────────────────────

export class CostController {
  /** 当前生效的预算策略 */
  private readonly policy: BudgetPolicy;

  /** 所有成本记录 */
  private records: CostRecord[] = [];

  constructor(policy?: Partial<BudgetPolicy>) {
    this.policy = { ...DEFAULT_POLICY, ...policy };
  }

  /**
   * 记录一次模型使用的成本
   *
   * 自动添加时间戳并存储记录。
   *
   * @param record - 不含时间戳的成本记录
   * @returns 包含时间戳的完整成本记录
   */
  recordUsage(record: Omit<CostRecord, 'timestamp'>): CostRecord {
    const fullRecord: CostRecord = {
      ...record,
      timestamp: new Date().toISOString(),
    };
    this.records.push(fullRecord);
    return fullRecord;
  }

  /**
   * 获取当前预算状态快照
   *
   * 计算已消费总额、剩余额度、使用率，以及是否触发预警或超出预算。
   */
  getStatus(): BudgetStatus {
    const totalSpent = this.records.reduce((sum, r) => sum + r.cost, 0);
    const remaining = Math.max(0, this.policy.max_total_cost - totalSpent);
    const utilization =
      this.policy.max_total_cost > 0
        ? totalSpent / this.policy.max_total_cost
        : 0;

    return {
      total_spent: totalSpent,
      total_budget: this.policy.max_total_cost,
      remaining,
      utilization,
      is_warning: utilization >= this.policy.warning_threshold,
      is_exceeded: totalSpent >= this.policy.max_total_cost,
      records: [...this.records],
    };
  }

  /**
   * 判断预算是否允许一次预估费用的调用
   *
   * 当 hard_limit 为 true 时，超出预算返回 false；
   * 当 hard_limit 为 false 时，始终返回 true（仅警告不阻断）。
   *
   * @param estimatedCost - 预估费用（美元）
   * @returns 是否允许执行
   */
  canAfford(estimatedCost: number): boolean {
    // 非硬性限制模式下，始终允许
    if (!this.policy.hard_limit) {
      return true;
    }

    const totalSpent = this.records.reduce((sum, r) => sum + r.cost, 0);
    return totalSpent + estimatedCost <= this.policy.max_total_cost;
  }

  /**
   * 获取剩余可用预算
   *
   * @returns 剩余额度（美元），最小为 0
   */
  getRemainingBudget(): number {
    const totalSpent = this.records.reduce((sum, r) => sum + r.cost, 0);
    return Math.max(0, this.policy.max_total_cost - totalSpent);
  }

  /**
   * 获取指定任务的累计成本
   *
   * 汇总该任务下所有调用记录的费用。
   *
   * @param taskId - 任务 id
   * @returns 该任务的累计费用（美元）
   */
  getTaskCost(taskId: string): number {
    return this.records
      .filter((r) => r.task_id === taskId)
      .reduce((sum, r) => sum + r.cost, 0);
  }

  /**
   * 估算单个任务的执行成本
   *
   * 基于模型配置的 max_tokens 和 cost_per_1k_tokens 计算上限估算值。
   * 假设输入 token 和输出 token 各占 max_tokens 的一半作为合理估算。
   *
   * @param _node - 任务节点（预留用于后续基于任务属性的精细估算）
   * @param modelConfig - 模型配置
   * @returns 预估费用（美元）
   */
  estimateTaskCost(_node: TaskNode, modelConfig: ModelConfig): number {
    // 以 max_tokens 作为上限估算：假设输入输出各占一半
    return (modelConfig.max_tokens / 1000) * modelConfig.cost_per_1k_tokens;
  }

  /**
   * 重置所有成本记录
   *
   * 清空已有记录，使预算恢复到初始状态。
   * 策略配置保持不变。
   */
  reset(): void {
    this.records = [];
  }
}
