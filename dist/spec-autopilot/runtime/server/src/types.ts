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
}

export interface PhaseContext {
  phase: number;
  phaseLabel: string;
  mode: AutopilotMode;
  totalPhases: number;
  changeName: string;
}

// --- 模型路由类型 (v5.3) ---

export type ModelTier = "fast" | "standard" | "deep" | "auto";
export type ModelName = "haiku" | "sonnet" | "opus" | "opusplan" | "auto";
export type EffortLevel = "low" | "medium" | "high";

export interface ModelRoutingEvidence {
  selected_tier: ModelTier;
  selected_model: ModelName;
  selected_effort: EffortLevel;
  routing_reason: string;
  escalated_from: ModelTier | null;
  fallback_applied: boolean;
  /** dispatch 运行时用：当 Task 因模型不可用失败时，用此模型重试 */
  fallback_model: ModelName | null;
}

export interface ModelRoutingEvent extends AutopilotEvent {
  type: "model_routing";
  payload: ModelRoutingEvidence & {
    agent_id?: string;
  };
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
