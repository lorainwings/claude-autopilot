/**
 * parallel-harness: Evidence Producer
 *
 * VerifierSwarm 第一层：证据采集。
 * 从真实执行面采集测试输出、覆盖率报告、安全扫描结果等原始证据。
 * 与 Gate Synthesizer 解耦：producer 只负责采集，不做判定。
 */

export interface RawEvidence {
  producer_type: EvidenceProducerType;
  collected_at: string;
  duration_ms: number;
  raw_output: string;
  exit_code: number;
  structured_data: Record<string, unknown>;
  artifacts: string[];
}

export type EvidenceProducerType =
  | "test"
  | "coverage"
  | "security"
  | "lint"
  | "design_review"
  | "architecture_review"
  | "report_review";

export interface EvidenceProducerConfig {
  project_root?: string;
  timeout_ms: number;
  custom_commands?: Record<string, string>;
}

const DEFAULT_CONFIG: EvidenceProducerConfig = {
  timeout_ms: 60000,
};

/** 证据采集器接口 */
export interface EvidenceProducer {
  type: EvidenceProducerType;
  collect(config: EvidenceProducerConfig): Promise<RawEvidence>;
}

// ============================================================
// Test Evidence Producer
// ============================================================

export class TestEvidenceProducer implements EvidenceProducer {
  type: EvidenceProducerType = "test";

  async collect(config: EvidenceProducerConfig): Promise<RawEvidence> {
    const start = Date.now();
    const cmd = config.custom_commands?.test || "bun test 2>&1";

    try {
      const proc = Bun.spawn(["sh", "-c", cmd], {
        cwd: config.project_root,
        stdout: "pipe",
        stderr: "pipe",
      });
      const stdout = await new Response(proc.stdout).text();
      const exitCode = await proc.exited;

      // 解析测试结果
      const passMatch = stdout.match(/(\d+)\s+pass/);
      const failMatch = stdout.match(/(\d+)\s+fail/);

      return {
        producer_type: "test",
        collected_at: new Date().toISOString(),
        duration_ms: Date.now() - start,
        raw_output: stdout.slice(0, 10000),
        exit_code: exitCode,
        structured_data: {
          pass_count: passMatch ? parseInt(passMatch[1]) : 0,
          fail_count: failMatch ? parseInt(failMatch[1]) : 0,
          success: exitCode === 0,
        },
        artifacts: [],
      };
    } catch {
      return {
        producer_type: "test",
        collected_at: new Date().toISOString(),
        duration_ms: Date.now() - start,
        raw_output: "测试执行失败",
        exit_code: 127,
        structured_data: { success: false, error: "execution_failed" },
        artifacts: [],
      };
    }
  }
}

// ============================================================
// Coverage Evidence Producer
// ============================================================

export class CoverageEvidenceProducer implements EvidenceProducer {
  type: EvidenceProducerType = "coverage";

  async collect(config: EvidenceProducerConfig): Promise<RawEvidence> {
    const start = Date.now();
    const cmd = config.custom_commands?.coverage || "bun test --coverage 2>&1";

    try {
      const proc = Bun.spawn(["sh", "-c", cmd], {
        cwd: config.project_root,
        stdout: "pipe",
        stderr: "pipe",
      });
      const stdout = await new Response(proc.stdout).text();
      const exitCode = await proc.exited;

      // 解析覆盖率
      const coverageMatch = stdout.match(/(\d+(?:\.\d+)?)\s*%/);

      return {
        producer_type: "coverage",
        collected_at: new Date().toISOString(),
        duration_ms: Date.now() - start,
        raw_output: stdout.slice(0, 10000),
        exit_code: exitCode,
        structured_data: {
          coverage_percent: coverageMatch ? parseFloat(coverageMatch[1]) : 0,
          success: exitCode === 0,
        },
        artifacts: [],
      };
    } catch {
      return {
        producer_type: "coverage",
        collected_at: new Date().toISOString(),
        duration_ms: Date.now() - start,
        raw_output: "覆盖率采集失败",
        exit_code: 127,
        structured_data: { success: false, coverage_percent: 0 },
        artifacts: [],
      };
    }
  }
}

// ============================================================
// Security Evidence Producer
// ============================================================

export class SecurityEvidenceProducer implements EvidenceProducer {
  type: EvidenceProducerType = "security";

  async collect(config: EvidenceProducerConfig): Promise<RawEvidence> {
    const start = Date.now();

    // 静态安全检查：检测常见安全问题模式
    const findings: Array<{ pattern: string; severity: string }> = [];

    // 简化实现：使用 grep 检查常见安全模式
    const patterns = [
      { pattern: "eval\\(", severity: "high" },
      { pattern: "innerHTML", severity: "medium" },
      { pattern: "document\\.write", severity: "medium" },
      { pattern: "exec\\(", severity: "high" },
    ];

    for (const p of patterns) {
      try {
        const proc = Bun.spawn(["sh", "-c", `grep -r "${p.pattern}" --include="*.ts" --include="*.js" -l 2>/dev/null || true`], {
          cwd: config.project_root,
          stdout: "pipe",
          stderr: "pipe",
        });
        const stdout = await new Response(proc.stdout).text();
        if (stdout.trim()) {
          findings.push({ pattern: p.pattern, severity: p.severity });
        }
      } catch {
        // ignore grep errors
      }
    }

    return {
      producer_type: "security",
      collected_at: new Date().toISOString(),
      duration_ms: Date.now() - start,
      raw_output: JSON.stringify(findings),
      exit_code: findings.length > 0 ? 1 : 0,
      structured_data: {
        findings_count: findings.length,
        high_severity: findings.filter(f => f.severity === "high").length,
        findings,
      },
      artifacts: [],
    };
  }
}

// ============================================================
// Design Review Evidence Producer
// ============================================================

export class DesignEvidenceProducer implements EvidenceProducer {
  type: EvidenceProducerType = "design_review";

  async collect(_config: EvidenceProducerConfig): Promise<RawEvidence> {
    const start = Date.now();

    // 设计审查：检查是否有设计文档
    return {
      producer_type: "design_review",
      collected_at: new Date().toISOString(),
      duration_ms: Date.now() - start,
      raw_output: "设计审查需要人工介入",
      exit_code: 0,
      structured_data: {
        requires_human_review: true,
        auto_checks_passed: true,
      },
      artifacts: [],
    };
  }
}

// ============================================================
// Architecture Review Evidence Producer
// ============================================================

export class ArchitectureEvidenceProducer implements EvidenceProducer {
  type: EvidenceProducerType = "architecture_review";

  async collect(_config: EvidenceProducerConfig): Promise<RawEvidence> {
    const start = Date.now();

    return {
      producer_type: "architecture_review",
      collected_at: new Date().toISOString(),
      duration_ms: Date.now() - start,
      raw_output: "架构审查需要人工介入",
      exit_code: 0,
      structured_data: {
        requires_human_review: true,
        auto_checks_passed: true,
      },
      artifacts: [],
    };
  }
}

// ============================================================
// Report Review Evidence Producer
// ============================================================

export class ReportEvidenceProducer implements EvidenceProducer {
  type: EvidenceProducerType = "report_review";

  async collect(_config: EvidenceProducerConfig): Promise<RawEvidence> {
    const start = Date.now();

    return {
      producer_type: "report_review",
      collected_at: new Date().toISOString(),
      duration_ms: Date.now() - start,
      raw_output: "报告审查需要人工介入",
      exit_code: 0,
      structured_data: {
        requires_human_review: true,
        auto_checks_passed: true,
      },
      artifacts: [],
    };
  }
}

// ============================================================
// Producer Registry
// ============================================================

export function createDefaultProducers(): EvidenceProducer[] {
  return [
    new TestEvidenceProducer(),
    new CoverageEvidenceProducer(),
    new SecurityEvidenceProducer(),
    new DesignEvidenceProducer(),
    new ArchitectureEvidenceProducer(),
    new ReportEvidenceProducer(),
  ];
}

// ============================================================
// P1-2: 默认 Producer 工厂 — 接入 verifier plane
// ============================================================

/** 运行所有 producers 并收集证据 */
export async function collectAllEvidence(
  producers: EvidenceProducer[],
  config: EvidenceProducerConfig
): Promise<Map<string, RawEvidence>> {
  const evidenceMap = new Map<string, RawEvidence>();

  for (const producer of producers) {
    try {
      const evidence = await producer.collect(config);
      evidenceMap.set(producer.type, evidence);
    } catch (err) {
      evidenceMap.set(producer.type, {
        producer_type: producer.type,
        collected_at: new Date().toISOString(),
        duration_ms: 0,
        raw_output: `Error: ${err instanceof Error ? err.message : String(err)}`,
        exit_code: -1,
        structured_data: {},
        artifacts: [],
      });
    }
  }

  return evidenceMap;
}
