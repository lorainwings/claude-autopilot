#!/usr/bin/env bun
/// <reference types="bun" />
/// <reference types="node" />
/**
 * autopilot-server.ts
 * 聚合式 GUI 服务器:
 *   1. HTTP: 托管 gui-dist 静态资产
 *   2. WS: 推送归一化后的当前会话事件流
 *   3. 聚合: legacy events + raw hooks + raw statusline + transcript
 */

import { watch } from "node:fs";
import { access, mkdir, readFile, stat, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { spawn } from "node:child_process";
import { dirname, extname, join, resolve } from "node:path";

import type { ServerWebSocket } from "bun";

const WS_PORT = 8765;
const HTTP_PORT = 9527;
const POLL_INTERVAL_MS = 700;

const args = process.argv.slice(2);
let projectRoot = process.cwd();
let autoOpen = true;
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--project-root" && args[i + 1]) {
    projectRoot = resolve(args[++i]);
  } else if (args[i] === "--no-open") {
    autoOpen = false;
  }
}

const PLUGIN_ROOT = resolve(import.meta.dir, "..");
const GUI_DIST = join(PLUGIN_ROOT, "gui-dist");
const PLUGIN_JSON = join(PLUGIN_ROOT, ".claude-plugin", "plugin.json");
const LOGS_DIR = join(projectRoot, "logs");
const EVENTS_FILE = join(LOGS_DIR, "events.jsonl");
const SESSIONS_DIR = join(LOGS_DIR, "sessions");
const CHANGES_DIR = join(projectRoot, "openspec", "changes");
const LOCK_FILE = join(CHANGES_DIR, ".autopilot-active");

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

type AutopilotMode = "full" | "lite" | "minimal";

interface AutopilotEvent {
  type: string;
  phase: number;
  mode: AutopilotMode;
  timestamp: string;
  change_name: string;
  session_id: string;
  phase_label: string;
  total_phases: number;
  sequence: number;
  payload: Record<string, unknown>;
  event_id: string;
  ingest_seq: number;
  source: "legacy" | "hook" | "statusline" | "transcript";
  raw_ref?: string;
}

interface RawHookRecord {
  source: "hook";
  hook_name: string;
  captured_at: string;
  project_root?: string;
  session_id: string;
  session_key?: string;
  cwd?: string;
  transcript_path?: string;
  agent_transcript_path?: string;
  active_agent_id?: string | null;
  data: Record<string, unknown>;
}

interface RawStatusRecord {
  source: "statusline";
  captured_at: string;
  project_root?: string;
  session_id: string;
  session_key?: string;
  cwd?: string;
  transcript_path?: string;
  data: Record<string, unknown>;
}

interface SessionSnapshot {
  sessionId: string | null;
  sessionKey: string | null;
  changeName: string;
  mode: AutopilotMode;
  events: AutopilotEvent[];
  journalPath: string | null;
  telemetryAvailable: boolean;
  transcriptAvailable: boolean;
}

interface PhaseContext {
  phase: number;
  phaseLabel: string;
  mode: AutopilotMode;
  totalPhases: number;
  changeName: string;
}

interface CachedFile<T> {
  stamp: string;
  items: T[];
}

const wsClients = new Set<ServerWebSocket<unknown>>();
const fileCache = new Map<string, CachedFile<unknown>>();
let snapshotState: SessionSnapshot = {
  sessionId: null,
  sessionKey: null,
  changeName: "unknown",
  mode: "full",
  events: [],
  journalPath: null,
  telemetryAvailable: false,
  transcriptAvailable: false,
};
let refreshInFlight = false;
let dirtyWhileInFlight = false;
let pluginVersionCache = "unknown";
const lastJournalHashes = new Map<string, string>();

// ─── CORS ───────────────────────────────────────────────────

const ALLOWED_ORIGIN_RE = /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/;

function corsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin") ?? "";
  return {
    "Access-Control-Allow-Origin": ALLOWED_ORIGIN_RE.test(origin) ? origin : "",
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "Vary": "Origin",
  };
}

// ─── API 层脱敏 ─────────────────────────────────────────────

/** 绝对路径中的用户主目录替换为 ~ */
function sanitizePath(s: string): string {
  return s.replace(/\/(Users|home|root)\/[^/\s"')]+/g, "~");
}

/** 真正的机密字段 — 直接 redact */
const SECRET_FIELDS = new Set(["apiKey", "ANTHROPIC_API_KEY", "api_key", "token", "secret"]);

function sanitizeForApi(obj: unknown, depth = 0): unknown {
  if (depth > 12 || obj === null || typeof obj !== "object") {
    if (typeof obj === "string") return sanitizePath(obj);
    return obj;
  }
  if (Array.isArray(obj)) return obj.map(v => sanitizeForApi(v, depth + 1));
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(obj as Record<string, unknown>)) {
    if (SECRET_FIELDS.has(k)) {
      out[k] = "[REDACTED]";
    } else {
      out[k] = sanitizeForApi(v, depth + 1);
    }
  }
  return out;
}

// ─────────────────────────────────────────────────────────────

function sanitizeSessionKey(sessionId: string): string {
  const cleaned = sessionId.replace(/[^A-Za-z0-9._-]+/g, "_").replace(/^_+|_+$/g, "");
  return cleaned || "unknown";
}

function safeJsonParse<T>(line: string): T | null {
  try {
    return JSON.parse(line) as T;
  } catch {
    return null;
  }
}

function hashText(text: string): string {
  return createHash("sha1").update(text).digest("hex");
}

function toIso(value: unknown, fallback = "1970-01-01T00:00:00.000Z"): string {
  if (typeof value === "string" && value.trim()) {
    const parsed = Date.parse(value);
    if (!Number.isNaN(parsed)) return new Date(parsed).toISOString();
  }
  return fallback;
}

function toMillis(value: string): number {
  const ms = Date.parse(value);
  return Number.isNaN(ms) ? 0 : ms;
}

function normalizeMode(value: unknown, fallback: AutopilotMode = "full"): AutopilotMode {
  return value === "lite" || value === "minimal" || value === "full" ? value : fallback;
}

function getPhaseLabel(phase: number): string {
  switch (phase) {
    case 0: return "Environment Setup";
    case 1: return "Requirements";
    case 2: return "OpenSpec";
    case 3: return "Fast-Forward";
    case 4: return "Test Design";
    case 5: return "Implementation";
    case 6: return "Test Report";
    case 7: return "Archive";
    default: return "Unknown";
  }
}

function totalPhases(mode: AutopilotMode): number {
  if (mode === "lite") return 5;
  if (mode === "minimal") return 4;
  return 8;
}

function truncateText(value: unknown, limit = 1200): string | undefined {
  if (typeof value !== "string") return undefined;
  return value.length > limit ? `${value.slice(0, limit)}…` : value;
}

function extractKeyParam(toolName: string, data: Record<string, unknown>): string | undefined {
  const toolInput = (data.tool_input as Record<string, unknown> | undefined) || {};
  switch (toolName) {
    case "Bash":
      return truncateText(toolInput.command, 400);
    case "Read":
    case "Write":
    case "Edit":
      return truncateText(toolInput.file_path, 400);
    case "Glob":
    case "Grep":
      return truncateText(toolInput.pattern, 400);
    case "Task":
    case "Agent":
      return truncateText((toolInput.description ?? data.description), 400);
    default:
      return truncateText(JSON.stringify(toolInput), 400);
  }
}

function extractOutputPreview(data: Record<string, unknown>): string | undefined {
  const candidates = [
    data.stdout,
    data.output,
    data.tool_response,
    (data.tool_result as Record<string, unknown> | undefined)?.stdout,
    (data.tool_result as Record<string, unknown> | undefined)?.output,
  ];
  for (const candidate of candidates) {
    const text = truncateText(typeof candidate === "string" ? candidate : JSON.stringify(candidate ?? ""), 2000);
    if (text) return text;
  }
  return undefined;
}

function getNestedString(obj: Record<string, unknown>, ...paths: string[]): string | undefined {
  for (const path of paths) {
    const parts = path.split(".");
    let current: unknown = obj;
    let ok = true;
    for (const part of parts) {
      if (!current || typeof current !== "object" || !(part in current)) {
        ok = false;
        break;
      }
      current = (current as Record<string, unknown>)[part];
    }
    if (ok && typeof current === "string" && current) return current;
  }
  return undefined;
}

function extractTranscriptText(value: unknown, depth = 0): string {
  if (depth > 4 || value == null) return "";
  if (typeof value === "string") return value;
  if (Array.isArray(value)) {
    return value.map((item) => extractTranscriptText(item, depth + 1)).filter(Boolean).join("\n").trim();
  }
  if (typeof value === "object") {
    const obj = value as Record<string, unknown>;
    const directKeys = ["text", "content", "message", "output", "prompt", "completion", "result", "summary"];
    for (const key of directKeys) {
      if (key in obj) {
        const text = extractTranscriptText(obj[key], depth + 1);
        if (text) return text;
      }
    }
    const values = Object.values(obj).map((item) => extractTranscriptText(item, depth + 1)).filter(Boolean);
    return values.join("\n").trim();
  }
  return "";
}

function detectTranscriptRole(record: Record<string, unknown>): string {
  const candidates = [
    record.role,
    record.speaker,
    record.author,
    record.type,
    (record.message as Record<string, unknown> | undefined)?.role,
  ];
  for (const candidate of candidates) {
    if (typeof candidate === "string" && candidate) {
      if (/user/i.test(candidate)) return "user";
      if (/assistant|claude/i.test(candidate)) return "assistant";
      if (/system/i.test(candidate)) return "system";
      if (/tool/i.test(candidate)) return "tool";
      return candidate.toLowerCase();
    }
  }
  return "event";
}

async function ensurePluginVersion() {
  if (pluginVersionCache !== "unknown") return pluginVersionCache;
  try {
    const content = await readFile(PLUGIN_JSON, "utf-8");
    const parsed = JSON.parse(content) as { version?: string };
    pluginVersionCache = parsed.version || "unknown";
  } catch {
    pluginVersionCache = "unknown";
  }
  return pluginVersionCache;
}

async function fileStamp(filePath: string): Promise<string> {
  try {
    const info = await stat(filePath);
    return `${info.size}-${info.mtimeMs}`;
  } catch {
    return "";
  }
}

async function readJsonLinesCached<T>(filePath: string): Promise<T[]> {
  const stamp = await fileStamp(filePath);
  if (!stamp) return [];
  const cached = fileCache.get(filePath) as CachedFile<T> | undefined;
  if (cached && cached.stamp === stamp) return cached.items;
  try {
    const content = await readFile(filePath, "utf-8");
    const items = content
      .split("\n")
      .filter(Boolean)
      .map((line: string) => safeJsonParse<T>(line))
      .filter((line: T | null): line is T => line !== null);
    fileCache.set(filePath, { stamp, items });
    return items;
  } catch {
    return [];
  }
}

async function readLockContext(): Promise<{ sessionId: string | null; changeName: string; mode: AutopilotMode }> {
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

async function inferLatestLegacyContext(): Promise<{ sessionId: string | null; changeName: string; mode: AutopilotMode }> {
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

async function getCurrentSessionContext() {
  const lockContext = await readLockContext();
  if (lockContext.sessionId) return lockContext;
  return inferLatestLegacyContext();
}

function normalizeLegacyEvents(items: Record<string, unknown>[], sessionId: string, fallback: { changeName: string; mode: AutopilotMode }): AutopilotEvent[] {
  return items
    .filter((item) => item.session_id === sessionId)
    .filter((item) => item.type !== "tool_use")
    .map((item) => {
      const phase = typeof item.phase === "number" ? item.phase : 0;
      const mode = normalizeMode(item.mode, fallback.mode);
      const timestamp = toIso(item.timestamp);
      const payload = typeof item.payload === "object" && item.payload ? item.payload as Record<string, unknown> : {};
      const sequence = typeof item.sequence === "number" ? item.sequence : 0;
      const raw = JSON.stringify(item);
      return {
        type: typeof item.type === "string" ? item.type : "legacy_event",
        phase,
        mode,
        timestamp,
        change_name: typeof item.change_name === "string" && item.change_name ? item.change_name : fallback.changeName,
        session_id: sessionId,
        phase_label: typeof item.phase_label === "string" && item.phase_label ? item.phase_label : getPhaseLabel(phase),
        total_phases: typeof item.total_phases === "number" ? item.total_phases : totalPhases(mode),
        sequence,
        payload,
        event_id: `legacy-${hashText(raw)}`,
        ingest_seq: 0,
        source: "legacy",
        raw_ref: "logs/events.jsonl",
      } satisfies AutopilotEvent;
    });
}

function buildPhaseLookup(events: AutopilotEvent[]) {
  const phaseEvents = events
    .filter((event) => Number.isFinite(toMillis(event.timestamp)))
    .sort((a, b) => {
      const ta = toMillis(a.timestamp);
      const tb = toMillis(b.timestamp);
      if (ta !== tb) return ta - tb;
      return a.sequence - b.sequence;
    });

  return (timestamp: string): PhaseContext => {
    const target = toMillis(timestamp);
    let ctx: PhaseContext = {
      phase: 0,
      phaseLabel: getPhaseLabel(0),
      mode: "full",
      totalPhases: 8,
      changeName: "unknown",
    };
    for (const event of phaseEvents) {
      if (toMillis(event.timestamp) > target) break;
      ctx = {
        phase: event.phase,
        phaseLabel: event.phase_label,
        mode: event.mode,
        totalPhases: event.total_phases,
        changeName: event.change_name,
      };
    }
    return ctx;
  };
}

async function readSessionRawRecords<T>(sessionKey: string, filename: string): Promise<T[]> {
  const filePath = join(SESSIONS_DIR, sessionKey, "raw", filename);
  return readJsonLinesCached<T>(filePath);
}

function normalizeHookRecords(records: RawHookRecord[], sessionId: string, phaseLookup: (ts: string) => PhaseContext, fallback: { changeName: string; mode: AutopilotMode }): AutopilotEvent[] {
  const result: AutopilotEvent[] = [];
  for (const record of records) {
    if (record.session_id !== sessionId) continue;
    const data = record.data || {};
    const hookName = record.hook_name || "Hook";
    const timestamp = toIso(record.captured_at);
    const ctx = phaseLookup(timestamp);
    const phase = ctx.phase;
    const mode = ctx.mode || fallback.mode;
    const payloadBase = {
      hook_name: hookName,
      cwd: record.cwd ?? data.cwd,
      transcript_path: record.transcript_path ?? data.transcript_path,
      active_agent_id: record.active_agent_id ?? undefined,
    };

    if (hookName === "PostToolUse" && typeof data.tool_name === "string") {
      const toolName = data.tool_name;
      const toolPayload: Record<string, unknown> = {
        ...payloadBase,
        tool_name: toolName,
        key_param: extractKeyParam(toolName, data),
        exit_code: typeof data.exit_code === "number" ? data.exit_code : (data.tool_result as Record<string, unknown> | undefined)?.exit_code,
        output_preview: extractOutputPreview(data),
        tool_input: (data.tool_input as Record<string, unknown> | undefined) || {},
        tool_result: (data.tool_result as Record<string, unknown> | undefined) || {},
      };
      if (record.active_agent_id) toolPayload.agent_id = record.active_agent_id;
      const rawRef = join("logs", "sessions", sanitizeSessionKey(sessionId), "raw", "hooks.jsonl");
      result.push({
        type: "tool_use",
        phase,
        mode,
        timestamp,
        change_name: ctx.changeName || fallback.changeName,
        session_id: sessionId,
        phase_label: ctx.phaseLabel,
        total_phases: ctx.totalPhases || totalPhases(mode),
        sequence: 0,
        payload: toolPayload,
        event_id: `hook-tool-${hashText(`${record.captured_at}|${toolName}|${JSON.stringify(data.tool_input ?? {})}|${JSON.stringify(data.tool_result ?? {})}`)}`,
        ingest_seq: 0,
        source: "hook",
        raw_ref: rawRef,
      });
      continue;
    }

    const promptPreview = truncateText((data.prompt ?? data.text ?? data.description) as string | undefined, 400);
    const summaryPayload: Record<string, unknown> = { ...payloadBase };
    if (promptPreview) summaryPayload.preview = promptPreview;
    if (record.agent_transcript_path) summaryPayload.agent_transcript_path = record.agent_transcript_path;

    const typeMap: Record<string, string> = {
      SessionStart: "session_start",
      SessionEnd: "session_end",
      Stop: "session_stop",
      PreCompact: "compact_start",
      PostCompact: "compact_end",
      UserPromptSubmit: "user_prompt",
      SubagentStart: "subagent_start",
      SubagentStop: "subagent_stop",
      PreToolUse: "tool_prepare",
    };

    result.push({
      type: typeMap[hookName] || "hook_event",
      phase,
      mode,
      timestamp,
      change_name: ctx.changeName || fallback.changeName,
      session_id: sessionId,
      phase_label: ctx.phaseLabel,
      total_phases: ctx.totalPhases || totalPhases(mode),
      sequence: 0,
      payload: summaryPayload,
      event_id: `hook-${hashText(`${hookName}|${record.captured_at}|${JSON.stringify(data)}`)}`,
      ingest_seq: 0,
      source: "hook",
      raw_ref: join("logs", "sessions", sanitizeSessionKey(sessionId), "raw", "hooks.jsonl"),
    });
  }
  return result;
}

function normalizeStatusRecords(records: RawStatusRecord[], sessionId: string, phaseLookup: (ts: string) => PhaseContext, fallback: { changeName: string; mode: AutopilotMode }): AutopilotEvent[] {
  return records
    .filter((record) => record.session_id === sessionId)
    .map((record) => {
      const data = record.data || {};
      const timestamp = toIso(record.captured_at);
      const ctx = phaseLookup(timestamp);
      const mode = ctx.mode || fallback.mode;
      const payload: Record<string, unknown> = {
        model: data.model,
        cwd: data.cwd ?? record.cwd,
        transcript_path: data.transcript_path ?? record.transcript_path,
        cost: data.cost ?? data.cost_usd ?? data.total_cost_usd,
        context_window: data.context_window,
        worktree: data.worktree,
        version: data.version,
      };
      return {
        type: "status_snapshot",
        phase: ctx.phase,
        mode,
        timestamp,
        change_name: ctx.changeName || fallback.changeName,
        session_id: sessionId,
        phase_label: ctx.phaseLabel,
        total_phases: ctx.totalPhases || totalPhases(mode),
        sequence: 0,
        payload,
        event_id: `status-${hashText(`${record.captured_at}|${JSON.stringify(data)}`)}`,
        ingest_seq: 0,
        source: "statusline",
        raw_ref: join("logs", "sessions", sanitizeSessionKey(sessionId), "raw", "statusline.jsonl"),
      };
    });
}

async function parseTranscriptEvents(paths: Array<{ path: string; kind: "main" | "agent"; agentId?: string; discoveredAt: string }>, sessionId: string, phaseLookup: (ts: string) => PhaseContext, fallback: { changeName: string; mode: AutopilotMode }): Promise<AutopilotEvent[]> {
  const events: AutopilotEvent[] = [];
  const seen = new Set<string>();

  for (const descriptor of paths) {
    if (!descriptor.path || seen.has(`${descriptor.kind}:${descriptor.path}`)) continue;
    seen.add(`${descriptor.kind}:${descriptor.path}`);
    try {
      await access(descriptor.path);
    } catch {
      continue;
    }
    const lines = await readJsonLinesCached<Record<string, unknown>>(descriptor.path).catch(() => []);
    lines.forEach((line, index) => {
      const role = detectTranscriptRole(line);
      const text = extractTranscriptText(line);
      if (!text) return;
      const fallbackTs = new Date(Date.parse(descriptor.discoveredAt || "1970-01-01T00:00:00.000Z") + index).toISOString();
      const timestamp = toIso(
        getNestedString(line, "timestamp", "created_at", "time", "message.timestamp"),
        fallbackTs
      );
      const ctx = phaseLookup(timestamp);
      const mode = ctx.mode || fallback.mode;
      const payload: Record<string, unknown> = {
        role,
        text,
        text_preview: truncateText(text, 400),
        transcript_kind: descriptor.kind,
        transcript_path: descriptor.path,
      };
      if (descriptor.agentId) payload.agent_id = descriptor.agentId;
      events.push({
        type: "transcript_message",
        phase: ctx.phase,
        mode,
        timestamp,
        change_name: ctx.changeName || fallback.changeName,
        session_id: sessionId,
        phase_label: ctx.phaseLabel,
        total_phases: ctx.totalPhases || totalPhases(mode),
        sequence: 0,
        payload,
        event_id: `transcript-${hashText(`${descriptor.path}|${index}|${JSON.stringify(line)}`)}`,
        ingest_seq: 0,
        source: "transcript",
        raw_ref: descriptor.path,
      });
    });
  }

  return events;
}

function collectTranscriptDescriptors(hooks: RawHookRecord[], statuses: RawStatusRecord[]) {
  const descriptors: Array<{ path: string; kind: "main" | "agent"; agentId?: string; discoveredAt: string }> = [];
  for (const record of hooks) {
    if (record.transcript_path) {
      descriptors.push({ path: record.transcript_path, kind: "main", discoveredAt: record.captured_at });
    }
    if (record.agent_transcript_path) {
      descriptors.push({
        path: record.agent_transcript_path,
        kind: "agent",
        agentId: record.active_agent_id ?? getNestedString(record.data, "agent_id", "payload.agent_id"),
        discoveredAt: record.captured_at,
      });
    }
  }
  for (const record of statuses) {
    if (record.transcript_path) {
      descriptors.push({ path: record.transcript_path, kind: "main", discoveredAt: record.captured_at });
    }
  }
  return descriptors;
}

function sortAndFinalize(events: AutopilotEvent[]): AutopilotEvent[] {
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

async function writeJournal(sessionKey: string, events: AutopilotEvent[]) {
  const journalDir = join(SESSIONS_DIR, sessionKey, "journal");
  const journalPath = join(journalDir, "events.jsonl");
  const content = events.map((event) => JSON.stringify(event)).join("\n");
  const contentBody = content ? `${content}\n` : "";
  // Skip write when content is identical (hash covers both count and value changes)
  const contentHash = hashText(contentBody);
  if (contentHash === (lastJournalHashes.get(sessionKey) ?? "")) return journalPath;
  await mkdir(journalDir, { recursive: true });
  await writeFile(journalPath, contentBody, "utf-8");
  lastJournalHashes.set(sessionKey, contentHash);
  return journalPath;
}

async function buildSnapshot(): Promise<SessionSnapshot> {
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

function broadcastReset() {
  const payload = JSON.stringify({ type: "reset" });
  for (const ws of wsClients) {
    try {
      ws.send(payload);
    } catch {
      wsClients.delete(ws);
    }
  }
}

function broadcastSnapshot(events: AutopilotEvent[]) {
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

function broadcastEvents(events: AutopilotEvent[]) {
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

async function refreshSnapshot(forceSnapshot = false) {
  if (refreshInFlight) {
    dirtyWhileInFlight = true;
    return;
  }
  refreshInFlight = true;
  try {
    const next = await buildSnapshot();
    const prev = snapshotState;

    const sessionChanged = next.sessionId !== prev.sessionId;
    const prevIds = new Set(prev.events.map((event) => event.event_id));
    const added = next.events.filter((event) => !prevIds.has(event.event_id));

    snapshotState = next;

    if (sessionChanged) {
      broadcastReset();
      broadcastSnapshot(next.events);
      return;
    }

    if (forceSnapshot) {
      broadcastSnapshot(next.events);
      return;
    }

    if (added.length > 0) {
      broadcastEvents(added);
    }
  } finally {
    refreshInFlight = false;
    if (dirtyWhileInFlight) {
      dirtyWhileInFlight = false;
      refreshSnapshot().catch(() => undefined);
    }
  }
}

async function resolveDecisionFile(): Promise<string | null> {
  try {
    const content = await readFile(LOCK_FILE, "utf-8");
    const parsed = safeJsonParse<Record<string, unknown>>(content);
    const changeName = parsed && typeof parsed.change === "string" ? parsed.change : content.trim();
    if (!changeName) return null;
    return join(CHANGES_DIR, changeName, "context", "decision.json");
  } catch {
    return null;
  }
}

async function handleDecision(decision: { action: string; phase: number; reason?: string }) {
  try {
    const decisionFile = await resolveDecisionFile();
    if (!decisionFile) return;
    await mkdir(dirname(decisionFile), { recursive: true });
    await writeFile(decisionFile, JSON.stringify(decision, null, 2), "utf-8");

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
    console.error("  ❌ Failed to write decision:", error);
  }
}

function startRefreshLoop() {
  setInterval(() => {
    refreshSnapshot().catch(() => undefined);
  }, POLL_INTERVAL_MS);

  try {
    watch(LOGS_DIR, { recursive: true }, () => {
      refreshSnapshot().catch(() => undefined);
    });
  } catch {
    // polling loop already covers this
  }

  try {
    watch(CHANGES_DIR, { recursive: false }, () => {
      refreshSnapshot(true).catch(() => undefined);
    });
  } catch {
    // polling loop already covers this
  }
}

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

const wsServer = Bun.serve({
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
      }), { headers: { "Content-Type": "application/json" } });
    }
    return new Response("WebSocket server. Connect via ws://", { status: 200 });
  },
  websocket: {
    open(ws: ServerWebSocket<unknown>) {
      wsClients.add(ws);
      const sanitized = snapshotState.events.map(e => sanitizeForApi(e));
      ws.send(JSON.stringify({ type: "snapshot", data: sanitized }));
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

const httpServer = Bun.serve({
  hostname: "127.0.0.1",
  port: HTTP_PORT,
  async fetch(req: Request) {
    const url = new URL(req.url);

    if (req.method === "OPTIONS") {
      return new Response(null, {
        headers: corsHeaders(req),
      });
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
        headers: {
          "Content-Type": "application/json",
          ...corsHeaders(req),
        },
      });
    }

    if (url.pathname === "/api/info") {
      const version = await ensurePluginVersion();
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
      }), {
        headers: {
          "Content-Type": "application/json",
          ...corsHeaders(req),
        },
      });
    }

    if (url.pathname === "/api/raw") {
      const kind = url.searchParams.get("kind");
      const sessionKey = snapshotState.sessionKey;
      if (!sessionKey || !kind) {
        return new Response(JSON.stringify({ lines: [] }), {
          headers: {
            "Content-Type": "application/json",
            ...corsHeaders(req),
          },
        });
      }
      const fileName = kind === "hooks" ? "hooks.jsonl" : kind === "statusline" ? "statusline.jsonl" : null;
      if (!fileName) {
        return new Response(JSON.stringify({ lines: [] }), {
          headers: {
            "Content-Type": "application/json",
            ...corsHeaders(req),
          },
        });
      }
      const filePath = join(SESSIONS_DIR, sessionKey, "raw", fileName);
      try {
        const rawLines = (await readFile(filePath, "utf-8")).split("\n").filter(Boolean);
        const lines = rawLines.map(l => {
          try { return JSON.stringify(sanitizeForApi(JSON.parse(l))); }
          catch { return sanitizePath(l); }
        });
        return new Response(JSON.stringify({ lines, filePath: sanitizePath(filePath) }), {
          headers: {
            "Content-Type": "application/json",
            ...corsHeaders(req),
          },
        });
      } catch {
        return new Response(JSON.stringify({ lines: [], filePath: sanitizePath(filePath) }), {
          headers: {
            "Content-Type": "application/json",
            ...corsHeaders(req),
          },
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
      const fileName = kind === "hooks" ? "hooks.jsonl" : kind === "statusline" ? "statusline.jsonl" : null;
      if (!fileName) {
        return Response.json({ lines: [], cursor: 0, fileSize: 0 },
          { headers: { "Content-Type": "application/json", ...corsHeaders(req) } });
      }
      const filePath = join(SESSIONS_DIR, sessionKey, "raw", fileName);
      try {
        const file = Bun.file(filePath);
        const fileSize = file.size;
        if (cursor >= fileSize) {
          return Response.json({ lines: [], cursor, fileSize },
            { headers: { "Content-Type": "application/json", ...corsHeaders(req) } });
        }
        const readSize = Math.min(fileSize - cursor, 256 * 1024);
        const text = await file.slice(cursor, cursor + readSize).text();
        // Handle chunk boundary: only consume up to the last complete line
        const lastNewline = text.lastIndexOf("\n");
        const safeText = lastNewline >= 0 ? text.slice(0, lastNewline + 1) : "";
        const nextCursor = lastNewline >= 0 ? cursor + lastNewline + 1 : cursor;
        if (!safeText) {
          // No complete line in this chunk (single line > 256KB); skip ahead
          return Response.json({ lines: [], cursor: cursor + readSize, fileSize },
            { headers: { "Content-Type": "application/json", ...corsHeaders(req) } });
        }
        const rawLines = safeText.split("\n").filter(Boolean).slice(-maxLines);
        const sanitized = rawLines.map(l => {
          try { return JSON.stringify(sanitizeForApi(JSON.parse(l))); }
          catch { return sanitizePath(l); }
        });
        return Response.json({ lines: sanitized, cursor: nextCursor, fileSize },
          { headers: { "Content-Type": "application/json", ...corsHeaders(req) } });
      } catch {
        return Response.json({ lines: [], cursor: 0, fileSize: 0 },
          { headers: { "Content-Type": "application/json", ...corsHeaders(req) } });
      }
    }

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

await mkdir(SESSIONS_DIR, { recursive: true }).catch(() => undefined);
await ensurePluginVersion();
snapshotState = await buildSnapshot();
startRefreshLoop();

if (autoOpen) {
  const url = `http://localhost:${HTTP_PORT}`;
  const platform = process.platform;
  const cmd = platform === "darwin" ? "open" : platform === "win32" ? "start" : "xdg-open";
  try {
    spawn(cmd, [url], { detached: true, stdio: "ignore" }).unref();
  } catch {
    // ignore
  }
}

console.log(`
  ✨ Autopilot 聚合服务器已启动
  ├─ HTTP  → http://localhost:${HTTP_PORT}
  ├─ WS    → ws://localhost:${WS_PORT}
  ├─ 项目  → ${projectRoot}
  ├─ 旧事件 → ${EVENTS_FILE}
  └─ 会话  → ${snapshotState.sessionId ?? "none"}
`);

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
