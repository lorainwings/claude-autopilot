/**
 * parallel-harness: Anti-Reward-Hacking Chain
 *
 * 防止 agent 通过以下手段绕过质量检查:
 * - 删除或弱化断言
 * - 添加 skip/todo 标记
 * - 修改测试阈值
 * - 修改 gate 配置
 */

export interface SuspiciousPatchResult {
  suspicious: boolean;
  findings: SuspiciousFinding[];
  severity: "none" | "low" | "medium" | "high";
}

export interface SuspiciousFinding {
  type: SuspiciousPatchType;
  file_path: string;
  line_content: string;
  reason: string;
  severity: "low" | "medium" | "high";
}

export type SuspiciousPatchType =
  | "assertion_removed"
  | "skip_added"
  | "todo_added"
  | "threshold_lowered"
  | "test_deleted"
  | "gate_weakened"
  | "expect_removed"
  | "coverage_lowered";

/** 可疑模式定义 */
interface SuspiciousPattern {
  type: SuspiciousPatchType;
  /** 匹配删除行（- 开头）的正则 */
  removed_pattern?: RegExp;
  /** 匹配新增行（+ 开头）的正则 */
  added_pattern?: RegExp;
  severity: "low" | "medium" | "high";
  reason: string;
}

const SUSPICIOUS_PATTERNS: SuspiciousPattern[] = [
  {
    type: "assertion_removed",
    removed_pattern: /^\-.*\b(expect|assert|should|toBe|toEqual|toThrow|toContain)\b/,
    severity: "high",
    reason: "删除了断言语句",
  },
  {
    type: "expect_removed",
    removed_pattern: /^\-.*\bexpect\s*\(/,
    severity: "high",
    reason: "删除了 expect 调用",
  },
  {
    type: "skip_added",
    added_pattern: /^\+.*\b(\.skip|xit|xdescribe|xtest|it\.skip|describe\.skip|test\.skip)\b/,
    severity: "high",
    reason: "添加了测试跳过标记",
  },
  {
    type: "todo_added",
    added_pattern: /^\+.*\b(\.todo|it\.todo|test\.todo)\b/,
    severity: "medium",
    reason: "添加了 todo 标记替代真实测试",
  },
  {
    type: "threshold_lowered",
    added_pattern: /^\+.*\b(min_pass_rate|min_coverage|threshold)\s*[:=]\s*0\.[0-3]/,
    severity: "high",
    reason: "降低了质量阈值到不合理水平",
  },
  {
    type: "gate_weakened",
    added_pattern: /^\+.*\bblocking\s*[:=]\s*false/,
    severity: "medium",
    reason: "将阻断 gate 改为非阻断",
  },
  {
    type: "coverage_lowered",
    added_pattern: /^\+.*\bmin_coverage\s*[:=]\s*0\.[0-3]/,
    severity: "medium",
    reason: "降低了覆盖率要求",
  },
];

/**
 * 检测 diff 中的可疑补丁模式
 */
export function detectSuspiciousPatches(diff: string): SuspiciousPatchResult {
  const findings: SuspiciousFinding[] = [];
  const lines = diff.split("\n");

  let currentFile = "";

  for (const line of lines) {
    // 追踪当前文件
    const fileMatch = line.match(/^\+\+\+\s+[ab]\/(.+)/);
    if (fileMatch) {
      currentFile = fileMatch[1];
      continue;
    }

    // 检查每个模式
    for (const pattern of SUSPICIOUS_PATTERNS) {
      if (pattern.removed_pattern && pattern.removed_pattern.test(line)) {
        findings.push({
          type: pattern.type,
          file_path: currentFile,
          line_content: line.slice(0, 200),
          reason: pattern.reason,
          severity: pattern.severity,
        });
      }
      if (pattern.added_pattern && pattern.added_pattern.test(line)) {
        findings.push({
          type: pattern.type,
          file_path: currentFile,
          line_content: line.slice(0, 200),
          reason: pattern.reason,
          severity: pattern.severity,
        });
      }
    }
  }

  // 计算整体 severity
  let severity: "none" | "low" | "medium" | "high" = "none";
  if (findings.some(f => f.severity === "high")) severity = "high";
  else if (findings.some(f => f.severity === "medium")) severity = "medium";
  else if (findings.length > 0) severity = "low";

  return { suspicious: findings.length > 0, findings, severity };
}

/**
 * 审计测试文件变更
 */
export function auditTestFileChanges(modifiedPaths: string[]): {
  audited: boolean;
  test_files_changed: string[];
  requires_review: boolean;
} {
  const testPatterns = [/\.test\.[tj]sx?$/, /\.spec\.[tj]sx?$/, /[\\/]tests?[\\/]/, /[\\/]__tests__[\\/]/];
  const testFiles = modifiedPaths.filter(p => testPatterns.some(pattern => pattern.test(p)));

  return {
    audited: true,
    test_files_changed: testFiles,
    requires_review: testFiles.length > 0,
  };
}

/**
 * 审计 gate 文件变更
 */
export function auditGateFileChanges(modifiedPaths: string[]): {
  audited: boolean;
  gate_files_changed: string[];
  requires_review: boolean;
} {
  const gatePatterns = [/[\\/]gates[\\/]/, /[\\/]verifiers[\\/]/, /gate-system/, /gate-classification/];
  const gateFiles = modifiedPaths.filter(p => gatePatterns.some(pattern => pattern.test(p)));

  return {
    audited: true,
    gate_files_changed: gateFiles,
    requires_review: gateFiles.length > 0,
  };
}
