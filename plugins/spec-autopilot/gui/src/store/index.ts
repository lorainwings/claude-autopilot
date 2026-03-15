/**
 * Zustand Store — 全局状态管理
 * 管理事件流、Phase 状态、连接状态
 */

import { create } from "zustand";
import type { AutopilotEvent } from "../lib/ws-bridge";

interface TaskProgress {
  task_name: string;
  status: "running" | "passed" | "failed" | "retrying";
  tdd_step?: "red" | "green" | "refactor";
  retry_count?: number;
  task_index: number;
  task_total: number;
  timestamp: string;
}

interface TaskProgressPayload {
  task_name: string;
  status: "running" | "passed" | "failed" | "retrying";
  tdd_step?: "red" | "green" | "refactor";
  retry_count?: number;
  task_index: number;
  task_total: number;
}

function isTaskProgressPayload(p: unknown): p is TaskProgressPayload {
  const obj = p as Record<string, unknown>;
  return typeof obj.task_name === "string" && typeof obj.status === "string" && typeof obj.task_index === "number";
}

export interface AgentInfo {
  agent_id: string;
  agent_label: string;
  phase: number;
  status: "dispatched" | "ok" | "warning" | "blocked" | "failed";
  dispatch_time: string;
  complete_time?: string;
  summary?: string;
  duration_ms?: number;
  output_files?: string[];
}

interface AppState {
  events: AutopilotEvent[];
  connected: boolean;
  currentPhase: number | null;
  sessionId: string | null;
  changeName: string | null;
  mode: "full" | "lite" | "minimal" | null;
  taskProgress: Map<string, TaskProgress>;
  agentMap: Map<string, AgentInfo>;
  decisionAcked: boolean;

  addEvents: (events: AutopilotEvent[]) => void;
  setConnected: (connected: boolean) => void;
  setDecisionAcked: (acked: boolean) => void;
  lastAckedBlockSequence: number;
  setLastAckedBlockSequence: (seq: number) => void;
  reset: () => void;
}

// ============================================
// Derived selectors for V2 Telemetry Dashboard
// ============================================

export interface PhaseDuration {
  phase: number;
  label: string;
  durationMs: number;
  status: "pending" | "running" | "ok" | "warning" | "blocked" | "failed";
}

export interface GateStats {
  passed: number;
  blocked: number;
  pending: number;
  passRate: number;
}

const ALL_LABELS = [
  "环境初始化", "需求理解", "OpenSpec 创建", "快速生成",
  "测试设计", "代码实施", "测试报告", "归档清理",
];

// lite mode only uses phases 0,1,5,6,7; minimal uses 0,1,5,7
const MODE_PHASES: Record<string, number[]> = {
  full: [0, 1, 2, 3, 4, 5, 6, 7],
  lite: [0, 1, 5, 6, 7],
  minimal: [0, 1, 5, 7],
};

/** Get actual total phases count from events or fallback */
export function selectTotalPhases(events: AutopilotEvent[]): number {
  const latest = [...events].reverse().find((e) => e.total_phases > 0);
  return latest?.total_phases ?? 8;
}

/** Get active phase indices based on mode from events */
export function selectActivePhaseIndices(events: AutopilotEvent[]): number[] {
  const latest = [...events].reverse().find((e) => e.mode);
  const mode = latest?.mode ?? "full";
  return MODE_PHASES[mode] ?? MODE_PHASES.full!;
}

/** Compute per-phase duration from events */
export function selectPhaseDurations(events: AutopilotEvent[]): PhaseDuration[] {
  const activeIndices = selectActivePhaseIndices(events);

  return activeIndices.map((idx) => {
    const label = ALL_LABELS[idx] ?? `Phase ${idx}`;
    const phaseEvents = events.filter((e) => e.phase === idx);
    const startEvent = phaseEvents.find((e) => e.type === "phase_start");
    const endEvent = phaseEvents.find((e) => e.type === "phase_end");
    const gateBlock = phaseEvents.findLast((e) => e.type === "gate_block");
    const gatePass = phaseEvents.findLast((e) => e.type === "gate_pass");

    let status: PhaseDuration["status"] = "pending";
    let durationMs = 0;

    if (endEvent) {
      status = (endEvent.payload.status as PhaseDuration["status"]) || "ok";
      durationMs = (endEvent.payload.duration_ms as number) || 0;
      // Fallback: when duration_ms is missing (e.g. Phase 0), compute from timestamps
      if (durationMs === 0 && startEvent) {
        durationMs = new Date(endEvent.timestamp).getTime() - new Date(startEvent.timestamp).getTime();
      }
    } else if (gateBlock && (!gatePass || gateBlock.sequence > gatePass.sequence)) {
      // Only show blocked if the latest gate_block is not resolved by a gate_pass
      status = "blocked";
      if (startEvent) {
        durationMs = Date.now() - new Date(startEvent.timestamp).getTime();
      }
    } else if (startEvent) {
      status = "running";
      durationMs = Date.now() - new Date(startEvent.timestamp).getTime();
    }

    return { phase: idx, label, durationMs, status };
  });
}

/** Compute total session elapsed time */
export function selectTotalElapsedMs(events: AutopilotEvent[]): number {
  const starts = events.filter((e) => e.type === "phase_start");
  const ends = events.filter((e) => e.type === "phase_end");
  if (starts.length === 0) return 0;

  const firstStart = new Date(starts[0]!.timestamp).getTime();
  if (ends.length > 0) {
    // Sum all completed phase durations
    let total = 0;
    for (const e of ends) {
      let dur = (e.payload.duration_ms as number) || 0;
      // Fallback: compute from timestamps when duration_ms missing
      if (dur === 0) {
        const matchingStart = starts.find((s) => s.phase === e.phase);
        if (matchingStart) {
          dur = new Date(e.timestamp).getTime() - new Date(matchingStart.timestamp).getTime();
        }
      }
      total += dur;
    }
    // If there's a running phase, add elapsed time
    const runningStart = starts.find(
      (s) => !ends.some((e) => e.phase === s.phase)
    );
    if (runningStart) {
      total += Date.now() - new Date(runningStart.timestamp).getTime();
    }
    return total || (Date.now() - firstStart);
  }

  return Date.now() - firstStart;
}

/** Count tool_use events associated with a specific agent (v5.3 WS4.D) */
export function selectAgentToolCount(events: AutopilotEvent[], agentId: string): number {
  return events.filter(
    (e) => e.type === "tool_use" && (e.payload as Record<string, unknown>).agent_id === agentId
  ).length;
}

/** Get tool_use events associated with a specific agent (v5.3 WS4.B) */
export function selectAgentToolEvents(events: AutopilotEvent[], agentId: string): AutopilotEvent[] {
  return events.filter(
    (e) => e.type === "tool_use" && (e.payload as Record<string, unknown>).agent_id === agentId
  );
}

/** Get unique agent IDs from events (v5.3 WS4.C) */
export function selectAgentIds(agentMap: Map<string, AgentInfo>): { id: string; label: string }[] {
  return Array.from(agentMap.values()).map((a) => ({ id: a.agent_id, label: a.agent_label }));
}

/** Compute gate pass/block/pending statistics (single-pass) */
export function selectGateStats(events: AutopilotEvent[]): GateStats {
  let passed = 0;
  let blocked = 0;
  let pending = 0;
  for (const e of events) {
    if (e.type === "gate_pass") passed++;
    else if (e.type === "gate_block") blocked++;
    else if (e.type === "gate_decision_pending") pending++;
  }
  const total = passed + blocked;
  const passRate = total > 0 ? Math.round((passed / total) * 100) : 0;

  return { passed, blocked, pending, passRate };
}

export const useStore = create<AppState>((set) => ({
  events: [],
  connected: false,
  currentPhase: null,
  sessionId: null,
  changeName: null,
  mode: null,
  taskProgress: new Map(),
  agentMap: new Map(),
  decisionAcked: false,
  lastAckedBlockSequence: -1,

  addEvents: (newEvents) =>
    set((state) => {
      // Deduplicate by sequence, then cap at 1000 events
      const seen = new Set(state.events.map((e) => e.sequence));
      const unique = newEvents.filter((e) => !seen.has(e.sequence));
      const CRITICAL_TYPES = new Set(["phase_start", "phase_end", "gate_block", "gate_pass", "agent_dispatch", "agent_complete"]);
      const allSorted = [...state.events, ...unique].sort((a, b) => a.sequence - b.sequence);
      const critical = allSorted.filter((e) => CRITICAL_TYPES.has(e.type));
      const regular = allSorted.filter((e) => !CRITICAL_TYPES.has(e.type));
      const regularBudget = Math.max(0, 1000 - critical.length);
      const cappedRegular = regularBudget === 0 ? [] : regular.slice(-regularBudget);
      // Build keep-set from capped regular, then filter allSorted (already sorted) in one pass
      const keepSeqs = new Set(cappedRegular.map((e) => e.sequence));
      const merged = allSorted.filter((e) => CRITICAL_TYPES.has(e.type) || keepSeqs.has(e.sequence));
      const latest = merged[merged.length - 1];

      const newTaskProgress = new Map(state.taskProgress);
      const newAgentMap = new Map(state.agentMap);

      for (const event of newEvents) {
        if (event.type === "task_progress" && event.phase === 5 && isTaskProgressPayload(event.payload)) {
          const p = event.payload;
          newTaskProgress.set(p.task_name, {
            task_name: p.task_name,
            status: p.status,
            tdd_step: p.tdd_step,
            retry_count: p.retry_count,
            task_index: p.task_index,
            task_total: p.task_total,
            timestamp: event.timestamp,
          });
        } else if (event.type === "agent_dispatch" && typeof event.payload.agent_id === "string") {
          newAgentMap.set(event.payload.agent_id as string, {
            agent_id: event.payload.agent_id as string,
            agent_label: (event.payload.agent_label as string) || event.payload.agent_id as string,
            phase: event.phase,
            status: "dispatched",
            dispatch_time: event.timestamp,
          });
        } else if (event.type === "agent_complete" && typeof event.payload.agent_id === "string") {
          const existing = newAgentMap.get(event.payload.agent_id as string);
          newAgentMap.set(event.payload.agent_id as string, {
            agent_id: event.payload.agent_id as string,
            agent_label: (event.payload.agent_label as string) || existing?.agent_label || event.payload.agent_id as string,
            phase: event.phase,
            status: (event.payload.status as AgentInfo["status"]) || "ok",
            dispatch_time: existing?.dispatch_time || event.timestamp,
            complete_time: event.timestamp,
            summary: event.payload.summary as string | undefined,
            duration_ms: event.payload.duration_ms as number | undefined,
            output_files: (event.payload.output_files as string[] | undefined) || existing?.output_files,
          });
        } else if (event.type === "phase_end" || event.type === "error") {
          // When a phase ends or errors, mark any still-dispatched agents in that phase as failed
          for (const [id, info] of newAgentMap) {
            if (info.phase === event.phase && info.status === "dispatched") {
              newAgentMap.set(id, { ...info, status: "failed", complete_time: event.timestamp });
            }
          }
        }
      }

      // G2 fix: Auto-reset decisionAcked when a new gate_block arrives after the acked one
      let newDecisionAcked = state.decisionAcked;
      if (state.decisionAcked) {
        const hasNewBlock = newEvents.some(
          (e) => e.type === "gate_block" && e.sequence > state.lastAckedBlockSequence
        );
        if (hasNewBlock) {
          newDecisionAcked = false;
        }
      }

      return {
        events: merged,
        currentPhase: latest?.phase ?? state.currentPhase,
        sessionId: latest?.session_id ?? state.sessionId,
        changeName: latest?.change_name ?? state.changeName,
        mode: latest?.mode ?? state.mode,
        taskProgress: newTaskProgress,
        agentMap: newAgentMap,
        decisionAcked: newDecisionAcked,
      };
    }),

  setConnected: (connected) => set({ connected }),

  setDecisionAcked: (acked) => set({ decisionAcked: acked }),

  setLastAckedBlockSequence: (seq) => set({ lastAckedBlockSequence: seq }),

  reset: () =>
    set({
      events: [],
      connected: false,
      currentPhase: null,
      sessionId: null,
      changeName: null,
      mode: null,
      taskProgress: new Map(),
      agentMap: new Map(),
      decisionAcked: false,
      lastAckedBlockSequence: -1,
    }),
}));
