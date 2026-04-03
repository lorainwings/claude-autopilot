import { describe, test, expect } from "bun:test";
import { LifecycleSpecStore } from "../../runtime/lifecycle/lifecycle-spec-store";
import { buildStageGraph, type StageGraph } from "../../runtime/lifecycle/stage-contract-engine";
import { createDefaultProducers, collectAllEvidence } from "../../runtime/verifiers/evidence-producer";
import { createDefaultHiddenSuites, runHiddenEvalForRelease } from "../../runtime/verifiers/hidden-eval-runner";
import { ReportTemplateEngine, generateFinalReports } from "../../runtime/integrations/report-template-engine";

describe("P1-1: StageContractEngine 主链化", () => {
  test("buildStageGraph creates graph from lifecycle store", () => {
    const store = new LifecycleSpecStore();
    const graph = buildStageGraph(store);

    expect(graph.nodes).toHaveLength(8);
    expect(graph.current_phase).toBeNull();
    expect(graph.completed_phases).toHaveLength(0);
  });

  test("buildStageGraph tracks completed phases", () => {
    const store = new LifecycleSpecStore();
    store.setSpec("requirement", { status: "completed", completed_at: new Date().toISOString() });
    store.setSpec("product_design", { status: "in_progress", started_at: new Date().toISOString() });

    const graph = buildStageGraph(store);
    expect(graph.completed_phases).toContain("requirement");
    expect(graph.current_phase).toBe("product_design");
  });

  test("buildStageGraph tracks blocked phases", () => {
    const store = new LifecycleSpecStore();
    store.setSpec("requirement", { status: "blocked" });

    const graph = buildStageGraph(store);
    expect(graph.blocked_phases).toContain("requirement");
  });

  test("StageGraph nodes have dependencies", () => {
    const store = new LifecycleSpecStore();
    const graph = buildStageGraph(store);

    // First node has no dependencies
    expect(graph.nodes[0].dependencies).toHaveLength(0);
    // Second node depends on first
    expect(graph.nodes[1].dependencies).toContain("requirement");
  });

  test("StageGraph nodes track artifact completeness", () => {
    const store = new LifecycleSpecStore();
    store.addArtifact("requirement", {
      artifact_id: "a1",
      name: "req-spec",
      type: "requirement_spec",
      created_at: new Date().toISOString(),
      verified: true,
    });

    const graph = buildStageGraph(store);
    expect(graph.nodes[0].artifacts_complete).toBe(true);
  });
});

describe("P1-2: HiddenEvalRunner 接线", () => {
  test("createDefaultProducers returns all 6 producers", () => {
    const producers = createDefaultProducers();
    expect(producers).toHaveLength(6);
  });

  test("collectAllEvidence collects from all producers", async () => {
    const producers = createDefaultProducers();
    const config = { timeout_ms: 5000, project_root: "/tmp/nonexistent" };
    const evidenceMap = await collectAllEvidence(producers, config);
    // Should have an entry for each producer (even if errored)
    expect(evidenceMap.size).toBe(6);
  });

  test("runHiddenEvalForRelease returns gate recommendation", async () => {
    const suites = createDefaultHiddenSuites("/tmp/nonexistent");
    const result = await runHiddenEvalForRelease(
      suites.slice(0, 1),
      { test_count: 10, pass_count: 10 },
      "/tmp/nonexistent"
    );
    expect(result.gate_recommendation).toBeDefined();
    expect(["pass", "block", "warn"]).toContain(result.gate_recommendation);
  });
});

describe("P1-3: ReportTemplateEngine 主链化", () => {
  test("generateFinalReports produces reports for all templates", () => {
    const engine = new ReportTemplateEngine();
    const reports = generateFinalReports(engine, {
      run_id: "test-run-1",
      run_result: {
        schema_version: "1.0.0",
        run_id: "test-run-1",
        final_status: "succeeded",
        completed_tasks: ["t1", "t2"],
        failed_tasks: [],
        skipped_tasks: [],
        quality_report: {
          overall_grade: "A",
          gate_results: [],
          pass_rate: 1.0,
          findings_count: { info: 0, warning: 0, error: 0, critical: 0 },
          recommendations: [],
        },
        cost_summary: {
          total_tokens: 10000,
          total_cost: 25,
          tier_distribution: { "tier-1": 5, "tier-2": 15, "tier-3": 5 },
          total_retries: 0,
          budget_utilization: 0.25,
        },
        audit_summary: {
          total_events: 10,
          key_decisions: [],
          policy_violations_count: 0,
          approvals_count: 0,
          human_interventions: 0,
          model_escalations: 0,
        },
        completed_at: new Date().toISOString(),
        total_duration_ms: 60000,
      },
      evidence_refs: [{ ref_id: "ev1", kind: "test", description: "All tests pass" }],
      gate_results: [],
    });

    expect(reports.size).toBeGreaterThanOrEqual(1);
  });

  test("generateFinalReports handles failed runs", () => {
    const engine = new ReportTemplateEngine();
    const reports = generateFinalReports(engine, {
      run_id: "test-run-2",
      run_result: {
        schema_version: "1.0.0",
        run_id: "test-run-2",
        final_status: "failed",
        completed_tasks: [],
        failed_tasks: [{
          task_id: "t1",
          failure_class: "verification_failed",
          message: "tests failed",
          attempts: 2,
          last_attempt_id: "a2",
        }],
        skipped_tasks: ["t2"],
        quality_report: {
          overall_grade: "F",
          gate_results: [],
          pass_rate: 0,
          findings_count: { info: 0, warning: 1, error: 2, critical: 0 },
          recommendations: ["Fix tests"],
        },
        cost_summary: {
          total_tokens: 5000,
          total_cost: 10,
          tier_distribution: { "tier-1": 10, "tier-2": 0, "tier-3": 0 },
          total_retries: 2,
          budget_utilization: 0.1,
        },
        audit_summary: {
          total_events: 5,
          key_decisions: [],
          policy_violations_count: 1,
          approvals_count: 0,
          human_interventions: 0,
          model_escalations: 1,
        },
        completed_at: new Date().toISOString(),
        total_duration_ms: 30000,
      },
      evidence_refs: [],
      gate_results: [],
    });

    expect(reports.size).toBeGreaterThanOrEqual(1);
  });
});
