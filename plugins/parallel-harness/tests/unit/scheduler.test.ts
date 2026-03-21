/**
 * scheduler.ts 单元测试
 *
 * 覆盖：
 * - createSchedulePlan(): 单任务、无依赖并行、依赖分批、关键路径优先、高风险限并发、死锁回退
 * - getNextBatch(): 实时获取可执行任务、跳过已完成和正在执行的任务
 */

import { describe, expect, it, test } from "bun:test";
import { createSchedulePlan, getNextBatch } from "../../runtime/scheduler/scheduler";
import type { TaskNode, TaskEdge, TaskGraph } from "../../runtime/orchestrator/task-graph";

// ============================================================
// 辅助函数
// ============================================================

/** 创建一个带完整字段的 mock 任务节点 */
function createMockTask(overrides: Partial<TaskNode> = {}): TaskNode {
  return {
    id: "task-1",
    title: "测试任务",
    goal: "完成测试",
    dependencies: [],
    status: "pending",
    risk_level: "low",
    complexity: {
      level: "low",
      score: 20,
      dimensions: {
        file_count: 1,
        module_count: 1,
        involves_critical: false,
        estimated_tokens: 1000,
      },
      reasoning: "测试",
    },
    allowed_paths: ["src/"],
    forbidden_paths: ["config/"],
    acceptance_criteria: ["通过测试"],
    required_tests: [],
    model_tier: "tier-1",
    verifier_set: ["test"],
    retry_policy: {
      max_retries: 2,
      escalate_on_retry: true,
      compact_context_on_retry: true,
    },
    ...overrides,
  };
}

/** 创建一个 mock 任务图 */
function createMockGraph(tasks: TaskNode[], edges: TaskEdge[] = []): TaskGraph {
  return {
    graph_id: "test-graph",
    tasks,
    edges,
    critical_path: tasks.map((t) => t.id),
    metadata: {
      created_at: new Date().toISOString(),
      original_intent: "测试",
      total_tasks: tasks.length,
      max_parallelism: 1,
      critical_path_length: tasks.length,
      estimated_total_tokens: tasks.reduce(
        (s, t) => s + t.complexity.dimensions.estimated_tokens,
        0,
      ),
    },
  };
}

// ============================================================
// createSchedulePlan 测试
// ============================================================

describe("createSchedulePlan", () => {
  it("单任务生成单批次", () => {
    const task = createMockTask({ id: "task-1" });
    const graph = createMockGraph([task]);

    const plan = createSchedulePlan(graph);

    expect(plan.total_batches).toBe(1);
    expect(plan.batches).toHaveLength(1);
    expect(plan.batches[0].task_ids).toEqual(["task-1"]);
    expect(plan.batches[0].batch_index).toBe(0);
  });

  it("无依赖多任务可并行（一个批次）", () => {
    // 三个互相独立的任务，没有任何依赖
    const tasks = [
      createMockTask({ id: "a" }),
      createMockTask({ id: "b" }),
      createMockTask({ id: "c" }),
    ];
    const graph = createMockGraph(tasks);

    const plan = createSchedulePlan(graph, { max_concurrency: 10 });

    // 所有任务应该在同一批次
    expect(plan.total_batches).toBe(1);
    expect(plan.batches[0].task_ids).toHaveLength(3);
    expect(plan.batches[0].task_ids).toContain("a");
    expect(plan.batches[0].task_ids).toContain("b");
    expect(plan.batches[0].task_ids).toContain("c");
  });

  it("有依赖任务分到不同批次", () => {
    // task-2 依赖 task-1，必须在不同批次
    const tasks = [
      createMockTask({ id: "task-1" }),
      createMockTask({ id: "task-2", dependencies: ["task-1"] }),
    ];
    const graph = createMockGraph(tasks);

    const plan = createSchedulePlan(graph);

    expect(plan.total_batches).toBe(2);
    expect(plan.batches[0].task_ids).toContain("task-1");
    expect(plan.batches[1].task_ids).toContain("task-2");
  });

  it("关键路径优先调度", () => {
    // 创建多个无依赖任务，其中 critical-task 在关键路径上
    const criticalTask = createMockTask({ id: "critical-task", complexity: { level: "low", score: 50, dimensions: { file_count: 1, module_count: 1, involves_critical: false, estimated_tokens: 1000 }, reasoning: "关键" } });
    const normalTask1 = createMockTask({ id: "normal-1", complexity: { level: "low", score: 10, dimensions: { file_count: 1, module_count: 1, involves_critical: false, estimated_tokens: 500 }, reasoning: "普通" } });
    const normalTask2 = createMockTask({ id: "normal-2", complexity: { level: "low", score: 10, dimensions: { file_count: 1, module_count: 1, involves_critical: false, estimated_tokens: 500 }, reasoning: "普通" } });

    const graph = createMockGraph([normalTask1, criticalTask, normalTask2]);
    // 只有 critical-task 在关键路径上
    graph.critical_path = ["critical-task"];

    // 限制并发为 1，这样只取排序后的第一个
    const plan = createSchedulePlan(graph, {
      max_concurrency: 1,
      prioritize_critical_path: true,
    });

    // 关键路径任务应该排在第一批
    expect(plan.batches[0].task_ids[0]).toBe("critical-task");
    expect(plan.batches[0].has_critical_path_task).toBe(true);
  });

  it("高风险任务限制并发 (high_risk_max_concurrency)", () => {
    // 创建包含高风险任务的批次
    const tasks = [
      createMockTask({ id: "risky-1", risk_level: "high" }),
      createMockTask({ id: "risky-2", risk_level: "high" }),
      createMockTask({ id: "safe-1", risk_level: "low" }),
      createMockTask({ id: "safe-2", risk_level: "low" }),
    ];
    const graph = createMockGraph(tasks);

    const plan = createSchedulePlan(graph, {
      max_concurrency: 10,
      high_risk_max_concurrency: 2,
    });

    // 第一批应只有 high_risk_max_concurrency 个任务（因为批次中包含高风险任务）
    expect(plan.batches[0].task_ids.length).toBeLessThanOrEqual(2);
    expect(plan.batches[0].max_concurrency).toBeLessThanOrEqual(2);
  });

  it("死锁检测和强制串行回退", () => {
    // 构造循环依赖：A -> B -> A（通过 edges 制造死锁场景）
    const taskA = createMockTask({ id: "A" });
    const taskB = createMockTask({ id: "B", dependencies: ["A"] });

    // 通过 edges 让 A 也依赖 B，形成环
    const edges: TaskEdge[] = [
      { from: "A", to: "B", type: "dependency" },
      { from: "B", to: "A", type: "dependency" },
    ];

    const graph = createMockGraph([taskA, taskB], edges);

    // 不应抛出异常，应该通过死锁检测强制串行处理
    const plan = createSchedulePlan(graph);

    // 两个任务最终都应被调度（通过强制串行回退）
    const allScheduledIds = plan.batches.flatMap((b) => b.task_ids);
    expect(allScheduledIds).toContain("A");
    expect(allScheduledIds).toContain("B");
    // 至少需要 2 个批次（因为死锁后强制取一个）
    expect(plan.total_batches).toBeGreaterThanOrEqual(2);
  });
});

// ============================================================
// getNextBatch 测试
// ============================================================

describe("getNextBatch", () => {
  it("实时获取可执行任务", () => {
    const tasks = [
      createMockTask({ id: "task-1" }),
      createMockTask({ id: "task-2", dependencies: ["task-1"] }),
      createMockTask({ id: "task-3" }),
    ];
    const graph = createMockGraph(tasks);

    // 没有任何任务完成，task-1 和 task-3 都可执行
    const batch = getNextBatch(graph, []);

    expect(batch).toContain("task-1");
    expect(batch).toContain("task-3");
    // task-2 依赖 task-1，不在 batch 中
    expect(batch).not.toContain("task-2");
  });

  it("跳过已完成和正在执行的任务", () => {
    const tasks = [
      createMockTask({ id: "done", status: "completed" }),
      createMockTask({ id: "running-task", status: "running" }),
      createMockTask({ id: "dispatched-task", status: "dispatched" }),
      createMockTask({ id: "waiting", dependencies: ["done"] }),
    ];
    const graph = createMockGraph(tasks);

    // done 已完成
    const batch = getNextBatch(graph, ["done"]);

    // done 已完成不应出现
    expect(batch).not.toContain("done");
    // running 和 dispatched 状态应被跳过
    expect(batch).not.toContain("running-task");
    expect(batch).not.toContain("dispatched-task");
    // waiting 的依赖 done 已完成，应在可执行列表中
    expect(batch).toContain("waiting");
  });
});
