/**
 * PhaseResultsTable -- 按 phase 汇总结果表格
 */

import { memo, useMemo } from "react";
import { useStore, selectPhaseDurations } from "../store";

function formatDuration(ms: number): string {
  const sec = Math.floor(ms / 1000);
  const min = Math.floor(sec / 60);
  const s = sec % 60;
  if (min === 0 && s === 0) return "--";
  return `${min}:${String(s).padStart(2, "0")}`;
}

const STATUS_COLORS: Record<string, string> = {
  ok: "text-emerald",
  warning: "text-amber",
  blocked: "text-rose",
  failed: "text-rose",
  running: "text-cyan",
  pending: "text-text-muted",
};

const STATUS_LABELS: Record<string, string> = {
  ok: "通过",
  warning: "警告",
  blocked: "阻断",
  failed: "失败",
  running: "运行中",
  pending: "待定",
};

export const PhaseResultsTable = memo(function PhaseResultsTable() {
  const events = useStore((s) => s.events);
  const gateSteps = useStore((s) => s.orchestration.gateSteps);

  const phaseDurations = useMemo(() => selectPhaseDurations(events), [events]);

  // Gate score per phase: pass_count / total_count for that phase
  const gateScores = useMemo(() => {
    const map = new Map<number, { pass: number; total: number }>();
    for (const step of gateSteps) {
      const entry = map.get(step.phase) ?? { pass: 0, total: 0 };
      entry.total++;
      if (step.step_result === "pass") entry.pass++;
      map.set(step.phase, entry);
    }
    return map;
  }, [gateSteps]);

  if (phaseDurations.length === 0) {
    return (
      <div className="px-4 py-3 bg-deep border border-border rounded">
        <div className="text-[10px] font-mono text-text-muted">暂无阶段数据</div>
      </div>
    );
  }

  return (
    <div className="px-4 py-3 bg-deep border border-border rounded">
      <div className="flex items-center gap-2 mb-2">
        <span className="w-1.5 h-1.5 rounded-full bg-violet"></span>
        <span className="font-display text-[10px] font-bold text-text-bright uppercase tracking-wider">
          阶段结果汇总
        </span>
      </div>
      <table className="w-full text-[10px] font-mono">
        <thead>
          <tr className="text-text-muted border-b border-border">
            <th className="text-left py-1 pr-2">Phase</th>
            <th className="text-left py-1 pr-2">Status</th>
            <th className="text-right py-1 pr-2">Duration</th>
            <th className="text-right py-1">Gate</th>
          </tr>
        </thead>
        <tbody>
          {phaseDurations.map((p) => {
            const gs = gateScores.get(p.phase);
            const gateLabel = gs ? `${gs.pass}/${gs.total}` : "--";
            const statusColor = STATUS_COLORS[p.status] ?? "text-text-muted";
            return (
              <tr key={p.phase} className="border-b border-border/30">
                <td className="py-1 pr-2 text-text-bright">
                  P{p.phase} <span className="text-text-muted">{p.label}</span>
                </td>
                <td className={`py-1 pr-2 ${statusColor}`}>
                  {STATUS_LABELS[p.status] ?? p.status}
                </td>
                <td className={`py-1 pr-2 text-right ${p.status === "running" ? "text-cyan" : "text-text-muted"}`}>
                  {formatDuration(p.durationMs)}
                </td>
                <td className="py-1 text-right text-text-muted">{gateLabel}</td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
});
