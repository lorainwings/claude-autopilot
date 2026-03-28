/**
 * App -- v5.9 主应用组件 (orchestration-first)
 * 三栏布局: 左侧时间轴 | 中心(OrchestrationPanel + Kanban + LogWorkbench) | 右侧遥测(可折叠)
 * 核心变更: 主窗口优先展示编排信息，遥测降级为折叠面板
 */

import { useEffect, memo, useState } from "react";
import { WSBridge } from "./lib/ws-bridge";
import { useStore } from "./store";
import { PhaseTimeline } from "./components/PhaseTimeline";
import { GateBlockCard } from "./components/GateBlockCard";
import { OrchestrationPanel } from "./components/OrchestrationPanel";
import { ParallelKanban } from "./components/ParallelKanban";
import { TelemetryDashboard } from "./components/TelemetryDashboard";
import { LogWorkbench } from "./components/LogWorkbench";
import type { ModelRoutingState } from "./store";

declare const __PLUGIN_VERSION__: string;

const wsBridge = new WSBridge();

// --- Model Routing Banner (v5.8) ---
// 显示在中心主视区，醒目提示当前 Phase 的模型路由决策
const ModelRoutingBanner = memo(function ModelRoutingBanner({ routing }: { routing: ModelRoutingState }) {
  const [visible, setVisible] = useState(false);
  const [prev, setPrev] = useState<string | null>(null);

  // 每次 updated_at 变化（新路由事件）时显示 banner，8 秒后自动淡出
  useEffect(() => {
    if (!routing.updated_at || routing.updated_at === prev) return;
    setPrev(routing.updated_at);
    setVisible(true);
    const t = setTimeout(() => setVisible(false), 8000);
    return () => clearTimeout(t);
  }, [routing.updated_at, prev]);

  if (!visible || !routing.updated_at) return null;

  const isFallback = routing.fallback_applied;
  const isEscalated = (routing as unknown as Record<string, unknown>).escalated_from != null;
  const borderColor = isFallback ? "border-rose/60" : isEscalated ? "border-amber/60" : "border-cyan/60";
  const titleColor = isFallback ? "text-rose" : isEscalated ? "text-amber" : "text-cyan";

  return (
    <div className={`mx-4 mt-3 px-4 py-2 bg-deep border ${borderColor} rounded font-mono text-[11px] z-20`}>
      <div className="flex items-center gap-2">
        <span className={`font-bold ${titleColor}`}>
          Phase {routing.phase} Model:
        </span>
        <span className="text-text-bright font-bold">
          {routing.requested_model ?? "--"}
        </span>
        <span className="text-text-muted">
          ({routing.requested_tier ?? "--"})
        </span>
        {routing.requested_effort && (
          <span className="text-text-muted">| Effort: {routing.requested_effort}</span>
        )}
        {routing.routing_reason && (
          <span className="text-text-muted truncate">| {routing.routing_reason}</span>
        )}
        {isFallback && routing.fallback_model && (
          <span className="text-rose font-bold ml-1">Fallback: {routing.fallback_model}</span>
        )}
        {isEscalated && (
          <span className="text-amber ml-1">Escalated</span>
        )}
        <button
          className="ml-auto text-text-muted hover:text-text-bright shrink-0"
          onClick={() => setVisible(false)}
        >
          x
        </button>
      </div>
    </div>
  );
});

export function App() {
  const { connected, setConnected, setHttpOk, addEvents, changeName, sessionId, mode } = useStore();
  const hasEvents = useStore((s) => s.events.length > 0);
  const modelRouting = useStore((s) => s.modelRouting);
  const [telemetryOpen, setTelemetryOpen] = useState(false);

  useEffect(() => {
    wsBridge.connect();

    const unsubscribe = wsBridge.onEvents((events) => {
      addEvents(events);
    });

    // v5.4: Listen for reset signal (restart scenario) -> clear all GUI state
    const unsubscribeReset = wsBridge.onReset(() => {
      useStore.getState().reset();
    });

    // v5.1.51: decision_ack only for UI feedback -- does not control GateBlockCard visibility
    // Merged into single atomic setState to avoid intermediate render (P0-3 fix)
    const unsubscribeAck = wsBridge.onDecisionAck(() => {
      const state = useStore.getState();
      const blockEvents = state.events.filter((e) => e.type === "gate_block");
      const lastBlockSeq = blockEvents.length > 0 ? blockEvents[blockEvents.length - 1]!.sequence : -1;
      useStore.setState({ decisionAcked: true, lastAckedBlockSequence: lastBlockSeq });
    });

    const checkConnection = setInterval(() => {
      setConnected(wsBridge.connected);
    }, 1000);

    // v5.4: Independent HTTP health ping (not tied to WS state)
    const checkHttp = setInterval(() => {
      fetch("/api/health", { signal: AbortSignal.timeout(2000) })
        .then((r) => { setHttpOk(r.ok); })
        .catch(() => {
          // Fallback to /api/info if /api/health not available
          fetch("/api/info", { signal: AbortSignal.timeout(2000) })
            .then((r) => { setHttpOk(r.ok); })
            .catch(() => { setHttpOk(false); });
        });
    }, 5000);
    // Initial check
    fetch("/api/health", { signal: AbortSignal.timeout(2000) })
      .then((r) => { setHttpOk(r.ok); })
      .catch(() => {
        fetch("/api/info", { signal: AbortSignal.timeout(2000) })
          .then((r) => { setHttpOk(r.ok); })
          .catch(() => { setHttpOk(false); });
      });

    return () => {
      clearInterval(checkConnection);
      clearInterval(checkHttp);
      unsubscribe();
      unsubscribeReset();
      unsubscribeAck();
      wsBridge.disconnect();
    };
  }, [addEvents, setConnected, setHttpOk]);

  const handleDecision = async (action: "retry" | "fix" | "override", phase: number, reason?: string) => {
    try {
      wsBridge.sendDecision({ action, phase, reason });
    } catch (error) {
      console.error("Failed to send decision:", error);
      throw error;
    }
  };

  return (
    <div className="font-body h-full flex flex-col selection:bg-cyan selection:text-void">
      {/* Global Overlays */}
      <div className="scanline-overlay animate-scanline"></div>
      <div className="fixed inset-0 grid-background opacity-40 pointer-events-none"></div>

      {/* HeaderBar */}
      <header className="h-12 border-b border-border bg-abyss flex items-center justify-between px-4 z-50 shrink-0">
        <div className="flex items-center space-x-6">
          <div className="flex items-center space-x-2">
            <span className="text-cyan text-xl">{"\u2B21"}</span>
            <h1 className="font-display font-bold text-sm tracking-widest text-text-bright uppercase">
              Autopilot <span className="text-cyan">v{__PLUGIN_VERSION__}</span>
            </h1>
          </div>
          <div className="h-4 w-px bg-border"></div>
          <div className="flex items-center space-x-4 font-mono text-xs text-text-muted">
            <div>变更: <span className="text-text-bright">{changeName || "\u2014"}</span></div>
            <div>会话: <span className="text-text-bright">{sessionId ? sessionId.slice(0, 8) : "\u2014"}</span></div>
          </div>
        </div>
        <div className="flex items-center space-x-4">
          {/* 遥测面板展开/折叠按钮 */}
          <button
            onClick={() => setTelemetryOpen(!telemetryOpen)}
            className={`px-2 py-0.5 text-[10px] font-mono border rounded transition-colors ${
              telemetryOpen
                ? "border-cyan/50 bg-cyan/10 text-cyan"
                : "border-border text-text-muted hover:border-cyan/30"
            }`}
          >
            {telemetryOpen ? "收起遥测" : "展开遥测"}
          </button>
          {mode && (
            <div className="px-2 py-0.5 border border-cyan/50 bg-cyan/10 text-cyan text-[10px] font-bold rounded uppercase tracking-tighter">
              {mode === "full" ? "全模式" : mode === "lite" ? "精简" : "最小"}
            </div>
          )}
          <div className={`flex items-center space-x-2 text-[11px] font-bold uppercase ${connected ? "text-emerald" : "text-rose"}`}>
            <span className="relative flex h-2 w-2">
              {connected && (
                <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald opacity-75"></span>
              )}
              <span className={`relative inline-flex rounded-full h-2 w-2 ${connected ? "bg-emerald" : "bg-rose"}`}></span>
            </span>
            <span>{connected ? "运行中" : "断开"}</span>
          </div>
        </div>
      </header>

      {/* Main Layout */}
      <main className="flex flex-1 overflow-hidden">
        {/* Left Panel: Phase Timeline */}
        <PhaseTimeline />

        {/* Center: Orchestration + Kanban + LogWorkbench */}
        <div className="flex flex-1 min-w-0">
          {/* Orchestration Panel (左侧编排驾驶舱) */}
          <div className="w-[260px] shrink-0 border-r border-border">
            <OrchestrationPanel />
          </div>

          {/* Main Content Area */}
          <div className="flex-1 flex flex-col min-w-0 bg-void">
            {/* Gate Block Card -- Floating overlay when active */}
            <div className="relative">
              <div className="absolute top-4 left-4 right-4 z-30">
                <GateBlockCard onDecision={handleDecision} />
              </div>
            </div>

            {/* Model Routing Banner -- 中心醒目展示当前 Phase 模型路由 (v5.8) */}
            <ModelRoutingBanner routing={modelRouting} />

            {/* Empty state placeholder when no events yet */}
            {!hasEvents && (
              <div className="flex-1 flex items-center justify-center">
                <div className="text-center space-y-3">
                  <div className="w-8 h-8 border-2 border-cyan/40 border-t-cyan rounded-full animate-spin mx-auto"></div>
                  <div className="font-mono text-sm text-text-muted">
                    {connected ? "等待事件流..." : "正在连接引擎..."}
                  </div>
                </div>
              </div>
            )}

            {hasEvents && (
              <>
                {/* ParallelKanban (Top) */}
                <div className="h-[42%]">
                  <ParallelKanban />
                </div>

                {/* Log Workbench (Bottom) */}
                <div className="h-[58%]">
                  <LogWorkbench />
                </div>
              </>
            )}
          </div>
        </div>

        {/* Right Panel: Telemetry Dashboard (可折叠) */}
        {telemetryOpen && <TelemetryDashboard />}
      </main>
    </div>
  );
}
