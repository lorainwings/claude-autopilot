/**
 * broadcaster.ts — WebSocket 广播
 */

import type { AutopilotEvent } from "../types";
import { snapshotState, wsClients } from "../state";
import { sanitizeForApi } from "../security/sanitize";

/** 构建 snapshot 消息中的 meta 字段（从 snapshotState 提取编排关键数据） */
function buildSnapshotMeta(): Record<string, unknown> {
  const ss = snapshotState.stateSnapshot;
  return {
    archiveReadiness: snapshotState.archiveReadiness ?? null,
    requirementPacketHash: ss?.requirement_packet_hash ?? null,
    // v7.1: Phase 1 清晰度系统
    clarityScore: ss?.clarity_score ?? null,
    discussionRounds: ss?.discussion_rounds ?? null,
    challengeAgentsActivated: ss?.challenge_agents_activated ?? [],
    gateFrontier: ss?.gate_frontier ?? null,
    // v7.0: 恢复状态 (工作包 G)
    recoverySource: ss?.recovery_source ?? null,
    recoveryReason: ss?.recovery_reason ?? null,
    recoveryConfidence: ss?.recovery_confidence ?? null,
    // v7.0: 报告状态 (工作包 D)
    reportState: ss?.report_state ?? null,
    // v7.0: TDD 审计 (工作包 I)
    tddAudit: ss?.tdd_audit ?? null,
    // v7.0: 执行进度
    executedPhases: ss?.executed_phases ?? [],
    skippedPhases: ss?.skipped_phases ?? [],
    mode: ss?.mode ?? snapshotState.mode ?? null,
    currentPhase: ss?.current_phase ?? null,
  };
}

export function broadcastReset() {
  const payload = JSON.stringify({ type: "reset" });
  for (const ws of wsClients) {
    try {
      ws.send(payload);
    } catch {
      wsClients.delete(ws);
    }
  }
}

export function broadcastSnapshot(events: AutopilotEvent[]) {
  const sanitized = events.map(e => sanitizeForApi(e));
  const payload = JSON.stringify({ type: "snapshot", data: sanitized, meta: buildSnapshotMeta() });
  for (const ws of wsClients) {
    try {
      ws.send(payload);
    } catch {
      wsClients.delete(ws);
    }
  }
}

export function broadcastEvents(events: AutopilotEvent[]) {
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
