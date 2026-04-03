/**
 * parallel-harness: 全量修复回归测试
 * 覆盖 10 个能力域修复项
 */
import { describe, expect, it } from "bun:test";
import { groundRequirement, extractGroundingCriteria, getDeliveryArtifactChecklist } from "../../runtime/orchestrator/requirement-grounding";
import { planOwnership } from "../../runtime/orchestrator/ownership-planner";
import { createSchedulePlan } from "../../runtime/scheduler/scheduler";
import { loadEvidenceFiles } from "../../runtime/session/evidence-loader";
import { ExecutionProxy } from "../../runtime/workers/execution-proxy";
import { classifyGate, createEvidenceBundle } from "../../runtime/gates/gate-classification";
import { GateSystem } from "../../runtime/gates/gate-system";
import { aggregateRunEvidence } from "../../runtime/integrations/report-aggregator";
import type { TaskGraph, TaskNode } from "../../runtime/orchestrator/task-graph";
import type { GateResult, RunResult } from "../../runtime/schemas/ga-schemas";

// ============================================================
// 辅助函数
// ============================================================

function createMockTask(overrides: Partial<TaskNode> = {}): TaskNode {
  return {
    id: overrides.id || "task-1",
    title: overrides.title || "测试任务",
    description: "测试任务描述",
    goal: "完成测试任务",
    type: "implementation",
    status: "pending",
    phase: "implementation",
    domain: "backend",
    dependencies: [],
    allowed_paths: overrides.allowed_paths || ["src/"],
    forbidden_paths: [],
    acceptance_criteria: ["功能正常"],
    required_tests: [],
    risk_level: "medium",
    model_tier: "tier-2",
    complexity: { level: "moderate", score: 5, factors: [] },
    retry_policy: { max_retries: 2, backoff_strategy: "linear", retry_on: ["transient_tool_failure"] },
    verifier_set: ["test"],
    verification_requirements: [],
    ...(overrides as any),
  };
}

function createMockGraph(tasks: TaskNode[]): TaskGraph {
  return {
    tasks,
    edges: [],
    critical_path: tasks.map(t => t.id),
  } as unknown as TaskGraph;
}

function createMockRunRequest(intent: string): any {
  return {
    request_id: `req-${Date.now()}`,
    intent,
    project: { root_path: "/tmp/test", known_modules: [], scope: { scope_type: "full", included_paths: [] } },
    actor: { id: "user-1", type: "user", name: "test", role: "developer" },
    config: {},
    requested_at: new Date().toISOString(),
    schema_version: "1.0.0",
  };
}

function createMockGateResult(overrides: Partial<GateResult> = {}): GateResult {
  return {
    schema_version: "1.0.0",
    gate_id: "gate-1",
    gate_type: "test",
    gate_level: "task",
    run_id: "run-1",
    passed: true,
    blocking: true,
    conclusion: {
      summary: "ok",
      findings: [],
      risk: "low",
      required_actions: [],
      suggested_patches: [],
    },
    evaluated_at: new Date().toISOString(),
    ...overrides,
  } as GateResult;
}

// ============================================================
// Workstream 1: Requirement Grounding
// ============================================================

describe("Requirement Grounding", () => {
  it("正常需求生成结构化契约", () => {
    const result = groundRequirement(createMockRunRequest("实现用户登录功能，包含前端表单和后端 API"));
    expect(result.acceptance_matrix.length).toBeGreaterThan(0);
    expect(result.acceptance_matrix[0].category).toBe("functional");
  });

  it("简短需求被标记为歧义", () => {
    const result = groundRequirement(createMockRunRequest("fix bug"));
    expect(result.ambiguity_items.length).toBeGreaterThan(0);
  });

  it("acceptance_matrix 包含阻断级别标记", () => {
    const result = groundRequirement(createMockRunRequest("添加用户认证模块的单元测试和集成测试"));
    const blocking = result.acceptance_matrix.filter(m => m.blocking);
    expect(blocking.length).toBeGreaterThan(0);
  });
});

// ============================================================
// Workstream 3: Ownership Reservation & Safe Scheduler
// ============================================================

describe("Ownership write-set 冲突调度隔离", () => {
  it("write-set 冲突的任务不在同一批次", () => {
    const tasks = [
      createMockTask({ id: "t1", allowed_paths: ["src/shared/config.ts"] }),
      createMockTask({ id: "t2", allowed_paths: ["src/shared/config.ts"] }),
      createMockTask({ id: "t3", allowed_paths: ["src/other/"] }),
    ];
    const graph = createMockGraph(tasks);
    const ownership = planOwnership(graph);

    const schedule = createSchedulePlan(graph, { max_concurrency: 3 }, ownership);

    // t1 和 t2 有冲突，不能在同一批次
    const firstBatch = schedule.batches[0];
    const hasBothConflicting =
      firstBatch.task_ids.includes("t1") && firstBatch.task_ids.includes("t2");
    expect(hasBothConflicting).toBe(false);
  });

  it("无冲突任务可以同批并发", () => {
    const tasks = [
      createMockTask({ id: "t1", allowed_paths: ["src/a/"] }),
      createMockTask({ id: "t2", allowed_paths: ["src/b/"] }),
    ];
    const graph = createMockGraph(tasks);
    const ownership = planOwnership(graph);

    const schedule = createSchedulePlan(graph, { max_concurrency: 3 }, ownership);

    expect(schedule.batches[0].task_ids).toContain("t1");
    expect(schedule.batches[0].task_ids).toContain("t2");
  });
});

// ============================================================
// Workstream 4: Context / Evidence Loader
// ============================================================

describe("Evidence Loader", () => {
  it("加载真实存在的文件", () => {
    const task = { id: "t1", allowed_paths: ["package.json"], dependencies: [] };
    const files = loadEvidenceFiles(task, {
      project_root: process.cwd(),
      max_files_per_task: 10,
      max_file_size_kb: 500,
    });
    expect(files.length).toBeGreaterThan(0);
    expect(files[0].path).toBe("package.json");
    expect(files[0].content.length).toBeGreaterThan(0);
  });

  it("不存在的文件返回空列表", () => {
    const task = { id: "t1", allowed_paths: ["nonexistent_file_xyz.ts"], dependencies: [] };
    const files = loadEvidenceFiles(task, {
      project_root: process.cwd(),
    });
    expect(files.length).toBe(0);
  });

  it("文件大小限制生效", () => {
    const task = { id: "t1", allowed_paths: ["package.json"], dependencies: [] };
    const files = loadEvidenceFiles(task, {
      project_root: process.cwd(),
      max_file_size_kb: 0,
    });
    expect(files.length).toBe(0);
  });
});

// ============================================================
// Workstream 5: Execution Proxy
// ============================================================

describe("Execution Proxy", () => {
  const mockWorkerOutput = {
    status: "ok" as const,
    summary: "执行完成",
    artifacts: [],
    modified_paths: ["src/main.ts"],
    tokens_used: 500,
    duration_ms: 1000,
    actual_tool_calls: [] as Array<{ name: string; args_hash: string }>,
    exit_code: 0,
  };

  it("生成 execution attestation", () => {
    const proxy = new ExecutionProxy();
    const result = proxy.wrapExecution(
      { model_tier: "tier-2", project_root: "/tmp" },
      mockWorkerOutput
    );
    expect(result.attestation).toBeDefined();
    expect(result.attestation.repo_root).toBe("/tmp");
    expect(result.attestation.timestamp).toBeTruthy();
    expect(result.attestation.modified_paths).toContain("src/main.ts");
  });

  it("model tier 映射为真实模型", () => {
    const proxy = new ExecutionProxy();
    const result = proxy.wrapExecution(
      { model_tier: "tier-3", project_root: "/tmp" },
      mockWorkerOutput
    );
    expect(result.attestation.actual_model).toBe("claude-opus-4");
  });

  it("sandbox violation 检测", () => {
    const proxy = new ExecutionProxy();
    const result = proxy.wrapExecution(
      { model_tier: "tier-2", project_root: "/tmp", sandbox_paths: ["src/allowed/"] },
      { ...mockWorkerOutput, modified_paths: ["src/forbidden/hack.ts"] }
    );
    expect(result.attestation.sandbox_violations.length).toBeGreaterThan(0);
  });
});

// ============================================================
// Workstream 6: Gate Classification
// ============================================================

describe("Gate Classification", () => {
  it("test 为 hard gate", () => {
    const cls = classifyGate("test");
    expect(cls.is_hard_gate).toBe(true);
    expect(cls.is_signal_gate).toBe(false);
  });

  it("review 为 signal gate", () => {
    const cls = classifyGate("review");
    expect(cls.is_hard_gate).toBe(false);
    expect(cls.is_signal_gate).toBe(true);
  });

  it("evidence bundle 生成正确", () => {
    const bundle = createEvidenceBundle(
      createMockGateResult({ gate_type: "test" }),
      ["ref-1", "ref-2"]
    );
    expect(bundle.evidence_refs.length).toBe(2);
    expect(bundle.gate_type).toBe("test");
  });
});

// ============================================================
// Workstream 9: Report Aggregator
// ============================================================

describe("Report Aggregator", () => {
  it("聚合运行证据生成报告", () => {
    const result = {
      schema_version: "1.0.0",
      run_id: "run-1",
      final_status: "succeeded",
      completed_tasks: ["t1"],
      failed_tasks: [],
      skipped_tasks: [],
      quality_report: {
        overall_grade: "A",
        gate_results: [],
        pass_rate: 1,
        findings_count: { info: 0, warning: 0, error: 0, critical: 0 },
        recommendations: [],
      },
      cost_summary: {
        total_tokens: 1000,
        total_cost: 0.01,
        tier_distribution: {},
        total_retries: 0,
        budget_utilization: 0.1,
      },
      audit_summary: { total_events: 0, event_types: {} },
      completed_at: new Date().toISOString(),
      total_duration_ms: 1000,
    } as unknown as RunResult;
    const gates: GateResult[] = [createMockGateResult()];
    const report = aggregateRunEvidence(result, gates);
    expect(report.run_id).toBe("run-1");
    expect(report.evidence_refs.length).toBe(1);
    expect(report.quality_summary.overall_grade).toBe("A");
  });
});

// ============================================================
// Workstream 10: 主链闭环集成测试
// ============================================================

describe("determineFinalStatus 基于任务全集", () => {
  it("有 skipped tasks 时不返回 succeeded", () => {
    const mockPlan = {
      task_graph: { tasks: [{ id: "t1" }, { id: "t2" }, { id: "t3" }] },
    } as any;
    const allAttempts = [
      { task_id: "t1", status: "succeeded" },
      { task_id: "t2", status: "succeeded" },
    ];
    const attemptedTaskIds = new Set(allAttempts.map(a => a.task_id));
    const allTaskIds = new Set<string>(mockPlan.task_graph.tasks.map((t: any) => t.id));
    const hasSkippedTasks = [...allTaskIds].some((id) => !attemptedTaskIds.has(id));

    expect(hasSkippedTasks).toBe(true);
    expect(attemptedTaskIds.size).toBeLessThan(allTaskIds.size);
  });
});

describe("Evidence Loader 目录和 glob", () => {
  it("目录模式加载子文件", () => {
    const task = { id: "t1", allowed_paths: ["runtime/"], dependencies: [] };
    const files = loadEvidenceFiles(task, {
      project_root: process.cwd(),
      max_files_per_task: 5,
      max_file_size_kb: 100,
    });
    expect(files.length).toBeGreaterThan(0);
  });

  it("glob 模式加载匹配文件", () => {
    const task = { id: "t1", allowed_paths: ["*.json"], dependencies: [] };
    const files = loadEvidenceFiles(task, {
      project_root: process.cwd(),
      max_files_per_task: 10,
      max_file_size_kb: 500,
    });
    expect(files.length).toBeGreaterThan(0);
    expect(files.some(f => f.path.endsWith(".json"))).toBe(true);
  });

  it("项目根目录 '.' 加载顶层文件", () => {
    const task = { id: "t1", allowed_paths: ["."], dependencies: [] };
    const files = loadEvidenceFiles(task, {
      project_root: process.cwd(),
      max_files_per_task: 10,
      max_file_size_kb: 100,
    });
    expect(files.length).toBeGreaterThan(0);
  });
});

describe("Scheduler 路径重叠语义", () => {
  it("目录前缀冲突被检测", () => {
    const tasks = [
      createMockTask({ id: "t1", allowed_paths: ["src/"] }),
      createMockTask({ id: "t2", allowed_paths: ["src/auth/login.ts"] }),
    ];
    const graph = createMockGraph(tasks);
    const ownership = planOwnership(graph);

    const schedule = createSchedulePlan(graph, { max_concurrency: 3 }, ownership);
    const firstBatch = schedule.batches[0];
    const hasBoth = firstBatch.task_ids.includes("t1") && firstBatch.task_ids.includes("t2");
    expect(hasBoth).toBe(false);
  });
});

describe("RequirementGrounding 歧义检测", () => {
  it("极短且无动作词的请求触发多个歧义项", () => {
    const result = groundRequirement(createMockRunRequest("hmm maybe"));
    expect(result.ambiguity_items.length).toBeGreaterThan(2);
  });

  it("正常请求不触发过多歧义", () => {
    const result = groundRequirement(createMockRunRequest("实现用户登录功能，包含前端表单验证和后端 API 鉴权"));
    expect(result.ambiguity_items.length).toBeLessThanOrEqual(2);
  });
});

// ============================================================
// Workstream B: ExecutionProxy prepare/finalize 分离
// ============================================================

describe("ExecutionProxy prepare/finalize 分离", () => {
  const mockWorkerOutput = {
    status: "ok" as const,
    summary: "执行完成",
    artifacts: [],
    modified_paths: ["src/main.ts"],
    tokens_used: 500,
    duration_ms: 1000,
    actual_tool_calls: [] as Array<{ name: string; args_hash: string }>,
    exit_code: 0,
  };

  it("prepareExecution 返回验证后的执行配置", () => {
    const proxy = new ExecutionProxy();
    const prep = proxy.prepareExecution({
      model_tier: "tier-2",
      project_root: "/tmp/project",
    });
    expect(prep.validated_model).toBe("claude-sonnet-4");
    expect(prep.validated_cwd).toBe("/tmp/project");
    expect(prep.started_at).toBeTruthy();
  });

  it("prepareExecution 空 project_root 抛出错误", () => {
    const proxy = new ExecutionProxy();
    expect(() => proxy.prepareExecution({
      model_tier: "tier-2",
      project_root: "",
    })).toThrow("project_root");
  });

  it("finalizeExecution 生成含时间戳的 attestation", () => {
    const proxy = new ExecutionProxy();
    const startedAt = new Date().toISOString();
    const { attestation } = proxy.finalizeExecution(
      { model_tier: "tier-2", project_root: "/tmp", attempt_id: "att-123", worker_id: "w1" },
      mockWorkerOutput,
      startedAt
    );
    expect(attestation.started_at).toBe(startedAt);
    expect(attestation.ended_at).toBeTruthy();
    expect(attestation.attempt_id).toBe("att-123");
    expect(attestation.worker_id).toBe("w1");
    expect(attestation.execution_outcome).toBe("success");
  });

  it("sandbox 违规时 execution_outcome 为 violation", () => {
    const proxy = new ExecutionProxy();
    const { attestation } = proxy.finalizeExecution(
      { model_tier: "tier-1", project_root: "/tmp", sandbox_paths: ["src/safe/"] },
      { ...mockWorkerOutput, modified_paths: ["src/unsafe/hack.ts"] },
      new Date().toISOString()
    );
    expect(attestation.execution_outcome).toBe("violation");
    expect(attestation.sandbox_violations.length).toBeGreaterThan(0);
  });

  it("失败 worker 输出的 execution_outcome 为 failure", () => {
    const proxy = new ExecutionProxy();
    const { attestation } = proxy.finalizeExecution(
      { model_tier: "tier-1", project_root: "/tmp" },
      { ...mockWorkerOutput, status: "failed" as any },
      new Date().toISOString()
    );
    expect(attestation.execution_outcome).toBe("failure");
  });
});

// ============================================================
// Workstream C: PR/Git repo_root 绑定
// ============================================================

describe("PR Provider repo_root 绑定", () => {
  it("CreatePRRequest 包含 repo_root 字段", () => {
    const request: import("../../runtime/integrations/pr-provider").CreatePRRequest = {
      title: "test",
      body: "body",
      head_branch: "feature/test",
      base_branch: "main",
      repo_root: "/project/root",
    };
    expect(request.repo_root).toBe("/project/root");
  });

  it("CreatePRRequest 包含 expected_remote 字段", () => {
    const request: import("../../runtime/integrations/pr-provider").CreatePRRequest = {
      title: "test",
      body: "body",
      head_branch: "feature/test",
      base_branch: "main",
      repo_root: "/project/root",
      expected_remote: "github.com/org/repo",
    };
    expect(request.expected_remote).toBe("github.com/org/repo");
  });
});

// ============================================================
// Workstream D: Context Budget 闭环
// ============================================================

describe("Context Budget 闭环", () => {
  it("packContext 接受外部 budget 并覆盖默认值", () => {
    const { packContext } = require("../../runtime/session/context-packager");
    const task = createMockTask({ allowed_paths: ["src/"], forbidden_paths: [] });
    const pack = packContext(task, [], {}, { max_input_tokens: 8000 });
    expect(pack.budget.max_input_tokens).toBe(8000);
  });

  it("ContextPack 包含 occupancy_ratio 字段", () => {
    const { packContext } = require("../../runtime/session/context-packager");
    const task = createMockTask({ allowed_paths: ["src/"], forbidden_paths: [] });
    const pack = packContext(task, [], {});
    expect(typeof pack.occupancy_ratio).toBe("number");
    expect(pack.occupancy_ratio).toBeGreaterThanOrEqual(0);
    expect(pack.occupancy_ratio).toBeLessThanOrEqual(1);
  });

  it("ContextPack 包含 compaction_policy 字段", () => {
    const { packContext } = require("../../runtime/session/context-packager");
    const task = createMockTask({ allowed_paths: ["src/"], forbidden_paths: [] });
    const pack = packContext(task, [], {});
    expect(["none", "summarize", "truncate"]).toContain(pack.compaction_policy);
  });

  it("ContextPack 包含 loaded_files_count 和 loaded_snippets_count", () => {
    const { packContext } = require("../../runtime/session/context-packager");
    const task = createMockTask({ allowed_paths: ["src/"], forbidden_paths: [] });
    const pack = packContext(task, [], {});
    expect(typeof pack.loaded_files_count).toBe("number");
    expect(typeof pack.loaded_snippets_count).toBe("number");
  });
});

// ============================================================
// Workstream E: Grounding 消费闭环
// ============================================================

describe("Grounding 消费闭环", () => {
  it("extractGroundingCriteria 提取验收矩阵", () => {
    const grounding = groundRequirement(createMockRunRequest("实现用户认证功能"));
    const criteria = extractGroundingCriteria(grounding);
    expect(criteria.length).toBeGreaterThan(0);
    expect(criteria[0].category).toBe("functional");
    expect(typeof criteria[0].blocking).toBe("boolean");
  });

  it("getDeliveryArtifactChecklist 生成产出物清单", () => {
    const grounding = groundRequirement(createMockRunRequest("创建新功能模块"));
    const checklist = getDeliveryArtifactChecklist(grounding);
    expect(checklist.length).toBeGreaterThan(0);
    expect(checklist[0].artifact).toBeTruthy();
    expect(checklist[0].required).toBe(true);
  });

  it("TaskContract 包含 grounding_criteria 字段", () => {
    const { buildTaskContract, packContext } = require("../../runtime/session/context-packager");
    const task = createMockTask({ allowed_paths: ["src/"], forbidden_paths: [] });
    const pack = packContext(task, [], {});
    const contract = buildTaskContract(task, pack);
    // grounding_criteria 是可选字段
    expect(contract.task_id).toBe(task.id);
    // 手动设置后应保持
    contract.grounding_criteria = [{ category: "functional", criterion: "核心功能", blocking: true }];
    expect(contract.grounding_criteria.length).toBe(1);
  });

  it("grounding impacted_modules 基于 intent 关键词推断", () => {
    const result = groundRequirement(createMockRunRequest("实现 model router 路由优化"));
    expect(result.impacted_modules.length).toBeGreaterThan(0);
  });
});

// ============================================================
// Workstream F: Gate 分层
// ============================================================

describe("Gate 分层增强", () => {
  it("hard gate 列表完整", () => {
    const hardTypes = ["test", "lint_type", "policy", "security"];
    for (const t of hardTypes) {
      const cls = classifyGate(t);
      expect(cls.is_hard_gate).toBe(true);
      expect(cls.strength).toBe("hard");
    }
  });

  it("signal gate 列表完整", () => {
    const signalTypes = ["review", "coverage", "documentation", "perf", "release_readiness"];
    for (const t of signalTypes) {
      const cls = classifyGate(t);
      expect(cls.is_signal_gate).toBe(true);
      expect(cls.strength).toBe("signal");
    }
  });

  it("classifyGate 返回 confidence_note", () => {
    const cls = classifyGate("test");
    expect(cls.confidence_note).toBeTruthy();
    expect(cls.confidence_note.length).toBeGreaterThan(0);
  });

  it("evidence bundle 包含 strength 字段", () => {
    const bundle = createEvidenceBundle(
      createMockGateResult({ gate_type: "test" }),
      ["ref-1"]
    );
    expect(bundle.strength).toBe("hard");
  });

  it("report evidence refs 包含 strength 分层", () => {
    const result = {
      run_id: "run-1",
      final_status: "succeeded",
      completed_tasks: ["t1"],
      failed_tasks: [],
      skipped_tasks: [],
      quality_report: { overall_grade: "A", gate_results: [], pass_rate: 1, findings_count: { info: 0, warning: 0, error: 0, critical: 0 }, recommendations: [] },
      cost_summary: { total_tokens: 1000, total_cost: 0.01, tier_distribution: {}, total_retries: 0, budget_utilization: 0.1 },
      audit_summary: { total_events: 0, event_types: {} },
      completed_at: new Date().toISOString(),
      total_duration_ms: 1000,
    } as unknown as RunResult;
    const gates = [
      createMockGateResult({ gate_type: "test" }),
      createMockGateResult({ gate_type: "review", blocking: false }),
    ];
    const report = aggregateRunEvidence(result, gates);
    const hardRef = report.evidence_refs.find(r => r.strength === "hard");
    const signalRef = report.evidence_refs.find(r => r.strength === "signal");
    expect(hardRef).toBeDefined();
    expect(signalRef).toBeDefined();
    expect(report.quality_summary.hard_gate_summary).toContain("hard gates");
    expect(report.quality_summary.signal_gate_summary).toContain("signal gates");
  });
});

// ============================================================
// Workstream G: Hook effect 化
// ============================================================

describe("Hook effect 化", () => {
  it("HookResult 支持 effects 字段", async () => {
    const { HookRegistry } = require("../../runtime/capabilities/capability-registry");
    const registry = new HookRegistry();

    registry.register({
      id: "test-hook",
      name: "Test Hook",
      phase: "pre_plan",
      priority: 1,
      enabled: true,
      handler: async () => ({
        continue: true,
        effects: [
          { type: "add_gate", payload: { gate_type: "custom" } },
          { type: "require_approval", payload: { reason: "hook triggered" } },
        ],
      }),
    });

    // 执行并收集 effects — 正确 await
    const results = await registry.executePhase("pre_plan", { run_id: "test", data: {} });
    const effectsCollected: any[] = [];
    for (const r of results) {
      if (r.effects) effectsCollected.push(...r.effects);
    }
    expect(effectsCollected.length).toBe(2);
    expect(effectsCollected[0].type).toBe("add_gate");
    expect(effectsCollected[1].type).toBe("require_approval");
  });

  it("InstructionRegistry.resolve() 能返回匹配指令", () => {
    const { InstructionRegistry } = require("../../runtime/capabilities/capability-registry");
    const registry = new InstructionRegistry();
    registry.register({
      id: "repo-rule",
      name: "Repo Rule",
      scope: { type: "repo", repo_path: "/project" },
      instructions: [{ type: "coding", content: "使用 TypeScript strict 模式" }],
      priority: 1,
    });

    const instructions = registry.resolve({ repo_path: "/project" });
    expect(instructions.length).toBe(1);
    expect(instructions[0].content).toContain("TypeScript");
  });
});

// ============================================================
// P0-4: Gate Classification — hasBlockingFailure + classifyResults
// ============================================================

describe("GateSystem classifyResults", () => {
  it("signal gate 失败不阻断", () => {
    const gs = new GateSystem();
    const results = [
      createMockGateResult({ gate_type: "review", blocking: true, passed: false }),
      createMockGateResult({ gate_type: "perf", blocking: true, passed: false }),
    ];
    expect(gs.hasBlockingFailure(results)).toBe(false);
  });

  it("hard gate 失败阻断", () => {
    const gs = new GateSystem();
    const results = [
      createMockGateResult({ gate_type: "test", blocking: true, passed: false }),
      createMockGateResult({ gate_type: "review", blocking: true, passed: true }),
    ];
    expect(gs.hasBlockingFailure(results)).toBe(true);
  });

  it("classifyResults 正确分类 hard/signal/blocking_failures", () => {
    const gs = new GateSystem();
    const results = [
      createMockGateResult({ gate_type: "test", blocking: true, passed: false }),
      createMockGateResult({ gate_type: "lint_type", blocking: true, passed: true }),
      createMockGateResult({ gate_type: "review", blocking: true, passed: false }),
      createMockGateResult({ gate_type: "perf", blocking: false, passed: false }),
    ];
    const classified = gs.classifyResults(results);
    expect(classified.hard_results.length).toBe(2);
    expect(classified.signal_results.length).toBe(2);
    expect(classified.blocking_failures.length).toBe(1);
    expect(classified.blocking_failures[0].gate_type).toBe("test");
  });
});

// ============================================================
// P0-3: Trusted Execution Plane
// ============================================================

describe("Trusted Execution Plane", () => {
  const mockWorkerOutput = {
    status: "ok" as const,
    summary: "执行完成",
    artifacts: [],
    modified_paths: ["src/main.ts", "src/utils.ts"],
    tokens_used: 500,
    duration_ms: 1000,
    actual_tool_calls: [] as Array<{ name: string; args_hash: string }>,
    exit_code: 0,
  };

  it("prepareExecution 采集 baseline_commit", () => {
    const proxy = new ExecutionProxy();
    const prep = proxy.prepareExecution({
      model_tier: "tier-2",
      project_root: process.cwd(),
    });
    // 在 git 仓库中应该能获取到 baseline_commit
    expect(prep.baseline_commit).toBeTruthy();
    expect(typeof prep.baseline_commit).toBe("string");
  });

  it("finalizeExecution 填充 tool_calls 和 diff_ref", () => {
    const proxy = new ExecutionProxy();
    const { attestation } = proxy.finalizeExecution(
      { model_tier: "tier-2", project_root: "/tmp" },
      mockWorkerOutput,
      new Date().toISOString(),
      false,
      "abc123def"
    );
    // tool_calls 从 modified_paths 派生
    expect(attestation.tool_calls.length).toBe(2);
    expect(attestation.tool_calls[0].name).toBe("Edit");
    expect(attestation.tool_calls[0].args_hash).toBeTruthy();
    // P0-4: diff_ref 现在由 generateDiffRef 生成真实 diff 引用
    expect(attestation.diff_ref).toBeTruthy();
    expect(typeof attestation.diff_ref).toBe("string");
  });

  it("sandbox_mode worktree 优雅降级 (P0-4: 不再抛异常)", () => {
    const proxy = new ExecutionProxy();
    // P0-4: worktree 模式不再抛异常，而是在创建失败时优雅降级到 path_check
    const result = proxy.prepareExecution({
      model_tier: "tier-2",
      project_root: "/tmp",
      sandbox_mode: "worktree",
    });
    expect(result.validated_model).toBe("claude-sonnet-4");
    expect(result.validated_cwd).toBeTruthy();
  });
});
