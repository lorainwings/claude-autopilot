/**
 * parallel-harness: Hidden Eval Runner
 *
 * 隐藏回归测试套件运行器。
 * worker 不知道 hidden tests 的存在，防止针对性优化/作弊。
 * 支持 canary check 和与自报结果的交叉比对。
 */

export interface HiddenTestSuite {
  suite_id: string;
  name: string;
  test_command: string;
  expected_pass_rate: number;
  canary: boolean;
}

export interface HiddenEvalResult {
  suite_id: string;
  passed: boolean;
  pass_rate: number;
  total_tests: number;
  passed_tests: number;
  failed_tests: number;
  duration_ms: number;
  output_snippet: string;
  is_canary: boolean;
  discrepancy?: DiscrepancyReport;
}

export interface DiscrepancyReport {
  reported_pass_rate: number;
  actual_pass_rate: number;
  deviation: number;
  suspicious: boolean;
  reason: string;
}

export interface HiddenEvalConfig {
  project_root: string;
  suites: HiddenTestSuite[];
  timeout_ms: number;
  discrepancy_threshold: number;
}

const DEFAULT_CONFIG: Partial<HiddenEvalConfig> = {
  timeout_ms: 120000,
  discrepancy_threshold: 0.1,
};

/**
 * 运行隐藏测试套件
 */
export async function runHiddenTests(
  config: HiddenEvalConfig
): Promise<HiddenEvalResult[]> {
  const results: HiddenEvalResult[] = [];
  const mergedConfig = { ...DEFAULT_CONFIG, ...config };

  for (const suite of mergedConfig.suites!) {
    const result = await runSingleSuite(suite, mergedConfig as HiddenEvalConfig);
    results.push(result);
  }

  return results;
}

async function runSingleSuite(
  suite: HiddenTestSuite,
  config: HiddenEvalConfig
): Promise<HiddenEvalResult> {
  const start = Date.now();

  try {
    const proc = Bun.spawn(["sh", "-c", suite.test_command], {
      cwd: config.project_root,
      stdout: "pipe",
      stderr: "pipe",
    });

    const stdout = await new Response(proc.stdout).text();
    const exitCode = await proc.exited;
    const duration = Date.now() - start;

    // 解析结果
    const passMatch = stdout.match(/(\d+)\s+pass/);
    const failMatch = stdout.match(/(\d+)\s+fail/);
    const passed = passMatch ? parseInt(passMatch[1]) : (exitCode === 0 ? 1 : 0);
    const failed = failMatch ? parseInt(failMatch[1]) : (exitCode !== 0 ? 1 : 0);
    const total = passed + failed;
    const passRate = total > 0 ? passed / total : 0;

    return {
      suite_id: suite.suite_id,
      passed: passRate >= suite.expected_pass_rate,
      pass_rate: passRate,
      total_tests: total,
      passed_tests: passed,
      failed_tests: failed,
      duration_ms: duration,
      output_snippet: stdout.slice(0, 2000),
      is_canary: suite.canary,
    };
  } catch {
    return {
      suite_id: suite.suite_id,
      passed: false,
      pass_rate: 0,
      total_tests: 0,
      passed_tests: 0,
      failed_tests: 0,
      duration_ms: Date.now() - start,
      output_snippet: "执行失败",
      is_canary: suite.canary,
    };
  }
}

/**
 * 比对 worker 自报结果与 hidden eval 结果
 */
export function compareWithReportedResults(
  hiddenResults: HiddenEvalResult[],
  reportedPassRate: number,
  discrepancyThreshold: number = 0.1
): DiscrepancyReport[] {
  const reports: DiscrepancyReport[] = [];

  for (const result of hiddenResults) {
    const deviation = Math.abs(result.pass_rate - reportedPassRate);
    const suspicious = deviation > discrepancyThreshold;

    if (suspicious || result.is_canary) {
      reports.push({
        reported_pass_rate: reportedPassRate,
        actual_pass_rate: result.pass_rate,
        deviation,
        suspicious,
        reason: suspicious
          ? `通过率偏差 ${(deviation * 100).toFixed(1)}% 超过阈值 ${(discrepancyThreshold * 100).toFixed(1)}%`
          : `Canary check: 偏差 ${(deviation * 100).toFixed(1)}%`,
      });

      // 将 discrepancy 关联到结果
      result.discrepancy = reports[reports.length - 1];
    }
  }

  return reports;
}

/**
 * 加载默认 hidden test suites（用于项目初始化）
 */
export function createDefaultHiddenSuites(projectRoot: string): HiddenTestSuite[] {
  return [
    {
      suite_id: "hidden_unit",
      name: "隐藏单元测试",
      test_command: "bun test tests/unit/ 2>&1",
      expected_pass_rate: 0.95,
      canary: false,
    },
    {
      suite_id: "hidden_canary",
      name: "Canary 回归测试",
      test_command: "bun test tests/unit/ --bail 1 2>&1",
      expected_pass_rate: 1.0,
      canary: true,
    },
  ];
}

// ============================================================
// P1-2: Hidden eval 接入 release 决策
// ============================================================

/** 执行隐藏评估并生成 gate 级别的结论 */
export async function runHiddenEvalForRelease(
  suites: HiddenTestSuite[],
  reportedResults: { test_count: number; pass_count: number },
  cwd?: string
): Promise<{
  all_passed: boolean;
  has_discrepancy: boolean;
  results: HiddenEvalResult[];
  gate_recommendation: "pass" | "block" | "warn";
}> {
  const config: HiddenEvalConfig = {
    project_root: cwd || process.cwd(),
    suites,
    timeout_ms: 120000,
    discrepancy_threshold: 0.1,
  };

  const results = await runHiddenTests(config);
  let hasDiscrepancy = false;

  // 与报告结果对比
  const reportedPassRate = reportedResults.test_count > 0
    ? reportedResults.pass_count / reportedResults.test_count
    : 0;

  const discrepancies = compareWithReportedResults(
    results,
    reportedPassRate
  );

  if (discrepancies.some(d => d.suspicious)) {
    hasDiscrepancy = true;
  }

  const allPassed = results.every(r => r.passed);

  let gateRecommendation: "pass" | "block" | "warn" = "pass";
  if (!allPassed) {
    gateRecommendation = "block";
  } else if (hasDiscrepancy) {
    gateRecommendation = "warn";
  }

  return {
    all_passed: allPassed,
    has_discrepancy: hasDiscrepancy,
    results,
    gate_recommendation: gateRecommendation,
  };
}
