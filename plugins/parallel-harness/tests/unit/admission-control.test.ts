import { describe, it, expect } from "bun:test";
import { estimateBatchCost, admitBatch, admitTask } from "../../runtime/engine/admission-control";
import type { CostLedger } from "../../runtime/schemas/ga-schemas";
import type { TaskNode } from "../../runtime/orchestrator/task-graph";

import { SCHEMA_VERSION } from "../../runtime/schemas/ga-schemas";

function createMockLedger(budget: number, spent: number): CostLedger {
  return {
    schema_version: SCHEMA_VERSION,
    run_id: "run_test",
    budget_limit: budget,
    total_cost: spent,
    remaining_budget: budget - spent,
    entries: [],
    tier_distribution: {
      "tier-1": { tokens: 0, cost: 0, count: 0 },
      "tier-2": { tokens: 0, cost: 0, count: 0 },
      "tier-3": { tokens: 0, cost: 0, count: 0 },
    },
  };
}

function createMockTask(tier: "tier-1" | "tier-2" | "tier-3" = "tier-2"): TaskNode {
  return {
    id: "task_test",
    title: "测试任务",
    goal: "测试",
    dependencies: [],
    status: "pending",
    risk_level: "low",
    complexity: {
      level: "low",
      score: 20,
      dimensions: { file_count: 1, module_count: 1, involves_critical: false, estimated_tokens: 2000 },
      reasoning: "测试任务",
    },
    allowed_paths: ["."],
    forbidden_paths: [],
    acceptance_criteria: [],
    required_tests: [],
    model_tier: tier,
    verifier_set: [],
    retry_policy: { max_retries: 0, escalate_on_retry: false, compact_context_on_retry: false },
  };
}

describe("estimateBatchCost", () => {
  it("正确计算单个 tier-1 任务成本", () => {
    const cost = estimateBatchCost([createMockTask("tier-1")], 2000);
    // (2000/1000) * 1 = 2
    expect(cost).toBe(2);
  });

  it("正确计算混合 tier 批次成本", () => {
    const batch = [
      createMockTask("tier-1"),
      createMockTask("tier-2"),
      createMockTask("tier-3"),
    ];
    const cost = estimateBatchCost(batch, 1000);
    // tier-1: 1, tier-2: 5, tier-3: 25 = 31
    expect(cost).toBe(31);
  });

  it("空批次成本为零", () => {
    expect(estimateBatchCost([])).toBe(0);
  });
});

describe("admitBatch", () => {
  it("充足预算放行", () => {
    const ledger = createMockLedger(1000, 0);
    const result = admitBatch(ledger, 100);
    expect(result.admitted).toBe(true);
    expect(result.remaining_budget).toBe(1000);
  });

  it("预算刚好不足拒绝", () => {
    const ledger = createMockLedger(100, 95);
    const result = admitBatch(ledger, 10);
    expect(result.admitted).toBe(false);
    expect(result.reason).toContain("预算不足");
  });

  it("预算已耗尽拒绝", () => {
    const ledger = createMockLedger(100, 100);
    const result = admitBatch(ledger, 1);
    expect(result.admitted).toBe(false);
    expect(result.reason).toContain("预算已耗尽");
  });

  it("预算刚好等于预估成本时放行", () => {
    const ledger = createMockLedger(100, 90);
    const result = admitBatch(ledger, 10);
    expect(result.admitted).toBe(true);
  });
});

describe("admitTask", () => {
  it("单任务准入检查", () => {
    const ledger = createMockLedger(1000, 0);
    const task = createMockTask("tier-3");
    const result = admitTask(ledger, task, 1000);
    // tier-3: (1000/1000) * 25 = 25, budget 1000, admitted
    expect(result.admitted).toBe(true);
    expect(result.estimated_cost).toBe(25);
  });
});
