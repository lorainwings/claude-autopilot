/**
 * parallel-harness: Gate System + 治理 + 持久化 + Merge Guard 测试
 */
import { describe, expect, it, beforeEach } from "bun:test";
import { GateSystem, DEFAULT_GATE_CONTRACTS } from "../../runtime/gates/gate-system";
import { RBACEngine, ApprovalWorkflow, HumanInteractionManager, BUILT_IN_ROLES } from "../../runtime/governance/governance";
import { MergeGuard } from "../../runtime/guards/merge-guard";
import {
  LocalMemoryStore, SessionStore, RunStore, AuditTrail, ReplayEngine,
} from "../../runtime/persistence/session-persistence";
import { EventBus } from "../../runtime/observability/event-bus";
import { DefaultPolicyEngine, type ExecutionContext } from "../../runtime/engine/orchestrator-runtime";
import { SCHEMA_VERSION, generateId, type SessionState, type RunRequest, type RunExecution, type AuditEvent } from "../../runtime/schemas/ga-schemas";
import type { TaskGraph, TaskNode, TaskEdge } from "../../runtime/orchestrator/task-graph";
import type { WorkerOutput } from "../../runtime/orchestrator/role-contracts";
import type { OwnershipPlan } from "../../runtime/orchestrator/ownership-planner";

// ============================================================
// 辅助函数
// ============================================================

function createMockContext(policyEngine = new DefaultPolicyEngine()): ExecutionContext {
  return {
    run_id: "run_test", batch_id: "batch_test",
    actor: { id: "test-user", type: "user", name: "Test", roles: ["developer"] },
    project: { root_path: ".", known_modules: [], scope: {} },
    config: {
      max_concurrency: 5, high_risk_max_concurrency: 2, prioritize_critical_path: true,
      budget_limit: 100000, max_model_tier: "tier-3", enabled_gates: [],
      auto_approve_rules: [], timeout_ms: 600000, pr_strategy: "none", enable_autofix: false,
    },
    eventBus: new EventBus(),
    costLedger: {
      schema_version: SCHEMA_VERSION, run_id: "run_test", entries: [],
      total_cost: 0, budget_limit: 100000, remaining_budget: 100000, tier_distribution: {} as any,
    },
    policyEngine,
    auditLog: [],
    collectedGateResults: [],
  };
}

function createMockTask(overrides: Partial<TaskNode> = {}): TaskNode {
  return {
    id: "task-1", title: "测试任务", goal: "完成测试", dependencies: [],
    status: "pending", risk_level: "low",
    complexity: { level: "low", score: 20, dimensions: { file_count: 1, module_count: 1, involves_critical: false, estimated_tokens: 1000 }, reasoning: "" },
    allowed_paths: ["src/"], forbidden_paths: ["config/"],
    acceptance_criteria: [], required_tests: [], model_tier: "tier-1", verifier_set: ["test"],
    retry_policy: { max_retries: 2, escalate_on_retry: true, compact_context_on_retry: true },
    ...overrides,
  };
}

function createMockGraph(tasks: TaskNode[], edges: TaskEdge[] = []): TaskGraph {
  return {
    graph_id: "test-graph", tasks, edges, critical_path: tasks.map(t => t.id),
    metadata: { created_at: new Date().toISOString(), original_intent: "测试", total_tasks: tasks.length, max_parallelism: 1, critical_path_length: tasks.length, estimated_total_tokens: 1000 },
  };
}

function createMockOwnershipPlan(taskIds: string[]): OwnershipPlan {
  return {
    assignments: taskIds.map(id => ({ task_id: id, exclusive_paths: [`src/${id}/`], shared_read_paths: [], forbidden_paths: [] })),
    conflicts: [], has_unresolvable_conflicts: false, downgrade_suggestions: [],
  };
}

function createMockSession(runId: string): SessionState {
  return {
    schema_version: SCHEMA_VERSION, session_id: generateId("sess"), run_id: runId,
    created_at: new Date().toISOString(), last_active_at: new Date().toISOString(),
    status: "active", checkpoint: {}, human_feedback: [],
  };
}

// ============================================================
// Gate System 测试
// ============================================================

describe("GateSystem", () => {
  it("构造函数注册 9 个评估器", () => {
    const gs = new GateSystem();
    expect(gs.getRegisteredTypes().length).toBe(9);
  });

  it("getContracts 返回默认合同", () => {
    const gs = new GateSystem();
    expect(gs.getContracts().length).toBe(DEFAULT_GATE_CONTRACTS.length);
  });

  it("hasBlockingFailure: blocking+failed -> true", () => {
    const gs = new GateSystem();
    const results = [{ gate_id: "g1", gate_type: "test" as any, gate_level: "task" as any, run_id: "r1", passed: false, blocking: true, conclusion: { summary: "", findings: [], risk: "high" as any, required_actions: [], suggested_patches: [] }, evaluated_at: new Date().toISOString(), schema_version: SCHEMA_VERSION }];
    expect(gs.hasBlockingFailure(results)).toBe(true);
  });

  it("hasBlockingFailure: non-blocking+failed -> false", () => {
    const gs = new GateSystem();
    const results = [{ gate_id: "g1", gate_type: "review" as any, gate_level: "task" as any, run_id: "r1", passed: false, blocking: false, conclusion: { summary: "", findings: [], risk: "low" as any, required_actions: [], suggested_patches: [] }, evaluated_at: new Date().toISOString(), schema_version: SCHEMA_VERSION }];
    expect(gs.hasBlockingFailure(results)).toBe(false);
  });

  it("hasBlockingFailure: blocking+passed -> false", () => {
    const gs = new GateSystem();
    const results = [{ gate_id: "g1", gate_type: "test" as any, gate_level: "task" as any, run_id: "r1", passed: true, blocking: true, conclusion: { summary: "", findings: [], risk: "low" as any, required_actions: [], suggested_patches: [] }, evaluated_at: new Date().toISOString(), schema_version: SCHEMA_VERSION }];
    expect(gs.hasBlockingFailure(results)).toBe(false);
  });

  it("evaluate 只评估 enabledTypes 中的 gate", async () => {
    const gs = new GateSystem();
    const ctx = createMockContext();
    const workerOutput: WorkerOutput = { status: "ok", summary: "完成", artifacts: [], modified_paths: [], tokens_used: 0, duration_ms: 100, actual_tool_calls: [], exit_code: 0 };
    const results = await gs.evaluate({ ctx, workerOutput, level: "task" }, ["review"]);
    expect(results.length).toBe(1);
    expect(results[0].gate_type).toBe("review");
  });

  it("security gate 检测敏感文件", async () => {
    const gs = new GateSystem();
    const ctx = createMockContext();
    const workerOutput: WorkerOutput = { status: "ok", summary: "", artifacts: [], modified_paths: [".env"], tokens_used: 0, duration_ms: 0, actual_tool_calls: [], exit_code: 0 };
    const results = await gs.evaluate({ ctx, workerOutput, level: "run" }, ["security"]);
    expect(results.length).toBe(1);
    expect(results[0].passed).toBe(false);
    expect(results[0].conclusion.findings.some(f => f.severity === "critical")).toBe(true);
  });
});

// ============================================================
// RBAC 测试
// ============================================================

describe("RBACEngine", () => {
  it("admin 角色有所有 12 个权限", () => {
    const rbac = new RBACEngine();
    const admin = { id: "u1", type: "user" as const, name: "Admin", roles: ["admin"] };
    const allPerms = BUILT_IN_ROLES.find(r => r.name === "admin")!.permissions;
    for (const perm of allPerms) {
      expect(rbac.hasPermission(admin, perm)).toBe(true);
    }
  });

  it("viewer 角色只有 run.view 和 audit.view", () => {
    const rbac = new RBACEngine();
    const viewer = { id: "u2", type: "user" as const, name: "Viewer", roles: ["viewer"] };
    expect(rbac.hasPermission(viewer, "run.view")).toBe(true);
    expect(rbac.hasPermission(viewer, "audit.view")).toBe(true);
    expect(rbac.hasPermission(viewer, "run.create")).toBe(false);
    expect(rbac.hasPermission(viewer, "policy.manage")).toBe(false);
  });

  it("system actor 始终有所有权限", () => {
    const rbac = new RBACEngine();
    const system = { id: "sys", type: "system" as const, name: "System", roles: [] };
    expect(rbac.hasPermission(system, "run.create")).toBe(true);
    expect(rbac.hasPermission(system, "policy.manage")).toBe(true);
    expect(rbac.hasPermission(system, "audit.export")).toBe(true);
  });

  it("assignRole/revokeRole 正常工作", () => {
    const rbac = new RBACEngine();
    const user = { id: "u3", type: "user" as const, name: "User", roles: [] };
    expect(rbac.hasPermission(user, "run.create")).toBe(false);
    rbac.assignRole("u3", "developer");
    expect(rbac.hasPermission(user, "run.create")).toBe(true);
    rbac.revokeRole("u3", "developer");
    expect(rbac.hasPermission(user, "run.create")).toBe(false);
  });
});

// ============================================================
// Approval Workflow 测试
// ============================================================

describe("ApprovalWorkflow", () => {
  it("requestApproval 返回 pending", () => {
    const wf = new ApprovalWorkflow();
    const result = wf.requestApproval({ run_id: "r1", action: "execute", reason: "测试", triggered_rules: [] });
    expect(result.status).toBe("pending");
    expect(result.approval_id).toBeDefined();
  });

  it("自动审批规则 all 自动通过", () => {
    const wf = new ApprovalWorkflow(["all"]);
    const result = wf.requestApproval({ run_id: "r1", action: "execute", reason: "测试", triggered_rules: [] });
    expect(result.status).toBe("approved");
    expect(wf.getPending().length).toBe(0);
  });

  it("自动审批规则匹配 action 自动通过", () => {
    const wf = new ApprovalWorkflow(["execute"]);
    const result = wf.requestApproval({ run_id: "r1", action: "execute", reason: "测试", triggered_rules: [] });
    expect(result.status).toBe("approved");
  });

  it("decide approved 正确记录", () => {
    const wf = new ApprovalWorkflow();
    const req = wf.requestApproval({ run_id: "r1", action: "execute", reason: "测试", triggered_rules: [] });
    const record = wf.decide(req.approval_id, "approved", "admin");
    expect(record).toBeDefined();
    expect(record!.decision).toBe("approved");
    expect(record!.decided_by).toBe("admin");
  });

  it("decide denied 正确记录", () => {
    const wf = new ApprovalWorkflow();
    const req = wf.requestApproval({ run_id: "r1", action: "execute", reason: "测试", triggered_rules: [] });
    const record = wf.decide(req.approval_id, "denied", "admin", "不允许");
    expect(record!.decision).toBe("denied");
    expect(record!.comment).toBe("不允许");
  });

  it("decide 不存在的 approval 返回 undefined", () => {
    const wf = new ApprovalWorkflow();
    const result = wf.decide("nonexistent", "approved", "admin");
    expect(result).toBeUndefined();
  });

  it("rehydrate 恢复 pending approval", () => {
    const wf = new ApprovalWorkflow();
    const req: any = { approval_id: "appr_test", run_id: "r1", action: "exec", reason: "测试", triggered_rules: [], status: "pending", requested_at: new Date().toISOString() };
    wf.rehydrate(req);
    expect(wf.getPending().length).toBe(1);
  });

  it("getPending 和 getHistory 正确返回", () => {
    const wf = new ApprovalWorkflow();
    const req = wf.requestApproval({ run_id: "r1", action: "execute", reason: "测试", triggered_rules: [] });
    expect(wf.getPending().length).toBe(1);
    wf.decide(req.approval_id, "approved", "admin");
    expect(wf.getPending().length).toBe(0);
    expect(wf.getHistory().length).toBe(1);
  });
});

// ============================================================
// Human Interaction 测试
// ============================================================

describe("HumanInteractionManager", () => {
  it("requestFeedback 返回 ID", () => {
    const mgr = new HumanInteractionManager();
    const id = mgr.requestFeedback({ run_id: "r1", question: "确认？", context: "测试", urgency: "low" });
    expect(id).toBeDefined();
    expect(mgr.getPendingRequests().length).toBe(1);
  });

  it("submitFeedback 正确记录", () => {
    const mgr = new HumanInteractionManager();
    const id = mgr.requestFeedback({ run_id: "r1", question: "确认？", context: "测试", urgency: "medium" });
    const actor = { id: "u1", type: "user" as const, name: "User", roles: [] };
    const response = mgr.submitFeedback(id, "确认", actor);
    expect(response).toBeDefined();
    expect(response!.response).toBe("确认");
    expect(mgr.getPendingRequests().length).toBe(0);
  });
});

// ============================================================
// Merge Guard 测试
// ============================================================

describe("MergeGuard", () => {
  it("无违规时 allowed=true", () => {
    const guard = new MergeGuard();
    const ctx = createMockContext();
    const tasks = [createMockTask({ id: "t1" })];
    const graph = createMockGraph(tasks);
    const ownership = createMockOwnershipPlan(["t1"]);
    const outputs = new Map<string, WorkerOutput>([["t1", { status: "ok", summary: "", artifacts: [], modified_paths: ["src/t1/file.ts"], tokens_used: 0, duration_ms: 0, actual_tool_calls: [], exit_code: 0 }]]);
    const result = guard.check(ctx, graph, ownership, outputs);
    expect(result.allowed).toBe(true);
    expect(result.ownership_violations.length).toBe(0);
  });

  it("所有权违规时 allowed=false", () => {
    const guard = new MergeGuard();
    const ctx = createMockContext();
    const tasks = [createMockTask({ id: "t1" })];
    const graph = createMockGraph(tasks);
    const ownership = createMockOwnershipPlan(["t1"]);
    // t1 只允许写 src/t1/，但实际修改了 lib/
    const outputs = new Map<string, WorkerOutput>([["t1", { status: "ok", summary: "", artifacts: [], modified_paths: ["lib/other.ts"], tokens_used: 0, duration_ms: 0, actual_tool_calls: [], exit_code: 0 }]]);
    const result = guard.check(ctx, graph, ownership, outputs);
    expect(result.ownership_violations.length).toBeGreaterThan(0);
    expect(result.allowed).toBe(false);
  });

  it("多任务写同一文件检测冲突", () => {
    const guard = new MergeGuard();
    const ctx = createMockContext();
    const tasks = [createMockTask({ id: "t1" }), createMockTask({ id: "t2" })];
    const graph = createMockGraph(tasks);
    const ownership: OwnershipPlan = {
      assignments: [
        { task_id: "t1", exclusive_paths: ["src/"], shared_read_paths: [], forbidden_paths: [] },
        { task_id: "t2", exclusive_paths: ["src/"], shared_read_paths: [], forbidden_paths: [] },
      ],
      conflicts: [], has_unresolvable_conflicts: false, downgrade_suggestions: [],
    };
    const outputs = new Map<string, WorkerOutput>([
      ["t1", { status: "ok", summary: "", artifacts: [], modified_paths: ["src/shared.ts"], tokens_used: 0, duration_ms: 0, actual_tool_calls: [], exit_code: 0 }],
      ["t2", { status: "ok", summary: "", artifacts: [], modified_paths: ["src/shared.ts"], tokens_used: 0, duration_ms: 0, actual_tool_calls: [], exit_code: 0 }],
    ]);
    const result = guard.check(ctx, graph, ownership, outputs);
    expect(result.file_conflicts.length).toBeGreaterThan(0);
    expect(result.file_conflicts[0].type).toBe("concurrent_write");
  });

  it("schema/config 冲突建议 manual 解决", () => {
    const guard = new MergeGuard();
    const ctx = createMockContext();
    const tasks = [createMockTask({ id: "t1" }), createMockTask({ id: "t2" })];
    const graph = createMockGraph(tasks);
    const ownership: OwnershipPlan = {
      assignments: [
        { task_id: "t1", exclusive_paths: ["db/"], shared_read_paths: [], forbidden_paths: [] },
        { task_id: "t2", exclusive_paths: ["db/"], shared_read_paths: [], forbidden_paths: [] },
      ],
      conflicts: [], has_unresolvable_conflicts: false, downgrade_suggestions: [],
    };
    const outputs = new Map<string, WorkerOutput>([
      ["t1", { status: "ok", summary: "", artifacts: [], modified_paths: ["db/schema.ts"], tokens_used: 0, duration_ms: 0, actual_tool_calls: [], exit_code: 0 }],
      ["t2", { status: "ok", summary: "", artifacts: [], modified_paths: ["db/schema.ts"], tokens_used: 0, duration_ms: 0, actual_tool_calls: [], exit_code: 0 }],
    ]);
    const result = guard.check(ctx, graph, ownership, outputs);
    expect(result.file_conflicts[0].resolution).toBe("manual");
  });
});

// ============================================================
// LocalMemoryStore 测试
// ============================================================

describe("LocalMemoryStore", () => {
  it("set/get 正常工作", async () => {
    const store = new LocalMemoryStore<{ value: string }>();
    await store.set("key1", { value: "test" });
    const result = await store.get("key1");
    expect(result?.value).toBe("test");
  });

  it("delete 正常工作", async () => {
    const store = new LocalMemoryStore<string>();
    await store.set("k1", "v1");
    await store.delete("k1");
    expect(await store.get("k1")).toBeUndefined();
  });

  it("list 返回所有", async () => {
    const store = new LocalMemoryStore<string>();
    await store.set("a", "1");
    await store.set("b", "2");
    const list = await store.list();
    expect(list.length).toBe(2);
  });

  it("count 返回正确数量", async () => {
    const store = new LocalMemoryStore<number>();
    await store.set("a", 1);
    await store.set("b", 2);
    expect(await store.count()).toBe(2);
  });

  it("get 不存在返回 undefined", async () => {
    const store = new LocalMemoryStore<string>();
    expect(await store.get("nonexistent")).toBeUndefined();
  });
});

// ============================================================
// SessionStore 测试
// ============================================================

describe("SessionStore", () => {
  it("save/get 正常", async () => {
    const ss = new SessionStore();
    const session = createMockSession("run_001");
    await ss.save(session);
    const found = await ss.get(session.session_id);
    expect(found?.run_id).toBe("run_001");
  });

  it("getByRunId 正确查找", async () => {
    const ss = new SessionStore();
    const session = createMockSession("run_999");
    await ss.save(session);
    const found = await ss.getByRunId("run_999");
    expect(found).toBeDefined();
  });

  it("updateCheckpoint 更新检查点", async () => {
    const ss = new SessionStore();
    const session = createMockSession("run_ck");
    await ss.save(session);
    await ss.updateCheckpoint(session.session_id, { phase: "execution" });
    const updated = await ss.get(session.session_id);
    expect(updated?.checkpoint.phase).toBe("execution");
  });

  it("complete 标记完成", async () => {
    const ss = new SessionStore();
    const session = createMockSession("run_cmp");
    await ss.save(session);
    await ss.complete(session.session_id);
    const updated = await ss.get(session.session_id);
    expect(updated?.status).toBe("completed");
  });

  it("listActive 只返回活跃 session", async () => {
    const ss = new SessionStore();
    const s1 = createMockSession("r1");
    const s2 = createMockSession("r2");
    await ss.save(s1);
    await ss.save(s2);
    await ss.complete(s1.session_id);
    const active = await ss.listActive();
    expect(active.length).toBe(1);
    expect(active[0].session_id).toBe(s2.session_id);
  });
});

// ============================================================
// AuditTrail 测试
// ============================================================

function createMockAuditEvent(runId: string, type: string = "run_created"): AuditEvent {
  return {
    schema_version: SCHEMA_VERSION, event_id: generateId("evt"), type: type as any,
    timestamp: new Date().toISOString(),
    actor: { id: "u1", type: "user", name: "Test", roles: [] },
    run_id: runId, payload: {}, scope: {},
  };
}

describe("AuditTrail", () => {
  it("recordBatch + flush 持久化", async () => {
    const trail = new AuditTrail(undefined, 3);
    await trail.recordBatch([createMockAuditEvent("r1"), createMockAuditEvent("r1")]);
    const events = await trail.query({ run_id: "r1" });
    expect(events.length).toBe(2);
  });

  it("query 按 run_id 过滤", async () => {
    const trail = new AuditTrail();
    await trail.recordBatch([createMockAuditEvent("r1"), createMockAuditEvent("r2")]);
    await trail.flush();
    const events = await trail.query({ run_id: "r1" });
    expect(events.length).toBe(1);
  });

  it("getTimeline 按时间排序", async () => {
    const trail = new AuditTrail();
    const e1 = createMockAuditEvent("r1");
    e1.timestamp = "2026-01-01T00:00:01Z";
    const e2 = createMockAuditEvent("r1");
    e2.timestamp = "2026-01-01T00:00:00Z";
    await trail.recordBatch([e1, e2]);
    await trail.flush();
    const timeline = await trail.getTimeline("r1");
    expect(new Date(timeline[0].timestamp).getTime()).toBeLessThan(new Date(timeline[1].timestamp).getTime());
  });

  it("export JSON 格式", async () => {
    const trail = new AuditTrail();
    await trail.record(createMockAuditEvent("r1"));
    await trail.flush();
    const json = await trail.export("json");
    expect(() => JSON.parse(json)).not.toThrow();
  });

  it("export CSV 格式", async () => {
    const trail = new AuditTrail();
    await trail.record(createMockAuditEvent("r1"));
    await trail.flush();
    const csv = await trail.export("csv");
    expect(csv).toContain("event_id");
    expect(csv).toContain("timestamp");
  });

  it("getBufferSize 返回缓冲大小", async () => {
    const trail = new AuditTrail(undefined, 100);
    await trail.record(createMockAuditEvent("r1"));
    expect(trail.getBufferSize()).toBe(1);
  });
});

// ============================================================
// ReplayEngine 测试
// ============================================================

describe("ReplayEngine", () => {
  it("getReplayTimeline 返回排序事件", async () => {
    const trail = new AuditTrail();
    const events = [createMockAuditEvent("r1", "run_started"), createMockAuditEvent("r1", "task_completed")];
    events[0].timestamp = "2026-01-01T00:00:00Z";
    events[1].timestamp = "2026-01-01T00:00:01Z";
    await trail.recordBatch(events);
    await trail.flush();
    const engine = new ReplayEngine(trail);
    const timeline = await engine.getReplayTimeline("r1");
    expect(timeline.length).toBe(2);
  });

  it("getResumePoint 返回正确信息", async () => {
    const trail = new AuditTrail();
    const events = [
      { ...createMockAuditEvent("r1", "task_completed"), task_id: "task-1" },
    ];
    await trail.recordBatch(events);
    await trail.flush();
    const engine = new ReplayEngine(trail);
    const point = await engine.getResumePoint("r1");
    expect(point).toBeDefined();
    expect(point!.run_id).toBe("r1");
  });
});
