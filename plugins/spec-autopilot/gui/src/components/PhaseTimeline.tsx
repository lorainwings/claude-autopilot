/**
 * PhaseTimeline — Phase 进度时间轴组件
 * 显示 8 个 Phase 的执行状态和耗时
 */

import { useStore } from "../store";

const PHASE_LABELS = [
  "Environment Setup",
  "Requirements",
  "OpenSpec",
  "Fast-Forward",
  "Test Design",
  "Implementation",
  "Test Report",
  "Archive",
];

export function PhaseTimeline() {
  const { events, currentPhase, mode } = useStore();

  const phaseStates = PHASE_LABELS.map((label, idx) => {
    const phaseEvents = events.filter((e) => e.phase === idx);
    const startEvent = phaseEvents.find((e) => e.type === "phase_start");
    const endEvent = phaseEvents.find((e) => e.type === "phase_end");
    const gateBlock = phaseEvents.find((e) => e.type === "gate_block");

    let status: "pending" | "running" | "ok" | "warning" | "blocked" | "failed" = "pending";
    let duration = 0;

    if (gateBlock) {
      status = "blocked";
    } else if (endEvent) {
      status = (endEvent.payload.status as typeof status) || "ok";
      duration = (endEvent.payload.duration_ms as number) || 0;
    } else if (startEvent) {
      status = "running";
    }

    return { phase: idx, label, status, duration, active: idx === currentPhase };
  });

  return (
    <div className="phase-timeline">
      <div className="timeline-header">
        <h2>Phase Timeline</h2>
        <span className="mode-badge">{mode || "—"}</span>
      </div>
      <div className="timeline-track">
        {phaseStates.map(({ phase, label, status, duration, active }) => (
          <div key={phase} className={`phase-node ${status} ${active ? "active" : ""}`}>
            <div className="phase-number">{phase}</div>
            <div className="phase-label">{label}</div>
            {duration > 0 && <div className="phase-duration">{(duration / 1000).toFixed(1)}s</div>}
            <div className={`phase-status-dot ${status}`} />
          </div>
        ))}
      </div>
    </div>
  );
}
