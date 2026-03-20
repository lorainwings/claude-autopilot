/**
 * CI 运行集成模块
 *
 * 提供 CI 流水线接口，将任务图和验证结果转换为 CI 友好的输出格式。
 * 支持 JSON、JUnit XML、Markdown 三种输出格式，
 * 兼容 GitHub Actions、GitLab CI 等主流 CI 平台。
 */

import type { TaskGraph } from '../schemas/task-graph.js';
import type { SynthesizedResult } from '../schemas/verifier-result.js';

// ─── 配置接口 ───────────────────────────────────────────

/** CI 运行配置 */
export interface CIConfig {
  /** CI 提供商 */
  provider: 'github_actions' | 'gitlab_ci' | 'generic';
  /** 在何种严重级别时使 CI 失败 */
  fail_on: 'error' | 'warning' | 'any';
  /** 输出格式 */
  output_format: 'json' | 'junit' | 'markdown';
  /** 输出文件路径 */
  output_path: string;
}

// ─── 输出接口 ───────────────────────────────────────────

/** CI 运行结果 */
export interface CIResult {
  /** 是否通过 */
  success: boolean;
  /** 退出码：0 通过，1 失败 */
  exit_code: number;
  /** 摘要信息 */
  summary: string;
  /** 输出文件路径 */
  output_path?: string;
  /** 总耗时（毫秒） */
  duration_ms: number;
  /** 各任务的 CI 结果 */
  task_results: TaskCIResult[];
}

/** 单个任务的 CI 结果 */
export interface TaskCIResult {
  /** 任务 id */
  task_id: string;
  /** 任务标题 */
  task_title: string;
  /** 验证状态 */
  status: 'pass' | 'fail' | 'warn' | 'skip';
  /** 综合分数 0-100 */
  score: number;
  /** 发现数量 */
  findings_count: number;
  /** 耗时（毫秒） */
  duration_ms: number;
}

// ─── 默认配置 ───────────────────────────────────────────

/** 默认 CI 配置 */
const DEFAULT_CONFIG: CIConfig = {
  provider: 'github_actions',
  fail_on: 'error',
  output_format: 'json',
  output_path: '.parallel-harness/ci-report',
};

// ─── CIRunner 类 ────────────────────────────────────────

/**
 * CI 运行器：将任务图执行结果转换为 CI 友好的格式。
 *
 * 使用方式：
 * ```ts
 * const runner = new CIRunner({ fail_on: 'error', output_format: 'junit' });
 * const result = runner.run(graph, synthesizedResults);
 * if (!result.success) process.exit(result.exit_code);
 * ```
 */
export class CIRunner {
  /** 合并后的配置 */
  private readonly config: CIConfig;

  /**
   * 构造 CI 运行器
   * @param config - 可选的部分配置，未指定字段使用默认值
   */
  constructor(config?: Partial<CIConfig>) {
    this.config = { ...DEFAULT_CONFIG, ...config };
  }

  /**
   * 根据任务图和验证结果执行 CI 判定
   *
   * @param graph - 任务图（用于获取任务标题等元信息）
   * @param results - 各任务的综合验证结果
   * @returns CI 运行结果
   */
  run(graph: TaskGraph, results: SynthesizedResult[]): CIResult {
    const startTime = Date.now();

    // 构建节点 id → 标题映射
    const titleMap = new Map<string, string>();
    for (const node of graph.nodes) {
      titleMap.set(node.id, node.title);
    }

    // 逐任务计算结果
    const taskResults: TaskCIResult[] = results.map(synthesized => {
      const findingsCount = synthesized.results.reduce(
        (sum, r) => sum + r.findings.length,
        0,
      );

      return {
        task_id: synthesized.task_id,
        task_title: titleMap.get(synthesized.task_id) ?? synthesized.task_id,
        status: synthesized.overall_status === 'skip'
          ? 'skip'
          : synthesized.overall_status,
        score: synthesized.overall_score,
        findings_count: findingsCount,
        duration_ms: 0, // 实际运行时可从元数据填充
      };
    });

    // 判定是否失败
    const shouldFail = this.shouldFail(results);
    const exitCode = this.getExitCode(results);
    const duration = Date.now() - startTime;

    // 生成摘要
    const passCount = taskResults.filter(r => r.status === 'pass').length;
    const failCount = taskResults.filter(r => r.status === 'fail').length;
    const warnCount = taskResults.filter(r => r.status === 'warn').length;
    const skipCount = taskResults.filter(r => r.status === 'skip').length;
    const summary = `共 ${taskResults.length} 个任务: ${passCount} 通过, ${failCount} 失败, ${warnCount} 警告, ${skipCount} 跳过`;

    return {
      success: !shouldFail,
      exit_code: exitCode,
      summary,
      output_path: this.config.output_path,
      duration_ms: duration,
      task_results: taskResults,
    };
  }

  /**
   * 将 CIResult 格式化为 JSON 字符串
   * @param result - CI 运行结果
   * @returns 格式化的 JSON（2 空格缩进）
   */
  formatAsJSON(result: CIResult): string {
    return JSON.stringify(result, null, 2);
  }

  /**
   * 将 CIResult 格式化为 JUnit XML
   *
   * 映射规则：
   * - CIResult → testsuite
   * - TaskCIResult → testcase
   * - fail 状态 → failure 元素
   * - warn 状态 → 无 failure（JUnit 不支持 warning，记录到 system-out）
   * - skip 状态 → skipped 元素
   *
   * @param result - CI 运行结果
   * @returns JUnit XML 字符串
   */
  formatAsJUnit(result: CIResult): string {
    const totalTests = result.task_results.length;
    const failures = result.task_results.filter(r => r.status === 'fail').length;
    const skipped = result.task_results.filter(r => r.status === 'skip').length;
    const timeSeconds = (result.duration_ms / 1000).toFixed(3);

    const lines: string[] = [];
    lines.push('<?xml version="1.0" encoding="UTF-8"?>');
    lines.push(
      `<testsuite name="parallel-harness" tests="${totalTests}" failures="${failures}" skipped="${skipped}" time="${timeSeconds}">`,
    );

    for (const task of result.task_results) {
      const taskTime = (task.duration_ms / 1000).toFixed(3);
      const escapedTitle = this.escapeXml(task.task_title);
      const escapedId = this.escapeXml(task.task_id);

      lines.push(
        `  <testcase name="${escapedTitle}" classname="${escapedId}" time="${taskTime}">`,
      );

      if (task.status === 'fail') {
        lines.push(
          `    <failure message="验证失败: 分数 ${task.score}/100, ${task.findings_count} 个发现" />`,
        );
      } else if (task.status === 'skip') {
        lines.push('    <skipped />');
      } else if (task.status === 'warn') {
        lines.push(
          `    <system-out>警告: 分数 ${task.score}/100, ${task.findings_count} 个发现</system-out>`,
        );
      }

      lines.push('  </testcase>');
    }

    lines.push('</testsuite>');
    return lines.join('\n');
  }

  /**
   * 将 CIResult 格式化为 Markdown 表格
   * @param result - CI 运行结果
   * @returns Markdown 字符串
   */
  formatAsMarkdown(result: CIResult): string {
    const lines: string[] = [];

    // 标题和摘要
    lines.push('## CI 验证报告');
    lines.push('');
    lines.push(`**状态**: ${result.success ? '✅ 通过' : '❌ 失败'}`);
    lines.push(`**摘要**: ${result.summary}`);
    lines.push(`**耗时**: ${result.duration_ms}ms`);
    lines.push('');

    // 任务详情表格
    lines.push('| 任务 | 状态 | 分数 | 发现数 |');
    lines.push('| --- | --- | --- | --- |');

    /** 状态 emoji 映射 */
    const statusEmoji: Record<string, string> = {
      pass: '✅',
      fail: '❌',
      warn: '⚠️',
      skip: '⏭️',
    };

    for (const task of result.task_results) {
      const emoji = statusEmoji[task.status] ?? '';
      lines.push(
        `| ${task.task_title} | ${emoji} ${task.status} | ${task.score}/100 | ${task.findings_count} |`,
      );
    }

    return lines.join('\n');
  }

  /**
   * 判断是否应让 CI 失败
   *
   * 判断规则根据 fail_on 配置：
   * - 'error'：存在 fail 状态的结果时失败
   * - 'warning'：存在 fail 或 warn 状态的结果时失败
   * - 'any'：存在任何非 pass 状态的结果时失败（skip 除外）
   *
   * @param results - 各任务的综合验证结果
   * @returns 是否应该失败
   */
  shouldFail(results: SynthesizedResult[]): boolean {
    switch (this.config.fail_on) {
      case 'error':
        return results.some(r => r.overall_status === 'fail');
      case 'warning':
        return results.some(
          r => r.overall_status === 'fail' || r.overall_status === 'warn',
        );
      case 'any':
        return results.some(
          r =>
            r.overall_status !== 'pass' && r.overall_status !== 'skip',
        );
      default:
        return results.some(r => r.overall_status === 'fail');
    }
  }

  /**
   * 获取 CI 退出码
   * @param results - 各任务的综合验证结果
   * @returns 0 表示通过，1 表示失败
   */
  getExitCode(results: SynthesizedResult[]): number {
    return this.shouldFail(results) ? 1 : 0;
  }

  // ─── 私有辅助方法 ───────────────────────────────────────

  /**
   * 对 XML 特殊字符进行转义
   * @param str - 原始字符串
   * @returns 转义后的字符串
   */
  private escapeXml(str: string): string {
    return str
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&apos;');
  }
}
