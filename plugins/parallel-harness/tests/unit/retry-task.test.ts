/**
 * P0-5: retryTask 测试
 */
import { describe, expect, it } from "bun:test";
import { isValidRunTransition, transitionRunStatus } from "../../runtime/engine/orchestrator-runtime";
import type { RunExecution, TaskAttempt, RunStatus } from "../../runtime/schemas/ga-schemas";
import { RuntimeBridgeDataProvider, InMemoryDataProvider } from "../../runtime/server/control-plane";

function createMockExecution(overrides: Partial<RunExecution> = {}): RunExecution {
  return {
    schema_version: "1.0.0",
    run_id: "run-1",
    batch_id: "batch-1",
    status: "failed" as RunStatus,
    status_history: [{ from: "", to: "pending", reason: "init", timestamp: new Date().toISOString() }],
    active_attempts: {},
    completed_attempts: {},
    verification_results: {},
    approval_records: [],
    policy_violations: [],
    cost_ledger: {
      schema_version: "1.0.0",
      run_id: "run-1",
      entries: [],
      total_cost: 0,
      budget_limit: 100000,
      remaining_budget: 100000,
      tier_distribution: {} as any,
    },
    started_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
    ...overrides,
  };
}

function createMockAttempt(overrides: Partial<TaskAttempt> = {}): TaskAttempt {
  return {
    schema_version: "1.0.0",
    attempt_id: "att-1",
    run_id: "run-1",
    task_id: "task-1",
    attempt_number: 1,
    status: "failed",
    status_history: [],
    model_tier: "tier-2",
    input_summary: "",
    output_summary: "",
    modified_files: [],
    artifacts: [],
    tokens_used: 100,
    cost: 1,
    pre_checks: [],
    started_at: new Date().toISOString(),
    ...overrides,
  } as TaskAttempt;
}

describe("retryTask 状态机", () => {
  it("failed → running 迁移合法", () => {
    expect(isValidRunTransition("failed", "running")).toBe(true);
  });

  it("failed → archived 迁移仍然合法", () => {
    expect(isValidRunTransition("failed", "archived")).toBe(true);
  });

  it("succeeded → running 迁移不合法", () => {
    expect(isValidRunTransition("succeeded", "running")).toBe(false);
  });

  it("partially_failed → running 迁移合法", () => {
    expect(isValidRunTransition("partially_failed", "running")).toBe(true);
  });
});

describe("retryTask 校验逻辑", () => {
  it("RuntimeBridgeDataProvider.retryTask 委托到 runtime.retryTask", async () => {
    let calledWith: { runId: string; taskId: string } | undefined;
    const mockRuntime = {
      cancelRun: async () => {},
      approveAndResume: async () => ({}),
      rejectRun: async () => {},
      listRuns: async () => [],
      retryTask: async (runId: string, taskId: string) => {
        calledWith = { runId, taskId };
        return {};
      },
    };
    const provider = new RuntimeBridgeDataProvider(mockRuntime);
    const result = await provider.retryTask("run-1", "task-1");
    expect(result.ok).toBe(true);
    expect(calledWith!.runId).toBe("run-1");
    expect(calledWith!.taskId).toBe("task-1");
  });

  it("RuntimeBridgeDataProvider.retryTask 无 runtime.retryTask 时返回错误", async () => {
    const mockRuntime = {
      cancelRun: async () => {},
      approveAndResume: async () => ({}),
      rejectRun: async () => {},
      listRuns: async () => [],
    };
    const provider = new RuntimeBridgeDataProvider(mockRuntime);
    const result = await provider.retryTask("run-1", "task-1");
    expect(result.ok).toBe(false);
    expect(result.message).toContain("尚未实现");
  });

  it("transitionRunStatus 从 failed 到 running 成功", () => {
    const execution = createMockExecution({ status: "failed" });
    // 确保 status_history 有 "failed" 状态记录
    execution.status_history.push({
      from: "running",
      to: "failed",
      reason: "任务失败",
      timestamp: new Date().toISOString(),
    });
    transitionRunStatus(execution, "running", "重试 task");
    expect(execution.status).toBe("running");
  });

  it("transitionRunStatus 从 succeeded 到 running 抛出错误", () => {
    const execution = createMockExecution({ status: "succeeded" as RunStatus });
    expect(() => transitionRunStatus(execution, "running", "不允许")).toThrow("非法状态迁移");
  });
});
