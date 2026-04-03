/**
 * parallel-harness: Test & Gate Change Guard
 *
 * 检测 worker 是否修改了测试文件、gate 脚本或 verifier 脚本。
 * 若检测到变更，触发审批流程，防止 agent 通过修改测试/gate 绕过质量检查。
 */

/** 敏感路径模式：匹配测试、gate、verifier 文件 */
const SENSITIVE_PATTERNS: RegExp[] = [
  /\.test\.[tj]sx?$/,
  /\.spec\.[tj]sx?$/,
  /[\\/]tests?[\\/]/,
  /[\\/]__tests__[\\/]/,
  /[\\/]gates[\\/]/,
  /[\\/]verifiers[\\/]/,
  /[\\/]gate-system\.[tj]s$/,
  /[\\/]gate-classification\.[tj]s$/,
  /[\\/]verifier-result\.[tj]s$/,
];

export interface TestChangeDetectionResult {
  has_sensitive_changes: boolean;
  sensitive_paths: string[];
  categories: {
    test_files: string[];
    gate_files: string[];
    verifier_files: string[];
  };
}

/**
 * 检测修改路径中是否包含测试、gate 或 verifier 文件
 */
export function detectTestOrGateChanges(modifiedPaths: string[]): TestChangeDetectionResult {
  const test_files: string[] = [];
  const gate_files: string[] = [];
  const verifier_files: string[] = [];

  for (const p of modifiedPaths) {
    const normalized = p.replace(/\\/g, "/");

    if (/\.test\.[tj]sx?$/.test(normalized) || /\.spec\.[tj]sx?$/.test(normalized) || /[\\/]tests?[\\/]/.test(normalized) || /[\\/]__tests__[\\/]/.test(normalized)) {
      test_files.push(p);
    } else if (/[\\/]gates[\\/]/.test(normalized) || /gate-system\.[tj]s$/.test(normalized) || /gate-classification\.[tj]s$/.test(normalized)) {
      gate_files.push(p);
    } else if (/[\\/]verifiers[\\/]/.test(normalized) || /verifier-result\.[tj]s$/.test(normalized)) {
      verifier_files.push(p);
    }
  }

  const sensitive_paths = [...test_files, ...gate_files, ...verifier_files];

  return {
    has_sensitive_changes: sensitive_paths.length > 0,
    sensitive_paths,
    categories: { test_files, gate_files, verifier_files },
  };
}

/**
 * 判断路径是否匹配敏感模式
 */
export function isSensitivePath(path: string): boolean {
  const normalized = path.replace(/\\/g, "/");
  return SENSITIVE_PATTERNS.some(pattern => pattern.test(normalized));
}

/**
 * 生成审批请求原因描述
 */
export function buildApprovalReason(result: TestChangeDetectionResult): string {
  const parts: string[] = [];
  const { test_files, gate_files, verifier_files } = result.categories;

  if (test_files.length > 0) {
    parts.push(`测试文件变更 (${test_files.length} 个)`);
  }
  if (gate_files.length > 0) {
    parts.push(`Gate 脚本变更 (${gate_files.length} 个)`);
  }
  if (verifier_files.length > 0) {
    parts.push(`Verifier 脚本变更 (${verifier_files.length} 个)`);
  }

  return `敏感文件变更需审批: ${parts.join(", ")}`;
}
