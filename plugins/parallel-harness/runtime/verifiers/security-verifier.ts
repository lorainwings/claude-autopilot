/**
 * security-verifier.ts — 安全验证器
 *
 * 检测常见安全问题：
 *   1. eval / exec / Function 动态执行
 *   2. SQL 拼接（非参数化查询）
 *   3. 硬编码凭据
 *   4. 不安全的文件操作（路径遍历模式 ../ ）
 *   5. 不安全的正则表达式（ReDoS 风险）
 *
 * 评分公式: 100 - (error 数 * 25) - (warning 数 * 10)
 */

import type { VerifierResult, Finding, TaskNode } from '../schemas';
import { BaseVerifier, type FileChange, type VerifierConfig } from './base-verifier';

// ---------------------------------------------------------------------------
// 检测规则
// ---------------------------------------------------------------------------

/** 规则描述 */
interface SecurityRule {
  /** 规则标识 */
  id: string;
  /** 规则描述（中文） */
  description: string;
  /** 检测正则 */
  pattern: RegExp;
  /** 发现严重级别 */
  severity: Finding['severity'];
}

/** 动态执行检测 */
const EVAL_RULES: SecurityRule[] = [
  {
    id: 'no-eval',
    description: '禁止使用 eval()',
    pattern: /\beval\s*\(/,
    severity: 'error',
  },
  {
    id: 'no-function-constructor',
    description: '禁止使用 new Function()',
    pattern: /\bnew\s+Function\s*\(/,
    severity: 'error',
  },
  {
    id: 'no-exec',
    description: '禁止使用 exec() / execSync()',
    pattern: /\bexec(Sync)?\s*\(/,
    severity: 'warning',
  },
];

/** SQL 拼接检测 */
const SQL_INJECTION_RULES: SecurityRule[] = [
  {
    id: 'no-sql-concat',
    description: 'SQL 拼接风险 — 模板字符串中嵌入变量',
    pattern: /\b(SELECT|INSERT|UPDATE|DELETE|DROP)\b[^;]*\$\{/i,
    severity: 'error',
  },
  {
    id: 'no-sql-plus-concat',
    description: 'SQL 拼接风险 — 字符串 + 连接',
    pattern: /['"]?\s*\+\s*\w+.*\b(SELECT|INSERT|UPDATE|DELETE|WHERE)\b/i,
    severity: 'error',
  },
];

/** 硬编码凭据检测 */
const CREDENTIAL_RULES: SecurityRule[] = [
  {
    id: 'no-hardcoded-password',
    description: '硬编码密码',
    pattern: /\b(password|passwd|pwd)\s*[:=]\s*['"][^'"]{4,}['"]/i,
    severity: 'error',
  },
  {
    id: 'no-hardcoded-secret',
    description: '硬编码密钥',
    pattern: /\b(secret|api_key|apikey|access_key|private_key)\s*[:=]\s*['"][^'"]{4,}['"]/i,
    severity: 'error',
  },
  {
    id: 'no-hardcoded-token',
    description: '硬编码令牌',
    pattern: /\b(token|auth_token|bearer)\s*[:=]\s*['"][^'"]{8,}['"]/i,
    severity: 'error',
  },
];

/** 路径遍历检测 */
const PATH_TRAVERSAL_RULES: SecurityRule[] = [
  {
    id: 'no-path-traversal',
    description: '路径遍历风险 — 包含 ../',
    pattern: /\.\.\//,
    severity: 'warning',
  },
  {
    id: 'no-user-input-path',
    description: '用户输入直接用于文件路径',
    pattern: /\b(readFile|writeFile|readdir|unlink|rmdir|mkdir)\s*\([^)]*\breq\.(body|query|params)/,
    severity: 'error',
  },
];

/** ReDoS 风险检测（嵌套量词和回溯） */
const REDOS_RULES: SecurityRule[] = [
  {
    id: 'no-redos-nested-quantifier',
    description: 'ReDoS 风险 — 嵌套量词',
    pattern: /new\s+RegExp\s*\([^)]*[+*]\)[^)]*[+*]/,
    severity: 'warning',
  },
  {
    id: 'no-redos-catastrophic',
    description: 'ReDoS 风险 — 灾难性回溯模式 (a+)+',
    pattern: /\([^)]*[+*]\)\s*[+*]/,
    severity: 'warning',
  },
];

/** 所有安全规则集合 */
const ALL_RULES: SecurityRule[] = [
  ...EVAL_RULES,
  ...SQL_INJECTION_RULES,
  ...CREDENTIAL_RULES,
  ...PATH_TRAVERSAL_RULES,
  ...REDOS_RULES,
];

// ---------------------------------------------------------------------------
// SecurityVerifier
// ---------------------------------------------------------------------------

export class SecurityVerifier extends BaseVerifier {
  readonly type = 'security' as const;

  constructor(config?: Partial<VerifierConfig>) {
    super(config);
  }

  async verify(node: TaskNode, changes: FileChange[]): Promise<VerifierResult> {
    const findings: Finding[] = [];

    for (const change of changes) {
      // 跳过删除的文件
      if (change.type === 'delete') continue;

      // 需要文件内容才能做静态分析
      if (!change.content) continue;

      const lines = change.content.split('\n');

      // 遍历每一行，逐条规则扫描
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i];

        // 跳过注释行（简单启发：以 // 或 * 开头、行内 // 后面的内容不跳过）
        const trimmed = line.trim();
        if (trimmed.startsWith('//') || trimmed.startsWith('*') || trimmed.startsWith('/*')) {
          continue;
        }

        for (const rule of ALL_RULES) {
          if (rule.pattern.test(line)) {
            findings.push(
              this.createFinding(
                rule.severity,
                rule.description,
                change.path,
                i + 1,
                rule.id,
              ),
            );
          }
        }
      }
    }

    // ------ 评分: 100 - (error 数 * 25) - (warning 数 * 10) ------
    const errorCount = findings.filter((f) => f.severity === 'error').length;
    const warningCount = findings.filter((f) => f.severity === 'warning').length;
    const score = clampScore(100 - errorCount * 25 - warningCount * 10);

    // ------ 确定状态 ------
    const status = errorCount > 0 ? 'fail' : warningCount > 0 ? 'warn' : 'pass';

    return this.createResult({
      task_id: node.id,
      status,
      score,
      findings,
    });
  }
}

// ---------------------------------------------------------------------------
// 辅助
// ---------------------------------------------------------------------------

/** 将分数夹到 [0, 100] 区间 */
function clampScore(score: number): number {
  return Math.max(0, Math.min(100, score));
}
