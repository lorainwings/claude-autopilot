/**
 * broadcaster.ts — WebSocket 广播
 */

import type { AutopilotEvent } from "../types";
import { snapshotState, wsClients } from "../state";
import { sanitizeForApi } from "../security/sanitize";

/** 构建 snapshot 消息中的 meta 字段（从 snapshotState 提取编排关键数据） */
function buildSnapshotMeta(): Record<string, unknown> {
  return {
    archiveReadiness: snapshotState.archiveReadiness ?? null,
    requirementPacketHash: snapshotState.stateSnapshot?.requirement_packet_hash ?? null,
    gateFrontier: snapshotState.stateSnapshot?.gate_frontier ?? null,
  };
}

export function broadcastReset() {
  const payload = JSON.stringify({ type: "reset" });
  for (const ws of wsClients) {
    try {
      ws.send(payload);
    } catch {
      wsClients.delete(ws);
    }
  }
}

export function broadcastSnapshot(events: AutopilotEvent[]) {
  const sanitized = events.map(e => sanitizeForApi(e));
  const payload = JSON.stringify({ type: "snapshot", data: sanitized, meta: buildSnapshotMeta() });
  for (const ws of wsClients) {
    try {
      ws.send(payload);
    } catch {
      wsClients.delete(ws);
    }
  }
}

export function broadcastEvents(events: AutopilotEvent[]) {
  for (const event of events) {
    const sanitized = sanitizeForApi(event);
    const payload = JSON.stringify({ type: "event", data: sanitized });
    for (const ws of wsClients) {
      try {
        ws.send(payload);
      } catch {
        wsClients.delete(ws);
      }
    }
  }
}
