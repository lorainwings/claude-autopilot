import { describe, it, expect } from "bun:test";
import type { RawEvidence } from "../../runtime/verifiers/evidence-producer";
import {
  HardGateSynthesizer,
  SignalGateSynthesizer,
  ReleaseReadinessSynthesizer,
  DEFAULT_HARD_THRESHOLDS,
  DEFAULT_SIGNAL_THRESHOLDS,
} from "../../runtime/verifiers/gate-synthesizer";

function createTestEvidence(overrides: Partial<RawEvidence> = {}): RawEvidence {
  return {
    producer_type: "test",
    collected_at: new Date().toISOString(),
    duration_ms: 100,
    raw_output: "10 pass, 0 fail",
    exit_code: 0,
    structured_data: { pass_count: 10, fail_count: 0, success: true },
    artifacts: [],
    ...overrides,
  };
}

function createSecurityEvidence(highSeverity = 0): RawEvidence {
  return {
    producer_type: "security",
    collected_at: new Date().toISOString(),
    duration_ms: 50,
    raw_output: "security scan",
    exit_code: highSeverity > 0 ? 1 : 0,
    structured_data: { findings_count: highSeverity, high_severity: highSeverity, findings: [] },
    artifacts: [],
  };
}

function createCoverageEvidence(percent: number): RawEvidence {
  return {
    producer_type: "coverage",
    collected_at: new Date().toISOString(),
    duration_ms: 200,
    raw_output: `coverage: ${percent}%`,
    exit_code: 0,
    structured_data: { coverage_percent: percent, success: true },
    artifacts: [],
  };
}

describe("HardGateSynthesizer", () => {
  const synthesizer = new HardGateSynthesizer();

  it("所有必须证据通过时 hard gate 通过", () => {
    const result = synthesizer.synthesize({
      evidence: [createTestEvidence()],
      thresholds: DEFAULT_HARD_THRESHOLDS,
    });
    expect(result.passed).toBe(true);
    expect(result.blocking).toBe(true);
    expect(result.synthesizer_type).toBe("hard");
  });

  it("测试失败时 hard gate 阻断", () => {
    const result = synthesizer.synthesize({
      evidence: [createTestEvidence({
        exit_code: 1,
        structured_data: { pass_count: 8, fail_count: 2, success: false },
      })],
      thresholds: DEFAULT_HARD_THRESHOLDS,
    });
    expect(result.passed).toBe(false);
    expect(result.summary).toContain("阻断");
  });

  it("缺少必须证据时阻断", () => {
    const result = synthesizer.synthesize({
      evidence: [], // 没有 test 证据
      thresholds: DEFAULT_HARD_THRESHOLDS,
    });
    expect(result.passed).toBe(false);
  });

  it("覆盖率低于阈值时相应 detail 失败", () => {
    const result = synthesizer.synthesize({
      evidence: [
        createTestEvidence(),
        createCoverageEvidence(30), // 30% < 60%
      ],
      thresholds: { ...DEFAULT_HARD_THRESHOLDS, required_evidence_types: ["test", "coverage"] },
    });
    expect(result.passed).toBe(false);
    const coverageDetail = result.details.find(d => d.evidence_type === "coverage");
    expect(coverageDetail?.passed).toBe(false);
  });

  it("安全检查有高危发现时失败", () => {
    const result = synthesizer.synthesize({
      evidence: [
        createTestEvidence(),
        createSecurityEvidence(2),
      ],
      thresholds: { ...DEFAULT_HARD_THRESHOLDS, required_evidence_types: ["test", "security"] },
    });
    expect(result.passed).toBe(false);
  });
});

describe("SignalGateSynthesizer", () => {
  const synthesizer = new SignalGateSynthesizer();

  it("所有信号正常时通过", () => {
    const result = synthesizer.synthesize({
      evidence: [createTestEvidence(), createCoverageEvidence(80)],
      thresholds: DEFAULT_SIGNAL_THRESHOLDS,
    });
    expect(result.passed).toBe(true);
    expect(result.blocking).toBe(false);
  });

  it("部分信号异常但通过率达标时仍通过", () => {
    const result = synthesizer.synthesize({
      evidence: [
        createTestEvidence(),
        createCoverageEvidence(80),
        createTestEvidence({ exit_code: 1, structured_data: { success: false } }),
        createTestEvidence(),
        createTestEvidence(),
      ],
      thresholds: DEFAULT_SIGNAL_THRESHOLDS, // min_pass_rate: 0.8
    });
    expect(result.passed).toBe(true);
  });

  it("空证据时默认通过", () => {
    const result = synthesizer.synthesize({
      evidence: [],
      thresholds: DEFAULT_SIGNAL_THRESHOLDS,
    });
    expect(result.passed).toBe(true);
  });
});

describe("ReleaseReadinessSynthesizer", () => {
  const synthesizer = new ReleaseReadinessSynthesizer();

  it("测试通过 + 无安全问题时就绪", () => {
    const result = synthesizer.synthesize({
      evidence: [createTestEvidence(), createSecurityEvidence(0)],
      thresholds: DEFAULT_HARD_THRESHOLDS,
    });
    expect(result.passed).toBe(true);
    expect(result.blocking).toBe(true);
    expect(result.summary).toContain("发布就绪");
  });

  it("测试失败时不就绪", () => {
    const result = synthesizer.synthesize({
      evidence: [
        createTestEvidence({ exit_code: 1, structured_data: { success: false } }),
        createSecurityEvidence(0),
      ],
      thresholds: DEFAULT_HARD_THRESHOLDS,
    });
    expect(result.passed).toBe(false);
    expect(result.summary).toContain("阻断");
  });

  it("安全高危时不就绪", () => {
    const result = synthesizer.synthesize({
      evidence: [createTestEvidence(), createSecurityEvidence(3)],
      thresholds: DEFAULT_HARD_THRESHOLDS,
    });
    expect(result.passed).toBe(false);
  });

  it("无测试证据时不就绪", () => {
    const result = synthesizer.synthesize({
      evidence: [createSecurityEvidence(0)],
      thresholds: DEFAULT_HARD_THRESHOLDS,
    });
    expect(result.passed).toBe(false);
  });
});
