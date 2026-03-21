/**
 * parallel-harness: Merge Guard
 *
 * 合并守卫。在任务汇总、autofix、PR 输出前再次检查所有权和策略。
 * 升级 ownership 从"规划建议"到"强约束执行器"。
 *
 * 三层检查：
 * 1. Path ownership — 越界写入检测
 * 2. Policy compliance — 策略合规检查
 * 3. Interface contract — 接口契约验证
 */

import type { TaskNode, TaskGraph } from "../orchestrator/task-graph";
import type { WorkerOutput } from "../orchestrator/role-contracts";
import type { OwnershipPlan, OwnershipAssignment } from "../orchestrator/ownership-planner";
import { validateOwnership, type OwnershipViolation } from "../orchestrator/ownership-planner";
import type { ExecutionContext, PolicyEvalResult } from "../engine/orchestrator-runtime";
import { generateId } from "../schemas/ga-schemas";

// ============================================================
// Merge Guard Result
// ============================================================

export interface MergeGuardResult {
  /** 检查 ID */
  check_id: string;

  /** 是否允许合并 */
  allowed: boolean;

  /** 所有权违规 */
  ownership_violations: OwnershipViolation[];

  /** 策略违规 */
  policy_violations: PolicyViolationDetail[];

  /** 接口契约违规 */
  interface_violations: InterfaceViolation[];

  /** 冲突文件（多个 worker 修改同一文件） */
  file_conflicts: FileConflict[];

  /** 阻断原因 */
  blocking_reasons: string[];

  /** 警告 */
  warnings: string[];

  /** 检查时间 */
  checked_at: string;
}

export interface PolicyViolationDetail {
  rule_id: string;
  message: string;
  severity: "warning" | "error" | "critical";
  task_id: string;
}

export interface InterfaceViolation {
  expected_contract: string;
  actual_output: string;
  task_id: string;
  message: string;
}

export interface FileConflict {
  path: string;
  conflicting_tasks: string[];
  type: "concurrent_write" | "delete_modify" | "structural";
  resolution: "manual" | "auto_merge" | "last_write_wins";
}

// ============================================================
// Merge Guard Implementation
// ============================================================

export class MergeGuard {
  /**
   * 执行合并前完整检查
   */
  check(
    ctx: ExecutionContext,
    graph: TaskGraph,
    ownershipPlan: OwnershipPlan,
    workerOutputs: Map<string, WorkerOutput>
  ): MergeGuardResult {
    const result: MergeGuardResult = {
      check_id: generateId("mg"),
      allowed: true,
      ownership_violations: [],
      policy_violations: [],
      interface_violations: [],
      file_conflicts: [],
      blocking_reasons: [],
      warnings: [],
      checked_at: new Date().toISOString(),
    };

    // 1. 所有权检查
    for (const [taskId, output] of workerOutputs) {
      const assignment = ownershipPlan.assignments.find((a) => a.task_id === taskId);
      if (!assignment) {
        result.warnings.push(`任务 ${taskId} 缺少所有权分配`);
        continue;
      }

      const violations = validateOwnership(assignment, output.modified_paths);
      result.ownership_violations.push(...violations);
    }

    // 2. 文件冲突检测
    result.file_conflicts = this.detectFileConflicts(workerOutputs);

    // 3. 策略合规检查
    for (const [taskId, output] of workerOutputs) {
      const policyResult = ctx.policyEngine.evaluate(ctx, "merge_check", {
        task_id: taskId,
        modified_paths: output.modified_paths,
        artifacts: output.artifacts,
      });

      if (!policyResult.allowed) {
        for (const v of policyResult.violations) {
          result.policy_violations.push({
            rule_id: v.rule_id,
            message: v.message,
            severity: v.severity === "critical" ? "critical" : v.severity === "error" ? "error" : "warning",
            task_id: taskId,
          });
        }
      }
    }

    // 4. 接口契约检查
    result.interface_violations = this.checkInterfaceContracts(graph, workerOutputs);

    // 5. 汇总阻断原因
    if (result.ownership_violations.length > 0) {
      result.blocking_reasons.push(
        `${result.ownership_violations.length} 个所有权违规: ` +
        result.ownership_violations.map((v) => v.message).join("; ")
      );
    }

    if (result.file_conflicts.filter((c) => c.resolution === "manual").length > 0) {
      result.blocking_reasons.push(
        `${result.file_conflicts.filter((c) => c.resolution === "manual").length} 个需要手工解决的文件冲突`
      );
    }

    if (result.policy_violations.filter((v) => v.severity === "error" || v.severity === "critical").length > 0) {
      result.blocking_reasons.push(
        `${result.policy_violations.filter((v) => v.severity !== "warning").length} 个策略违规`
      );
    }

    result.allowed = result.blocking_reasons.length === 0;

    return result;
  }

  /**
   * 检测多个 worker 修改同一文件的冲突
   */
  private detectFileConflicts(workerOutputs: Map<string, WorkerOutput>): FileConflict[] {
    const pathToTasks = new Map<string, string[]>();

    for (const [taskId, output] of workerOutputs) {
      for (const path of output.modified_paths) {
        const tasks = pathToTasks.get(path) || [];
        tasks.push(taskId);
        pathToTasks.set(path, tasks);
      }
    }

    const conflicts: FileConflict[] = [];
    for (const [path, tasks] of pathToTasks) {
      if (tasks.length > 1) {
        conflicts.push({
          path,
          conflicting_tasks: tasks,
          type: "concurrent_write",
          resolution: this.suggestResolution(path),
        });
      }
    }

    return conflicts;
  }

  /**
   * 检查接口契约
   */
  private checkInterfaceContracts(
    graph: TaskGraph,
    workerOutputs: Map<string, WorkerOutput>
  ): InterfaceViolation[] {
    const violations: InterfaceViolation[] = [];

    // 检查 interface_contract 类型的边
    for (const edge of graph.edges) {
      if (edge.type !== "interface_contract") continue;

      const fromOutput = workerOutputs.get(edge.from);
      const toTask = graph.tasks.find((t) => t.id === edge.to);

      if (!fromOutput || !toTask) continue;

      // 简单检查：上游任务是否产出了下游任务期望的文件
      const expectedPaths = toTask.allowed_paths;
      const producedPaths = fromOutput.modified_paths;

      const missing = expectedPaths.filter(
        (ep) => !producedPaths.some((pp) => pp.startsWith(ep.replace(/\/\*\*?$/, "")))
      );

      if (missing.length > 0) {
        violations.push({
          expected_contract: `任务 ${edge.to} 期望路径: ${missing.join(", ")}`,
          actual_output: `任务 ${edge.from} 产出路径: ${producedPaths.join(", ")}`,
          task_id: edge.from,
          message: `接口契约未满足: 上游 ${edge.from} 未产出下游 ${edge.to} 期望的文件`,
        });
      }
    }

    return violations;
  }

  /**
   * 根据路径类型建议冲突解决方式
   */
  private suggestResolution(path: string): "manual" | "auto_merge" | "last_write_wins" {
    const lower = path.toLowerCase();

    // 配置文件、schema、关键逻辑需要手动解决
    if (
      lower.includes("schema") ||
      lower.includes("config") ||
      lower.includes("migration") ||
      lower.includes("index")
    ) {
      return "manual";
    }

    // 测试文件可以自动合并
    if (lower.includes("test") || lower.includes("spec")) {
      return "auto_merge";
    }

    // 文档可以 last_write_wins
    if (lower.includes("readme") || lower.includes(".md") || lower.includes("doc")) {
      return "last_write_wins";
    }

    return "manual";
  }
}
