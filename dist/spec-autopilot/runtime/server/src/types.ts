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
