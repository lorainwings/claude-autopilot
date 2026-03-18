import { memo, useRef } from "react";
import { useStore } from "../store";
import { useVirtualizer } from "@tanstack/react-virtual";

function pretty(value: unknown): string {
  if (value == null) return "";
  if (typeof value === "string") return value;
  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return String(value);
  }
}

export const ToolTracePanel = memo(function ToolTracePanel() {
  const toolEvents = useStore((s) => s.toolEvents);
  const containerRef = useRef<HTMLDivElement>(null);

  // 倒序展示（最新在最前）
  const reversed = toolEvents.slice().reverse();

  const virtualizer = useVirtualizer({
    count: reversed.length,
    getScrollElement: () => containerRef.current,
    estimateSize: () => 80,
    overscan: 5,
  });

  if (reversed.length === 0) {
    return (
      <div className="h-full flex items-center justify-center text-text-muted text-sm font-mono">
        暂无工具调用明细
      </div>
    );
  }

  return (
    <div ref={containerRef} className="h-full overflow-y-auto bg-void">
      <div
        className="relative w-full"
        style={{ height: `${virtualizer.getTotalSize()}px` }}
      >
        {virtualizer.getVirtualItems().map((virtualRow) => {
          const event = reversed[virtualRow.index]!;
          const payload = event.payload as Record<string, unknown>;
          const toolName = String(payload.tool_name ?? "--");
          const keyParam = payload.key_param ? String(payload.key_param) : "";
          const outputPreview = payload.output_preview ? String(payload.output_preview) : "";
          const exitCode = typeof payload.exit_code === "number" ? payload.exit_code : undefined;
          const agentId = typeof payload.agent_id === "string" ? payload.agent_id : undefined;
          return (
            <div
              key={virtualRow.key}
              data-index={virtualRow.index}
              ref={virtualizer.measureElement}
              className="absolute top-0 left-0 w-full px-4 py-1.5"
              style={{ transform: `translateY(${virtualRow.start}px)` }}
            >
              <article className="border border-border rounded-lg bg-deep/70 overflow-hidden">
                <div className="px-3 py-2 border-b border-border flex items-center justify-between text-[10px] font-mono">
                  <div className="flex items-center gap-2 min-w-0">
                    <span className="px-2 py-0.5 rounded border border-cyan/40 bg-cyan/10 text-cyan font-bold">{toolName}</span>
                    <span className="text-text-muted">Phase {event.phase}</span>
                    {agentId && <span className="text-violet truncate">{agentId}</span>}
                    {exitCode != null && (
                      <span className={exitCode === 0 ? "text-emerald" : "text-rose"}>exit={exitCode}</span>
                    )}
                  </div>
                  <span className="text-text-muted">{new Date(event.timestamp).toLocaleTimeString()}</span>
                </div>
                <div className="p-3 space-y-3 text-[12px] font-mono">
                  {keyParam && (
                    <div>
                      <div className="text-text-muted mb-1">关键参数</div>
                      <pre className="whitespace-pre-wrap break-words text-text-bright">{keyParam}</pre>
                    </div>
                  )}
                  {outputPreview && (
                    <div>
                      <div className="text-text-muted mb-1">输出预览</div>
                      <pre className="whitespace-pre-wrap break-words text-text-bright">{outputPreview}</pre>
                    </div>
                  )}
                  {(payload.tool_input != null || payload.tool_result != null) && (
                    <details className="border border-border rounded bg-void/70">
                      <summary className="px-3 py-2 cursor-pointer text-text-muted">查看结构化输入/输出</summary>
                      <div className="grid grid-cols-1 xl:grid-cols-2 gap-3 p-3 border-t border-border">
                        <div>
                          <div className="text-text-muted mb-1">tool_input</div>
                          <pre className="whitespace-pre-wrap break-words text-text-bright">{pretty(payload.tool_input)}</pre>
                        </div>
                        <div>
                          <div className="text-text-muted mb-1">tool_result</div>
                          <pre className="whitespace-pre-wrap break-words text-text-bright">{pretty(payload.tool_result)}</pre>
                        </div>
                      </div>
                    </details>
                  )}
                </div>
              </article>
            </div>
          );
        })}
      </div>
    </div>
  );
});
