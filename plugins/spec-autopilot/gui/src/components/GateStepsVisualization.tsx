/**
 * GateStepsVisualization -- 8 格横向 Gate 步骤进度条
 */

import { memo, useMemo } from "react";
import type { GateStep } from "../store";

const STEP_COLORS: Record<string, { bg: string; border: string }> = {
  pass: { bg: "bg-emerald", border: "border-emerald/50" },
  fail: { bg: "bg-rose", border: "border-rose/50" },
  skip: { bg: "bg-text-muted/40", border: "border-border" },
  warning: { bg: "bg-amber", border: "border-amber/50" },
};

const PENDING_STYLE = { bg: "bg-surface", border: "border-border/50" };

const TOTAL_GATE_STEPS = 8;

export const GateStepsVisualization = memo(function GateStepsVisualization({
  gateSteps,
  phase,
}: {
  gateSteps: GateStep[];
  phase: number;
}) {
  const phaseSteps = useMemo(
    () => gateSteps.filter((s) => s.phase === phase),
    [gateSteps, phase]
  );

  const stepMap = useMemo(() => {
    const map = new Map<number, GateStep>();
    for (const s of phaseSteps) {
      map.set(s.step_index, s);
    }
    return map;
  }, [phaseSteps]);

  if (phaseSteps.length === 0) return null;

  return (
    <div className="flex gap-1 items-center">
      {Array.from({ length: TOTAL_GATE_STEPS }, (_, i) => {
        const step = stepMap.get(i);
        const style = step ? (STEP_COLORS[step.step_result] ?? PENDING_STYLE) : PENDING_STYLE;
        return (
          <div
            key={i}
            className="group relative"
          >
            <div
              className={`w-5 h-2 rounded-sm border ${style.bg} ${style.border} transition-all`}
            />
            {step && (
              <div className="absolute bottom-full left-1/2 -translate-x-1/2 mb-1 hidden group-hover:block z-50 pointer-events-none">
                <div className="px-2 py-1 bg-deep border border-border rounded shadow-lg text-[9px] font-mono whitespace-nowrap">
                  <div className="text-text-bright font-bold">{step.step_name}</div>
                  {step.step_detail && (
                    <div className="text-text-muted mt-0.5 max-w-[200px] whitespace-normal">{step.step_detail}</div>
                  )}
                </div>
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
});
