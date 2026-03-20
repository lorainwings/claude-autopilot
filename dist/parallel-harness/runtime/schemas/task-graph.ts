/**
 * 任务图 schema
 *
 * 定义任务节点（TaskNode）和任务图（TaskGraph）的数据结构，
 * 以及用于创建、验证和查询任务图的工具函数。
 * 任务图本质上是一个有向无环图（DAG），节点间通过依赖关系连接。
 */

import type {
  ModelTier,
  RiskLevel,
  TaskStatus,
  RoleType,
  VerifierType,
} from './types.js';

// ─── 任务节点 ───────────────────────────────────────────

/** 任务节点：DAG 中的一个可执行单元 */
export interface TaskNode {
  /** 节点唯一标识 */
  id: string;
  /** 任务标题（简短描述） */
  title: string;
  /** 任务目标（详细说明期望完成的工作） */
  goal: string;
  /** 依赖的前置任务 id 列表 */
  dependencies: string[];
  /** 风险级别，决定验证强度 */
  risk_level: RiskLevel;
  /** 允许访问的文件路径 glob 模式 */
  allowed_paths: string[];
  /** 禁止访问的文件路径 glob 模式 */
  forbidden_paths: string[];
  /** 验收标准列表（人类可读） */
  acceptance_criteria: string[];
  /** 必须通过的测试用例路径或名称 */
  required_tests: string[];
  /** 推荐使用的模型层级 */
  model_tier: ModelTier;
  /** 需要运行的验证器集合 */
  verifier_set: VerifierType[];
  /** 当前任务状态 */
  status: TaskStatus;
  /** 被分配的角色类型（可选） */
  assigned_role?: RoleType;
  /** 复杂度评分 0-100（可选） */
  complexity_score?: number;
  /** 任意扩展元数据（可选） */
  metadata?: Record<string, unknown>;
}

// ─── 任务图 ─────────────────────────────────────────────

/** 任务图：由多个 TaskNode 组成的有向无环图 */
export interface TaskGraph {
  /** 图唯一标识 */
  id: string;
  /** 用户原始意图描述 */
  intent: string;
  /** 任务节点列表 */
  nodes: TaskNode[];
  /** 创建时间（ISO 8601 格式） */
  created_at: string;
  /** 最后更新时间（ISO 8601 格式） */
  updated_at: string;
  /** 整图状态 */
  status: 'pending' | 'in_progress' | 'completed' | 'failed';
}

// ─── 工厂函数 ───────────────────────────────────────────

/**
 * 创建 TaskNode，未指定字段使用合理默认值。
 * @param partial - 部分 TaskNode 字段覆盖
 */
export function createTaskNode(partial: Partial<TaskNode> = {}): TaskNode {
  return {
    id: partial.id ?? `task-${Date.now()}`,
    title: partial.title ?? '未命名任务',
    goal: partial.goal ?? '',
    dependencies: partial.dependencies ?? [],
    risk_level: partial.risk_level ?? 'low',
    allowed_paths: partial.allowed_paths ?? [],
    forbidden_paths: partial.forbidden_paths ?? [],
    acceptance_criteria: partial.acceptance_criteria ?? [],
    required_tests: partial.required_tests ?? [],
    model_tier: partial.model_tier ?? 'tier-2',
    verifier_set: partial.verifier_set ?? ['test', 'review'],
    status: partial.status ?? 'pending',
    assigned_role: partial.assigned_role,
    complexity_score: partial.complexity_score,
    metadata: partial.metadata,
  };
}

/**
 * 创建 TaskGraph，未指定字段使用合理默认值。
 * @param partial - 部分 TaskGraph 字段覆盖
 */
export function createTaskGraph(partial: Partial<TaskGraph> = {}): TaskGraph {
  const now = new Date().toISOString();
  return {
    id: partial.id ?? `graph-${Date.now()}`,
    intent: partial.intent ?? '',
    nodes: partial.nodes ?? [],
    created_at: partial.created_at ?? now,
    updated_at: partial.updated_at ?? now,
    status: partial.status ?? 'pending',
  };
}

// ─── 验证函数 ───────────────────────────────────────────

/** 验证结果 */
export interface ValidationResult {
  /** 是否合法 */
  valid: boolean;
  /** 错误信息列表 */
  errors: string[];
}

/**
 * 验证 TaskGraph 的结构完整性。
 * 检查内容：
 * - 节点 id 唯一性
 * - 依赖引用完整性（所有 dependency 都指向图内已有节点）
 * - 循环依赖检测（DFS 回边检测）
 * - 空图检查
 */
export function validateTaskGraph(graph: TaskGraph): ValidationResult {
  const errors: string[] = [];

  // 空图检查
  if (graph.nodes.length === 0) {
    errors.push('任务图不包含任何节点');
    return { valid: false, errors };
  }

  // 节点 id 唯一性检查
  const nodeIds = new Set<string>();
  for (const node of graph.nodes) {
    if (nodeIds.has(node.id)) {
      errors.push(`存在重复的节点 id: "${node.id}"`);
    }
    nodeIds.add(node.id);
  }

  // 依赖引用完整性检查：被依赖的节点必须存在于图中
  for (const node of graph.nodes) {
    for (const dep of node.dependencies) {
      if (!nodeIds.has(dep)) {
        errors.push(`节点 "${node.id}" 依赖了不存在的节点 "${dep}"`);
      }
    }
  }

  // 自引用检查
  for (const node of graph.nodes) {
    if (node.dependencies.includes(node.id)) {
      errors.push(`节点 "${node.id}" 依赖了自身`);
    }
  }

  // 循环依赖检测（DFS 灰白黑三色标记法）
  // 0 = 未访问(白), 1 = 正在访问(灰), 2 = 已完成(黑)
  const color = new Map<string, number>();
  for (const id of nodeIds) {
    color.set(id, 0);
  }

  /** 构建邻接表（节点 → 其依赖列表） */
  const adjList = new Map<string, string[]>();
  for (const node of graph.nodes) {
    adjList.set(node.id, node.dependencies.filter(d => nodeIds.has(d)));
  }

  /**
   * DFS 遍历，检测回边（灰 → 灰 = 循环）
   * @returns 是否在此次遍历中发现循环
   */
  function dfs(nodeId: string, path: string[]): boolean {
    color.set(nodeId, 1); // 标记为灰色（正在访问）
    const deps = adjList.get(nodeId) ?? [];
    for (const dep of deps) {
      if (color.get(dep) === 1) {
        // 发现回边，构造循环路径说明
        const cycleStart = path.indexOf(dep);
        const cyclePath = [...path.slice(cycleStart), dep].join(' → ');
        errors.push(`检测到循环依赖: ${cyclePath}`);
        return true;
      }
      if (color.get(dep) === 0) {
        if (dfs(dep, [...path, dep])) {
          return true;
        }
      }
    }
    color.set(nodeId, 2); // 标记为黑色（已完成）
    return false;
  }

  for (const node of graph.nodes) {
    if (color.get(node.id) === 0) {
      dfs(node.id, [node.id]);
    }
  }

  return { valid: errors.length === 0, errors };
}

// ─── 查询函数 ───────────────────────────────────────────

/**
 * 返回所有"就绪"的任务：
 * - 当前状态为 pending
 * - 所有依赖任务均已 completed
 */
export function getReadyTasks(graph: TaskGraph): TaskNode[] {
  const completedIds = new Set(
    graph.nodes
      .filter(n => n.status === 'completed')
      .map(n => n.id),
  );

  return graph.nodes.filter(node => {
    // 只考虑 pending 状态的任务
    if (node.status !== 'pending') return false;
    // 所有依赖都必须已完成
    return node.dependencies.every(dep => completedIds.has(dep));
  });
}

/**
 * 对任务图进行拓扑排序（Kahn 算法）。
 * 如果图中存在循环依赖，返回 null。
 * @returns 按拓扑顺序排列的 TaskNode 数组，或 null（存在循环）
 */
export function getTopologicalOrder(graph: TaskGraph): TaskNode[] | null {
  const nodeMap = new Map<string, TaskNode>();
  for (const node of graph.nodes) {
    nodeMap.set(node.id, node);
  }

  // 计算每个节点的入度（被多少个节点依赖于）
  const inDegree = new Map<string, number>();
  for (const node of graph.nodes) {
    inDegree.set(node.id, 0);
  }
  for (const node of graph.nodes) {
    for (const dep of node.dependencies) {
      // dep → node 是一条边，node 的入度不变，
      // 但在我们的模型里 dependencies 表示 "node 依赖 dep"，
      // 即 dep 必须先执行，所以边方向为 dep → node
      // 入度统计的是 "有多少前置"，即 dependencies.length
    }
    inDegree.set(node.id, node.dependencies.filter(d => nodeMap.has(d)).length);
  }

  // 初始化队列：入度为 0 的节点（无前置依赖）
  const queue: string[] = [];
  for (const [id, degree] of inDegree) {
    if (degree === 0) {
      queue.push(id);
    }
  }

  // 构建"谁依赖我"的反向邻接表
  const dependents = new Map<string, string[]>();
  for (const node of graph.nodes) {
    for (const dep of node.dependencies) {
      if (nodeMap.has(dep)) {
        const list = dependents.get(dep) ?? [];
        list.push(node.id);
        dependents.set(dep, list);
      }
    }
  }

  const sorted: TaskNode[] = [];

  while (queue.length > 0) {
    const current = queue.shift()!;
    const node = nodeMap.get(current);
    if (node) {
      sorted.push(node);
    }

    // 将当前节点从图中"移除"，更新所有后继节点的入度
    const deps = dependents.get(current) ?? [];
    for (const next of deps) {
      const newDegree = (inDegree.get(next) ?? 1) - 1;
      inDegree.set(next, newDegree);
      if (newDegree === 0) {
        queue.push(next);
      }
    }
  }

  // 如果排序结果不包含所有节点，说明存在循环
  if (sorted.length !== graph.nodes.length) {
    return null;
  }

  return sorted;
}
