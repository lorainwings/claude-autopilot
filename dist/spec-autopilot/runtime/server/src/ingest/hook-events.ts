/**
 * hook-events.ts — Hook 记录归一化
 */

import { join } from "node:path";
import type { AutopilotEvent, AutopilotMode, PhaseContext, RawHookRecord } from "../types";
import { extractKeyParam, extractOutputPreview, hashText, sanitizeSessionKey, toIso, totalPhases, truncateText } from "../utils";

export function normalizeHookRecords(
  records: RawHookRecord[],
  sessionId: string,
  phaseLookup: (ts: string) => PhaseContext,
  fallback: { changeName: string; mode: AutopilotMode },
): AutopilotEvent[] {
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
      const rawRef = join("logs", "sessions", sanitizeSessionKey(sessionId), "raw", "events.jsonl");
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
      raw_ref: join("logs", "sessions", sanitizeSessionKey(sessionId), "raw", "events.jsonl"),
    });
  }
  return result;
}
