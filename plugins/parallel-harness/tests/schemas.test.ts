/**
 * schemas 模块测试
 *
 * 覆盖 TaskNode、TaskGraph、ContextPack、VerifierResult
 * 的工厂函数、验证函数和角色合同定义。
 */

import { describe, it, expect } from 'bun:test';
import {
  createTaskNode,
  createTaskGraph,
  validateTaskGraph,
  getReadyTasks,
} from '../runtime/schemas/task-graph';
import {
  createContextPack,
  validateContextPack,
} from '../runtime/schemas/context-pack';
import {
  createVerifierResult,
  isPassingResult,
} from '../runtime/schemas/verifier-result';
import {
  PLANNER_CONTRACT,
  WORKER_CONTRACT,
  VERIFIER_CONTRACT,
  SYNTHESIZER_CONTRACT,
} from '../runtime/schemas/role-contracts';
import type { RoleType } from '../runtime/schemas/types';

// ─────────────────────────────────────────────────────────────
// TaskNode schema
// ─────────────────────────────────────────────────────────────

describe('TaskNode schema', () => {
  it('createTaskNode 使用默认值', () => {
    const node = createTaskNode();

    // 默认 id 以 task- 开头
    expect(node.id).toMatch(/^task-/);
    expect(node.title).toBe('未命名任务');
    expect(node.goal).toBe('');
    expect(node.dependencies).toEqual([]);
    expect(node.risk_level).toBe('low');
    expect(node.allowed_paths).toEqual([]);
    expect(node.forbidden_paths).toEqual([]);
    expect(node.acceptance_criteria).toEqual([]);
    expect(node.required_tests).toEqual([]);
    // 默认 model_tier 为 tier-2（通用模型）
    expect(node.model_tier).toBe('tier-2');
    expect(node.verifier_set).toEqual(['test', 'review']);
    expect(node.status).toBe('pending');
  });

  it('createTaskNode 覆盖指定字段', () => {
    const node = createTaskNode({
      id: 'custom-1',
      title: '实现登录模块',
      risk_level: 'high',
      model_tier: 'tier-3',
      status: 'ready',
      allowed_paths: ['src/auth/**'],
      complexity_score: 75,
    });

    expect(node.id).toBe('custom-1');
    expect(node.title).toBe('实现登录模块');
    expect(node.risk_level).toBe('high');
    expect(node.model_tier).toBe('tier-3');
    expect(node.status).toBe('ready');
    expect(node.allowed_paths).toEqual(['src/auth/**']);
    expect(node.complexity_score).toBe(75);
    // 未覆盖的字段保持默认
    expect(node.goal).toBe('');
    expect(node.dependencies).toEqual([]);
  });

  it('所有必填字段都有值', () => {
    const node = createTaskNode();
    const requiredKeys: (keyof typeof node)[] = [
      'id', 'title', 'goal', 'dependencies', 'risk_level',
      'allowed_paths', 'forbidden_paths', 'acceptance_criteria',
      'required_tests', 'model_tier', 'verifier_set', 'status',
    ];

    for (const key of requiredKeys) {
      expect(node[key]).toBeDefined();
    }
  });
});

// ─────────────────────────────────────────────────────────────
// TaskGraph schema
// ─────────────────────────────────────────────────────────────

describe('TaskGraph schema', () => {
  it('createTaskGraph 使用默认值', () => {
    const graph = createTaskGraph();

    expect(graph.id).toMatch(/^graph-/);
    expect(graph.intent).toBe('');
    expect(graph.nodes).toEqual([]);
    expect(graph.status).toBe('pending');
    // 时间戳为合法 ISO 8601
    expect(new Date(graph.created_at).toISOString()).toBe(graph.created_at);
    expect(new Date(graph.updated_at).toISOString()).toBe(graph.updated_at);
  });

  it('validateTaskGraph 检测循环依赖', () => {
    const graph = createTaskGraph({
      nodes: [
        createTaskNode({ id: 'a', dependencies: ['b'] }),
        createTaskNode({ id: 'b', dependencies: ['c'] }),
        createTaskNode({ id: 'c', dependencies: ['a'] }),
      ],
    });

    const result = validateTaskGraph(graph);
    expect(result.valid).toBe(false);
    // 至少有一条循环依赖的错误信息
    expect(result.errors.some(e => e.includes('循环依赖'))).toBe(true);
  });

  it('validateTaskGraph 检测无效引用', () => {
    const graph = createTaskGraph({
      nodes: [
        createTaskNode({ id: 'a', dependencies: ['nonexistent'] }),
        createTaskNode({ id: 'b', dependencies: [] }),
      ],
    });

    const result = validateTaskGraph(graph);
    expect(result.valid).toBe(false);
    expect(result.errors.some(e => e.includes('nonexistent'))).toBe(true);
  });

  it('validateTaskGraph 对有效图返回 valid', () => {
    const graph = createTaskGraph({
      nodes: [
        createTaskNode({ id: 'a', dependencies: [] }),
        createTaskNode({ id: 'b', dependencies: ['a'] }),
        createTaskNode({ id: 'c', dependencies: ['a'] }),
      ],
    });

    const result = validateTaskGraph(graph);
    expect(result.valid).toBe(true);
    expect(result.errors).toEqual([]);
  });

  it('getReadyTasks 返回依赖已完成的任务', () => {
    const graph = createTaskGraph({
      nodes: [
        createTaskNode({ id: 'a', dependencies: [], status: 'completed' }),
        createTaskNode({ id: 'b', dependencies: ['a'], status: 'pending' }),
        createTaskNode({ id: 'c', dependencies: ['a', 'b'], status: 'pending' }),
      ],
    });

    const ready = getReadyTasks(graph);
    // a 已完成，b 的依赖 a 已完成 → b 就绪
    // c 依赖 a 和 b，b 未完成 → c 不就绪
    expect(ready.map(n => n.id)).toEqual(['b']);
  });

  it('getReadyTasks 排除已完成和失败的任务', () => {
    const graph = createTaskGraph({
      nodes: [
        createTaskNode({ id: 'a', dependencies: [], status: 'completed' }),
        createTaskNode({ id: 'b', dependencies: [], status: 'failed' }),
        createTaskNode({ id: 'c', dependencies: [], status: 'pending' }),
        createTaskNode({ id: 'd', dependencies: [], status: 'in_progress' }),
      ],
    });

    const ready = getReadyTasks(graph);
    // 只有 pending 且无未完成依赖的才算就绪
    const readyIds = ready.map(n => n.id);
    expect(readyIds).toContain('c');
    expect(readyIds).not.toContain('a'); // 已完成
    expect(readyIds).not.toContain('b'); // 已失败
    expect(readyIds).not.toContain('d'); // 进行中
  });
});

// ─────────────────────────────────────────────────────────────
// ContextPack schema
// ─────────────────────────────────────────────────────────────

describe('ContextPack schema', () => {
  it('createContextPack 使用默认值', () => {
    const pack = createContextPack();

    expect(pack.task_id).toBe('');
    expect(pack.files).toEqual([]);
    expect(pack.references).toEqual([]);
    // 默认约束已配置
    expect(pack.constraints.max_files).toBeGreaterThan(0);
    expect(pack.constraints.max_tokens).toBeGreaterThan(0);
    expect(pack.constraints.allowed_paths.length).toBeGreaterThan(0);
  });

  it('validateContextPack 检测无效数据', () => {
    // task_id 为空
    const pack1 = createContextPack({ task_id: '' });
    const r1 = validateContextPack(pack1);
    expect(r1.valid).toBe(false);
    expect(r1.errors.some(e => e.includes('task_id'))).toBe(true);

    // relevance 超出范围
    const pack2 = createContextPack({
      task_id: 'task-1',
      files: [{ path: 'foo.ts', relevance: 1.5 }],
    });
    const r2 = validateContextPack(pack2);
    expect(r2.valid).toBe(false);
    expect(r2.errors.some(e => e.includes('relevance'))).toBe(true);

    // 文件路径为空
    const pack3 = createContextPack({
      task_id: 'task-1',
      files: [{ path: '', relevance: 0.5 }],
    });
    const r3 = validateContextPack(pack3);
    expect(r3.valid).toBe(false);
    expect(r3.errors.some(e => e.includes('路径'))).toBe(true);
  });
});

// ─────────────────────────────────────────────────────────────
// VerifierResult schema
// ─────────────────────────────────────────────────────────────

describe('VerifierResult schema', () => {
  it('createVerifierResult 使用默认值', () => {
    const result = createVerifierResult();

    expect(result.verifier_type).toBe('test');
    expect(result.task_id).toBe('');
    expect(result.status).toBe('skip');
    expect(result.score).toBe(0);
    expect(result.findings).toEqual([]);
    // timestamp 为合法 ISO 8601
    expect(new Date(result.timestamp).toISOString()).toBe(result.timestamp);
  });

  it('isPassingResult 判断通过/失败', () => {
    // 通过：status=pass 且 score>=60
    const passing = createVerifierResult({ status: 'pass', score: 80 });
    expect(isPassingResult(passing)).toBe(true);

    // 通过：status=warn 且 score>=60（警告不阻断）
    const warning = createVerifierResult({ status: 'warn', score: 65 });
    expect(isPassingResult(warning)).toBe(true);

    // 失败：status=fail
    const failing = createVerifierResult({ status: 'fail', score: 90 });
    expect(isPassingResult(failing)).toBe(false);

    // 失败：score < 60
    const lowScore = createVerifierResult({ status: 'pass', score: 50 });
    expect(isPassingResult(lowScore)).toBe(false);

    // 失败：status=skip
    const skipped = createVerifierResult({ status: 'skip', score: 100 });
    expect(isPassingResult(skipped)).toBe(false);
  });
});

// ─────────────────────────────────────────────────────────────
// Role contracts
// ─────────────────────────────────────────────────────────────

describe('Role contracts', () => {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const allContracts: { name: RoleType; contract: { role: RoleType; input_schema: any; output_schema: any; failure_semantics: any; resource_boundary: any } }[] = [
    { name: 'planner', contract: PLANNER_CONTRACT },
    { name: 'worker', contract: WORKER_CONTRACT },
    { name: 'verifier', contract: VERIFIER_CONTRACT },
    { name: 'synthesizer', contract: SYNTHESIZER_CONTRACT },
  ];

  it('四个角色合同均已定义', () => {
    expect(PLANNER_CONTRACT).toBeDefined();
    expect(WORKER_CONTRACT).toBeDefined();
    expect(VERIFIER_CONTRACT).toBeDefined();
    expect(SYNTHESIZER_CONTRACT).toBeDefined();
  });

  it('每个合同包含必要字段', () => {
    for (const { name, contract } of allContracts) {
      // 角色类型
      expect(contract.role).toBe(name);
      // 输入/输出 schema 描述
      expect(typeof contract.input_schema).toBe('string');
      expect(contract.input_schema.length).toBeGreaterThan(0);
      expect(typeof contract.output_schema).toBe('string');
      expect(contract.output_schema.length).toBeGreaterThan(0);
      // 失败语义
      expect(contract.failure_semantics).toBeDefined();
      expect(typeof contract.failure_semantics.retry_allowed).toBe('boolean');
      expect(typeof contract.failure_semantics.max_retries).toBe('number');
      expect(['skip', 'escalate', 'abort']).toContain(
        contract.failure_semantics.fallback_action,
      );
      // 资源边界
      expect(contract.resource_boundary).toBeDefined();
      expect(Array.isArray(contract.resource_boundary.allowed_paths)).toBe(true);
      expect(Array.isArray(contract.resource_boundary.forbidden_paths)).toBe(true);
      expect(contract.resource_boundary.max_tokens).toBeGreaterThan(0);
      expect(Array.isArray(contract.resource_boundary.allowed_tools)).toBe(true);
      expect(contract.resource_boundary.allowed_tools.length).toBeGreaterThan(0);
    }
  });
});
