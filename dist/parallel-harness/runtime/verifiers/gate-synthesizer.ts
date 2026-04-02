/**
 * parallel-harness: Gate Synthesizer
 *
 * VerifierSwarm 第二层：门禁综合判定。
 * 从 Evidence Producer 的原始证据合成最终的 gate pass/fail 判定。
 * 分为 hard gate（阻断）和 signal gate（建议）。
 */

import type { RawEvidence, EvidenceProducerType } from "./evidence-producer";

// ============================================================
// Gate Synthesis 类型
// ============================================================

export type GateSynthesizerType = "hard" | "signal" | "release_readiness";

export interface SynthesisInput {
  evidence: RawEvidence[];
  thresholds: SynthesisThresholds;
}

export interface SynthesisThresholds {
  min_pass_rate: number;
  min_coverage: number;
  max_high_severity_findings: number;
  required_evidence_types: EvidenceProducerType[];
}

export interface SynthesisResult {
  synthesizer_type: GateSynthesizerType;
  passed: boolean;
  blocking: boolean;
  summary: string;
  details: SynthesisDetail[];
  synthesized_at: string;
}

export interface SynthesisDetail {
  evidence_type: EvidenceProducerType;
  passed: boolean;
  reason: string;
}

/** Gate Synthesizer 接口 */
export interface GateSynthesizer {
  type: GateSynthesizerType;
  synthesize(input: SynthesisInput): SynthesisResult;
}

// ============================================================
// 默认阈值
// ============================================================

export const DEFAULT_HARD_THRESHOLDS: SynthesisThresholds = {
  min_pass_rate: 1.0,
  min_coverage: 0.6,
  max_high_severity_findings: 0,
  required_evidence_types: ["test"],
};

export const DEFAULT_SIGNAL_THRESHOLDS: SynthesisThresholds = {
  min_pass_rate: 0.8,
  min_coverage: 0.4,
  max_high_severity_findings: 3,
  required_evidence_types: [],
};

// ============================================================
// Hard Gate Synthesizer — 阻断级
// ============================================================

export class HardGateSynthesizer implements GateSynthesizer {
  type: GateSynthesizerType = "hard";

  synthesize(input: SynthesisInput): SynthesisResult {
    const details: SynthesisDetail[] = [];
    let allPassed = true;

    // 检查必须的证据类型
    for (const reqType of input.thresholds.required_evidence_types) {
      const evidence = input.evidence.find(e => e.producer_type === reqType);
      if (!evidence) {
        details.push({ evidence_type: reqType, passed: false, reason: `缺少 ${reqType} 证据` });
        allPassed = false;
        continue;
      }

      const evalResult = this.evaluateEvidence(evidence, input.thresholds);
      details.push(evalResult);
      if (!evalResult.passed) allPassed = false;
    }

    // 检查额外提供的证据
    for (const evidence of input.evidence) {
      if (input.thresholds.required_evidence_types.includes(evidence.producer_type)) continue;

      const evalResult = this.evaluateEvidence(evidence, input.thresholds);
      details.push(evalResult);
      // 非必须的证据不影响 hard gate 结果
    }

    return {
      synthesizer_type: "hard",
      passed: allPassed,
      blocking: true,
      summary: allPassed
        ? `Hard gate 通过: ${details.filter(d => d.passed).length}/${details.length} 项证据合格`
        : `Hard gate 阻断: ${details.filter(d => !d.passed).length} 项证据不合格`,
      details,
      synthesized_at: new Date().toISOString(),
    };
  }

  private evaluateEvidence(evidence: RawEvidence, thresholds: SynthesisThresholds): SynthesisDetail {
    const data = evidence.structured_data;

    if (evidence.producer_type === "test") {
      const passCount = (data.pass_count as number) || 0;
      const failCount = (data.fail_count as number) || 0;
      const total = passCount + failCount;
      const rate = total > 0 ? passCount / total : 0;
      const passed = rate >= thresholds.min_pass_rate && evidence.exit_code === 0;

      return {
        evidence_type: "test",
        passed,
        reason: passed ? `测试通过率 ${(rate * 100).toFixed(1)}%` : `测试通过率 ${(rate * 100).toFixed(1)}% 低于阈值 ${(thresholds.min_pass_rate * 100).toFixed(1)}%`,
      };
    }

    if (evidence.producer_type === "coverage") {
      const coveragePercent = (data.coverage_percent as number) || 0;
      const passed = coveragePercent / 100 >= thresholds.min_coverage;

      return {
        evidence_type: "coverage",
        passed,
        reason: passed ? `覆盖率 ${coveragePercent}%` : `覆盖率 ${coveragePercent}% 低于阈值 ${thresholds.min_coverage * 100}%`,
      };
    }

    if (evidence.producer_type === "security") {
      const highSeverity = (data.high_severity as number) || 0;
      const passed = highSeverity <= thresholds.max_high_severity_findings;

      return {
        evidence_type: "security",
        passed,
        reason: passed ? `安全检查通过 (高危: ${highSeverity})` : `安全检查失败: ${highSeverity} 个高危发现`,
      };
    }

    // 默认：基于 exit_code
    return {
      evidence_type: evidence.producer_type,
      passed: evidence.exit_code === 0,
      reason: evidence.exit_code === 0 ? `${evidence.producer_type} 检查通过` : `${evidence.producer_type} 检查失败`,
    };
  }
}

// ============================================================
// Signal Gate Synthesizer — 建议级
// ============================================================

export class SignalGateSynthesizer implements GateSynthesizer {
  type: GateSynthesizerType = "signal";

  synthesize(input: SynthesisInput): SynthesisResult {
    const details: SynthesisDetail[] = [];
    let passedCount = 0;

    for (const evidence of input.evidence) {
      const passed = evidence.exit_code === 0;
      details.push({
        evidence_type: evidence.producer_type,
        passed,
        reason: passed ? `${evidence.producer_type} 信号正常` : `${evidence.producer_type} 信号异常`,
      });
      if (passed) passedCount++;
    }

    const rate = input.evidence.length > 0 ? passedCount / input.evidence.length : 1;
    const overallPassed = rate >= input.thresholds.min_pass_rate;

    return {
      synthesizer_type: "signal",
      passed: overallPassed,
      blocking: false,
      summary: `Signal gate: ${passedCount}/${input.evidence.length} 项信号正常 (${(rate * 100).toFixed(1)}%)`,
      details,
      synthesized_at: new Date().toISOString(),
    };
  }
}

// ============================================================
// Release Readiness Synthesizer — 发布就绪综合判定
// ============================================================

export class ReleaseReadinessSynthesizer implements GateSynthesizer {
  type: GateSynthesizerType = "release_readiness";

  synthesize(input: SynthesisInput): SynthesisResult {
    const details: SynthesisDetail[] = [];
    let criticalFailures = 0;

    // 测试必须通过
    const testEvidence = input.evidence.find(e => e.producer_type === "test");
    if (!testEvidence || testEvidence.exit_code !== 0) {
      details.push({ evidence_type: "test", passed: false, reason: "测试未通过，不可发布" });
      criticalFailures++;
    } else {
      details.push({ evidence_type: "test", passed: true, reason: "测试通过" });
    }

    // 安全检查无高危
    const secEvidence = input.evidence.find(e => e.producer_type === "security");
    if (secEvidence) {
      const highSeverity = (secEvidence.structured_data.high_severity as number) || 0;
      if (highSeverity > 0) {
        details.push({ evidence_type: "security", passed: false, reason: `${highSeverity} 个高危安全发现` });
        criticalFailures++;
      } else {
        details.push({ evidence_type: "security", passed: true, reason: "无高危安全发现" });
      }
    }

    // 其他证据作为 signal
    for (const e of input.evidence) {
      if (e.producer_type === "test" || e.producer_type === "security") continue;
      details.push({
        evidence_type: e.producer_type,
        passed: e.exit_code === 0,
        reason: e.exit_code === 0 ? `${e.producer_type} 正常` : `${e.producer_type} 异常（非阻断）`,
      });
    }

    return {
      synthesizer_type: "release_readiness",
      passed: criticalFailures === 0,
      blocking: true,
      summary: criticalFailures === 0
        ? `发布就绪: 所有关键检查通过`
        : `发布阻断: ${criticalFailures} 项关键检查失败`,
      details,
      synthesized_at: new Date().toISOString(),
    };
  }
}
