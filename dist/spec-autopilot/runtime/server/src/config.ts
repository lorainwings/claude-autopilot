/**
 * config.ts — 配置管理：端口、路径、CLI 参数、MIME 类型
 */

import { join, resolve } from "node:path";
import { accessSync } from "node:fs";

export const WS_PORT = 8765;
export const HTTP_PORT = 9527;
export const POLL_INTERVAL_MS = 700;

// CLI 参数解析
const args = process.argv.slice(2);
let _projectRoot = process.cwd();
let _autoOpen = true;
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--project-root" && args[i + 1]) {
    _projectRoot = resolve(args[++i]);
  } else if (args[i] === "--no-open") {
    _autoOpen = false;
  }
}

export const projectRoot = _projectRoot;
export const autoOpen = _autoOpen;

// 路径常量：runtime/server/src/ → ../../.. → plugins/spec-autopilot/
export const PLUGIN_ROOT = resolve(import.meta.dir, "../../..");

// GUI 产物路径：dist 态 → assets/gui，源码态 → gui-dist
function resolveGuiDist(): string {
  const distPath = join(PLUGIN_ROOT, "assets", "gui");
  try { accessSync(distPath); return distPath; } catch { /* fall through */ }
  return join(PLUGIN_ROOT, "gui-dist");
}
export const GUI_DIST = resolveGuiDist();
export const PLUGIN_JSON = join(PLUGIN_ROOT, ".claude-plugin", "plugin.json");
export const LOGS_DIR = join(projectRoot, "logs");
export const EVENTS_FILE = join(LOGS_DIR, "events.jsonl");
export const SESSIONS_DIR = join(LOGS_DIR, "sessions");
export const CHANGES_DIR = join(projectRoot, "openspec", "changes");
export const LOCK_FILE = join(CHANGES_DIR, ".autopilot-active");

export const MIME_TYPES: Record<string, string> = {
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
