/**
 * TelemetryDashboard — V2 右侧遥测面板
 * 会话指标(SVG环形图)、阶段耗时条、门禁统计
 * 数据源: Zustand Store (events) → derived selectors
 */

import { useState, useEffect, useMemo, memo } from "react";
import { useStore, selectPhaseDurations, selectTotalElapsedMs, selectGateStats, selectActivePhaseIndices } from "../store";

function formatDuration(ms: number): string {
  const totalSec = Math.floor(ms / 1000);
  const min = Math.floor(totalSec / 60);
  const sec = totalSec % 60;
  const hours = Math.floor(min / 60);
  const remainMin = min % 60;
  return `${String(hours).padStart(2, "0")}:${String(remainMin).padStart(2, "0")}:${String(sec).padStart(2, "0")}`;
}

function formatShortDuration(ms: number): string {
  const totalSec = Math.floor(ms / 1000);
  const min = Math.floor(totalSec / 60);
  const sec = totalSec % 60;
  if (min === 0 && sec === 0) return "--:--";
  return `${min}:${String(sec).padStart(2, "0")}`;
}

export const TelemetryDashboard = memo(function TelemetryDashboard() {
  const events = useStore((s) => s.events);
  const phaseDurations = useMemo(() => selectPhaseDurations(events), [events]);
  const totalElapsedMs = useMemo(() => selectTotalElapsedMs(events), [events]);
  const gateStats = useMemo(() => selectGateStats(events), [events]);

  // G9: Force re-render every second when a phase is running
  const [, setTick] = useState(0);
  const hasRunning = phaseDurations.some((p) => p.status === "running");
  useEffect(() => {
    if (!hasRunning) return;
    const timer = setInterval(() => setTick((t) => t + 1), 1000);
    return () => clearInterval(timer);
  }, [hasRunning]);

  const activePhaseIndices = useMemo(() => selectActivePhaseIndices(events), [events]);
  const totalPhaseCount = activePhaseIndices.length;
  const completedPhases = phaseDurations.filter(
    (p) => p.status === "ok" || p.status === "warning"
  ).length;
  const totalRetries = useMemo(
    () => events.filter(
      (e) => e.type === "task_progress" && (e.payload as Record<string, unknown>).status === "retrying"
    ).length,
    [events]
  );

  // SVG ring chart computation
  const circumference = 2 * Math.PI * 58; // r=58
  const completionRatio = totalPhaseCount > 0 ? completedPhases / totalPhaseCount : 0;
  const strokeDashoffset = circumference * (1 - completionRatio);

  // Max duration for bar chart scaling
  const maxDuration = Math.max(...phaseDurations.map((p) => p.durationMs), 1);

  return (
    <aside className="w-[360px] bg-abyss border-l border-border flex flex-col p-4 space-y-4 overflow-y-auto shrink-0">
      {/* Card 1: Session Metrics */}
      <section className="bg-deep border border-border p-4 rounded-lg">
        <h3 className="font-display text-[10px] font-bold text-text-bright uppercase mb-4 flex items-center">
          <span className="w-2 h-2 rounded-full bg-cyan mr-2"></span> 会话指标
        </h3>
        <div className="flex justify-center mb-4 relative">
          {/* Circular Ring Chart (SVG) */}
          <svg className="w-32 h-32 transform -rotate-90">
            <circle cx="64" cy="64" fill="transparent" r="58" style={{ stroke: "var(--color-surface)" }} strokeWidth="8"></circle>
            <circle
              cx="64" cy="64" fill="transparent" r="58"
              style={{ stroke: "var(--color-cyan)" }} strokeWidth="8"
              strokeDasharray={circumference}
              strokeDashoffset={strokeDashoffset}
              strokeLinecap="round"
              className="transition-all duration-1000 ease-out"
            ></circle>
          </svg>
          <div className="absolute inset-0 flex flex-col items-center justify-center">
            <span className="font-mono text-xl font-bold text-white leading-none">{formatDuration(totalElapsedMs)}</span>
            <span className="text-[9px] text-text-muted uppercase font-bold mt-1">总耗时</span>
          </div>
        </div>
        <div className="grid grid-cols-2 gap-y-3 text-[11px] font-mono">
          <div className="text-text-muted">已完成阶段</div>
          <div className="text-right text-text-bright">{completedPhases} / {totalPhaseCount}</div>
          <div className="text-text-muted">总重试次数</div>
          <div className="text-right text-amber font-bold">{totalRetries}</div>
          <div className="text-text-muted">通过门禁</div>
          <div className="text-right text-emerald font-bold">{gateStats.passed}</div>
          <div className="text-text-muted">阻断门禁</div>
          <div className="text-right text-rose font-bold">{gateStats.blocked}</div>
        </div>
      </section>

      {/* Card 2: Phase Duration */}
      <section className="bg-deep border border-border p-4 rounded-lg">
        <h3 className="font-display text-[10px] font-bold text-text-bright uppercase mb-4 flex items-center">
          <span className="w-2 h-2 rounded-full bg-violet mr-2"></span> 阶段耗时
        </h3>
        <div className="space-y-2">
          {phaseDurations.map((p) => {
            const barWidth = p.durationMs > 0 ? Math.max((p.durationMs / maxDuration) * 100, 2) : 0;
            const isRunning = p.status === "running";
            const barColor = isRunning ? "bg-cyan shadow-[0_0_8px_rgba(0,217,255,0.4)]" : "bg-cyan";

            return (
              <div key={p.phase} className="flex items-center text-[10px] font-mono">
                <span className="w-6 text-text-muted">P{p.phase}</span>
                <div className="flex-1 h-2 bg-border mx-2 overflow-hidden rounded-full">
                  <div
                    className={`h-full ${barColor} transition-all duration-500`}
                    style={{ width: `${barWidth}%` }}
                  ></div>
                </div>
                <span className={isRunning ? "text-cyan font-bold" : "text-text-muted"}>
                  {formatShortDuration(p.durationMs)}
                </span>
              </div>
            );
          })}
        </div>
      </section>

      {/* Card 3: Gate Statistics */}
      <section className="bg-deep border border-border p-4 rounded-lg flex space-x-4">
        <div className="w-20 h-20 rounded-full border-4 border-emerald border-l-rose flex items-center justify-center shrink-0">
          <span className="text-[10px] font-bold text-text-bright">{gateStats.passRate}% 通过</span>
        </div>
        <div className="flex-1">
          <h3 className="font-display text-[10px] font-bold text-text-bright uppercase mb-2">门禁统计</h3>
          <div className="space-y-1 text-[11px] font-mono">
            <div className="flex justify-between items-center">
              <span className="text-emerald">通过</span>
              <span>{gateStats.passed}</span>
            </div>
            <div className="flex justify-between items-center">
              <span className="text-rose">阻断</span>
              <span>{gateStats.blocked}</span>
            </div>
            <div className="flex justify-between items-center">
              <span className="text-text-muted">待定</span>
              <span>{gateStats.pending}</span>
            </div>
          </div>
        </div>
      </section>
    </aside>
  );
});
