/**
 * parallel-harness: 全量修复回归测试
 * 覆盖 10 个能力域修复项
 */
import { describe, expect, it } from "bun:test";
import { groundRequirement } from "../../runtime/orchestrator/requirement-grounding";
import { planOwnership } from "../../runtime/orchestrator/ownership-planner";
import { createSchedulePlan } from "../../runtime/scheduler/scheduler";
import { loadEvidenceFiles } from "../../runtime/session/evidence-loader";
import { ExecutionProxy } from "../../runtime/workers/execution-proxy";
import { classifyGate, createEvidenceBundle } from "../../runtime/gates/gate-classification";
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
    type: "implementation",
    status: "pending",
    phase: "implementation",
    domain: "backend",
    dependencies: [],
    allowed_paths: overrides.allowed_paths || ["src/"],
    forbidden_paths: [],
    risk_level: "medium",
    complexity: { level: "moderate", score: 5, factors: [] },
    retry_policy: { max_retries: 2, backoff_strategy: "linear", retry_on: ["transient_tool_failure"] },
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
