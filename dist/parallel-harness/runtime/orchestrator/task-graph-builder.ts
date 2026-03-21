/**
 * parallel-harness: Task Graph Builder
 *
 * 从意图分析结果构建任务 DAG。
 * 核心职责：拆解任务、建立依赖、标记关键路径。
 *
 * 来源设计：
 * - claude-task-master: 任务图、依赖、复杂度字段
 * - oh-my-claudecode: 多 agent 但必须 task-graph-first
 *
 * 反向增强：
 * - 任务图必须是 DAG（无环）
 * - 每个节点必须有完整契约字段
 */

import type {
  TaskGraph,
  TaskNode,
  TaskEdge,
  TaskStatus,
  ModelTier,
  ComplexityScore,
  RetryPolicy,
  VerifierType,
} from "./task-graph";
import type { IntentAnalysis } from "./intent-analyzer";
import { scoreComplexity } from "./complexity-scorer";

// ============================================================
// Builder 配置
// ============================================================

export interface BuilderConfig {
  /** 默认重试策略 */
  default_retry_policy: RetryPolicy;

  /** 默认验证器集合 */
  default_verifier_set: VerifierType[];

  /** 最大任务数限制 */
  max_tasks: number;
}

const DEFAULT_CONFIG: BuilderConfig = {
  default_retry_policy: {
    max_retries: 2,
    escalate_on_retry: true,
    compact_context_on_retry: true,
  },
  default_verifier_set: ["test", "review"],
  max_tasks: 20,
};

// ============================================================
// Task Graph Builder
// ============================================================

/**
 * 从意图分析结果构建任务图
 */
export function buildTaskGraph(
  analysis: IntentAnalysis,
  config: Partial<BuilderConfig> = {},
  project_root?: string
): TaskGraph {
  const cfg = { ...DEFAULT_CONFIG, ...config };

  // 1. 为每个子目标创建任务节点
  const tasks = createTaskNodes(analysis, cfg, project_root);

  // 2. 推断依赖关系
  const edges = inferDependencies(tasks, analysis);

  // 3. 验证 DAG（无环检测）
  if (hasCycle(tasks, edges)) {
    // 如果检测到环，回退为串行链
    return buildSerialChain(tasks, analysis);
  }

  // 4. 计算关键路径
  const criticalPath = computeCriticalPath(tasks, edges);

  // 5. 组装任务图
  const graph: TaskGraph = {
    graph_id: generateGraphId(),
    tasks,
    edges,
    critical_path: criticalPath,
    metadata: {
      created_at: new Date().toISOString(),
      original_intent: analysis.raw_input,
      total_tasks: tasks.length,
      max_parallelism: computeMaxParallelism(tasks, edges),
      critical_path_length: criticalPath.length,
      estimated_total_tokens: tasks.reduce(
        (sum, t) => sum + t.complexity.dimensions.estimated_tokens,
        0
      ),
    },
  };

  return graph;
}

// ============================================================
// 内部实现
// ============================================================

function createTaskNodes(
  analysis: IntentAnalysis,
  config: BuilderConfig,
  project_root?: string
): TaskNode[] {
  const tasks: TaskNode[] = [];

  for (let i = 0; i < Math.min(analysis.sub_goals.length, config.max_tasks); i++) {
    const subGoal = analysis.sub_goals[i];
    const domain = analysis.change_scope.domains[
      i % analysis.change_scope.domains.length
    ];

    const complexity = scoreComplexity({
      goal: subGoal,
      domain_name: domain?.name || "general",
      estimated_files: domain?.estimated_change_lines
        ? Math.ceil(domain.estimated_change_lines / 30)
        : 3,
      has_cross_dependency:
        analysis.change_scope.has_cross_module_dependencies,
    });

    const modelTier = selectModelTier(complexity);

    const task: TaskNode = {
      id: `task-${i + 1}`,
      title: subGoal.substring(0, 80),
      goal: subGoal,
      dependencies: [],
      status: "pending" as TaskStatus,
      risk_level: analysis.risk_estimation.overall,
      complexity,
      // general 域 paths 为空时，用 project_root 收窄权限（最小权限原则）
      // 若连 project_root 也没有，则保持空数组（validateOwnership 视为不限制）
      allowed_paths: domain?.paths.length
        ? domain.paths
        : (project_root ? [project_root] : []),
      forbidden_paths: [],
      acceptance_criteria: [`完成: ${subGoal}`],
      required_tests: [],
      model_tier: modelTier,
      verifier_set: config.default_verifier_set,
      retry_policy: config.default_retry_policy,
    };

    tasks.push(task);
  }

  return tasks;
}

function inferDependencies(
  tasks: TaskNode[],
  analysis: IntentAnalysis
): TaskEdge[] {
  const edges: TaskEdge[] = [];

  // MVP 策略：如果有跨模块依赖，后续域依赖前序域
  if (analysis.change_scope.has_cross_module_dependencies && tasks.length > 1) {
    // 检查路径重叠
    for (let i = 0; i < tasks.length; i++) {
      for (let j = i + 1; j < tasks.length; j++) {
        const overlap = hasPathOverlap(
          tasks[i].allowed_paths,
          tasks[j].allowed_paths
        );
        if (overlap) {
          edges.push({
            from: tasks[i].id,
            to: tasks[j].id,
            type: "dependency",
          });
        }
      }
    }
  }

  // 如果涉及 infra/schema，让它们优先执行
  const infraTasks = tasks.filter(
    (t) =>
      t.goal.toLowerCase().includes("schema") ||
      t.goal.toLowerCase().includes("infra") ||
      t.goal.toLowerCase().includes("migration") ||
      t.goal.toLowerCase().includes("config")
  );

  const nonInfraTasks = tasks.filter((t) => !infraTasks.includes(t));

  for (const infra of infraTasks) {
    for (const other of nonInfraTasks) {
      // 避免重复边
      if (!edges.some((e) => e.from === infra.id && e.to === other.id)) {
        edges.push({
          from: infra.id,
          to: other.id,
          type: "dependency",
        });
      }
    }
  }

  return edges;
}

function hasPathOverlap(paths1: string[], paths2: string[]): boolean {
  for (const p1 of paths1) {
    for (const p2 of paths2) {
      if (p1 === p2 || p1.startsWith(p2) || p2.startsWith(p1)) {
        return true;
      }
    }
  }
  return false;
}

/**
 * 基于拓扑排序检测环
 */
function hasCycle(tasks: TaskNode[], edges: TaskEdge[]): boolean {
  const inDegree = new Map<string, number>();
  const adj = new Map<string, string[]>();

  for (const t of tasks) {
    inDegree.set(t.id, 0);
    adj.set(t.id, []);
  }

  for (const e of edges) {
    inDegree.set(e.to, (inDegree.get(e.to) || 0) + 1);
    adj.get(e.from)?.push(e.to);
  }

  const queue: string[] = [];
  for (const [id, deg] of inDegree) {
    if (deg === 0) queue.push(id);
  }

  let visited = 0;
  while (queue.length > 0) {
    const node = queue.shift()!;
    visited++;
    for (const neighbor of adj.get(node) || []) {
      const newDeg = (inDegree.get(neighbor) || 1) - 1;
      inDegree.set(neighbor, newDeg);
      if (newDeg === 0) queue.push(neighbor);
    }
  }

  return visited !== tasks.length;
}

/**
 * 环检测失败时回退为串行链
 */
function buildSerialChain(
  tasks: TaskNode[],
  analysis: IntentAnalysis
): TaskGraph {
  const edges: TaskEdge[] = [];

  for (let i = 1; i < tasks.length; i++) {
    tasks[i].dependencies = [tasks[i - 1].id];
    edges.push({
      from: tasks[i - 1].id,
      to: tasks[i].id,
      type: "dependency",
    });
  }

  const criticalPath = tasks.map((t) => t.id);

  return {
    graph_id: generateGraphId(),
    tasks,
    edges,
    critical_path: criticalPath,
    metadata: {
      created_at: new Date().toISOString(),
      original_intent: analysis.raw_input,
      total_tasks: tasks.length,
      max_parallelism: 1,
      critical_path_length: tasks.length,
      estimated_total_tokens: tasks.reduce(
        (sum, t) => sum + t.complexity.dimensions.estimated_tokens,
        0
      ),
    },
  };
}

/**
 * 计算关键路径（最长路径）
 */
function computeCriticalPath(
  tasks: TaskNode[],
  edges: TaskEdge[]
): string[] {
  const adj = new Map<string, string[]>();
  const inDegree = new Map<string, number>();

  for (const t of tasks) {
    adj.set(t.id, []);
    inDegree.set(t.id, 0);
  }

  for (const e of edges) {
    adj.get(e.from)?.push(e.to);
    inDegree.set(e.to, (inDegree.get(e.to) || 0) + 1);
  }

  // 拓扑排序
  const topoOrder: string[] = [];
  const queue: string[] = [];
  for (const [id, deg] of inDegree) {
    if (deg === 0) queue.push(id);
  }

  while (queue.length > 0) {
    const node = queue.shift()!;
    topoOrder.push(node);
    for (const neighbor of adj.get(node) || []) {
      const newDeg = (inDegree.get(neighbor) || 1) - 1;
      inDegree.set(neighbor, newDeg);
      if (newDeg === 0) queue.push(neighbor);
    }
  }

  // 按拓扑序计算最长路径
  const dist = new Map<string, number>();
  const prev = new Map<string, string | null>();

  for (const id of topoOrder) {
    dist.set(id, 0);
    prev.set(id, null);
  }

  for (const node of topoOrder) {
    for (const neighbor of adj.get(node) || []) {
      const newDist = (dist.get(node) || 0) + 1;
      if (newDist > (dist.get(neighbor) || 0)) {
        dist.set(neighbor, newDist);
        prev.set(neighbor, node);
      }
    }
  }

  // 找到最远节点
  let maxDist = 0;
  let endNode = topoOrder[0];
  for (const [id, d] of dist) {
    if (d > maxDist) {
      maxDist = d;
      endNode = id;
    }
  }

  // 回溯路径
  const path: string[] = [];
  let current: string | null | undefined = endNode;
  while (current) {
    path.unshift(current);
    current = prev.get(current);
  }

  return path;
}

function computeMaxParallelism(
  tasks: TaskNode[],
  edges: TaskEdge[]
): number {
  if (tasks.length <= 1) return 1;

  const inDegree = new Map<string, number>();
  const adj = new Map<string, string[]>();

  for (const t of tasks) {
    inDegree.set(t.id, 0);
    adj.set(t.id, []);
  }

  for (const e of edges) {
    inDegree.set(e.to, (inDegree.get(e.to) || 0) + 1);
    adj.get(e.from)?.push(e.to);
  }

  // BFS 层级宽度最大值
  let maxWidth = 0;
  const queue: string[] = [];
  for (const [id, deg] of inDegree) {
    if (deg === 0) queue.push(id);
  }
  maxWidth = Math.max(maxWidth, queue.length);

  while (queue.length > 0) {
    const nextLevel: string[] = [];
    for (const node of queue) {
      for (const neighbor of adj.get(node) || []) {
        const newDeg = (inDegree.get(neighbor) || 1) - 1;
        inDegree.set(neighbor, newDeg);
        if (newDeg === 0) nextLevel.push(neighbor);
      }
    }
    if (nextLevel.length > 0) {
      maxWidth = Math.max(maxWidth, nextLevel.length);
    }
    queue.length = 0;
    queue.push(...nextLevel);
  }

  return maxWidth;
}

function selectModelTier(complexity: ComplexityScore): ModelTier {
  if (complexity.level === "trivial" || complexity.level === "low")
    return "tier-1";
  if (complexity.level === "medium" || complexity.level === "high")
    return "tier-2";
  return "tier-3";
}

function generateGraphId(): string {
  return `graph-${Date.now()}-${Math.random().toString(36).substring(2, 8)}`;
}
