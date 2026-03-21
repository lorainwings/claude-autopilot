/**
 * parallel-harness: Context Packager + PR Provider + Capability Registry 测试
 */
import { describe, expect, it } from "bun:test";
import { packContext, buildTaskContract, type FileInfo } from "../../runtime/session/context-packager";
import { renderPRSummary, renderReviewComments, parseCIFailure, RunMappingRegistry } from "../../runtime/integrations/pr-provider";
import { SkillRegistry, InstructionRegistry, HookRegistry } from "../../runtime/capabilities/capability-registry";
import type { TaskNode } from "../../runtime/orchestrator/task-graph";
import { SCHEMA_VERSION, type RunResult, type RunPlan, type GateResult } from "../../runtime/schemas/ga-schemas";

// ============================================================
// Mock 数据
// ============================================================

const mockTask: TaskNode = {
  id: "task-1", title: "测试任务", goal: "完成测试实现",
  dependencies: [], status: "pending", risk_level: "low",
  complexity: { level: "low", score: 20, dimensions: { file_count: 1, module_count: 1, involves_critical: false, estimated_tokens: 1000 }, reasoning: "简单" },
  allowed_paths: ["src/"], forbidden_paths: ["config/secret/"],
  acceptance_criteria: ["所有测试通过"], required_tests: ["unit test"],
  model_tier: "tier-1", verifier_set: ["test"],
  retry_policy: { max_retries: 2, escalate_on_retry: true, compact_context_on_retry: true },
};

const mockFiles: FileInfo[] = [
  { path: "src/main.ts", content: "const x = 1;\n".repeat(10), size: 130, type: "ts" },
  { path: "src/utils.ts", content: "export function foo() {}\n".repeat(5), size: 120, type: "ts" },
  { path: "config/secret/key.json", content: "{}", size: 2, type: "json" },
];

const mockResult: RunResult = {
  schema_version: SCHEMA_VERSION, run_id: "run_test", final_status: "succeeded",
  completed_tasks: ["task-1", "task-2"], failed_tasks: [], skipped_tasks: [],
  quality_report: { overall_grade: "A", gate_results: [], pass_rate: 1.0, findings_count: { info: 0, warning: 0, error: 0, critical: 0 }, recommendations: [] },
  cost_summary: { total_tokens: 5000, total_cost: 25, tier_distribution: { "tier-1": 2000, "tier-2": 3000, "tier-3": 0 } as any, total_retries: 0, budget_utilization: 0.00025 },
  audit_summary: { total_events: 10, key_decisions: [], policy_violations_count: 0, approvals_count: 0, human_interventions: 0, model_escalations: 0 },
  completed_at: new Date().toISOString(), total_duration_ms: 30000,
};

const mockPlan: RunPlan = {
  schema_version: SCHEMA_VERSION, plan_id: "plan_test", run_id: "run_test",
  task_graph: {
    graph_id: "g1", tasks: [mockTask, { ...mockTask, id: "task-2", title: "任务二", status: "verified" }],
    edges: [], critical_path: ["task-1"],
    metadata: { created_at: new Date().toISOString(), original_intent: "测试", total_tasks: 2, max_parallelism: 2, critical_path_length: 1, estimated_total_tokens: 2000 },
  },
  ownership_plan: { assignments: [], conflicts: [], has_unresolvable_conflicts: false, downgrade_suggestions: [] },
  schedule_plan: { batches: [], total_batches: 1, max_parallelism: 2, estimated_rounds: 1 },
  routing_decisions: [], budget_estimate: { estimated_total_tokens: 2000, estimated_total_cost: 10, budget_limit: 100000, within_budget: true },
  pending_approvals: [], planned_at: new Date().toISOString(),
};

const mockGateResults: GateResult[] = [
  { schema_version: SCHEMA_VERSION, gate_id: "g1", gate_type: "test", gate_level: "run", run_id: "run_test", passed: true, blocking: true, conclusion: { summary: "通过", findings: [{ severity: "info", message: "10 tests pass", file_path: "src/main.test.ts", line: 1 }], risk: "low", required_actions: [], suggested_patches: [] }, evaluated_at: new Date().toISOString() },
  { schema_version: SCHEMA_VERSION, gate_id: "g2", gate_type: "review", gate_level: "run", run_id: "run_test", passed: false, blocking: false, conclusion: { summary: "警告", findings: [{ severity: "warning", message: "missing tests", file_path: "src/utils.ts", line: 5 }], risk: "medium", required_actions: [], suggested_patches: [] }, evaluated_at: new Date().toISOString() },
];

// ============================================================
// Context Packager 测试
// ============================================================

describe("packContext", () => {
  it("返回正确的 ContextPack 结构", () => {
    const pack = packContext(mockTask, mockFiles);
    expect(pack.task_summary).toBeDefined();
    expect(pack.relevant_files).toBeDefined();
    expect(pack.constraints).toBeDefined();
    expect(pack.test_requirements).toBeDefined();
    expect(pack.budget).toBeDefined();
  });

  it("task_summary 包含任务信息", () => {
    const pack = packContext(mockTask, mockFiles);
    expect(pack.task_summary).toContain("测试任务");
    expect(pack.task_summary).toContain("完成测试实现");
  });

  it("过滤禁止路径的文件", () => {
    const pack = packContext(mockTask, mockFiles);
    expect(pack.relevant_files).not.toContain("config/secret/key.json");
    expect(pack.relevant_files).toContain("src/main.ts");
  });

  it("超预算时压缩片段", () => {
    // 10000 行代码，确保超预算且有换行符可以正确截断
    const largeContent = "const x = 1; // 这是一行代码\n".repeat(10000);
    const largeFiles: FileInfo[] = [{ path: "src/huge.ts", content: largeContent, size: largeContent.length, type: "ts" }];
    const pack = packContext(mockTask, largeFiles, { default_budget: { max_input_tokens: 100, max_output_tokens: 500, auto_summarize_on_overflow: true } });
    if (pack.relevant_snippets.length > 0) {
      const snippet = pack.relevant_snippets[0];
      // 压缩后内容应小于原始内容（10000行 -> 50行）
      expect(snippet.content.length).toBeLessThan(largeContent.length);
    }
  });
});

describe("buildTaskContract", () => {
  it("返回完整 TaskContract", () => {
    const pack = packContext(mockTask, mockFiles);
    const contract = buildTaskContract(mockTask, pack);
    expect(contract.task_id).toBe("task-1");
    expect(contract.goal).toBe("完成测试实现");
    expect(contract.allowed_paths).toEqual(["src/"]);
    expect(contract.forbidden_paths).toEqual(["config/secret/"]);
    expect(contract.acceptance_criteria).toEqual(["所有测试通过"]);
    expect(contract.test_requirements).toEqual(["unit test"]);
    expect(contract.preferred_model_tier).toBe("tier-1");
    expect(contract.retry_policy).toBeDefined();
    expect(contract.context).toBeDefined();
  });
});

// ============================================================
// PR Provider 测试
// ============================================================

describe("renderPRSummary", () => {
  it("包含 Run ID", () => {
    const summary = renderPRSummary(mockResult, mockPlan, mockGateResults);
    expect(summary).toContain("run_test");
  });

  it("包含状态", () => {
    const summary = renderPRSummary(mockResult, mockPlan, mockGateResults);
    expect(summary).toContain("succeeded");
  });

  it("包含任务统计表", () => {
    const summary = renderPRSummary(mockResult, mockPlan, mockGateResults);
    expect(summary).toContain("Completed");
    expect(summary).toContain("2");
  });

  it("包含 gate 结果表", () => {
    const summary = renderPRSummary(mockResult, mockPlan, mockGateResults);
    expect(summary).toContain("test");
    expect(summary).toContain("review");
  });

  it("包含成本汇总", () => {
    const summary = renderPRSummary(mockResult, mockPlan, mockGateResults);
    expect(summary).toContain("Total Tokens");
    expect(summary).toContain("5,000");
  });

  it("failed_tasks 不为空时显示失败列表", () => {
    const failedResult = { ...mockResult, failed_tasks: [{ task_id: "t-fail", failure_class: "transient_tool_failure" as any, message: "出错了", attempts: 2, last_attempt_id: "att_1" }] };
    const summary = renderPRSummary(failedResult, mockPlan, []);
    expect(summary).toContain("t-fail");
    expect(summary).toContain("transient_tool_failure");
  });
});

describe("renderReviewComments", () => {
  it("从 gate findings 生成评论", () => {
    const comments = renderReviewComments(mockGateResults);
    expect(comments.length).toBeGreaterThan(0);
  });

  it("只包含有 file_path 和 line 的 findings", () => {
    const gateWithNoLine: GateResult[] = [{ schema_version: SCHEMA_VERSION, gate_id: "g3", gate_type: "policy", gate_level: "run", run_id: "r1", passed: false, blocking: true, conclusion: { summary: "", findings: [{ severity: "error", message: "no file" }], risk: "high", required_actions: [], suggested_patches: [] }, evaluated_at: new Date().toISOString() }];
    const comments = renderReviewComments(gateWithNoLine);
    expect(comments.length).toBe(0);
  });

  it("尊重 maxComments 限制", () => {
    const manyFindings: GateResult[] = Array.from({ length: 5 }, (_, i) => ({
      schema_version: SCHEMA_VERSION, gate_id: `g${i}`, gate_type: "review" as any,
      gate_level: "run" as any, run_id: "r1", passed: false, blocking: false,
      conclusion: { summary: "", findings: Array.from({ length: 5 }, (_, j) => ({ severity: "warning" as any, message: `finding ${j}`, file_path: "src/file.ts", line: j + 1 })), risk: "medium" as any, required_actions: [], suggested_patches: [] },
      evaluated_at: new Date().toISOString(),
    }));
    const comments = renderReviewComments(manyFindings, 3);
    expect(comments.length).toBe(3);
  });
});

describe("parseCIFailure", () => {
  it("解析测试失败", () => {
    const failure = parseCIFailure("FAIL src/test.spec.ts\n3 tests failed");
    expect(failure.failure_type).toBe("test");
  });

  it("解析类型检查失败", () => {
    const failure = parseCIFailure("error TS2345: Argument of type 'string' is not assignable");
    expect(failure.failure_type).toBe("type_check");
  });

  it("解析 lint 失败", () => {
    const failure = parseCIFailure("eslint: 5 errors found");
    expect(failure.failure_type).toBe("lint");
  });

  it("解析构建失败", () => {
    const failure = parseCIFailure("build failed: compile error in webpack");
    expect(failure.failure_type).toBe("build");
  });
});

describe("RunMappingRegistry", () => {
  it("register/getByRunId 正常", () => {
    const reg = new RunMappingRegistry();
    reg.register({ run_id: "r1", pr_number: 42, created_at: new Date().toISOString() });
    expect(reg.getByRunId("r1")?.pr_number).toBe(42);
  });

  it("getByPR 正常", () => {
    const reg = new RunMappingRegistry();
    reg.register({ run_id: "r1", pr_number: 42, created_at: new Date().toISOString() });
    expect(reg.getByPR(42)?.run_id).toBe("r1");
  });

  it("getByIssue 正常", () => {
    const reg = new RunMappingRegistry();
    reg.register({ run_id: "r1", issue_number: 10, created_at: new Date().toISOString() });
    expect(reg.getByIssue(10)?.run_id).toBe("r1");
  });

  it("listAll 返回所有", () => {
    const reg = new RunMappingRegistry();
    reg.register({ run_id: "r1", created_at: new Date().toISOString() });
    reg.register({ run_id: "r2", created_at: new Date().toISOString() });
    expect(reg.listAll().length).toBe(2);
  });
});

// ============================================================
// Capability Registry 测试
// ============================================================

describe("SkillRegistry", () => {
  it("register/get 正常工作", () => {
    const reg = new SkillRegistry();
    reg.register({ id: "s1", name: "测试 Skill", version: "1.0.0", description: "测试", input_schema: {}, output_schema: {}, permissions: [], required_tools: ["Read"], recommended_tier: "tier-1", applicable_phases: ["testing"] });
    expect(reg.get("s1")?.name).toBe("测试 Skill");
  });

  it("findByPhase 按阶段过滤", () => {
    const reg = new SkillRegistry();
    reg.register({ id: "s1", name: "实现 Skill", version: "1.0.0", description: "", input_schema: {}, output_schema: {}, permissions: [], required_tools: [], recommended_tier: "tier-2", applicable_phases: ["implementation"] });
    reg.register({ id: "s2", name: "测试 Skill", version: "1.0.0", description: "", input_schema: {}, output_schema: {}, permissions: [], required_tools: [], recommended_tier: "tier-1", applicable_phases: ["testing"] });
    expect(reg.findByPhase("implementation").length).toBe(1);
    expect(reg.findByPhase("testing")[0].id).toBe("s2");
  });

  it("findByLanguage 按语言过滤", () => {
    const reg = new SkillRegistry();
    reg.register({ id: "ts-skill", name: "TS Skill", version: "1.0.0", description: "", input_schema: {}, output_schema: {}, permissions: [], required_tools: [], recommended_tier: "tier-1", applicable_phases: [], languages: ["typescript"] });
    reg.register({ id: "py-skill", name: "Py Skill", version: "1.0.0", description: "", input_schema: {}, output_schema: {}, permissions: [], required_tools: [], recommended_tier: "tier-1", applicable_phases: [], languages: ["python"] });
    expect(reg.findByLanguage("typescript")[0].id).toBe("ts-skill");
    expect(reg.findByLanguage("python")[0].id).toBe("py-skill");
  });
});

describe("InstructionRegistry", () => {
  it("resolve 按 org scope 匹配", () => {
    const reg = new InstructionRegistry();
    reg.register({ id: "p1", name: "Org Pack", scope: { type: "org", org_id: "acme" }, instructions: [{ type: "coding", content: "使用 camelCase" }], priority: 1 });
    const instructions = reg.resolve({ org_id: "acme" });
    expect(instructions.length).toBe(1);
    expect(instructions[0].content).toBe("使用 camelCase");
  });

  it("resolve 按 language scope 匹配", () => {
    const reg = new InstructionRegistry();
    reg.register({ id: "p2", name: "TS Pack", scope: { type: "language", language: "typescript" }, instructions: [{ type: "review", content: "检查类型安全" }], priority: 1 });
    const instructions = reg.resolve({ language: "typescript" });
    expect(instructions.length).toBe(1);
  });

  it("resolve 不匹配的 scope 返回空", () => {
    const reg = new InstructionRegistry();
    reg.register({ id: "p3", name: "Pack", scope: { type: "org", org_id: "acme" }, instructions: [{ type: "coding", content: "规则" }], priority: 1 });
    const instructions = reg.resolve({ org_id: "other" });
    expect(instructions.length).toBe(0);
  });
});

describe("HookRegistry", () => {
  it("register 和 executePhase 正常工作", async () => {
    const reg = new HookRegistry();
    let executed = false;
    reg.register({
      id: "h1", name: "测试 Hook", phase: "pre_plan", priority: 1, enabled: true,
      handler: async () => { executed = true; return { continue: true }; },
    });
    await reg.executePhase("pre_plan", { run_id: "r1", data: {} });
    expect(executed).toBe(true);
  });

  it("disabled hook 不执行", async () => {
    const reg = new HookRegistry();
    let executed = false;
    reg.register({
      id: "h1", name: "禁用 Hook", phase: "pre_plan", priority: 1, enabled: false,
      handler: async () => { executed = true; return { continue: true }; },
    });
    await reg.executePhase("pre_plan", { run_id: "r1", data: {} });
    expect(executed).toBe(false);
  });

  it("continue=false 时停止执行后续 hook", async () => {
    const reg = new HookRegistry();
    const order: number[] = [];
    reg.register({ id: "h1", name: "Hook1", phase: "pre_dispatch", priority: 1, enabled: true, handler: async () => { order.push(1); return { continue: false }; } });
    reg.register({ id: "h2", name: "Hook2", phase: "pre_dispatch", priority: 2, enabled: true, handler: async () => { order.push(2); return { continue: true }; } });
    await reg.executePhase("pre_dispatch", { run_id: "r1", data: {} });
    expect(order).toEqual([1]);
  });
});
