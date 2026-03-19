/**
 * utils.ts — 纯工具函数（无副作用）
 */

import { createHash } from "node:crypto";
import type { AutopilotMode } from "./types";

export function safeJsonParse<T>(line: string): T | null {
  try {
    return JSON.parse(line) as T;
  } catch {
    return null;
  }
}

export function hashText(text: string): string {
  return createHash("sha1").update(text).digest("hex");
}

export function toIso(value: unknown, fallback = "1970-01-01T00:00:00.000Z"): string {
  if (typeof value === "string" && value.trim()) {
    const parsed = Date.parse(value);
    if (!Number.isNaN(parsed)) return new Date(parsed).toISOString();
  }
  return fallback;
}

export function toMillis(value: string): number {
  const ms = Date.parse(value);
  return Number.isNaN(ms) ? 0 : ms;
}

export function normalizeMode(value: unknown, fallback: AutopilotMode = "full"): AutopilotMode {
  return value === "lite" || value === "minimal" || value === "full" ? value : fallback;
}

export function getPhaseLabel(phase: number): string {
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

export function totalPhases(mode: AutopilotMode): number {
  if (mode === "lite") return 5;
  if (mode === "minimal") return 4;
  return 8;
}

export function truncateText(value: unknown, limit = 1200): string | undefined {
  if (typeof value !== "string") return undefined;
  return value.length > limit ? `${value.slice(0, limit)}…` : value;
}

export function extractKeyParam(toolName: string, data: Record<string, unknown>): string | undefined {
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

export function extractOutputPreview(data: Record<string, unknown>): string | undefined {
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

export function getNestedString(obj: Record<string, unknown>, ...paths: string[]): string | undefined {
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

export function extractTranscriptText(value: unknown, depth = 0): string {
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

export function detectTranscriptRole(record: Record<string, unknown>): string {
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

export function sanitizeSessionKey(sessionId: string): string {
  const cleaned = sessionId.replace(/[^A-Za-z0-9._-]+/g, "_").replace(/^_+|_+$/g, "");
  return cleaned || "unknown";
}
