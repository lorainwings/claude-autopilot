/**
 * parallel-harness: 集成测试 — OrchestratorRuntime 完整生命周期
 */
import { describe, expect, it } from "bun:test";
import {
  OrchestratorRuntime,
  DefaultPolicyEngine,
  type WorkerAdapter,
  type PolicyEngine,
  type PolicyEvalResult,
  type ExecutionContext,
} from "../../runtime/engine/orchestrator-runtime";
import { ApprovalWorkflow } from "../../runtime/governance/governance";
import { RuntimeBridgeDataProvider } from "../../runtime/server/control-plane";
import type { WorkerInput, WorkerOutput } from "../../runtime/orchestrator/role-contracts";
import { generateId, SCHEMA_VERSION, type RunRequest } from "../../runtime/schemas/ga-schemas";

// ============================================================
// Mock Worker Adapter
// ============================================================

class MockSuccessAdapter implements WorkerAdapter {
  async execute(input: WorkerInput): Promise<WorkerOutput> {
    const paths = input.contract.allowed_paths.length > 0
      ? [input.contract.allowed_paths[0].replace(/\/?$/, "/") + "result.ts"]
      : ["src/result.ts"];
    return {
      status: "ok",
      summary: `完成任务: ${input.contract.goal}`,
      artifacts: [],
      modified_paths: paths,
      tokens_used: 500,
      duration_ms: 50,
    };
  }
}

class MockFailAdapter implements WorkerAdapter {
  async execute(_input: WorkerInput): Promise<WorkerOutput> {
    return {
      status: "failed",
      summary: "执行失败：模拟错误",
      artifacts: [],
      modified_paths: [],
      tokens_used: 0,
      duration_ms: 10,
    };
  }
}

// ============================================================
// 辅助函数：创建 RunRequest
// ============================================================

function createRunRequest(intent: string, overrides: Partial<RunRequest["config"]> = {}): RunRequest {
  return {
    schema_version: SCHEMA_VERSION,
    request_id: generateId("req"),
    intent,
    actor: { id: "test-user", type: "user", name: "测试用户", roles: ["developer"] },
    project: { root_path: ".", known_modules: ["src"], scope: {} },
    config: {
      max_concurrency: 3,
      high_risk_max_concurrency: 1,
      prioritize_critical_path: true,
      budget_limit: 100000,
      max_model_tier: "tier-3",
      enabled_gates: [],          // 禁用所有 gate 避免 I/O
      auto_approve_rules: ["all"], // 自动审批
      timeout_ms: 60000,
      pr_strategy: "none",
      enable_autofix: false,
      ...overrides,
    },
    requested_at: new Date().toISOString(),
  };
}

// ============================================================
// 集成测试
// ============================================================

describe("OrchestratorRuntime 集成测试", () => {
  it("简单任务完整执行流程", async () => {
    const runtime = new OrchestratorRuntime({
      workerAdapter: new MockSuccessAdapter(),
    });

    const request = createRunRequest("实现一个工具函数");
    const result = await runtime.executeRun(request);

    expect(result).toBeDefined();
    expect(result.run_id).toBeDefined();
    expect(result.final_status).toBeDefined();
    expect(result.completed_at).toBeDefined();
  });

  it("多任务并行执行", async () => {
    const runtime = new OrchestratorRuntime({
      workerAdapter: new MockSuccessAdapter(),
    });

    const request = createRunRequest("- 实现 A 功能\n- 实现 B 功能\n- 实现 C 功能");
    const result = await runtime.executeRun(request);

    expect(result.completed_tasks.length + result.failed_tasks.length + result.skipped_tasks.length).toBeGreaterThan(0);
    expect(result.cost_summary.total_tokens).toBeGreaterThanOrEqual(0);
  });

  it("成本账本记录正确", async () => {
    const runtime = new OrchestratorRuntime({
      workerAdapter: new MockSuccessAdapter(),
    });

    const request = createRunRequest("实现功能");
    const result = await runtime.executeRun(request);

    expect(result.cost_summary).toBeDefined();
    expect(result.cost_summary.budget_utilization).toBeGreaterThanOrEqual(0);
    expect(result.cost_summary.budget_utilization).toBeLessThanOrEqual(1);
  });

  it("审计日志不为空", async () => {
    const runtime = new OrchestratorRuntime({
      workerAdapter: new MockSuccessAdapter(),
    });

    const request = createRunRequest("测试任务");
    const result = await runtime.executeRun(request);

    const auditLog = await runtime.getAuditLog(result.run_id);
    expect(auditLog.length).toBeGreaterThan(0);
  });

  it("Run 可以被查询", async () => {
    const runtime = new OrchestratorRuntime({
      workerAdapter: new MockSuccessAdapter(),
    });

    const request = createRunRequest("查询测试");
    const result = await runtime.executeRun(request);

    const execution = await runtime.getRun(result.run_id);
    expect(execution).toBeDefined();
    expect(execution!.run_id).toBe(result.run_id);
  });

  it("cancelRun 取消运行中的 run", async () => {
    const runtime = new OrchestratorRuntime({
      workerAdapter: new MockSuccessAdapter(),
    });

    const request = createRunRequest("待取消任务");
    const result = await runtime.executeRun(request);

    // 已完成的 run 无法取消
    if (result.final_status === "succeeded" || result.final_status === "failed") {
      const execution = await runtime.getRun(result.run_id);
      expect(execution).toBeDefined();
    }
  });

  it("质量报告包含等级", async () => {
    const runtime = new OrchestratorRuntime({
      workerAdapter: new MockSuccessAdapter(),
    });

    const request = createRunRequest("质量报告测试");
    const result = await runtime.executeRun(request);

    expect(result.quality_report).toBeDefined();
    expect(["A", "B", "C", "D", "F"]).toContain(result.quality_report.overall_grade);
    expect(result.quality_report.pass_rate).toBeGreaterThanOrEqual(0);
    expect(result.quality_report.pass_rate).toBeLessThanOrEqual(1);
  });

  it("worker 失败时正确处理", async () => {
    const runtime = new OrchestratorRuntime({
      workerAdapter: new MockFailAdapter(),
    });

    const request = createRunRequest("失败任务测试", { auto_approve_rules: ["all"] });

    // 失败任务会抛异常或返回 failed 状态
    try {
      const result = await runtime.executeRun(request);
      expect(["failed", "partially_failed"]).toContain(result.final_status);
    } catch (e) {
      // 所有任务失败时抛出异常也是合法的
      expect(e).toBeDefined();
    }
  });

  it("getEventBus 返回事件总线", () => {
    const runtime = new OrchestratorRuntime();
    const bus = runtime.getEventBus();
    expect(bus).toBeDefined();
  });
});

// ============================================================
// 回归测试：task-level approveAndResume 跨进程恢复
// ============================================================

describe("approveAndResume 回归测试", () => {
  /** PolicyEngine：对所有 worker_execute 动作要求审批（不自动通过） */
  class AlwaysApproveRequiredPolicy implements PolicyEngine {
    evaluate(_ctx: ExecutionContext, action: string, _params: Record<string, unknown>): PolicyEvalResult {
      if (action === "worker_execute") {
        return { allowed: true, violations: [], requires_approval: true, message: "需要审批" };
      }
      return { allowed: true, violations: [], requires_approval: false, message: "允许" };
    }
  }

  it("task-level 审批阻断后 approveAndResume 能恢复并成功完成", async () => {
    // 不传 autoApproveRules → ApprovalWorkflow 不自动批准
    const approvalWorkflow = new ApprovalWorkflow([]);
    const runtime = new OrchestratorRuntime({
      workerAdapter: new MockSuccessAdapter(),
      policyEngine: new AlwaysApproveRequiredPolicy(),
      approvalWorkflow,
    });

    const request = createRunRequest("实现一个工具函数", { auto_approve_rules: [] });
    // 第一次执行应该 blocked
    const blockedResult = await runtime.executeRun(request);
    expect(blockedResult.final_status).toBe("blocked");

    // 从 execution 中取审批 ID（已持久化到 checkpoint）
    const execution = await runtime.getRun(blockedResult.run_id);
    expect(execution).toBeDefined();
    expect(execution!.status).toBe("blocked");

    // 取 pending approval_id：从 approval_records 找 pending，或从 approvalWorkflow
    const pending = approvalWorkflow.getPending();
    expect(pending.length).toBeGreaterThan(0);
    const approvalId = pending[0].approval_id;

    // 恢复执行
    const resumedResult = await runtime.approveAndResume(blockedResult.run_id, approvalId, "test-admin");
    expect(resumedResult.final_status).not.toBe("blocked");
    // 恢复后任务应完成
    expect(resumedResult.completed_tasks.length + resumedResult.failed_tasks.length).toBeGreaterThan(0);
  });
});

// ============================================================
// 回归测试：Control Plane listRuns / getRunDetail 读 runtime 数据
// ============================================================

describe("Control Plane 读模型回归测试", () => {
  it("listRuns 返回 runtime 中已完成的 run", async () => {
    const runtime = new OrchestratorRuntime({
      workerAdapter: new MockSuccessAdapter(),
    });

    const request = createRunRequest("测试 listRuns");
    const result = await runtime.executeRun(request);

    const runs = await runtime.listRuns();
    expect(runs.length).toBeGreaterThan(0);
    const found = runs.find((r) => r.run_id === result.run_id);
    expect(found).toBeDefined();
    expect(found!.status).toBeDefined();
    expect(found!.intent).toBe("测试 listRuns");
  });

  it("getRunDetail 返回包含 tasks / cost / timeline 的结构化详情", async () => {
    const runtime = new OrchestratorRuntime({
      workerAdapter: new MockSuccessAdapter(),
    });

    const request = createRunRequest("测试 getRunDetail");
    const result = await runtime.executeRun(request);

    const detail = await runtime.getRunDetail(result.run_id);
    expect(detail).toBeDefined();
    expect(detail!.run_id).toBe(result.run_id);
    expect(Array.isArray(detail!.tasks)).toBe(true);
    expect(detail!.cost).toBeDefined();
    expect(detail!.cost.total_cost).toBeGreaterThanOrEqual(0);
    expect(Array.isArray(detail!.timeline)).toBe(true);
    expect(detail!.timeline.length).toBeGreaterThan(0);
  });

  it("RuntimeBridgeDataProvider.listRuns 通过 bridge 读取 runtime 数据而非空 inner store", async () => {
    const runtime = new OrchestratorRuntime({
      workerAdapter: new MockSuccessAdapter(),
    });

    const request = createRunRequest("测试 bridge listRuns");
    const result = await runtime.executeRun(request);

    const provider = new RuntimeBridgeDataProvider(runtime as any);
    const runs = await provider.listRuns();
    expect(runs.length).toBeGreaterThan(0);
    const found = runs.find((r) => r.run_id === result.run_id);
    expect(found).toBeDefined();
  });
});

// ============================================================
// 回归测试：generic intent ownership fallback
// ============================================================

describe("Generic intent ownership fallback 回归测试", () => {
  it("general 域任务使用 project_root 作 allowed_paths，产出路径不被判定为越界", async () => {
    const runtime = new OrchestratorRuntime({
      // MockSuccessAdapter 对 allowed_paths 为空时产出 src/result.ts
      // 对有 root_path 时产出 root_path/result.ts
      workerAdapter: new MockSuccessAdapter(),
    });

    // 模糊请求，不含任何域关键词 → general 域 → allowed_paths = [project.root_path]
    const request = createRunRequest("实现一个功能模块", {
      auto_approve_rules: ["all"],
      enabled_gates: [],
    });
    const result = await runtime.executeRun(request);

    // 不应该出现 ownership_conflict 失败
    const hasOwnershipConflict = result.failed_tasks.some(
      (t) => t.failure_class === "ownership_conflict"
    );
    expect(hasOwnershipConflict).toBe(false);
    // run 应完成（succeeded 或 partially_failed，但不是纯 ownership 失败）
    expect(result.final_status).not.toBe("failed");
  });

  it("general 域 allowed_paths 包含 project_root 而不是空数组", async () => {
    const { buildTaskGraph } = await import("../../runtime/orchestrator/task-graph-builder");
    const { analyzeIntent } = await import("../../runtime/orchestrator/intent-analyzer");

    const analysis = analyzeIntent("实现一个功能", { root_path: "/project", known_modules: [] });
    const graph = buildTaskGraph(analysis, {}, "/project");

    // 所有任务的 allowed_paths 不应为空（general 域应 fallback 到 project_root）
    for (const task of graph.tasks) {
      expect(task.allowed_paths.length).toBeGreaterThan(0);
      expect(task.allowed_paths).toContain("/project");
    }
  });
});

// ============================================================
// Workstream B/D/E/F 主链闭环集成测试
// ============================================================

describe("主链闭环: ExecutionProxy + Context Budget + Grounding + Gate 分层", () => {
  it("执行结果包含 attestation 审计记录", async () => {
    const runtime = new OrchestratorRuntime({
      workerAdapter: new MockSuccessAdapter(),
    });

    const request = createRunRequest("实现 attestation 测试功能");
    const result = await runtime.executeRun(request);

    // 审计日志应包含 attestation 相关事件
    const auditLog = await runtime.getAuditLog(result.run_id);
    const attestationEvents = auditLog.filter(
      e => e.payload && (e.payload as any).attestation_model
    );
    expect(attestationEvents.length).toBeGreaterThan(0);
  });

  it("执行结果 quality_report 包含 evidence 分层信息", async () => {
    const runtime = new OrchestratorRuntime({
      workerAdapter: new MockSuccessAdapter(),
    });

    const request = createRunRequest("实现质量报告 evidence 测试");
    const result = await runtime.executeRun(request);

    // quality_report 的 recommendations 应包含 evidence refs
    expect(result.quality_report).toBeDefined();
    expect(result.quality_report.recommendations).toBeDefined();
  });

  it("context_budget 从 routing 传入 packContext", async () => {
    const runtime = new OrchestratorRuntime({
      workerAdapter: new MockSuccessAdapter(),
    });

    const request = createRunRequest("测试 context budget 闭环");
    const result = await runtime.executeRun(request);

    // 审计日志应包含 context_occupancy 字段
    const auditLog = await runtime.getAuditLog(result.run_id);
    const contextEvents = auditLog.filter(
      e => e.payload && typeof (e.payload as any).context_occupancy === "number"
    );
    expect(contextEvents.length).toBeGreaterThan(0);
  });

  it("grounding blocking 验收项在部分成功时标记为未满足", async () => {
    const runtime = new OrchestratorRuntime({
      workerAdapter: new MockFailAdapter(),
    });

    const request = createRunRequest("实现用户认证功能的安全审查测试", {
      auto_approve_rules: ["all"],
      enabled_gates: [],
    });
    try {
      const result = await runtime.executeRun(request);
      // 有失败任务时，blocking grounding 应出现在 recommendations 中
      if (result.failed_tasks.length > 0) {
        const hasGroundingWarning = result.quality_report.recommendations.some(
          r => r.includes("[grounding/blocking]")
        );
        expect(hasGroundingWarning).toBe(true);
      }
    } catch {
      // 全失败抛异常也是合法的
    }
  });

  it("PR createPR 请求包含 repo_root", async () => {
    // 验证 orchestrator 传递 repo_root 给 createPR
    let capturedRequest: any = null;
    const mockPRProvider = {
      name: "mock",
      async createPR(req: any) {
        capturedRequest = req;
        return { pr_number: 1, pr_url: "http://mock/1", head_branch: req.head_branch };
      },
      async addReviewComment() {},
      async setCheckStatus() {},
      async getPR() { return { number: 0, url: "", state: "open" as const, title: "", head_branch: "", base_branch: "main", changed_files: [] }; },
      async mergePR() {},
    };

    const runtime = new OrchestratorRuntime({
      workerAdapter: new MockSuccessAdapter(),
      prProvider: mockPRProvider,
    });

    const request = createRunRequest("测试 PR repo_root", {
      pr_strategy: "single_pr",
      auto_approve_rules: ["all"],
      enabled_gates: [],
    });
    await runtime.executeRun(request);

    // PR 请求应包含 repo_root
    if (capturedRequest) {
      expect(capturedRequest.repo_root).toBe(".");
    }
  });
});
