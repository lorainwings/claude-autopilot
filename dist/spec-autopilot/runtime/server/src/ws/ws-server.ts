/**
 * ws-server.ts — WebSocket 服务器
 */

import type { ServerWebSocket } from "bun";
import { WS_PORT } from "../config";
import { snapshotState, wsClients } from "../state";
import { sanitizeForApi } from "../security/sanitize";
import { handleDecision } from "../decision/decision-service";

export function createWsServer() {
  return Bun.serve({
    hostname: "127.0.0.1",
    port: WS_PORT,
    fetch(req: Request, server: { upgrade(request: Request): boolean }) {
      if (server.upgrade(req)) return;
      const url = new URL(req.url);
      if (url.pathname === "/health") {
        return new Response(JSON.stringify({
          status: "ok",
          service: "autopilot-ws",
          clients: wsClients.size,
          sessionId: snapshotState.sessionId,
          journalPath: snapshotState.journalPath,
          telemetryAvailable: snapshotState.telemetryAvailable,
          transcriptAvailable: snapshotState.transcriptAvailable,
          uptimeMs: Math.floor(process.uptime() * 1000),
          pid: process.pid,
        }), { headers: { "Content-Type": "application/json" } });
      }
      return new Response("WebSocket server. Connect via ws://", { status: 200 });
    },
    websocket: {
      open(ws: ServerWebSocket<unknown>) {
        wsClients.add(ws);
        const sanitized = snapshotState.events.map(e => sanitizeForApi(e));
        const meta = {
          archiveReadiness: snapshotState.archiveReadiness ?? null,
          requirementPacketHash: snapshotState.stateSnapshot?.requirement_packet_hash ?? null,
          gateFrontier: snapshotState.stateSnapshot?.gate_frontier ?? null,
        };
        ws.send(JSON.stringify({ type: "snapshot", data: sanitized, meta }));
      },
      message(ws: ServerWebSocket<unknown>, message: string | Uint8Array | ArrayBuffer) {
        try {
          const msg = JSON.parse(String(message)) as { type?: string; data?: { action: string; phase: number; reason?: string } };
          if (msg.type === "ping") {
            ws.send(JSON.stringify({ type: "pong", timestamp: Date.now() }));
          } else if (msg.type === "decision" && msg.data) {
            handleDecision(msg.data).catch(console.error);
          }
        } catch {
          // ignore malformed payload
        }
      },
      close(ws: ServerWebSocket<unknown>) {
        wsClients.delete(ws);
      },
    },
  });
}
