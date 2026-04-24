/**
 * session-context.ts — 会话上下文解析
 */

import { readFile, readdir, stat } from "node:fs/promises";
import { join } from "node:path";
import { EVENTS_FILE, LOCK_FILE, PLUGIN_JSON, SESSIONS_DIR } from "../config";
import { pluginVersionCache, setPluginVersionCache } from "../state";
import type { AutopilotMode, RawStatusRecord } from "../types";
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

/**
 * 从 logs/sessions/<session_key>/raw/events.jsonl 中选择"最近活跃" session。
 * 依据：events 文件 mtime 最新者 → 读最后一条 statusline source 记录拿 session_id。
 * 用于 lockfile 缺失 / legacy events 未写的首次安装场景，解除 GUI 遥测对 autopilot 锁文件的强耦合。
 */
export async function inferLatestSessionFromDisk(): Promise<{
  sessionId: string | null;
  changeName: string;
  mode: AutopilotMode;
  /** Non-null iff sessionId was derived from disk scan — indicates trust level. */
  inference_source?: "statusline" | "hook_fallback";
}> {
  let entries: string[] = [];
  try {
    entries = await readdir(SESSIONS_DIR);
  } catch {
    return { sessionId: null, changeName: "unknown", mode: "full" };
  }

  let best: { path: string; mtimeMs: number } | null = null;
  for (const entry of entries) {
    const statusPath = join(SESSIONS_DIR, entry, "raw", "events.jsonl");
    try {
      const st = await stat(statusPath);
      if (!st.isFile() || st.size === 0) continue;
      if (!best || st.mtimeMs > best.mtimeMs) {
        best = { path: statusPath, mtimeMs: st.mtimeMs };
      }
    } catch {
      // 跳过不存在/不可读
    }
  }
  if (!best) return { sessionId: null, changeName: "unknown", mode: "full" };

  const records = await readJsonLinesCached<RawStatusRecord>(best.path);
  for (let i = records.length - 1; i >= 0; i--) {
    const rec = records[i];
    // events.jsonl 混合了 source=hook 与 source=statusline 记录，优先取 statusline
    if (rec && rec.source === "statusline" && typeof rec.session_id === "string" && rec.session_id) {
      return {
        sessionId: rec.session_id,
        changeName: "unknown",
        mode: "full",
        inference_source: "statusline",
      };
    }
  }
  // 回退：任何有 session_id 的记录都能代表这是 active session。
  // Hook records lag statusline and may include read-only events, so the
  // inferred session is less authoritative — callers can gate on
  // inference_source === "hook_fallback" to degrade UI confidence.
  for (let i = records.length - 1; i >= 0; i--) {
    const rec = records[i];
    if (rec && typeof rec.session_id === "string" && rec.session_id) {
      return {
        sessionId: rec.session_id,
        changeName: "unknown",
        mode: "full",
        inference_source: "hook_fallback",
      };
    }
  }
  return { sessionId: null, changeName: "unknown", mode: "full" };
}

export async function getCurrentSessionContext() {
  const lockContext = await readLockContext();
  if (lockContext.sessionId) return lockContext;
  const legacyContext = await inferLatestLegacyContext();
  if (legacyContext.sessionId) return legacyContext;
  // Fallback: 没有 lockfile 也没有 legacy events 时，扫描磁盘 events.jsonl
  // 消除 autopilot 未跑过 Phase 0 即 GUI 永远拿不到遥测的问题
  return inferLatestSessionFromDisk();
}

