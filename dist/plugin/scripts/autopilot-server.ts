#!/usr/bin/env bun
/**
 * autopilot-server.ts
 * v5.0 双模服务器 — WebSocket (8765) + HTTP 静态服务 (9527)
 *
 * 职责:
 *   1. WebSocket: 监听 events.jsonl 变化，实时推送事件到 GUI 前端
 *   2. HTTP: 托管 gui-dist/ 静态资产，SPA fallback
 *   3. 启动后自动打开浏览器
 *
 * 启动: bun run scripts/autopilot-server.ts [--project-root <path>] [--no-open]
 * 停止: 发送 SIGTERM 或 SIGINT
 */

import { watch } from "fs";
import { readFile, writeFile, mkdir } from "fs/promises";
import { join, extname, resolve, dirname } from "path";
import { spawn } from "child_process";

// --- Configuration ---
const WS_PORT = 8765;
const HTTP_PORT = 9527;

// Parse CLI args
const args = process.argv.slice(2);
let projectRoot = process.cwd();
let autoOpen = true;

for (let i = 0; i < args.length; i++) {
  if (args[i] === "--project-root" && args[i + 1]) {
    projectRoot = resolve(args[++i]);
  }
  if (args[i] === "--no-open") {
    autoOpen = false;
  }
}

const PLUGIN_ROOT = resolve(import.meta.dir, "..");
const GUI_DIST = join(PLUGIN_ROOT, "gui-dist");
const EVENTS_FILE = join(projectRoot, "logs", "events.jsonl");
const CHANGES_DIR = join(projectRoot, "openspec", "changes");
const LOCK_FILE = join(CHANGES_DIR, ".autopilot-active");

// --- MIME type map ---
const MIME_TYPES: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".mjs": "application/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
  ".ttf": "font/ttf",
  ".map": "application/json",
};

// --- WebSocket clients ---
const wsClients = new Set<any>();

// --- Event file watcher state ---
let lastLineCount = 0;
let watcherActive = false;

async function getEventLines(): Promise<string[]> {
  try {
    const content = await readFile(EVENTS_FILE, "utf-8");
    return content.split("\n").filter(Boolean);
  } catch {
    return [];
  }
}

async function broadcastNewEvents() {
  if (wsClients.size === 0) return;

  const lines = await getEventLines();
  if (lines.length <= lastLineCount) return;

  const newLines = lines.slice(lastLineCount);
  lastLineCount = lines.length;

  for (const line of newLines) {
    const message = JSON.stringify({ type: "event", data: JSON.parse(line) });
    for (const ws of wsClients) {
      try {
        ws.send(message);
      } catch {
        wsClients.delete(ws);
      }
    }
  }
}

function startEventWatcher() {
  if (watcherActive) return;

  // Initial line count
  getEventLines().then((lines) => {
    lastLineCount = lines.length;
  });

  // Watch for file changes
  try {
    const logsDir = join(projectRoot, "logs");
    watch(logsDir, { recursive: false }, (eventType, filename) => {
      if (filename === "events.jsonl") {
        broadcastNewEvents();
      }
    });
    watcherActive = true;
  } catch {
    // Fallback: poll every 500ms if watch fails
    setInterval(broadcastNewEvents, 500);
    watcherActive = true;
  }
}

// --- Resolve decision file path via .autopilot-active lock file ---
// Must align with poll-gate-decision.sh: {change_dir}/context/decision.json
async function resolveDecisionFile(): Promise<string | null> {
  try {
    const lockContent = await readFile(LOCK_FILE, "utf-8");
    let changeName: string;
    try {
      const lockData = JSON.parse(lockContent);
      changeName = lockData.change || "";
    } catch {
      changeName = lockContent.trim();
    }
    if (!changeName) return null;
    return join(CHANGES_DIR, changeName, "context", "decision.json");
  } catch {
    return null;
  }
}

// --- Decision handler ---
async function handleDecision(decision: { action: string; phase: number; reason?: string }) {
  try {
    const decisionFile = await resolveDecisionFile();
    if (!decisionFile) {
      console.error(`  ❌ Cannot resolve decision path: no active autopilot session found`);
      return;
    }
    await mkdir(dirname(decisionFile), { recursive: true });
    await writeFile(decisionFile, JSON.stringify(decision, null, 2));
    console.log(`  ✅ Decision written to ${decisionFile}: ${decision.action} for Phase ${decision.phase}`);

    // v5.2: Broadcast decision_ack to all clients for immediate UI feedback
    const ackMessage = JSON.stringify({
      type: "decision_ack",
      data: {
        action: decision.action,
        phase: decision.phase,
        timestamp: new Date().toISOString(),
      },
    });
    for (const ws of wsClients) {
      try {
        ws.send(ackMessage);
      } catch {
        wsClients.delete(ws);
      }
    }
  } catch (error) {
    console.error(`  ❌ Failed to write decision:`, error);
  }
}

// --- WebSocket Server (port 8765) ---
const wsServer = Bun.serve({
  port: WS_PORT,
  fetch(req, server) {
    // Upgrade HTTP → WebSocket
    if (server.upgrade(req)) {
      return;
    }
    // Health check endpoint
    const url = new URL(req.url);
    if (url.pathname === "/health") {
      return new Response(
        JSON.stringify({
          status: "ok",
          service: "autopilot-ws",
          clients: wsClients.size,
          eventsFile: EVENTS_FILE,
        }),
        { headers: { "Content-Type": "application/json" } }
      );
    }
    return new Response("WebSocket server. Connect via ws://", { status: 200 });
  },
  websocket: {
    open(ws) {
      wsClients.add(ws);
      // Send all existing events as initial snapshot
      getEventLines().then((lines) => {
        ws.send(
          JSON.stringify({
            type: "snapshot",
            data: lines.map((l) => JSON.parse(l)),
          })
        );
      });
    },
    message(ws, message) {
      try {
        const msg = JSON.parse(String(message));
        if (msg.type === "ping") {
          ws.send(JSON.stringify({ type: "pong", timestamp: Date.now() }));
        } else if (msg.type === "decision") {
          handleDecision(msg.data).catch(console.error);
        }
      } catch {
        // Ignore malformed messages
      }
    },
    close(ws) {
      wsClients.delete(ws);
    },
  },
});

// --- HTTP Static Server (port 9527) ---
async function serveStaticFile(filePath: string): Promise<Response> {
  try {
    const file = Bun.file(filePath);
    if (await file.exists()) {
      const ext = extname(filePath);
      const contentType = MIME_TYPES[ext] || "application/octet-stream";
      return new Response(file, {
        headers: {
          "Content-Type": contentType,
          "Cache-Control": "no-cache",
          "Access-Control-Allow-Origin": "*",
        },
      });
    }
  } catch {
    // Fall through
  }
  return new Response(null, { status: 404 });
}

const httpServer = Bun.serve({
  port: HTTP_PORT,
  async fetch(req) {
    const url = new URL(req.url);

    // CORS preflight
    if (req.method === "OPTIONS") {
      return new Response(null, {
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "GET, OPTIONS",
          "Access-Control-Allow-Headers": "*",
        },
      });
    }

    // API: list events (REST fallback for non-WS consumers)
    if (url.pathname === "/api/events") {
      const lines = await getEventLines();
      const offset = parseInt(url.searchParams.get("offset") || "0");
      return new Response(
        JSON.stringify({
          events: lines.slice(offset).map((l) => JSON.parse(l)),
          total: lines.length,
        }),
        {
          headers: {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
          },
        }
      );
    }

    // API: server info
    if (url.pathname === "/api/info") {
      return new Response(
        JSON.stringify({
          version: "5.0.0",
          projectRoot,
          wsPort: WS_PORT,
          httpPort: HTTP_PORT,
          guiDist: GUI_DIST,
        }),
        {
          headers: {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
          },
        }
      );
    }

    // Static file serving from gui-dist/
    let filePath = join(GUI_DIST, url.pathname === "/" ? "index.html" : url.pathname);

    const response = await serveStaticFile(filePath);
    if (response.status !== 404) return response;

    // SPA fallback: serve index.html for non-file routes
    const indexPath = join(GUI_DIST, "index.html");
    const indexResponse = await serveStaticFile(indexPath);
    if (indexResponse.status !== 404) return indexResponse;

    // gui-dist not yet built — show friendly message
    return new Response(
      `<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>Autopilot Dashboard</title>
<style>
  body { font-family: -apple-system, system-ui, sans-serif; display: flex; justify-content: center; align-items: center; min-height: 100vh; margin: 0; background: #0a0a0a; color: #e0e0e0; }
  .card { text-align: center; padding: 3rem; border: 1px solid #333; border-radius: 12px; max-width: 480px; }
  h1 { font-size: 1.5rem; margin-bottom: 1rem; }
  p { color: #888; line-height: 1.6; }
  code { background: #1a1a2e; padding: 2px 8px; border-radius: 4px; color: #7dd3fc; }
  .status { margin-top: 1.5rem; padding: 1rem; background: #1a1a2e; border-radius: 8px; }
  .dot { display: inline-block; width: 8px; height: 8px; border-radius: 50%; background: #22c55e; margin-right: 8px; animation: pulse 2s infinite; }
  @keyframes pulse { 0%,100% { opacity:1 } 50% { opacity:0.4 } }
</style>
</head>
<body>
  <div class="card">
    <h1>Autopilot Dashboard</h1>
    <p>GUI 静态资产尚未构建。请先执行前端编译：</p>
    <p><code>cd vibe-workflow-app && bun run build</code></p>
    <div class="status">
      <span class="dot"></span>
      WebSocket 服务已就绪 — <code>ws://localhost:${WS_PORT}</code><br/>
      <span class="dot"></span>
      REST API 可用 — <code>/api/events</code>
    </div>
  </div>
</body>
</html>`,
      { headers: { "Content-Type": "text/html; charset=utf-8" } }
    );
  },
});

// --- Start event watcher ---
startEventWatcher();

// --- Auto-open browser ---
if (autoOpen) {
  const url = `http://localhost:${HTTP_PORT}`;
  const platform = process.platform;
  const cmd = platform === "darwin" ? "open" : platform === "win32" ? "start" : "xdg-open";
  try {
    spawn(cmd, [url], { detached: true, stdio: "ignore" }).unref();
  } catch {
    // Silently fail — user can open manually
  }
}

// --- Startup banner ---
console.log(`
  ✨ Autopilot 双模服务器已启动
  ├─ HTTP  → http://localhost:${HTTP_PORT}  (GUI 大盘)
  ├─ WS    → ws://localhost:${WS_PORT}    (事件推送)
  ├─ 项目  → ${projectRoot}
  └─ 事件  → ${EVENTS_FILE}
`);

// --- Graceful shutdown ---
process.on("SIGINT", () => {
  console.log("\n  🛑 服务器已停止");
  wsServer.stop();
  httpServer.stop();
  process.exit(0);
});

process.on("SIGTERM", () => {
  wsServer.stop();
  httpServer.stop();
  process.exit(0);
});
