/**
 * PhaseTimeline — V2 垂直左侧栏时间轴
 * 显示 8 个 Phase 的 hex 节点 + 连接线 + 统计面板
 * 数据源: Zustand Store (events, currentPhase, mode)
 */

import { useState, useEffect, useMemo, memo } from "react";
import { useStore, selectPhaseDurations, selectTotalElapsedMs, selectGateStats } from "../store";

function formatDuration(ms: number): string {
  const totalSec = Math.floor(ms / 1000);
  const min = Math.floor(totalSec / 60);
  const sec = totalSec % 60;
  const hours = Math.floor(min / 60);
  const remainMin = min % 60;
  return `${String(hours).padStart(2, "0")}:${String(remainMin).padStart(2, "0")}:${String(sec).padStart(2, "0")}`;
}

export const PhaseTimeline = memo(function PhaseTimeline() {
  const events = useStore((s) => s.events);
  const currentPhase = useStore((s) => s.currentPhase);
  const mode = useStore((s) => s.mode);

  // G9: Force re-render every second when a phase is running
  // tick is included in useMemo deps so Date.now()-based selectors recompute
  const [tick, setTick] = useState(0);

  const phaseDurations = useMemo(() => selectPhaseDurations(events), [events, tick]);
  const totalElapsedMs = useMemo(() => selectTotalElapsedMs(events), [events, tick]);
  const gateStats = useMemo(() => selectGateStats(events), [events]);

  const hasRunning = phaseDurations.some((p) => p.status === "running");
  useEffect(() => {
    if (!hasRunning) return;
    const timer = setInterval(() => setTick((t) => t + 1), 1000);
    return () => clearInterval(timer);
  }, [hasRunning]);

  const completedPhases = phaseDurations.filter(
    (p) => p.status === "ok" || p.status === "warning"
  ).length;

  return (
    <aside className="w-[220px] bg-abyss border-r border-border flex flex-col z-40 shrink-0">
      <div className="flex-1 overflow-y-auto py-6 px-4 space-y-2 relative">
        {/* Vertical Timeline Connection Line */}
        <div className="absolute left-[35px] top-10 bottom-10 w-px bg-border z-0"></div>

        {/* Phase Nodes */}
        {phaseDurations.map((phase) => {
          const isRunning = phase.status === "running";
          const isPassed = phase.status === "ok" || phase.status === "warning";
          const isBlocked = phase.status === "blocked" || phase.status === "failed";
          const isCurrent = phase.phase === currentPhase;

          // Hex node color
          let hexBg = "bg-border"; // pending
          let textColor = "text-text-muted";
          let labelColor = "text-text-muted";
          let hexContent = <span className="text-xs font-bold">{phase.phase}</span>;

          if (isPassed) {
            hexBg = "bg-emerald";
            textColor = "text-white";
            labelColor = "text-emerald";
            hexContent = <span className="text-xs">&#10003;</span>;
          } else if (isRunning || isCurrent) {
            hexBg = "bg-cyan";
            textColor = "text-void";
            labelColor = "text-white";
          } else if (isBlocked) {
            hexBg = "bg-rose";
            textColor = "text-white";
            labelColor = "text-rose";
            hexContent = <span className="text-xs">&#10007;</span>;
          }

          return (
            <div key={phase.phase} className="relative z-10 flex items-center group cursor-pointer py-1">
              <div
                className={`w-10 h-10 ${hexBg} hex-clip flex items-center justify-center ${textColor} shrink-0 ${
                  (isRunning || isCurrent) && !isPassed
                    ? "animate-pulse-glow-cyan border-2 border-white/50"
                    : ""
                }`}
              >
                {hexContent}
              </div>
              <div className="ml-3">
                <div className={`text-[10px] font-display uppercase leading-tight ${
                  isCurrent && !isPassed ? "text-cyan font-bold" : "text-text-muted"
                }`}>
                  阶段 {phase.phase}
                </div>
                <div className={`text-[11px] font-bold leading-tight ${labelColor}`}>
                  {phase.label}
                </div>
              </div>
            </div>
          );
        })}
      </div>

      {/* Bottom Stats Panel */}
      <div className="p-4 border-t border-border space-y-4">
        <div className="space-y-1">
          <div className="text-[10px] text-text-muted uppercase font-display">总累计耗时</div>
          <div className="font-mono text-2xl text-cyan font-bold">{formatDuration(totalElapsedMs)}</div>
        </div>
        <div className="grid grid-cols-2 gap-2 text-[10px] font-bold">
          <div className="bg-surface p-2 rounded">
            <div className="text-text-muted mb-1">阶段</div>
            <div>{completedPhases} / {phaseDurations.length}</div>
          </div>
          <div className="bg-surface p-2 rounded">
            <div className="text-text-muted mb-1">门禁</div>
            <div className="text-emerald">{gateStats.passed} &#10003; <span className="text-rose ml-1">{gateStats.blocked} &#10007;</span></div>
          </div>
        </div>
        {mode && (
          <div className="px-2 py-0.5 border border-cyan/50 bg-cyan/10 text-cyan text-[10px] font-bold rounded uppercase tracking-tighter text-center">
            {mode === "full" ? "全模式" : mode === "lite" ? "精简" : "最小"}
          </div>
        )}
      </div>
    </aside>
  );
});
