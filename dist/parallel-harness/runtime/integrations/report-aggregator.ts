import type { RunResult, GateResult } from "../schemas/ga-schemas";
import type { ExecutionAttestation } from "../workers/execution-proxy";
import { classifyGate } from "../gates/gate-classification";

export interface EvidenceReference {
  type: "gate" | "attestation" | "artifact";
  ref_id: string;
  description: string;
  /** gate 强度分层 */
  strength?: "hard" | "signal";
}

export interface RunReport {
  run_id: string;
  summary: string;
  evidence_refs: EvidenceReference[];
  quality_summary: {
    overall_grade: string;
    gate_summary: string;
    cost_summary: string;
    /** hard gate 通过/总数 */
    hard_gate_summary: string;
    /** signal gate 通过/总数 */
    signal_gate_summary: string;
    /** 上下文占用信息 */
    context_occupancy?: string;
  };
  pr_artifacts?: {
    pr_url?: string;
    summary: string;
  };
  /** grounding 验收矩阵追溯 */
  grounding_evidence?: Array<{
    category: string;
    criterion: string;
    blocking: boolean;
    met: boolean;
  }>;
}

export function aggregateRunEvidence(
  result: RunResult,
  gateResults: GateResult[],
  attestations?: ExecutionAttestation[]
): RunReport {
  const evidenceRefs: EvidenceReference[] = [];

  // 1. Gate evidence refs（带 strength 分层）
  for (const g of gateResults) {
    const classification = classifyGate(g.gate_type);
    evidenceRefs.push({
      type: "gate",
      ref_id: g.gate_type,
      description: `${g.gate_type} [${classification.strength}]: ${g.passed ? "通过" : "失败"}`,
      strength: classification.strength,
    });
  }

  // 2. Attestation evidence refs
  if (attestations) {
    for (const att of attestations) {
      evidenceRefs.push({
        type: "attestation",
        ref_id: att.attempt_id,
        description: `执行证明 ${att.attempt_id}: model=${att.actual_model}, files=${att.modified_paths.length}, violations=${att.sandbox_violations.length}`,
      });
    }
  }

  // 3. 计算 hard/signal gate 统计
  const hardGates = gateResults.filter(g => classifyGate(g.gate_type).is_hard_gate);
  const signalGates = gateResults.filter(g => classifyGate(g.gate_type).is_signal_gate);
  const hardPassed = hardGates.filter(g => g.passed).length;
  const signalPassed = signalGates.filter(g => g.passed).length;

  return {
    run_id: result.run_id,
    summary: `完成 ${result.completed_tasks.length} 个任务，失败 ${result.failed_tasks.length} 个`,
    evidence_refs: evidenceRefs,
    quality_summary: {
      overall_grade: result.quality_report.overall_grade,
      gate_summary: `${gateResults.filter(g => g.passed).length}/${gateResults.length} gates 通过`,
      cost_summary: `总成本: ${result.cost_summary.total_cost}`,
      hard_gate_summary: `${hardPassed}/${hardGates.length} hard gates 通过`,
      signal_gate_summary: `${signalPassed}/${signalGates.length} signal gates 通过`,
    },
    pr_artifacts: result.pr_artifacts,
  };
}
