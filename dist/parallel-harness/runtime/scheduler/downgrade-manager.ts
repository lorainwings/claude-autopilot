/**
 * 降级管理器
 *
 * 当任务执行遇到持续失败、超时或预算超限时，
 * 自动降低模型层级或简化验证策略，确保整体流程不被单个任务阻塞。
 *
 * 降级路径：tier-3（最强） → tier-2（中等） → tier-1（轻量）
 */

import type { ModelTier } from '../schemas/types.js';
import type { TaskNode } from '../schemas/task-graph.js';

// ─── 降级触发条件 ───────────────────────────────────────

/** 降级触发器：定义何时触发降级 */
export interface DowngradeTrigger {
  /** 触发条件类型 */
  condition:
    | 'retry_exhausted'    // 重试次数耗尽
    | 'timeout'            // 执行超时
    | 'budget_exceeded'    // 预算超限
    | 'error_rate_high';   // 错误率过高
  /** 触发阈值（含义由 condition 决定） */
  threshold: number;
  /** 触发后执行的降级动作 */
  action: DowngradeAction;
}

/** 降级动作 */
export interface DowngradeAction {
  /** 动作类型 */
  type:
    | 'reduce_tier'       // 降低模型层级
    | 'simplify_task'     // 简化任务（减少验收标准等）
    | 'skip_verifier'     // 跳过部分验证器
    | 'reduce_context';   // 缩减上下文规模
  /** 动作参数（可选） */
  params?: Record<string, unknown>;
}

// ─── 降级策略配置 ───────────────────────────────────────

/** 降级策略配置 */
export interface DowngradePolicy {
  /** 是否启用降级机制 */
  enabled: boolean;
  /** 降级触发器列表（按顺序评估，命中第一个即停止） */
  triggers: DowngradeTrigger[];
  /** 最低允许降到的模型层级 */
  min_tier: ModelTier;
}

/** 默认降级触发器 */
const DEFAULT_TRIGGERS: DowngradeTrigger[] = [
  {
    condition: 'retry_exhausted',
    threshold: 3,
    action: { type: 'reduce_tier' },
  },
  {
    condition: 'timeout',
    threshold: 300_000, // 5 分钟
    action: { type: 'reduce_tier' },
  },
];

/** 默认降级策略 */
const DEFAULT_DOWNGRADE_POLICY: DowngradePolicy = {
  enabled: true,
  triggers: DEFAULT_TRIGGERS,
  min_tier: 'tier-1',
};

// ─── 降级记录 ───────────────────────────────────────────

/** 降级操作记录 */
export interface DowngradeRecord {
  /** 关联的任务 id */
  task_id: string;
  /** 降级前的模型层级 */
  original_tier: ModelTier;
  /** 降级后的模型层级 */
  downgraded_tier: ModelTier;
  /** 降级原因描述 */
  reason: string;
  /** 记录时间（ISO 8601） */
  timestamp: string;
}

// ─── 模型层级工具 ───────────────────────────────────────

/**
 * 模型层级优先级映射（数值越大表示越强）
 *
 * tier-1: 轻量模型（如 haiku）
 * tier-2: 中等模型（如 sonnet）
 * tier-3: 最强模型（如 opus）
 */
const TIER_RANK: Record<ModelTier, number> = {
  'tier-1': 1,
  'tier-2': 2,
  'tier-3': 3,
};

/** 按 rank 反查 ModelTier */
const RANK_TO_TIER: Record<number, ModelTier> = {
  1: 'tier-1',
  2: 'tier-2',
  3: 'tier-3',
};

// ─── 降级管理器实现 ─────────────────────────────────────

export class DowngradeManager {
  /** 当前生效的降级策略 */
  private readonly policy: DowngradePolicy;

  /** 降级历史记录：task_id → DowngradeRecord[] */
  private readonly records: Map<string, DowngradeRecord[]> = new Map();

  constructor(policy?: Partial<DowngradePolicy>) {
    this.policy = { ...DEFAULT_DOWNGRADE_POLICY, ...policy };
    // 如果用户提供了部分 triggers，则完全替换默认值
    if (policy?.triggers) {
      this.policy.triggers = policy.triggers;
    }
  }

  // ── 降级评估 ────────────────────────────────────────────

  /**
   * 评估指定任务当前是否需要降级。
   *
   * 遍历所有触发器，按顺序检查是否命中：
   * - retry_exhausted: context.retries >= threshold
   * - timeout:         context.elapsed_ms >= threshold
   * - budget_exceeded: context.cost >= threshold
   * - error_rate_high: context.error_rate >= threshold
   *
   * @param taskId  - 任务 id（用于日志追踪）
   * @param context - 当前执行上下文指标
   * @returns 如果需要降级，返回建议的 DowngradeAction；否则返回 null
   */
  evaluate(
    _taskId: string,
    context: {
      retries: number;
      elapsed_ms: number;
      cost: number;
      error_rate: number;
    },
  ): DowngradeAction | null {
    // 降级未启用时直接跳过
    if (!this.policy.enabled) {
      return null;
    }

    for (const trigger of this.policy.triggers) {
      const triggered = this.checkTrigger(trigger, context);
      if (triggered) {
        return trigger.action;
      }
    }

    return null;
  }

  // ── 降级执行 ────────────────────────────────────────────

  /**
   * 对任务节点执行降级操作。
   *
   * 当前支持的降级行为：
   * - 将 model_tier 降低一级（如 tier-3 → tier-2）
   * - 简化 verifier_set（仅保留 'test'，移除 review/security/perf）
   *
   * 返回一个新的 TaskNode（不修改原对象），便于调用方做差异追踪。
   *
   * @param node - 原始任务节点
   * @returns 降级后的任务节点副本
   */
  downgrade(node: TaskNode): TaskNode {
    const originalTier = node.model_tier;
    const nextTier = this.getNextTier(originalTier);

    // 创建副本以避免修改原始对象
    const downgraded: TaskNode = { ...node };

    // 降低模型层级
    if (nextTier !== null) {
      downgraded.model_tier = nextTier;
    }

    // 简化验证器集合：仅保留最基本的 'test' 验证器
    if (downgraded.verifier_set.length > 1) {
      downgraded.verifier_set = downgraded.verifier_set.includes('test')
        ? ['test']
        : [downgraded.verifier_set[0]];
    }

    // 记录降级历史
    const record: DowngradeRecord = {
      task_id: node.id,
      original_tier: originalTier,
      downgraded_tier: downgraded.model_tier,
      reason: `模型层级 ${originalTier} → ${downgraded.model_tier}，验证器集合已简化`,
      timestamp: new Date().toISOString(),
    };

    const history = this.records.get(node.id) ?? [];
    history.push(record);
    this.records.set(node.id, history);

    return downgraded;
  }

  // ── 层级查询 ────────────────────────────────────────────

  /**
   * 判断当前模型层级是否还能继续降级。
   *
   * 当且仅当 currentTier 高于策略中的 min_tier 时返回 true。
   *
   * @param currentTier - 当前模型层级
   */
  canDowngrade(currentTier: ModelTier): boolean {
    return TIER_RANK[currentTier] > TIER_RANK[this.policy.min_tier];
  }

  /**
   * 获取下一个降级层级。
   *
   * 例如 tier-3 → tier-2，tier-2 → tier-1。
   * 如果已经是最低层级或达到 min_tier，返回 null。
   *
   * @param currentTier - 当前模型层级
   * @returns 下一个更低的层级，或 null（已到底）
   */
  getNextTier(currentTier: ModelTier): ModelTier | null {
    const currentRank = TIER_RANK[currentTier];
    const minRank = TIER_RANK[this.policy.min_tier];

    // 已经是最低允许层级，无法再降
    if (currentRank <= minRank) {
      return null;
    }

    // 降低一级
    const nextRank = currentRank - 1;
    return RANK_TO_TIER[nextRank] ?? null;
  }

  // ── 历史查询 ────────────────────────────────────────────

  /** 获取指定任务的降级历史记录 */
  getDowngradeHistory(taskId: string): DowngradeRecord[] {
    return [...(this.records.get(taskId) ?? [])];
  }

  // ── 只读访问器 ──────────────────────────────────────────

  /** 获取当前策略（只读副本） */
  getPolicy(): Readonly<DowngradePolicy> {
    return { ...this.policy };
  }

  // ── 内部辅助 ────────────────────────────────────────────

  /**
   * 检查单个触发器是否命中
   *
   * @param trigger - 待检查的触发器
   * @param context - 当前执行上下文指标
   * @returns 是否命中
   */
  private checkTrigger(
    trigger: DowngradeTrigger,
    context: {
      retries: number;
      elapsed_ms: number;
      cost: number;
      error_rate: number;
    },
  ): boolean {
    switch (trigger.condition) {
      case 'retry_exhausted':
        return context.retries >= trigger.threshold;

      case 'timeout':
        return context.elapsed_ms >= trigger.threshold;

      case 'budget_exceeded':
        return context.cost >= trigger.threshold;

      case 'error_rate_high':
        return context.error_rate >= trigger.threshold;

      default:
        return false;
    }
  }
}
