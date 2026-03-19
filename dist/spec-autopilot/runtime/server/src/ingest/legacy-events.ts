/**
 * legacy-events.ts — 旧 events.jsonl 归一化
 */

import type { AutopilotEvent, AutopilotMode } from "../types";
import { getPhaseLabel, hashText, normalizeMode, toIso, totalPhases } from "../utils";

export function normalizeLegacyEvents(
  items: Record<string, unknown>[],
  sessionId: string,
  fallback: { changeName: string; mode: AutopilotMode },
): AutopilotEvent[] {
  return items
    .filter((item) => item.session_id === sessionId)
    .filter((item) => item.type !== "tool_use")
    .map((item) => {
      const phase = typeof item.phase === "number" ? item.phase : 0;
      const mode = normalizeMode(item.mode, fallback.mode);
      const timestamp = toIso(item.timestamp);
      const payload = typeof item.payload === "object" && item.payload ? item.payload as Record<string, unknown> : {};
      const sequence = typeof item.sequence === "number" ? item.sequence : 0;
      const raw = JSON.stringify(item);
      return {
        type: typeof item.type === "string" ? item.type : "legacy_event",
        phase,
        mode,
        timestamp,
        change_name: typeof item.change_name === "string" && item.change_name ? item.change_name : fallback.changeName,
        session_id: sessionId,
        phase_label: typeof item.phase_label === "string" && item.phase_label ? item.phase_label : getPhaseLabel(phase),
        total_phases: typeof item.total_phases === "number" ? item.total_phases : totalPhases(mode),
        sequence,
        payload,
        event_id: `legacy-${hashText(raw)}`,
        ingest_seq: 0,
        source: "legacy",
        raw_ref: "logs/events.jsonl",
      } satisfies AutopilotEvent;
    });
}
