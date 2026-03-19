/**
 * phase-lookup.ts — Phase 上下文时间线解析
 */

import type { AutopilotEvent, PhaseContext } from "../types";
import { getPhaseLabel, toMillis } from "../utils";

export function buildPhaseLookup(events: AutopilotEvent[]) {
  const phaseEvents = events
    .filter((event) => Number.isFinite(toMillis(event.timestamp)))
    .sort((a, b) => {
      const ta = toMillis(a.timestamp);
      const tb = toMillis(b.timestamp);
      if (ta !== tb) return ta - tb;
      return a.sequence - b.sequence;
    });

  return (timestamp: string): PhaseContext => {
    const target = toMillis(timestamp);
    let ctx: PhaseContext = {
      phase: 0,
      phaseLabel: getPhaseLabel(0),
      mode: "full",
      totalPhases: 8,
      changeName: "unknown",
    };
    for (const event of phaseEvents) {
      if (toMillis(event.timestamp) > target) break;
      ctx = {
        phase: event.phase,
        phaseLabel: event.phase_label,
        mode: event.mode,
        totalPhases: event.total_phases,
        changeName: event.change_name,
      };
    }
    return ctx;
  };
}
