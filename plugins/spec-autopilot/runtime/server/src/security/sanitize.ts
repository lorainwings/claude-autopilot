/**
 * sanitize.ts — API 层脱敏与 CORS
 */

/** 绝对路径中的用户主目录替换为 ~ */
export function sanitizePath(s: string): string {
  return s.replace(/\/(Users|home|root)\/[^/\s"')]+/g, "~");
}

/** 真正的机密字段 — 直接 redact */
const SECRET_FIELDS = new Set(["apiKey", "ANTHROPIC_API_KEY", "api_key", "token", "secret"]);

export function sanitizeForApi(obj: unknown, depth = 0): unknown {
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

export const ALLOWED_ORIGIN_RE = /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/;

export function corsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin") ?? "";
  return {
    "Access-Control-Allow-Origin": ALLOWED_ORIGIN_RE.test(origin) ? origin : "",
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "Vary": "Origin",
  };
}
