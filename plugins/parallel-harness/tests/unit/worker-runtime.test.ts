/**
 * parallel-harness: Worker 运行时测试
 */
import { describe, expect, it, test } from "bun:test";
import {
  CapabilityRegistry,
  createDefaultCapabilityRegistry,
  isToolAllowed,
  isPathInSandbox,
  WorkerExecutionController,
  DEFAULT_TOOL_POLICY,
  decideRetry,
  decideDowngrade,
  type ToolPolicy,
  type PathSandbox,
} from "../../runtime/workers/worker-runtime";
import type { WorkerAdapter } from "../../runtime/engine/orchestrator-runtime";
import type { WorkerInput, WorkerOutput } from "../../runtime/orchestrator/role-contracts";

// ============================================================
// Mock Worker Adapter
// ============================================================

class MockWorkerAdapter implements WorkerAdapter {
  async execute(input: WorkerInput): Promise<WorkerOutput> {
    return {
      status: "ok",
      summary: "Mock 执行完成",
      artifacts: [],
      modified_paths: input.contract.allowed_paths.map(p => p + "file.ts"),
      tokens_used: 500,
      duration_ms: 100,
      actual_tool_calls: [],
      exit_code: 0,
    };
  }
}

// ============================================================
// CapabilityRegistry 测试
// ============================================================

describe("CapabilityRegistry", () => {
  it("register 和 get 正常工作", () => {
    const registry = new CapabilityRegistry();
    registry.register({
      id: "test-cap", name: "测试", description: "测试能力",
      task_types: ["test"], required_tools: ["Read"],
      recommended_tier: "tier-1", applicable_phases: ["testing"],
    });
    const cap = registry.get("test-cap");
    expect(cap).toBeDefined();
    expect(cap!.name).toBe("测试");
  });

  it("findByTaskType 匹配任务类型", () => {
    const registry = createDefaultCapabilityRegistry();
    const caps = registry.findByTaskType("implementation");
    expect(caps.length).toBeGreaterThan(0);
    expect(caps[0].id).toBe("code_implementation");
  });

  it("listAll 返回所有能力", () => {
    const registry = createDefaultCapabilityRegistry();
    expect(registry.listAll().length).toBe(6);
  });

  it("hasCapability 检查存在", () => {
    const registry = createDefaultCapabilityRegistry();
    expect(registry.hasCapability("code_implementation")).toBe(true);
    expect(registry.hasCapability("nonexistent")).toBe(false);
  });
});

describe("createDefaultCapabilityRegistry", () => {
  it("注册 6 个内置能力", () => {
    const registry = createDefaultCapabilityRegistry();
    const all = registry.listAll();
    expect(all.length).toBe(6);
    const ids = all.map(c => c.id);
    expect(ids).toContain("code_implementation");
    expect(ids).toContain("test_writing");
    expect(ids).toContain("code_review");
    expect(ids).toContain("documentation");
    expect(ids).toContain("lint_fix");
    expect(ids).toContain("architecture_design");
  });
});

// ============================================================
// Tool Policy 测试
// ============================================================

describe("isToolAllowed", () => {
  it("denylist 中的工具被拒绝", () => {
    expect(isToolAllowed("TaskStop", DEFAULT_TOOL_POLICY)).toBe(false);
    expect(isToolAllowed("EnterWorktree", DEFAULT_TOOL_POLICY)).toBe(false);
  });

  it("空 allowlist 允许所有非 deny 工具", () => {
    expect(isToolAllowed("Read", DEFAULT_TOOL_POLICY)).toBe(true);
    expect(isToolAllowed("Write", DEFAULT_TOOL_POLICY)).toBe(true);
  });

  it("allowlist 不为空时只允许列表中的工具", () => {
    const policy: ToolPolicy = { allowlist: ["Read", "Write"], denylist: [] };
    expect(isToolAllowed("Read", policy)).toBe(true);
    expect(isToolAllowed("Bash", policy)).toBe(false);
  });
});

// ============================================================
// Path Sandbox 测试
// ============================================================

describe("isPathInSandbox", () => {
  const sandbox: PathSandbox = {
    allowed_paths: ["src/"],
    forbidden_paths: ["src/secrets/"],
    root_path: ".",
  };

  it("允许路径内的文件", () => {
    expect(isPathInSandbox("src/main.ts", sandbox)).toBe(true);
  });

  it("禁止路径内的文件被拒绝", () => {
    expect(isPathInSandbox("src/secrets/key.ts", sandbox)).toBe(false);
  });

  it("允许路径外的文件被拒绝", () => {
    expect(isPathInSandbox("lib/utils.ts", sandbox)).toBe(false);
  });

  it("空 allowed_paths 允许所有", () => {
    const openSandbox: PathSandbox = { allowed_paths: [], forbidden_paths: ["config/"], root_path: "." };
    expect(isPathInSandbox("src/main.ts", openSandbox)).toBe(true);
    expect(isPathInSandbox("config/app.json", openSandbox)).toBe(false);
  });

  it("glob 模式匹配", () => {
    const globSandbox: PathSandbox = { allowed_paths: ["src/**"], forbidden_paths: [], root_path: "." };
    expect(isPathInSandbox("src/deep/nested/file.ts", globSandbox)).toBe(true);
  });
});

// ============================================================
// WorkerExecutionController 测试
// ============================================================

describe("WorkerExecutionController", () => {
  it("缺少 task_id 报错", async () => {
    const controller = new WorkerExecutionController(new MockWorkerAdapter());
    try {
      await controller.execute({
        contract: { task_id: "", goal: "test", dependencies: [], allowed_paths: ["src/"], forbidden_paths: [], acceptance_criteria: [], test_requirements: [], preferred_model_tier: "tier-1", retry_policy: { max_retries: 1, escalate_on_retry: false, compact_context_on_retry: false }, verifier_set: ["test"], context: {} as any },
        model_tier: "tier-1",
      });
      expect(true).toBe(false); // 不应到达
    } catch (e) {
      expect((e as Error).message).toContain("task_id");
    }
  });

  it("缺少 goal 报错", async () => {
    const controller = new WorkerExecutionController(new MockWorkerAdapter());
    try {
      await controller.execute({
        contract: { task_id: "t1", goal: "", dependencies: [], allowed_paths: ["src/"], forbidden_paths: [], acceptance_criteria: [], test_requirements: [], preferred_model_tier: "tier-1", retry_policy: { max_retries: 1, escalate_on_retry: false, compact_context_on_retry: false }, verifier_set: ["test"], context: {} as any },
        model_tier: "tier-1",
      });
      expect(true).toBe(false);
    } catch (e) {
      expect((e as Error).message).toContain("goal");
    }
  });

  it("allowed_paths 为空时不报错（视为不限制路径）", async () => {
    const controller = new WorkerExecutionController(new MockWorkerAdapter());
    // 空 allowed_paths 表示 general 域无路径限制，不应抛错
    const result = await controller.execute({
      contract: { task_id: "t1", goal: "test", dependencies: [], allowed_paths: [], forbidden_paths: [], acceptance_criteria: [], test_requirements: [], preferred_model_tier: "tier-1", retry_policy: { max_retries: 1, escalate_on_retry: false, compact_context_on_retry: false }, verifier_set: ["test"], context: {} as any },
      model_tier: "tier-1",
    });
    expect(result.output.status).toBe("ok");
  });
});

// ============================================================
// Retry Manager 测试
// ============================================================

describe("decideRetry", () => {
  it("可重试失败类型返回 should_retry=true", () => {
    const result = decideRetry("transient_tool_failure", 1, 3, "tier-1", true);
    expect(result.should_retry).toBe(true);
  });

  it("不可重试失败类型返回 should_retry=false", () => {
    const result = decideRetry("permanent_policy_failure", 1, 3, "tier-1", true);
    expect(result.should_retry).toBe(false);
  });

  it("达到最大重试返回 should_retry=false", () => {
    const result = decideRetry("transient_tool_failure", 3, 3, "tier-1", true);
    expect(result.should_retry).toBe(false);
  });

  it("escalate 升级 tier", () => {
    const result = decideRetry("transient_tool_failure", 1, 3, "tier-1", true);
    expect(result.new_model_tier).toBe("tier-2");
  });

  it("tier-3 不再升级", () => {
    const result = decideRetry("transient_tool_failure", 1, 3, "tier-3", true);
    expect(result.new_model_tier).toBeUndefined();
  });

  it("指数退避延迟", () => {
    const r1 = decideRetry("transient_tool_failure", 0, 3, "tier-1", true);
    const r2 = decideRetry("transient_tool_failure", 1, 3, "tier-1", true);
    expect(r2.delay_ms).toBeGreaterThan(r1.delay_ms);
  });
});

// ============================================================
// Downgrade Manager 测试
// ============================================================

describe("decideDowngrade", () => {
  it("高冲突率触发降级", () => {
    const result = decideDowngrade(0.5, 0, false);
    expect(result.should_downgrade).toBe(true);
    expect(result.strategy).toBe("serialize");
  });

  it("低冲突率不降级", () => {
    const result = decideDowngrade(0.1, 0, false);
    expect(result.should_downgrade).toBe(false);
  });

  it("连续 block 触发降级", () => {
    const result = decideDowngrade(0, 3, false);
    expect(result.should_downgrade).toBe(true);
  });

  it("关键路径阻塞触发降级", () => {
    const result = decideDowngrade(0, 0, true);
    expect(result.should_downgrade).toBe(true);
  });

  it("正常情况不降级", () => {
    const result = decideDowngrade(0, 0, false);
    expect(result.should_downgrade).toBe(false);
    expect(result.strategy).toBe("none");
  });
});
