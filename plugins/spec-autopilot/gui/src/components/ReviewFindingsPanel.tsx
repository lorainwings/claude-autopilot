/**
 * ReviewFindingsPanel -- Phase 6.5 代码审查发现展示
 */

import { memo } from "react";
import { useStore } from "../store";
import type { ReviewFinding } from "../store";

const SEVERITY_COLORS: Record<string, string> = {
  critical: "text-rose font-bold",
  high: "text-rose",
  medium: "text-amber",
  low: "text-text-muted",
};

const SEVERITY_BG: Record<string, string> = {
  critical: "bg-rose/20 border-rose/40",
  high: "bg-rose/10 border-rose/30",
  medium: "bg-amber/10 border-amber/30",
  low: "bg-surface border-border",
};

function FindingItem({ finding }: { finding: ReviewFinding }) {
  const borderClass = finding.blocking ? "border-rose/60" : "border-amber/30";
  const icon = finding.blocking ? "\uD83D\uDEAB" : "\u26A0";
  const sevColor = SEVERITY_COLORS[finding.severity] ?? "text-text-muted";
  const bgClass = SEVERITY_BG[finding.severity] ?? "bg-surface border-border";

  return (
    <div className={`px-2 py-1.5 rounded border ${borderClass} ${bgClass} space-y-0.5`}>
      <div className="flex items-center gap-2 text-[10px] font-mono">
        <span>{icon}</span>
        <span className={`px-1 py-0 text-[8px] border rounded ${sevColor}`} style={{ borderColor: "currentColor" }}>
          {finding.severity.toUpperCase()}
        </span>
        <span className="text-text-bright truncate">
          {finding.file}{finding.line != null ? `:${finding.line}` : ""}
        </span>
      </div>
      <div className="text-[10px] font-mono text-text-muted leading-snug pl-5">
        {finding.message}
      </div>
    </div>
  );
}

export const ReviewFindingsPanel = memo(function ReviewFindingsPanel() {
  const reviewFindings = useStore((s) => s.orchestration.reviewFindings);

  if (reviewFindings.length === 0) {
    return (
      <div className="px-3 py-2 border-b border-border">
        <div className="flex items-center gap-2 mb-1">
          <span className="w-1.5 h-1.5 rounded-full bg-amber"></span>
          <span className="font-display text-[10px] font-bold text-text-bright uppercase tracking-wider">
            代码审查
          </span>
        </div>
        <div className="text-[10px] font-mono text-text-muted">
          等待 Phase 6.5 代码审查...
        </div>
      </div>
    );
  }

  const blocking = reviewFindings.filter((f) => f.blocking);
  const nonBlocking = reviewFindings.filter((f) => !f.blocking);

  return (
    <div className="px-3 py-2 border-b border-border space-y-2">
      <div className="flex items-center gap-2">
        <span className={`w-1.5 h-1.5 rounded-full ${blocking.length > 0 ? "bg-rose" : "bg-emerald"}`}></span>
        <span className="font-display text-[10px] font-bold text-text-bright uppercase tracking-wider">
          代码审查
        </span>
        <span className="text-[9px] font-mono text-text-muted">
          ({reviewFindings.length} findings)
        </span>
      </div>
      <div className="space-y-1 max-h-[200px] overflow-y-auto">
        {blocking.map((f, i) => <FindingItem key={`b-${i}`} finding={f} />)}
        {nonBlocking.map((f, i) => <FindingItem key={`n-${i}`} finding={f} />)}
      </div>
    </div>
  );
});
