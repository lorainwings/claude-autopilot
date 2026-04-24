/**
 * routes.ts — HTTP API 路由 + 静态文件服务
 */

import { readFile } from "node:fs/promises";
import { extname, join } from "node:path";
import { GUI_DIST, HTTP_PORT, MIME_TYPES, SESSIONS_DIR, WS_PORT } from "../config";
import { snapshotState, wsClients } from "../state";
import { sanitizeForApi, sanitizePath, corsHeaders } from "../security/sanitize";
import { ensurePluginVersion } from "../session/session-context";
import { projectRoot } from "../config";

async function serveStaticFile(filePath: string): Promise<Response> {
  try {
    const file = Bun.file(filePath);
    if (await file.exists()) {
      const ext = extname(filePath);
      const contentType = MIME_TYPES[ext] || "application/octet-stream";
      const cacheControl = ext === ".html" ? "no-store, no-cache, must-revalidate" : "public, max-age=31536000, immutable";
      return new Response(file, {
        headers: {
          "Content-Type": contentType,
          "Cache-Control": cacheControl,
        },
      });
    }
  } catch {
    // fall through
  }
  return new Response(null, { status: 404 });
}

export function createHttpServer() {
  return Bun.serve({
    hostname: "127.0.0.1",
    port: HTTP_PORT,
    async fetch(req: Request) {
      const url = new URL(req.url);

      if (req.method === "OPTIONS") {
        return new Response(null, { headers: corsHeaders(req) });
      }

      if (url.pathname === "/api/events") {
        const offset = parseInt(url.searchParams.get("offset") || "0", 10);
        const events = snapshotState.events.filter((event) => event.ingest_seq > offset);
        const sanitized = events.map(e => sanitizeForApi(e));
        return new Response(JSON.stringify({
          events: sanitized,
          total: snapshotState.events.length,
          sessionId: snapshotState.sessionId,
        }), {
          headers: { "Content-Type": "application/json", ...corsHeaders(req) },
        });
      }

      if (url.pathname === "/api/info") {
        const version = await ensurePluginVersion();
        // Derive currentPhase from events (latest phase field from phase_start/phase_end events)
        let currentPhase: number | null = null;
        for (let i = snapshotState.events.length - 1; i >= 0; i--) {
          const e = snapshotState.events[i]!;
          if ((e.type === "phase_start" || e.type === "phase_end") && e.phase != null) {
            currentPhase = e.phase;
            break;
          }
        }
        const ss = snapshotState.stateSnapshot;
        return new Response(JSON.stringify({
          version,
          projectRoot: sanitizePath(projectRoot),
          wsPort: WS_PORT,
          httpPort: HTTP_PORT,
          guiDist: sanitizePath(GUI_DIST),
          sessionId: snapshotState.sessionId,
          changeName: snapshotState.changeName,
          journalPath: snapshotState.journalPath ? sanitizePath(snapshotState.journalPath) : null,
          telemetryAvailable: snapshotState.telemetryAvailable,
          transcriptAvailable: snapshotState.transcriptAvailable,
          mode: snapshotState.mode || null,
          currentPhase,
          // H-2: 暴露 archive readiness 状态
          archiveReadiness: snapshotState.archiveReadiness ?? null,
          // H-1/H-3: 暴露 stateSnapshot 关键字段
          requirementPacketHash: ss?.requirement_packet_hash ?? null,
          // v7.1: Phase 1 清晰度系统
          clarityScore: ss?.clarity_score ?? null,
          discussionRounds: ss?.discussion_rounds ?? null,
          challengeAgentsActivated: ss?.challenge_agents_activated ?? [],
          gateFrontier: ss?.gate_frontier ?? null,
          // v7.0: 暴露恢复状态 (工作包 G)
          recoverySource: ss?.recovery_source ?? null,
          recoveryReason: ss?.recovery_reason ?? null,
          recoveryConfidence: ss?.recovery_confidence ?? null,
          // v7.0: 暴露报告状态 (工作包 D)
          reportState: ss?.report_state ?? null,
          // v7.0: 暴露 TDD 审计 (工作包 I)
          tddAudit: ss?.tdd_audit ?? null,
          // v7.0: 暴露执行 phase 信息
          executedPhases: ss?.executed_phases ?? [],
          skippedPhases: ss?.skipped_phases ?? [],
          // v7.0: 活跃 agent 和任务
          activeAgents: ss?.active_agents ?? [],
          activeTasks: ss?.active_tasks ?? [],
        }), {
          headers: { "Content-Type": "application/json", ...corsHeaders(req) },
        });
      }

      if (url.pathname === "/api/health") {
        const version = await ensurePluginVersion();
        const uptimeMs = Math.floor(process.uptime() * 1000);
        const wsClientCount = wsClients.size;

        // 结构化健康检查: HTTP、WS、snapshot、telemetry、transcript 分开报告
        const health = {
          status: "ok" as "ok" | "degraded" | "error",
          version,
          uptimeMs,
          pid: process.pid,
          checks: {
            http: { status: "ok" as const },
            ws: {
              status: wsClientCount > 0 ? "ok" as const : "no_clients" as const,
              clients: wsClientCount,
            },
            snapshot: {
              status: snapshotState.sessionId ? "ok" as const : "no_session" as const,
              sessionId: snapshotState.sessionId,
              eventCount: snapshotState.events.length,
            },
            telemetry: {
              status: snapshotState.telemetryAvailable ? "ok" as const : "unavailable" as const,
            },
            transcript: {
              status: snapshotState.transcriptAvailable ? "ok" as const : "unavailable" as const,
            },
          },
        };

        // 如果核心功能不可用，标记为 degraded
        if (!snapshotState.sessionId || !snapshotState.telemetryAvailable) {
          health.status = "degraded";
        }

        return new Response(JSON.stringify(health), {
          headers: { "Content-Type": "application/json", ...corsHeaders(req) },
        });
      }

      if (url.pathname === "/api/raw") {
        const kind = url.searchParams.get("kind");
        const sessionKey = snapshotState.sessionKey;
        if (!sessionKey || !kind) {
          return new Response(JSON.stringify({ lines: [] }), {
            headers: { "Content-Type": "application/json", ...corsHeaders(req) },
          });
        }
        // 统一读取 events.jsonl，按 source 字段过滤出 hooks / statusline 子流
        const sourceFilter = kind === "hooks" ? "hook" : kind === "statusline" ? "statusline" : null;
        if (!sourceFilter) {
          return new Response(JSON.stringify({ lines: [] }), {
            headers: { "Content-Type": "application/json", ...corsHeaders(req) },
          });
        }
        const filePath = join(SESSIONS_DIR, sessionKey, "raw", "events.jsonl");
        try {
          const rawLines = (await readFile(filePath, "utf-8")).split("\n").filter(Boolean);
          const lines: string[] = [];
          for (const l of rawLines) {
            try {
              const parsed = JSON.parse(l);
              if (parsed?.source !== sourceFilter) continue;
              lines.push(JSON.stringify(sanitizeForApi(parsed)));
            } catch {
              // 丢弃无法解析的行：kind 过滤依赖 source 字段
            }
          }
          return new Response(JSON.stringify({ lines, filePath: sanitizePath(filePath) }), {
            headers: { "Content-Type": "application/json", ...corsHeaders(req) },
          });
        } catch {
          return new Response(JSON.stringify({ lines: [], filePath: sanitizePath(filePath) }), {
            headers: { "Content-Type": "application/json", ...corsHeaders(req) },
          });
        }
      }

      if (url.pathname === "/api/raw-tail") {
        const kind = url.searchParams.get("kind");
        const cursor = parseInt(url.searchParams.get("cursor") || "0", 10);
        const maxLines = Math.min(parseInt(url.searchParams.get("lines") || "120", 10), 500);
        const sessionKey = snapshotState.sessionKey;
        if (!sessionKey || !kind) {
          return Response.json({ lines: [], cursor: 0, fileSize: 0 },
            { headers: { "Content-Type": "application/json", ...corsHeaders(req) } });
        }
        const sourceFilter = kind === "hooks" ? "hook" : kind === "statusline" ? "statusline" : null;
        if (!sourceFilter) {
          return Response.json({ lines: [], cursor: 0, fileSize: 0 },
            { headers: { "Content-Type": "application/json", ...corsHeaders(req) } });
        }
        const filePath = join(SESSIONS_DIR, sessionKey, "raw", "events.jsonl");
        try {
          const file = Bun.file(filePath);
          const fileSize = file.size;
          if (cursor >= fileSize) {
            return Response.json({ lines: [], cursor, fileSize },
              { headers: { "Content-Type": "application/json", ...corsHeaders(req) } });
          }
          const readSize = Math.min(fileSize - cursor, 256 * 1024);
          const text = await file.slice(cursor, cursor + readSize).text();
          const lastNewline = text.lastIndexOf("\n");
          const safeText = lastNewline >= 0 ? text.slice(0, lastNewline + 1) : "";
          const nextCursor = lastNewline >= 0 ? cursor + lastNewline + 1 : cursor;
          if (!safeText) {
            return Response.json({ lines: [], cursor: cursor + readSize, fileSize },
              { headers: { "Content-Type": "application/json", ...corsHeaders(req) } });
          }
          const rawLines = safeText.split("\n").filter(Boolean);
          const sanitized: string[] = [];
          let parseErrors = 0;
          for (const l of rawLines) {
            try {
              const parsed = JSON.parse(l);
              if (parsed?.source !== sourceFilter) continue;
              sanitized.push(JSON.stringify(sanitizeForApi(parsed)));
            } catch {
              // kind 过滤依赖 source 字段，无法解析的行跳过
              parseErrors++;
            }
          }
          const tailed = sanitized.slice(-maxLines);
          // raw_lines_scanned + parse_errors expose the gap between bytes consumed
          // (cursor advance) and lines emitted (post source filter), so clients
          // can distinguish "cursor moved a lot but few lines" from "stuck".
          return Response.json(
            {
              lines: tailed,
              cursor: nextCursor,
              fileSize,
              raw_lines_scanned: rawLines.length,
              parse_errors: parseErrors,
            },
            { headers: { "Content-Type": "application/json", ...corsHeaders(req) } },
          );
        } catch {
          return Response.json({ lines: [], cursor: 0, fileSize: 0 },
            { headers: { "Content-Type": "application/json", ...corsHeaders(req) } });
        }
      }

      // 静态文件服务
      const filePath = join(GUI_DIST, url.pathname === "/" ? "index.html" : url.pathname);
      const response = await serveStaticFile(filePath);
      if (response.status !== 404) return response;

      const indexPath = join(GUI_DIST, "index.html");
      const indexResponse = await serveStaticFile(indexPath);
      if (indexResponse.status !== 404) return indexResponse;

      return new Response(
        `<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>Autopilot Dashboard</title>
<style>
  body { font-family: -apple-system, system-ui, sans-serif; display: flex; justify-content: center; align-items: center; min-height: 100vh; margin: 0; background: #0a0a0a; color: #e0e0e0; }
  .card { text-align: center; padding: 3rem; border: 1px solid #333; border-radius: 12px; max-width: 560px; }
  code { background: #1a1a2e; padding: 2px 8px; border-radius: 4px; color: #7dd3fc; }
</style>
</head>
<body>
  <div class="card">
    <h1>Autopilot Dashboard</h1>
    <p>GUI 静态资源尚未构建。请先执行：</p>
    <p><code>cd plugins/spec-autopilot/gui && bun run build</code></p>
    <p>HTTP: <code>http://localhost:${HTTP_PORT}</code></p>
    <p>WS: <code>ws://localhost:${WS_PORT}</code></p>
  </div>
</body>
</html>`,
        { headers: { "Content-Type": "text/html; charset=utf-8" } }
      );
    },
  });
}
