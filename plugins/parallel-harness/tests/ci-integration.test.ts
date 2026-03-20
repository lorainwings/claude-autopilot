/**
 * CI 集成模块测试
 *
 * 覆盖 PRReviewer（PR 审查器）和 CIRunner（CI 运行器）
 * 的审查状态判定、格式化输出、退出码逻辑等。
 */

import { describe, it, expect } from 'bun:test';
import { PRReviewer } from '../runtime/ci/pr-reviewer';
import { CIRunner } from '../runtime/ci/ci-runner';
import {
  createVerifierResult,
  createSynthesizedResult,
} from '../runtime/schemas/verifier-result';
import { createTaskNode, createTaskGraph } from '../runtime/schemas/task-graph';
import type { SynthesizedResult, Finding } from '../runtime/schemas/verifier-result';

// ─── 辅助工厂函数 ───────────────────────────────────────────

/** 构造一个全部通过的综合结果 */
function makePassingResult(taskId: string): SynthesizedResult {
  return createSynthesizedResult({
    task_id: taskId,
    overall_status: 'pass',
    overall_score: 90,
    summary: '所有验证均已通过',
    results: [
      createVerifierResult({
        verifier_type: 'test',
        task_id: taskId,
        status: 'pass',
        score: 95,
        findings: [],
      }),
      createVerifierResult({
        verifier_type: 'review',
        task_id: taskId,
        status: 'pass',
        score: 85,
        findings: [],
      }),
    ],
  });
}

/** 构造一个失败的综合结果 */
function makeFailingResult(taskId: string): SynthesizedResult {
  return createSynthesizedResult({
    task_id: taskId,
    overall_status: 'fail',
    overall_score: 35,
    summary: '存在严重错误需要修复',
    results: [
      createVerifierResult({
        verifier_type: 'test',
        task_id: taskId,
        status: 'fail',
        score: 30,
        findings: [
          {
            severity: 'error',
            message: '单元测试失败: 预期输出不匹配',
            file: 'src/auth.ts',
            line: 42,
          },
          {
            severity: 'error',
            message: '类型检查失败: 参数类型不兼容',
            file: 'src/auth.ts',
            line: 78,
          },
        ],
      }),
      createVerifierResult({
        verifier_type: 'security',
        task_id: taskId,
        status: 'fail',
        score: 40,
        findings: [
          {
            severity: 'warning',
            message: '发现硬编码密钥',
            file: 'src/config.ts',
            line: 15,
            rule: 'no-hardcoded-secrets',
          },
        ],
      }),
    ],
  });
}

/** 构造一个包含大量 findings 的综合结果（用于折叠测试） */
function makeManyFindingsResult(taskId: string, count: number): SynthesizedResult {
  const findings: Finding[] = Array.from({ length: count }, (_, i) => ({
    severity: 'warning' as const,
    message: `发现问题 #${i + 1}`,
    file: `src/module-${i}.ts`,
    line: i + 1,
  }));

  return createSynthesizedResult({
    task_id: taskId,
    overall_status: 'warn',
    overall_score: 65,
    summary: `发现 ${count} 个警告`,
    results: [
      createVerifierResult({
        verifier_type: 'review',
        task_id: taskId,
        status: 'warn',
        score: 65,
        findings,
      }),
    ],
  });
}

// ─────────────────────────────────────────────────────────────
// PRReviewer
// ─────────────────────────────────────────────────────────────

describe('PRReviewer', () => {
  it('通过的结果生成 approved 状态', () => {
    const reviewer = new PRReviewer({ language: 'zh' });
    const synthesized = makePassingResult('task-pass');

    const comment = reviewer.generateReview(synthesized);

    expect(comment.status).toBe('approved');
    expect(typeof comment.body).toBe('string');
    expect(comment.body.length).toBeGreaterThan(0);
  });

  it('失败的结果生成 changes_requested', () => {
    const reviewer = new PRReviewer({ language: 'zh' });
    const synthesized = makeFailingResult('task-fail');

    const comment = reviewer.generateReview(synthesized);

    expect(comment.status).toBe('changes_requested');
  });

  it('生成的评论包含分数表格', () => {
    const reviewer = new PRReviewer({
      language: 'zh',
      include_score: true,
    });
    const synthesized = makePassingResult('task-table');

    const summary = reviewer.formatSummary(synthesized);

    // 应包含 Markdown 表格结构
    expect(summary).toContain('|');
    expect(summary).toContain('---');
    // 应包含验证器类型和分数
    expect(summary).toContain('测试验证');
    expect(summary).toContain('代码审查');
    expect(summary).toContain('95/100');
    expect(summary).toContain('85/100');
  });

  it('findings 超过阈值时折叠显示', () => {
    const reviewer = new PRReviewer({
      language: 'zh',
      include_findings: true,
      collapse_threshold: 3,
      max_findings: 10,
    });

    // 创建包含 8 个 findings 的结果
    const synthesized = makeManyFindingsResult('task-collapse', 8);
    const comment = reviewer.generateReview(synthesized);

    // 应包含 HTML details/summary 折叠标签
    expect(comment.body).toContain('<details>');
    expect(comment.body).toContain('<summary>');
    expect(comment.body).toContain('</details>');
  });

  it('getReviewStatus 对中等分数返回 commented', () => {
    const reviewer = new PRReviewer();

    // 状态为 warn、分数在 60-79 之间 → commented
    const synthesized = createSynthesizedResult({
      overall_status: 'warn',
      overall_score: 70,
    });

    const status = reviewer.getReviewStatus(synthesized);
    expect(status).toBe('commented');
  });

  it('生成的评论包含行级文件评论', () => {
    const reviewer = new PRReviewer({ language: 'zh' });
    const synthesized = makeFailingResult('task-file-comments');

    const comment = reviewer.generateReview(synthesized);

    // 应有文件行级评论（因为 findings 中包含 file 和 line）
    expect(comment.file_comments.length).toBeGreaterThan(0);
    expect(comment.file_comments[0].path).toBe('src/auth.ts');
    expect(comment.file_comments[0].line).toBe(42);
    expect(comment.file_comments[0].severity).toBe('error');
  });

  it('分数低于 60 时即使状态不是 fail 也返回 changes_requested', () => {
    const reviewer = new PRReviewer();

    const synthesized = createSynthesizedResult({
      overall_status: 'warn',
      overall_score: 50,
    });

    const status = reviewer.getReviewStatus(synthesized);
    expect(status).toBe('changes_requested');
  });
});

// ─────────────────────────────────────────────────────────────
// CIRunner
// ─────────────────────────────────────────────────────────────

describe('CIRunner', () => {
  // 构建测试用的任务图
  const testGraph = createTaskGraph({
    id: 'graph-ci-test',
    intent: '测试 CI 集成',
    nodes: [
      createTaskNode({ id: 'task-1', title: '实现功能 A' }),
      createTaskNode({ id: 'task-2', title: '实现功能 B' }),
      createTaskNode({ id: 'task-3', title: '修复 Bug C' }),
    ],
  });

  it('全部通过时 exit_code 为 0', () => {
    const runner = new CIRunner({ fail_on: 'error' });

    const results: SynthesizedResult[] = [
      makePassingResult('task-1'),
      makePassingResult('task-2'),
      makePassingResult('task-3'),
    ];

    const ciResult = runner.run(testGraph, results);

    expect(ciResult.success).toBe(true);
    expect(ciResult.exit_code).toBe(0);
    expect(ciResult.task_results.length).toBe(3);
    expect(ciResult.task_results.every(r => r.status === 'pass')).toBe(true);
  });

  it('有 error 时 exit_code 为 1', () => {
    const runner = new CIRunner({ fail_on: 'error' });

    const results: SynthesizedResult[] = [
      makePassingResult('task-1'),
      makeFailingResult('task-2'),
      makePassingResult('task-3'),
    ];

    const ciResult = runner.run(testGraph, results);

    expect(ciResult.success).toBe(false);
    expect(ciResult.exit_code).toBe(1);
  });

  it('JSON 格式输出正确', () => {
    const runner = new CIRunner({ output_format: 'json' });

    const results: SynthesizedResult[] = [
      makePassingResult('task-1'),
    ];

    const ciResult = runner.run(testGraph, results);
    const json = runner.formatAsJSON(ciResult);

    // 应该是合法 JSON
    const parsed = JSON.parse(json);
    expect(parsed.success).toBe(true);
    expect(parsed.exit_code).toBe(0);
    expect(parsed.task_results).toBeDefined();
    expect(Array.isArray(parsed.task_results)).toBe(true);
    expect(parsed.task_results.length).toBe(1);
    expect(parsed.task_results[0].task_id).toBe('task-1');
  });

  it('Markdown 格式包含表格', () => {
    const runner = new CIRunner({ output_format: 'markdown' });

    const results: SynthesizedResult[] = [
      makePassingResult('task-1'),
      makeFailingResult('task-2'),
    ];

    const ciResult = runner.run(testGraph, results);
    const markdown = runner.formatAsMarkdown(ciResult);

    // 应包含 Markdown 表格结构
    expect(markdown).toContain('| 任务 | 状态 | 分数 | 发现数 |');
    expect(markdown).toContain('| --- | --- | --- | --- |');
    // 应包含任务标题
    expect(markdown).toContain('实现功能 A');
    expect(markdown).toContain('实现功能 B');
    // 应包含 CI 报告标题
    expect(markdown).toContain('## CI 验证报告');
    // 应显示失败状态
    expect(markdown).toContain('❌');
  });

  it('JUnit 格式输出正确的 XML', () => {
    const runner = new CIRunner({ output_format: 'junit' });

    const results: SynthesizedResult[] = [
      makePassingResult('task-1'),
      makeFailingResult('task-2'),
    ];

    const ciResult = runner.run(testGraph, results);
    const junit = runner.formatAsJUnit(ciResult);

    // 应包含 XML 声明
    expect(junit).toContain('<?xml version="1.0"');
    // 应包含 testsuite 和 testcase
    expect(junit).toContain('<testsuite');
    expect(junit).toContain('<testcase');
    expect(junit).toContain('</testsuite>');
    // 失败的任务应有 failure 元素
    expect(junit).toContain('<failure');
  });

  it('shouldFail 根据 fail_on 配置判断', () => {
    // 只关注 error
    const errorRunner = new CIRunner({ fail_on: 'error' });
    const warnResult: SynthesizedResult[] = [
      createSynthesizedResult({
        task_id: 'task-w',
        overall_status: 'warn',
        overall_score: 65,
      }),
    ];
    const failResult: SynthesizedResult[] = [
      createSynthesizedResult({
        task_id: 'task-f',
        overall_status: 'fail',
        overall_score: 30,
      }),
    ];

    // warn 不导致失败（fail_on: 'error'）
    expect(errorRunner.shouldFail(warnResult)).toBe(false);
    // fail 导致失败
    expect(errorRunner.shouldFail(failResult)).toBe(true);

    // 关注 warning
    const warnRunner = new CIRunner({ fail_on: 'warning' });
    // warn 也应导致失败
    expect(warnRunner.shouldFail(warnResult)).toBe(true);
  });

  it('task_results 包含正确的发现数', () => {
    const runner = new CIRunner();
    const failingSynthesized = makeFailingResult('task-2');

    const ciResult = runner.run(testGraph, [failingSynthesized]);

    // task-2 的 failingResult 有 3 个 findings（2 error + 1 warning）
    const taskResult = ciResult.task_results.find(r => r.task_id === 'task-2');
    expect(taskResult).toBeDefined();
    expect(taskResult!.findings_count).toBe(3);
  });

  it('摘要信息包含统计数据', () => {
    const runner = new CIRunner();

    const results: SynthesizedResult[] = [
      makePassingResult('task-1'),
      makeFailingResult('task-2'),
      createSynthesizedResult({
        task_id: 'task-3',
        overall_status: 'warn',
        overall_score: 65,
      }),
    ];

    const ciResult = runner.run(testGraph, results);

    // 摘要应包含统计信息
    expect(ciResult.summary).toContain('3');      // 共 3 个任务
    expect(ciResult.summary).toContain('通过');
    expect(ciResult.summary).toContain('失败');
    expect(ciResult.summary).toContain('警告');
  });

  it('getExitCode 与 shouldFail 一致', () => {
    const runner = new CIRunner({ fail_on: 'error' });

    const passingResults = [makePassingResult('task-1')];
    const failingResults = [makeFailingResult('task-1')];

    // 通过时退出码为 0
    expect(runner.getExitCode(passingResults)).toBe(0);
    expect(runner.shouldFail(passingResults)).toBe(false);

    // 失败时退出码为 1
    expect(runner.getExitCode(failingResults)).toBe(1);
    expect(runner.shouldFail(failingResults)).toBe(true);
  });
});
