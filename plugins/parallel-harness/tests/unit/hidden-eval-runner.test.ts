import { describe, it, expect } from "bun:test";
import { compareWithReportedResults, createDefaultHiddenSuites } from "../../runtime/verifiers/hidden-eval-runner";
import type { HiddenEvalResult } from "../../runtime/verifiers/hidden-eval-runner";

function createMockResult(overrides: Partial<HiddenEvalResult> = {}): HiddenEvalResult {
  return {
    suite_id: "test_suite",
    passed: true,
    pass_rate: 0.95,
    total_tests: 20,
    passed_tests: 19,
    failed_tests: 1,
    duration_ms: 100,
    output_snippet: "19 pass, 1 fail",
    is_canary: false,
    ...overrides,
  };
}

describe("compareWithReportedResults", () => {
  it("无偏差时不报告可疑", () => {
    const results = [createMockResult({ pass_rate: 0.95 })];
    const reports = compareWithReportedResults(results, 0.95);
    expect(reports).toHaveLength(0);
  });

  it("偏差超阈值时报告可疑", () => {
    const results = [createMockResult({ pass_rate: 0.7 })];
    const reports = compareWithReportedResults(results, 0.95, 0.1);
    expect(reports).toHaveLength(1);
    expect(reports[0].suspicious).toBe(true);
    expect(reports[0].deviation).toBeCloseTo(0.25, 2);
  });

  it("canary check 始终报告", () => {
    const results = [createMockResult({ pass_rate: 0.95, is_canary: true })];
    const reports = compareWithReportedResults(results, 0.95);
    expect(reports).toHaveLength(1);
    expect(reports[0].suspicious).toBe(false);
  });
});

describe("createDefaultHiddenSuites", () => {
  it("返回默认套件列表", () => {
    const suites = createDefaultHiddenSuites("/tmp/test");
    expect(suites.length).toBeGreaterThan(0);
    expect(suites.some(s => s.canary)).toBe(true);
  });

  it("包含预期的套件 ID", () => {
    const suites = createDefaultHiddenSuites("/tmp/test");
    const ids = suites.map(s => s.suite_id);
    expect(ids).toContain("hidden_unit");
    expect(ids).toContain("hidden_canary");
  });
});
