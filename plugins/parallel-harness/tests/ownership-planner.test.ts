/**
 * 所有权规划器测试
 *
 * 覆盖 planOwnership 和 detectConflicts 的路径所有权分配、
 * 冲突检测和序列化解决逻辑。
 */

import { describe, it, expect } from 'bun:test';
import {
  planOwnership,
  detectConflicts,
} from '../runtime/orchestrator/ownership-planner';
import { createTaskNode } from '../runtime/schemas/task-graph';

describe('OwnershipPlanner', () => {
  it('为任务分配不重叠的路径', () => {
    const tasks = [
      createTaskNode({
        id: 'task-a',
        allowed_paths: ['src/api/auth.ts', 'src/api/user.ts'],
      }),
      createTaskNode({
        id: 'task-b',
        allowed_paths: ['src/db/models.ts', 'src/db/queries.ts'],
      }),
    ];

    const mappings = planOwnership(tasks);

    expect(mappings.length).toBe(2);

    const mappingA = mappings.find(m => m.task_id === 'task-a')!;
    const mappingB = mappings.find(m => m.task_id === 'task-b')!;

    // 无冲突时，各自保留自己的路径
    expect(mappingA.allowed_paths).toEqual(['src/api/auth.ts', 'src/api/user.ts']);
    expect(mappingB.allowed_paths).toEqual(['src/db/models.ts', 'src/db/queries.ts']);

    // 无冲突路径进入 forbidden_paths
    const allAForbidden = mappingA.forbidden_paths;
    const allBForbidden = mappingB.forbidden_paths;
    // 互不包含对方的路径
    for (const p of mappingA.allowed_paths) {
      expect(allBForbidden).not.toContain(p);
    }
    for (const p of mappingB.allowed_paths) {
      expect(allAForbidden).not.toContain(p);
    }
  });

  it('检测文件冲突', () => {
    const tasks = [
      createTaskNode({
        id: 'task-a',
        allowed_paths: ['shared.ts', 'a-only.ts'],
      }),
      createTaskNode({
        id: 'task-b',
        allowed_paths: ['shared.ts', 'b-only.ts'],
      }),
    ];

    const conflicts = detectConflicts(tasks);

    // 应该检测到 shared.ts 上的冲突
    expect(conflicts.length).toBe(1);
    expect(conflicts[0].path).toBe('shared.ts');
    expect(conflicts[0].tasks).toContain('task-a');
    expect(conflicts[0].tasks).toContain('task-b');
    expect(conflicts[0].resolution).toBe('serialize');
  });

  it('通过序列化解决冲突', () => {
    const tasks = [
      createTaskNode({
        id: 'task-a',
        allowed_paths: ['shared.ts', 'a-only.ts'],
      }),
      createTaskNode({
        id: 'task-b',
        allowed_paths: ['shared.ts', 'b-only.ts'],
      }),
    ];

    const mappings = planOwnership(tasks);

    const mappingA = mappings.find(m => m.task_id === 'task-a')!;
    const mappingB = mappings.find(m => m.task_id === 'task-b')!;

    // 第一个任务（task-a）获得 shared.ts 的所有权
    expect(mappingA.allowed_paths).toContain('shared.ts');
    // 第二个任务（task-b）失去 shared.ts 的所有权
    expect(mappingB.allowed_paths).not.toContain('shared.ts');
    // shared.ts 进入 task-b 的 forbidden_paths
    expect(mappingB.forbidden_paths).toContain('shared.ts');

    // 各自独占的路径不受影响
    expect(mappingA.allowed_paths).toContain('a-only.ts');
    expect(mappingB.allowed_paths).toContain('b-only.ts');
  });

  it('planOwnership 返回完整映射', () => {
    const tasks = [
      createTaskNode({
        id: 't1',
        allowed_paths: ['src/a.ts'],
        assigned_role: 'worker',
      }),
      createTaskNode({
        id: 't2',
        allowed_paths: ['src/b.ts'],
      }),
      createTaskNode({
        id: 't3',
        allowed_paths: ['src/c.ts'],
      }),
    ];

    const mappings = planOwnership(tasks);

    // 每个任务都有映射
    expect(mappings.length).toBe(3);
    const ids = mappings.map(m => m.task_id);
    expect(ids).toContain('t1');
    expect(ids).toContain('t2');
    expect(ids).toContain('t3');

    // 每个映射包含 role
    for (const m of mappings) {
      expect(typeof m.role).toBe('string');
      expect(m.role.length).toBeGreaterThan(0);
    }

    // t1 使用显式角色
    const m1 = mappings.find(m => m.task_id === 't1')!;
    expect(m1.role).toBe('worker');
  });

  it('forbidden_paths 正确设置', () => {
    // 三个任务共享一个路径
    const tasks = [
      createTaskNode({
        id: 'task-1',
        allowed_paths: ['shared.ts'],
        forbidden_paths: ['secret.ts'],
      }),
      createTaskNode({
        id: 'task-2',
        allowed_paths: ['shared.ts'],
        forbidden_paths: [],
      }),
      createTaskNode({
        id: 'task-3',
        allowed_paths: ['shared.ts'],
        forbidden_paths: ['config.ts'],
      }),
    ];

    const mappings = planOwnership(tasks);

    // task-1 是第一个拥有者，保留 shared.ts
    const m1 = mappings.find(m => m.task_id === 'task-1')!;
    expect(m1.allowed_paths).toContain('shared.ts');
    // 保留原有的 forbidden_paths
    expect(m1.forbidden_paths).toContain('secret.ts');

    // task-2 和 task-3 丧失 shared.ts
    const m2 = mappings.find(m => m.task_id === 'task-2')!;
    const m3 = mappings.find(m => m.task_id === 'task-3')!;
    expect(m2.forbidden_paths).toContain('shared.ts');
    expect(m3.forbidden_paths).toContain('shared.ts');
    // task-3 保留原有 forbidden_paths
    expect(m3.forbidden_paths).toContain('config.ts');
  });
});
