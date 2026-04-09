import { describe, expect, it } from "bun:test";

import {
  createHarnessRunRequest,
  detectKnownModules,
  executeHarnessRun,
  parseHarnessCliArgs,
} from "../../runtime/scripts/execute-harness";
import { DEFAULT_RUN_CONFIG, SCHEMA_VERSION, type RunRequest, type RunResult } from "../../runtime/schemas/ga-schemas";

describe("execute-harness script", () => {
  it("parseHarnessCliArgs 可以解析常用参数", () => {
    const parsed = parseHarnessCliArgs([
      "--intent", "实现一个工具函数",
      "--project-root", "/tmp/project",
      "--output", "text",
      "--worker-adapter", "mock-success",
    ]);

    expect(parsed.intent).toBe("实现一个工具函数");
    expect(parsed.projectRoot).toBe("/tmp/project");
    expect(parsed.output).toBe("text");
    expect(parsed.workerAdapterMode).toBe("mock-success");
  });

  it("detectKnownModules 在空仓库时回退到仓库根", () => {
    const modules = detectKnownModules("/tmp/parallel-harness-no-modules");
    expect(modules).toEqual(["."]);
  });

  it("createHarnessRunRequest 生成 runtime 可执行的 RunRequest", () => {
    const request = createHarnessRunRequest("实现一个工具函数", process.cwd(), DEFAULT_RUN_CONFIG);
    expect(request.intent).toBe("实现一个工具函数");
    expect(request.project.root_path).toBe(process.cwd());
    expect(request.actor.roles).toContain("developer");
  });

  it("executeHarnessRun 会把 intent 交给 runtime 并汇总结果", async () => {
    let capturedRequest: RunRequest | undefined;
    const fakeRuntime = {
      async executeRun(request: RunRequest): Promise<RunResult> {
        capturedRequest = request;
        return {
          schema_version: SCHEMA_VERSION,
          run_id: "run_test",
          final_status: "succeeded",
          completed_tasks: ["task-1"],
          failed_tasks: [],
          skipped_tasks: [],
          quality_report: {
            overall_grade: "A",
            gate_results: [],
            pass_rate: 1,
            findings_count: { info: 0, warning: 0, error: 0, critical: 0 },
            recommendations: ["all good"],
          },
          cost_summary: {
            total_tokens: 10,
            total_cost: 1,
            tier_distribution: { "tier-1": 10, "tier-2": 0, "tier-3": 0 },
            total_retries: 0,
            budget_utilization: 0.01,
          },
          audit_summary: {
            total_events: 1,
            key_decisions: [],
            policy_violations_count: 0,
            approvals_count: 0,
            human_interventions: 0,
            model_escalations: 0,
          },
          completed_at: new Date().toISOString(),
          total_duration_ms: 1,
        };
      },
    };

    const summary = await executeHarnessRun({
      intent: "实现一个工具函数",
      projectRoot: process.cwd(),
      output: "json",
      workerAdapterMode: "mock-success",
    }, fakeRuntime);

    expect(summary.ok).toBe(true);
    expect(summary.run_id).toBe("run_test");
    expect(summary.final_status).toBe("succeeded");
    expect(summary.completed_tasks).toEqual(["task-1"]);
    expect(summary.recommendations).toEqual(["all good"]);
    expect(capturedRequest?.intent).toBe("实现一个工具函数");
    expect(process.env.CLAUDE_PLUGIN_ROOT).toBeTruthy();
  });
});
