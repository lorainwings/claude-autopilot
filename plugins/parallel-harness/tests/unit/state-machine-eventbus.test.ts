/**
 * parallel-harness: 状态机 + EventBus + 成本 测试
 */
import { describe, expect, it, test } from "bun:test";
import {
  isValidRunTransition,
  transitionRunStatus,
  isValidAttemptTransition,
  transitionAttemptStatus,
  emitAudit,
  recordCost,
  isBudgetExhausted,
  DefaultPolicyEngine,
  type ExecutionContext,
} from "../../runtime/engine/orchestrator-runtime";
import { EventBus, createEvent } from "../../runtime/observability/event-bus";
import {
  SCHEMA_VERSION,
  type RunExecution,
  type TaskAttempt,
  type CostLedger,
} from "../../runtime/schemas/ga-schemas";
import type { ModelTier } from "../../runtime/orchestrator/task-graph";

// ============================================================
// 辅助函数
// ============================================================

function createMockExecution(status: string = "pending"): RunExecution {
  return {
    schema_version: SCHEMA_VERSION,
    run_id: "run_test",
    batch_id: "batch_test",
    status: status as any,
    status_history: [{ from: "", to: status, reason: "初始化", timestamp: new Date().toISOString() }],
    active_attempts: {},
    completed_attempts: {},
    verification_results: {},
    approval_records: [],
    policy_violations: [],
    cost_ledger: {
      schema_version: SCHEMA_VERSION,
      run_id: "run_test",
      entries: [],
      total_cost: 0,
      budget_limit: 100000,
      remaining_budget: 100000,
      tier_distribution: {} as any,
    },
    started_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };
}

function createMockAttempt(status: string = "pending"): TaskAttempt {
  return {
    schema_version: SCHEMA_VERSION,
    attempt_id: "att_test",
    run_id: "run_test",
    task_id: "task_test",
    attempt_number: 1,
    status: status as any,
    status_history: [{ from: "", to: status, reason: "初始化", timestamp: new Date().toISOString() }],
    model_tier: "tier-1",
    input_summary: "",
    output_summary: "",
    modified_files: [],
    artifacts: [],
    tokens_used: 0,
    cost: 0,
    pre_checks: [],
    started_at: new Date().toISOString(),
  };
}

function createMockLedger(budget: number = 100000): CostLedger {
  return {
    schema_version: SCHEMA_VERSION,
    run_id: "run_test",
    entries: [],
    total_cost: 0,
    budget_limit: budget,
    remaining_budget: budget,
    tier_distribution: {} as any,
  };
}

function createMockContext(): ExecutionContext {
  return {
    run_id: "run_test",
    batch_id: "batch_test",
    actor: { id: "test-user", type: "user", name: "Test", roles: [] },
    project: { root_path: ".", known_modules: [], scope: {} },
    config: {
      max_concurrency: 5, high_risk_max_concurrency: 2, prioritize_critical_path: true,
      budget_limit: 100000, max_model_tier: "tier-3",
      enabled_gates: [], auto_approve_rules: [], timeout_ms: 600000,
      pr_strategy: "none", enable_autofix: false,
    },
    eventBus: new EventBus(),
    costLedger: createMockLedger(),
    policyEngine: new DefaultPolicyEngine(),
    auditLog: [],
    collectedGateResults: [],
  };
}

// ============================================================
// Run 状态机测试
// ============================================================

describe("Run 状态机", () => {
  describe("isValidRunTransition", () => {
    it("pending -> planned 合法", () => {
      expect(isValidRunTransition("pending", "planned")).toBe(true);
    });
    it("planned -> scheduled 合法", () => {
      expect(isValidRunTransition("planned", "scheduled")).toBe(true);
    });
    it("planned -> awaiting_approval 合法", () => {
      expect(isValidRunTransition("planned", "awaiting_approval")).toBe(true);
    });
    it("running -> succeeded 合法", () => {
      expect(isValidRunTransition("running", "succeeded")).toBe(true);
    });
    it("running -> failed 合法", () => {
      expect(isValidRunTransition("running", "failed")).toBe(true);
    });
    it("pending -> running 非法", () => {
      expect(isValidRunTransition("pending", "running")).toBe(false);
    });
    it("archived -> pending 非法", () => {
      expect(isValidRunTransition("archived", "pending")).toBe(false);
    });
    it("succeeded -> failed 非法", () => {
      expect(isValidRunTransition("succeeded", "failed")).toBe(false);
    });
  });

  describe("transitionRunStatus", () => {
    it("正常迁移记录状态历史", () => {
      const exec = createMockExecution("pending");
      transitionRunStatus(exec, "planned", "规划完成");
      expect(exec.status).toBe("planned");
      expect(exec.status_history.length).toBe(2);
      expect(exec.status_history[1].from).toBe("pending");
      expect(exec.status_history[1].to).toBe("planned");
    });

    it("非法迁移抛出错误", () => {
      const exec = createMockExecution("pending");
      expect(() => transitionRunStatus(exec, "running", "直接跳")).toThrow("非法状态迁移");
    });
  });
});

// ============================================================
// Attempt 状态机测试
// ============================================================

describe("Attempt 状态机", () => {
  describe("isValidAttemptTransition", () => {
    it("pending -> pre_check 合法", () => {
      expect(isValidAttemptTransition("pending", "pre_check")).toBe(true);
    });
    it("executing -> succeeded 合法", () => {
      expect(isValidAttemptTransition("executing", "succeeded")).toBe(true);
    });
    it("pending -> succeeded 非法", () => {
      expect(isValidAttemptTransition("pending", "succeeded")).toBe(false);
    });
  });

  describe("transitionAttemptStatus", () => {
    it("正常迁移并计算 duration_ms", () => {
      const attempt = createMockAttempt("executing");
      attempt.started_at = new Date(Date.now() - 1000).toISOString();
      transitionAttemptStatus(attempt, "succeeded", "成功");
      expect(attempt.status).toBe("succeeded");
      expect(attempt.ended_at).toBeDefined();
      expect(attempt.duration_ms).toBeGreaterThanOrEqual(0);
    });

    it("非法迁移抛出错误", () => {
      const attempt = createMockAttempt("pending");
      expect(() => transitionAttemptStatus(attempt, "succeeded", "直接跳")).toThrow();
    });
  });
});

// ============================================================
// 成本账本测试
// ============================================================

describe("成本账本", () => {
  it("recordCost 正确记录成本和 tier 分布", () => {
    const ledger = createMockLedger(10000);
    recordCost(ledger, "task-1", "att-1", "tier-2", 1000);
    expect(ledger.entries.length).toBe(1);
    expect(ledger.total_cost).toBe(5); // 1000/1000 * 5
    expect(ledger.remaining_budget).toBe(9995);
    expect(ledger.tier_distribution["tier-2"].tokens).toBe(1000);
    expect(ledger.tier_distribution["tier-2"].count).toBe(1);
  });

  it("isBudgetExhausted 正确检测", () => {
    const ledger = createMockLedger(10);
    expect(isBudgetExhausted(ledger)).toBe(false);
    recordCost(ledger, "t", "a", "tier-3", 1000); // 1000/1000 * 25 = 25 > 10
    expect(isBudgetExhausted(ledger)).toBe(true);
  });
});

// ============================================================
// 审计事件测试
// ============================================================

describe("审计事件", () => {
  it("emitAudit 生成正确的审计事件", () => {
    const ctx = createMockContext();
    emitAudit(ctx, "run_created", { intent: "测试" });
    expect(ctx.auditLog.length).toBe(1);
    expect(ctx.auditLog[0].type).toBe("run_created");
    expect(ctx.auditLog[0].run_id).toBe("run_test");
    expect(ctx.auditLog[0].actor.id).toBe("test-user");
  });
});

// ============================================================
// EventBus 测试
// ============================================================

describe("EventBus", () => {
  it("基本发布订阅", () => {
    const bus = new EventBus();
    let received = false;
    bus.on("task_completed", () => { received = true; });
    bus.emit(createEvent("task_completed", {}));
    expect(received).toBe(true);
  });

  it("通配符 * 订阅", () => {
    const bus = new EventBus();
    const events: string[] = [];
    bus.on("*", (e) => { events.push(e.type); });
    bus.emit(createEvent("task_completed", {}));
    bus.emit(createEvent("run_started", {}));
    expect(events).toEqual(["task_completed", "run_started"]);
  });

  it("off 取消订阅", () => {
    const bus = new EventBus();
    let count = 0;
    const fn = () => { count++; };
    bus.on("task_completed", fn);
    bus.emit(createEvent("task_completed", {}));
    bus.off("task_completed", fn);
    bus.emit(createEvent("task_completed", {}));
    expect(count).toBe(1);
  });

  it("getEventLog 过滤查询", () => {
    const bus = new EventBus();
    bus.emit(createEvent("task_completed", {}, { graph_id: "g1" }));
    bus.emit(createEvent("task_failed", {}, { graph_id: "g2" }));
    const filtered = bus.getEventLog({ graph_id: "g1" });
    expect(filtered.length).toBe(1);
    expect(filtered[0].type).toBe("task_completed");
  });

  it("日志截断 maxLogSize", () => {
    const bus = new EventBus(5);
    for (let i = 0; i < 10; i++) {
      bus.emit(createEvent("task_completed", { i }));
    }
    expect(bus.getEventLog().length).toBe(5);
  });

  it("监听器异常不影响其他监听器", () => {
    const bus = new EventBus();
    let called = false;
    bus.on("task_completed", () => { throw new Error("boom"); });
    bus.on("task_completed", () => { called = true; });
    bus.emit(createEvent("task_completed", {}));
    expect(called).toBe(true);
  });

  it("createEvent 正确构造事件", () => {
    const event = createEvent("run_started", { foo: "bar" }, { graph_id: "g1", task_id: "t1" });
    expect(event.type).toBe("run_started");
    expect(event.graph_id).toBe("g1");
    expect(event.task_id).toBe("t1");
    expect(event.payload.foo).toBe("bar");
    expect(event.timestamp).toBeDefined();
  });
});

// ============================================================
// DefaultPolicyEngine 测试
// ============================================================

describe("DefaultPolicyEngine", () => {
  it("无规则时允许所有", () => {
    const engine = new DefaultPolicyEngine();
    const ctx = createMockContext();
    const result = engine.evaluate(ctx, "any_action", {});
    expect(result.allowed).toBe(true);
  });

  it("block 规则阻断执行", () => {
    const engine = new DefaultPolicyEngine([{
      rule_id: "r1", name: "阻断", category: "sensitive_directory",
      condition: { type: "always", params: {} },
      enforcement: "block", enabled: true, priority: 1,
    }]);
    const ctx = createMockContext();
    const result = engine.evaluate(ctx, "test", {});
    expect(result.allowed).toBe(false);
    expect(result.violations.length).toBeGreaterThan(0);
  });

  it("approve 规则要求审批", () => {
    const engine = new DefaultPolicyEngine([{
      rule_id: "r1", name: "需审批", category: "approval_required",
      condition: { type: "always", params: {} },
      enforcement: "approve", enabled: true, priority: 1,
    }]);
    const ctx = createMockContext();
    const result = engine.evaluate(ctx, "test", {});
    expect(result.allowed).toBe(true);
    expect(result.requires_approval).toBe(true);
  });

  it("禁用规则不生效", () => {
    const engine = new DefaultPolicyEngine([{
      rule_id: "r1", name: "禁用", category: "budget_limit",
      condition: { type: "always", params: {} },
      enforcement: "block", enabled: false, priority: 1,
    }]);
    const ctx = createMockContext();
    const result = engine.evaluate(ctx, "test", {});
    expect(result.allowed).toBe(true);
  });

  it("path_match 条件正确匹配", () => {
    const engine = new DefaultPolicyEngine([{
      rule_id: "r1", name: "路径匹配", category: "path_boundary",
      condition: { type: "path_match", params: { pattern: "config/secrets" } },
      enforcement: "block", enabled: true, priority: 1,
    }]);
    const ctx = createMockContext();
    const blocked = engine.evaluate(ctx, "write", { paths: ["config/secrets/key.json"] });
    expect(blocked.allowed).toBe(false);
    const allowed = engine.evaluate(ctx, "write", { paths: ["src/main.ts"] });
    expect(allowed.allowed).toBe(true);
  });
});
