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
