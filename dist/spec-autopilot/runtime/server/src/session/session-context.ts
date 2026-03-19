/**
 * session-context.ts — 会话上下文解析
 */

import { readFile } from "node:fs/promises";
import { EVENTS_FILE, LOCK_FILE, PLUGIN_JSON } from "../config";
import { pluginVersionCache, setPluginVersionCache } from "../state";
import type { AutopilotMode } from "../types";
import { normalizeMode, safeJsonParse } from "../utils";
import { readJsonLinesCached } from "./file-cache";

export async function ensurePluginVersion(): Promise<string> {
  if (pluginVersionCache !== "unknown") return pluginVersionCache;
  try {
    const content = await readFile(PLUGIN_JSON, "utf-8");
    const parsed = JSON.parse(content) as { version?: string };
    setPluginVersionCache(parsed.version || "unknown");
  } catch {
    setPluginVersionCache("unknown");
  }
  return pluginVersionCache;
}

export async function readLockContext(): Promise<{ sessionId: string | null; changeName: string; mode: AutopilotMode }> {
  try {
    const content = await readFile(LOCK_FILE, "utf-8");
    const parsed = safeJsonParse<Record<string, unknown>>(content);
    if (parsed) {
      return {
        sessionId: typeof parsed.session_id === "string" ? parsed.session_id : null,
        changeName: typeof parsed.change === "string" && parsed.change ? parsed.change : "unknown",
        mode: normalizeMode(parsed.mode),
      };
    }
    return {
      sessionId: null,
      changeName: content.trim() || "unknown",
      mode: "full",
    };
  } catch {
    return { sessionId: null, changeName: "unknown", mode: "full" };
  }
}

export async function inferLatestLegacyContext(): Promise<{ sessionId: string | null; changeName: string; mode: AutopilotMode }> {
  const legacy = await readJsonLinesCached<Record<string, unknown>>(EVENTS_FILE);
  for (let i = legacy.length - 1; i >= 0; i--) {
    const item = legacy[i]!;
    if (typeof item.session_id === "string" && item.session_id) {
      return {
        sessionId: item.session_id,
        changeName: typeof item.change_name === "string" && item.change_name ? item.change_name : "unknown",
        mode: normalizeMode(item.mode),
      };
    }
  }
  return { sessionId: null, changeName: "unknown", mode: "full" };
}

export async function getCurrentSessionContext() {
  const lockContext = await readLockContext();
  if (lockContext.sessionId) return lockContext;
  return inferLatestLegacyContext();
}
