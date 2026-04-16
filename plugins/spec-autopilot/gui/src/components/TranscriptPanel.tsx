import { memo, useMemo, useRef, useState } from "react";
import { useStore, selectAgentIds } from "../store";
import { useVirtualizer } from "@tanstack/react-virtual";

function roleClass(role: string) {
  if (role === "user") return "text-cyan border-cyan/40 bg-cyan/5";
  if (role === "assistant") return "text-emerald border-emerald/30 bg-emerald/5";
  if (role === "system") return "text-amber border-amber/30 bg-amber/5";
  if (role === "tool") return "text-violet border-violet/30 bg-violet/5";
  return "text-text-muted border-border bg-deep";
}

export const TranscriptPanel = memo(function TranscriptPanel() {
  const transcriptEvents = useStore((s) => s.transcriptEvents);
  const agentMap = useStore((s) => s.agentMap);
  const [selectedAgentId, setSelectedAgentId] = useState<string>("__all__");
  const containerRef = useRef<HTMLDivElement>(null);

  // 从 agentMap 获取可选 agent 列表
  const agentOptions = useMemo(() => selectAgentIds(agentMap), [agentMap]);

  // 按选中 agent 过滤 transcript 事件
  const filteredEvents = useMemo(() => {
    if (selectedAgentId === "__all__") return transcriptEvents;
    return transcriptEvents.filter(
      (e) => (e.payload.agent_id as string | undefined) === selectedAgentId,
    );
  }, [transcriptEvents, selectedAgentId]);

  const virtualizer = useVirtualizer({
    count: filteredEvents.length,
    getScrollElement: () => containerRef.current,
    estimateSize: () => 120,
    overscan: 5,
  });

  if (transcriptEvents.length === 0) {
    return (
      <div className="h-full flex items-center justify-center text-text-muted text-sm font-mono">
        暂无 transcript 正文
      </div>
    );
  }

  return (
    <div className="h-full flex flex-col bg-void">
      {/* Agent 过滤选择器 */}
      {agentOptions.length > 0 && (
        <div className="flex items-center gap-2 px-4 py-2 border-b border-border bg-deep/50">
          <label className="text-[10px] font-mono text-text-muted uppercase tracking-wide">
            Agent 过滤
          </label>
          <select
            value={selectedAgentId}
            onChange={(e) => setSelectedAgentId(e.target.value)}
            className="bg-deep border border-border rounded px-2 py-1 text-xs font-mono text-text-bright focus:outline-none focus:border-violet"
          >
            <option value="__all__">All Agents</option>
            {agentOptions.map((a) => (
              <option key={a.id} value={a.id}>
                {a.label || a.id}
              </option>
            ))}
          </select>
          <span className="text-[10px] text-text-muted font-mono">
            {filteredEvents.length} / {transcriptEvents.length} 条
          </span>
        </div>
      )}

      {/* 虚拟化列表 */}
      <div ref={containerRef} className="flex-1 overflow-y-auto">
        <div
          className="relative w-full"
          style={{ height: `${virtualizer.getTotalSize()}px` }}
        >
          {virtualizer.getVirtualItems().map((virtualRow) => {
            const event = filteredEvents[virtualRow.index]!;
            const role = (event.payload.role as string | undefined) || "event";
            const text = (event.payload.text as string | undefined) || "";
            const kind = (event.payload.transcript_kind as string | undefined) || "main";
            const agentId = event.payload.agent_id as string | undefined;
            return (
              <div
                key={virtualRow.key}
                data-index={virtualRow.index}
                ref={virtualizer.measureElement}
                className="absolute top-0 left-0 w-full px-4 py-1.5"
                style={{ transform: `translateY(${virtualRow.start}px)` }}
              >
                <article className="border border-border rounded-lg bg-deep/70 overflow-hidden">
                  <div className="flex items-center justify-between px-3 py-2 border-b border-border text-[10px] font-mono text-text-muted">
                    <div className="flex items-center gap-2">
                      <span className={`px-2 py-0.5 border rounded uppercase tracking-wide ${roleClass(role)}`}>
                        {role}
                      </span>
                      <span>Phase {event.phase}</span>
                      <span>{kind === "agent" ? "子代理" : "主会话"}</span>
                      {agentId && (
                        <span className="px-1.5 py-0.5 rounded bg-violet/10 border border-violet/30 text-violet">
                          {agentMap.get(agentId)?.agent_label || agentId}
                        </span>
                      )}
                    </div>
                    <span>{new Date(event.timestamp).toLocaleTimeString()}</span>
                  </div>
                  <pre className="p-3 text-[12px] leading-6 whitespace-pre-wrap break-words font-mono text-text-bright">
                    {text}
                  </pre>
                </article>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
});
