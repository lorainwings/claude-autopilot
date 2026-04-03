import { describe, test, expect } from "bun:test";
import {
  ClarificationLoop,
  buildGroundingBundle,
  type GroundingBundle,
  type ClarificationQuestion,
} from "../../runtime/orchestrator/requirement-grounding";
import {
  upgradeToEnvelopeV2,
  type ContextEnvelopeV2,
  type ContextPack,
} from "../../runtime/session/context-pack";
import {
  MemoryIntegration,
  type FailureMemoryEntry,
  type PhaseSummaryEntry,
  type DependencyOutputIndex,
} from "../../runtime/session/context-memory-service";
import {
  DocGovernanceEngine,
  type DocMetadata,
} from "../../runtime/governance/doc-governance";
import {
  gradeTrace,
  analyzeRootCause,
  extractPlaybook,
  type TraceGradingInput,
} from "../../runtime/verifiers/trace-grader";

describe("P2-1: GroundingBundle + ClarificationLoop", () => {
  test("ClarificationLoop tracks questions", () => {
    const loop = new ClarificationLoop();
    loop.addQuestion({
      question: "什么是目标用户？",
      category: "scope",
      priority: "blocking",
    });
    expect(loop.getAllQuestions()).toHaveLength(1);
    expect(loop.isComplete()).toBe(false);
  });

  test("ClarificationLoop completes when blocking questions answered", () => {
    const loop = new ClarificationLoop();
    loop.addQuestion({
      question: "范围确认？",
      category: "scope",
      priority: "blocking",
    });
    const q = loop.getAllQuestions()[0];
    loop.answerQuestion(q.question_id, "已确认");
    expect(loop.isComplete()).toBe(true);
  });

  test("ClarificationLoop respects max rounds", () => {
    const loop = new ClarificationLoop();
    expect(loop.advanceRound()).toBe(true);
    expect(loop.advanceRound()).toBe(true);
    expect(loop.advanceRound()).toBe(true);
    expect(loop.advanceRound()).toBe(false);
  });

  test("buildGroundingBundle creates complete bundle", () => {
    const loop = new ClarificationLoop();
    const bundle = buildGroundingBundle(
      "实现用户认证",
      {
        restated_goal: "实现基于 JWT 的用户认证",
        acceptance_matrix: [
          { category: "functional", criterion: "登录成功返回 token", blocking: true },
        ],
        ambiguity_items: [],
        assumptions: [],
        impacted_modules: ["auth"],
        delivery_artifacts: ["auth-service.ts"],
        required_approvals: [],
      },
      loop,
      [{ path: "src/auth/", kind: "file", relevance: "认证模块" }]
    );
    expect(bundle.restated_goal).toBe("实现基于 JWT 的用户认证");
    expect(bundle.evidence_refs).toHaveLength(1);
    expect(bundle.affected_modules).toContain("auth");
  });
});

describe("P2-2: ContextEnvelope V2", () => {
  test("upgradeToEnvelopeV2 converts ContextPack", () => {
    const pack: ContextPack = {
      task_summary: "test task",
      relevant_files: ["src/a.ts", "src/b.ts"],
      relevant_snippets: [],
      constraints: { allowed_paths: [], forbidden_paths: [], interface_contracts: [], coding_standards: [] },
      test_requirements: [],
      budget: { max_input_tokens: 30000, max_output_tokens: 8000, auto_summarize_on_overflow: true },
      occupancy_ratio: 0.5,
      loaded_files_count: 2,
      loaded_snippets_count: 0,
      compaction_policy: "none",
    };
    const envelope = upgradeToEnvelopeV2(pack, "t1", "author");
    expect(envelope.task_id).toBe("t1");
    expect(envelope.role).toBe("author");
    expect(envelope.evidence_refs).toHaveLength(2);
    expect(envelope.compaction_policy).toBe("none");
  });

  test("ContextEnvelopeV2 supports retry context", () => {
    const pack: ContextPack = {
      task_summary: "retry task",
      relevant_files: [],
      relevant_snippets: [],
      constraints: { allowed_paths: [], forbidden_paths: [], interface_contracts: [], coding_standards: [] },
      test_requirements: [],
      budget: { max_input_tokens: 30000, max_output_tokens: 8000, auto_summarize_on_overflow: true },
      occupancy_ratio: 0.3,
      loaded_files_count: 0,
      loaded_snippets_count: 0,
      compaction_policy: "summarize",
      retry_hint: 2,
    };
    const envelope = upgradeToEnvelopeV2(pack, "t2", "verifier");
    expect(envelope.retry_context?.attempt_number).toBe(2);
    expect(envelope.compaction_policy).toBe("summary");
  });
});

describe("P2-4: DocGovernanceEngine", () => {
  test("validates stale documents", () => {
    const engine = new DocGovernanceEngine({ staleness_threshold_days: 30 });
    const result = engine.validateDoc({
      path: "docs/old.md",
      title: "Old Doc",
      last_updated: "2024-01-01",
      cross_links: [],
      freshness_days: 60,
    });
    expect(result.issues.some(i => i.type === "stale")).toBe(true);
  });

  test("validates documents with no owner", () => {
    const engine = new DocGovernanceEngine({ require_owner: true });
    const result = engine.validateDoc({
      path: "docs/test.md",
      title: "Test",
      last_updated: "2024-01-01",
      cross_links: ["other.md"],
      freshness_days: 5,
    });
    expect(result.issues.some(i => i.type === "no_owner")).toBe(true);
  });

  test("generates governance report", () => {
    const engine = new DocGovernanceEngine();
    const results = engine.validateAll([
      { path: "a.md", title: "A", last_updated: "", cross_links: [], freshness_days: 100 },
      { path: "b.md", title: "B", last_updated: "", cross_links: ["a.md"], freshness_days: 10 },
    ]);
    const report = engine.generateReport(results);
    expect(report.total_docs).toBe(2);
    expect(report.issue_counts.stale).toBeGreaterThanOrEqual(1);
  });
});

describe("P2-5: Trace Grading", () => {
  test("grades a perfect run as A", () => {
    const grade = gradeTrace({
      run_id: "r1",
      total_tasks: 5,
      completed_tasks: 5,
      failed_tasks: 0,
      total_retries: 0,
      total_duration_ms: 60000,
      budget_utilization: 0.5,
      gate_pass_rate: 1.0,
      policy_violations: 0,
      model_escalations: 0,
    });
    expect(grade.grade).toBe("A");
    expect(grade.overall_score).toBeGreaterThan(80);
  });

  test("grades a failed run as D or F", () => {
    const grade = gradeTrace({
      run_id: "r2",
      total_tasks: 5,
      completed_tasks: 1,
      failed_tasks: 4,
      total_retries: 8,
      total_duration_ms: 300000,
      budget_utilization: 0.95,
      gate_pass_rate: 0.2,
      policy_violations: 3,
      model_escalations: 2,
    });
    expect(["D", "F"]).toContain(grade.grade);
  });

  test("analyzeRootCause identifies failure patterns", () => {
    const report = analyzeRootCause("r1", [
      { task_id: "t1", failure_class: "verification_failed", message: "tests failed", attempts: 3 },
      { task_id: "t2", failure_class: "verification_failed", message: "lint errors", attempts: 2 },
      { task_id: "t3", failure_class: "timeout", message: "timed out", attempts: 1 },
    ], []);
    expect(report.root_causes.length).toBeGreaterThanOrEqual(2);
    expect(report.prevention_suggestions.length).toBeGreaterThan(0);
  });

  test("extractPlaybook creates from successful run", () => {
    const playbook = extractPlaybook("r1", [
      { task_id: "t1", goal: "实现功能 A", model_tier: "tier-2", duration_ms: 5000, modified_paths: ["src/a.ts"] },
      { task_id: "t2", goal: "实现功能 B", model_tier: "tier-1", duration_ms: 3000, modified_paths: ["src/b.ts"] },
    ]);
    expect(playbook.steps).toHaveLength(2);
    expect(playbook.reusable_insights.length).toBeGreaterThan(0);
  });
});
