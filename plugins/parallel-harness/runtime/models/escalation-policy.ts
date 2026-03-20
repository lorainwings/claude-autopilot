/**
 * 模型升级策略
 *
 * 当任务执行失败、验证不通过或质量低于阈值时，
 * 自动将任务从低层级模型升级到高层级模型重试。
 * 提供可配置的升级规则和完整的升级历史追踪。
 */

import type { ModelTier, VerifierType } from '../schemas/types.js';

// ─── 升级触发条件 ─────────────────────────────────────────

/** 升级触发类型 */
export type EscalationTrigger =
  | 'verification_failed'
  | 'task_failed'
  | 'quality_below_threshold'
  | 'complexity_underestimated';

// ─── 升级规则 ───────────────────────────────────────────

/** 单条升级规则：定义何时从哪个层级升级到哪个层级 */
export interface EscalationRule {
  /** 触发升级的事件类型 */
  trigger: EscalationTrigger;
  /** 当前所在模型层级 */
  current_tier: ModelTier;
  /** 升级目标模型层级 */
  escalate_to: ModelTier;
  /** 触发条件（可选，满足所有指定条件才触发） */
  conditions?: {
    /** 最低分数阈值（低于此分数才触发） */
    min_score?: number;
    /** 最大重试次数（达到此次数才触发） */
    max_retries?: number;
    /** 特定验证器失败时才触发 */
    verifier_types?: VerifierType[];
  };
}

// ─── 升级记录 ───────────────────────────────────────────

/** 一次升级操作的记录 */
export interface EscalationRecord {
  /** 关联的任务 id */
  task_id: string;
  /** 升级前的模型层级 */
  from_tier: ModelTier;
  /** 升级后的模型层级 */
  to_tier: ModelTier;
  /** 触发升级的原因 */
  trigger: string;
  /** 记录时间戳（ISO 8601 格式） */
  timestamp: string;
}

// ─── 模型层级顺序 ─────────────────────────────────────────

/**
 * 模型层级优先级顺序（从低到高）
 *
 * tier-1（轻量）→ tier-2（通用）→ tier-3（旗舰）
 */
const TIER_ORDER: ModelTier[] = ['tier-1', 'tier-2', 'tier-3'];

// ─── 默认升级规则 ─────────────────────────────────────────

/** 默认升级规则集 */
const DEFAULT_RULES: EscalationRule[] = [
  // 验证失败：tier-1 → tier-2
  {
    trigger: 'verification_failed',
    current_tier: 'tier-1',
    escalate_to: 'tier-2',
  },
  // 验证失败：tier-2 → tier-3
  {
    trigger: 'verification_failed',
    current_tier: 'tier-2',
    escalate_to: 'tier-3',
  },
  // 任务失败：tier-1 重试 >= 2 次后 → tier-2
  {
    trigger: 'task_failed',
    current_tier: 'tier-1',
    escalate_to: 'tier-2',
    conditions: {
      max_retries: 2,
    },
  },
  // 任务失败：tier-2 重试 >= 1 次后 → tier-3
  {
    trigger: 'task_failed',
    current_tier: 'tier-2',
    escalate_to: 'tier-3',
    conditions: {
      max_retries: 1,
    },
  },
  // 质量低于阈值（分数 < 60）：tier-1 → tier-2
  {
    trigger: 'quality_below_threshold',
    current_tier: 'tier-1',
    escalate_to: 'tier-2',
    conditions: {
      min_score: 60,
    },
  },
  // 质量低于阈值（分数 < 60）：tier-2 → tier-3
  {
    trigger: 'quality_below_threshold',
    current_tier: 'tier-2',
    escalate_to: 'tier-3',
    conditions: {
      min_score: 60,
    },
  },
];

// ─── 升级策略实现 ─────────────────────────────────────────

export class EscalationPolicy {
  /** 升级规则列表 */
  private readonly rules: EscalationRule[];

  /** 升级历史记录（按任务 id 分组） */
  private readonly history: Map<string, EscalationRecord[]> = new Map();

  constructor(rules?: EscalationRule[]) {
    this.rules = rules ?? [...DEFAULT_RULES];
  }

  /**
   * 评估任务是否需要升级模型层级
   *
   * 遍历所有规则，找到第一条匹配当前上下文的规则。
   * 匹配条件包括：触发类型、当前层级、以及可选的条件约束。
   *
   * @param _taskId - 任务 id（预留用于后续基于历史记录的判断）
   * @param context - 当前任务的运行上下文
   * @returns 升级目标层级，如果不需要升级则返回 null
   */
  evaluate(
    _taskId: string,
    context: {
      current_tier: ModelTier;
      trigger: EscalationTrigger;
      score?: number;
      retries?: number;
      failed_verifiers?: VerifierType[];
    },
  ): ModelTier | null {
    // 如果已经是最高层级，无法继续升级
    if (!this.canEscalate(context.current_tier)) {
      return null;
    }

    for (const rule of this.rules) {
      // 匹配触发类型和当前层级
      if (
        rule.trigger !== context.trigger ||
        rule.current_tier !== context.current_tier
      ) {
        continue;
      }

      // 检查可选条件
      if (rule.conditions) {
        // 分数阈值检查：当前分数必须低于阈值才触发
        if (
          rule.conditions.min_score !== undefined &&
          context.score !== undefined
        ) {
          if (context.score >= rule.conditions.min_score) {
            continue;
          }
        }

        // 重试次数检查：当前重试次数必须达到阈值才触发
        if (
          rule.conditions.max_retries !== undefined &&
          context.retries !== undefined
        ) {
          if (context.retries < rule.conditions.max_retries) {
            continue;
          }
        }

        // 验证器类型检查：失败的验证器必须包含指定类型之一
        if (
          rule.conditions.verifier_types &&
          rule.conditions.verifier_types.length > 0 &&
          context.failed_verifiers
        ) {
          const hasMatch = rule.conditions.verifier_types.some((vt) =>
            context.failed_verifiers!.includes(vt),
          );
          if (!hasMatch) {
            continue;
          }
        }
      }

      // 找到匹配的规则，返回升级目标层级
      return rule.escalate_to;
    }

    // 没有匹配的规则
    return null;
  }

  /**
   * 记录一次升级操作
   *
   * @param taskId - 任务 id
   * @param fromTier - 升级前的模型层级
   * @param toTier - 升级后的模型层级
   * @param trigger - 触发升级的原因描述
   * @returns 完整的升级记录
   */
  recordEscalation(
    taskId: string,
    fromTier: ModelTier,
    toTier: ModelTier,
    trigger: string,
  ): EscalationRecord {
    const record: EscalationRecord = {
      task_id: taskId,
      from_tier: fromTier,
      to_tier: toTier,
      trigger,
      timestamp: new Date().toISOString(),
    };

    // 追加到对应任务的历史记录中
    const taskHistory = this.history.get(taskId) ?? [];
    taskHistory.push(record);
    this.history.set(taskId, taskHistory);

    return record;
  }

  /**
   * 获取指定任务的升级历史
   *
   * @param taskId - 任务 id
   * @returns 该任务的所有升级记录（按时间顺序）
   */
  getEscalationHistory(taskId: string): EscalationRecord[] {
    return [...(this.history.get(taskId) ?? [])];
  }

  /**
   * 判断当前层级是否还能继续升级
   *
   * tier-3 是最高层级，无法再升级。
   *
   * @param currentTier - 当前模型层级
   * @returns 是否还有更高层级可用
   */
  canEscalate(currentTier: ModelTier): boolean {
    const currentIndex = TIER_ORDER.indexOf(currentTier);
    return currentIndex >= 0 && currentIndex < TIER_ORDER.length - 1;
  }

  /**
   * 获取当前层级的上一级模型层级
   *
   * @param currentTier - 当前模型层级
   * @returns 上一级层级，如果已经是最高层级则返回 null
   */
  getNextTier(currentTier: ModelTier): ModelTier | null {
    const currentIndex = TIER_ORDER.indexOf(currentTier);
    if (currentIndex < 0 || currentIndex >= TIER_ORDER.length - 1) {
      return null;
    }
    return TIER_ORDER[currentIndex + 1];
  }
}
