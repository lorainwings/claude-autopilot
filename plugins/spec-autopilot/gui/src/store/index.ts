/**
 * Zustand Store — 全局状态管理
 * 管理事件流、Phase 状态、连接状态
 */

import { create } from "zustand";
import type { AutopilotEvent } from "../lib/ws-bridge";

// --- 模型路由聚合状态 (v5.4) ---
type ModelStatus = "requested" | "effective" | "fallback" | "unknown" | "unsupported";
type ModelTier = "fast" | "standard" | "deep" | "auto";
type EffortLevel = "low" | "medium" | "high";

export interface ModelRoutingState {
  requested_model: string | null;
  requested_tier: ModelTier | null;
  requested_effort: EffortLevel | null;
  effective_model: string | null;
  fallback_model: string | null;
  model_status: ModelStatus;
  routing_reason: string | null;
  fallback_applied: boolean;
  fallback_reason: string | null;
  inference_source: string | null;
  capability_note: string | null;
  phase: number;
  agent_id: string | null;
  updated_at: string | null;
}

export interface ParallelPlanSummary {
  scheduler_decision: string;
  total_tasks: number;
  batch_count: number;
  max_parallelism: number;
  fallback_to_serial: boolean;
  fallback_reason: string | null;
  diagnostics: string[];
  current_batch_index: number | null;
  updated_at: string | null;
}

interface TaskProgress {
  task_name: string;
  phase: number;
  status: "running" | "passed" | "failed" | "retrying";
  tdd_step?: "red" | "green" | "refactor";
  retry_count?: number;
  task_index: number;
  task_total: number;
  timestamp: string;
}

interface TaskProgressPayload {
  task_name: string;
  status: "running" | "passed" | "failed" | "retrying";
  tdd_step?: "red" | "green" | "refactor";
  retry_count?: number;
  task_index: number;
  task_total: number;
}

function isTaskProgressPayload(p: unknown): p is TaskProgressPayload {
  const obj = p as Record<string, unknown>;
  return typeof obj.task_name === "string" && typeof obj.status === "string" && typeof obj.task_index === "number";
}

export interface AgentInfo {
  agent_id: string;
  agent_label: string;
  phase: number;
  status: "dispatched" | "ok" | "warning" | "blocked" | "failed";
  dispatch_time: string;
  complete_time?: string;
  summary?: string;
  duration_ms?: number;
  output_files?: string[];
}

export interface StatusSnapshot {
  model?: string;
  cwd?: string;
  transcript_path?: string;
  cost?: string;
  context_window?: Record<string, unknown>;
  worktree?: string;
  version?: string;
  timestamp: string;
}

/** 服务可用性细分 (v5.4) */
/** 服务可用性细分 (v5.4) */
export interface ServerHealth {
  httpOk: boolean;
  wsConnected: boolean;
  telemetryAvailable: boolean;
  transcriptAvailable: boolean;
  statusLineInstalled: boolean;
}

/** 恢复来源枚举 (工作包 G) */
export type RecoverySource =
  | "fresh"
  | "snapshot_resume"
  | "checkpoint_resume"
  | "progress_resume"
  | "snapshot_hash_mismatch";

/** 报告状态 (工作包 D) */
export interface ReportState {
  report_format: "allure" | "junit" | "custom" | "none" | null;
  report_path: string | null;
  report_url: string | null;
  allure_results_dir: string | null;
  allure_preview_url: string | null;
  suite_results: {
    total: number;
    passed: number;
    failed: number;
    skipped: number;
    error: number;
  } | null;
  anomaly_alerts: string[];
}

/** TDD 审计摘要 (工作包 I) */
export interface TddAuditSummary {
  cycle_count: number;
  red_violations: number;
  green_violations: number;
  refactor_rollbacks: number;
  red_commands: string[];
  green_commands: string[];
}

/** 编排概览状态 (v7.0 统一控制面) */
export interface OrchestrationOverview {
  /** 目标摘要（从 session_start 或 phase_start payload 推断） */
  goalSummary: string | null;
  /** 当前 sub-step 描述 */
  currentSubStep: string | null;
  /** gate frontier：最新被阻断的 gate 原因 */
  gateFrontierReason: string | null;
  /** requirement packet hash (从 phase_end Phase 1 提取) */
  requirementPacketHash: string | null;
  /** compact 风险等级 */
  contextBudget: { percent: number; risk: "low" | "medium" | "high" } | null;
  /** archive readiness */
  archiveReadiness: {
    fixupComplete: boolean;
    reviewGatePassed: boolean;
    ready: boolean;
  } | null;
  /** 恢复来源 (工作包 G) */
  recoverySource: RecoverySource | null;
  /** 恢复原因 */
  recoveryReason: string | null;
  /** 报告状态 (工作包 D) */
  reportState: ReportState | null;
  /** TDD 审计 (工作包 I) */
  tddAudit: TddAuditSummary | null;
  /** 决策生命周期 (工作包 B) */
  decisionLifecycle: {
    requestId: string;
    phase: number;
    action: string;
    state: "idle" | "pending" | "accepted" | "applied" | "superseded" | "expired";
  } | null;
}

/** 决策生命周期状态 (v5.2) */
export interface DecisionLifecycle {
  requestId: string;
  phase: number;
  action: string;
  state: "idle" | "pending" | "accepted" | "applied" | "superseded" | "expired";
}

interface AppState {
  events: AutopilotEvent[];
  transcriptEvents: AutopilotEvent[];
  toolEvents: AutopilotEvent[];
  connected: boolean;
  currentPhase: number | null;
  sessionId: string | null;
  changeName: string | null;
  mode: "full" | "lite" | "minimal" | null;
  latestStatus: StatusSnapshot | null;
  taskProgress: Map<string, TaskProgress>;
  agentMap: Map<string, AgentInfo>;
  decisionAcked: boolean;
  /** 决策生命周期 (v5.2) */
  decisionLifecycle: DecisionLifecycle | null;
  /** 恢复来源 (v7.0 — 从 null 升级为结构化) */
  recoverySource: RecoverySource | null;
  /** 模型路由聚合状态 (v5.4) */
  modelRouting: ModelRoutingState;
  /** 模型路由历史记录 (v5.4) */
  modelRoutingHistory: ModelRoutingState[];
  /** 服务可用性细分 (v5.4) */
  serverHealth: ServerHealth;
  /** 并行调度计划摘要 (v5.5) */
  parallelPlan: ParallelPlanSummary;
  /** 编排概览 (v5.9 orchestration-first) */
  orchestration: OrchestrationOverview;

  addEvents: (events: AutopilotEvent[]) => void;
  /** H-2/H-1: 从 WS snapshot meta 初始化编排状态 */
  initOrchestrationFromMeta: (meta: {
    archiveReadiness?: { overall: string; checks?: Record<string, unknown>; block_reasons?: string[] } | null;
    requirementPacketHash?: string | null;
    gateFrontier?: number | null;
    recoverySource?: string | null;
    recoveryReason?: string | null;
    reportState?: {
      report_format: string | null;
      report_path: string | null;
      report_url: string | null;
      allure_results_dir: string | null;
      allure_preview_url: string | null;
      suite_results: { total: number; passed: number; failed: number; skipped: number; error: number } | null;
      anomaly_alerts: string[];
    } | null;
    tddAudit?: TddAuditSummary | null;
  }) => void;
  setConnected: (connected: boolean) => void;
  setHttpOk: (ok: boolean) => void;
  setDecisionAcked: (acked: boolean) => void;
  lastAckedBlockSequence: number;
  setLastAckedBlockSequence: (seq: number) => void;
  reset: () => void;
}

// ============================================
// Derived selectors for V2 Telemetry Dashboard
// ============================================

export interface PhaseDuration {
  phase: number;
  label: string;
  durationMs: number;
  status: "pending" | "running" | "ok" | "warning" | "blocked" | "failed";
}

export interface GateStats {
  passed: number;
  blocked: number;
  pending: number;
  passRate: number;
}

const ALL_LABELS = [
  "环境初始化", "需求理解", "OpenSpec 创建", "快速生成",
  "测试设计", "代码实施", "测试报告", "归档清理",
];

// lite mode only uses phases 0,1,5,6,7; minimal uses 0,1,5,7
const MODE_PHASES: Record<string, number[]> = {
  full: [0, 1, 2, 3, 4, 5, 6, 7],
  lite: [0, 1, 5, 6, 7],
  minimal: [0, 1, 5, 7],
};

/** Get actual total phases count from events or fallback */
export function selectTotalPhases(events: AutopilotEvent[]): number {
  const latest = [...events].reverse().find((e) => e.total_phases > 0);
  return latest?.total_phases ?? 8;
}

/** Get active phase indices based on mode from events */
export function selectActivePhaseIndices(events: AutopilotEvent[]): number[] {
  const latest = [...events].reverse().find((e) => e.mode);
  const mode = latest?.mode ?? "full";
  return MODE_PHASES[mode] ?? MODE_PHASES.full!;
}

/** Compute per-phase duration from events */
export function selectPhaseDurations(events: AutopilotEvent[]): PhaseDuration[] {
  const activeIndices = selectActivePhaseIndices(events);

  return activeIndices.map((idx) => {
    const label = ALL_LABELS[idx] ?? `Phase ${idx}`;
    const phaseEvents = events.filter((e) => e.phase === idx);
    // findLast: 同一 phase 有多个 start/end 时取最新的（崩溃恢复场景）
    const startEvent = phaseEvents.findLast((e) => e.type === "phase_start");
    const endEvent = phaseEvents.findLast((e) => e.type === "phase_end");
    const gateBlock = phaseEvents.findLast((e) => e.type === "gate_block");
    const gatePass = phaseEvents.findLast((e) => e.type === "gate_pass");

    let status: PhaseDuration["status"] = "pending";
    let durationMs = 0;

    const startTime = startEvent ? new Date(startEvent.timestamp).getTime() : 0;
    const endTime = endEvent ? new Date(endEvent.timestamp).getTime() : 0;

    // 时间顺序校验：end 必须在 start 之后才算完成
    if (endEvent && endTime > startTime) {
      status = (endEvent.payload.status as PhaseDuration["status"]) || "ok";
      durationMs = (endEvent.payload.duration_ms as number) || 0;
      if (durationMs === 0 && startEvent) {
        durationMs = endTime - startTime;
      }
    } else if (gateBlock && (!gatePass || gateBlock.sequence > gatePass.sequence)) {
      status = "blocked";
      if (startEvent) {
        durationMs = Date.now() - startTime;
      }
    } else if (startEvent) {
      status = "running";
      durationMs = Date.now() - startTime;
    }

    return { phase: idx, label, durationMs, status };
  });
}

/** Compute total session elapsed time */
export function selectTotalElapsedMs(events: AutopilotEvent[]): number {
  const starts = events.filter((e) => e.type === "phase_start");
  const ends = events.filter((e) => e.type === "phase_end");
  if (starts.length === 0) return 0;

  let total = 0;

  // 收集每个 phase 的最新 start 和 end（崩溃恢复场景下取最新事件）
  const phaseSet = new Set(starts.map((s) => s.phase));

  for (const phase of phaseSet) {
    const latestStart = starts.findLast((s) => s.phase === phase);
    const latestEnd = ends.findLast((e) => e.phase === phase);

    if (!latestStart) continue;

    const startTime = new Date(latestStart.timestamp).getTime();

    if (latestEnd && new Date(latestEnd.timestamp).getTime() > startTime) {
      // 已完成：使用 duration_ms 或 fallback 计算
      let dur = (latestEnd.payload.duration_ms as number) || 0;
      if (dur === 0) {
        dur = new Date(latestEnd.timestamp).getTime() - startTime;
      }
      total += dur;
    } else {
      // 正在运行：使用 Date.now()
      total += Date.now() - startTime;
    }
  }

  return total;
}

/** Count tool_use events associated with a specific agent (v5.3 WS4.D) */
export function selectAgentToolCount(events: AutopilotEvent[], agentId: string): number {
  return events.filter(
    (e) => e.type === "tool_use" && (e.payload as Record<string, unknown>).agent_id === agentId
  ).length;
}

/** Get tool_use events associated with a specific agent (v5.3 WS4.B) */
export function selectAgentToolEvents(events: AutopilotEvent[], agentId: string): AutopilotEvent[] {
  return events.filter(
    (e) => e.type === "tool_use" && (e.payload as Record<string, unknown>).agent_id === agentId
  );
}

/** Get unique agent IDs from events (v5.3 WS4.C) */
export function selectAgentIds(agentMap: Map<string, AgentInfo>): { id: string; label: string }[] {
  return Array.from(agentMap.values()).map((a) => ({ id: a.agent_id, label: a.agent_label }));
}

/** Compute gate pass/block/pending statistics (single-pass) */
export function selectGateStats(events: AutopilotEvent[]): GateStats {
  let passed = 0;
  let blocked = 0;
  let pending = 0;
  for (const e of events) {
    if (e.type === "gate_pass") passed++;
    else if (e.type === "gate_block") blocked++;
    else if (e.type === "gate_decision_pending") pending++;
  }
  const total = passed + blocked;
  const passRate = total > 0 ? Math.round((passed / total) * 100) : 0;

  return { passed, blocked, pending, passRate };
}

/** 提取模型路由事件历史 (v5.4) */
export function selectModelRoutingEvents(events: AutopilotEvent[]): AutopilotEvent[] {
  return events.filter((e) => e.type === "model_routing" || e.type === "model_effective" || e.type === "model_fallback");
}

const DEFAULT_MODEL_ROUTING: ModelRoutingState = {
  requested_model: null,
  requested_tier: null,
  requested_effort: null,
  effective_model: null,
  fallback_model: null,
  model_status: "unknown",
  routing_reason: null,
  fallback_applied: false,
  fallback_reason: null,
  inference_source: null,
  capability_note: null,
  phase: 0,
  agent_id: null,
  updated_at: null,
};

const DEFAULT_SERVER_HEALTH: ServerHealth = {
  httpOk: false,
  wsConnected: false,
  telemetryAvailable: false,
  transcriptAvailable: false,
  statusLineInstalled: false,
};

const DEFAULT_PARALLEL_PLAN: ParallelPlanSummary = {
  scheduler_decision: "unknown",
  total_tasks: 0,
  batch_count: 0,
  max_parallelism: 0,
  fallback_to_serial: false,
  fallback_reason: null,
  diagnostics: [],
  current_batch_index: null,
  updated_at: null,
};

const DEFAULT_ORCHESTRATION: OrchestrationOverview = {
  goalSummary: null,
  currentSubStep: null,
  gateFrontierReason: null,
  requirementPacketHash: null,
  contextBudget: null,
  archiveReadiness: null,
  recoverySource: null,
  recoveryReason: null,
  reportState: null,
  tddAudit: null,
  decisionLifecycle: null,
};

export const useStore = create<AppState>((set) => ({
  events: [],
  transcriptEvents: [],
  toolEvents: [],
  connected: false,
  currentPhase: null,
  sessionId: null,
  changeName: null,
  mode: null,
  latestStatus: null,
  taskProgress: new Map(),
  agentMap: new Map(),
  decisionAcked: false,
  decisionLifecycle: null,
  recoverySource: null,
  lastAckedBlockSequence: -1,
  modelRouting: { ...DEFAULT_MODEL_ROUTING },
  modelRoutingHistory: [],
  serverHealth: { ...DEFAULT_SERVER_HEALTH },
  parallelPlan: { ...DEFAULT_PARALLEL_PLAN },
  orchestration: { ...DEFAULT_ORCHESTRATION },

  addEvents: (newEvents) =>
    set((state) => {
      const eventKey = (event: AutopilotEvent) =>
        event.event_id || `${event.source || "legacy"}:${event.type}:${event.sequence}:${event.timestamp}`;

      const sortKey = (event: AutopilotEvent) => event.ingest_seq ?? event.sequence;

      // Deduplicate by stable event_id / fallback signature
      const seen = new Set(state.events.map(eventKey));
      const unique = newEvents.filter((e) => !seen.has(eventKey(e)));

      const CRITICAL_TYPES = new Set([
        "phase_start", "phase_end", "gate_block", "gate_pass",
        "agent_dispatch", "agent_complete", "session_start", "session_end",
        "model_routing", "model_effective", "model_fallback",
        "parallel_plan", "parallel_batch_start", "parallel_batch_end",
        "parallel_task_ready", "parallel_task_blocked", "parallel_fallback",
        "report_ready", "tdd_audit", "archive_readiness",
      ]);
      const MAX_CRITICAL = 400;
      const MAX_REGULAR = 2400;
      const allSorted = [...state.events, ...unique].sort((a, b) => sortKey(a) - sortKey(b));
      const critical = allSorted.filter((e) => CRITICAL_TYPES.has(e.type));
      const regular = allSorted.filter((e) => !CRITICAL_TYPES.has(e.type));
      // Cap both pools: keep most recent
      const cappedCritical = critical.length > MAX_CRITICAL ? critical.slice(-MAX_CRITICAL) : critical;
      const cappedRegular = regular.slice(-MAX_REGULAR);
      const keepSeqs = new Set([
        ...cappedCritical.map(eventKey),
        ...cappedRegular.map(eventKey),
      ]);
      const merged = allSorted.filter((e) => keepSeqs.has(eventKey(e)));
      const latest = merged[merged.length - 1];

      const newTaskProgress = new Map(state.taskProgress);
      const newAgentMap = new Map(state.agentMap);
      let latestStatus = state.latestStatus;
      let modelRouting = state.modelRouting;
      const modelRoutingHistory = [...state.modelRoutingHistory];
      let parallelPlan = state.parallelPlan;
      let orchestration = { ...state.orchestration };

      for (const event of newEvents) {
        if (event.type === "task_progress" && isTaskProgressPayload(event.payload)) {
          const p = event.payload;
          const progressKey = `p${event.phase}:${p.task_name}`;
          newTaskProgress.set(progressKey, {
            task_name: p.task_name,
            phase: event.phase,
            status: p.status,
            tdd_step: p.tdd_step,
            retry_count: p.retry_count,
            task_index: p.task_index,
            task_total: p.task_total,
            timestamp: event.timestamp,
          });
        } else if (event.type === "agent_dispatch" && typeof event.payload.agent_id === "string") {
          newAgentMap.set(event.payload.agent_id as string, {
            agent_id: event.payload.agent_id as string,
            agent_label: (event.payload.agent_label as string) || event.payload.agent_id as string,
            phase: event.phase,
            status: "dispatched",
            dispatch_time: event.timestamp,
          });
        } else if (event.type === "agent_complete" && typeof event.payload.agent_id === "string") {
          const existing = newAgentMap.get(event.payload.agent_id as string);
          newAgentMap.set(event.payload.agent_id as string, {
            agent_id: event.payload.agent_id as string,
            agent_label: (event.payload.agent_label as string) || existing?.agent_label || event.payload.agent_id as string,
            phase: event.phase,
            status: (event.payload.status as AgentInfo["status"]) || "ok",
            dispatch_time: existing?.dispatch_time || event.timestamp,
            complete_time: event.timestamp,
            summary: event.payload.summary as string | undefined,
            duration_ms: event.payload.duration_ms as number | undefined,
            output_files: (event.payload.output_files as string[] | undefined) || existing?.output_files,
          });
        } else if (event.type === "phase_end" || event.type === "error") {
          // When a phase ends or errors, mark any still-dispatched agents in that phase as failed
          for (const [id, info] of newAgentMap) {
            if (info.phase === event.phase && info.status === "dispatched") {
              newAgentMap.set(id, { ...info, status: "failed", complete_time: event.timestamp });
            }
          }
        } else if (event.type === "status_snapshot") {
          latestStatus = {
            model: event.payload.model as string | undefined,
            cwd: event.payload.cwd as string | undefined,
            transcript_path: event.payload.transcript_path as string | undefined,
            cost: event.payload.cost == null ? undefined : String(event.payload.cost),
            context_window: event.payload.context_window as Record<string, unknown> | undefined,
            worktree: event.payload.worktree as string | undefined,
            version: event.payload.version as string | undefined,
            timestamp: event.timestamp,
          };
          // v5.4: 从 statusLine 推断 effective_model
          // 仅在尚未收到 model_effective 事件时推断（避免与 model_effective 路径竞争覆盖）
          if (
            latestStatus.model &&
            modelRouting.requested_model &&
            modelRouting.model_status === "requested" &&
            modelRouting.inference_source === null
          ) {
            const inferredModel = latestStatus.model;
            const match = inferredModel.includes(modelRouting.requested_model) ||
              modelRouting.requested_model === "auto";
            modelRouting = {
              ...modelRouting,
              effective_model: inferredModel,
              model_status: "effective",
              inference_source: "statusline",
              capability_note: match ? null : "runtime model override unsupported — effective model inferred from statusLine",
              updated_at: event.timestamp,
            };
          }
        } else if (event.type === "model_routing") {
          // v5.4: 路由器请求事件 → requested 状态
          const p = event.payload as Record<string, unknown>;
          modelRouting = {
            requested_model: String(p.selected_model ?? "auto"),
            requested_tier: (p.selected_tier as ModelTier) ?? "auto",
            requested_effort: (p.selected_effort as EffortLevel) ?? "medium",
            effective_model: null,
            fallback_model: (p.fallback_model as string) ?? null,
            model_status: "requested",
            routing_reason: String(p.routing_reason ?? ""),
            fallback_applied: Boolean(p.fallback_applied),
            fallback_reason: null,
            inference_source: null,
            capability_note: null,
            phase: event.phase,
            agent_id: (p.agent_id as string) ?? null,
            updated_at: event.timestamp,
          };
          modelRoutingHistory.push({ ...modelRouting });
        } else if (event.type === "model_effective") {
          // v5.4: 运行时确认实际模型
          const p = event.payload as Record<string, unknown>;
          modelRouting = {
            ...modelRouting,
            effective_model: String(p.effective_model ?? "unknown"),
            model_status: p.match === false ? "unsupported" : "effective",
            inference_source: String(p.inference_source ?? "unknown"),
            capability_note: p.match === false
              ? "runtime model override unsupported — effective model inferred from statusLine"
              : null,
            phase: event.phase,
            agent_id: (p.agent_id as string) ?? modelRouting.agent_id,
            updated_at: event.timestamp,
          };
          // 推入历史（与 model_routing / model_fallback 保持一致）
          modelRoutingHistory.push({ ...modelRouting });
        } else if (event.type === "model_fallback") {
          // v5.4: 模型降级
          const p = event.payload as Record<string, unknown>;
          modelRouting = {
            ...modelRouting,
            fallback_model: String(p.fallback_model ?? "sonnet"),
            model_status: "fallback",
            fallback_applied: true,
            fallback_reason: String(p.fallback_reason ?? ""),
            phase: event.phase,
            agent_id: (p.agent_id as string) ?? modelRouting.agent_id,
            updated_at: event.timestamp,
          };
          modelRoutingHistory.push({ ...modelRouting });
        } else if (event.type === "parallel_plan") {
          // v5.5: 并行计划生成事件
          const p = event.payload as Record<string, unknown>;
          parallelPlan = {
            scheduler_decision: String(p.scheduler_decision ?? "unknown"),
            total_tasks: Number(p.total_tasks ?? 0),
            batch_count: Number(p.batch_count ?? 0),
            max_parallelism: Number(p.max_parallelism ?? 0),
            fallback_to_serial: Boolean(p.fallback_to_serial),
            fallback_reason: p.fallback_reason ? String(p.fallback_reason) : null,
            diagnostics: Array.isArray(p.diagnostics) ? (p.diagnostics as string[]) : [],
            current_batch_index: parallelPlan.current_batch_index,
            updated_at: event.timestamp,
          };
        } else if (event.type === "parallel_batch_start") {
          const p = event.payload as Record<string, unknown>;
          parallelPlan = {
            ...parallelPlan,
            current_batch_index: Number(p.batch_index ?? 0),
            updated_at: event.timestamp,
          };
        } else if (event.type === "parallel_batch_end") {
          parallelPlan = {
            ...parallelPlan,
            updated_at: event.timestamp,
          };
        } else if (event.type === "parallel_fallback") {
          const p = event.payload as Record<string, unknown>;
          parallelPlan = {
            ...parallelPlan,
            fallback_to_serial: true,
            fallback_reason: p.fallback_reason ? String(p.fallback_reason) : null,
            scheduler_decision: "serial",
            updated_at: event.timestamp,
          };
        }

        // --- 编排概览提取 (v5.9) ---
        if (event.type === "session_start" || event.type === "phase_start") {
          const p = event.payload as Record<string, unknown>;
          if (typeof p.goal_summary === "string") {
            orchestration.goalSummary = p.goal_summary;
          }
          if (typeof p.change_name === "string" && !orchestration.goalSummary) {
            orchestration.goalSummary = event.change_name || null;
          }
          if (typeof p.sub_step === "string") {
            orchestration.currentSubStep = p.sub_step;
          }
        }
        if (event.type === "gate_block") {
          const p = event.payload as Record<string, unknown>;
          orchestration.gateFrontierReason = typeof p.reason === "string"
            ? p.reason
            : typeof p.error_message === "string"
              ? p.error_message
              : "gate blocked";
        }
        if (event.type === "gate_pass") {
          // gate 通过时清除 frontier 原因
          orchestration.gateFrontierReason = null;
        }
        if (event.type === "phase_end" && event.phase === 1) {
          const p = event.payload as Record<string, unknown>;
          if (typeof p.requirement_packet_hash === "string") {
            orchestration.requirementPacketHash = p.requirement_packet_hash;
          }
        }
        if (event.type === "status_snapshot") {
          const p = event.payload as Record<string, unknown>;
          const cw = p.context_window as Record<string, unknown> | undefined;
          if (cw && typeof cw.percent === "number") {
            const pct = cw.percent as number;
            orchestration.contextBudget = {
              percent: pct,
              risk: pct > 80 ? "high" : pct > 60 ? "medium" : "low",
            };
          }
        }
        if (event.type === "archive_readiness") {
          const p = event.payload as Record<string, unknown>;
          orchestration.archiveReadiness = {
            fixupComplete: Boolean(p.fixup_complete),
            reviewGatePassed: Boolean(p.review_gate_passed),
            ready: Boolean(p.ready),
          };
        }

        // v7.0: 报告就绪事件 (工作包 D)
        if (event.type === "report_ready") {
          const p = event.payload as Record<string, unknown>;
          orchestration.reportState = {
            report_format: (p.report_format as ReportState["report_format"]) ?? null,
            report_path: (p.report_path as string) ?? null,
            report_url: (p.report_url as string) ?? null,
            allure_results_dir: (p.allure_results_dir as string) ?? null,
            allure_preview_url: (p.allure_preview_url as string) ?? null,
            suite_results: p.suite_results ? {
              total: Number((p.suite_results as Record<string, unknown>).total ?? 0),
              passed: Number((p.suite_results as Record<string, unknown>).passed ?? 0),
              failed: Number((p.suite_results as Record<string, unknown>).failed ?? 0),
              skipped: Number((p.suite_results as Record<string, unknown>).skipped ?? 0),
              error: Number((p.suite_results as Record<string, unknown>).error ?? 0),
            } : null,
            anomaly_alerts: Array.isArray(p.anomaly_alerts) ? (p.anomaly_alerts as string[]) : [],
          };
        }

        // v7.0: TDD 审计事件 (工作包 I)
        if (event.type === "tdd_audit") {
          const p = event.payload as Record<string, unknown>;
          orchestration.tddAudit = {
            cycle_count: Number(p.cycle_count ?? 0),
            red_violations: Number(p.red_violations ?? 0),
            green_violations: Number(p.green_violations ?? 0),
            refactor_rollbacks: Number(p.refactor_rollbacks ?? 0),
            red_commands: Array.isArray(p.red_commands) ? (p.red_commands as string[]) : [],
            green_commands: Array.isArray(p.green_commands) ? (p.green_commands as string[]) : [],
          };
        }

        // v7.0: 恢复来源事件 (工作包 G)
        if (event.type === "session_start") {
          const p = event.payload as Record<string, unknown>;
          if (typeof p.recovery_source === "string") {
            orchestration.recoverySource = p.recovery_source as RecoverySource;
          }
          if (typeof p.recovery_reason === "string") {
            orchestration.recoveryReason = p.recovery_reason;
          }
        }

        // v7.0: 决策生命周期事件 (工作包 B) — decisionLifecycle 不再只是占位字段
        if (event.type === "gate_block") {
          const p = event.payload as Record<string, unknown>;
          orchestration.decisionLifecycle = {
            requestId: (p.request_id as string) ?? `gate-${event.phase}-${event.sequence}`,
            phase: event.phase,
            action: "pending",
            state: "pending",
          };
        }
        if (event.type === "gate_pass") {
          if (orchestration.decisionLifecycle && orchestration.decisionLifecycle.phase === event.phase) {
            orchestration.decisionLifecycle = {
              ...orchestration.decisionLifecycle,
              state: "applied",
            };
          }
        }
      }

      // G2 fix: Auto-reset decisionAcked when a new gate_block arrives after the acked one
      let newDecisionAcked = state.decisionAcked;
      if (state.decisionAcked) {
        const hasNewBlock = newEvents.some(
          (e) => e.type === "gate_block" && e.sequence > state.lastAckedBlockSequence
        );
        if (hasNewBlock) {
          newDecisionAcked = false;
        }
      }

      const latestPhaseEvent = [...merged].reverse().find((event) => ![
        "transcript_message", "status_snapshot", "tool_prepare", "hook_event",
      ].includes(event.type));

      const transcriptEvents = merged.filter((e) => e.type === "transcript_message");
      const toolEvents = merged.filter((e) => e.type === "tool_use");

      // v5.4: Derive serverHealth from accumulated state
      const hasStatusSnapshot = merged.some((e) => e.type === "status_snapshot");
      const hasTranscript = merged.some((e) => e.type === "transcript_message");
      const newServerHealth: ServerHealth = {
        httpOk: state.serverHealth.httpOk, // preserved from WS/snapshot init, not hardcoded
        wsConnected: state.connected, // actual WS connection state
        telemetryAvailable: merged.length > 0,
        transcriptAvailable: hasTranscript,
        statusLineInstalled: hasStatusSnapshot,
      };

      return {
        events: merged,
        transcriptEvents,
        toolEvents,
        currentPhase: latestPhaseEvent?.phase ?? latest?.phase ?? state.currentPhase,
        sessionId: latest?.session_id ?? state.sessionId,
        changeName: latest?.change_name ?? state.changeName,
        mode: latest?.mode ?? state.mode,
        latestStatus,
        taskProgress: newTaskProgress,
        agentMap: newAgentMap,
        decisionAcked: newDecisionAcked,
        modelRouting,
        modelRoutingHistory,
        serverHealth: newServerHealth,
        parallelPlan,
        orchestration,
      };
    }),

  /** H-2/H-1: 从 server snapshot meta 初始化编排关键字段 */
  initOrchestrationFromMeta: (meta) =>
    set((state) => {
      const orchestration = { ...state.orchestration };
      let recoverySource = state.recoverySource;

      // H-2: archive readiness — 仅当事件流尚未提供时用 meta fallback
      if (meta.archiveReadiness && !orchestration.archiveReadiness) {
        const ar = meta.archiveReadiness;
        const checks = ar.checks as Record<string, unknown> | undefined;
        orchestration.archiveReadiness = {
          fixupComplete: Boolean(checks?.fixup_completeness && (checks.fixup_completeness as Record<string, unknown>)?.passed),
          reviewGatePassed: Boolean(checks?.review_findings_clear),
          ready: ar.overall === "ready",
        };
      }

      // H-1: requirement packet hash — 仅当事件流尚未提供时用 meta fallback
      if (meta.requirementPacketHash && !orchestration.requirementPacketHash) {
        orchestration.requirementPacketHash = meta.requirementPacketHash;
      }

      // v7.0: 恢复状态 (工作包 G) — recoverySource 不再永远是 null
      if (meta.recoverySource && !orchestration.recoverySource) {
        orchestration.recoverySource = meta.recoverySource as RecoverySource;
        recoverySource = meta.recoverySource as RecoverySource;
      }
      if (meta.recoveryReason && !orchestration.recoveryReason) {
        orchestration.recoveryReason = meta.recoveryReason;
      }

      // v7.0: 报告状态 (工作包 D) — 从 meta 初始化
      if (meta.reportState && !orchestration.reportState) {
        orchestration.reportState = {
          ...meta.reportState,
          report_format: meta.reportState.report_format as ReportState["report_format"],
        };
      }

      // v7.0: TDD 审计 (工作包 I)
      if (meta.tddAudit && !orchestration.tddAudit) {
        orchestration.tddAudit = meta.tddAudit;
      }

      return { orchestration, recoverySource };
    }),

  setConnected: (connected) => set((state) => ({
    connected,
    serverHealth: { ...state.serverHealth, wsConnected: connected },
  })),

  setHttpOk: (ok) => set((state) => ({
    serverHealth: { ...state.serverHealth, httpOk: ok },
  })),

  setDecisionAcked: (acked) => set({ decisionAcked: acked }),

  setLastAckedBlockSequence: (seq) => set({ lastAckedBlockSequence: seq }),

  reset: () =>
    set({
      events: [],
      transcriptEvents: [],
      toolEvents: [],
      // 注意：不重置 connected — reset 由 WS 消息触发，连接仍然活跃
      currentPhase: null,
      sessionId: null,
      changeName: null,
      mode: null,
      latestStatus: null,
      taskProgress: new Map(),
      agentMap: new Map(),
      decisionAcked: false,
      decisionLifecycle: null,
      recoverySource: null,
      lastAckedBlockSequence: -1,
      modelRouting: { ...DEFAULT_MODEL_ROUTING },
      modelRoutingHistory: [],
      serverHealth: { ...DEFAULT_SERVER_HEALTH },
      parallelPlan: { ...DEFAULT_PARALLEL_PLAN },
      orchestration: { ...DEFAULT_ORCHESTRATION },
    }),
}));
