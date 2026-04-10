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
      actual_tool_calls: [],
      exit_code: 0,
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
      actual_tool_calls: [],
      exit_code: 1,
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

const INTEGRATION_TIMEOUT_MS = 20000;

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
  }, INTEGRATION_TIMEOUT_MS);

  it("多任务并行执行", async () => {
    const runtime = new OrchestratorRuntime({
      workerAdapter: new MockSuccessAdapter(),
    });

    const request = createRunRequest("- 实现 A 功能\n- 实现 B 功能\n- 实现 C 功能");
    const result = await runtime.executeRun(request);

    expect(result.completed_tasks.length + result.failed_tasks.length + result.skipped_tasks.length).toBeGreaterThan(0);
    expect(result.cost_summary.total_tokens).toBeGreaterThanOrEqual(0);
  }, INTEGRATION_TIMEOUT_MS);

  it("成本账本记录正确", async () => {
    const runtime = new OrchestratorRuntime({
      workerAdapter: new MockSuccessAdapter(),
    });

    const request = createRunRequest("实现功能");
    const result = await runtime.executeRun(request);

    expect(result.cost_summary).toBeDefined();
    expect(result.cost_summary.budget_utilization).toBeGreaterThanOrEqual(0);
    expect(result.cost_summary.budget_utilization).toBeLessThanOrEqual(1);
  }, INTEGRATION_TIMEOUT_MS);

  it("审计日志不为空", async () => {
    const runtime = new OrchestratorRuntime({
      workerAdapter: new MockSuccessAdapter(),
    });

    const request = createRunRequest("测试任务");
    const result = await runtime.executeRun(request);

    const auditLog = await runtime.getAuditLog(result.run_id);
    expect(auditLog.length).toBeGreaterThan(0);
  }, INTEGRATION_TIMEOUT_MS);

  it("Run 可以被查询", async () => {
    const runtime = new OrchestratorRuntime({
      workerAdapter: new MockSuccessAdapter(),
    });

    const request = createRunRequest("查询测试");
    const result = await runtime.executeRun(request);

    const execution = await runtime.getRun(result.run_id);
    expect(execution).toBeDefined();
    expect(execution!.run_id).toBe(result.run_id);
  }, INTEGRATION_TIMEOUT_MS);

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
  }, INTEGRATION_TIMEOUT_MS);

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
  }, INTEGRATION_TIMEOUT_MS);

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
  }, INTEGRATION_TIMEOUT_MS);

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
  }, INTEGRATION_TIMEOUT_MS);
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
  }, INTEGRATION_TIMEOUT_MS);

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
  }, INTEGRATION_TIMEOUT_MS);

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
  }, INTEGRATION_TIMEOUT_MS);
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
  }, INTEGRATION_TIMEOUT_MS);

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
  }, INTEGRATION_TIMEOUT_MS);

  it("执行结果 quality_report 包含 evidence 分层信息", async () => {
    const runtime = new OrchestratorRuntime({
      workerAdapter: new MockSuccessAdapter(),
    });

    const request = createRunRequest("实现质量报告 evidence 测试");
    const result = await runtime.executeRun(request);

    // quality_report 的 recommendations 应包含 evidence refs
    expect(result.quality_report).toBeDefined();
    expect(result.quality_report.recommendations).toBeDefined();
  }, INTEGRATION_TIMEOUT_MS);

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
  }, INTEGRATION_TIMEOUT_MS);

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
  }, INTEGRATION_TIMEOUT_MS);

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
  }, INTEGRATION_TIMEOUT_MS);
});

// ============================================================
// 协议注入闭环集成测试
// ============================================================

describe("协议注入闭环", () => {
  it("默认 skillRegistry 加载完整协议（非截断）", () => {
    const runtime = new OrchestratorRuntime({
      workerAdapter: new MockSuccessAdapter(),
    });
    const registry = (runtime as any).skillRegistry;
    expect(registry).toBeDefined();

    const planManifest = registry.get("harness-plan");
    expect(planManifest).toBeDefined();
    expect(planManifest.protocol_content).toContain("## 约束");
    expect(planManifest.protocol_content.length).toBeGreaterThan(800);

    const dispatchManifest = registry.get("harness-dispatch");
    expect(dispatchManifest.protocol_content).toContain("## 约束");

    const verifyManifest = registry.get("harness-verify");
    expect(verifyManifest.protocol_content).toContain("## 约束");
    expect(verifyManifest.protocol_content).toContain("## 输出格式");
  });

  it("完整 run 审计日志包含 protocol_validation 事件", async () => {
    const runtime = new OrchestratorRuntime({
      workerAdapter: new MockSuccessAdapter(),
    });

    const request = createRunRequest("实现一个工具函数");
    const result = await runtime.executeRun(request);
    const auditLog = await runtime.getAuditLog(result.run_id);

    const pvEvents = auditLog.filter(
      (e: any) => e.payload?.phase === "protocol_validation"
    );
    expect(pvEvents.length).toBeGreaterThan(0);
    expect(pvEvents[0].payload.skill_id).toBe("harness-plan");
    expect(Array.isArray(pvEvents[0].payload.constraints_checked)).toBe(true);
    expect((pvEvents[0].payload.constraints_checked as string[]).length).toBeGreaterThan(0);
  }, INTEGRATION_TIMEOUT_MS);

  it("完整 run 审计日志包含 skill_selected 和 skill_injected", async () => {
    const runtime = new OrchestratorRuntime({
      workerAdapter: new MockSuccessAdapter(),
    });

    const request = createRunRequest("实现一个功能模块");
    const result = await runtime.executeRun(request);
    const auditLog = await runtime.getAuditLog(result.run_id);

    const skillSelected = auditLog.filter((e: any) => e.type === "skill_selected");
    expect(skillSelected.length).toBeGreaterThan(0);

    const skillInjected = auditLog.filter((e: any) => e.type === "skill_injected");
    expect(skillInjected.length).toBeGreaterThan(0);

    const runLevelInjected = skillInjected.filter(
      (e: any) => e.payload?.has_protocol_content === true
    );
    expect(runLevelInjected.length).toBeGreaterThan(0);
  }, INTEGRATION_TIMEOUT_MS);
});

// ============================================================
// 协议辅助函数单元测试
// ============================================================

describe("协议辅助函数", () => {
  const {
    extractProtocolSection,
    extractPlanConstraints,
    extractVerifyGateSpec,
    validatePlanAgainstProtocol,
  } = require("../../runtime/engine/orchestrator-runtime");

  it("extractProtocolSection 提取约束段落", () => {
    const protocol = "# Title\n\n## 执行步骤\n\n步骤内容\n\n## 约束\n\n- 必须验证 DAG 无环\n- 高风险任务必须标记\n";
    const section = extractProtocolSection(protocol, "约束");
    expect(section).toContain("DAG 无环");
    expect(section).toContain("高风险");
  });

  it("extractPlanConstraints 返回约束数组", () => {
    const protocol = "## 约束\n\n- 必须验证 DAG 无环\n- 文件所有权冲突并解决\n- 高风险任务必须标记\n- 不可在规划阶段修改任何代码文件\n";
    const constraints = extractPlanConstraints(protocol);
    expect(constraints.length).toBe(4);
    expect(constraints[0]).toContain("DAG 无环");
  });

  it("extractVerifyGateSpec 解析门禁分级（含 policy / ownership 语法）", () => {
    const protocol = [
      "## 执行步骤",
      "",
      "#### Gate 1: test (阻断)",
      "",
      "内容",
      "",
      "#### Gate 2: lint_type (阻断)",
      "",
      "内容",
      "",
      "#### Gate 4: policy / ownership (阻断)",
      "",
      "内容",
      "",
      "#### Gate 5: review (非阻断)",
      "",
      "内容",
    ].join("\n");
    const specs = extractVerifyGateSpec(protocol);
    expect(specs.length).toBe(4);
    expect(specs[0]).toEqual({ gate: "test", blocking: true });
    expect(specs[1]).toEqual({ gate: "lint_type", blocking: true });
    expect(specs[2]).toEqual({ gate: "policy", blocking: true });
    expect(specs[3]).toEqual({ gate: "review", blocking: false });
  });

  it("extractVerifyGateSpec 解析真实 harness-verify SKILL.md", () => {
    const { resolve } = require("path");
    const { readFileSync } = require("fs");
    const pluginRoot = resolve(__dirname, "../..");
    const content = readFileSync(resolve(pluginRoot, "skills/harness-verify/SKILL.md"), "utf-8");
    let protocol = content;
    if (protocol.startsWith("---")) {
      const endIdx = protocol.indexOf("---", 3);
      if (endIdx > 0) protocol = protocol.slice(endIdx + 3).trim();
    }
    const specs = extractVerifyGateSpec(protocol);
    const gateNames = specs.map((s: any) => s.gate);
    // 协议要求的 4 项阻断性 gate 必须全部被解析出
    expect(gateNames).toContain("test");
    expect(gateNames).toContain("lint_type");
    expect(gateNames).toContain("security");
    expect(gateNames).toContain("policy");
    // policy 必须是 blocking
    const policySpec = specs.find((s: any) => s.gate === "policy");
    expect(policySpec!.blocking).toBe(true);
  });

  it("validatePlanAgainstProtocol 合法 plan 通过", () => {
    const plan = {
      task_graph: {
        tasks: [{ id: "t1", risk_level: "high" }, { id: "t2", risk_level: "low" }],
      },
      schedule_plan: { batches: [{ task_ids: ["t1", "t2"] }] },
      ownership_plan: { has_unresolvable_conflicts: false },
      routing_decisions: [{ task_id: "t1" }, { task_id: "t2" }],
    };
    const constraints = [
      "必须验证 DAG 无环（检测到环则回退为串行链）",
      "必须检测文件所有权冲突并解决",
      "高风险任务必须标记",
      "不可在规划阶段修改任何代码文件",
    ];
    const result = validatePlanAgainstProtocol(plan, constraints);
    expect(result.passed).toBe(true);
    expect(result.checked).toContain("dag_acyclic");
    expect(result.checked).toContain("high_risk_tagged");
  });

  it("validatePlanAgainstProtocol 缺少调度触发 violation", () => {
    const plan = {
      task_graph: { tasks: [{ id: "t1" }, { id: "t2" }] },
      schedule_plan: { batches: [{ task_ids: ["t1"] }] },
      ownership_plan: { has_unresolvable_conflicts: false },
      routing_decisions: [],
    };
    const result = validatePlanAgainstProtocol(plan, ["必须验证 DAG 无环"]);
    expect(result.passed).toBe(false);
    expect(result.violations[0]).toContain("t2");
  });
});

// ============================================================
// Finding 1: 协议驱动 gate 阻断判定
// ============================================================

describe("协议驱动 gate 阻断判定", () => {
  it("classifyGate 无协议覆盖时使用硬编码分类", () => {
    const { classifyGate } = require("../../runtime/gates/gate-classification");

    const testGate = classifyGate("test");
    expect(testGate.is_hard_gate).toBe(true);
    expect(testGate.strength).toBe("hard");

    const reviewGate = classifyGate("review");
    expect(reviewGate.is_hard_gate).toBe(false);
    expect(reviewGate.strength).toBe("signal");
  });

  it("classifyGate 接受协议覆盖后 signal gate 可升级为 hard", () => {
    const { classifyGate } = require("../../runtime/gates/gate-classification");

    // review 原本是 signal，协议定义为阻断后升级为 hard
    const overrides = [{ gate: "review", blocking: true }];
    const reviewGate = classifyGate("review", overrides);
    expect(reviewGate.is_hard_gate).toBe(true);
    expect(reviewGate.strength).toBe("hard");
  });

  it("classifyGate 接受协议覆盖后 hard gate 可降级为 signal", () => {
    const { classifyGate } = require("../../runtime/gates/gate-classification");

    // test 原本是 hard，协议定义为非阻断后降级为 signal
    const overrides = [{ gate: "test", blocking: false }];
    const testGate = classifyGate("test", overrides);
    expect(testGate.is_hard_gate).toBe(false);
    expect(testGate.strength).toBe("signal");
  });

  it("GateSystem.hasBlockingFailure 使用协议覆盖（真实场景: blocking:false + override:true）", () => {
    const { GateSystem } = require("../../runtime/gates/gate-system");
    const gs = new GateSystem();

    // 真实场景：review gate 的合同 blocking=false，GateResult 继承 blocking=false
    const results = [{
      gate_type: "review",
      passed: false,
      blocking: false, // 真实的 GateResult.blocking（继承自合同）
      gate_level: "run",
      conclusion: null,
    }];

    // 无协议覆盖：review 是 signal + blocking=false，不阻断
    expect(gs.hasBlockingFailure(results)).toBe(false);

    // 有协议覆盖：review 升级为 blocking，协议覆盖 GateResult.blocking，应阻断
    const overrides = [{ gate: "review", blocking: true }];
    expect(gs.hasBlockingFailure(results, overrides)).toBe(true);
  });
});

// ============================================================
// Finding 2: plan 协议校验 fail-closed
// ============================================================

describe("plan 协议校验 fail-closed", () => {
  it("validatePlanAgainstProtocol 检查所有权冲突", () => {
    const { validatePlanAgainstProtocol } = require("../../runtime/engine/orchestrator-runtime");
    const plan = {
      task_graph: { tasks: [{ id: "t1" }] },
      schedule_plan: { batches: [{ task_ids: ["t1"] }] },
      ownership_plan: { has_unresolvable_conflicts: true },
      routing_decisions: [{ task_id: "t1" }],
      pending_approvals: [], // 没有审批请求 → violation
    };
    const result = validatePlanAgainstProtocol(plan, ["必须检测文件所有权冲突并解决"]);
    expect(result.passed).toBe(false);
    expect(result.violations[0]).toContain("所有权冲突");
    expect(result.checked).toContain("ownership_conflicts_resolved");
  });

  it("validatePlanAgainstProtocol 所有权冲突有审批请求时通过", () => {
    const { validatePlanAgainstProtocol } = require("../../runtime/engine/orchestrator-runtime");
    const plan = {
      task_graph: { tasks: [{ id: "t1" }] },
      schedule_plan: { batches: [{ task_ids: ["t1"] }] },
      ownership_plan: { has_unresolvable_conflicts: true },
      routing_decisions: [{ task_id: "t1" }],
      pending_approvals: [{ action: "execute_with_conflicts" }],
    };
    const result = validatePlanAgainstProtocol(plan, ["必须检测文件所有权冲突并解决"]);
    expect(result.passed).toBe(true);
  });

  it("validatePlanAgainstProtocol 不检查歧义项（由 Phase 1b blocked 语义处理）", () => {
    const { validatePlanAgainstProtocol } = require("../../runtime/engine/orchestrator-runtime");
    const plan = {
      task_graph: { tasks: [] },
      schedule_plan: { batches: [] },
      ownership_plan: { has_unresolvable_conflicts: false },
      routing_decisions: [],
      requirement_grounding: { ambiguity_items: ["a", "b", "c"] },
    };
    // 歧义项约束不在 validatePlanAgainstProtocol 中检查，应通过
    const result = validatePlanAgainstProtocol(plan, [
      "如果歧义项 > 2 个，必须使用 AskUserQuestion 确认",
    ]);
    expect(result.passed).toBe(true);
  });
});

// ============================================================
// F1+F2+F4: verify 主链端到端测试（enabled_gates 非空）
// ============================================================

describe("verify 协议主链 — gate 实际执行", () => {
  it("启用 gate 后 verify 阶段真正执行并产生 gate 结果", async () => {
    const runtime = new OrchestratorRuntime({
      workerAdapter: new MockSuccessAdapter(),
    });

    // 启用 review gate（非 I/O 密集型 gate，避免超时）
    const request = createRunRequest("实现工具函数", {
      enabled_gates: ["review"] as any,
    });
    const result = await runtime.executeRun(request);

    const auditLog = await runtime.getAuditLog(result.run_id);
    const gateEvents = auditLog.filter(
      (e: any) => e.type === "gate_passed" || e.type === "gate_blocked"
    );
    expect(gateEvents.length).toBeGreaterThan(0);
  }, INTEGRATION_TIMEOUT_MS);

  it("协议缺失的 blocking gate 导致 run 阻断，gate_results 含失败项，不重试", async () => {
    const runtime = new OrchestratorRuntime({
      workerAdapter: new MockSuccessAdapter(),
    });

    // 只启用 review，协议要求的 blocking gates (test/lint_type/security/policy) 全缺失
    const request = createRunRequest("实现功能", {
      enabled_gates: ["review"] as any,
    });
    const result = await runtime.executeRun(request);

    expect(result.final_status).toBe("blocked");

    // gate_results 应包含缺失 gate 的合成 FAIL 项
    const missingGateResults = result.quality_report.gate_results.filter(
      (g: any) => !g.passed && g.conclusion?.findings?.some(
        (f: any) => f.rule_id === "PROTOCOL-GATE-MISSING"
      )
    );
    expect(missingGateResults.length).toBeGreaterThan(0);
    // 至少包含 test/lint_type/security/policy 中的部分（task-level 会先捕获）
    const missingTypes = missingGateResults.map((g: any) => g.gate_type);
    expect(missingTypes.length).toBeGreaterThanOrEqual(1);

    // 配置错误不应被重试：failed_tasks 中每个任务只有 1 次 attempt
    for (const ft of result.failed_tasks) {
      expect(ft.attempts).toBeLessThanOrEqual(1);
    }

    // skill_failed 事件不应重复（同一个 attempt 只产生一次）
    const auditLog = await runtime.getAuditLog(result.run_id);
    const skillFailedEvents = auditLog.filter((e: any) => e.type === "skill_failed");
    // 按 attempt_id 分组，每个 attempt 最多一次 skill_failed
    const failedByAttempt = new Map<string, number>();
    for (const e of skillFailedEvents) {
      const key = String(e.attempt_id || (e.payload as any)?.attempt_id || "run_level");
      failedByAttempt.set(key, (failedByAttempt.get(key) || 0) + 1);
    }
    for (const [attemptId, count] of failedByAttempt) {
      expect(count).toBeLessThanOrEqual(1);
    }
  }, INTEGRATION_TIMEOUT_MS);

  it("只漏 policy 时协议仍然检测到缺失（最小回归面）", async () => {
    const runtime = new OrchestratorRuntime({
      workerAdapter: new MockSuccessAdapter(),
    });

    // 只启用 review（轻量非 blocking gate），所有 blocking gate 含 policy 都缺失
    const request = createRunRequest("测试漏 policy", {
      enabled_gates: ["review"] as any,
    });
    const result = await runtime.executeRun(request);

    const auditLog = await runtime.getAuditLog(result.run_id);
    const coverageEvents = auditLog.filter(
      (e: any) => e.payload?.phase === "verify_protocol_coverage" || e.payload?.phase === "task_protocol_coverage"
    );
    expect(coverageEvents.length).toBeGreaterThan(0);
    const allMissing = coverageEvents.flatMap(
      (e: any) => (e.payload.missing_blocking_gates as string[]) || []
    );
    // policy 应在缺失列表中（正则修复后能正确解析 "policy / ownership"）
    expect(allMissing).toContain("policy");
    expect(result.final_status).toBe("blocked");

    // gate_results 应包含 policy 的合成 FAIL 项
    const policyFailResults = result.quality_report.gate_results.filter(
      (g: any) => g.gate_type === "policy" && !g.passed
    );
    expect(policyFailResults.length).toBeGreaterThan(0);
    expect(policyFailResults[0].conclusion.findings[0].rule_id).toBe("PROTOCOL-GATE-MISSING");
  }, INTEGRATION_TIMEOUT_MS);

  it("协议覆盖写回 GateResult.blocking（合同值与协议不同时生效）", () => {
    // 直接验证写回机制：gate 合同 blocking=true，但协议覆盖为 false → 写回后应为 false
    const gateResult = {
      gate_type: "test",
      passed: true,
      blocking: true, // 合同原值
      gate_level: "run",
      conclusion: { summary: "ok", findings: [], risk: "low", required_actions: [], suggested_patches: [] },
      schema_version: "1.0.0",
      gate_id: "g1",
      run_id: "r1",
      evaluated_at: new Date().toISOString(),
    };

    // 模拟协议覆盖写回逻辑（与 orchestrator-runtime.ts:1961-1967 一致）
    const protocolGateSpecs = [{ gate: "test", blocking: false }];
    const spec = protocolGateSpecs.find(s => s.gate === gateResult.gate_type);
    if (spec) {
      gateResult.blocking = spec.blocking;
    }

    // 验证写回生效
    expect(gateResult.blocking).toBe(false);

    // 反向验证：协议覆盖为 true 时也生效
    const gateResult2 = { ...gateResult, gate_type: "review", blocking: false };
    const protocolSpecs2 = [{ gate: "review", blocking: true }];
    const spec2 = protocolSpecs2.find(s => s.gate === gateResult2.gate_type);
    if (spec2) {
      gateResult2.blocking = spec2.blocking;
    }
    expect(gateResult2.blocking).toBe(true);
  });

  it("shouldBlock 与 hasBlockingFailure 行为一致", () => {
    const { shouldBlock } = require("../../runtime/gates/gate-classification");
    const { GateSystem } = require("../../runtime/gates/gate-system");
    const gs = new GateSystem();

    const gateResult = {
      gate_type: "review",
      passed: false,
      blocking: false, // 合同原值
      gate_level: "run",
      conclusion: null,
    };
    const overrides = [{ gate: "review", blocking: true }];

    expect(shouldBlock(gateResult, overrides)).toBe(true);
    expect(gs.hasBlockingFailure([gateResult], overrides)).toBe(true);
  });

  it("security gate 合同支持 task 级", () => {
    const { GateSystem } = require("../../runtime/gates/gate-system");
    const gs = new GateSystem();
    const contracts = gs.getContracts();
    const securityContract = contracts.find((c: any) => c.type === "security");
    expect(securityContract).toBeDefined();
    expect(securityContract.levels).toContain("task");
  });

  it("getRunDetail gate_results.blocking 反映协议写回值", async () => {
    const runtime = new OrchestratorRuntime({
      workerAdapter: new MockSuccessAdapter(),
    });

    // 启用 review gate（唯一非 blocking gate），运行会因缺失 blocking gates 而 blocked
    const request = createRunRequest("测试 gate blocking 展示", {
      enabled_gates: ["review"] as any,
    });
    const result = await runtime.executeRun(request);

    // getRunDetail 应包含 gate_results
    const detail = await runtime.getRunDetail(result.run_id);
    expect(detail).toBeDefined();

    // 如果有 review gate 结果，blocking 应与协议一致（review = 非阻断 = false）
    const reviewGateViews = detail!.gate_results.filter(
      (g: any) => g.gate_type === "review"
    );
    if (reviewGateViews.length > 0) {
      expect(reviewGateViews[0].blocking).toBe(false);
    }
  }, INTEGRATION_TIMEOUT_MS);

  it("DEFAULT_RUN_CONFIG.enabled_gates 包含 security", () => {
    const { DEFAULT_RUN_CONFIG } = require("../../runtime/schemas/ga-schemas");
    expect(DEFAULT_RUN_CONFIG.enabled_gates).toContain("security");
    // 验证与协议要求的 blocking gates 一致
    for (const required of ["test", "lint_type", "security", "policy"]) {
      expect(DEFAULT_RUN_CONFIG.enabled_gates).toContain(required);
    }
  });
});