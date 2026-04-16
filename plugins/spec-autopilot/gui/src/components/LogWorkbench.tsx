import { useState } from "react";
import { VirtualTerminal } from "./VirtualTerminal";
import { TranscriptPanel } from "./TranscriptPanel";
import { ToolTracePanel } from "./ToolTracePanel";
import { RawInspectorPanel } from "./RawInspectorPanel";
import { DispatchAuditPanel } from "./DispatchAuditPanel";

type TabKey = "events" | "transcript" | "tools" | "raw" | "dispatch";

const TABS: Array<{ key: TabKey; label: string }> = [
  { key: "events", label: "事件流" },
  { key: "transcript", label: "正文" },
  { key: "tools", label: "工具" },
  { key: "dispatch", label: "调度" },
  { key: "raw", label: "原始" },
];

export function LogWorkbench() {
  const [activeTab, setActiveTab] = useState<TabKey>("events");

  return (
    <section className="h-full flex flex-col bg-void overflow-hidden">
      <div className="h-9 shrink-0 border-b border-border bg-surface flex items-center justify-between px-4">
        <div className="font-display text-[10px] uppercase tracking-[0.25em] text-text-bright">
          日志工作台
        </div>
        <div className="flex items-center gap-2">
          {TABS.map((tab) => (
            <button
              key={tab.key}
              onClick={() => setActiveTab(tab.key)}
              className={`px-2 py-1 text-[10px] font-mono border rounded transition-colors ${
                activeTab === tab.key
                  ? "border-cyan/50 bg-cyan/10 text-cyan"
                  : "border-border text-text-muted hover:border-cyan/30"
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>
      </div>

      <div className="flex-1 min-h-0">
        {activeTab === "events" && <VirtualTerminal />}
        {activeTab === "transcript" && <TranscriptPanel />}
        {activeTab === "tools" && <ToolTracePanel />}
        {activeTab === "dispatch" && <DispatchAuditPanel />}
        {activeTab === "raw" && <RawInspectorPanel />}
      </div>
    </section>
  );
}
