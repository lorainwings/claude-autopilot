import { describe, it, expect } from "bun:test";
import { WorkerExecutionController, DEFAULT_WORKER_EXECUTION_CONFIG } from "../../runtime/workers/worker-runtime";
import type { WorkerInput, WorkerOutput } from "../../runtime/orchestrator/role-contracts";
import type { WorkerAdapter } from "../../runtime/engine/orchestrator-runtime";

// Mock adapter — 可控延迟
function createDelayedAdapter(delayMs: number, shouldFail = false): WorkerAdapter {
  return {
    execute: async (_input: WorkerInput): Promise<WorkerOutput> => {
      await new Promise(resolve => setTimeout(resolve, delayMs));
      if (shouldFail) throw new Error("adapter 执行失败");
      return {
        status: "ok",
        summary: "测试完成",
        artifacts: [],
        modified_paths: [],
        tokens_used: 100,
        duration_ms: delayMs,
        actual_tool_calls: [],
        exit_code: 0,
      };
    },
  };
}

function createMockInput(): WorkerInput {
  return {
    contract: {
      task_id: "task_timeout_test",
      goal: "超时测试",
      dependencies: [],
      allowed_paths: ["."],
      forbidden_paths: [],
      acceptance_criteria: [],
      test_requirements: [],
      preferred_model_tier: "tier-1",
      retry_policy: { max_retries: 0, escalate_on_retry: false, compact_context_on_retry: false },
      verifier_set: [],
      context: {
        task_summary: "test",
        relevant_files: [],
        relevant_snippets: [],
        constraints: { allowed_paths: ["."], forbidden_paths: [], interface_contracts: [], coding_standards: [] },
        test_requirements: [],
        budget: { max_input_tokens: 1000, max_output_tokens: 1000, auto_summarize_on_overflow: false },
        occupancy_ratio: 0.5,
        loaded_files_count: 0,
        loaded_snippets_count: 0,
        compaction_policy: "none",
      },
    },
    model_tier: "tier-1",
    project_root: "/tmp/test",
  };
}

describe("WorkerExecutionController timeout", () => {
  it("正常完成时 timer 被清理（无泄漏）", async () => {
    const adapter = createDelayedAdapter(10); // 10ms 快速完成
    const controller = new WorkerExecutionController(adapter, {
      ...DEFAULT_WORKER_EXECUTION_CONFIG,
      timeout_ms: 5000,
    });

    const result = await controller.execute(createMockInput());
    expect(result.output.status).toBe("ok");
    expect(result.execution_metadata.timed_out).toBe(false);
  });

  it("超时触发 reject", async () => {
    const adapter = createDelayedAdapter(5000); // 5秒，远超 timeout
    const controller = new WorkerExecutionController(adapter, {
      ...DEFAULT_WORKER_EXECUTION_CONFIG,
      timeout_ms: 50, // 50ms 超时
    });

    await expect(controller.execute(createMockInput())).rejects.toThrow("Worker 执行超时");
  });

  it("并发执行互不干扰", async () => {
    const adapter = createDelayedAdapter(10);
    const controller = new WorkerExecutionController(adapter, {
      ...DEFAULT_WORKER_EXECUTION_CONFIG,
      timeout_ms: 5000,
    });

    const input = createMockInput();
    const results = await Promise.all([
      controller.execute(input),
      controller.execute(input),
      controller.execute(input),
    ]);

    expect(results).toHaveLength(3);
    for (const r of results) {
      expect(r.output.status).toBe("ok");
    }
  });
});
