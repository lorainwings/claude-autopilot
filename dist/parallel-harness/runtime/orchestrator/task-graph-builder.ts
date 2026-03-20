/**
 * 任务图构建器
 *
 * 根据意图分析结果构建任务图，包含拆分策略和依赖推断
 */

import type { IntentAnalysis } from '../schemas/types.js';
import type { TaskNode, TaskGraph } from '../schemas/task-graph.js';
import { createTaskNode, createTaskGraph } from '../schemas/task-graph.js';

/**
 * 根据意图分析结果构建任务图
 */
export function buildTaskGraph(analysis: IntentAnalysis): TaskGraph {
  const nodes = splitTasks(analysis);
  const withDeps = inferDependencies(nodes, analysis);

  return createTaskGraph({
    id: `graph-${Date.now()}`,
    intent: analysis.description,
    nodes: withDeps,
    status: 'pending',
  });
}

/** 根据拆分策略生成任务节点 */
function splitTasks(analysis: IntentAnalysis): TaskNode[] {
  switch (analysis.split_strategy) {
    case 'file-based':
      return fileBased(analysis);
    case 'layer-based':
      return layerBased(analysis);
    case 'feature-based':
      return featureBased(analysis);
    default:
      return [createTaskNode({
        id: 'task-1',
        title: analysis.description,
        goal: analysis.description,
        model_tier: analysis.recommended_model_tier,
      })];
  }
}

/** 基于文件的拆分：每个文件一个任务 */
function fileBased(analysis: IntentAnalysis): TaskNode[] {
  if (analysis.scope.length === 0) {
    return [createTaskNode({
      id: 'task-1',
      title: `${analysis.type}: ${analysis.description}`,
      goal: analysis.description,
      allowed_paths: [],
      model_tier: analysis.recommended_model_tier,
    })];
  }

  return analysis.scope.map((file, i) => createTaskNode({
    id: `task-${i + 1}`,
    title: `${analysis.type}: ${file}`,
    goal: `处理文件 ${file}`,
    allowed_paths: [file],
    model_tier: analysis.recommended_model_tier,
  }));
}

/** 基于层级的拆分：按目录层级分组 */
function layerBased(analysis: IntentAnalysis): TaskNode[] {
  const layers = new Map<string, string[]>();

  for (const file of analysis.scope) {
    const dir = file.split('/')[0] || 'root';
    if (!layers.has(dir)) layers.set(dir, []);
    layers.get(dir)!.push(file);
  }

  const nodes: TaskNode[] = [];
  let idx = 1;
  for (const [layer, files] of layers) {
    nodes.push(createTaskNode({
      id: `task-${idx}`,
      title: `${analysis.type}: ${layer} 层`,
      goal: `处理 ${layer} 层的文件: ${files.join(', ')}`,
      allowed_paths: files,
      model_tier: analysis.recommended_model_tier,
    }));
    idx++;
  }

  return nodes;
}

/** 基于功能的拆分 */
function featureBased(analysis: IntentAnalysis): TaskNode[] {
  // 默认生成设计 + 实现 + 测试三个阶段
  return [
    createTaskNode({
      id: 'task-design',
      title: '架构设计',
      goal: `为 "${analysis.description}" 制定架构方案`,
      model_tier: 'tier-3',
      risk_level: 'medium',
    }),
    createTaskNode({
      id: 'task-impl',
      title: '功能实现',
      goal: `实现 "${analysis.description}"`,
      model_tier: analysis.recommended_model_tier,
      allowed_paths: analysis.scope,
    }),
    createTaskNode({
      id: 'task-test',
      title: '测试编写',
      goal: `为 "${analysis.description}" 编写测试`,
      model_tier: 'tier-1',
      allowed_paths: analysis.scope.map(p => p.replace(/^src\//, 'tests/')),
    }),
  ];
}

/** 推断任务间的依赖关系 */
function inferDependencies(nodes: TaskNode[], analysis: IntentAnalysis): TaskNode[] {
  if (nodes.length <= 1) return nodes;

  // 对 layer-based：后续层依赖前层
  if (analysis.split_strategy === 'layer-based') {
    return nodes.map((node, i) => ({
      ...node,
      dependencies: i > 0 ? [nodes[i - 1].id] : [],
    }));
  }

  // 对 feature-based：impl 依赖 design，test 依赖 impl
  if (analysis.split_strategy === 'feature-based') {
    const idMap = new Map(nodes.map(n => [n.id, n]));
    if (idMap.has('task-impl')) {
      nodes.find(n => n.id === 'task-impl')!.dependencies = ['task-design'];
    }
    if (idMap.has('task-test')) {
      nodes.find(n => n.id === 'task-test')!.dependencies = ['task-impl'];
    }
    return nodes;
  }

  // 对 file-based：默认无依赖（并行）
  return nodes;
}
