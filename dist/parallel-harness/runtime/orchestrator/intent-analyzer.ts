/**
 * 意图分析器
 *
 * 分析用户输入的自然语言指令，提取意图类型、作用域和复杂度
 */

import type { IntentAnalysis, IntentType, ModelTier, SplitStrategy } from '../schemas/types.js';

/** 意图关键词映射 */
const INTENT_KEYWORDS: Record<IntentType, string[]> = {
  feature: ['添加', '新增', '创建', '实现', 'add', 'create', 'implement', 'new', 'feature'],
  bugfix: ['修复', '修改', 'bug', 'fix', 'repair', 'resolve', '问题', '错误', 'error'],
  refactor: ['重构', '优化', '重写', 'refactor', 'optimize', 'rewrite', 'restructure', 'clean'],
  test: ['测试', 'test', 'spec', '验证', 'verify'],
  docs: ['文档', '注释', 'doc', 'readme', 'comment', '说明'],
  unknown: [],
};

/** 文件路径提取正则 */
const FILE_PATH_REGEX = /(?:^|\s)((?:[\w.-]+\/)*[\w.-]+\.\w+)/g;

/** 复杂度评估关键词 */
const HIGH_COMPLEXITY_KEYWORDS = ['全面', '重构', '架构', '迁移', 'migrate', 'architecture', '跨模块', 'cross-module'];
const MEDIUM_COMPLEXITY_KEYWORDS = ['修改', '更新', '调整', 'update', 'modify', 'adjust', '多个'];

/**
 * 分析用户指令的意图
 * @param prompt 用户输入的自然语言指令
 * @returns 意图分析结果
 */
export function analyzeIntent(prompt: string): IntentAnalysis {
  const lower = prompt.toLowerCase();

  // 识别意图类型
  const type = detectIntentType(lower);

  // 提取文件路径作为作用域
  const scope = extractScope(prompt);

  // 评估复杂度
  const complexity = assessComplexity(lower, scope);

  // 推荐模型层级
  const recommended_model_tier = recommendTier(complexity);

  // 推荐拆分策略
  const split_strategy = recommendSplitStrategy(type, scope, complexity);

  return {
    type,
    scope,
    complexity,
    recommended_model_tier,
    split_strategy,
    description: prompt,
  };
}

/** 检测意图类型 */
function detectIntentType(text: string): IntentType {
  let bestType: IntentType = 'unknown';
  let bestScore = 0;

  for (const [type, keywords] of Object.entries(INTENT_KEYWORDS)) {
    const score = keywords.filter(kw => text.includes(kw)).length;
    if (score > bestScore) {
      bestScore = score;
      bestType = type as IntentType;
    }
  }

  return bestType;
}

/** 提取文件路径 */
function extractScope(text: string): string[] {
  const matches: string[] = [];
  let match: RegExpExecArray | null;
  const regex = new RegExp(FILE_PATH_REGEX.source, 'g');
  while ((match = regex.exec(text)) !== null) {
    matches.push(match[1]);
  }
  return matches;
}

/** 评估复杂度 */
function assessComplexity(text: string, scope: string[]): 'low' | 'medium' | 'high' {
  if (HIGH_COMPLEXITY_KEYWORDS.some(kw => text.includes(kw))) return 'high';
  if (MEDIUM_COMPLEXITY_KEYWORDS.some(kw => text.includes(kw)) || scope.length > 3) return 'medium';
  return 'low';
}

/** 根据复杂度推荐模型层级 */
function recommendTier(complexity: 'low' | 'medium' | 'high'): ModelTier {
  switch (complexity) {
    case 'high': return 'tier-3';
    case 'medium': return 'tier-2';
    default: return 'tier-1';
  }
}

/** 推荐拆分策略 */
function recommendSplitStrategy(
  type: IntentType,
  scope: string[],
  complexity: 'low' | 'medium' | 'high',
): SplitStrategy {
  // 如果范围中有多个不同目录层的文件，用 layer-based
  if (scope.length > 0) {
    const dirs = new Set(scope.map(p => p.split('/')[0]));
    if (dirs.size > 1) return 'layer-based';
  }
  // 文件集中或简单情况用 file-based
  if (scope.length > 0) return 'file-based';
  // 复杂的用 feature-based
  return complexity === 'high' ? 'feature-based' : 'file-based';
}
