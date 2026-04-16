/**
 * DispatchAuditPanel -- 调度审计面板
 */

import { memo, useMemo, useState } from "react";
import { useStore } from "../store";
import type { AgentInfo } from "../store";

const STATUS_COLORS: Record<string, string> = {
  dispatched: "text-violet",
  ok: "text-emerald",
  warning: "text-amber",
  blocked: "text-rose",
  failed: "text-rose",
};

function AgentRow({ agent, dispatchPayload }: { agent: AgentInfo; dispatchPayload: Record<string, unknown> | null }) {
  const [expanded, setExpanded] = useState(false);
  const statusColor = STATUS_COLORS[agent.status] ?? "text-text-muted";

  return (
    <div className="border-b border-border/30">
      <div
        className="flex items-center gap-2 py-1.5 px-2 text-[10px] font-mono cursor-pointer hover:bg-surface/30"
        onClick={() => setExpanded(!expanded)}
      >
        <span className="text-text-muted w-3">{expanded ? "\u25BC" : "\u25B6"}</span>
        <span className="text-text-bright truncate flex-1">{agent.agent_label}</span>
        <span className="text-text-muted">P{agent.phase}</span>
        <span className={statusColor}>{agent.status}</span>
      </div>
      {expanded && (
        <div className="pl-7 pr-2 pb-2 space-y-1 text-[9px] font-mono">
          {!!dispatchPayload?.selection_reason && (
            <div className="flex gap-2">
              <span className="text-text-muted shrink-0">Reason:</span>
              <span className="text-text-bright">{String(dispatchPayload.selection_reason)}</span>
            </div>
          )}
          {!!dispatchPayload?.resolved_priority && (
            <div className="flex gap-2">
              <span className="text-text-muted shrink-0">Priority:</span>
              <span className="text-amber">{String(dispatchPayload.resolved_priority)}</span>
            </div>
          )}
          {!!(dispatchPayload?.owned_artifacts && Array.isArray(dispatchPayload.owned_artifacts)) && (
            <div className="space-y-0.5">
              <span className="text-text-muted">Owned Artifacts:</span>
              {(dispatchPayload.owned_artifacts as string[]).map((f: string, i: number) => (
                <div key={i} className="text-cyan pl-2 truncate">{f}</div>
              ))}
            </div>
          )}
          {agent.output_files && agent.output_files.length > 0 && (
            <div className="space-y-0.5">
              <span className="text-text-muted">Output Files:</span>
              {agent.output_files.map((f, i) => (
                <div key={i} className="text-emerald pl-2 truncate">{f}</div>
              ))}
            </div>
          )}
          {agent.duration_ms != null && (
            <div className="flex gap-2">
              <span className="text-text-muted">Duration:</span>
              <span className="text-text-bright">{Math.round(agent.duration_ms / 1000)}s</span>
            </div>
          )}
          {agent.summary && (
            <div className="flex gap-2">
              <span className="text-text-muted shrink-0">Summary:</span>
              <span className="text-text-bright leading-snug">{agent.summary}</span>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

export const DispatchAuditPanel = memo(function DispatchAuditPanel() {
  const agentMap = useStore((s) => s.agentMap);
  const events = useStore((s) => s.events);

  const agents = useMemo(() => Array.from(agentMap.values()), [agentMap]);

  // Extract dispatch payloads from events for each agent
  const dispatchPayloads = useMemo(() => {
    const map = new Map<string, Record<string, unknown>>();
    for (const e of events) {
      if (e.type === "agent_dispatch" && typeof e.payload.agent_id === "string") {
        map.set(e.payload.agent_id as string, e.payload as Record<string, unknown>);
      }
    }
    return map;
  }, [events]);

  if (agents.length === 0) {
    return (
      <div className="h-full flex items-center justify-center">
        <div className="text-[10px] font-mono text-text-muted">暂无调度记录</div>
      </div>
    );
  }

  return (
    <div className="h-full overflow-y-auto">
      <div className="px-3 py-2">
        <div className="flex items-center gap-2 mb-2">
          <span className="w-1.5 h-1.5 rounded-full bg-violet"></span>
          <span className="font-display text-[10px] font-bold text-text-bright uppercase tracking-wider">
            调度审计
          </span>
          <span className="text-[9px] font-mono text-text-muted">({agents.length} agents)</span>
        </div>
        <div className="border border-border rounded overflow-hidden">
          {agents.map((agent) => (
            <AgentRow
              key={agent.agent_id}
              agent={agent}
              dispatchPayload={dispatchPayloads.get(agent.agent_id) ?? null}
            />
          ))}
        </div>
      </div>
    </div>
  );
});
