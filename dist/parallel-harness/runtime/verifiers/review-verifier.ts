/**
 * review-verifier.ts — 代码审查验证器
 *
 * 静态扫描代码质量问题：
 *   1. 文件是否在 allowed_paths 范围内
 *   2. 是否有超长函数（>50 行）
 *   3. 是否有 TODO / FIXME / HACK 注释
 *   4. 是否有调试代码（console.log / debugger / print）
 *   5. 是否有硬编码密钥模式（password= / secret= / api_key=）
 *
 * 评分基于 finding 数量和严重度加权扣分。
 */

import type { VerifierResult, Finding, TaskNode } from '../schemas';
import { BaseVerifier, type FileChange, type VerifierConfig } from './base-verifier';

// ---------------------------------------------------------------------------
// 检测规则的正则模式
// ---------------------------------------------------------------------------

/** TODO / FIXME / HACK 注释 */
const TODO_PATTERN = /\b(TODO|FIXME|HACK)\b/gi;

/** 调试代码模式 */
const DEBUG_PATTERNS = [
  { pattern: /\bconsole\.(log|debug|info|warn|error)\s*\(/, name: 'console.log' },
  { pattern: /\bdebugger\b/, name: 'debugger' },
  { pattern: /\bprint\s*\(/, name: 'print()' },
];

/** 硬编码密钥模式（大小写不敏感） */
const SECRET_PATTERNS = [
  /\bpassword\s*=\s*['"][^'"]+['"]/i,
  /\bsecret\s*=\s*['"][^'"]+['"]/i,
  /\bapi_key\s*=\s*['"][^'"]+['"]/i,
  /\bapi[-_]?secret\s*=\s*['"][^'"]+['"]/i,
  /\btoken\s*=\s*['"][^'"]+['"]/i,
];

/** 函数声明模式（用于检测超长函数） */
const FUNCTION_START_PATTERNS = [
  /^\s*(export\s+)?(async\s+)?function\s+\w+/,
  /^\s*(export\s+)?(const|let|var)\s+\w+\s*=\s*(async\s+)?\(/,
  /^\s*(export\s+)?(const|let|var)\s+\w+\s*=\s*(async\s+)?\w+\s*=>/,
  /^\s*(public|private|protected)?\s*(async\s+)?\w+\s*\([^)]*\)\s*[:{]/,
];

// ---------------------------------------------------------------------------
// ReviewVerifier
// ---------------------------------------------------------------------------

export class ReviewVerifier extends BaseVerifier {
  readonly type = 'review' as const;

  constructor(config?: Partial<VerifierConfig>) {
    super(config);
  }

  async verify(node: TaskNode, changes: FileChange[]): Promise<VerifierResult> {
    const findings: Finding[] = [];

    for (const change of changes) {
      // 跳过删除的文件
      if (change.type === 'delete') continue;

      // ------ 1. 检查文件是否在 allowed_paths 范围内 ------
      if (node.allowed_paths.length > 0) {
        const isAllowed = node.allowed_paths.some(
          (ap) => change.path.startsWith(ap) || change.path === ap,
        );
        if (!isAllowed) {
          findings.push(
            this.createFinding(
              'error',
              `文件不在允许路径范围内: ${change.path}`,
              change.path,
              undefined,
              'path-not-allowed',
            ),
          );
        }
      }

      // 以下检查需要文件内容
      if (!change.content) continue;
      const lines = change.content.split('\n');

      // ------ 2. 检查超长函数（>50 行） ------
      this.checkLongFunctions(lines, change.path, findings);

      // ------ 3. 检查 TODO / FIXME / HACK 注释 ------
      for (let i = 0; i < lines.length; i++) {
        const matches = lines[i].match(TODO_PATTERN);
        if (matches) {
          findings.push(
            this.createFinding(
              'info',
              `发现 ${matches[0]} 注释`,
              change.path,
              i + 1,
              'todo-comment',
            ),
          );
        }
      }

      // ------ 4. 检查调试代码 ------
      for (let i = 0; i < lines.length; i++) {
        for (const debug of DEBUG_PATTERNS) {
          if (debug.pattern.test(lines[i])) {
            findings.push(
              this.createFinding(
                'warning',
                `发现调试代码: ${debug.name}`,
                change.path,
                i + 1,
                'debug-code',
              ),
            );
          }
        }
      }

      // ------ 5. 检查硬编码密钥 ------
      for (let i = 0; i < lines.length; i++) {
        for (const secretPattern of SECRET_PATTERNS) {
          if (secretPattern.test(lines[i])) {
            findings.push(
              this.createFinding(
                'error',
                `疑似硬编码凭据`,
                change.path,
                i + 1,
                'hardcoded-secret',
              ),
            );
            break; // 同一行只报告一次
          }
        }
      }
    }

    // ------ 计算评分 ------
    const score = this.calculateScore(findings);

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

  // -----------------------------------------------------------------------
  // 私有方法
  // -----------------------------------------------------------------------

  /**
   * 检测超长函数
   * 通过简单的大括号匹配追踪函数体长度
   */
  private checkLongFunctions(
    lines: string[],
    filePath: string,
    findings: Finding[],
  ): void {
    let braceDepth = 0;
    let funcStartLine = -1;
    let inFunction = false;

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];

      // 检测函数起始行
      if (!inFunction && FUNCTION_START_PATTERNS.some((p) => p.test(line))) {
        funcStartLine = i;
        inFunction = true;
        braceDepth = 0;
      }

      if (inFunction) {
        // 统计大括号（简单计数，不处理字符串内的大括号）
        for (const ch of line) {
          if (ch === '{') braceDepth++;
          if (ch === '}') braceDepth--;
        }

        // 函数结束
        if (braceDepth <= 0 && funcStartLine !== i) {
          const funcLength = i - funcStartLine + 1;
          if (funcLength > 50) {
            findings.push(
              this.createFinding(
                'warning',
                `函数过长 (${funcLength} 行，建议不超过 50 行)`,
                filePath,
                funcStartLine + 1,
                'long-function',
              ),
            );
          }
          inFunction = false;
          braceDepth = 0;
        }
      }
    }
  }

  /**
   * 基于 finding 数量和严重度计算评分
   *   - error:   每个扣 15 分
   *   - warning: 每个扣 5 分
   *   - info:    每个扣 2 分
   */
  private calculateScore(findings: Finding[]): number {
    let deduction = 0;
    for (const f of findings) {
      switch (f.severity) {
        case 'error':
          deduction += 15;
          break;
        case 'warning':
          deduction += 5;
          break;
        case 'info':
          deduction += 2;
          break;
      }
    }
    return Math.max(0, Math.min(100, 100 - deduction));
  }
}
