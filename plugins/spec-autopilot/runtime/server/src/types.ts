/**
 * types.ts — 共享类型定义
 */

export type AutopilotMode = "full" | "lite" | "minimal";

export interface AutopilotEvent {
  type: string;
  phase: number;
  mode: AutopilotMode;
  timestamp: string;
  change_name: string;
  session_id: string;
  phase_label: string;
  total_phases: number;
  sequence: number;
  payload: Record<string, unknown>;
  event_id: string;
  ingest_seq: number;
  source: "legacy" | "hook" | "statusline" | "transcript";
  raw_ref?: string;
}

export interface RawHookRecord {
  source: "hook";
  hook_name: string;
  captured_at: string;
  project_root?: string;
  session_id: string;
  session_key?: string;
  cwd?: string;
  transcript_path?: string;
  agent_transcript_path?: string;
  active_agent_id?: string | null;
  data: Record<string, unknown>;
}

export interface RawStatusRecord {
  source: "statusline";
  captured_at: string;
  project_root?: string;
  session_id: string;
  session_key?: string;
  cwd?: string;
  transcript_path?: string;
  data: Record<string, unknown>;
}

export interface SessionSnapshot {
  sessionId: string | null;
  sessionKey: string | null;
  changeName: string;
  mode: AutopilotMode;
  events: AutopilotEvent[];
  journalPath: string | null;
  telemetryAvailable: boolean;
  transcriptAvailable: boolean;
  stateSnapshot: StateSnapshot | null;
  /** H-2: Phase 7 archive-readiness.json 归档就绪判定 */
  archiveReadiness: ArchiveReadiness | null;
}

export interface PhaseContext {
  phase: number;
  phaseLabel: string;
  mode: AutopilotMode;
  totalPhases: number;
  changeName: string;
}

// --- 模型路由类型 (v5.3 → v5.4 可观测性闭环) ---

export type ModelTier = "fast" | "standard" | "deep" | "auto";
export type ModelName = "haiku" | "sonnet" | "opus" | "opusplan" | "auto";
export type EffortLevel = "low" | "medium" | "high";

/**
 * 模型状态语义（v5.4 诚实降级）:
 * - requested: 路由器建议使用的模型（已发射 model_routing 事件）
 * - effective: 运行时实际确认使用的模型（statusLine/transcript 推断）
 * - fallback: 因原模型不可用，降级到 fallback 模型
 * - unknown: 无法确认实际模型（平台限制）
 * - unsupported: 当前环境不支持 per-task model 切换
 */
export type ModelStatus = "requested" | "effective" | "fallback" | "unknown" | "unsupported";

export interface ModelRoutingEvidence {
  selected_tier: ModelTier;
  selected_model: ModelName;
  selected_effort: EffortLevel;
  routing_reason: string;
  escalated_from: ModelTier | null;
  fallback_applied: boolean;
  /** dispatch 运行时用：当 Task 因模型不可用失败时，用此模型重试 */
  fallback_model: ModelName | null;
  [key: string]: unknown;
}

export interface ModelRoutingEvent extends AutopilotEvent {
  type: "model_routing";
  payload: ModelRoutingEvidence & {
    agent_id?: string;
  };
}

/** model_effective 事件 — 运行时确认实际模型 */
export interface ModelEffectiveEvent extends AutopilotEvent {
  type: "model_effective";
  payload: {
    effective_model: string;
    effective_tier: ModelTier | "unknown";
    inference_source: "statusline" | "transcript" | "api_response" | "config";
    requested_model?: string;
    match: boolean;            // effective 是否与 requested 一致
    agent_id?: string;
  };
}

/** model_fallback 事件 — 模型降级触发 */
export interface ModelFallbackEvent extends AutopilotEvent {
  type: "model_fallback";
  payload: {
    requested_model: string;
    fallback_model: string;
    fallback_reason: string;
    agent_id?: string;
  };
}

/** GUI 消费的模型路由聚合状态 */
export interface ModelRoutingState {
  /** 路由器请求的模型 */
  requested_model: string | null;
  requested_tier: ModelTier | null;
  requested_effort: EffortLevel | null;
  /** 运行时实际观测到的模型 */
  effective_model: string | null;
  /** 降级后使用的模型 */
  fallback_model: string | null;
  /** 当前模型状态 */
  model_status: ModelStatus;
  /** 路由决策理由 */
  routing_reason: string | null;
  /** 是否发生了降级 */
  fallback_applied: boolean;
  /** 降级原因 */
  fallback_reason: string | null;
  /** 推断来源 */
  inference_source: string | null;
  /** 能力说明（平台限制时显示） */
  capability_note: string | null;
  /** 当前 phase */
  phase: number;
  /** agent id */
  agent_id: string | null;
  /** 最后更新时间 */
  updated_at: string | null;
}

/** 旧格式兼容: heavy/light/auto */
export type LegacyModelRouting = "heavy" | "light" | "auto";

/** 新格式 phase 级配置 */
export interface PhaseModelConfig {
  tier?: ModelTier | "auto";
  model?: ModelName;
  effort?: EffortLevel;
  escalate_on_failure_to?: ModelTier | ModelName;
}

/** 新格式完整 model_routing 配置 */
export interface ModelRoutingConfig {
  enabled?: boolean;
  default_session_model?: ModelName | ModelTier;
  default_subagent_model?: ModelName | ModelTier;
  fallback_model?: ModelName | ModelTier;
  phases?: Record<string, PhaseModelConfig | LegacyModelRouting>;
}

// --- v6.0 新增类型 ---

/** 恢复来源枚举 — GUI 可见恢复状态 (工作包 G) */
export type RecoverySource =
  | "fresh"
  | "snapshot_resume"
  | "checkpoint_resume"
  | "progress_resume"
  | "snapshot_hash_mismatch";

/** 报告状态 — Phase 6 测试报告产物 (工作包 D) */
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

/** TDD 审计摘要 — Phase 5 TDD 产物 (工作包 I) */
export interface TddAuditSummary {
  cycle_count: number;
  red_violations: number;
  green_violations: number;
  refactor_rollbacks: number;
  red_commands: string[];
  green_commands: string[];
}

/** Dispatch 计划/实际记录 (工作包 H) */
export interface DispatchRecord {
  requested_agent: string;
  resolved_agent: string;
  priority_source: "project" | "plugin" | "builtin";
  ownership: string[];
  validators: string[];
  model_routing: string | null;
  status: "planned" | "dispatched" | "completed" | "failed" | "reconciled";
}

/** Fixup manifest 条目 (工作包 J) */
export interface FixupManifestEntry {
  checkpoint_id: string;
  checkpoint_phase: number;
  expected_fixup_message: string;
  actual_sha: string | null;
  squash_result: "pending" | "squashed" | "missing";
}

/** state-snapshot.json 结构化控制态 (v7.0 — 统一控制面) */
export interface StateSnapshot {
  schema_version: string;
  snapshot_hash: string;
  /** 执行模式 */
  mode: AutopilotMode;
  /** 当前 phase */
  current_phase: number;
  /** 已执行的 phase 列表 */
  executed_phases: number[];
  /** 已跳过的 phase 列表 (mode-dependent) */
  skipped_phases: number[];
  /** gate 前沿 */
  gate_frontier: number;
  next_action: string;
  /** 恢复来源 */
  recovery_source: RecoverySource;
  /** 恢复原因 */
  recovery_reason: string | null;
  /** 恢复置信度 */
  recovery_confidence: "high" | "medium" | "low" | null;
  /** 恢复起始 phase */
  resume_from_phase: number | null;
  /** 恢复时丢弃的产物 */
  discarded_artifacts: string[];
  /** 恢复时需要重放的任务 */
  replay_required_tasks: string[];
  /** 需求包哈希 */
  requirement_packet_hash: string | null;
  /** 各 phase 结果 */
  phase_results: Record<string, { status: string; timestamp: string }>;
  /** review 状态 */
  review_status: string | null;
  /** fixup 状态 */
  fixup_status: string | null;
  /** 归档状态 */
  archive_status: string | null;
  /** 报告状态 (工作包 D) */
  report_state: ReportState | null;
  /** TDD 审计摘要 (工作包 I) */
  tdd_audit: TddAuditSummary | null;
  /** 活跃 agent 列表 */
  active_agents: DispatchRecord[];
  /** 活跃任务列表 */
  active_tasks: string[];
  /** 模型路由信息 */
  model_routing: {
    requested_model: string | null;
    effective_model: string | null;
    fallback_model: string | null;
    routing_reason: string | null;
  } | null;
}

/** archive-readiness.json 归档就绪判定 (Phase 7, WS-H) */
export interface ArchiveReadiness {
  timestamp: string;
  mode: string;
  checks: {
    all_checkpoints_ok: boolean;
    fixup_completeness: { passed: boolean; fixup_count: number; checkpoint_count: number };
    anchor_valid: boolean;
    worktree_clean: boolean;
    review_findings_clear: boolean;
    zero_skip_passed: boolean;
  };
  overall: "ready" | "blocked";
  block_reasons: string[];
}

/** 编排概览状态 — GUI store 消费 (WS-D) */
export interface OrchestrationOverview {
  goalSummary: string | null;
  currentSubStep: string | null;
  gateFrontierReason: string | null;
  requirementPacketHash: string | null;
  contextBudget: { percent: number; risk: "low" | "medium" | "high" } | null;
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

/** Review finding 结构 (WS-E) */
export interface ReviewFinding {
  id: string;
  severity: "info" | "warning" | "critical";
  evidence: string;
  blocking: boolean;
  owner: string;
  resolved: boolean;
}

/** Agent dispatch 审计记录 (WS-E) */
export interface AgentDispatchRecord {
  agent_id: string;
  agent_class: string;
  phase: number;
  selection_reason: string;
  resolved_priority: string;
  owned_artifacts: string[];
  background: boolean;
  scanned_sources: string[];
  required_validators: string[];
  fallback_reason: string | null;
}

/** Requirement packet (WS-A) */
export interface RequirementPacket {
  schema_version: string;
  hash: string;
  requirement_maturity: "clear" | "partial" | "ambiguous";
  goal: string;
  scope: string[];
  non_goals: string[];
  acceptance_criteria: string[];
  assumptions: string[];
  risks: string[];
  open_questions: string[];
  decision_log: Array<{ question: string; decision: string; rationale: string }>;
}
