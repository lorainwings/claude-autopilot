/**
 * perf-verifier.ts — 性能验证器
 *
 * 检测常见性能反模式：
 *   1. N+1 查询模式（循环内数据库调用）
 *   2. 循环内 await
 *   3. 大数组全量拷贝（Array spread / slice / concat）
 *   4. 同步文件 I/O（readFileSync / writeFileSync 等）
 *   5. 未限制的正则匹配（无边界的 .* 贪婪模式）
 *
 * 评分基于发现的反模式数量加权扣分。
 */

import type { VerifierResult, Finding, TaskNode } from '../schemas';
import { BaseVerifier, type FileChange, type VerifierConfig } from './base-verifier';

// ---------------------------------------------------------------------------
// 检测规则
// ---------------------------------------------------------------------------

/** 性能规则描述 */
interface PerfRule {
  /** 规则标识 */
  id: string;
  /** 中文描述 */
  description: string;
  /** 严重级别 */
  severity: Finding['severity'];
  /**
   * 检测函数
   * 接收文件内容的所有行，返回匹配的行号列表（1-indexed）
   */
  detect: (lines: string[]) => number[];
}

/** N+1 查询模式检测 — 循环体内出现数据库查询调用 */
const N_PLUS_ONE_RULE: PerfRule = {
  id: 'no-n-plus-one',
  description: 'N+1 查询风险 — 循环内执行数据库调用',
  severity: 'warning',
  detect(lines) {
    const hits: number[] = [];
    // 查询关键词
    const queryPattern = /\b(query|find|findOne|findMany|select|fetch|get)\s*\(/i;
    // 简单追踪：是否在 for / while / forEach / map 等循环体内
    let loopDepth = 0;

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      // 检测循环入口
      if (/\b(for|while)\s*\(/.test(line) || /\.\s*(forEach|map|flatMap|reduce)\s*\(/.test(line)) {
        loopDepth++;
      }
      // 简单跟踪大括号闭合（不处理字符串内的情况）
      for (const ch of line) {
        if (ch === '{') loopDepth = Math.max(loopDepth, loopDepth);
        if (ch === '}' && loopDepth > 0) {
          // 仅在匹配到循环后才递减
        }
      }
      // 循环内出现查询调用
      if (loopDepth > 0 && queryPattern.test(line)) {
        hits.push(i + 1);
      }
      // 结束循环块的简单启发：如果行只有 } 则可能退出循环
      if (line.trim() === '}' && loopDepth > 0) {
        loopDepth--;
      }
    }
    return hits;
  },
};

/** 循环内 await 检测 */
const LOOP_AWAIT_RULE: PerfRule = {
  id: 'no-loop-await',
  description: '循环内 await — 考虑使用 Promise.all() 并发执行',
  severity: 'warning',
  detect(lines) {
    const hits: number[] = [];
    let inLoop = false;
    let braceCount = 0;
    let loopBraceStart = 0;

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];

      // 检测循环起始
      if (/\b(for|while)\s*\(/.test(line) || /\.\s*(forEach|map)\s*\(/.test(line)) {
        if (!inLoop) {
          inLoop = true;
          loopBraceStart = braceCount;
        }
      }

      // 统计大括号
      for (const ch of line) {
        if (ch === '{') braceCount++;
        if (ch === '}') braceCount--;
      }

      // 循环内 await
      if (inLoop && /\bawait\b/.test(line)) {
        hits.push(i + 1);
      }

      // 退出循环
      if (inLoop && braceCount <= loopBraceStart) {
        inLoop = false;
      }
    }
    return hits;
  },
};

/** 大数组全量拷贝检测 */
const ARRAY_COPY_RULE: PerfRule = {
  id: 'no-large-array-copy',
  description: '大数组全量拷贝 — 注意性能影响',
  severity: 'info',
  detect(lines) {
    const hits: number[] = [];
    const pattern = /\[\s*\.\.\.\w+\]|\.slice\s*\(\s*\)|\.concat\s*\(/;
    for (let i = 0; i < lines.length; i++) {
      if (pattern.test(lines[i])) {
        hits.push(i + 1);
      }
    }
    return hits;
  },
};

/** 同步文件 I/O 检测 */
const SYNC_IO_RULE: PerfRule = {
  id: 'no-sync-io',
  description: '同步文件 I/O — 会阻塞事件循环',
  severity: 'warning',
  detect(lines) {
    const hits: number[] = [];
    const pattern = /\b(readFileSync|writeFileSync|appendFileSync|existsSync|mkdirSync|readdirSync|statSync|unlinkSync|rmdirSync|copyFileSync)\s*\(/;
    for (let i = 0; i < lines.length; i++) {
      if (pattern.test(lines[i])) {
        hits.push(i + 1);
      }
    }
    return hits;
  },
};

/** 未限制的贪婪正则检测 */
const GREEDY_REGEX_RULE: PerfRule = {
  id: 'no-unbounded-regex',
  description: '未限制的贪婪正则匹配 — 可能导致性能问题',
  severity: 'info',
  detect(lines) {
    const hits: number[] = [];
    // 检测 new RegExp 或 正则字面量中包含 .* 且无 ? 非贪婪
    const pattern = /\.\*(?!\?)/;
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      // 仅对包含 RegExp 或正则字面量 /.../ 的行检查
      if ((/new\s+RegExp/.test(line) || /\/[^/]+\//.test(line)) && pattern.test(line)) {
        hits.push(i + 1);
      }
    }
    return hits;
  },
};

/** 所有性能规则 */
const ALL_PERF_RULES: PerfRule[] = [
  N_PLUS_ONE_RULE,
  LOOP_AWAIT_RULE,
  ARRAY_COPY_RULE,
  SYNC_IO_RULE,
  GREEDY_REGEX_RULE,
];

// ---------------------------------------------------------------------------
// PerfVerifier
// ---------------------------------------------------------------------------

export class PerfVerifier extends BaseVerifier {
  readonly type = 'perf' as const;

  constructor(config?: Partial<VerifierConfig>) {
    super(config);
  }

  async verify(node: TaskNode, changes: FileChange[]): Promise<VerifierResult> {
    const findings: Finding[] = [];

    for (const change of changes) {
      // 跳过删除的文件
      if (change.type === 'delete') continue;

      // 需要文件内容
      if (!change.content) continue;

      const lines = change.content.split('\n');

      // 执行每条性能规则
      for (const rule of ALL_PERF_RULES) {
        const hitLines = rule.detect(lines);
        for (const lineNo of hitLines) {
          findings.push(
            this.createFinding(
              rule.severity,
              rule.description,
              change.path,
              lineNo,
              rule.id,
            ),
          );
        }
      }
    }

    // ------ 评分 ------
    // error: -20, warning: -10, info: -5
    const score = this.calculateScore(findings);

    // ------ 状态 ------
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

  /**
   * 基于反模式数量和严重度加权计算评分
   */
  private calculateScore(findings: Finding[]): number {
    let deduction = 0;
    for (const f of findings) {
      switch (f.severity) {
        case 'error':
          deduction += 20;
          break;
        case 'warning':
          deduction += 10;
          break;
        case 'info':
          deduction += 5;
          break;
      }
    }
    return Math.max(0, Math.min(100, 100 - deduction));
  }
}
