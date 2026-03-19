/**
 * transcript-events.ts — Transcript 解析
 */

import { access } from "node:fs/promises";
import type { AutopilotEvent, AutopilotMode, PhaseContext, RawHookRecord, RawStatusRecord } from "../types";
import { detectTranscriptRole, extractTranscriptText, getNestedString, hashText, toIso, totalPhases, truncateText } from "../utils";
import { readJsonLinesCached } from "../session/file-cache";

export function collectTranscriptDescriptors(
  hooks: RawHookRecord[],
  statuses: RawStatusRecord[],
) {
  const descriptors: Array<{ path: string; kind: "main" | "agent"; agentId?: string; discoveredAt: string }> = [];
  for (const record of hooks) {
    if (record.transcript_path) {
      descriptors.push({ path: record.transcript_path, kind: "main", discoveredAt: record.captured_at });
    }
    if (record.agent_transcript_path) {
      descriptors.push({
        path: record.agent_transcript_path,
        kind: "agent",
        agentId: record.active_agent_id ?? getNestedString(record.data, "agent_id", "payload.agent_id"),
        discoveredAt: record.captured_at,
      });
    }
  }
  for (const record of statuses) {
    if (record.transcript_path) {
      descriptors.push({ path: record.transcript_path, kind: "main", discoveredAt: record.captured_at });
    }
  }
  return descriptors;
}

export async function parseTranscriptEvents(
  paths: Array<{ path: string; kind: "main" | "agent"; agentId?: string; discoveredAt: string }>,
  sessionId: string,
  phaseLookup: (ts: string) => PhaseContext,
  fallback: { changeName: string; mode: AutopilotMode },
): Promise<AutopilotEvent[]> {
  const events: AutopilotEvent[] = [];
  const seen = new Set<string>();

  for (const descriptor of paths) {
    if (!descriptor.path || seen.has(`${descriptor.kind}:${descriptor.path}`)) continue;
    seen.add(`${descriptor.kind}:${descriptor.path}`);
    try {
      await access(descriptor.path);
    } catch {
      continue;
    }
    const lines = await readJsonLinesCached<Record<string, unknown>>(descriptor.path).catch(() => []);
    lines.forEach((line, index) => {
      const role = detectTranscriptRole(line);
      const text = extractTranscriptText(line);
      if (!text) return;
      const fallbackTs = new Date(Date.parse(descriptor.discoveredAt || "1970-01-01T00:00:00.000Z") + index).toISOString();
      const timestamp = toIso(
        getNestedString(line, "timestamp", "created_at", "time", "message.timestamp"),
        fallbackTs
      );
      const ctx = phaseLookup(timestamp);
      const mode = ctx.mode || fallback.mode;
      const payload: Record<string, unknown> = {
        role,
        text,
        text_preview: truncateText(text, 400),
        transcript_kind: descriptor.kind,
        transcript_path: descriptor.path,
      };
      if (descriptor.agentId) payload.agent_id = descriptor.agentId;
      events.push({
        type: "transcript_message",
        phase: ctx.phase,
        mode,
        timestamp,
        change_name: ctx.changeName || fallback.changeName,
        session_id: sessionId,
        phase_label: ctx.phaseLabel,
        total_phases: ctx.totalPhases || totalPhases(mode),
        sequence: 0,
        payload,
        event_id: `transcript-${hashText(`${descriptor.path}|${index}|${JSON.stringify(line)}`)}`,
        ingest_seq: 0,
        source: "transcript",
        raw_ref: descriptor.path,
      });
    });
  }

  return events;
}
