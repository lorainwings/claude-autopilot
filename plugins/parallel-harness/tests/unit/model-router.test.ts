/**
 * model-router.ts 单元测试
 *
 * 覆盖：
 * - routeModel(): 复杂度到 tier 的映射、高风险提升、重试升级、任务类型匹配、token 预算限制
 * - applyEscalationPolicy(): 正确升级 tier
 */

import { describe, expect, it, test } from "bun:test";
import {
  routeModel,
  applyEscalationPolicy,
  DEFAULT_TIER_CONFIGS,
} from "../../runtime/models/model-router";
import type { RoutingRequest } from "../../runtime/models/model-router";

// ============================================================
// 辅助函数
// ============================================================

/** 创建基础路由请求 */
function createRequest(overrides: Partial<RoutingRequest> = {}): RoutingRequest {
  return {
    complexity: "low",
    risk_level: "low",
    token_budget: 0,
    retry_count: 0,
    ...overrides,
  };
}

// ============================================================
// routeModel 测试
// ============================================================

describe("routeModel", () => {
  it("低复杂度 -> tier-1", () => {
    const result = routeModel(createRequest({ complexity: "low" }));
    expect(result.recommended_tier).toBe("tier-1");
  });

  it("中复杂度 -> tier-2", () => {
    const result = routeModel(createRequest({ complexity: "medium" }));
    expect(result.recommended_tier).toBe("tier-2");
  });

  it("高复杂度 -> tier-3", () => {
    const result = routeModel(createRequest({ complexity: "high" }));
    expect(result.recommended_tier).toBe("tier-3");
  });

  it("高风险提升 tier", () => {
    // 低复杂度 + 高风险 = tier-1 提升到 tier-2
    const result = routeModel(
      createRequest({ complexity: "low", risk_level: "high" }),
    );
    expect(result.recommended_tier).toBe("tier-2");

    // 中复杂度 + critical 风险 = tier-2 提升到 tier-3
    const result2 = routeModel(
      createRequest({ complexity: "medium", risk_level: "critical" }),
    );
    expect(result2.recommended_tier).toBe("tier-3");
  });

  it("重试次数提升 tier (escalation)", () => {
    // tier-1 基础 + 1 次重试 -> tier-2
    const result = routeModel(
      createRequest({ complexity: "low", retry_count: 1 }),
    );
    expect(result.recommended_tier).toBe("tier-2");

    // tier-1 基础 + 2 次重试 -> tier-3
    const result2 = routeModel(
      createRequest({ complexity: "low", retry_count: 2 }),
    );
    expect(result2.recommended_tier).toBe("tier-3");
  });

  it("task_type_hint 匹配", () => {
    // "search" 对应 tier-1
    const result = routeModel(
      createRequest({ complexity: "low", task_type_hint: "search" }),
    );
    expect(result.recommended_tier).toBe("tier-1");

    // "planning" 对应 tier-3，即使复杂度低也应取更高 tier
    const result2 = routeModel(
      createRequest({ complexity: "low", task_type_hint: "planning" }),
    );
    expect(result2.recommended_tier).toBe("tier-3");

    // "implementation" 对应 tier-2
    const result3 = routeModel(
      createRequest({ complexity: "low", task_type_hint: "implementation" }),
    );
    expect(result3.recommended_tier).toBe("tier-2");
  });

  it("token_budget 限制上下文预算", () => {
    // 不设预算：使用 tier 默认值
    const resultNoBudget = routeModel(
      createRequest({ complexity: "medium", token_budget: 0 }),
    );
    const tier2Config = DEFAULT_TIER_CONFIGS.find((c) => c.tier === "tier-2")!;
    expect(resultNoBudget.context_budget).toBe(tier2Config.max_context_budget);

    // 设定比 tier 默认更小的预算
    const resultSmallBudget = routeModel(
      createRequest({ complexity: "medium", token_budget: 10000 }),
    );
    expect(resultSmallBudget.context_budget).toBe(10000);

    // 设定比 tier 默认更大的预算 -> 取 tier 默认值
    const resultLargeBudget = routeModel(
      createRequest({ complexity: "medium", token_budget: 999999 }),
    );
    expect(resultLargeBudget.context_budget).toBe(
      tier2Config.max_context_budget,
    );
  });
});

// ============================================================
// applyEscalationPolicy 测试
// ============================================================

describe("applyEscalationPolicy", () => {
  it("正确升级 tier", () => {
    // tier-1 + 0 次重试 -> 保持 tier-1
    expect(applyEscalationPolicy("tier-1", 0)).toBe("tier-1");

    // tier-1 + 1 次重试 -> tier-2
    expect(applyEscalationPolicy("tier-1", 1)).toBe("tier-2");

    // tier-1 + 2 次重试 -> tier-3
    expect(applyEscalationPolicy("tier-1", 2)).toBe("tier-3");

    // tier-2 + 1 次重试 -> tier-3
    expect(applyEscalationPolicy("tier-2", 1)).toBe("tier-3");

    // tier-3 + 任意次数 -> 保持 tier-3（已到最高）
    expect(applyEscalationPolicy("tier-3", 1)).toBe("tier-3");
    expect(applyEscalationPolicy("tier-3", 5)).toBe("tier-3");
  });
});
