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

interface AppState {
  events: AutopilotEvent[];
  connected: boolean;
  currentPhase: number | null;
  sessionId: string | null;
  changeName: string | null;
  mode: "full" | "lite" | "minimal" | null;
  taskProgress: Map<string, TaskProgress>;
  decisionAcked: boolean;

  addEvents: (events: AutopilotEvent[]) => void;
  setConnected: (connected: boolean) => void;
  setDecisionAcked: (acked: boolean) => void;
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

/** Compute per-phase duration from events */
export function selectPhaseDurations(events: AutopilotEvent[]): PhaseDuration[] {
  const LABELS = [
    "环境初始化", "需求理解", "OpenSpec 创建", "快速生成",
    "测试设计", "代码实施", "测试报告", "归档清理",
  ];

  return LABELS.map((label, idx) => {
    const phaseEvents = events.filter((e) => e.phase === idx);
    const startEvent = phaseEvents.find((e) => e.type === "phase_start");
    const endEvent = phaseEvents.find((e) => e.type === "phase_end");
    const gateBlock = phaseEvents.find((e) => e.type === "gate_block");

    let status: PhaseDuration["status"] = "pending";
    let durationMs = 0;

    if (gateBlock && !endEvent) {
      status = "blocked";
    } else if (endEvent) {
      status = (endEvent.payload.status as PhaseDuration["status"]) || "ok";
      durationMs = (endEvent.payload.duration_ms as number) || 0;
    } else if (startEvent) {
      status = "running";
      // Compute elapsed since start for running phases
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
      total += (e.payload.duration_ms as number) || 0;
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

/** Compute gate pass/block/pending statistics */
export function selectGateStats(events: AutopilotEvent[]): GateStats {
  const passed = events.filter((e) => e.type === "gate_pass").length;
  const blocked = events.filter((e) => e.type === "gate_block").length;
  const pending = events.filter(
    (e) => e.type === "gate_decision_pending"
  ).length;
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
  decisionAcked: false,

  addEvents: (newEvents) =>
    set((state) => {
      // Deduplicate by sequence, then cap at 1000 events
      const seen = new Set(state.events.map((e) => e.sequence));
      const unique = newEvents.filter((e) => !seen.has(e.sequence));
      const merged = [...state.events, ...unique]
        .sort((a, b) => a.sequence - b.sequence)
        .slice(-1000);
      const latest = merged[merged.length - 1];

      const newTaskProgress = new Map(state.taskProgress);

      for (const event of newEvents) {
        if (event.type === "task_progress" && event.phase === 5) {
          const payload = event.payload as any;
          newTaskProgress.set(payload.task_name, {
            task_name: payload.task_name,
            status: payload.status,
            tdd_step: payload.tdd_step,
            retry_count: payload.retry_count,
            task_index: payload.task_index,
            task_total: payload.task_total,
            timestamp: event.timestamp,
          });
        }
      }

      return {
        events: merged,
        currentPhase: latest?.phase ?? state.currentPhase,
        sessionId: latest?.session_id ?? state.sessionId,
        changeName: latest?.change_name ?? state.changeName,
        mode: latest?.mode ?? state.mode,
        taskProgress: newTaskProgress,
      };
    }),

  setConnected: (connected) => set({ connected }),

  setDecisionAcked: (acked) => set({ decisionAcked: acked }),

  reset: () =>
    set({
      events: [],
      connected: false,
      currentPhase: null,
      sessionId: null,
      changeName: null,
      mode: null,
      taskProgress: new Map(),
      decisionAcked: false,
    }),
}));
