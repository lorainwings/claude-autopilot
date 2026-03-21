/**
 * parallel-harness: Intent Analyzer
 *
 * 从用户输入中提取任务意图、工作域和风险预估。
 * 这是整个流水线的入口——先理解，再拆解。
 *
 * 来源设计：
 * - claude-task-master: PRD -> 任务分解
 * - superpowers: 低摩擦能力入口
 *
 * 反向增强：
 * - 不只拆任务，还要输出 change scope 和 risk estimation
 */

import type { RiskLevel } from "./task-graph";

// ============================================================
// Intent Analysis 数据结构
// ============================================================

/** 工作域 */
export interface WorkDomain {
  /** 域名称（如 "frontend", "backend", "database", "infra"） */
  name: string;

  /** 涉及的目录或模块 */
  paths: string[];

  /** 预估变更量（行数） */
  estimated_change_lines: number;
}

/** 变更范围 */
export interface ChangeScope {
  /** 涉及的工作域 */
  domains: WorkDomain[];

  /** 新增文件预估 */
  new_files_estimate: number;

  /** 修改文件预估 */
  modified_files_estimate: number;

  /** 是否涉及跨模块依赖 */
  has_cross_module_dependencies: boolean;
}

/** 意图分析结果 */
export interface IntentAnalysis {
  /** 原始用户输入 */
  raw_input: string;

  /** 提取的核心目标 */
  core_goal: string;

  /** 子目标列表 */
  sub_goals: string[];

  /** 变更范围 */
  change_scope: ChangeScope;

  /** 风险预估 */
  risk_estimation: RiskEstimation;

  /** 建议的执行模式 */
  suggested_mode: "parallel" | "serial" | "hybrid";

  /** 分析时间戳 */
  analyzed_at: string;
}

/** 风险预估 */
export interface RiskEstimation {
  /** 总体风险等级 */
  overall: RiskLevel;

  /** 各维度风险 */
  dimensions: {
    /** 冲突风险 */
    conflict_risk: RiskLevel;
    /** 复杂度风险 */
    complexity_risk: RiskLevel;
    /** 集成风险 */
    integration_risk: RiskLevel;
  };

  /** 风险说明 */
  reasoning: string;
}

// ============================================================
// Intent Analyzer 实现
// ============================================================

/**
 * 分析用户意图
 *
 * MVP 阶段：基于结构化规则进行分析
 * 后续阶段：接入 AI 模型做深度意图理解
 */
export function analyzeIntent(input: string, projectContext?: ProjectContext): IntentAnalysis {
  const subGoals = extractSubGoals(input);
  const changeScope = estimateChangeScope(input, projectContext);
  const riskEstimation = estimateRisk(changeScope, subGoals.length);

  return {
    raw_input: input,
    core_goal: extractCoreGoal(input),
    sub_goals: subGoals,
    change_scope: changeScope,
    risk_estimation: riskEstimation,
    suggested_mode: suggestMode(riskEstimation, subGoals.length),
    analyzed_at: new Date().toISOString(),
  };
}

/** 项目上下文（可选，用于更精确的分析） */
export interface ProjectContext {
  /** 项目根目录 */
  root_path: string;

  /** 已知模块列表 */
  known_modules: string[];

  /** 文件结构摘要 */
  file_tree_summary?: string;
}

// ============================================================
// 内部辅助函数
// ============================================================

function extractCoreGoal(input: string): string {
  // MVP: 取第一句话或第一段作为核心目标
  const firstSentence = input.split(/[.。\n]/)[0]?.trim();
  return firstSentence || input.substring(0, 200);
}

function extractSubGoals(input: string): string[] {
  const goals: string[] = [];

  // 检查列表格式（- 或 数字.）
  const listPattern = /^[\s]*[-*]\s+(.+)$/gm;
  const numberedPattern = /^[\s]*\d+[.)]\s+(.+)$/gm;

  let match: RegExpExecArray | null;

  match = listPattern.exec(input);
  while (match !== null) {
    goals.push(match[1].trim());
    match = listPattern.exec(input);
  }

  match = numberedPattern.exec(input);
  while (match !== null) {
    goals.push(match[1].trim());
    match = numberedPattern.exec(input);
  }

  // 如果没有找到列表格式，按段落拆分
  if (goals.length === 0) {
    const paragraphs = input
      .split(/\n\s*\n/)
      .map((p) => p.trim())
      .filter((p) => p.length > 10);
    if (paragraphs.length > 1) {
      return paragraphs;
    }
    // 单段落时，作为单个目标
    return [input.trim()];
  }

  return goals;
}

function estimateChangeScope(
  input: string,
  context?: ProjectContext
): ChangeScope {
  const domains: WorkDomain[] = [];
  const inputLower = input.toLowerCase();

  // 基于关键词检测工作域
  const domainKeywords: Record<string, string[]> = {
    frontend: ["ui", "component", "page", "css", "style", "react", "vue", "html", "前端", "组件", "页面"],
    backend: ["api", "server", "route", "controller", "service", "后端", "接口", "服务"],
    database: ["db", "database", "migration", "schema", "model", "数据库", "迁移"],
    infra: ["ci", "cd", "docker", "deploy", "config", "infra", "部署", "配置"],
    test: ["test", "spec", "e2e", "测试"],
  };

  for (const [domain, keywords] of Object.entries(domainKeywords)) {
    if (keywords.some((kw) => inputLower.includes(kw))) {
      domains.push({
        name: domain,
        paths: context?.known_modules?.filter((m) =>
          m.toLowerCase().includes(domain)
        ) || [],
        estimated_change_lines: 100, // MVP: 默认估值
      });
    }
  }

  // 如果没检测到任何域，默认为 general
  if (domains.length === 0) {
    domains.push({
      name: "general",
      paths: [],
      estimated_change_lines: 50,
    });
  }

  return {
    domains,
    new_files_estimate: Math.ceil(domains.length * 2),
    modified_files_estimate: Math.ceil(domains.length * 3),
    has_cross_module_dependencies: domains.length > 1,
  };
}

function estimateRisk(changeScope: ChangeScope, goalCount: number): RiskEstimation {
  const domainCount = changeScope.domains.length;
  const hasCrossDep = changeScope.has_cross_module_dependencies;

  // 冲突风险
  let conflictRisk: RiskLevel = "low";
  if (domainCount >= 3 || hasCrossDep) conflictRisk = "high";
  else if (domainCount >= 2) conflictRisk = "medium";

  // 复杂度风险
  let complexityRisk: RiskLevel = "low";
  if (goalCount >= 5) complexityRisk = "high";
  else if (goalCount >= 3) complexityRisk = "medium";

  // 集成风险
  let integrationRisk: RiskLevel = "low";
  if (hasCrossDep && goalCount >= 3) integrationRisk = "high";
  else if (hasCrossDep) integrationRisk = "medium";

  // 总体风险
  const riskScores: Record<RiskLevel, number> = {
    low: 1,
    medium: 2,
    high: 3,
    critical: 4,
  };

  const avgScore =
    (riskScores[conflictRisk] +
      riskScores[complexityRisk] +
      riskScores[integrationRisk]) /
    3;

  let overall: RiskLevel = "low";
  if (avgScore >= 3) overall = "high";
  else if (avgScore >= 2) overall = "medium";

  return {
    overall,
    dimensions: {
      conflict_risk: conflictRisk,
      complexity_risk: complexityRisk,
      integration_risk: integrationRisk,
    },
    reasoning: `检测到 ${domainCount} 个工作域, ${goalCount} 个子目标, 跨模块依赖: ${hasCrossDep}`,
  };
}

function suggestMode(
  risk: RiskEstimation,
  goalCount: number
): "parallel" | "serial" | "hybrid" {
  if (risk.overall === "high" || risk.overall === "critical") return "serial";
  if (goalCount <= 1) return "serial";
  if (risk.dimensions.conflict_risk === "high") return "hybrid";
  return "parallel";
}
