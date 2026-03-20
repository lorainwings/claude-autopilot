/**
 * 所有权规划器
 *
 * 为任务分配文件路径所有权，检测并解决路径冲突
 */

import type { OwnershipMapping, ConflictInfo } from '../schemas/types.js';
import type { TaskNode } from '../schemas/task-graph.js';

/**
 * 为任务列表规划文件所有权
 * 确保每个任务拥有不重叠的文件路径
 */
export function planOwnership(tasks: TaskNode[]): OwnershipMapping[] {
  const conflicts = detectConflicts(tasks);
  const resolved = resolveConflicts(tasks, conflicts);
  return resolved;
}

/**
 * 检测任务间的文件路径冲突
 */
export function detectConflicts(tasks: TaskNode[]): ConflictInfo[] {
  const pathMap = new Map<string, string[]>();

  // 收集每个路径被哪些任务使用
  for (const task of tasks) {
    for (const path of task.allowed_paths) {
      if (!pathMap.has(path)) pathMap.set(path, []);
      pathMap.get(path)!.push(task.id);
    }
  }

  // 找出被多个任务共享的路径
  const conflicts: ConflictInfo[] = [];
  for (const [path, taskIds] of pathMap) {
    if (taskIds.length > 1) {
      conflicts.push({
        path,
        tasks: taskIds,
        resolution: 'serialize',
      });
    }
  }

  return conflicts;
}

/**
 * 解决文件路径冲突
 * 通过序列化（添加依赖关系）或分割路径来解决
 */
function resolveConflicts(tasks: TaskNode[], conflicts: ConflictInfo[]): OwnershipMapping[] {
  // 收集需要序列化的路径
  const serializedPaths = new Set<string>();
  for (const conflict of conflicts) {
    serializedPaths.add(conflict.path);
  }

  // 为每个任务生成所有权映射
  const mappings: OwnershipMapping[] = [];

  for (const task of tasks) {
    // 排除冲突路径中不属于自己的（按优先级：先出现的任务优先）
    const ownedPaths: string[] = [];
    const forbidden: string[] = [];

    for (const path of task.allowed_paths) {
      if (serializedPaths.has(path)) {
        // 冲突路径：只有第一个声称拥有它的任务可以拥有
        const conflict = conflicts.find(c => c.path === path);
        if (conflict && conflict.tasks[0] === task.id) {
          ownedPaths.push(path);
        } else {
          // 其他任务的 forbidden_paths 中添加这个路径
          forbidden.push(path);
        }
      } else {
        ownedPaths.push(path);
      }
    }

    mappings.push({
      task_id: task.id,
      role: task.assigned_role ?? 'implementer',
      allowed_paths: ownedPaths,
      forbidden_paths: [...task.forbidden_paths, ...forbidden],
    });
  }

  return mappings;
}
