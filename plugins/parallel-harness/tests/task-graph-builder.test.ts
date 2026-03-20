/**
 * 任务图构建器 + 意图分析器测试
 *
 * 覆盖 analyzeIntent 意图识别和 buildTaskGraph 图构建、
 * 拆分策略、依赖推断等核心逻辑。
 */

import { describe, it, expect } from 'bun:test';
import { analyzeIntent } from '../runtime/orchestrator/intent-analyzer';
import { buildTaskGraph } from '../runtime/orchestrator/task-graph-builder';
import { validateTaskGraph } from '../runtime/schemas/task-graph';
import {
  scoreComplexity,
  recommendModelTier,
  scoreTaskGraph,
} from '../runtime/orchestrator/complexity-scorer';
import { createTaskNode } from '../runtime/schemas/task-graph';

// ─────────────────────────────────────────────────────────────
// IntentAnalyzer
// ─────────────────────────────────────────────────────────────

describe('IntentAnalyzer', () => {
  it('识别 feature 类型意图', () => {
    const result = analyzeIntent('添加用户登录功能，创建 auth 模块');
    expect(result.type).toBe('feature');
  });

  it('识别 bugfix 类型意图', () => {
    const result = analyzeIntent('修复登录页面的 bug，resolve 500 error');
    expect(result.type).toBe('bugfix');
  });

  it('识别 refactor 类型意图', () => {
    const result = analyzeIntent('重构数据库层，优化查询性能 refactor');
    expect(result.type).toBe('refactor');
  });

  it('提取文件路径作为 scope', () => {
    const result = analyzeIntent('修改 src/auth/login.ts 和 src/utils/crypto.ts');
    expect(result.scope).toContain('src/auth/login.ts');
    expect(result.scope).toContain('src/utils/crypto.ts');
    expect(result.scope.length).toBe(2);
  });

  it('根据复杂度推荐 model_tier', () => {
    // 低复杂度 → tier-1
    const low = analyzeIntent('fix a typo');
    expect(low.complexity).toBe('low');
    expect(low.recommended_model_tier).toBe('tier-1');

    // 高复杂度（包含"架构"关键词）→ tier-3
    const high = analyzeIntent('全面重构架构，迁移到新的数据层');
    expect(high.complexity).toBe('high');
    expect(high.recommended_model_tier).toBe('tier-3');
  });
});

// ─────────────────────────────────────────────────────────────
// TaskGraphBuilder
// ─────────────────────────────────────────────────────────────

describe('TaskGraphBuilder', () => {
  it('从意图分析构建任务图', () => {
    const analysis = analyzeIntent('修复 src/api/handler.ts 中的 bug');
    const graph = buildTaskGraph(analysis);

    expect(graph.id).toMatch(/^graph-/);
    expect(graph.intent).toBeTruthy();
    expect(graph.nodes.length).toBeGreaterThan(0);
    expect(graph.status).toBe('pending');
  });

  it('file-based 拆分策略', () => {
    // 同一目录下的多个文件 → file-based 策略
    const analysis = analyzeIntent('修复 src/a.ts 和 src/b.ts 中的 bug');
    expect(analysis.split_strategy).toBe('file-based');

    const graph = buildTaskGraph(analysis);
    // 每个文件对应一个任务节点
    expect(graph.nodes.length).toBe(2);
    // file-based 策略下，任务间默认无依赖（可并行执行）
    for (const node of graph.nodes) {
      expect(node.dependencies).toEqual([]);
    }
  });

  it('layer-based 拆分策略', () => {
    // 不同目录层级的文件 → layer-based 策略
    const analysis = analyzeIntent('修复 src/api.ts 和 lib/utils.ts 的问题');
    expect(analysis.split_strategy).toBe('layer-based');

    const graph = buildTaskGraph(analysis);
    // 按目录层级分组，至少 2 个节点（src 层 + lib 层）
    expect(graph.nodes.length).toBeGreaterThanOrEqual(2);
    // layer-based 策略下，后续层依赖前一层
    for (let i = 1; i < graph.nodes.length; i++) {
      expect(graph.nodes[i].dependencies).toContain(graph.nodes[i - 1].id);
    }
  });

  it('生成的图通过验证', () => {
    const analysis = analyzeIntent('添加新功能 create src/feature.ts');
    const graph = buildTaskGraph(analysis);

    const validation = validateTaskGraph(graph);
    expect(validation.valid).toBe(true);
    expect(validation.errors).toEqual([]);
  });

  it('依赖推断正确', () => {
    // feature-based 拆分策略下的依赖关系
    const analysis = analyzeIntent('全面重构架构');
    expect(analysis.split_strategy).toBe('feature-based');

    const graph = buildTaskGraph(analysis);
    // feature-based 生成 design → impl → test 三阶段
    const designNode = graph.nodes.find(n => n.id === 'task-design');
    const implNode = graph.nodes.find(n => n.id === 'task-impl');
    const testNode = graph.nodes.find(n => n.id === 'task-test');

    expect(designNode).toBeDefined();
    expect(implNode).toBeDefined();
    expect(testNode).toBeDefined();

    // impl 依赖 design
    expect(implNode!.dependencies).toContain('task-design');
    // test 依赖 impl
    expect(testNode!.dependencies).toContain('task-impl');
    // design 无依赖
    expect(designNode!.dependencies).toEqual([]);
  });
});
