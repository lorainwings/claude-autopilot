/**
 * AgentTranscriptPanel — 选中 agent 的综合视图
 * 三栏布局: Transcript | Tool Calls | File Changes
 */

import { memo, useMemo, useRef, useState } from "react";
import { useStore, selectAgentIds } from "../store";
import { useVirtualizer } from "@tanstack/react-virtual";

/** 从 tool_use 事件中提取文件路径（Write/Edit 操作） */
function extractFilePaths(toolEvents: Array<{ payload: Record<string, unknown> }>): string[] {
  const paths = new Set<string>();
  for (const ev of toolEvents) {
    const toolName = ev.payload.tool_name as string | undefined;
    if (toolName === "Write" || toolName === "Edit" || toolName === "write" || toolName === "edit") {
      const filePath = (ev.payload.file_path as string) || (ev.payload.path as string);
      if (filePath) paths.add(filePath);
    }
  }
  return Array.from(paths).sort();
}

function roleClass(role: string) {
  if (role === "user") return "text-cyan border-cyan/40 bg-cyan/5";
  if (role === "assistant") return "text-emerald border-emerald/30 bg-emerald/5";
  if (role === "system") return "text-amber border-amber/30 bg-amber/5";
  if (role === "tool") return "text-violet border-violet/30 bg-violet/5";
  return "text-text-muted border-border bg-deep";
}

/** 虚拟化 Transcript 列 */
const TranscriptColumn = memo(function TranscriptColumn({
  events,
}: {
  events: Array<{ payload: Record<string, unknown>; phase: number; timestamp: string }>;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const virtualizer = useVirtualizer({
    count: events.length,
    getScrollElement: () => containerRef.current,
    estimateSize: () => 80,
    overscan: 5,
  });

  if (events.length === 0) {
    return (
      <div className="h-full flex items-center justify-center text-text-muted text-xs font-mono">
        暂无 transcript
      </div>
    );
  }

  return (
    <div ref={containerRef} className="h-full overflow-y-auto">
      <div className="relative w-full" style={{ height: `${virtualizer.getTotalSize()}px` }}>
        {virtualizer.getVirtualItems().map((vr) => {
          const ev = events[vr.index]!;
          const role = (ev.payload.role as string) || "event";
          const text = (ev.payload.text as string) || (ev.payload.text_preview as string) || "";
          return (
            <div
              key={vr.key}
              data-index={vr.index}
              ref={virtualizer.measureElement}
              className="absolute top-0 left-0 w-full px-2 py-1"
              style={{ transform: `translateY(${vr.start}px)` }}
            >
              <div className="border border-border rounded bg-deep/70 p-2 text-[11px] font-mono">
                <div className="flex items-center gap-2 mb-1">
                  <span className={`px-1.5 py-0.5 border rounded uppercase text-[9px] tracking-wide ${roleClass(role)}`}>
                    {role}
                  </span>
                  <span className="text-text-muted text-[9px]">
                    {new Date(ev.timestamp).toLocaleTimeString()}
                  </span>
                </div>
                <pre className="whitespace-pre-wrap break-words text-text-bright leading-5">
                  {text}
                </pre>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
});

/** 虚拟化 Tool Calls 列 */
const ToolCallsColumn = memo(function ToolCallsColumn({
  events,
}: {
  events: Array<{ payload: Record<string, unknown>; timestamp: string }>;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const virtualizer = useVirtualizer({
    count: events.length,
    getScrollElement: () => containerRef.current,
    estimateSize: () => 60,
    overscan: 5,
  });

  if (events.length === 0) {
    return (
      <div className="h-full flex items-center justify-center text-text-muted text-xs font-mono">
        暂无工具调用
      </div>
    );
  }

  return (
    <div ref={containerRef} className="h-full overflow-y-auto">
      <div className="relative w-full" style={{ height: `${virtualizer.getTotalSize()}px` }}>
        {virtualizer.getVirtualItems().map((vr) => {
          const ev = events[vr.index]!;
          const toolName = (ev.payload.tool_name as string) || "unknown";
          const status = (ev.payload.status as string) || "";
          const filePath = (ev.payload.file_path as string) || (ev.payload.path as string) || "";
          return (
            <div
              key={vr.key}
              data-index={vr.index}
              ref={virtualizer.measureElement}
              className="absolute top-0 left-0 w-full px-2 py-1"
              style={{ transform: `translateY(${vr.start}px)` }}
            >
              <div className="border border-border rounded bg-deep/70 p-2 text-[11px] font-mono">
                <div className="flex items-center gap-2">
                  <span className="px-1.5 py-0.5 rounded bg-amber/10 border border-amber/30 text-amber text-[9px]">
                    {toolName}
                  </span>
                  {status && (
                    <span className={`text-[9px] ${status === "error" ? "text-red-400" : "text-emerald"}`}>
                      {status}
                    </span>
                  )}
                  <span className="text-text-muted text-[9px] ml-auto">
                    {new Date(ev.timestamp).toLocaleTimeString()}
                  </span>
                </div>
                {filePath && (
                  <div className="mt-1 text-[10px] text-text-muted truncate" title={filePath}>
                    {filePath}
                  </div>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
});

export const AgentTranscriptPanel = memo(function AgentTranscriptPanel() {
  const transcriptEvents = useStore((s) => s.transcriptEvents);
  const toolEvents = useStore((s) => s.toolEvents);
  const agentMap = useStore((s) => s.agentMap);
  const [selectedAgentId, setSelectedAgentId] = useState<string>("__none__");

  const agentOptions = useMemo(() => selectAgentIds(agentMap), [agentMap]);

  // 过滤选中 agent 的 transcript 事件
  const agentTranscripts = useMemo(() => {
    if (selectedAgentId === "__none__") return [];
    return transcriptEvents.filter(
      (e) => (e.payload.agent_id as string | undefined) === selectedAgentId,
    );
  }, [transcriptEvents, selectedAgentId]);

  // 过滤选中 agent 的 tool_use 事件
  const agentTools = useMemo(() => {
    if (selectedAgentId === "__none__") return [];
    return toolEvents.filter(
      (e) => (e.payload.agent_id as string | undefined) === selectedAgentId,
    );
  }, [toolEvents, selectedAgentId]);

  // 从 tool 事件中提取文件变更列表
  const fileChanges = useMemo(() => extractFilePaths(agentTools), [agentTools]);

  if (agentOptions.length === 0) {
    return (
      <div className="h-full flex items-center justify-center text-text-muted text-sm font-mono">
        暂无活跃 Agent
      </div>
    );
  }

  return (
    <div className="h-full flex flex-col bg-void">
      {/* Agent 选择器 */}
      <div className="flex items-center gap-2 px-4 py-2 border-b border-border bg-deep/50">
        <label className="text-[10px] font-mono text-text-muted uppercase tracking-wide">
          Agent 综合视图
        </label>
        <select
          value={selectedAgentId}
          onChange={(e) => setSelectedAgentId(e.target.value)}
          className="bg-deep border border-border rounded px-2 py-1 text-xs font-mono text-text-bright focus:outline-none focus:border-violet"
        >
          <option value="__none__">-- 选择 Agent --</option>
          {agentOptions.map((a) => (
            <option key={a.id} value={a.id}>
              {a.label || a.id}
            </option>
          ))}
        </select>
        {selectedAgentId !== "__none__" && (
          <span className="text-[10px] text-text-muted font-mono">
            Transcript: {agentTranscripts.length} | 工具: {agentTools.length} | 文件: {fileChanges.length}
          </span>
        )}
      </div>

      {/* 三栏布局 */}
      {selectedAgentId === "__none__" ? (
        <div className="flex-1 flex items-center justify-center text-text-muted text-xs font-mono">
          请选择一个 Agent 查看详情
        </div>
      ) : (
        <div className="flex-1 grid grid-cols-3 gap-px bg-border min-h-0">
          {/* Transcript 栏 */}
          <div className="flex flex-col bg-void min-h-0">
            <div className="px-3 py-1.5 border-b border-border bg-deep/30 text-[10px] font-mono text-text-muted uppercase tracking-wide">
              Transcript ({agentTranscripts.length})
            </div>
            <div className="flex-1 min-h-0">
              <TranscriptColumn events={agentTranscripts} />
            </div>
          </div>

          {/* Tool Calls 栏 */}
          <div className="flex flex-col bg-void min-h-0">
            <div className="px-3 py-1.5 border-b border-border bg-deep/30 text-[10px] font-mono text-text-muted uppercase tracking-wide">
              工具调用 ({agentTools.length})
            </div>
            <div className="flex-1 min-h-0">
              <ToolCallsColumn events={agentTools} />
            </div>
          </div>

          {/* File Changes 栏 */}
          <div className="flex flex-col bg-void min-h-0">
            <div className="px-3 py-1.5 border-b border-border bg-deep/30 text-[10px] font-mono text-text-muted uppercase tracking-wide">
              文件变更 ({fileChanges.length})
            </div>
            <div className="flex-1 overflow-y-auto p-2">
              {fileChanges.length === 0 ? (
                <div className="text-text-muted text-xs font-mono text-center mt-4">
                  暂无文件变更
                </div>
              ) : (
                <ul className="space-y-1">
                  {fileChanges.map((fp) => (
                    <li
                      key={fp}
                      className="text-[11px] font-mono text-text-bright px-2 py-1.5 rounded border border-border bg-deep/50 truncate"
                      title={fp}
                    >
                      <span className="text-emerald mr-1.5">M</span>
                      {fp.split("/").slice(-2).join("/")}
                    </li>
                  ))}
                </ul>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
});
