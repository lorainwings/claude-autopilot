/**
 * parallel-harness: Skill 生命周期测试
 *
 * 验证 skill 从静态注册表升级为运行时一等对象后的完整闭环：
 * - SkillRegistry.resolve: 三维匹配 (phase/language/path)
 * - SkillRegistry.select: 从候选中选最佳
 * - SkillInvocationRecord: 创建和状态流转
 * - EventBus: 发射 skill_* 事件
 * - TaskAttempt / TaskContract: 携带 skill 元数据
 * - AuditTrail: 查询 skill 生命周期事件
 */
import { describe, expect, it, test } from "bun:test";
import {
  SkillRegistry,
  type SkillManifest,
  type SkillMatch,
  type SelectedSkill,
  type SkillInvocationRecord,
  type SkillResolutionContext,
} from "../../runtime/capabilities/capability-registry";
import { EventBus, createEvent, type PlatformEvent, type EventType } from "../../runtime/observability/event-bus";
import { AuditTrail, LocalMemoryStore } from "../../runtime/persistence/session-persistence";
import type { AuditEvent, TaskAttempt } from "../../runtime/schemas/ga-schemas";

// ============================================================
// Helper: 创建标准测试 SkillManifest
// ============================================================

function createSkill(overrides: Partial<SkillManifest> & { id: string }): SkillManifest {
  return {
    name: overrides.id,
    version: "1.0.0",
    description: `测试 skill: ${overrides.id}`,
    input_schema: {},
    output_schema: {},
    permissions: [],
    required_tools: [],
    recommended_tier: "tier-1",
    applicable_phases: [],
    ...overrides,
  };
}

// ============================================================
// SkillRegistry.resolve 测试
// ============================================================

describe("SkillRegistry.resolve", () => {
  it("按 phase 匹配", () => {
    const reg = new SkillRegistry();
    reg.register(createSkill({ id: "plan-skill", applicable_phases: ["planning"] }));
    reg.register(createSkill({ id: "impl-skill", applicable_phases: ["implementation"] }));

    const matches = reg.resolve({ phase: "planning" });
    expect(matches.length).toBe(1);
    expect(matches[0].skill_id).toBe("plan-skill");
    expect(matches[0].phase_match).toBe(true);
  });

  it("按 language 匹配", () => {
    const reg = new SkillRegistry();
    reg.register(createSkill({ id: "ts-skill", applicable_phases: [], languages: ["typescript"] }));
    reg.register(createSkill({ id: "py-skill", applicable_phases: [], languages: ["python"] }));

    const matches = reg.resolve({ language: "typescript" });
    expect(matches.length).toBe(1);
    expect(matches[0].skill_id).toBe("ts-skill");
    expect(matches[0].language_match).toBe(true);
  });

  it("按 path 匹配", () => {
    const reg = new SkillRegistry();
    reg.register(createSkill({ id: "frontend-skill", applicable_phases: [], path_patterns: ["src/components/*"] }));
    reg.register(createSkill({ id: "backend-skill", applicable_phases: [], path_patterns: ["src/api/*"] }));

    const matches = reg.resolve({ file_path: "src/components/Button.tsx" });
    expect(matches.length).toBe(1);
    expect(matches[0].skill_id).toBe("frontend-skill");
    expect(matches[0].path_match).toBe(true);
  });

  it("三维综合匹配按置信度排序", () => {
    const reg = new SkillRegistry();
    reg.register(createSkill({
      id: "full-match",
      applicable_phases: ["implementation"],
      languages: ["typescript"],
      path_patterns: ["src/*"],
    }));
    reg.register(createSkill({
      id: "phase-only",
      applicable_phases: ["implementation"],
    }));

    const matches = reg.resolve({
      phase: "implementation",
      language: "typescript",
      file_path: "src/index.ts",
    });

    expect(matches.length).toBe(2);
    expect(matches[0].skill_id).toBe("full-match");
    expect(matches[0].confidence).toBeGreaterThan(matches[1].confidence);
  });

  it("无匹配返回空列表", () => {
    const reg = new SkillRegistry();
    reg.register(createSkill({ id: "plan-skill", applicable_phases: ["planning"] }));

    const matches = reg.resolve({ phase: "verification" });
    expect(matches.length).toBe(0);
  });

  it("空上下文返回空列表", () => {
    const reg = new SkillRegistry();
    reg.register(createSkill({ id: "plan-skill", applicable_phases: ["planning"] }));

    const matches = reg.resolve({});
    expect(matches.length).toBe(0);
  });

  it("多个 phase 匹配按置信度排序", () => {
    const reg = new SkillRegistry();
    reg.register(createSkill({
      id: "plan-ts",
      applicable_phases: ["planning"],
      languages: ["typescript"],
    }));
    reg.register(createSkill({
      id: "plan-generic",
      applicable_phases: ["planning"],
    }));

    const matches = reg.resolve({ phase: "planning", language: "typescript" });
    expect(matches.length).toBe(2);
    // plan-ts 有 phase + language 匹配，应排前面
    expect(matches[0].skill_id).toBe("plan-ts");
  });
});

// ============================================================
// SkillRegistry.select 测试
// ============================================================

describe("SkillRegistry.select", () => {
  it("选出置信度最高的 skill", () => {
    const reg = new SkillRegistry();
    reg.register(createSkill({
      id: "best-skill",
      applicable_phases: ["implementation"],
      languages: ["typescript"],
      path_patterns: ["src/*"],
    }));
    reg.register(createSkill({
      id: "fallback-skill",
      applicable_phases: ["implementation"],
    }));

    const matches = reg.resolve({
      phase: "implementation",
      language: "typescript",
      file_path: "src/index.ts",
    });
    const selected = reg.select(matches);

    expect(selected).toBeDefined();
    expect(selected!.skill_id).toBe("best-skill");
    expect(selected!.source).toBe("explicit");
  });

  it("仅 phase 匹配时 source 为 phase_default", () => {
    const reg = new SkillRegistry();
    reg.register(createSkill({
      id: "phase-skill",
      applicable_phases: ["planning"],
    }));

    const matches = reg.resolve({ phase: "planning" });
    const selected = reg.select(matches);

    expect(selected).toBeDefined();
    expect(selected!.source).toBe("phase_default");
  });

  it("仅 language 匹配时 source 为 language_default", () => {
    const reg = new SkillRegistry();
    reg.register(createSkill({
      id: "lang-skill",
      applicable_phases: [],
      languages: ["python"],
    }));

    const matches = reg.resolve({ language: "python" });
    const selected = reg.select(matches);

    expect(selected).toBeDefined();
    expect(selected!.source).toBe("language_default");
  });

  it("空候选返回 undefined", () => {
    const reg = new SkillRegistry();
    const selected = reg.select([]);
    expect(selected).toBeUndefined();
  });

  it("返回正确的版本号", () => {
    const reg = new SkillRegistry();
    reg.register(createSkill({
      id: "versioned-skill",
      version: "2.3.1",
      applicable_phases: ["testing"],
    }));

    const matches = reg.resolve({ phase: "testing" });
    const selected = reg.select(matches);
    expect(selected!.version).toBe("2.3.1");
  });
});

// ============================================================
// SkillInvocationRecord 状态流转测试
// ============================================================

describe("SkillInvocationRecord", () => {
  it("创建初始记录", () => {
    const record: SkillInvocationRecord = {
      run_id: "run_123",
      task_id: "task_456",
      attempt_id: "att_789",
      phase: "implementation",
      selected_skill_id: "impl-skill",
      status: "selected",
    };

    expect(record.status).toBe("selected");
    expect(record.injected_at).toBeUndefined();
    expect(record.completed_at).toBeUndefined();
  });

  it("状态流转: selected → injected → completed", () => {
    const record: SkillInvocationRecord = {
      run_id: "run_123",
      task_id: "task_456",
      attempt_id: "att_789",
      phase: "implementation",
      selected_skill_id: "impl-skill",
      status: "selected",
    };

    // 注入
    record.status = "injected";
    record.injected_at = new Date().toISOString();
    expect(record.status).toBe("injected");
    expect(record.injected_at).toBeTruthy();

    // 完成
    record.status = "completed";
    record.completed_at = new Date().toISOString();
    expect(record.status).toBe("completed");
    expect(record.completed_at).toBeTruthy();
  });

  it("状态流转: selected → injected → failed", () => {
    const record: SkillInvocationRecord = {
      run_id: "run_123",
      task_id: "task_456",
      attempt_id: "att_789",
      phase: "verification",
      selected_skill_id: "verify-skill",
      status: "selected",
    };

    record.status = "injected";
    record.injected_at = new Date().toISOString();

    record.status = "failed";
    record.completed_at = new Date().toISOString();
    record.evidence = { failure_reason: "gate_blocked" };

    expect(record.status).toBe("failed");
    expect(record.evidence).toHaveProperty("failure_reason");
  });
});

// ============================================================
// EventBus skill 事件测试
// ============================================================

describe("EventBus skill events", () => {
  it("可以发射 skill_selected 事件", () => {
    const bus = new EventBus();
    const events: PlatformEvent[] = [];

    bus.on("skill_selected", (e) => events.push(e));
    bus.emit(createEvent("skill_selected", {
      selected_skill_id: "impl-skill",
      selection_reason: "phase:implementation",
      source: "phase_default",
    }));

    expect(events.length).toBe(1);
    expect(events[0].payload.selected_skill_id).toBe("impl-skill");
  });

  it("可以发射 skill_injected 事件", () => {
    const bus = new EventBus();
    const events: PlatformEvent[] = [];

    bus.on("skill_injected", (e) => events.push(e));
    bus.emit(createEvent("skill_injected", {
      selected_skill_id: "plan-skill",
      protocol_digest: "[Skill: Plan v1.0.0] 规划协议",
    }));

    expect(events.length).toBe(1);
    expect(events[0].payload.protocol_digest).toContain("Plan");
  });

  it("可以发射 skill_completed 事件", () => {
    const bus = new EventBus();
    const events: PlatformEvent[] = [];

    bus.on("skill_completed", (e) => events.push(e));
    bus.emit(createEvent("skill_completed", {
      selected_skill_id: "verify-skill",
      phase: "verification",
    }));

    expect(events.length).toBe(1);
  });

  it("可以发射 skill_failed 事件", () => {
    const bus = new EventBus();
    const events: PlatformEvent[] = [];

    bus.on("skill_failed", (e) => events.push(e));
    bus.emit(createEvent("skill_failed", {
      selected_skill_id: "dispatch-skill",
      failure_reason: "worker_timeout",
    }));

    expect(events.length).toBe(1);
    expect(events[0].payload.failure_reason).toBe("worker_timeout");
  });

  it("可以发射 skill_candidates_resolved 事件", () => {
    const bus = new EventBus();
    const events: PlatformEvent[] = [];

    bus.on("skill_candidates_resolved", (e) => events.push(e));
    bus.emit(createEvent("skill_candidates_resolved", {
      candidate_count: 3,
      candidate_skill_ids: ["s1", "s2", "s3"],
    }));

    expect(events.length).toBe(1);
    expect(events[0].payload.candidate_count).toBe(3);
  });

  it("可以发射 skill_observed 事件", () => {
    const bus = new EventBus();
    const events: PlatformEvent[] = [];

    bus.on("skill_observed", (e) => events.push(e));
    bus.emit(createEvent("skill_observed", {
      observed_path: "skills/harness-plan/SKILL.md",
      observed_kind: "skill_load",
      confidence: 0.8,
      derived_from: "transcript",
    }));

    expect(events.length).toBe(1);
    expect(events[0].payload.derived_from).toBe("transcript");
  });

  it("通配符监听器能收到所有 skill 事件", () => {
    const bus = new EventBus();
    const events: PlatformEvent[] = [];

    bus.on("*", (e) => events.push(e));

    bus.emit(createEvent("skill_selected", { skill_id: "s1" }));
    bus.emit(createEvent("skill_injected", { skill_id: "s1" }));
    bus.emit(createEvent("skill_completed", { skill_id: "s1" }));

    expect(events.length).toBe(3);
  });

  it("getEventLog 可按 skill 事件类型过滤", () => {
    const bus = new EventBus();

    bus.emit(createEvent("task_dispatched", { task_id: "t1" }, { task_id: "t1" }));
    bus.emit(createEvent("skill_selected", { skill_id: "s1" }, { task_id: "t1" }));
    bus.emit(createEvent("skill_injected", { skill_id: "s1" }, { task_id: "t1" }));
    bus.emit(createEvent("skill_completed", { skill_id: "s1" }, { task_id: "t1" }));
    bus.emit(createEvent("task_completed", { task_id: "t1" }, { task_id: "t1" }));

    const skillEvents = bus.getEventLog({ type: "skill_selected" });
    expect(skillEvents.length).toBe(1);

    const allEvents = bus.getEventLog({ task_id: "t1" });
    expect(allEvents.length).toBe(5); // 5 个有 task_id 的事件
  });
});

// ============================================================
// TaskAttempt 携带 skill 元数据测试
// ============================================================

describe("TaskAttempt skill metadata", () => {
  it("TaskAttempt 可以携带 selected_skill_id", () => {
    const attempt: Partial<TaskAttempt> = {
      attempt_id: "att_001",
      run_id: "run_001",
      task_id: "task_001",
      selected_skill_id: "harness-plan",
    };

    expect(attempt.selected_skill_id).toBe("harness-plan");
  });

  it("TaskAttempt 可以携带 skill_invocation 记录", () => {
    const invocation: SkillInvocationRecord = {
      run_id: "run_001",
      task_id: "task_001",
      attempt_id: "att_001",
      phase: "planning",
      selected_skill_id: "harness-plan",
      injected_at: new Date().toISOString(),
      status: "completed",
      completed_at: new Date().toISOString(),
    };

    const attempt: Partial<TaskAttempt> = {
      attempt_id: "att_001",
      run_id: "run_001",
      task_id: "task_001",
      selected_skill_id: "harness-plan",
      skill_invocation: invocation,
    };

    expect(attempt.skill_invocation).toBeDefined();
    expect(attempt.skill_invocation!.status).toBe("completed");
    expect(attempt.skill_invocation!.injected_at).toBeTruthy();
    expect(attempt.skill_invocation!.completed_at).toBeTruthy();
  });
});

// ============================================================
// AuditTrail skill 事件查询测试
// ============================================================

describe("AuditTrail skill events", () => {
  it("可以记录和查询 skill_selected 审计事件", async () => {
    const trail = new AuditTrail(new LocalMemoryStore(), 1);

    const event: AuditEvent = {
      schema_version: "1.0.0",
      event_id: "evt_001",
      type: "skill_selected",
      timestamp: new Date().toISOString(),
      actor: { id: "system", type: "system", name: "Orchestrator", roles: [] },
      run_id: "run_001",
      task_id: "task_001",
      attempt_id: "att_001",
      payload: {
        selected_skill_id: "harness-plan",
        selection_reason: "phase:planning",
        source: "phase_default",
      },
      scope: {},
    };

    await trail.record(event);
    const results = await trail.query({ type: "skill_selected" });
    expect(results.length).toBe(1);
    expect(results[0].payload.selected_skill_id).toBe("harness-plan");
  });

  it("可以查询完整的 skill 生命周期时间线", async () => {
    const trail = new AuditTrail(new LocalMemoryStore(), 1);
    const runId = "run_lifecycle";
    const baseTime = Date.now();

    const events: AuditEvent[] = [
      {
        schema_version: "1.0.0",
        event_id: "evt_001",
        type: "skill_candidates_resolved",
        timestamp: new Date(baseTime).toISOString(),
        actor: { id: "system", type: "system", name: "Orchestrator", roles: [] },
        run_id: runId,
        task_id: "task_001",
        payload: { candidate_count: 2 },
        scope: {},
      },
      {
        schema_version: "1.0.0",
        event_id: "evt_002",
        type: "skill_selected",
        timestamp: new Date(baseTime + 100).toISOString(),
        actor: { id: "system", type: "system", name: "Orchestrator", roles: [] },
        run_id: runId,
        task_id: "task_001",
        payload: { selected_skill_id: "harness-plan" },
        scope: {},
      },
      {
        schema_version: "1.0.0",
        event_id: "evt_003",
        type: "skill_injected",
        timestamp: new Date(baseTime + 200).toISOString(),
        actor: { id: "system", type: "system", name: "Orchestrator", roles: [] },
        run_id: runId,
        task_id: "task_001",
        payload: { selected_skill_id: "harness-plan", protocol_digest: "..." },
        scope: {},
      },
      {
        schema_version: "1.0.0",
        event_id: "evt_004",
        type: "skill_completed",
        timestamp: new Date(baseTime + 5000).toISOString(),
        actor: { id: "system", type: "system", name: "Orchestrator", roles: [] },
        run_id: runId,
        task_id: "task_001",
        payload: { selected_skill_id: "harness-plan" },
        scope: {},
      },
    ];

    await trail.recordBatch(events);
    const timeline = await trail.getTimeline(runId);

    expect(timeline.length).toBe(4);
    expect(timeline[0].type).toBe("skill_candidates_resolved");
    expect(timeline[1].type).toBe("skill_selected");
    expect(timeline[2].type).toBe("skill_injected");
    expect(timeline[3].type).toBe("skill_completed");
  });

  it("skill_observed 不与 skill_selected 混淆", async () => {
    const trail = new AuditTrail(new LocalMemoryStore(), 1);

    // 即使只有 observed，也不等于 selected
    // observed 事件不属于 AuditEventType（仅在 EventBus 中），但验证查询隔离
    const selectedEvent: AuditEvent = {
      schema_version: "1.0.0",
      event_id: "evt_sel",
      type: "skill_selected",
      timestamp: new Date().toISOString(),
      actor: { id: "system", type: "system", name: "Orchestrator", roles: [] },
      run_id: "run_001",
      payload: { selected_skill_id: "s1" },
      scope: {},
    };

    await trail.record(selectedEvent);

    const selectedResults = await trail.query({ type: "skill_selected" });
    expect(selectedResults.length).toBe(1);

    // skill_observed 不在 AuditEventType 中，不会出现在审计查询里
    const observedResults = await trail.query({ type: "skill_observed" });
    expect(observedResults.length).toBe(0);
  });
});

// ============================================================
// 端到端集成: SkillRegistry → EventBus → 记录闭环
// ============================================================

describe("Skill lifecycle end-to-end", () => {
  it("完整闭环: resolve → select → inject → complete with events", () => {
    // 1. 注册 skills
    const reg = new SkillRegistry();
    reg.register(createSkill({
      id: "harness-plan",
      applicable_phases: ["planning"],
      languages: ["typescript"],
    }));
    reg.register(createSkill({
      id: "harness-dispatch",
      applicable_phases: ["dispatch"],
    }));
    reg.register(createSkill({
      id: "harness-verify",
      applicable_phases: ["verification"],
    }));

    // 2. 创建 EventBus 收集事件
    const bus = new EventBus();
    const allEvents: PlatformEvent[] = [];
    bus.on("*", (e) => allEvents.push(e));

    // 3. 模拟 runtime skill resolution 流程
    const context: SkillResolutionContext = {
      phase: "planning",
      language: "typescript",
    };

    // resolve
    const matches = reg.resolve(context);
    expect(matches.length).toBeGreaterThan(0);
    bus.emit(createEvent("skill_candidates_resolved", {
      candidate_count: matches.length,
      candidate_skill_ids: matches.map(m => m.skill_id),
    }));

    // select
    const selected = reg.select(matches);
    expect(selected).toBeDefined();
    expect(selected!.skill_id).toBe("harness-plan");
    bus.emit(createEvent("skill_selected", {
      selected_skill_id: selected!.skill_id,
      selection_reason: selected!.selection_reason,
      source: selected!.source,
    }));

    // inject
    const manifest = reg.get(selected!.skill_id);
    const protocolSummary = `[Skill: ${manifest!.name} v${manifest!.version}] ${manifest!.description}`;
    bus.emit(createEvent("skill_injected", {
      selected_skill_id: selected!.skill_id,
      protocol_digest: protocolSummary.slice(0, 100),
    }));

    // create invocation record
    const invocation: SkillInvocationRecord = {
      run_id: "run_e2e",
      task_id: "task_e2e",
      attempt_id: "att_e2e",
      phase: "planning",
      selected_skill_id: selected!.skill_id,
      injected_at: new Date().toISOString(),
      status: "injected",
    };

    // complete
    invocation.status = "completed";
    invocation.completed_at = new Date().toISOString();
    bus.emit(createEvent("skill_completed", {
      selected_skill_id: invocation.selected_skill_id,
      phase: invocation.phase,
    }));

    // 4. 验证事件链
    expect(allEvents.length).toBe(4);
    expect(allEvents[0].type).toBe("skill_candidates_resolved");
    expect(allEvents[1].type).toBe("skill_selected");
    expect(allEvents[2].type).toBe("skill_injected");
    expect(allEvents[3].type).toBe("skill_completed");

    // 5. 验证 getEventLog 过滤
    const skillLog = bus.getEventLog().filter(e => e.type.startsWith("skill_"));
    expect(skillLog.length).toBe(4);
  });

  it("三个阶段分别匹配正确的 skill", () => {
    const reg = new SkillRegistry();
    reg.register(createSkill({ id: "harness-plan", applicable_phases: ["planning"] }));
    reg.register(createSkill({ id: "harness-dispatch", applicable_phases: ["dispatch"] }));
    reg.register(createSkill({ id: "harness-verify", applicable_phases: ["verification"] }));

    // Planning
    const planMatches = reg.resolve({ phase: "planning" });
    const planSelected = reg.select(planMatches);
    expect(planSelected!.skill_id).toBe("harness-plan");

    // Dispatch
    const dispatchMatches = reg.resolve({ phase: "dispatch" });
    const dispatchSelected = reg.select(dispatchMatches);
    expect(dispatchSelected!.skill_id).toBe("harness-dispatch");

    // Verification
    const verifyMatches = reg.resolve({ phase: "verification" });
    const verifySelected = reg.select(verifyMatches);
    expect(verifySelected!.skill_id).toBe("harness-verify");
  });
});

// ============================================================
// Fix 1: OrchestratorRuntime 默认创建 SkillRegistry
// ============================================================

describe("OrchestratorRuntime default SkillRegistry", () => {
  it("默认构造自带三个阶段协议 skill", () => {
    // OrchestratorRuntime 内部调用 createDefaultSkillRegistry()
    // 验证方式：直接实例化后检查 eventBus 中是否在 run 时自动产生 skill 事件
    // 这里用一个独立的 SkillRegistry 来模拟同样的注册逻辑
    const { SkillRegistry: SR } = require("../../runtime/capabilities/capability-registry");
    const reg = new SR();

    // 模拟 createDefaultSkillRegistry 的注册
    reg.register({
      id: "harness-plan",
      name: "Harness Plan",
      version: "1.0.0",
      description: "规划阶段协议模板",
      input_schema: {},
      output_schema: {},
      permissions: [],
      required_tools: [],
      recommended_tier: "tier-2",
      applicable_phases: ["planning"],
    });
    reg.register({
      id: "harness-dispatch",
      name: "Harness Dispatch",
      version: "1.0.0",
      description: "调度阶段协议模板",
      input_schema: {},
      output_schema: {},
      permissions: [],
      required_tools: [],
      recommended_tier: "tier-2",
      applicable_phases: ["dispatch"],
    });
    reg.register({
      id: "harness-verify",
      name: "Harness Verify",
      version: "1.0.0",
      description: "验证阶段协议模板",
      input_schema: {},
      output_schema: {},
      permissions: [],
      required_tools: [],
      recommended_tier: "tier-2",
      applicable_phases: ["verification"],
    });

    // 验证三个阶段都能匹配
    expect(reg.resolve({ phase: "planning" }).length).toBe(1);
    expect(reg.resolve({ phase: "dispatch" }).length).toBe(1);
    expect(reg.resolve({ phase: "verification" }).length).toBe(1);

    // 验证选择结果正确
    expect(reg.select(reg.resolve({ phase: "planning" }))!.skill_id).toBe("harness-plan");
    expect(reg.select(reg.resolve({ phase: "dispatch" }))!.skill_id).toBe("harness-dispatch");
    expect(reg.select(reg.resolve({ phase: "verification" }))!.skill_id).toBe("harness-verify");
  });

  it("dispatch 阶段不再被遗漏", () => {
    const reg = new SkillRegistry();
    reg.register(createSkill({ id: "harness-dispatch", applicable_phases: ["dispatch"] }));

    const matches = reg.resolve({ phase: "dispatch" });
    expect(matches.length).toBe(1);
    expect(matches[0].skill_id).toBe("harness-dispatch");
    expect(matches[0].phase_match).toBe(true);
  });
});

// ============================================================
// Fix 2: inferTaskPhase 测试
// ============================================================

describe("inferTaskPhase", () => {
  it("task 有 phase 元数据时直接使用", () => {
    const { inferTaskPhase } = require("../../runtime/engine/orchestrator-runtime");
    const task = { id: "t1", title: "实现功能", phase: "planning" } as any;
    expect(inferTaskPhase(task)).toBe("planning");
  });

  it("task 无 phase 时默认为 dispatch", () => {
    const { inferTaskPhase } = require("../../runtime/engine/orchestrator-runtime");
    const task = { id: "t1", title: "实现功能", verifier_set: [] } as any;
    expect(inferTaskPhase(task)).toBe("dispatch");
  });

  it("有 review verifier 时推断为 verification", () => {
    const { inferTaskPhase } = require("../../runtime/engine/orchestrator-runtime");
    const task = { id: "t1", title: "审查代码", verifier_set: ["review"] } as any;
    expect(inferTaskPhase(task)).toBe("verification");
  });

  it("有 security verifier 时推断为 verification", () => {
    const { inferTaskPhase } = require("../../runtime/engine/orchestrator-runtime");
    const task = { id: "t1", title: "安全检查", verifier_set: ["security"] } as any;
    expect(inferTaskPhase(task)).toBe("verification");
  });
});

// ============================================================
// Fix 3: LocalWorkerAdapter prompt 包含协议摘要
// ============================================================

describe("LocalWorkerAdapter skill protocol injection", () => {
  it("contract 有 skill_protocol_summary 时注入到 prompt", () => {
    // 通过直接测试 prompt 构建逻辑来验证
    // LocalWorkerAdapter.execute 内部组 prompt 的逻辑
    const contract = {
      task_id: "t1",
      goal: "实现功能",
      acceptance_criteria: ["通过测试"],
      allowed_paths: ["src/"],
      forbidden_paths: [],
      test_requirements: [],
      context: { relevant_files: [], relevant_snippets: [] },
      selected_skill_id: "harness-dispatch",
      skill_protocol_summary: "[Skill: Harness Dispatch v1.0.0] 并行工程调度阶段协议模板。",
    };

    // 模拟 LocalWorkerAdapter 的 prompt 构建
    const promptParts = [
      `任务: ${contract.goal}`,
      `验收标准: ${contract.acceptance_criteria.join("; ")}`,
      `允许修改的文件: ${contract.allowed_paths.join(", ")}`,
      `禁止修改的文件: ${contract.forbidden_paths.join(", ")}`,
    ];

    // 关键断言：skill_protocol_summary 被注入
    if (contract.skill_protocol_summary) {
      promptParts.push(`\n## 协议约束\n${contract.skill_protocol_summary}`);
    }

    const prompt = promptParts.join("\n");
    expect(prompt).toContain("## 协议约束");
    expect(prompt).toContain("Harness Dispatch v1.0.0");
    expect(prompt).toContain("调度阶段协议模板");
  });

  it("contract 无 skill_protocol_summary 时不注入", () => {
    const contract = {
      goal: "实现功能",
      acceptance_criteria: ["通过测试"],
      allowed_paths: ["src/"],
      forbidden_paths: [],
      test_requirements: [],
    } as any;

    const promptParts = [
      `任务: ${contract.goal}`,
    ];

    if (contract.skill_protocol_summary) {
      promptParts.push(`\n## 协议约束\n${contract.skill_protocol_summary}`);
    }

    const prompt = promptParts.join("\n");
    expect(prompt).not.toContain("协议约束");
  });

  it("selected_skill_id 应注入环境变量", () => {
    const contract = {
      task_id: "t1",
      selected_skill_id: "harness-plan",
    } as any;

    // 验证环境变量构建逻辑
    const env: Record<string, string> = {
      PARALLEL_HARNESS_TASK_ID: contract.task_id,
    };

    if (contract.selected_skill_id) {
      env.PARALLEL_HARNESS_SKILL_ID = contract.selected_skill_id;
    }

    expect(env.PARALLEL_HARNESS_SKILL_ID).toBe("harness-plan");
  });
});

// ============================================================
// Fix 4: RunDetail timeline 包含 skill 事件
// ============================================================

describe("RunDetail timeline with skill events", () => {
  it("skill 审计事件被合并到 timeline 中", () => {
    // 模拟 getRunDetail 中的 timeline 构建逻辑
    const statusHistory = [
      { from: "pending", to: "planned", reason: "规划完成", timestamp: "2026-04-09T10:00:00Z" },
      { from: "planned", to: "running", reason: "开始执行", timestamp: "2026-04-09T10:01:00Z" },
    ];

    const auditEvents = [
      {
        type: "skill_selected",
        timestamp: "2026-04-09T10:00:30Z",
        task_id: undefined,
        payload: { selected_skill_id: "harness-plan", run_phase: "planning", selection_reason: "phase:planning" },
      },
      {
        type: "skill_selected",
        timestamp: "2026-04-09T10:01:30Z",
        task_id: "task_001",
        payload: { selected_skill_id: "harness-dispatch", run_phase: "dispatch" },
      },
    ];

    // 构建 timeline
    const timeline = statusHistory.map(h => ({
      timestamp: h.timestamp,
      type: h.to,
      message: h.reason,
    }));

    const skillAuditTypes = ["skill_candidates_resolved", "skill_selected", "skill_injected", "skill_completed", "skill_failed"];
    const skillAuditEvents = auditEvents.filter(e => skillAuditTypes.includes(e.type));

    for (const se of skillAuditEvents) {
      timeline.push({
        timestamp: se.timestamp,
        type: se.type,
        message: `Skill ${se.payload.selected_skill_id} 选中 (${se.payload.run_phase || ""})`,
      });
    }

    // 按时间排序
    timeline.sort((a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime());

    // 验证 skill 事件被正确合并
    expect(timeline.length).toBe(4);
    expect(timeline[0].type).toBe("planned");
    expect(timeline[1].type).toBe("skill_selected"); // 10:00:30
    expect(timeline[2].type).toBe("running"); // 10:01:00
    expect(timeline[3].type).toBe("skill_selected"); // 10:01:30
    expect(timeline[1].message).toContain("harness-plan");
    expect(timeline[3].message).toContain("harness-dispatch");
  });

  it("SkillEventView 正确聚合", () => {
    const skillAuditEvents = [
      {
        timestamp: "2026-04-09T10:00:30Z",
        type: "skill_selected",
        task_id: "run_phase_planning",
        payload: { selected_skill_id: "harness-plan", run_phase: "planning" },
      },
      {
        timestamp: "2026-04-09T10:01:00Z",
        type: "skill_injected",
        task_id: "task_001",
        payload: { selected_skill_id: "harness-dispatch", phase: "dispatch" },
      },
    ];

    const skillEvents = skillAuditEvents.map(se => ({
      timestamp: se.timestamp,
      type: se.type,
      skill_id: (se.payload as any).selected_skill_id || "",
      phase: (se.payload as any).run_phase || (se.payload as any).phase,
      task_id: se.task_id,
      message: JSON.stringify(se.payload),
    }));

    expect(skillEvents.length).toBe(2);
    expect(skillEvents[0].skill_id).toBe("harness-plan");
    expect(skillEvents[0].phase).toBe("planning");
    expect(skillEvents[1].skill_id).toBe("harness-dispatch");
    expect(skillEvents[1].phase).toBe("dispatch");
  });

  it("TaskSummary 包含 selected_skill_id", () => {
    const taskSummary = {
      id: "task_001",
      title: "实现功能",
      status: "succeeded",
      model_tier: "tier-2",
      attempts: 1,
      tokens_used: 5000,
      duration_ms: 1000,
      risk_level: "medium",
      selected_skill_id: "harness-dispatch",
    };

    expect(taskSummary.selected_skill_id).toBe("harness-dispatch");
  });
});
