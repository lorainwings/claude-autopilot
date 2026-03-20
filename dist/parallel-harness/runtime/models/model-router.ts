/**
 * 最小模型路由器
 *
 * 根据任务属性（风险等级、复杂度、任务类型）将任务路由到合适的模型层级。
 * 提供成本估算能力。
 */

import type { ModelTier, RiskLevel } from '../schemas/types.js';
import type { TaskNode, TaskGraph } from '../schemas/task-graph.js';

// ─── 模型配置 ───────────────────────────────────────────────

/** 单个模型的配置信息 */
export interface ModelConfig {
  /** 模型所属层级 */
  tier: ModelTier;
  /** 模型标识符 */
  model_id: string;
  /** 最大输出 token 数 */
  max_tokens: number;
  /** 每 1000 token 的费用（美元） */
  cost_per_1k_tokens: number;
  /** 模型擅长的能力标签 */
  capabilities: string[];
}

// ─── 路由规则 ───────────────────────────────────────────────

/** 路由规则：匹配模式 → 模型层级 */
export interface RoutingRule {
  /** 匹配模式（正则或字符串关键词） */
  pattern: RegExp | string;
  /** 适用的任务类型列表 */
  task_types: string[];
  /** 适用的风险等级列表 */
  risk_levels: RiskLevel[];
  /** 路由到的目标层级 */
  tier: ModelTier;
}

// ─── 默认三层模型配置 ───────────────────────────────────────

/** tier-1: 轻量模型，适用于搜索、格式化、低风险重构 */
const TIER_1_CONFIG: ModelConfig = {
  tier: 'tier-1',
  model_id: 'claude-haiku-4-5',
  max_tokens: 8192,
  cost_per_1k_tokens: 0.25,
  capabilities: ['search', 'format', 'lint', 'refactor-simple'],
};

/** tier-2: 通用模型，适用于实现、一般审查、测试 */
const TIER_2_CONFIG: ModelConfig = {
  tier: 'tier-2',
  model_id: 'claude-sonnet-4-6',
  max_tokens: 16384,
  cost_per_1k_tokens: 3.0,
  capabilities: ['implement', 'review', 'test', 'debug', 'refactor'],
};

/** tier-3: 旗舰模型，适用于规划、设计、关键审查 */
const TIER_3_CONFIG: ModelConfig = {
  tier: 'tier-3',
  model_id: 'claude-opus-4-6',
  max_tokens: 32768,
  cost_per_1k_tokens: 15.0,
  capabilities: ['plan', 'design', 'architecture', 'critical-review', 'synthesize'],
};

/** 默认模型配置列表 */
const DEFAULT_CONFIGS: ModelConfig[] = [TIER_1_CONFIG, TIER_2_CONFIG, TIER_3_CONFIG];

// ─── 默认路由规则 ───────────────────────────────────────────

const DEFAULT_RULES: RoutingRule[] = [
  {
    pattern: /search|format|lint/i,
    task_types: ['search', 'format', 'lint'],
    risk_levels: ['low'],
    tier: 'tier-1',
  },
  {
    pattern: /implement|review|test/i,
    task_types: ['implement', 'review', 'test'],
    risk_levels: ['medium'],
    tier: 'tier-2',
  },
  {
    pattern: /plan|design|architecture|critical/i,
    task_types: ['plan', 'design', 'architecture', 'critical'],
    risk_levels: ['high', 'critical'],
    tier: 'tier-3',
  },
];

// ─── 模型路由器实现 ─────────────────────────────────────────

export class ModelRouter {
  /** 各层级的模型配置 */
  private readonly configs: ModelConfig[];

  /** 路由规则列表（按优先级从高到低） */
  private readonly rules: RoutingRule[];

  constructor(configs?: ModelConfig[], rules?: RoutingRule[]) {
    this.configs = configs ?? [...DEFAULT_CONFIGS];
    this.rules = rules ?? [...DEFAULT_RULES];
  }

  /**
   * 根据任务节点属性综合路由到合适的模型
   *
   * 路由优先级：
   *   1. 节点显式指定的 model_tier（最高优先）
   *   2. 风险等级路由
   *   3. 任务标题 / 目标关键词匹配
   *   4. 复杂度分数路由
   *   5. 兜底使用 tier-2
   */
  route(node: TaskNode): ModelConfig {
    // 1. 如果节点已显式指定层级，直接使用
    if (node.model_tier) {
      return this.getModelConfig(node.model_tier);
    }

    // 2. 按风险等级路由
    const riskTier = this.routeByRiskLevel(node.risk_level);
    if (riskTier === 'tier-3') {
      // 高风险 / 关键任务无条件走旗舰模型
      return this.getModelConfig('tier-3');
    }

    // 3. 按任务标题和目标中的关键词匹配规则
    const textToMatch = `${node.title} ${node.goal}`;
    for (const rule of this.rules) {
      const pattern =
        rule.pattern instanceof RegExp
          ? rule.pattern
          : new RegExp(rule.pattern, 'i');

      if (pattern.test(textToMatch)) {
        return this.getModelConfig(rule.tier);
      }
    }

    // 4. 按复杂度分数路由
    if (node.complexity_score !== undefined) {
      const complexityTier = this.routeByComplexity(node.complexity_score);
      return this.getModelConfig(complexityTier);
    }

    // 5. 兜底：使用通用层级
    return this.getModelConfig(riskTier);
  }

  /**
   * 按复杂度分数路由
   *
   * - score < 3  → tier-1（简单任务）
   * - score < 7  → tier-2（中等任务）
   * - score >= 7 → tier-3（复杂任务）
   */
  routeByComplexity(score: number): ModelTier {
    if (score < 3) return 'tier-1';
    if (score < 7) return 'tier-2';
    return 'tier-3';
  }

  /**
   * 按风险等级路由
   *
   * - low      → tier-1
   * - medium   → tier-2
   * - high     → tier-3
   * - critical → tier-3
   */
  routeByRiskLevel(level: RiskLevel): ModelTier {
    switch (level) {
      case 'low':
        return 'tier-1';
      case 'medium':
        return 'tier-2';
      case 'high':
      case 'critical':
        return 'tier-3';
    }
  }

  /**
   * 按任务类型字符串路由
   *
   * 遍历规则列表，匹配第一个包含该类型的规则；无匹配则返回 tier-2。
   */
  routeByTaskType(taskType: string): ModelTier {
    for (const rule of this.rules) {
      if (rule.task_types.includes(taskType)) {
        return rule.tier;
      }
    }
    // 未匹配到任何规则，使用通用层级
    return 'tier-2';
  }

  /**
   * 获取指定层级的模型配置
   *
   * 若找不到对应层级，则回退到 tier-2 配置。
   */
  getModelConfig(tier: ModelTier): ModelConfig {
    const config = this.configs.find((c) => c.tier === tier);
    if (config) return config;

    // 回退到 tier-2
    const fallback = this.configs.find((c) => c.tier === 'tier-2');
    if (fallback) return fallback;

    // 极端兜底：返回第一个可用配置
    if (this.configs.length > 0) return this.configs[0];

    // 配置列表为空的最终兜底（不应该发生）
    return { ...TIER_2_CONFIG };
  }

  /**
   * 估算整个任务图的执行成本
   *
   * 基于每个任务路由到的模型层级和该模型的 cost_per_1k_tokens，
   * 乘以模型的 max_tokens 作为上限估算值。
   *
   * @returns total 总成本、breakdown 按层级细分
   */
  estimateCost(graph: TaskGraph): {
    total: number;
    breakdown: Record<ModelTier, number>;
  } {
    const breakdown: Record<ModelTier, number> = {
      'tier-1': 0,
      'tier-2': 0,
      'tier-3': 0,
    };

    for (const node of graph.nodes) {
      const config = this.route(node);
      // 按最大 token 上限估算单任务成本
      const taskCost = (config.max_tokens / 1000) * config.cost_per_1k_tokens;
      breakdown[config.tier] += taskCost;
    }

    const total = breakdown['tier-1'] + breakdown['tier-2'] + breakdown['tier-3'];

    return { total, breakdown };
  }
}
