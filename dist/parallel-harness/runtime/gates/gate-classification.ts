import type { GateResult } from "../schemas/ga-schemas";

export type GateStrength = "hard" | "signal";

export interface GateClassification {
  gate_type: string;
  strength: GateStrength;
  is_hard_gate: boolean;
  is_signal_gate: boolean;
  requires_evidence: boolean;
  /** 当前可信度描述 */
  confidence_note: string;
}

/**
 * 将 gate type 分类为 hard gate 或 signal gate。
 *
 * Hard gates: 拥有真实工程检测能力（运行 bun test、tsc --noEmit 等），失败会阻断。
 * Signal gates: 基于启发式或代理检测，失败只产生风险信号，不阻断。
 */
export function classifyGate(gateType: string): GateClassification {
  const hardGates: Record<string, string> = {
    test: "基于真实 bun test 执行",
    lint_type: "基于真实 tsc --noEmit / ruff check 执行",
    policy: "基于 PolicyEngine 规则评估",
    security: "基于敏感文件路径模式检测",
  };

  const signalGates: Record<string, string> = {
    review: "基于输出长度/文件数/测试对应关系的启发式检查",
    coverage: "基于 bun test --coverage 输出解析（可能降级为启发式）",
    documentation: "基于文件路径关键词匹配",
    perf: "基于 token 用量和执行时间阈值",
    release_readiness: "基于任务完成状态统计",
  };

  const isHard = gateType in hardGates;
  const isSignal = gateType in signalGates;

  return {
    gate_type: gateType,
    strength: isHard ? "hard" : "signal",
    is_hard_gate: isHard,
    is_signal_gate: isSignal || !isHard,
    requires_evidence: true,
    confidence_note: hardGates[gateType] || signalGates[gateType] || "未知 gate 类型",
  };
}

/**
 * 判断 gate 结果是否应该真正阻断（hard gate 失败才阻断）
 */
export function shouldBlock(gateResult: GateResult): boolean {
  const classification = classifyGate(gateResult.gate_type);
  return classification.is_hard_gate && gateResult.blocking && !gateResult.passed;
}

export interface EvidenceBundle {
  gate_type: string;
  strength: GateStrength;
  evidence_refs: string[];
  attestation_hash: string;
  timestamp: string;
}

export function createEvidenceBundle(
  gateResult: GateResult,
  evidenceRefs: string[]
): EvidenceBundle {
  const classification = classifyGate(gateResult.gate_type);
  return {
    gate_type: gateResult.gate_type,
    strength: classification.strength,
    evidence_refs: evidenceRefs,
    attestation_hash: `hash_${Date.now()}`,
    timestamp: new Date().toISOString(),
  };
}
