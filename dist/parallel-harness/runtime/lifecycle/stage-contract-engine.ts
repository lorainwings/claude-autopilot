/**
 * parallel-harness: Stage Contract Engine
 *
 * 将 StageContract 从"数据结构"升级为"运行时控制器"。
 * 控制阶段进入/退出条件、必交工件验证、必跑 gate 触发。
 */

import type {
  LifecyclePhase,
  PhaseSpec,
  PhaseArtifact,
  PhaseStatus,
} from "./lifecycle-spec-store";
import { LifecycleSpecStore } from "./lifecycle-spec-store";

// ============================================================
// Stage Contract Engine 类型
// ============================================================

export interface StageEntryResult {
  allowed: boolean;
  phase: LifecyclePhase;
  reason?: string;
  unmet_criteria: string[];
}

export interface StageExitResult {
  allowed: boolean;
  phase: LifecyclePhase;
  reason?: string;
  missing_artifacts: string[];
  pending_gates: string[];
  unmet_criteria: string[];
}

export interface StageValidationResult {
  phase: LifecyclePhase;
  artifacts_complete: boolean;
  missing_artifacts: string[];
  gates_passed: boolean;
  pending_gates: string[];
}

export type FailureStrategy = "block" | "retry" | "escalate" | "skip";

export interface StageFailurePolicy {
  phase: LifecyclePhase;
  max_retries: number;
  strategy: FailureStrategy;
  escalation_target?: string;
}

// ============================================================
// 默认失败策略
// ============================================================

const DEFAULT_FAILURE_POLICIES: Record<LifecyclePhase, StageFailurePolicy> = {
  requirement: { phase: "requirement", strategy: "escalate", max_retries: 0, escalation_target: "human" },
  product_design: { phase: "product_design", strategy: "escalate", max_retries: 0, escalation_target: "human" },
  ui_design: { phase: "ui_design", strategy: "skip", max_retries: 0 },
  tech_plan: { phase: "tech_plan", strategy: "retry", max_retries: 2 },
  architecture: { phase: "architecture", strategy: "retry", max_retries: 2 },
  implementation: { phase: "implementation", strategy: "retry", max_retries: 3 },
  testing: { phase: "testing", strategy: "retry", max_retries: 3 },
  reporting: { phase: "reporting", strategy: "block", max_retries: 1 },
};

// ============================================================
// StageContractEngine
// ============================================================

export class StageContractEngine {
  private store: LifecycleSpecStore;
  private gateResults: Map<string, boolean> = new Map();
  private failurePolicies: Record<LifecyclePhase, StageFailurePolicy>;

  constructor(store: LifecycleSpecStore, customPolicies?: Partial<Record<LifecyclePhase, StageFailurePolicy>>) {
    this.store = store;
    this.failurePolicies = { ...DEFAULT_FAILURE_POLICIES, ...customPolicies };
  }

  /**
   * 尝试进入阶段
   * - 检查前置阶段是否完成
   * - 检查进入条件
   */
  enterStage(phase: LifecyclePhase): StageEntryResult {
    const spec = this.store.getSpec(phase);
    if (!spec) return { allowed: false, phase, reason: `未知阶段: ${phase}`, unmet_criteria: [] };

    // 已在进行中或已完成，不允许重复进入
    if (spec.status === "in_progress") {
      return { allowed: false, phase, reason: `阶段 ${phase} 已在进行中`, unmet_criteria: [] };
    }
    if (spec.status === "completed") {
      return { allowed: false, phase, reason: `阶段 ${phase} 已完成`, unmet_criteria: [] };
    }

    // 检查进入条件（简化: 检查 entry_criteria 中引用的前置阶段是否完成）
    const unmet: string[] = [];
    for (const criterion of spec.entry_criteria) {
      // 约定: entry_criteria 格式为 "{phase}_completed" 或 "{phase}_received"
      const match = criterion.match(/^(\w+)_(completed|received|approved)$/);
      if (match) {
        const refPhase = match[1] as LifecyclePhase;
        const refSpec = this.store.getSpec(refPhase);
        if (refSpec && refSpec.status !== "completed" && refSpec.status !== "skipped") {
          // 特殊处理: run_request_received 对 requirement 阶段始终满足
          if (criterion !== "run_request_received") {
            unmet.push(criterion);
          }
        }
      }
    }

    if (unmet.length > 0) {
      return {
        allowed: false,
        phase,
        reason: `进入条件不满足: ${unmet.join(", ")}`,
        unmet_criteria: unmet,
      };
    }

    // 进入阶段
    this.store.setSpec(phase, {
      status: "in_progress",
      started_at: new Date().toISOString(),
    });

    return { allowed: true, phase, unmet_criteria: [] };
  }

  /**
   * 验证阶段工件和 gate
   */
  validateStage(phase: LifecyclePhase): StageValidationResult {
    const spec = this.store.getSpec(phase);
    if (!spec) {
      return { phase, artifacts_complete: false, missing_artifacts: [], gates_passed: false, pending_gates: [] };
    }

    // 检查工件
    const artifactCheck = this.store.checkArtifacts(phase);

    // 检查 gate
    const pendingGates: string[] = [];
    for (const gate of spec.gates) {
      if (gate.required) {
        const passed = this.gateResults.get(`${phase}:${gate.gate_type}`);
        if (passed !== true) {
          pendingGates.push(gate.gate_type);
        }
      }
    }

    return {
      phase,
      artifacts_complete: artifactCheck.complete,
      missing_artifacts: artifactCheck.missing,
      gates_passed: pendingGates.length === 0,
      pending_gates: pendingGates,
    };
  }

  /**
   * 尝试退出阶段（标记完成）
   * - 检查必交工件
   * - 检查必跑 gate
   * - 检查退出条件
   */
  exitStage(phase: LifecyclePhase): StageExitResult {
    const spec = this.store.getSpec(phase);
    if (!spec) {
      return { allowed: false, phase, reason: `未知阶段: ${phase}`, missing_artifacts: [], pending_gates: [], unmet_criteria: [] };
    }

    if (spec.status !== "in_progress") {
      return { allowed: false, phase, reason: `阶段 ${phase} 不在进行中 (${spec.status})`, missing_artifacts: [], pending_gates: [], unmet_criteria: [] };
    }

    const validation = this.validateStage(phase);

    if (!validation.artifacts_complete || !validation.gates_passed) {
      return {
        allowed: false,
        phase,
        reason: `退出条件不满足`,
        missing_artifacts: validation.missing_artifacts,
        pending_gates: validation.pending_gates,
        unmet_criteria: [],
      };
    }

    // 标记完成
    this.store.setSpec(phase, {
      status: "completed",
      completed_at: new Date().toISOString(),
    });

    return { allowed: true, phase, missing_artifacts: [], pending_gates: [], unmet_criteria: [] };
  }

  /** 记录 gate 结果 */
  recordGateResult(phase: LifecyclePhase, gateType: string, passed: boolean): void {
    this.gateResults.set(`${phase}:${gateType}`, passed);
  }

  /** 获取当前活跃阶段 */
  getActiveStage(): LifecyclePhase | undefined {
    return this.store.getActivePhase();
  }

  /** 获取阶段失败策略 */
  getFailurePolicy(phase: LifecyclePhase): StageFailurePolicy {
    return this.failurePolicies[phase] || DEFAULT_FAILURE_POLICIES[phase];
  }

  /** 获取底层 store */
  getStore(): LifecycleSpecStore {
    return this.store;
  }
}

// ============================================================
// P1-1: Stage Graph — 真正的阶段图
// ============================================================

/** 阶段图节点 */
export interface StageGraphNode {
  phase: LifecyclePhase;
  status: PhaseStatus;
  dependencies: LifecyclePhase[];
  gate_results: Array<{ gate_type: string; passed: boolean; blocking: boolean }>;
  artifacts_complete: boolean;
  evidence_refs: string[];
}

/** 阶段图 — RunPlan.stage_contracts 的升级形态 */
export interface StageGraph {
  nodes: StageGraphNode[];
  current_phase: LifecyclePhase | null;
  completed_phases: LifecyclePhase[];
  blocked_phases: LifecyclePhase[];
}

/** 从 LifecycleSpecStore 构建阶段图 */
export function buildStageGraph(store: LifecycleSpecStore): StageGraph {
  const nodes: StageGraphNode[] = [];
  const completedPhases: LifecyclePhase[] = [];
  const blockedPhases: LifecyclePhase[] = [];
  let currentPhase: LifecyclePhase | null = null;

  const phases = store.listPhases();
  for (let i = 0; i < phases.length; i++) {
    const spec = phases[i];
    const deps: LifecyclePhase[] = i > 0 ? [phases[i - 1].phase] : [];
    const artifactCheck = store.checkArtifacts(spec.phase);

    nodes.push({
      phase: spec.phase,
      status: spec.status,
      dependencies: deps,
      gate_results: spec.gates.map(g => ({
        gate_type: g.gate_type,
        passed: spec.status === "completed",
        blocking: g.blocking,
      })),
      artifacts_complete: artifactCheck.complete,
      evidence_refs: spec.evidence_refs,
    });

    if (spec.status === "completed" || spec.status === "skipped") {
      completedPhases.push(spec.phase);
    } else if (spec.status === "blocked") {
      blockedPhases.push(spec.phase);
    } else if (spec.status === "in_progress" && !currentPhase) {
      currentPhase = spec.phase;
    }
  }

  return { nodes, current_phase: currentPhase, completed_phases: completedPhases, blocked_phases: blockedPhases };
}
