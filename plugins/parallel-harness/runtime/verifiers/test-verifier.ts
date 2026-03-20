/**
 * test-verifier.ts — 测试验证器
 *
 * 检查任务产出是否包含必要的测试：
 *   1. required_tests 中定义的测试文件是否存在
 *   2. 新增 / 修改的源码是否有对应测试文件
 *   3. 测试文件中是否包含至少一个 test / it / describe
 *
 * 评分公式: 100 - (缺失测试数 * 20) - (缺失覆盖 * 10)
 */

import type { VerifierResult, Finding, TaskNode } from '../schemas';
import { BaseVerifier, type FileChange, type VerifierConfig } from './base-verifier';

// ---------------------------------------------------------------------------
// 常量
// ---------------------------------------------------------------------------

/** 匹配测试文件的路径模式 */
const TEST_FILE_PATTERNS = [
  /\.test\.[jt]sx?$/,
  /\.spec\.[jt]sx?$/,
  /__tests__\//,
  /\/tests?\//,
];

/** 匹配测试用例声明 */
const TEST_CASE_PATTERN = /\b(test|it|describe)\s*\(/;

/** 源码文件后缀 */
const SOURCE_EXTENSIONS = /\.(ts|tsx|js|jsx|mts|cts)$/;

// ---------------------------------------------------------------------------
// TestVerifier
// ---------------------------------------------------------------------------

export class TestVerifier extends BaseVerifier {
  readonly type = 'test' as const;

  constructor(config?: Partial<VerifierConfig>) {
    super(config);
  }

  async verify(node: TaskNode, changes: FileChange[]): Promise<VerifierResult> {
    const findings: Finding[] = [];

    // ------ 1. 检查 required_tests 中定义的测试文件是否存在 ------
    const changePaths = new Set(changes.map((c) => c.path));
    let missingRequiredCount = 0;

    for (const requiredTest of node.required_tests) {
      // 在变更列表中查找是否存在该测试文件（支持路径尾部匹配）
      const found = changes.some(
        (c) => c.path === requiredTest || c.path.endsWith(`/${requiredTest}`),
      );
      if (!found) {
        missingRequiredCount++;
        findings.push(
          this.createFinding(
            'error',
            `缺失必需测试文件: ${requiredTest}`,
            requiredTest,
            undefined,
            'required-test-missing',
          ),
        );
      }
    }

    // ------ 2. 检查新增 / 修改的源码是否有对应测试 ------
    const sourceFiles = changes.filter(
      (c) =>
        c.type !== 'delete' &&
        SOURCE_EXTENSIONS.test(c.path) &&
        !isTestFile(c.path),
    );

    let missingCoverageCount = 0;

    for (const src of sourceFiles) {
      const expectedTestPaths = deriveTestPaths(src.path);
      const hasCoverage = expectedTestPaths.some((tp) =>
        changes.some(
          (c) => c.path === tp || c.path.endsWith(`/${tp}`),
        ),
      );
      if (!hasCoverage) {
        missingCoverageCount++;
        findings.push(
          this.createFinding(
            'warning',
            `源文件缺少对应测试: ${src.path}`,
            src.path,
            undefined,
            'missing-test-coverage',
          ),
        );
      }
    }

    // ------ 3. 检查测试文件是否包含至少一个 test/it/describe ------
    const testFiles = changes.filter(
      (c) => c.type !== 'delete' && isTestFile(c.path) && c.content,
    );

    for (const tf of testFiles) {
      if (!TEST_CASE_PATTERN.test(tf.content!)) {
        findings.push(
          this.createFinding(
            'warning',
            `测试文件未包含任何测试用例 (test/it/describe): ${tf.path}`,
            tf.path,
            undefined,
            'empty-test-file',
          ),
        );
      }
    }

    // ------ 计算评分 ------
    const score = clampScore(100 - missingRequiredCount * 20 - missingCoverageCount * 10);

    // ------ 确定状态 ------
    const hasError = findings.some((f) => f.severity === 'error');
    const hasWarning = findings.some((f) => f.severity === 'warning');
    const status = hasError ? 'fail' : hasWarning ? 'warn' : 'pass';

    return this.createResult({
      task_id: node.id,
      status,
      score,
      findings,
    });
  }
}

// ---------------------------------------------------------------------------
// 辅助函数
// ---------------------------------------------------------------------------

/** 判断路径是否为测试文件 */
function isTestFile(path: string): boolean {
  return TEST_FILE_PATTERNS.some((p) => p.test(path));
}

/**
 * 根据源文件路径推导可能的测试文件路径
 * 例: src/utils/foo.ts → [src/utils/foo.test.ts, src/utils/foo.spec.ts, ...]
 */
function deriveTestPaths(srcPath: string): string[] {
  const base = srcPath.replace(SOURCE_EXTENSIONS, '');
  const ext = srcPath.match(SOURCE_EXTENSIONS)?.[0] ?? '.ts';
  return [
    `${base}.test${ext}`,
    `${base}.spec${ext}`,
    srcPath.replace(/\/src\//, '/tests/').replace(SOURCE_EXTENSIONS, `.test${ext}`),
  ];
}

/** 将分数夹到 [0, 100] 区间 */
function clampScore(score: number): number {
  return Math.max(0, Math.min(100, score));
}
