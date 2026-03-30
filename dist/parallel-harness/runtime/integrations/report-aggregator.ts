import type { RunResult, GateResult } from "../schemas/ga-schemas";

export interface EvidenceReference {
  type: "gate" | "attestation" | "artifact";
  ref_id: string;
  description: string;
}

export interface RunReport {
  run_id: string;
  summary: string;
  evidence_refs: EvidenceReference[];
  quality_summary: {
    overall_grade: string;
    gate_summary: string;
    cost_summary: string;
  };
  pr_artifacts?: {
    pr_url?: string;
    summary: string;
  };
}

export function aggregateRunEvidence(
  result: RunResult,
  gateResults: GateResult[]
): RunReport {
  const evidenceRefs: EvidenceReference[] = gateResults.map(g => ({
    type: "gate" as const,
    ref_id: g.gate_type,
    description: `${g.gate_type}: ${g.passed ? "通过" : "失败"}`,
  }));

  return {
    run_id: result.run_id,
    summary: `完成 ${result.completed_tasks.length} 个任务，失败 ${result.failed_tasks.length} 个`,
    evidence_refs: evidenceRefs,
    quality_summary: {
      overall_grade: result.quality_report.overall_grade,
      gate_summary: `${gateResults.filter(g => g.passed).length}/${gateResults.length} gates 通过`,
      cost_summary: `总成本: ${result.cost_summary.total_cost}`,
    },
    pr_artifacts: result.pr_artifacts,
  };
}
