/**
 * parallel-harness: Complexity Scorer
 *
 * 为任务分配复杂度评分。
 * 复杂度决定了模型 tier 选择、上下文预算和重试策略。
 *
 * 来源设计：
 * - claude-task-master: 复杂度字段
 *
 * 评分维度：
 * - 文件数量
 * - 涉及模块数
 * - 是否涉及关键逻辑（schema/infra/security）
 * - 预估 token 消耗
 */

import type { ComplexityScore, ComplexityLevel } from "./task-graph";

// ============================================================
// 评分输入
// ============================================================

export interface ComplexityInput {
  /** 任务目标描述 */
  goal: string;

  /** 所在域名称 */
  domain_name: string;

  /** 预估涉及文件数 */
  estimated_files: number;

  /** 是否存在跨模块依赖 */
  has_cross_dependency: boolean;

  /** 额外上下文（可选） */
  extra_context?: string;
}

// ============================================================
// 评分器实现
// ============================================================

/** 关键模式关键词 */
const CRITICAL_KEYWORDS = [
  "schema",
  "migration",
  "database",
  "security",
  "auth",
  "permission",
  "infra",
  "deploy",
  "config",
  "critical",
  "breaking",
  "数据库",
  "安全",
  "权限",
  "部署",
  "配置",
  "破坏性",
];

/**
 * 计算任务复杂度评分
 */
export function scoreComplexity(input: ComplexityInput): ComplexityScore {
  const goalLower = input.goal.toLowerCase();

  // 维度分析
  const fileCount = input.estimated_files;
  const moduleCount = input.has_cross_dependency ? 2 : 1;
  const involvesCritical = CRITICAL_KEYWORDS.some((kw) =>
    goalLower.includes(kw)
  );
  const estimatedTokens = estimateTokens(input);

  // 各维度打分 (0-25 each, total 0-100)
  const fileScore = Math.min(25, fileCount * 3);
  const moduleScore = moduleCount >= 3 ? 25 : moduleCount >= 2 ? 15 : 5;
  const criticalScore = involvesCritical ? 25 : 5;
  const tokenScore = Math.min(25, Math.floor(estimatedTokens / 2000));

  const totalScore = fileScore + moduleScore + criticalScore + tokenScore;
  const level = scoreToLevel(totalScore);

  return {
    level,
    score: totalScore,
    dimensions: {
      file_count: fileCount,
      module_count: moduleCount,
      involves_critical: involvesCritical,
      estimated_tokens: estimatedTokens,
    },
    reasoning: buildReasoning(
      level,
      fileCount,
      moduleCount,
      involvesCritical,
      estimatedTokens
    ),
  };
}

// ============================================================
// 辅助函数
// ============================================================

function estimateTokens(input: ComplexityInput): number {
  let base = 2000; // 基础 token

  // 按文件数增加
  base += input.estimated_files * 500;

  // 跨模块增加上下文需求
  if (input.has_cross_dependency) base += 3000;

  // 关键逻辑需要更多理解上下文
  const goalLower = input.goal.toLowerCase();
  if (CRITICAL_KEYWORDS.some((kw) => goalLower.includes(kw))) {
    base += 5000;
  }

  return base;
}

function scoreToLevel(score: number): ComplexityLevel {
  if (score <= 15) return "trivial";
  if (score <= 35) return "low";
  if (score <= 55) return "medium";
  if (score <= 75) return "high";
  return "extreme";
}

function buildReasoning(
  level: ComplexityLevel,
  fileCount: number,
  moduleCount: number,
  involvesCritical: boolean,
  estimatedTokens: number
): string {
  const parts: string[] = [];
  parts.push(`复杂度等级: ${level}`);
  parts.push(`涉及文件: ${fileCount}`);
  parts.push(`涉及模块: ${moduleCount}`);
  if (involvesCritical) parts.push("涉及关键逻辑(schema/infra/security)");
  parts.push(`预估 token: ${estimatedTokens}`);
  return parts.join(", ");
}
