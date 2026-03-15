/**
 * App — V2 主应用组件
 * 三栏布局: 左侧时间轴 | 中心(Kanban + Terminal) | 右侧遥测面板
 * 逻辑骨架: WSBridge + Zustand Store 保持不变
 */

import { useEffect } from "react";
import { WSBridge } from "./lib/ws-bridge";
import { useStore } from "./store";
import { PhaseTimeline } from "./components/PhaseTimeline";
import { GateBlockCard } from "./components/GateBlockCard";
import { VirtualTerminal } from "./components/VirtualTerminal";
import { ParallelKanban } from "./components/ParallelKanban";
import { TelemetryDashboard } from "./components/TelemetryDashboard";

declare const __PLUGIN_VERSION__: string;

const wsBridge = new WSBridge();

export function App() {
  const { connected, setConnected, addEvents, setDecisionAcked, setLastAckedBlockSequence, changeName, sessionId, mode } = useStore();
  const hasEvents = useStore((s) => s.events.length > 0);

  useEffect(() => {
    wsBridge.connect();

    const unsubscribe = wsBridge.onEvents((events) => {
      addEvents(events);
    });

    // v5.4: Listen for reset signal (restart scenario) → clear all GUI state
    const unsubscribeReset = wsBridge.onReset(() => {
      useStore.getState().reset();
    });

    // v5.2: Listen for decision_ack to dismiss GateBlockCard (event-driven, no timer)
    const unsubscribeAck = wsBridge.onDecisionAck(() => {
      // Record the sequence of the latest gate_block being acked
      const state = useStore.getState();
      const blockEvents = state.events.filter((e) => e.type === "gate_block");
      if (blockEvents.length > 0) {
        setLastAckedBlockSequence(blockEvents[blockEvents.length - 1]!.sequence);
      }
      setDecisionAcked(true);
    });

    const checkConnection = setInterval(() => {
      setConnected(wsBridge.connected);
    }, 1000);

    return () => {
      clearInterval(checkConnection);
      unsubscribe();
      unsubscribeReset();
      unsubscribeAck();
      wsBridge.disconnect();
    };
  }, [addEvents, setConnected, setDecisionAcked, setLastAckedBlockSequence]);

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

      {/* Main Three-Column Layout */}
      <main className="flex flex-1 overflow-hidden">
        {/* Left Panel: Phase Timeline */}
        <PhaseTimeline />

        {/* Center Panel: Kanban (top 45%) + Terminal (bottom 55%) */}
        <div className="flex-1 flex flex-col min-w-0 bg-void">
          {/* Gate Block Card — Floating overlay when active */}
          <div className="relative">
            <div className="absolute top-4 left-4 right-4 z-30">
              <GateBlockCard onDecision={handleDecision} />
            </div>
          </div>

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
              <div className="h-[45%]">
                <ParallelKanban />
              </div>

              {/* HackerTerminal (Bottom) */}
              <div className="h-[55%]">
                <VirtualTerminal />
              </div>
            </>
          )}
        </div>

        {/* Right Panel: Telemetry Dashboard */}
        <TelemetryDashboard />
      </main>
    </div>
  );
}
