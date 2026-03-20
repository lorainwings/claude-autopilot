/**
 * 覆盖率报告模块
 *
 * 从任务图和验证结果中汇总覆盖率信息，判断是否满足最低覆盖率阈值，
 * 并输出结构化报告（支持 Markdown 格式）。
 */

import type { TaskGraph } from '../schemas/task-graph.js';
import type { SynthesizedResult } from '../schemas/verifier-result.js';

// ─── 配置接口 ───────────────────────────────────────────

/** 覆盖率报告配置 */
export interface CoverageConfig {
  /** 最低覆盖率阈值 0-100 */
  min_coverage: number;
  /** 是否列出未覆盖文件 */
  include_uncovered: boolean;
  /** 报告格式：summary 仅摘要，detailed 包含详情 */
  format: 'summary' | 'detailed';
}

// ─── 输出接口 ───────────────────────────────────────────

/** 覆盖率报告 */
export interface CoverageReport {
  /** 涉及的文件总数 */
  total_files: number;
  /** 已覆盖的文件数 */
  covered_files: number;
  /** 未覆盖的文件路径列表 */
  uncovered_files: string[];
  /** 覆盖率百分比 0-100 */
  coverage_percentage: number;
  /** 按任务维度的覆盖率 */
  by_task: TaskCoverage[];
  /** 是否达到阈值 */
  meets_threshold: boolean;
  /** 报告生成时间（ISO 8601 格式） */
  timestamp: string;
}

/** 单个任务的覆盖率信息 */
export interface TaskCoverage {
  /** 任务 id */
  task_id: string;
  /** 任务变更的文件列表 */
  files_changed: string[];
  /** 被测试覆盖的文件列表 */
  files_tested: string[];
  /** 是否有对应测试 */
  has_tests: boolean;
  /** 覆盖率分数 0-100 */
  coverage_score: number;
}

// ─── 默认配置 ───────────────────────────────────────────

/** 默认覆盖率配置 */
const DEFAULT_CONFIG: CoverageConfig = {
  min_coverage: 70,
  include_uncovered: true,
  format: 'detailed',
};

// ─── CoverageReporter 类 ────────────────────────────────

/**
 * 覆盖率报告器：从任务图和验证结果中提取覆盖率信息。
 *
 * 覆盖率的计算逻辑：
 * - 从任务图节点的 allowed_paths 提取变更文件
 * - 从验证结果的 test 类型验证器 findings 提取被测文件
 * - 通过交集计算覆盖率
 *
 * 使用方式：
 * ```ts
 * const reporter = new CoverageReporter({ min_coverage: 80 });
 * const report = reporter.generateReport(graph, results);
 * console.log(reporter.formatReport(report));
 * ```
 */
export class CoverageReporter {
  /** 合并后的配置 */
  private readonly config: CoverageConfig;

  /**
   * 构造覆盖率报告器
   * @param config - 可选的部分配置，未指定字段使用默认值
   */
  constructor(config?: Partial<CoverageConfig>) {
    this.config = { ...DEFAULT_CONFIG, ...config };
  }

  /**
   * 从任务图和验证结果生成覆盖率报告
   *
   * @param graph - 任务图（从中提取各任务涉及的文件）
   * @param results - 各任务的综合验证结果
   * @returns 覆盖率报告
   */
  generateReport(
    graph: TaskGraph,
    results: SynthesizedResult[],
  ): CoverageReport {
    // 构建结果查找表：task_id → SynthesizedResult
    const resultMap = new Map<string, SynthesizedResult>();
    for (const r of results) {
      resultMap.set(r.task_id, r);
    }

    // 收集所有变更文件（去重）
    const allChangedFiles = new Set<string>();
    // 收集所有被测试覆盖的文件（去重）
    const allTestedFiles = new Set<string>();

    // 按任务维度计算覆盖率
    const byTask: TaskCoverage[] = [];

    for (const node of graph.nodes) {
      const synthesized = resultMap.get(node.id);

      // 从 allowed_paths 提取变更文件
      const changedFiles = node.allowed_paths.filter(
        p => !p.includes('*'), // 排除 glob 通配符，仅保留具体文件路径
      );

      // 从测试验证器的 findings 中提取被测试的文件路径
      const testedFiles = this.extractTestedFiles(synthesized);

      // 记录到全局集合
      for (const f of changedFiles) {
        allChangedFiles.add(f);
      }
      for (const f of testedFiles) {
        allTestedFiles.add(f);
      }

      // 计算此任务的覆盖率
      const taskCoverage = this.calculateTaskCoverage(
        node.id,
        changedFiles,
        testedFiles,
      );
      byTask.push(taskCoverage);
    }

    // 计算整体覆盖率
    const totalFiles = allChangedFiles.size;
    const coveredFiles = [...allChangedFiles].filter(f =>
      allTestedFiles.has(f),
    ).length;

    const coveragePercentage =
      totalFiles > 0 ? Math.round((coveredFiles / totalFiles) * 100) : 100;

    // 未覆盖文件列表
    const uncoveredFiles = [...allChangedFiles].filter(
      f => !allTestedFiles.has(f),
    );

    return {
      total_files: totalFiles,
      covered_files: coveredFiles,
      uncovered_files: uncoveredFiles,
      coverage_percentage: coveragePercentage,
      by_task: byTask,
      meets_threshold: this.meetsThreshold(coveragePercentage),
      timestamp: new Date().toISOString(),
    };
  }

  /**
   * 计算单个任务的覆盖率
   *
   * @param taskId - 任务 id
   * @param changedFiles - 任务变更的文件列表
   * @param testedFiles - 被测试覆盖的文件列表
   * @returns 任务覆盖率信息
   */
  calculateTaskCoverage(
    taskId: string,
    changedFiles: string[],
    testedFiles: string[],
  ): TaskCoverage {
    const testedSet = new Set(testedFiles);
    const covered = changedFiles.filter(f => testedSet.has(f));
    const hasTests = testedFiles.length > 0;
    const coverageScore =
      changedFiles.length > 0
        ? Math.round((covered.length / changedFiles.length) * 100)
        : 100; // 无变更文件视为全覆盖

    return {
      task_id: taskId,
      files_changed: changedFiles,
      files_tested: testedFiles,
      has_tests: hasTests,
      coverage_score: coverageScore,
    };
  }

  /**
   * 判断覆盖率是否达到阈值
   * @param coverage - 覆盖率百分比 0-100
   * @returns 是否达标
   */
  meetsThreshold(coverage: number): boolean {
    return coverage >= this.config.min_coverage;
  }

  /**
   * 将覆盖率报告格式化为 Markdown
   * @param report - 覆盖率报告
   * @returns Markdown 字符串
   */
  formatReport(report: CoverageReport): string {
    const lines: string[] = [];

    // 标题
    lines.push('## 覆盖率报告');
    lines.push('');

    // 总览
    const statusEmoji = report.meets_threshold ? '✅' : '❌';
    lines.push(
      `**总体覆盖率**: ${statusEmoji} ${report.coverage_percentage}% (阈值: ${this.config.min_coverage}%)`,
    );
    lines.push(
      `**文件统计**: ${report.covered_files}/${report.total_files} 个文件已覆盖`,
    );
    lines.push('');

    // 详细模式：按任务维度输出表格
    if (this.config.format === 'detailed') {
      lines.push('### 任务覆盖率详情');
      lines.push('');
      lines.push('| 任务 ID | 变更文件数 | 测试文件数 | 有测试 | 覆盖率 |');
      lines.push('| --- | --- | --- | --- | --- |');

      for (const task of report.by_task) {
        const hasTestsEmoji = task.has_tests ? '✅' : '❌';
        lines.push(
          `| ${task.task_id} | ${task.files_changed.length} | ${task.files_tested.length} | ${hasTestsEmoji} | ${task.coverage_score}% |`,
        );
      }

      lines.push('');
    }

    // 未覆盖文件列表
    if (this.config.include_uncovered && report.uncovered_files.length > 0) {
      lines.push('### 未覆盖文件');
      lines.push('');
      for (const file of report.uncovered_files) {
        lines.push(`- \`${file}\``);
      }
      lines.push('');
    }

    // 时间戳
    lines.push(`---`);
    lines.push(`生成时间: ${report.timestamp}`);

    return lines.join('\n');
  }

  // ─── 私有辅助方法 ───────────────────────────────────────

  /**
   * 从综合验证结果中提取被测试覆盖的文件路径
   *
   * 提取逻辑：
   * - 仅从 verifier_type 为 'test' 的结果中提取
   * - 从 findings 的 file 字段收集（有 file 字段说明被测试触及）
   * - 从 metadata 的 tested_files 字段收集（如果存在）
   *
   * @param synthesized - 综合验证结果（可能为 undefined）
   * @returns 被测文件路径数组（已去重）
   */
  private extractTestedFiles(
    synthesized: SynthesizedResult | undefined,
  ): string[] {
    if (!synthesized) return [];

    const testedFiles = new Set<string>();

    for (const result of synthesized.results) {
      // 仅从测试验证器中提取
      if (result.verifier_type !== 'test') continue;

      // 从 findings 中提取 file 字段
      for (const finding of result.findings) {
        if (finding.file) {
          testedFiles.add(finding.file);
        }
      }

      // 从 metadata 中提取 tested_files（如果验证器提供了此信息）
      if (
        result.metadata &&
        Array.isArray(result.metadata['tested_files'])
      ) {
        for (const file of result.metadata['tested_files'] as string[]) {
          testedFiles.add(file);
        }
      }
    }

    return [...testedFiles];
  }
}
