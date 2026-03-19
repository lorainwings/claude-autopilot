/**
 * snapshot-builder.ts — 快照构建核心逻辑
 */

import { join } from "node:path";
import { EVENTS_FILE, SESSIONS_DIR } from "../config";
import type { AutopilotEvent, RawHookRecord, RawStatusRecord, SessionSnapshot } from "../types";
import { sanitizeSessionKey, toMillis } from "../utils";
import { getCurrentSessionContext } from "../session/session-context";
import { readJsonLinesCached } from "../session/file-cache";
import { normalizeLegacyEvents } from "../ingest/legacy-events";
import { normalizeHookRecords } from "../ingest/hook-events";
import { normalizeStatusRecords } from "../ingest/status-events";
import { collectTranscriptDescriptors, parseTranscriptEvents } from "../ingest/transcript-events";
import { buildPhaseLookup } from "./phase-lookup";
import { writeJournal } from "./journal-writer";

/** 去重 + 排序 + 分配 ingest_seq */
export function sortAndFinalize(events: AutopilotEvent[]): AutopilotEvent[] {
  const deduped = new Map<string, AutopilotEvent>();
  for (const event of events) {
    const existing = deduped.get(event.event_id);
    if (!existing) {
      deduped.set(event.event_id, event);
      continue;
    }
    if (existing.source === "legacy" && event.source !== "legacy") {
      deduped.set(event.event_id, event);
    }
  }

  return Array.from(deduped.values())
    .sort((a, b) => {
      const ta = toMillis(a.timestamp);
      const tb = toMillis(b.timestamp);
      if (ta !== tb) return ta - tb;
      const sa = a.sequence || 0;
      const sb = b.sequence || 0;
      if (sa !== sb) return sa - sb;
      return a.event_id.localeCompare(b.event_id);
    })
    .map((event, index) => ({ ...event, ingest_seq: index + 1 }));
}

async function readSessionRawRecords<T>(sessionKey: string, filename: string): Promise<T[]> {
  const filePath = join(SESSIONS_DIR, sessionKey, "raw", filename);
  return readJsonLinesCached<T>(filePath);
}

export async function buildSnapshot(): Promise<SessionSnapshot> {
  const context = await getCurrentSessionContext();
  if (!context.sessionId) {
    return {
      sessionId: null,
      sessionKey: null,
      changeName: context.changeName,
      mode: context.mode,
      events: [],
      journalPath: null,
      telemetryAvailable: false,
      transcriptAvailable: false,
    };
  }

  const sessionId = context.sessionId;
  const sessionKey = sanitizeSessionKey(sessionId);
  const legacyRaw = await readJsonLinesCached<Record<string, unknown>>(EVENTS_FILE);
  const legacyEvents = normalizeLegacyEvents(legacyRaw, sessionId, { changeName: context.changeName, mode: context.mode });
  const phaseLookup = buildPhaseLookup(legacyEvents);

  const rawHooks = await readSessionRawRecords<RawHookRecord>(sessionKey, "hooks.jsonl");
  const rawStatus = await readSessionRawRecords<RawStatusRecord>(sessionKey, "statusline.jsonl");

  const hookEvents = normalizeHookRecords(rawHooks, sessionId, phaseLookup, { changeName: context.changeName, mode: context.mode });
  const statusEvents = normalizeStatusRecords(rawStatus, sessionId, phaseLookup, { changeName: context.changeName, mode: context.mode });
  const transcriptDescriptors = collectTranscriptDescriptors(rawHooks, rawStatus);
  const transcriptEvents = await parseTranscriptEvents(transcriptDescriptors, sessionId, phaseLookup, { changeName: context.changeName, mode: context.mode }).catch(() => []);

  const events = sortAndFinalize([...legacyEvents, ...hookEvents, ...statusEvents, ...transcriptEvents]);
  const journalPath = await writeJournal(sessionKey, events);

  return {
    sessionId,
    sessionKey,
    changeName: context.changeName,
    mode: context.mode,
    events,
    journalPath,
    telemetryAvailable: statusEvents.length > 0,
    transcriptAvailable: transcriptEvents.length > 0,
  };
}
