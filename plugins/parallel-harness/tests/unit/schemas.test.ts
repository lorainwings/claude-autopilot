/**
 * ga-schemas.ts 单元测试
 *
 * 覆盖：generateId、SCHEMA_VERSION、FAILURE_ACTION_MAP、DEFAULT_RUN_CONFIG、RunStatus 类型
 */

import { describe, expect, it, test } from "bun:test";
import {
  generateId,
  SCHEMA_VERSION,
  FAILURE_ACTION_MAP,
  DEFAULT_RUN_CONFIG,
  type RunStatus,
  type FailureClass,
  type FailureAction,
} from "../../runtime/schemas/ga-schemas";

// ============================================================
// generateId()
// ============================================================

describe("generateId", () => {
  it("生成的 ID 以指定前缀开头", () => {
    const id = generateId("run");
    expect(id.startsWith("run_")).toBe(true);
  });

  it("支持任意前缀", () => {
    const prefixes = ["att", "evt", "cost", "plan", "sess", "pvio", "route"];
    for (const prefix of prefixes) {
      const id = generateId(prefix);
      expect(id.startsWith(`${prefix}_`)).toBe(true);
    }
  });

  it("格式为 prefix_timestamp_random", () => {
    const id = generateId("test");
    const parts = id.split("_");
    // 至少有 3 段：prefix, timestamp(base36), random(base36)
    expect(parts.length).toBeGreaterThanOrEqual(3);
    expect(parts[0]).toBe("test");
    // timestamp 和 random 部分应为合法的 base36 字符串
    expect(/^[0-9a-z]+$/.test(parts[1])).toBe(true);
    expect(/^[0-9a-z]+$/.test(parts[2])).toBe(true);
  });

  it("连续调用生成唯一 ID", () => {
    const ids = new Set<string>();
    for (let i = 0; i < 1000; i++) {
      ids.add(generateId("uniq"));
    }
    // 1000 次调用应产生 1000 个不同 ID
    expect(ids.size).toBe(1000);
  });

  it("空前缀也能正常工作", () => {
    const id = generateId("");
    expect(id.startsWith("_")).toBe(true);
  });
});

// ============================================================
// SCHEMA_VERSION
// ============================================================

describe("SCHEMA_VERSION", () => {
  it("值为 '1.0.0'", () => {
    expect(SCHEMA_VERSION).toBe("1.0.0");
  });

  it("是字符串类型", () => {
    expect(typeof SCHEMA_VERSION).toBe("string");
  });
});

// ============================================================
// FAILURE_ACTION_MAP
// ============================================================

describe("FAILURE_ACTION_MAP", () => {
  // 所有 FailureClass 枚举值
  const allFailureClasses: FailureClass[] = [
    "transient_tool_failure",
    "permanent_policy_failure",
    "ownership_conflict",
    "budget_exhausted",
    "approval_denied",
    "verification_failed",
    "network_restricted",
    "unsupported_capability",
    "human_intervention_required",
    "timeout",
    "unknown",
  ];

  it("覆盖所有 FailureClass 枚举值", () => {
    for (const fc of allFailureClasses) {
      expect(FAILURE_ACTION_MAP[fc]).toBeDefined();
    }
  });

  it("每个映射都包含 retry/escalate/downgrade/human 四个布尔字段", () => {
    for (const fc of allFailureClasses) {
      const action = FAILURE_ACTION_MAP[fc];
      expect(typeof action.retry).toBe("boolean");
      expect(typeof action.escalate).toBe("boolean");
      expect(typeof action.downgrade).toBe("boolean");
      expect(typeof action.human).toBe("boolean");
    }
  });

  // 关键映射验证
  test("transient_tool_failure: retry=true, escalate=false", () => {
    const action = FAILURE_ACTION_MAP["transient_tool_failure"];
    expect(action.retry).toBe(true);
    expect(action.escalate).toBe(false);
    expect(action.downgrade).toBe(false);
    expect(action.human).toBe(false);
  });

  test("permanent_policy_failure: retry=false, human=true", () => {
    const action = FAILURE_ACTION_MAP["permanent_policy_failure"];
    expect(action.retry).toBe(false);
    expect(action.escalate).toBe(false);
    expect(action.downgrade).toBe(false);
    expect(action.human).toBe(true);
  });

  test("ownership_conflict: downgrade=true", () => {
    const action = FAILURE_ACTION_MAP["ownership_conflict"];
    expect(action.retry).toBe(false);
    expect(action.downgrade).toBe(true);
  });

  test("budget_exhausted: retry=false, downgrade=true, human=true", () => {
    const action = FAILURE_ACTION_MAP["budget_exhausted"];
    expect(action.retry).toBe(false);
    expect(action.downgrade).toBe(true);
    expect(action.human).toBe(true);
  });

  test("verification_failed: retry=true, escalate=true", () => {
    const action = FAILURE_ACTION_MAP["verification_failed"];
    expect(action.retry).toBe(true);
    expect(action.escalate).toBe(true);
  });

  test("timeout: retry=true, escalate=true", () => {
    const action = FAILURE_ACTION_MAP["timeout"];
    expect(action.retry).toBe(true);
    expect(action.escalate).toBe(true);
  });

  test("unknown: retry=true, human=true", () => {
    const action = FAILURE_ACTION_MAP["unknown"];
    expect(action.retry).toBe(true);
    expect(action.human).toBe(true);
  });

  test("approval_denied: retry=false, human=true", () => {
    const action = FAILURE_ACTION_MAP["approval_denied"];
    expect(action.retry).toBe(false);
    expect(action.human).toBe(true);
  });

  test("network_restricted: retry=false, human=true", () => {
    const action = FAILURE_ACTION_MAP["network_restricted"];
    expect(action.retry).toBe(false);
    expect(action.human).toBe(true);
  });

  test("unsupported_capability: escalate=true", () => {
    const action = FAILURE_ACTION_MAP["unsupported_capability"];
    expect(action.retry).toBe(false);
    expect(action.escalate).toBe(true);
  });

  test("human_intervention_required: human=true, 其余全 false", () => {
    const action = FAILURE_ACTION_MAP["human_intervention_required"];
    expect(action.retry).toBe(false);
    expect(action.escalate).toBe(false);
    expect(action.downgrade).toBe(false);
    expect(action.human).toBe(true);
  });
});

// ============================================================
// DEFAULT_RUN_CONFIG
// ============================================================

describe("DEFAULT_RUN_CONFIG", () => {
  it("max_concurrency 为正整数", () => {
    expect(DEFAULT_RUN_CONFIG.max_concurrency).toBeGreaterThan(0);
    expect(Number.isInteger(DEFAULT_RUN_CONFIG.max_concurrency)).toBe(true);
  });

  it("high_risk_max_concurrency 小于等于 max_concurrency", () => {
    expect(DEFAULT_RUN_CONFIG.high_risk_max_concurrency).toBeLessThanOrEqual(
      DEFAULT_RUN_CONFIG.max_concurrency
    );
    expect(DEFAULT_RUN_CONFIG.high_risk_max_concurrency).toBeGreaterThan(0);
  });

  it("prioritize_critical_path 默认为 true", () => {
    expect(DEFAULT_RUN_CONFIG.prioritize_critical_path).toBe(true);
  });

  it("budget_limit 为正数", () => {
    expect(DEFAULT_RUN_CONFIG.budget_limit).toBeGreaterThan(0);
  });

  it("max_model_tier 为合法的 tier 值", () => {
    expect(["tier-1", "tier-2", "tier-3"]).toContain(
      DEFAULT_RUN_CONFIG.max_model_tier
    );
  });

  it("enabled_gates 包含核心 gate 类型", () => {
    expect(DEFAULT_RUN_CONFIG.enabled_gates).toContain("test");
    expect(DEFAULT_RUN_CONFIG.enabled_gates).toContain("lint_type");
    expect(DEFAULT_RUN_CONFIG.enabled_gates).toContain("review");
    expect(DEFAULT_RUN_CONFIG.enabled_gates).toContain("policy");
  });

  it("auto_approve_rules 默认为空数组", () => {
    expect(DEFAULT_RUN_CONFIG.auto_approve_rules).toEqual([]);
  });

  it("timeout_ms 为正数且至少 60 秒", () => {
    expect(DEFAULT_RUN_CONFIG.timeout_ms).toBeGreaterThanOrEqual(60000);
  });

  it("pr_strategy 为合法值", () => {
    expect(["none", "single_pr", "stacked_pr"]).toContain(
      DEFAULT_RUN_CONFIG.pr_strategy
    );
  });

  it("enable_autofix 默认为 false", () => {
    expect(DEFAULT_RUN_CONFIG.enable_autofix).toBe(false);
  });
});

// ============================================================
// RunStatus 类型覆盖（编译时 + 运行时检验）
// ============================================================

describe("RunStatus 类型覆盖", () => {
  // 在运行时列举所有预期状态，确保类型正确
  const allStatuses: RunStatus[] = [
    "pending",
    "planned",
    "awaiting_approval",
    "scheduled",
    "running",
    "verifying",
    "blocked",
    "failed",
    "partially_failed",
    "succeeded",
    "cancelled",
    "archived",
  ];

  it("包含 12 种状态", () => {
    expect(allStatuses.length).toBe(12);
  });

  it("所有状态值互不相同", () => {
    const unique = new Set(allStatuses);
    expect(unique.size).toBe(allStatuses.length);
  });

  it("每个状态值都是字符串", () => {
    for (const s of allStatuses) {
      expect(typeof s).toBe("string");
    }
  });

  // 编译时类型安全测试：如果遗漏某个状态，下面的函数签名会导致 TypeScript 编译失败
  it("类型穷尽性检查（编译时保护）", () => {
    function exhaustiveCheck(status: RunStatus): string {
      switch (status) {
        case "pending":           return "pending";
        case "planned":           return "planned";
        case "awaiting_approval": return "awaiting_approval";
        case "scheduled":         return "scheduled";
        case "running":           return "running";
        case "verifying":         return "verifying";
        case "blocked":           return "blocked";
        case "failed":            return "failed";
        case "partially_failed":  return "partially_failed";
        case "succeeded":         return "succeeded";
        case "cancelled":         return "cancelled";
        case "archived":          return "archived";
        default: {
          // 如果 RunStatus 新增了值但此处未处理，TypeScript 会报错
          const _exhaustive: never = status;
          return _exhaustive;
        }
      }
    }

    // 验证每个状态都能正常通过 switch
    for (const s of allStatuses) {
      expect(exhaustiveCheck(s)).toBe(s);
    }
  });
});
