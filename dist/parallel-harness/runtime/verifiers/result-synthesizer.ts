/**
 * result-synthesizer.ts — 验证结果综合器
 *
 * 将多个验证器的 VerifierResult 合并为一份 SynthesizedResult：
 *   - 综合状态判定（任一 fail → fail，任一 warn → warn，否则 pass）
 *   - 加权总分计算（test: 30%, review: 25%, security: 30%, perf: 15%）
 *   - 摘要文本生成
 *   - 阻断级别 findings 提取
 */

import type {
  VerifierType,
  VerifierResult,
  SynthesizedResult,
  Finding,
} from '../schemas';
import { createSynthesizedResult } from '../schemas';

// ---------------------------------------------------------------------------
// 权重配置
// ---------------------------------------------------------------------------

/** 各验证器类型的权重 */
const VERIFIER_WEIGHTS: Record<VerifierType, number> = {
  test: 0.30,
  review: 0.25,
  security: 0.30,
  perf: 0.15,
};

// ---------------------------------------------------------------------------
// ResultSynthesizer
// ---------------------------------------------------------------------------

export class ResultSynthesizer {
  /**
   * 综合多个验证器结果
   * @param results 各验证器的结果列表
   * @returns 综合后的结果
   */
  synthesize(results: VerifierResult[]): SynthesizedResult {
    // 提取 task_id（取第一个结果的，所有结果应属于同一个 task）
    const taskId = results[0]?.task_id ?? 'unknown';

    // 综合状态：任一 fail → fail，任一 warn → warn，否则 pass
    const overallStatus = this.determineOverallStatus(results);

    // 加权总分
    const overallScore = this.getWeightedScore(results);

    // 摘要文本
    const summary = this.generateSummary(results);

    return createSynthesizedResult({
      task_id: taskId,
      results,
      overall_status: overallStatus,
      overall_score: overallScore,
      summary,
      timestamp: new Date().toISOString(),
    });
  }

  /**
   * 计算加权总分
   * 权重: test(30%) + review(25%) + security(30%) + perf(15%)
   * 如果某类验证器缺失结果，将其权重按比例分配给其他验证器
   */
  getWeightedScore(results: VerifierResult[]): number {
    if (results.length === 0) return 0;

    // 按类型分组（同类型取最低分）
    const scoreByType = new Map<VerifierType, number>();
    for (const r of results) {
      const existing = scoreByType.get(r.verifier_type);
      if (existing === undefined || r.score < existing) {
        scoreByType.set(r.verifier_type, r.score);
      }
    }

    // 计算实际参与的权重总和
    let activeWeightSum = 0;
    for (const [type] of scoreByType) {
      activeWeightSum += VERIFIER_WEIGHTS[type] ?? 0;
    }

    // 权重归一化后加权求和
    if (activeWeightSum === 0) return 0;

    let weightedScore = 0;
    for (const [type, score] of scoreByType) {
      const normalizedWeight = (VERIFIER_WEIGHTS[type] ?? 0) / activeWeightSum;
      weightedScore += score * normalizedWeight;
    }

    return Math.round(weightedScore * 100) / 100;
  }

  /**
   * 生成中文摘要文本
   */
  generateSummary(results: VerifierResult[]): string {
    if (results.length === 0) return '无验证结果';

    const parts: string[] = [];

    // 汇总各验证器状态
    for (const r of results) {
      const typeLabel = VERIFIER_TYPE_LABELS[r.verifier_type] ?? r.verifier_type;
      const statusLabel = STATUS_LABELS[r.status] ?? r.status;
      const findingCount = r.findings.length;

      parts.push(
        `${typeLabel}: ${statusLabel} (${r.score}分, ${findingCount}个发现)`,
      );
    }

    // 统计阻断级别
    const blockingFindings = this.getBlockingFindings(results);
    if (blockingFindings.length > 0) {
      parts.push(`共 ${blockingFindings.length} 个阻断级别问题需要修复`);
    }

    // 总体评价
    const overallStatus = this.determineOverallStatus(results);
    const overallScore = this.getWeightedScore(results);
    parts.unshift(`综合评分: ${overallScore}分 — ${STATUS_LABELS[overallStatus]}`);

    return parts.join('\n');
  }

  /**
   * 获取所有阻断级别（error）的 findings
   */
  getBlockingFindings(results: VerifierResult[]): Finding[] {
    const blocking: Finding[] = [];
    for (const r of results) {
      for (const f of r.findings) {
        if (f.severity === 'error') {
          blocking.push(f);
        }
      }
    }
    return blocking;
  }

  // -----------------------------------------------------------------------
  // 私有方法
  // -----------------------------------------------------------------------

  /**
   * 确定综合状态
   * 优先级: fail > warn > pass
   */
  private determineOverallStatus(
    results: VerifierResult[],
  ): 'pass' | 'fail' | 'warn' {
    let hasFail = false;
    let hasWarn = false;

    for (const r of results) {
      if (r.status === 'fail') hasFail = true;
      if (r.status === 'warn') hasWarn = true;
    }

    if (hasFail) return 'fail';
    if (hasWarn) return 'warn';
    return 'pass';
  }
}

// ---------------------------------------------------------------------------
// 标签映射
// ---------------------------------------------------------------------------

/** 验证器类型中文标签 */
const VERIFIER_TYPE_LABELS: Record<VerifierType, string> = {
  test: '测试验证',
  review: '代码审查',
  security: '安全扫描',
  perf: '性能检测',
};

/** 状态中文标签 */
const STATUS_LABELS: Record<string, string> = {
  pass: '通过',
  fail: '未通过',
  warn: '有警告',
  skip: '跳过',
};
