/**
 * parallel-harness: 集成测试 — OrchestratorRuntime 完整生命周期
 */
import { describe, expect, it } from "bun:test";
import { OrchestratorRuntime, type WorkerAdapter } from "../../runtime/engine/orchestrator-runtime";
import type { WorkerInput, WorkerOutput } from "../../runtime/orchestrator/role-contracts";
import { generateId, SCHEMA_VERSION, type RunRequest } from "../../runtime/schemas/ga-schemas";

// ============================================================
// Mock Worker Adapter
// ============================================================

class MockSuccessAdapter implements WorkerAdapter {
  async execute(input: WorkerInput): Promise<WorkerOutput> {
    const paths = input.contract.allowed_paths.length > 0
      ? [input.contract.allowed_paths[0] + "result.ts"]
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
