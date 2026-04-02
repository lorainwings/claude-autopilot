/**
 * parallel-harness: Model Router
 *
 * 成本感知的自动模型路由。
 * 不同于手工切换，基于任务复杂度、token 预算和失败历史自动选择 tier。
 *
 * 来源设计：
 * - claude-code-switch: 模型 tier 定义
 *
 * 反向增强：
 * - 不只做手工切换，做自动路由
 * - 路由接入任务复杂度、预算、失败次数
 * - 失败时自动升级策略（escalation）
 */

import type { ModelTier, ComplexityLevel, RiskLevel } from "../orchestrator/task-graph";

// ============================================================
// Tier 定义
// ============================================================

/** 模型 Tier 配置 */
export interface TierConfig {
  /** Tier 名称 */
  tier: ModelTier;

  /** 适用任务类型 */
  task_types: string[];

  /** 最大上下文预算 (tokens) */
  max_context_budget: number;

  /** 最大重试次数 */
  max_retry: number;

  /** 每 1K token 成本（相对值） */
  cost_per_1k: number;

  /** 描述 */
  description: string;
}

/** 默认 Tier 配置 */
export const DEFAULT_TIER_CONFIGS: TierConfig[] = [
  {
    tier: "tier-1",
    task_types: [
      "search",
      "grep",
      "format",
      "rename",
      "simple-refactor",
      "lint-fix",
      "comment-update",
    ],
    max_context_budget: 16000,
    max_retry: 3,
    cost_per_1k: 1,
    description: "低成本执行模型，适用于简单重复性任务",
  },
  {
    tier: "tier-2",
    task_types: [
      "implementation",
      "test-writing",
      "bug-fix",
      "general-review",
      "documentation",
      "moderate-refactor",
    ],
    max_context_budget: 64000,
    max_retry: 2,
    cost_per_1k: 5,
    description: "中成本通用模型，适用于一般实现和审查任务",
  },
  {
    tier: "tier-3",
    task_types: [
      "planning",
      "architecture-design",
      "critical-review",
      "security-audit",
      "complex-refactor",
      "performance-optimization",
    ],
    max_context_budget: 200000,
    max_retry: 1,
    cost_per_1k: 25,
    description: "高能力规划/审查模型，适用于复杂设计和关键审查",
  },
];

// ============================================================
// 路由输入输出
// ============================================================

/** 路由请求 */
export interface RoutingRequest {
  /** 任务复杂度等级 */
  complexity: ComplexityLevel;

  /** 风险等级 */
  risk_level: RiskLevel;

  /** Token 预算（0 = 不限） */
  token_budget: number;

  /** 已重试次数 */
  retry_count: number;

  /** 任务类型提示 */
  task_type_hint?: string;
}

/** 路由结果 */
export interface RoutingResult {
  /** 推荐的模型 tier */
  recommended_tier: ModelTier;

  /** 该 tier 的配置 */
  tier_config: TierConfig;

  /** 上下文预算 */
  context_budget: number;

  /** 最大重试次数 */
  max_retries: number;

  /** 路由理由 */
  reasoning: string;
}

// ============================================================
// Model Router 实现
// ============================================================

/**
 * 根据任务特征自动路由模型 tier
 */
export function routeModel(
  request: RoutingRequest,
  tierConfigs: TierConfig[] = DEFAULT_TIER_CONFIGS
): RoutingResult {
  // 1. 基于复杂度的基础 tier
  let baseTier = complexityToTier(request.complexity);

  // 2. 风险等级可能提升 tier
  if (request.risk_level === "critical" || request.risk_level === "high") {
    baseTier = escalateTier(baseTier);
  }

  // 3. 重试次数导致升级（escalation policy）
  const escalatedTier = applyEscalation(baseTier, request.retry_count);

  // 4. 任务类型匹配
  if (request.task_type_hint) {
    const matchedTier = findTierByTaskType(
      request.task_type_hint,
      tierConfigs
    );
    if (matchedTier) {
      // 取更高的 tier
      const finalTier = higherTier(escalatedTier, matchedTier);
      return buildResult(finalTier, tierConfigs, request);
    }
  }

  return buildResult(escalatedTier, tierConfigs, request);
}

/**
 * 应用升级策略：失败后自动升级 tier
 */
export function applyEscalationPolicy(
  currentTier: ModelTier,
  retryCount: number
): ModelTier {
  return applyEscalation(currentTier, retryCount);
}

// ============================================================
// 辅助函数
// ============================================================

function complexityToTier(complexity: ComplexityLevel): ModelTier {
  switch (complexity) {
    case "trivial":
    case "low":
      return "tier-1";
    case "medium":
      return "tier-2";
    case "high":
    case "extreme":
      return "tier-3";
    default:
      return "tier-2";
  }
}

function escalateTier(tier: ModelTier): ModelTier {
  switch (tier) {
    case "tier-1":
      return "tier-2";
    case "tier-2":
      return "tier-3";
    case "tier-3":
      return "tier-3";
    default:
      return tier;
  }
}

function applyEscalation(tier: ModelTier, retryCount: number): ModelTier {
  let current = tier;
  for (let i = 0; i < retryCount; i++) {
    current = escalateTier(current);
  }
  return current;
}

function findTierByTaskType(
  taskType: string,
  configs: TierConfig[]
): ModelTier | null {
  const typeLower = taskType.toLowerCase();
  for (const config of configs) {
    if (config.task_types.some((t) => typeLower.includes(t))) {
      return config.tier;
    }
  }
  return null;
}

function higherTier(a: ModelTier, b: ModelTier): ModelTier {
  const order: Record<ModelTier, number> = {
    "tier-1": 1,
    "tier-2": 2,
    "tier-3": 3,
  };
  return order[a] >= order[b] ? a : b;
}

function buildResult(
  tier: ModelTier,
  configs: TierConfig[],
  request: RoutingRequest
): RoutingResult {
  const tierConfig = configs.find((c) => c.tier === tier) || configs[1];

  // 上下文预算：取 tier 默认和请求预算中较小的
  let contextBudget = tierConfig.max_context_budget;
  if (request.token_budget > 0) {
    contextBudget = Math.min(contextBudget, request.token_budget);
  }

  const reasoning = buildReasoning(tier, request);

  return {
    recommended_tier: tier,
    tier_config: tierConfig,
    context_budget: contextBudget,
    max_retries: tierConfig.max_retry,
    reasoning,
  };
}

function buildReasoning(tier: ModelTier, request: RoutingRequest): string {
  const parts: string[] = [];
  parts.push(`复杂度 ${request.complexity} -> 基础 tier`);
  if (request.risk_level === "high" || request.risk_level === "critical") {
    parts.push(`高风险提升`);
  }
  if (request.retry_count > 0) {
    parts.push(`${request.retry_count} 次重试升级`);
  }
  parts.push(`-> 最终推荐 ${tier}`);
  return parts.join(", ");
}

// ============================================================
// Occupancy-Aware Routing — P2-5 数据化调优
// ============================================================

export interface OccupancyRoutingInput {
  complexity: ComplexityLevel;
  risk_level: RiskLevel;
  retry_count: number;
  task_type_hint?: string;
  /** 上下文占用率 (0-1) */
  occupancy_ratio: number;
  /** 可用 token 预算 */
  available_tokens: number;
}

export interface OccupancyRoutingResult extends RoutingResult {
  /** 是否因 occupancy 降级 */
  downgraded_by_occupancy: boolean;
  /** 调整后的上下文预算 */
  adjusted_context_budget: number;
  /** occupancy 因子描述 */
  occupancy_factor: string;
}

/**
 * 基于 occupancy 的动态模型路由
 *
 * 当上下文占用率高时：
 * - 降低模型 tier（减少生成量）
 * - 缩减上下文预算
 * - 优先使用高效模型
 */
export function routeWithOccupancy(
  input: OccupancyRoutingInput,
  tierConfigs: TierConfig[] = DEFAULT_TIER_CONFIGS
): OccupancyRoutingResult {
  // 先做基础路由
  const baseResult = routeModel(
    {
      complexity: input.complexity,
      risk_level: input.risk_level,
      token_budget: input.available_tokens,
      retry_count: input.retry_count,
      task_type_hint: input.task_type_hint,
    },
    tierConfigs
  );

  let downgraded = false;
  let finalTier = baseResult.recommended_tier;
  let occupancyFactor = "正常";

  // 高 occupancy 时降级 tier
  if (input.occupancy_ratio > 0.9) {
    // 严重：降两级
    finalTier = downgradeTier(downgradeTier(finalTier));
    downgraded = true;
    occupancyFactor = `严重 (${(input.occupancy_ratio * 100).toFixed(1)}%)，降两级`;
  } else if (input.occupancy_ratio > 0.75) {
    // 警告：降一级
    finalTier = downgradeTier(finalTier);
    downgraded = true;
    occupancyFactor = `警告 (${(input.occupancy_ratio * 100).toFixed(1)}%)，降一级`;
  }

  // 根据 occupancy 调整上下文预算
  const budgetFactor = Math.max(0.3, 1 - input.occupancy_ratio);
  const adjustedBudget = Math.floor(baseResult.context_budget * budgetFactor);

  const tierConfig = tierConfigs.find(c => c.tier === finalTier) || tierConfigs[1];

  return {
    recommended_tier: finalTier,
    tier_config: tierConfig,
    context_budget: baseResult.context_budget,
    max_retries: tierConfig.max_retry,
    reasoning: `${baseResult.reasoning}${downgraded ? ` [occupancy 降级: ${occupancyFactor}]` : ""}`,
    downgraded_by_occupancy: downgraded,
    adjusted_context_budget: adjustedBudget,
    occupancy_factor: occupancyFactor,
  };
}

function downgradeTier(tier: ModelTier): ModelTier {
  switch (tier) {
    case "tier-3": return "tier-2";
    case "tier-2": return "tier-1";
    case "tier-1": return "tier-1";
    default: return tier;
  }
}

// ============================================================
// Routing Statistics — 趋势统计
// ============================================================

export interface RoutingStats {
  total_routings: number;
  tier_distribution: Record<ModelTier, number>;
  avg_occupancy: number;
  occupancy_downgrades: number;
  escalations: number;
}

export class RoutingStatsCollector {
  private stats: RoutingStats = {
    total_routings: 0,
    tier_distribution: { "tier-1": 0, "tier-2": 0, "tier-3": 0 },
    avg_occupancy: 0,
    occupancy_downgrades: 0,
    escalations: 0,
  };
  private occupancySum = 0;

  record(result: OccupancyRoutingResult, occupancy: number): void {
    this.stats.total_routings++;
    this.stats.tier_distribution[result.recommended_tier]++;
    this.occupancySum += occupancy;
    this.stats.avg_occupancy = this.occupancySum / this.stats.total_routings;
    if (result.downgraded_by_occupancy) this.stats.occupancy_downgrades++;
  }

  recordEscalation(): void {
    this.stats.escalations++;
  }

  getStats(): RoutingStats {
    return { ...this.stats };
  }

  reset(): void {
    this.stats = {
      total_routings: 0,
      tier_distribution: { "tier-1": 0, "tier-2": 0, "tier-3": 0 },
      avg_occupancy: 0,
      occupancy_downgrades: 0,
      escalations: 0,
    };
    this.occupancySum = 0;
  }
}
