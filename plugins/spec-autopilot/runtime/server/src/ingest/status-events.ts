/**
 * status-events.ts — Statusline 记录归一化
 *
 * 注意：statusline.jsonl 已按 session_key 做目录隔离（logs/sessions/<key>/raw/statusline.jsonl），
 * 因此本文件内所有记录天然属于同一 session。历史上这里对 `record.session_id === sessionId` 做
 * 严格过滤，会在 lockfile session 与当前 Claude Code UI 会话漂移时丢弃全部记录，
 * 导致 GUI 遥测顽固显示"未接入 statusLine 或当前会话暂无遥测"。
 * 现改为：只要记录自带 session_id 就信任文件-per-session 隔离，不再按 lockfile session 强过滤；
 * 事件的 session_id 采用记录自身的 session_id（失配时回退到传入的 sessionId）。
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
    .filter((record) => typeof record.session_id === "string" && record.session_id.length > 0)
    .map((record) => {
      const data = record.data || {};
      const timestamp = toIso(record.captured_at);
      const ctx = phaseLookup(timestamp);
      const mode = ctx.mode || fallback.mode;
      const effectiveSessionId = record.session_id || sessionId;
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
        session_id: effectiveSessionId,
        phase_label: ctx.phaseLabel,
        total_phases: ctx.totalPhases || totalPhases(mode),
        sequence: 0,
        payload,
        event_id: `status-${hashText(`${record.captured_at}|${JSON.stringify(data)}`)}`,
        ingest_seq: 0,
        source: "statusline",
        raw_ref: join("logs", "sessions", sanitizeSessionKey(effectiveSessionId), "raw", "statusline.jsonl"),
      };
    });
}
