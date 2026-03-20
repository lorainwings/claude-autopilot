/**
 * CI/PR 集成模块统一导出
 *
 * 提供验证结果到 CI 流水线和 PR 评论的桥梁，包括：
 * - PRReviewer: 将验证结果格式化为 PR 评论
 * - CIRunner: 提供 CI 流水线接口和多格式输出
 * - CoverageReporter: 汇总任务覆盖率信息
 */

// ─── PR 审查 ────────────────────────────────────────────
export type { PRReviewConfig, PRComment, FileComment } from './pr-reviewer.js';
export { PRReviewer } from './pr-reviewer.js';

// ─── CI 运行 ────────────────────────────────────────────
export type { CIConfig, CIResult, TaskCIResult } from './ci-runner.js';
export { CIRunner } from './ci-runner.js';

// ─── 覆盖率报告 ────────────────────────────────────────
export type {
  CoverageConfig,
  CoverageReport,
  TaskCoverage,
} from './coverage-reporter.js';
export { CoverageReporter } from './coverage-reporter.js';
