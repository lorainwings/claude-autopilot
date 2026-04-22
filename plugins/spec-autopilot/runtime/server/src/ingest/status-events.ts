/**
 * status-events.ts — Statusline 记录归一化
 */

import { join } from "node:path";
import type { AutopilotEvent, AutopilotMode, PhaseContext, RawStatusRecord } from "../types";
import { hashText, sanitizeSessionKey, toIso, totalPhases } from "../utils";

export function normalizeStatusRecords(
  records: RawStatusRecord[],
  sessionId: string,
  phaseLookup: (ts: string) => PhaseContext,
  fallback: { changeName: string; mode: AutopilotMode },
): AutopilotEvent[] {
  return records
    .filter((record) => record.session_id === sessionId)
    .map((record) => {
      const data = record.data || {};
      const timestamp = toIso(record.captured_at);
      const ctx = phaseLookup(timestamp);
      const mode = ctx.mode || fallback.mode;
      const payload: Record<string, unknown> = {
        model: data.model,
        cwd: data.cwd ?? record.cwd,
        transcript_path: data.transcript_path ?? record.transcript_path,
        cost: data.cost ?? data.cost_usd ?? data.total_cost_usd,
        context_window: data.context_window,
        worktree: data.worktree,
        version: data.version,
        // seed 模式下 data.source === 'seed'，透传给前端以区分"占位"与"真实"快照
        snapshot_source: (data as Record<string, unknown>).source,
      };
      return {
        type: "status_snapshot",
        phase: ctx.phase,
        mode,
        timestamp,
        change_name: ctx.changeName || fallback.changeName,
        session_id: sessionId,
        phase_label: ctx.phaseLabel,
        total_phases: ctx.totalPhases || totalPhases(mode),
        sequence: 0,
        payload,
        event_id: `status-${hashText(`${record.captured_at}|${JSON.stringify(data)}`)}`,
        ingest_seq: 0,
        source: "statusline",
        raw_ref: join("logs", "sessions", sanitizeSessionKey(sessionId), "raw", "statusline.jsonl"),
      };
    });
}
