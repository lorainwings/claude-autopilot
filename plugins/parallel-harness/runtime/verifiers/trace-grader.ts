/**
 * parallel-harness: Trace Grader (P2-5)
 *
 * 对 run trace 做 grading、对失败 run 生成根因报告、
 * 对高价值成功 run 提炼 playbook。
 */

/** Trace 评分维度 */
export interface TraceGradingDimension {
  dimension: string;
  score: number; // 0-100
  weight: number;
  findings: string[];
}

/** Trace 评分结果 */
export interface TraceGrade {
  run_id: string;
  overall_score: number;
  grade: "A" | "B" | "C" | "D" | "F";
  dimensions: TraceGradingDimension[];
  timestamp: string;
}

/** 失败根因报告 */
export interface RootCauseReport {
  run_id: string;
  root_causes: Array<{
    cause_id: string;
    category: "config" | "code" | "dependency" | "environment" | "timeout" | "budget" | "unknown";
    description: string;
    evidence: string[];
    suggested_fix?: string;
  }>;
  contributing_factors: string[];
  prevention_suggestions: string[];
}

/** 成功 Run Playbook */
export interface RunPlaybook {
  run_id: string;
  title: string;
  pattern_type: "implementation" | "debugging" | "refactoring" | "testing" | "deployment";
  steps: Array<{
    step_number: number;
    description: string;
    tools_used: string[];
    key_decisions: string[];
  }>;
  reusable_insights: string[];
  applicable_scenarios: string[];
}

/** Trace 评分输入 */
export interface TraceGradingInput {
  run_id: string;
  total_tasks: number;
  completed_tasks: number;
  failed_tasks: number;
  total_retries: number;
  total_duration_ms: number;
  budget_utilization: number;
  gate_pass_rate: number;
  policy_violations: number;
  model_escalations: number;
}

/** 对 run trace 进行评分 */
export function gradeTrace(input: TraceGradingInput): TraceGrade {
  const dimensions: TraceGradingDimension[] = [];

  // 完成率
  const completionRate = input.total_tasks > 0
    ? (input.completed_tasks / input.total_tasks) * 100
    : 0;
  dimensions.push({
    dimension: "completion_rate",
    score: completionRate,
    weight: 0.3,
    findings: completionRate < 100
      ? [`${input.failed_tasks} 个任务失败`]
      : ["所有任务完成"],
  });

  // 效率 (重试率低 = 高效)
  const retryRate = input.total_tasks > 0
    ? Math.max(0, 100 - (input.total_retries / input.total_tasks) * 50)
    : 100;
  dimensions.push({
    dimension: "efficiency",
    score: retryRate,
    weight: 0.2,
    findings: input.total_retries > 0
      ? [`${input.total_retries} 次重试`]
      : ["零重试"],
  });

  // 预算利用率 (0.3-0.7 为最佳)
  const budgetScore = input.budget_utilization <= 0.7
    ? Math.min(100, input.budget_utilization / 0.7 * 100)
    : Math.max(0, 100 - (input.budget_utilization - 0.7) / 0.3 * 50);
  dimensions.push({
    dimension: "budget_efficiency",
    score: budgetScore,
    weight: 0.15,
    findings: [`预算利用率: ${(input.budget_utilization * 100).toFixed(1)}%`],
  });

  // 质量 gate 通过率
  const qualityScore = input.gate_pass_rate * 100;
  dimensions.push({
    dimension: "quality",
    score: qualityScore,
    weight: 0.25,
    findings: input.policy_violations > 0
      ? [`${input.policy_violations} 个策略违规`]
      : ["无策略违规"],
  });

  // 合规性
  const complianceScore = Math.max(0, 100 - input.policy_violations * 20);
  dimensions.push({
    dimension: "compliance",
    score: complianceScore,
    weight: 0.1,
    findings: input.model_escalations > 0
      ? [`${input.model_escalations} 次模型升级`]
      : ["无模型升级"],
  });

  // 加权总分
  const overallScore = dimensions.reduce(
    (sum, d) => sum + d.score * d.weight,
    0
  );

  const grade = overallScore >= 90 ? "A"
    : overallScore >= 75 ? "B"
    : overallScore >= 60 ? "C"
    : overallScore >= 40 ? "D"
    : "F";

  return {
    run_id: input.run_id,
    overall_score: Math.round(overallScore * 10) / 10,
    grade,
    dimensions,
    timestamp: new Date().toISOString(),
  };
}

/** 分析失败 run 的根因 */
export function analyzeRootCause(
  runId: string,
  failedTasks: Array<{
    task_id: string;
    failure_class: string;
    message: string;
    attempts: number;
  }>,
  policyViolations: Array<{ message: string }>,
): RootCauseReport {
  const rootCauses: RootCauseReport["root_causes"] = [];
  const contributingFactors: string[] = [];

  // 分析失败模式
  const failureClassCounts = new Map<string, number>();
  for (const task of failedTasks) {
    failureClassCounts.set(
      task.failure_class,
      (failureClassCounts.get(task.failure_class) || 0) + 1
    );
  }

  for (const [cls, count] of failureClassCounts) {
    const category = mapFailureClassToCategory(cls);
    rootCauses.push({
      cause_id: `rc_${cls}`,
      category,
      description: `${count} 个任务因 ${cls} 失败`,
      evidence: failedTasks
        .filter(t => t.failure_class === cls)
        .map(t => `${t.task_id}: ${t.message}`),
    });
  }

  if (policyViolations.length > 0) {
    contributingFactors.push(`${policyViolations.length} 个策略违规`);
  }

  const highRetryTasks = failedTasks.filter(t => t.attempts > 2);
  if (highRetryTasks.length > 0) {
    contributingFactors.push(`${highRetryTasks.length} 个任务重试超过 2 次`);
  }

  return {
    run_id: runId,
    root_causes: rootCauses,
    contributing_factors: contributingFactors,
    prevention_suggestions: generatePreventionSuggestions(rootCauses),
  };
}

function mapFailureClassToCategory(cls: string): RootCauseReport["root_causes"][0]["category"] {
  const mapping: Record<string, RootCauseReport["root_causes"][0]["category"]> = {
    transient_tool_failure: "environment",
    permanent_policy_failure: "config",
    ownership_conflict: "config",
    budget_exhausted: "budget",
    verification_failed: "code",
    timeout: "timeout",
  };
  return mapping[cls] || "unknown";
}

function generatePreventionSuggestions(
  rootCauses: RootCauseReport["root_causes"]
): string[] {
  const suggestions: string[] = [];
  const categories = new Set(rootCauses.map(rc => rc.category));

  if (categories.has("budget")) suggestions.push("增加预算上限或优化 token 使用");
  if (categories.has("timeout")) suggestions.push("增加超时时间或拆分大任务");
  if (categories.has("config")) suggestions.push("检查策略配置和所有权规划");
  if (categories.has("code")) suggestions.push("增加测试覆盖率和代码审查");
  if (categories.has("environment")) suggestions.push("检查运行环境稳定性");

  return suggestions;
}

/** 从成功 run 提炼 playbook */
export function extractPlaybook(
  runId: string,
  completedTasks: Array<{
    task_id: string;
    goal: string;
    model_tier: string;
    duration_ms: number;
    modified_paths: string[];
  }>
): RunPlaybook {
  const steps = completedTasks.map((task, i) => ({
    step_number: i + 1,
    description: task.goal,
    tools_used: [`model:${task.model_tier}`],
    key_decisions: task.modified_paths.length > 5
      ? ["大范围修改，考虑拆分"]
      : [],
  }));

  return {
    run_id: runId,
    title: `Run ${runId} Playbook`,
    pattern_type: "implementation",
    steps,
    reusable_insights: [
      `共 ${completedTasks.length} 个任务`,
      `总修改 ${completedTasks.reduce((sum, t) => sum + t.modified_paths.length, 0)} 个文件`,
    ],
    applicable_scenarios: ["similar implementation tasks"],
  };
}
