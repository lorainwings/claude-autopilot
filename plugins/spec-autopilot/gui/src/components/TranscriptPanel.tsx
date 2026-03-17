import { memo } from "react";
import { useStore } from "../store";

function roleClass(role: string) {
  if (role === "user") return "text-cyan border-cyan/40 bg-cyan/5";
  if (role === "assistant") return "text-emerald border-emerald/30 bg-emerald/5";
  if (role === "system") return "text-amber border-amber/30 bg-amber/5";
  if (role === "tool") return "text-violet border-violet/30 bg-violet/5";
  return "text-text-muted border-border bg-deep";
}

export const TranscriptPanel = memo(function TranscriptPanel() {
  const events = useStore((s) => s.events);
  const transcriptEvents = events.filter((event) => event.type === "transcript_message");

  if (transcriptEvents.length === 0) {
    return (
      <div className="h-full flex items-center justify-center text-text-muted text-sm font-mono">
        暂无 transcript 正文
      </div>
    );
  }

  return (
    <div className="h-full overflow-y-auto p-4 space-y-3 bg-void">
      {transcriptEvents.map((event) => {
        const role = (event.payload.role as string | undefined) || "event";
        const text = (event.payload.text as string | undefined) || "";
        const kind = (event.payload.transcript_kind as string | undefined) || "main";
        const agentId = event.payload.agent_id as string | undefined;
        return (
          <article key={event.event_id || `${event.timestamp}-${text.slice(0, 8)}`} className="border border-border rounded-lg bg-deep/70 overflow-hidden">
            <div className="flex items-center justify-between px-3 py-2 border-b border-border text-[10px] font-mono text-text-muted">
              <div className="flex items-center gap-2">
                <span className={`px-2 py-0.5 border rounded uppercase tracking-wide ${roleClass(role)}`}>
                  {role}
                </span>
                <span>Phase {event.phase}</span>
                <span>{kind === "agent" ? "子代理" : "主会话"}</span>
                {agentId && <span className="text-violet">{agentId}</span>}
              </div>
              <span>{new Date(event.timestamp).toLocaleTimeString()}</span>
            </div>
            <pre className="p-3 text-[12px] leading-6 whitespace-pre-wrap break-words font-mono text-text-bright">
              {text}
            </pre>
          </article>
        );
      })}
    </div>
  );
});
