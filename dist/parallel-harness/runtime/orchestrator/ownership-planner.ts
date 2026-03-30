/**
 * parallel-harness: Ownership Planner
 *
 * 为每个任务分配最小文件所有权边界。
 * 文件所有权是并行执行安全的核心保证。
 *
 * 来源设计：
 * - oh-my-claudecode: 多 agent 但必须防冲突
 * - BMAD-METHOD: 角色职责边界
 *
 * 反向增强：
 * - 不能只开 agent 不做 ownership
 * - 路径重叠时必须拆分或降级
 */

import type { TaskNode, TaskGraph, RiskLevel } from "./task-graph";

// ============================================================
// Ownership 数据结构
// ============================================================

/** 所有权分配结果 */
export interface OwnershipPlan {
  /** 每个任务的所有权映射 */
  assignments: OwnershipAssignment[];

  /** 冲突检测结果 */
  conflicts: OwnershipConflict[];

  /** 是否存在不可解决的冲突 */
  has_unresolvable_conflicts: boolean;

  /** 建议的降级任务 */
  downgrade_suggestions: string[];
}

/** 单个任务的所有权分配 */
export interface OwnershipAssignment {
  /** 任务 ID */
  task_id: string;

  /** 独占路径（只有该任务能写） */
  exclusive_paths: string[];

  /** 共享读路径（可读不可写） */
  shared_read_paths: string[];

  /** 禁止路径 */
  forbidden_paths: string[];
}

/** 所有权冲突 */
export interface OwnershipConflict {
  /** 冲突路径 */
  path: string;

  /** 冲突的任务 ID 列表 */
  conflicting_tasks: string[];

  /** 冲突类型 */
  type: "write_write" | "structural_dependency";

  /** 建议的解决方式 */
  resolution: "serialize" | "split" | "merge_guard";

  /** 冲突风险等级 */
  risk: RiskLevel;
}

// ============================================================
// Ownership Planner 实现
// ============================================================

/**
 * 为任务图生成所有权规划
 */
export function planOwnership(graph: TaskGraph): OwnershipPlan {
  const assignments: OwnershipAssignment[] = [];
  const conflicts: OwnershipConflict[] = [];

  // 1. 为每个任务分配初始所有权
  for (const task of graph.tasks) {
    assignments.push({
      task_id: task.id,
      exclusive_paths: [...task.allowed_paths],
      shared_read_paths: [],
      forbidden_paths: [...task.forbidden_paths],
    });
  }

  // 2. 检测路径冲突
  for (let i = 0; i < assignments.length; i++) {
    for (let j = i + 1; j < assignments.length; j++) {
      const overlaps = findPathOverlaps(
        assignments[i].exclusive_paths,
        assignments[j].exclusive_paths
      );

      for (const overlap of overlaps) {
        conflicts.push({
          path: overlap,
          conflicting_tasks: [assignments[i].task_id, assignments[j].task_id],
          type: "write_write",
          resolution: resolveConflictStrategy(graph, assignments[i].task_id, assignments[j].task_id),
          risk: assessConflictRisk(overlap),
        });
      }
    }
  }

  // 3. 解决冲突：将冲突路径从后序任务的独占区移到共享读
  for (const conflict of conflicts) {
    if (conflict.resolution === "serialize") {
      // 后序任务转为共享读
      const laterTask = conflict.conflicting_tasks[1];
      const assignment = assignments.find((a) => a.task_id === laterTask);
      if (assignment) {
        assignment.exclusive_paths = assignment.exclusive_paths.filter(
          (p) => p !== conflict.path
        );
        if (!assignment.shared_read_paths.includes(conflict.path)) {
          assignment.shared_read_paths.push(conflict.path);
        }
      }
    } else if (conflict.resolution === "merge_guard") {
      // merge_guard 冲突：调度器层面禁止同批并发（通过 ownershipPlan 传递给 scheduler）
    }
  }

  // 4. 检查不可解决冲突
  const unresolvable = conflicts.filter(
    (c) => c.risk === "critical" || c.risk === "high"
  );

  return {
    assignments,
    conflicts,
    has_unresolvable_conflicts: unresolvable.length > 0,
    downgrade_suggestions: unresolvable.map(
      (c) =>
        `任务 ${c.conflicting_tasks.join(", ")} 在路径 ${c.path} 存在高风险冲突，建议串行执行`
    ),
  };
}

/**
 * 验证 worker 输出是否越界
 */
export function validateOwnership(
  assignment: OwnershipAssignment,
  modifiedPaths: string[]
): OwnershipViolation[] {
  const violations: OwnershipViolation[] = [];

  // exclusive_paths 为空表示不限制路径（general 域场景），跳过越界检查
  const hasPathRestriction = assignment.exclusive_paths.length > 0;

  for (const path of modifiedPaths) {
    // 检查是否在禁止路径内
    const isForbidden = assignment.forbidden_paths.some(
      (forbidden) => pathMatches(path, forbidden)
    );

    if (isForbidden) {
      violations.push({
        path,
        task_id: assignment.task_id,
        type: "forbidden_path_write",
        message: `任务 ${assignment.task_id} 写入了禁止路径: ${path}`,
      });
    } else if (hasPathRestriction) {
      // 只有在有路径限制时才检查越界
      const isAllowed = assignment.exclusive_paths.some(
        (allowed) => pathMatches(path, allowed)
      );
      if (!isAllowed) {
        violations.push({
          path,
          task_id: assignment.task_id,
          type: "out_of_scope_write",
          message: `任务 ${assignment.task_id} 写入了所有权范围外的路径: ${path}`,
        });
      }
    }
  }

  return violations;
}

/** 所有权违规 */
export interface OwnershipViolation {
  path: string;
  task_id: string;
  type: "forbidden_path_write" | "out_of_scope_write";
  message: string;
}

// ============================================================
// 辅助函数
// ============================================================

export function findPathOverlaps(paths1: string[], paths2: string[]): string[] {
  const overlaps: string[] = [];
  for (const p1 of paths1) {
    for (const p2 of paths2) {
      if (pathMatches(p1, p2) || pathMatches(p2, p1)) {
        overlaps.push(p1.length <= p2.length ? p1 : p2);
      }
    }
  }
  return [...new Set(overlaps)];
}

function pathMatches(path: string, pattern: string): boolean {
  // "." 或 "./" 代表项目根目录，匹配所有路径
  if (pattern === "." || pattern === "./") return true;
  // 简单匹配：精确匹配或前缀匹配
  if (path === pattern) return true;
  if (pattern.endsWith("/**") || pattern.endsWith("/*")) {
    const prefix = pattern.replace(/\/\*\*?$/, "");
    return path.startsWith(prefix);
  }
  if (pattern.includes("*")) {
    const regex = new RegExp(
      "^" + pattern.replace(/\*/g, ".*").replace(/\?/g, ".") + "$"
    );
    return regex.test(path);
  }
  // 目录前缀匹配：pattern 可能以 / 结尾也可能不以 / 结尾
  const normalizedPattern = pattern.endsWith("/") ? pattern : pattern + "/";
  return path.startsWith(normalizedPattern) || path === pattern;
}

function resolveConflictStrategy(
  graph: TaskGraph,
  task1Id: string,
  task2Id: string
): "serialize" | "split" | "merge_guard" {
  // 如果已有依赖关系，serialize
  const hasEdge = graph.edges.some(
    (e) =>
      (e.from === task1Id && e.to === task2Id) ||
      (e.from === task2Id && e.to === task1Id)
  );
  if (hasEdge) return "serialize";

  // 默认使用 merge_guard
  return "merge_guard";
}

function assessConflictRisk(path: string): RiskLevel {
  const pathLower = path.toLowerCase();

  if (
    pathLower.includes("schema") ||
    pathLower.includes("migration") ||
    pathLower.includes("config")
  ) {
    return "high";
  }

  if (
    pathLower.includes("index") ||
    pathLower.includes("main") ||
    pathLower.includes("app")
  ) {
    return "medium";
  }

  return "low";
}
