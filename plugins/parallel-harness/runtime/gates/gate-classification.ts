import type { GateResult } from "../schemas/ga-schemas";

export interface GateClassification {
  gate_type: string;
  is_hard_gate: boolean;
  is_signal_gate: boolean;
  requires_evidence: boolean;
}

export function classifyGate(gateType: string): GateClassification {
  const hardGates = ["test", "lint", "type_check", "security_scan"];
  const signalGates = ["review", "documentation", "performance"];

  return {
    gate_type: gateType,
    is_hard_gate: hardGates.includes(gateType),
    is_signal_gate: signalGates.includes(gateType),
    requires_evidence: true,
  };
}

export interface EvidenceBundle {
  gate_type: string;
  evidence_refs: string[];
  attestation_hash: string;
  timestamp: string;
}

export function createEvidenceBundle(
  gateResult: GateResult,
  evidenceRefs: string[]
): EvidenceBundle {
  return {
    gate_type: gateResult.gate_type,
    evidence_refs: evidenceRefs,
    attestation_hash: `hash_${Date.now()}`,
    timestamp: new Date().toISOString(),
  };
}
