/**
 * snapshot-builder.ts — 快照构建核心逻辑
 */

import { join } from "node:path";
import { EVENTS_FILE, SESSIONS_DIR, projectRoot as configProjectRoot } from "../config";
import type { ArchiveReadiness, AutopilotEvent, RawHookRecord, RawStatusRecord, SessionSnapshot, StateSnapshot } from "../types";
import { sanitizeSessionKey, toMillis } from "../utils";
import { getCurrentSessionContext } from "../session/session-context";
import { readJsonLinesCached } from "../session/file-cache";
import { existsSync, readFileSync } from "node:fs";
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
      stateSnapshot: null,
      archiveReadiness: null,
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

  // D3: 从 .active-agent-session-{key} marker 文件读取当前活跃 agent_id，
  // 为缺少 agentId 的 agent 类型 descriptor 补充关联
  const agentMarkerPath = join(configProjectRoot || process.cwd(), "logs", `.active-agent-session-${sessionKey}`);
  let fallbackAgentId: string | undefined;
  if (existsSync(agentMarkerPath)) {
    try {
      fallbackAgentId = readFileSync(agentMarkerPath, "utf-8").trim() || undefined;
    } catch {
      // 读取失败忽略
    }
  }
  if (fallbackAgentId) {
    for (const desc of transcriptDescriptors) {
      if (desc.kind === "agent" && !desc.agentId) {
        desc.agentId = fallbackAgentId;
      }
    }
  }

  const transcriptEvents = await parseTranscriptEvents(transcriptDescriptors, sessionId, phaseLookup, { changeName: context.changeName, mode: context.mode }).catch(() => []);

  const events = sortAndFinalize([...legacyEvents, ...hookEvents, ...statusEvents, ...transcriptEvents]);
  const journalPath = await writeJournal(sessionKey, events);

  // 读取 state-snapshot.json（v6.0 结构化控制态）
  // H-3 修复: 优先使用 config.ts 解析的 --project-root CLI 参数，env var 仅作 fallback
  let stateSnapshot: StateSnapshot | null = null;
  const projectRoot = configProjectRoot || process.env.AUTOPILOT_PROJECT_ROOT;
  if (projectRoot && context.changeName && context.changeName !== "unknown") {
    const changeContextDir = join(projectRoot, "openspec", "changes", context.changeName, "context");
    const snapshotPath = join(changeContextDir, "state-snapshot.json");
    if (existsSync(snapshotPath)) {
      try {
        stateSnapshot = JSON.parse(readFileSync(snapshotPath, "utf-8")) as StateSnapshot;
      } catch {
        // 解析失败时保持 null
      }
    }

    // H-2: 读取 archive-readiness.json（Phase 7 构建的归档就绪判定）
    let archiveReadiness: ArchiveReadiness | null = null;
    const archiveReadinessPath = join(changeContextDir, "archive-readiness.json");
    if (existsSync(archiveReadinessPath)) {
      try {
        archiveReadiness = JSON.parse(readFileSync(archiveReadinessPath, "utf-8")) as ArchiveReadiness;
      } catch {
        // 解析失败时保持 null
      }
    }

    return {
      sessionId,
      sessionKey,
      changeName: context.changeName,
      mode: context.mode,
      events,
      journalPath,
      telemetryAvailable: statusEvents.length > 0,
      transcriptAvailable: transcriptEvents.length > 0,
      stateSnapshot,
      archiveReadiness,
    };
  }

  return {
    sessionId,
    sessionKey,
    changeName: context.changeName,
    mode: context.mode,
    events,
    journalPath,
    telemetryAvailable: statusEvents.length > 0,
    transcriptAvailable: transcriptEvents.length > 0,
    stateSnapshot,
    archiveReadiness: null,
  };
}
