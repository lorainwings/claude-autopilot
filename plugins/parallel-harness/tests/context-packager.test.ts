/**
 * 上下文打包器测试
 *
 * 覆盖 ContextPackager 的路径过滤、forbidden_paths 排除、
 * 相关度排序、token 截断和相关度评分逻辑。
 */

import { describe, it, expect } from 'bun:test';
import { ContextPackager } from '../runtime/session/context-packager';
import { createTaskNode } from '../runtime/schemas/task-graph';

describe('ContextPackager', () => {
  it('根据 allowed_paths 过滤文件', () => {
    const packager = new ContextPackager({ relevance_threshold: 0 });
    const node = createTaskNode({
      id: 'task-filter',
      title: '过滤测试',
      allowed_paths: ['src/api/'],
    });

    const files = [
      'src/api/auth.ts',
      'src/api/user.ts',
      'src/db/models.ts',
      'lib/utils.ts',
    ];

    const pack = packager.pack(node, files);

    // 只保留 src/api/ 下的文件
    const paths = pack.files.map(f => f.path);
    expect(paths).toContain('src/api/auth.ts');
    expect(paths).toContain('src/api/user.ts');
    expect(paths).not.toContain('src/db/models.ts');
    expect(paths).not.toContain('lib/utils.ts');
  });

  it('排除 forbidden_paths', () => {
    const packager = new ContextPackager({ relevance_threshold: 0 });
    const node = createTaskNode({
      id: 'task-forbidden',
      title: '排除测试',
      allowed_paths: [],  // 不限制允许路径
      forbidden_paths: ['node_modules/', '.git/'],
    });

    const files = [
      'src/index.ts',
      'node_modules/lodash/index.js',
      '.git/config',
      'tests/foo.test.ts',
    ];

    const pack = packager.pack(node, files);

    const paths = pack.files.map(f => f.path);
    expect(paths).not.toContain('node_modules/lodash/index.js');
    expect(paths).not.toContain('.git/config');
    // src 和 tests 下的文件保留
    expect(paths.some(p => p.startsWith('src/'))).toBe(true);
  });

  it('文件按相关度排序', () => {
    const packager = new ContextPackager({ relevance_threshold: 0 });
    const node = createTaskNode({
      id: 'task-sort',
      title: 'auth handler 修复',
      goal: '修复 auth handler 的 bug',
      allowed_paths: ['src/'],
    });

    const files = [
      'src/unrelated.ts',
      'src/auth/handler.ts',
      'src/utils/random.ts',
    ];

    const pack = packager.pack(node, files);

    // 文件应按相关度降序排列
    for (let i = 1; i < pack.files.length; i++) {
      expect(pack.files[i - 1].relevance).toBeGreaterThanOrEqual(
        pack.files[i].relevance,
      );
    }

    // auth/handler.ts 包含关键词 "auth" 和 "handler"，应该排在前面
    if (pack.files.length >= 2) {
      const authFile = pack.files.find(f => f.path.includes('auth/handler'));
      expect(authFile).toBeDefined();
      // 确认 auth/handler.ts 的相关度高于 unrelated.ts
      const unrelatedFile = pack.files.find(f => f.path.includes('unrelated'));
      if (authFile && unrelatedFile) {
        expect(authFile.relevance).toBeGreaterThan(unrelatedFile.relevance);
      }
    }
  });

  it('截断到 max_tokens', () => {
    // 未提供 content 的文件预估 500 token/个，50 个文件共需 25000 token
    // 设置 5000 token 上限，最多能容纳约 10 个文件
    const packager = new ContextPackager({
      max_tokens: 5000,
      max_files: 50,
      relevance_threshold: 0,
    });

    const node = createTaskNode({
      id: 'task-truncate',
      title: '截断测试',
      allowed_paths: [],
    });

    // 生成大量文件
    const files = Array.from({ length: 50 }, (_, i) => `src/file-${i}.ts`);

    const pack = packager.pack(node, files);

    // 由于 max_tokens 限制，不应包含所有 50 个文件
    expect(pack.files.length).toBeLessThan(50);
    // 但至少有一些文件（5000 / 500 = 10 个）
    expect(pack.files.length).toBeGreaterThan(0);
    expect(pack.files.length).toBeLessThanOrEqual(10);
  });

  it('estimateRelevance 返回 0-1 范围值', () => {
    const packager = new ContextPackager();
    const node = createTaskNode({
      id: 'task-relevance',
      title: 'database migration',
      goal: 'migrate database schema',
      allowed_paths: ['src/db/'],
    });

    const testPaths = [
      'src/db/migration.ts',
      'src/api/handler.ts',
      'README.md',
      'package.json',
    ];

    for (const path of testPaths) {
      const relevance = packager.estimateRelevance(path, node);
      expect(relevance).toBeGreaterThanOrEqual(0);
      expect(relevance).toBeLessThanOrEqual(1);
    }

    // 路径匹配 + 关键词匹配的文件应有更高相关度
    const dbRelevance = packager.estimateRelevance('src/db/migration.ts', node);
    const apiRelevance = packager.estimateRelevance('src/api/handler.ts', node);
    expect(dbRelevance).toBeGreaterThan(apiRelevance);
  });

  it('空任务生成空上下文包', () => {
    const packager = new ContextPackager();
    const node = createTaskNode({ id: 'task-empty', title: '空任务' });

    // 没有可用文件
    const pack = packager.pack(node, []);

    expect(pack.task_id).toBe('task-empty');
    expect(pack.files).toEqual([]);
  });
});
