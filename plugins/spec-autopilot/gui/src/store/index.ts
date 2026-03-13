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

  addEvents: (events: AutopilotEvent[]) => void;
  setConnected: (connected: boolean) => void;
  reset: () => void;
}

export const useStore = create<AppState>((set) => ({
  events: [],
  connected: false,
  currentPhase: null,
  sessionId: null,
  changeName: null,
  mode: null,
  taskProgress: new Map(),

  addEvents: (newEvents) =>
    set((state) => {
      const merged = [...state.events, ...newEvents].sort((a, b) => a.sequence - b.sequence);
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

  reset: () =>
    set({
      events: [],
      connected: false,
      currentPhase: null,
      sessionId: null,
      changeName: null,
      mode: null,
      taskProgress: new Map(),
    }),
}));
