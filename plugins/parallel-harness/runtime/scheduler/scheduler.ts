/**
 * parallel-harness: Scheduler MVP
 *
 * 基于 DAG 依赖关系进行批次调度。
 * 核心原则：先满足依赖，再最大化并行。
 *
 * 来源设计：
 * - claude-task-master: 任务依赖
 * - oh-my-claudecode: 多 agent 调度
 *
 * 反向增强：
 * - 不只多 agent，必须先建图
 * - 优先执行关键路径上的阻塞任务
 * - 对高风险任务限制并发
 */

import type { TaskGraph, TaskNode, TaskStatus, RiskLevel } from "../orchestrator/task-graph";
import type { OwnershipPlan } from "../orchestrator/ownership-planner";
import { findPathOverlaps } from "../orchestrator/ownership-planner";

// ============================================================
// 调度数据结构
// ============================================================

/** 调度批次 */
export interface ScheduleBatch {
  /** 批次编号 */
  batch_index: number;

  /** 本批次的任务 ID */
  task_ids: string[];

  /** 本批次的最大并发数 */
  max_concurrency: number;

  /** 是否包含关键路径任务 */
  has_critical_path_task: boolean;
}

/** 调度计划 */
export interface SchedulePlan {
  /** 所有批次 */
  batches: ScheduleBatch[];

  /** 总批次数 */
  total_batches: number;

  /** 最大并行度 */
  max_parallelism: number;

  /** 预估总轮次 */
  estimated_rounds: number;
}

/** 调度器配置 */
export interface SchedulerConfig {
  /** 全局最大并发 worker 数 */
  max_concurrency: number;

  /** 高风险任务最大并发数 */
  high_risk_max_concurrency: number;

  /** 是否优先调度关键路径 */
  prioritize_critical_path: boolean;
}

const DEFAULT_SCHEDULER_CONFIG: SchedulerConfig = {
  max_concurrency: 5,
  high_risk_max_concurrency: 2,
  prioritize_critical_path: true,
};

// ============================================================
// Scheduler 实现
// ============================================================

/**
 * 生成调度计划
 */
export function createSchedulePlan(
  graph: TaskGraph,
  config: Partial<SchedulerConfig> = {},
  ownershipPlan?: OwnershipPlan
): SchedulePlan {
  const cfg = { ...DEFAULT_SCHEDULER_CONFIG, ...config };
  const batches: ScheduleBatch[] = [];

  // 构建状态追踪
  const completed = new Set<string>();
  const remaining = new Set(graph.tasks.map((t) => t.id));
  const taskMap = new Map(graph.tasks.map((t) => [t.id, t]));
  const criticalPathSet = new Set(graph.critical_path);

  // 构建入度表
  const dependencyMap = new Map<string, Set<string>>();
  for (const task of graph.tasks) {
    dependencyMap.set(task.id, new Set(task.dependencies));
  }
  for (const edge of graph.edges) {
    const deps = dependencyMap.get(edge.to) || new Set();
    deps.add(edge.from);
    dependencyMap.set(edge.to, deps);
  }

  // 构建 write-set 冲突映射
  const writeConflicts = new Map<string, Set<string>>();
  if (ownershipPlan) {
    for (let i = 0; i < ownershipPlan.assignments.length; i++) {
      for (let j = i + 1; j < ownershipPlan.assignments.length; j++) {
        const a1 = ownershipPlan.assignments[i];
        const a2 = ownershipPlan.assignments[j];
        const overlap = findPathOverlaps(a1.exclusive_paths, a2.exclusive_paths).length > 0;
        if (overlap) {
          if (!writeConflicts.has(a1.task_id)) writeConflicts.set(a1.task_id, new Set());
          if (!writeConflicts.has(a2.task_id)) writeConflicts.set(a2.task_id, new Set());
          writeConflicts.get(a1.task_id)!.add(a2.task_id);
          writeConflicts.get(a2.task_id)!.add(a1.task_id);
        }
      }
    }
  }

  let batchIndex = 0;

  while (remaining.size > 0) {
    // 找出所有依赖已满足的任务
    const ready: string[] = [];
    for (const id of remaining) {
      const deps = dependencyMap.get(id) || new Set();
      const allDepsCompleted = [...deps].every((d) => completed.has(d));
      if (allDepsCompleted) {
        ready.push(id);
      }
    }

    if (ready.length === 0) {
      // 死锁检测：剩余任务有依赖但都未完成
      console.warn(
        `调度死锁：剩余 ${remaining.size} 个任务无法调度，强制串行处理`
      );
      // 强制取第一个
      const forcedId = [...remaining][0];
      ready.push(forcedId);
    }

    // 排序：关键路径优先，高风险任务排后
    const sorted = sortByPriority(ready, taskMap, criticalPathSet, cfg);

    // 限制并发
    const hasHighRisk = sorted.some(
      (id) =>
        taskMap.get(id)?.risk_level === "high" ||
        taskMap.get(id)?.risk_level === "critical"
    );
    const maxConcurrency = hasHighRisk
      ? cfg.high_risk_max_concurrency
      : cfg.max_concurrency;

    // 过滤掉有 write-set 冲突的任务
    const batchTasks: string[] = [];
    for (const taskId of sorted) {
      if (batchTasks.length >= maxConcurrency) break;

      const conflicts = writeConflicts.get(taskId);
      const hasConflict = conflicts && [...conflicts].some(c => batchTasks.includes(c));
      if (!hasConflict) {
        batchTasks.push(taskId);
      }
    }

    if (batchTasks.length === 0 && sorted.length > 0) {
      // 所有任务都冲突，强制取第一个
      batchTasks.push(sorted[0]);
    }

    batches.push({
      batch_index: batchIndex,
      task_ids: batchTasks,
      max_concurrency: Math.min(batchTasks.length, maxConcurrency),
      has_critical_path_task: batchTasks.some((id) => criticalPathSet.has(id)),
    });

    // 标记完成
    for (const id of batchTasks) {
      completed.add(id);
      remaining.delete(id);
    }

    batchIndex++;

    // 安全阀
    if (batchIndex > graph.tasks.length * 2) {
      console.error("调度超出安全限制，中止");
      break;
    }
  }

  return {
    batches,
    total_batches: batches.length,
    max_parallelism: Math.max(...batches.map((b) => b.task_ids.length), 1),
    estimated_rounds: batches.length,
  };
}

/**
 * 获取下一批可执行任务（实时调度接口）
 */
export function getNextBatch(
  graph: TaskGraph,
  completedTaskIds: string[],
  config: Partial<SchedulerConfig> = {}
): string[] {
  const cfg = { ...DEFAULT_SCHEDULER_CONFIG, ...config };
  const completed = new Set(completedTaskIds);
  const taskMap = new Map(graph.tasks.map((t) => [t.id, t]));
  const criticalPathSet = new Set(graph.critical_path);

  const dependencyMap = new Map<string, Set<string>>();
  for (const task of graph.tasks) {
    dependencyMap.set(task.id, new Set(task.dependencies));
  }
  for (const edge of graph.edges) {
    const deps = dependencyMap.get(edge.to) || new Set();
    deps.add(edge.from);
    dependencyMap.set(edge.to, deps);
  }

  // 找出 ready 任务
  const ready: string[] = [];
  for (const task of graph.tasks) {
    if (completed.has(task.id)) continue;
    if (task.status === "running" || task.status === "dispatched") continue;

    const deps = dependencyMap.get(task.id) || new Set();
    if ([...deps].every((d) => completed.has(d))) {
      ready.push(task.id);
    }
  }

  const sorted = sortByPriority(ready, taskMap, criticalPathSet, cfg);
  const maxConcurrency = cfg.max_concurrency;

  return sorted.slice(0, maxConcurrency);
}

// ============================================================
// 辅助函数
// ============================================================

function sortByPriority(
  taskIds: string[],
  taskMap: Map<string, TaskNode>,
  criticalPathSet: Set<string>,
  config: SchedulerConfig
): string[] {
  return [...taskIds].sort((a, b) => {
    const taskA = taskMap.get(a);
    const taskB = taskMap.get(b);
    if (!taskA || !taskB) return 0;

    // 关键路径优先
    if (config.prioritize_critical_path) {
      const aOnCritical = criticalPathSet.has(a) ? 1 : 0;
      const bOnCritical = criticalPathSet.has(b) ? 1 : 0;
      if (aOnCritical !== bOnCritical) return bOnCritical - aOnCritical;
    }

    // 低风险优先并行
    const riskOrder: Record<RiskLevel, number> = {
      low: 0,
      medium: 1,
      high: 2,
      critical: 3,
    };
    const riskDiff = riskOrder[taskA.risk_level] - riskOrder[taskB.risk_level];
    if (riskDiff !== 0) return riskDiff;

    // 低复杂度优先
    return taskA.complexity.score - taskB.complexity.score;
  });
}
