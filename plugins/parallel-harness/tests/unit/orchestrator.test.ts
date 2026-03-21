/**
 * parallel-harness: 编排器组件测试（意图分析 + 任务图构建 + 所有权规划）
 */
import { describe, expect, it, test } from "bun:test";
import { analyzeIntent } from "../../runtime/orchestrator/intent-analyzer";
import { buildTaskGraph } from "../../runtime/orchestrator/task-graph-builder";
import { scoreComplexity } from "../../runtime/orchestrator/complexity-scorer";
import { planOwnership, validateOwnership } from "../../runtime/orchestrator/ownership-planner";
import type { TaskNode, TaskGraph, TaskEdge } from "../../runtime/orchestrator/task-graph";

// ============================================================
// 意图分析测试
// ============================================================

describe("analyzeIntent", () => {
  it("提取核心目标", () => {
    const result = analyzeIntent("实现用户登录功能。需要前后端配合。");
    expect(result.core_goal).toBe("实现用户登录功能");
  });

  it("列表格式提取子目标", () => {
    const result = analyzeIntent("任务列表：\n- 实现登录页面\n- 添加后端 API\n- 编写测试");
    expect(result.sub_goals.length).toBeGreaterThanOrEqual(3);
  });

  it("数字格式提取子目标", () => {
    const result = analyzeIntent("1. 创建数据库表\n2. 实现 API\n3. 添加前端页面");
    expect(result.sub_goals.length).toBeGreaterThanOrEqual(3);
  });

  it("检测多个工作域", () => {
    const result = analyzeIntent("修改前端 UI 组件和后端 API 接口，更新数据库 schema");
    expect(result.change_scope.domains.length).toBeGreaterThanOrEqual(2);
    expect(result.change_scope.has_cross_module_dependencies).toBe(true);
  });

  it("单域低风险", () => {
    const result = analyzeIntent("修改一个简单的工具函数");
    expect(result.risk_estimation.overall).toBe("low");
  });

  it("多域高风险", () => {
    const result = analyzeIntent("重构前端组件、后端服务和数据库迁移，还要更新 CI 配置和测试");
    expect(["medium", "high"]).toContain(result.risk_estimation.overall);
  });

  it("建议执行模式", () => {
    const simple = analyzeIntent("修复一个 typo");
    expect(simple.suggested_mode).toBe("serial");

    const complex = analyzeIntent("- 实现 A 模块\n- 实现 B 模块\n- 实现 C 模块");
    expect(["parallel", "hybrid"]).toContain(complex.suggested_mode);
  });
});

// ============================================================
// 任务图构建测试
// ============================================================

describe("buildTaskGraph", () => {
  it("单目标生成单任务", () => {
    const analysis = analyzeIntent("修复 bug");
    const graph = buildTaskGraph(analysis);
    expect(graph.tasks.length).toBeGreaterThanOrEqual(1);
    expect(graph.graph_id).toBeDefined();
    expect(graph.metadata.total_tasks).toBe(graph.tasks.length);
  });

  it("多目标生成多任务", () => {
    const analysis = analyzeIntent("- 实现 A 功能\n- 实现 B 功能\n- 实现 C 功能");
    const graph = buildTaskGraph(analysis);
    expect(graph.tasks.length).toBeGreaterThanOrEqual(3);
  });

  it("任务节点有完整字段", () => {
    const analysis = analyzeIntent("实现一个功能");
    const graph = buildTaskGraph(analysis);
    const task = graph.tasks[0];
    expect(task.id).toBeDefined();
    expect(task.title).toBeDefined();
    expect(task.goal).toBeDefined();
    expect(task.status).toBe("pending");
    expect(task.complexity).toBeDefined();
    expect(task.model_tier).toBeDefined();
    expect(task.retry_policy).toBeDefined();
    expect(task.verifier_set).toBeDefined();
  });

  it("关键路径计算", () => {
    const analysis = analyzeIntent("- 实现 schema\n- 实现 API\n- 实现 UI");
    const graph = buildTaskGraph(analysis);
    expect(graph.critical_path.length).toBeGreaterThanOrEqual(1);
  });

  it("元数据正确", () => {
    const analysis = analyzeIntent("- 任务 A\n- 任务 B");
    const graph = buildTaskGraph(analysis);
    expect(graph.metadata.total_tasks).toBe(graph.tasks.length);
    expect(graph.metadata.estimated_total_tokens).toBeGreaterThan(0);
    expect(graph.metadata.max_parallelism).toBeGreaterThanOrEqual(1);
    expect(graph.metadata.original_intent).toContain("任务");
  });

  it("包含 schema 关键词的任务被设为前置", () => {
    const analysis = analyzeIntent("- 更新 schema 定义\n- 实现业务逻辑\n- 编写测试");
    const graph = buildTaskGraph(analysis);
    if (graph.edges.length > 0) {
      const schemaTask = graph.tasks.find(t => t.goal.includes("schema"));
      if (schemaTask) {
        const hasOutEdge = graph.edges.some(e => e.from === schemaTask.id);
        expect(hasOutEdge).toBe(true);
      }
    }
  });
});

// ============================================================
// 复杂度评分测试
// ============================================================

describe("scoreComplexity", () => {
  it("简单任务得分低", () => {
    const score = scoreComplexity({
      goal: "修改一个变量名",
      domain_name: "general",
      estimated_files: 1,
      has_cross_dependency: false,
    });
    expect(["trivial", "low"]).toContain(score.level);
    expect(score.score).toBeLessThan(50);
  });

  it("复杂任务得分高", () => {
    const score = scoreComplexity({
      goal: "重构整个认证系统，涉及 schema 迁移和多模块修改",
      domain_name: "backend",
      estimated_files: 20,
      has_cross_dependency: true,
    });
    expect(["high", "extreme"]).toContain(score.level);
    expect(score.score).toBeGreaterThan(50);
  });

  it("分数范围 0-100", () => {
    const score = scoreComplexity({
      goal: "测试",
      domain_name: "test",
      estimated_files: 5,
      has_cross_dependency: false,
    });
    expect(score.score).toBeGreaterThanOrEqual(0);
    expect(score.score).toBeLessThanOrEqual(100);
  });

  it("dimensions 字段正确", () => {
    const score = scoreComplexity({
      goal: "实现功能",
      domain_name: "backend",
      estimated_files: 3,
      has_cross_dependency: true,
    });
    expect(score.dimensions.file_count).toBeDefined();
    expect(score.dimensions.estimated_tokens).toBeGreaterThan(0);
    expect(score.reasoning).toBeDefined();
  });
});

// ============================================================
// 所有权规划测试
// ============================================================

function createMockTask(overrides: Partial<TaskNode> = {}): TaskNode {
  return {
    id: "task-1", title: "测试任务", goal: "完成测试", dependencies: [],
    status: "pending", risk_level: "low",
    complexity: { level: "low", score: 20, dimensions: { file_count: 1, module_count: 1, involves_critical: false, estimated_tokens: 1000 }, reasoning: "测试" },
    allowed_paths: ["src/"], forbidden_paths: ["config/"],
    acceptance_criteria: ["通过测试"], required_tests: [],
    model_tier: "tier-1", verifier_set: ["test"],
    retry_policy: { max_retries: 2, escalate_on_retry: true, compact_context_on_retry: true },
    ...overrides,
  };
}

function createMockGraph(tasks: TaskNode[], edges: TaskEdge[] = []): TaskGraph {
  return {
    graph_id: "test-graph", tasks, edges,
    critical_path: tasks.map(t => t.id),
    metadata: {
      created_at: new Date().toISOString(), original_intent: "测试",
      total_tasks: tasks.length, max_parallelism: 1,
      critical_path_length: tasks.length,
      estimated_total_tokens: tasks.reduce((s, t) => s + t.complexity.dimensions.estimated_tokens, 0),
    },
  };
}

describe("planOwnership", () => {
  it("正常分配独占路径", () => {
    const tasks = [
      createMockTask({ id: "t1", allowed_paths: ["src/a/"], forbidden_paths: [] }),
      createMockTask({ id: "t2", allowed_paths: ["src/b/"], forbidden_paths: [] }),
    ];
    const graph = createMockGraph(tasks);
    const plan = planOwnership(graph);
    expect(plan.assignments.length).toBe(2);
    expect(plan.conflicts.length).toBe(0);
    expect(plan.has_unresolvable_conflicts).toBe(false);
  });

  it("检测路径重叠冲突", () => {
    const tasks = [
      createMockTask({ id: "t1", allowed_paths: ["src/shared/"] }),
      createMockTask({ id: "t2", allowed_paths: ["src/shared/"] }),
    ];
    const graph = createMockGraph(tasks);
    const plan = planOwnership(graph);
    expect(plan.conflicts.length).toBeGreaterThan(0);
    expect(plan.conflicts[0].type).toBe("write_write");
  });

  it("冲突路径从后序任务独占区移到共享读", () => {
    const tasks = [
      createMockTask({ id: "t1", allowed_paths: ["src/shared/"] }),
      createMockTask({ id: "t2", allowed_paths: ["src/shared/"] }),
    ];
    const graph = createMockGraph(tasks);
    const plan = planOwnership(graph);
    const t2Assignment = plan.assignments.find(a => a.task_id === "t2");
    // 冲突解决后，t2 的 shared_read_paths 应包含冲突路径
    if (plan.conflicts.some(c => c.resolution === "serialize")) {
      expect(t2Assignment?.shared_read_paths.length).toBeGreaterThan(0);
    }
  });
});

describe("validateOwnership", () => {
  it("合法路径通过", () => {
    const assignment = { task_id: "t1", exclusive_paths: ["src/"], shared_read_paths: [], forbidden_paths: [] };
    const violations = validateOwnership(assignment, ["src/main.ts"]);
    expect(violations.length).toBe(0);
  });

  it("禁止路径写入报违规", () => {
    const assignment = { task_id: "t1", exclusive_paths: ["src/"], shared_read_paths: [], forbidden_paths: ["config/"] };
    const violations = validateOwnership(assignment, ["config/settings.json"]);
    expect(violations.length).toBe(1);
    expect(violations[0].type).toBe("forbidden_path_write");
  });

  it("范围外写入报违规", () => {
    const assignment = { task_id: "t1", exclusive_paths: ["src/a/"], shared_read_paths: [], forbidden_paths: [] };
    const violations = validateOwnership(assignment, ["lib/utils.ts"]);
    expect(violations.length).toBe(1);
    expect(violations[0].type).toBe("out_of_scope_write");
  });
});
