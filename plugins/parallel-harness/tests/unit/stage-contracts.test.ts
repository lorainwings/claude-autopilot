/**
 * P0-1: StageContract 测试
 */
import { describe, expect, it } from "bun:test";
import {
  deriveDeliveryArtifacts,
  buildStageContracts,
  groundRequirement,
  type StageContract,
} from "../../runtime/orchestrator/requirement-grounding";
import type { TaskNode } from "../../runtime/orchestrator/task-graph";

function createMockTask(overrides: Partial<TaskNode> = {}): TaskNode {
  return {
    id: overrides.id || "task-1",
    title: overrides.title || "测试任务",
    goal: overrides.goal || "完成测试任务",
    dependencies: [],
    status: "pending",
    risk_level: "medium",
    complexity: { level: "medium", score: 5, dimensions: { file_count: 1, module_count: 1, involves_critical: false, estimated_tokens: 1000 }, reasoning: "" },
    allowed_paths: overrides.allowed_paths || ["src/"],
    forbidden_paths: [],
    acceptance_criteria: overrides.acceptance_criteria || ["功能正常"],
    required_tests: [],
    model_tier: "tier-2",
    verifier_set: ["test"],
    retry_policy: { max_retries: 2, escalate_on_retry: false, compact_context_on_retry: false },
  };
}

function createMockRunRequest(intent: string): any {
  return {
    request_id: `req-${Date.now()}`,
    intent,
    project: { root_path: "/tmp/test", known_modules: [], scope: {} },
    actor: { id: "user-1", type: "user", name: "test", role: "developer" },
    config: {},
    requested_at: new Date().toISOString(),
    schema_version: "1.0.0",
  };
}

describe("deriveDeliveryArtifacts", () => {
  it("默认包含 code 和 tests", () => {
    const artifacts = deriveDeliveryArtifacts("实现一个简单功能");
    expect(artifacts).toContain("code");
    expect(artifacts).toContain("tests");
  });

  it("security 意图包含 security artifact", () => {
    const artifacts = deriveDeliveryArtifacts("实现用户认证和鉴权功能");
    expect(artifacts).toContain("security");
  });

  it("doc 意图包含 docs artifact", () => {
    const artifacts = deriveDeliveryArtifacts("更新 API 文档和 README");
    expect(artifacts).toContain("docs");
  });

  it("config 意图包含 config artifact", () => {
    const artifacts = deriveDeliveryArtifacts("修改环境配置 env settings");
    expect(artifacts).toContain("config");
  });
});

describe("buildStageContracts", () => {
  it("按 domain 分组生成合同", () => {
    const grounding = groundRequirement(createMockRunRequest("实现用户登录和 API 测试"));
    const tasks = [
      createMockTask({ id: "t1", allowed_paths: ["backend/api/"], goal: "实现后端 API" }),
      createMockTask({ id: "t2", allowed_paths: ["frontend/forms/"], goal: "实现前端表单" }),
      createMockTask({ id: "t3", allowed_paths: ["backend/auth/"], goal: "实现后端鉴权" }),
    ];
    const contracts = buildStageContracts(grounding, tasks);
    expect(contracts.length).toBe(2);
    const backendStage = contracts.find(c => c.stage_name === "backend");
    expect(backendStage).toBeDefined();
    expect(backendStage!.acceptance_criteria.length).toBeGreaterThanOrEqual(2);
  });

  it("verifier_plan 根据 artifacts 生成", () => {
    const grounding = groundRequirement(createMockRunRequest("实现安全认证模块"));
    const tasks = [createMockTask({ goal: "实现 security 鉴权" })];
    const contracts = buildStageContracts(grounding, tasks);
    expect(contracts.length).toBe(1);
    expect(contracts[0].verifier_plan).toContain("run_security_gate");
    expect(contracts[0].verifier_plan).toContain("run_test_gate");
  });

  it("空任务列表返回空合同", () => {
    const grounding = groundRequirement(createMockRunRequest("实现功能"));
    const contracts = buildStageContracts(grounding, []);
    expect(contracts.length).toBe(0);
  });

  it("grounding 的 delivery_artifacts 使用 deriveDeliveryArtifacts", () => {
    const grounding = groundRequirement(createMockRunRequest("添加 API 文档和测试"));
    expect(grounding.delivery_artifacts).toContain("code");
    expect(grounding.delivery_artifacts).toContain("tests");
    expect(grounding.delivery_artifacts).toContain("docs");
    expect(grounding.delivery_artifacts).toContain("api");
  });
});
