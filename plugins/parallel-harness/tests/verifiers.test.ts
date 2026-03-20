/**
 * 验证器测试
 *
 * 覆盖 TestVerifier、ReviewVerifier 和 ResultSynthesizer
 * 的核心验证和综合逻辑。
 */

import { describe, it, expect } from 'bun:test';
import { TestVerifier } from '../runtime/verifiers/test-verifier';
import { ReviewVerifier } from '../runtime/verifiers/review-verifier';
import { ResultSynthesizer } from '../runtime/verifiers/result-synthesizer';
import { createTaskNode } from '../runtime/schemas/task-graph';
import { createVerifierResult } from '../runtime/schemas/verifier-result';
import type { FileChange } from '../runtime/verifiers/base-verifier';
import type { VerifierResult } from '../runtime/schemas/verifier-result';

// ─────────────────────────────────────────────────────────────
// TestVerifier
// ─────────────────────────────────────────────────────────────

describe('TestVerifier', () => {
  const verifier = new TestVerifier();

  it('缺少测试文件时产生 error', async () => {
    const node = createTaskNode({
      id: 'task-1',
      required_tests: ['tests/auth.test.ts'],
    });

    // 变更列表中没有 required_tests 要求的文件
    const changes: FileChange[] = [
      { path: 'src/auth.ts', type: 'modify', content: 'export const x = 1;' },
    ];

    const result = await verifier.verify(node, changes);

    // 应产生 error 级别的 finding
    expect(result.findings.some(
      f => f.severity === 'error' && f.message.includes('缺失必需测试'),
    )).toBe(true);
    // 状态为 fail
    expect(result.status).toBe('fail');
    // 分数低于满分
    expect(result.score).toBeLessThan(100);
  });

  it('有测试文件时评分较高', async () => {
    const node = createTaskNode({
      id: 'task-2',
      required_tests: ['tests/utils.test.ts'],
    });

    const changes: FileChange[] = [
      { path: 'src/utils.ts', type: 'modify', content: 'export function add(a: number, b: number) { return a + b; }' },
      {
        path: 'tests/utils.test.ts',
        type: 'add',
        content: `import { describe, it, expect } from 'bun:test';
describe('utils', () => {
  it('should add', () => {
    expect(1 + 1).toBe(2);
  });
});`,
      },
    ];

    const result = await verifier.verify(node, changes);

    // 有必需测试文件且包含测试用例 → 高分
    expect(result.score).toBeGreaterThanOrEqual(80);
    // 没有 error 级别的 finding
    expect(result.findings.filter(f => f.severity === 'error').length).toBe(0);
  });
});

// ─────────────────────────────────────────────────────────────
// ReviewVerifier
// ─────────────────────────────────────────────────────────────

describe('ReviewVerifier', () => {
  const verifier = new ReviewVerifier();

  it('检测超长函数', async () => {
    const node = createTaskNode({ id: 'task-review-1' });

    // 构造一个超过 50 行的函数
    const longFunctionLines = [
      'export function longFunction() {',
      ...Array.from({ length: 55 }, (_, i) => `  const x${i} = ${i};`),
      '}',
    ];

    const changes: FileChange[] = [{
      path: 'src/big.ts',
      type: 'add',
      content: longFunctionLines.join('\n'),
    }];

    const result = await verifier.verify(node, changes);

    // 应检测到超长函数的 warning
    expect(result.findings.some(
      f => f.severity === 'warning' && f.message.includes('函数过长'),
    )).toBe(true);
  });

  it('检测调试代码', async () => {
    const node = createTaskNode({ id: 'task-review-2' });

    const changes: FileChange[] = [{
      path: 'src/debug.ts',
      type: 'add',
      content: [
        'export function handler() {',
        '  console.log("debug info");',
        '  debugger;',
        '  return 42;',
        '}',
      ].join('\n'),
    }];

    const result = await verifier.verify(node, changes);

    // 应检测到 console.log 和 debugger
    const debugFindings = result.findings.filter(
      f => f.message.includes('调试代码'),
    );
    expect(debugFindings.length).toBeGreaterThanOrEqual(2);
  });

  it('检测硬编码密钥', async () => {
    const node = createTaskNode({ id: 'task-review-3' });

    const changes: FileChange[] = [{
      path: 'src/config.ts',
      type: 'add',
      content: [
        'const config = {',
        '  password = "super_secret_123",',
        '  api_key = "sk-abc123def456",',
        '};',
      ].join('\n'),
    }];

    const result = await verifier.verify(node, changes);

    // 应检测到硬编码凭据
    const secretFindings = result.findings.filter(
      f => f.severity === 'error' && f.message.includes('硬编码凭据'),
    );
    expect(secretFindings.length).toBeGreaterThanOrEqual(1);
    // 状态为 fail
    expect(result.status).toBe('fail');
  });

  it('干净代码高分通过', async () => {
    const node = createTaskNode({ id: 'task-review-4' });

    const changes: FileChange[] = [{
      path: 'src/clean.ts',
      type: 'add',
      content: [
        '/** 纯函数：计算两数之和 */',
        'export function add(a: number, b: number): number {',
        '  return a + b;',
        '}',
        '',
        '/** 纯函数：计算两数之差 */',
        'export function subtract(a: number, b: number): number {',
        '  return a - b;',
        '}',
      ].join('\n'),
    }];

    const result = await verifier.verify(node, changes);

    // 干净代码应获得高分
    expect(result.score).toBeGreaterThanOrEqual(80);
    // 没有 error 级别的 finding
    expect(result.findings.filter(f => f.severity === 'error').length).toBe(0);
    // 状态为 pass
    expect(result.status).toBe('pass');
  });
});

// ─────────────────────────────────────────────────────────────
// ResultSynthesizer
// ─────────────────────────────────────────────────────────────

describe('ResultSynthesizer', () => {
  const synthesizer = new ResultSynthesizer();

  it('任何 fail 导致总体 fail', () => {
    const results: VerifierResult[] = [
      createVerifierResult({
        verifier_type: 'test',
        task_id: 'task-1',
        status: 'pass',
        score: 90,
        findings: [],
      }),
      createVerifierResult({
        verifier_type: 'review',
        task_id: 'task-1',
        status: 'fail',
        score: 30,
        findings: [{ severity: 'error', message: '严重问题' }],
      }),
    ];

    const synth = synthesizer.synthesize(results);
    expect(synth.overall_status).toBe('fail');
  });

  it('全部 pass 导致总体 pass', () => {
    const results: VerifierResult[] = [
      createVerifierResult({
        verifier_type: 'test',
        task_id: 'task-1',
        status: 'pass',
        score: 95,
        findings: [],
      }),
      createVerifierResult({
        verifier_type: 'review',
        task_id: 'task-1',
        status: 'pass',
        score: 85,
        findings: [],
      }),
    ];

    const synth = synthesizer.synthesize(results);
    expect(synth.overall_status).toBe('pass');
  });

  it('加权评分计算正确', () => {
    // 只有 test 和 review 两个验证器
    // 权重: test=0.30, review=0.25
    // 归一化: test=0.30/(0.30+0.25)=0.5454..., review=0.25/(0.30+0.25)=0.4545...
    const results: VerifierResult[] = [
      createVerifierResult({
        verifier_type: 'test',
        task_id: 'task-1',
        status: 'pass',
        score: 100,
        findings: [],
      }),
      createVerifierResult({
        verifier_type: 'review',
        task_id: 'task-1',
        status: 'pass',
        score: 50,
        findings: [],
      }),
    ];

    const score = synthesizer.getWeightedScore(results);
    // 期望值: 100 * (0.30/0.55) + 50 * (0.25/0.55) ≈ 54.545 + 22.727 ≈ 77.27
    expect(score).toBeGreaterThan(70);
    expect(score).toBeLessThan(85);

    // 不是简单平均值 (100+50)/2 = 75
    // 应该偏向 test 的高分（因为 test 权重更大）
    expect(score).toBeGreaterThan(75);
  });

  it('生成摘要包含关键信息', () => {
    const results: VerifierResult[] = [
      createVerifierResult({
        verifier_type: 'test',
        task_id: 'task-1',
        status: 'pass',
        score: 90,
        findings: [],
      }),
      createVerifierResult({
        verifier_type: 'security',
        task_id: 'task-1',
        status: 'fail',
        score: 20,
        findings: [
          { severity: 'error', message: '发现 SQL 注入漏洞' },
          { severity: 'error', message: '发现 XSS 漏洞' },
        ],
      }),
    ];

    const synth = synthesizer.synthesize(results);

    // 摘要应包含综合评分
    expect(synth.summary).toContain('综合评分');
    // 摘要应包含各验证器的结果
    expect(synth.summary).toContain('测试验证');
    expect(synth.summary).toContain('安全扫描');
    // 摘要应提到阻断级别问题
    expect(synth.summary).toContain('阻断');
    // 总体状态为 fail
    expect(synth.overall_status).toBe('fail');
  });
});
