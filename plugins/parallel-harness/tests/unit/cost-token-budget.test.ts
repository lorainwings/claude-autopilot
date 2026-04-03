import { describe, test, expect } from "bun:test";
import type { CostBudget, TokenBudget, UsageTelemetry, CostEntry, TaskAttempt, CostSummary, RunConfig } from "../../runtime/schemas/ga-schemas";

describe("Cost/Token Budget Separation (P0-2)", () => {
  test("CostBudget tracks remaining cost units", () => {
    const budget: CostBudget = {
      max_cost_units: 1000,
      remaining_cost_units: 750,
    };
    expect(budget.remaining_cost_units).toBeLessThanOrEqual(budget.max_cost_units);
  });

  test("TokenBudget separates input/output limits", () => {
    const budget: TokenBudget = {
      max_input_tokens: 30000,
      max_output_tokens: 8000,
    };
    expect(budget.max_input_tokens).toBeGreaterThan(0);
    expect(budget.max_output_tokens).toBeGreaterThan(0);
  });

  test("UsageTelemetry records source", () => {
    const telemetry: UsageTelemetry = {
      input_tokens: 5000,
      output_tokens: 2000,
      usage_source: "provider",
      cost_units: 15,
    };
    expect(telemetry.usage_source).toBe("provider");
    expect(telemetry.input_tokens + telemetry.output_tokens).toBe(7000);
  });

  test("UsageTelemetry supports estimated source", () => {
    const telemetry: UsageTelemetry = {
      input_tokens: 4000,
      output_tokens: 0,
      usage_source: "estimated",
      cost_units: 10,
    };
    expect(telemetry.usage_source).toBe("estimated");
  });

  test("CostEntry supports usage_telemetry", () => {
    const entry: CostEntry = {
      entry_id: "ce_1",
      task_id: "t1",
      attempt_id: "a1",
      model_tier: "tier-2",
      tokens_used: 7000,
      cost: 15,
      recorded_at: new Date().toISOString(),
      usage_telemetry: {
        input_tokens: 5000,
        output_tokens: 2000,
        usage_source: "provider",
        cost_units: 15,
      },
    };
    expect(entry.usage_telemetry?.input_tokens).toBe(5000);
    expect(entry.tokens_used).toBe(entry.usage_telemetry!.input_tokens + entry.usage_telemetry!.output_tokens);
  });

  test("RunConfig supports separate cost and token budgets", () => {
    const config: Partial<RunConfig> = {
      budget_limit: 100000,
      cost_budget: { max_cost_units: 500, remaining_cost_units: 500 },
      token_budget: { max_input_tokens: 50000, max_output_tokens: 15000 },
    };
    expect(config.cost_budget).toBeDefined();
    expect(config.token_budget).toBeDefined();
    expect(config.budget_limit).toBe(100000); // backward compat
  });

  test("CostSummary supports telemetry breakdown", () => {
    const summary: CostSummary = {
      total_tokens: 10000,
      total_cost: 25,
      tier_distribution: { "tier-1": 5, "tier-2": 15, "tier-3": 5 },
      total_retries: 1,
      budget_utilization: 0.5,
      telemetry_breakdown: {
        provider_reported: { input_tokens: 8000, output_tokens: 1500, cost_units: 20 },
        estimated: { input_tokens: 500, output_tokens: 0, cost_units: 5 },
      },
    };
    expect(summary.telemetry_breakdown?.provider_reported.input_tokens).toBe(8000);
  });

  test("TaskAttempt supports usage_telemetry alongside legacy fields", () => {
    const attempt: Partial<TaskAttempt> = {
      tokens_used: 7000,
      cost: 15,
      usage_telemetry: {
        input_tokens: 5000,
        output_tokens: 2000,
        usage_source: "provider",
        cost_units: 15,
      },
    };
    expect(attempt.usage_telemetry).toBeDefined();
    expect(attempt.tokens_used).toBe(7000);
  });
});
