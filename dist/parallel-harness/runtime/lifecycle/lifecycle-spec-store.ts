/**
 * parallel-harness: Lifecycle Spec Store
 *
 * 统一生命周期真相源。覆盖产品开发全流程 8 个阶段的规格存储。
 * 每个阶段有结构化 schema、状态、所有者、阻塞项和证据引用。
 */

// ============================================================
// Lifecycle Phase 枚举与类型
// ============================================================

export type LifecyclePhase =
  | "requirement"
  | "product_design"
  | "ui_design"
  | "tech_plan"
  | "architecture"
  | "implementation"
  | "testing"
  | "reporting";

export type PhaseStatus = "not_started" | "in_progress" | "completed" | "blocked" | "skipped";

export interface PhaseArtifact {
  artifact_id: string;
  name: string;
  type: string;
  path?: string;
  created_at: string;
  verified: boolean;
}

export interface PhaseGateConfig {
  gate_type: string;
  blocking: boolean;
  required: boolean;
}

export interface PhaseTransitionRecord {
  from: LifecyclePhase;
  to: LifecyclePhase;
  timestamp: string;
  reason: string;
  approved_by?: string;
}

export interface PhaseSpec {
  phase: LifecyclePhase;
  status: PhaseStatus;
  owner?: string;
  required_artifacts: string[];
  entry_criteria: string[];
  exit_criteria: string[];
  gates: PhaseGateConfig[];
  evidence_refs: string[];
  blockers: string[];
  artifacts: PhaseArtifact[];
  started_at?: string;
  completed_at?: string;
}

// ============================================================
// 阶段顺序与默认配置
// ============================================================

export const PHASE_ORDER: LifecyclePhase[] = [
  "requirement",
  "product_design",
  "ui_design",
  "tech_plan",
  "architecture",
  "implementation",
  "testing",
  "reporting",
];

const DEFAULT_PHASE_SPECS: Record<LifecyclePhase, Omit<PhaseSpec, "status" | "artifacts" | "evidence_refs" | "blockers">> = {
  requirement: {
    phase: "requirement",
    required_artifacts: ["requirement_spec"],
    entry_criteria: ["run_request_received"],
    exit_criteria: ["requirement_spec_approved", "acceptance_matrix_defined"],
    gates: [{ gate_type: "review", blocking: true, required: true }],
  },
  product_design: {
    phase: "product_design",
    required_artifacts: ["product_design_spec"],
    entry_criteria: ["requirement_completed"],
    exit_criteria: ["product_design_approved"],
    gates: [{ gate_type: "design", blocking: true, required: true }],
  },
  ui_design: {
    phase: "ui_design",
    required_artifacts: ["ui_design_spec"],
    entry_criteria: ["product_design_completed"],
    exit_criteria: ["ui_design_approved"],
    gates: [{ gate_type: "design", blocking: false, required: false }],
  },
  tech_plan: {
    phase: "tech_plan",
    required_artifacts: ["tech_plan_doc"],
    entry_criteria: ["product_design_completed"],
    exit_criteria: ["tech_plan_approved"],
    gates: [{ gate_type: "architecture", blocking: true, required: true }],
  },
  architecture: {
    phase: "architecture",
    required_artifacts: ["architecture_spec"],
    entry_criteria: ["tech_plan_completed"],
    exit_criteria: ["architecture_reviewed", "interface_contracts_defined"],
    gates: [{ gate_type: "architecture", blocking: true, required: true }],
  },
  implementation: {
    phase: "implementation",
    required_artifacts: ["source_code", "unit_tests"],
    entry_criteria: ["architecture_completed"],
    exit_criteria: ["code_reviewed", "tests_passing", "lint_clean"],
    gates: [
      { gate_type: "test", blocking: true, required: true },
      { gate_type: "lint_type", blocking: true, required: true },
      { gate_type: "review", blocking: false, required: true },
      { gate_type: "security", blocking: true, required: true },
    ],
  },
  testing: {
    phase: "testing",
    required_artifacts: ["test_strategy_spec", "test_report"],
    entry_criteria: ["implementation_completed"],
    exit_criteria: ["test_coverage_met", "regression_passed"],
    gates: [
      { gate_type: "test", blocking: true, required: true },
      { gate_type: "coverage", blocking: false, required: true },
      { gate_type: "test_strategy", blocking: true, required: true },
    ],
  },
  reporting: {
    phase: "reporting",
    required_artifacts: ["delivery_report"],
    entry_criteria: ["testing_completed"],
    exit_criteria: ["report_approved", "release_readiness_confirmed"],
    gates: [
      { gate_type: "report_completeness", blocking: true, required: true },
      { gate_type: "release_readiness", blocking: true, required: true },
    ],
  },
};

// ============================================================
// LifecycleSpecStore
// ============================================================

export class LifecycleSpecStore {
  private specs: Map<LifecyclePhase, PhaseSpec> = new Map();
  private transitions: PhaseTransitionRecord[] = [];

  constructor() {
    this.initializeDefaults();
  }

  private initializeDefaults(): void {
    for (const phase of PHASE_ORDER) {
      const defaults = DEFAULT_PHASE_SPECS[phase];
      this.specs.set(phase, {
        ...defaults,
        status: "not_started",
        artifacts: [],
        evidence_refs: [],
        blockers: [],
      });
    }
  }

  /** 获取阶段规格 */
  getSpec(phase: LifecyclePhase): PhaseSpec | undefined {
    return this.specs.get(phase);
  }

  /** 设置/更新阶段规格 */
  setSpec(phase: LifecyclePhase, updates: Partial<PhaseSpec>): void {
    const current = this.specs.get(phase);
    if (!current) throw new Error(`未知阶段: ${phase}`);
    this.specs.set(phase, { ...current, ...updates });
  }

  /** 获取所有阶段状态 */
  listPhases(): PhaseSpec[] {
    return PHASE_ORDER.map(p => this.specs.get(p)!);
  }

  /** 获取阶段状态 */
  getPhaseStatus(phase: LifecyclePhase): PhaseStatus {
    const spec = this.specs.get(phase);
    if (!spec) throw new Error(`未知阶段: ${phase}`);
    return spec.status;
  }

  /** 获取当前活跃阶段 */
  getActivePhase(): LifecyclePhase | undefined {
    for (const phase of PHASE_ORDER) {
      const spec = this.specs.get(phase)!;
      if (spec.status === "in_progress") return phase;
    }
    return undefined;
  }

  /**
   * 验证阶段转换是否合法
   * - 必须按顺序推进（允许跳过 skipped 阶段）
   * - 前一阶段必须 completed 或 skipped
   */
  validateTransition(from: LifecyclePhase, to: LifecyclePhase): { valid: boolean; reason?: string } {
    const fromIdx = PHASE_ORDER.indexOf(from);
    const toIdx = PHASE_ORDER.indexOf(to);

    if (fromIdx === -1 || toIdx === -1) {
      return { valid: false, reason: `未知阶段: ${from} 或 ${to}` };
    }

    if (toIdx <= fromIdx) {
      return { valid: false, reason: `不允许回退: ${from} → ${to}` };
    }

    // 检查中间阶段是否都已完成或跳过
    for (let i = fromIdx + 1; i < toIdx; i++) {
      const intermediate = this.specs.get(PHASE_ORDER[i])!;
      if (intermediate.status !== "completed" && intermediate.status !== "skipped") {
        return {
          valid: false,
          reason: `中间阶段 ${PHASE_ORDER[i]} 状态为 ${intermediate.status}，无法跳过`,
        };
      }
    }

    // 检查 from 阶段是否已完成
    const fromSpec = this.specs.get(from)!;
    if (fromSpec.status !== "completed" && fromSpec.status !== "skipped") {
      return { valid: false, reason: `阶段 ${from} 尚未完成 (${fromSpec.status})` };
    }

    return { valid: true };
  }

  /** 记录阶段转换 */
  recordTransition(from: LifecyclePhase, to: LifecyclePhase, reason: string, approvedBy?: string): void {
    const validation = this.validateTransition(from, to);
    if (!validation.valid) {
      throw new Error(`阶段转换失败: ${validation.reason}`);
    }

    this.transitions.push({
      from,
      to,
      timestamp: new Date().toISOString(),
      reason,
      approved_by: approvedBy,
    });

    this.setSpec(to, { status: "in_progress", started_at: new Date().toISOString() });
  }

  /** 获取转换历史 */
  getTransitions(): PhaseTransitionRecord[] {
    return [...this.transitions];
  }

  /** 添加证据引用 */
  addEvidenceRef(phase: LifecyclePhase, ref: string): void {
    const spec = this.specs.get(phase);
    if (!spec) throw new Error(`未知阶段: ${phase}`);
    if (!spec.evidence_refs.includes(ref)) {
      spec.evidence_refs.push(ref);
    }
  }

  /** 添加工件 */
  addArtifact(phase: LifecyclePhase, artifact: PhaseArtifact): void {
    const spec = this.specs.get(phase);
    if (!spec) throw new Error(`未知阶段: ${phase}`);
    spec.artifacts.push(artifact);
  }

  /** 检查阶段必交工件是否齐全 */
  checkArtifacts(phase: LifecyclePhase): { complete: boolean; missing: string[] } {
    const spec = this.specs.get(phase);
    if (!spec) throw new Error(`未知阶段: ${phase}`);

    const provided = new Set(spec.artifacts.map(a => a.type));
    const missing = spec.required_artifacts.filter(r => !provided.has(r));

    return { complete: missing.length === 0, missing };
  }
}
