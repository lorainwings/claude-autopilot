/**
 * broadcaster.ts — WebSocket 广播
 */

import type { AutopilotEvent } from "../types";
import { wsClients } from "../state";
import { sanitizeForApi } from "../security/sanitize";

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
  const payload = JSON.stringify({ type: "snapshot", data: sanitized });
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
