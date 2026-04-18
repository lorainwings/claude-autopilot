/**
 * App -- v7.0 主应用组件 (orchestration-first + report-visible)
 * 三栏布局: 左侧时间轴 | 中心(OrchestrationPanel + PhasePipelineOverview + GateBlockCard + ReportCard) | 右侧遥测(可折叠)
 * v7.0 变更: 主窗口只保留编排控制信息，LogWorkbench 下沉为二级诊断面板
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
import { ReportCard } from "./components/ReportCard";
import { PhaseResultsTable } from "./components/PhaseResultsTable";
import type { ModelRoutingState } from "./store";

declare const __PLUGIN_VERSION__: string;

// 模块级 bridge 引用，由 useEffect 内部异步初始化
let _bridge: WSBridge | null = null;

/** 计算 WS URL：优先用 /api/info 返回的 wsPort，否则从当前页面端口 +1 推导 */
async function resolveWsUrl(): Promise<string> {
  const host = window.location.hostname || "localhost";
  try {
    const r = await fetch("/api/info", { signal: AbortSignal.timeout(3000) });
    const info = await r.json();
    if (info.wsPort) return `ws://${host}:${info.wsPort}`;
  } catch { /* fall through */ }
  const httpPort = parseInt(window.location.port, 10) || 9527;
  return `ws://${host}:${httpPort + 1}`;
}

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
  const { connected, setConnected, setHttpOk, addEvents, initOrchestrationFromMeta, changeName, sessionId, mode } = useStore();
  const hasEvents = useStore((s) => s.events.length > 0);
  const modelRouting = useStore((s) => s.modelRouting);
  const [telemetryOpen, setTelemetryOpen] = useState(false);
  // v7.0: 主窗口默认显示 orchestration 视图，diagnostics 为二级面板
  const [activeView, setActiveView] = useState<"orchestration" | "diagnostics">("orchestration");
  // 运行时版本（以 /api/info 为权威来源，消除构建期烘焙漂移）
  const [liveVersion, setLiveVersion] = useState<string>(__PLUGIN_VERSION__);

  useEffect(() => {
    let cancelled = false;
    let connectionTimer: ReturnType<typeof setInterval> | null = null;
    let httpTimer: ReturnType<typeof setInterval> | null = null;
    let unsubs: Array<() => void> = [];

    // 运行时拉取权威版本（以 plugin.json 为准，绕过构建烘焙 + 浏览器缓存）
    fetch("/api/info", { signal: AbortSignal.timeout(3000) })
      .then((r) => r.json())
      .then((info) => {
        if (!cancelled && typeof info?.version === "string" && info.version) {
          setLiveVersion(info.version);
        }
      })
      .catch(() => { /* 保持烘焙 fallback */ });

    // 异步初始化：先拿 wsPort，再创建 bridge + 订阅
    resolveWsUrl().then((wsUrl) => {
      if (cancelled) return;

      const bridge = new WSBridge(wsUrl);
      _bridge = bridge;
      bridge.connect();

      unsubs.push(bridge.onEvents((events) => { addEvents(events); }));
      unsubs.push(bridge.onMeta((meta) => { initOrchestrationFromMeta(meta); }));
      unsubs.push(bridge.onReset(() => { useStore.getState().reset(); }));
      unsubs.push(bridge.onDecisionAck(() => {
        const state = useStore.getState();
        const blockEvents = state.events.filter((e) => e.type === "gate_block");
        const lastBlockSeq = blockEvents.length > 0 ? blockEvents[blockEvents.length - 1]!.sequence : -1;
        useStore.setState({ decisionAcked: true, lastAckedBlockSequence: lastBlockSeq });
      }));

      connectionTimer = setInterval(() => { setConnected(bridge.connected); }, 1000);
    });

    // v5.4: Independent HTTP health ping (not tied to WS state)
    httpTimer = setInterval(() => {
      fetch("/api/health", { signal: AbortSignal.timeout(2000) })
        .then((r) => { setHttpOk(r.ok); })
        .catch(() => {
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
      cancelled = true;
      if (connectionTimer) clearInterval(connectionTimer);
      if (httpTimer) clearInterval(httpTimer);
      unsubs.forEach((fn) => fn());
      _bridge?.disconnect();
      _bridge = null;
    };
  }, [addEvents, initOrchestrationFromMeta, setConnected, setHttpOk]);

  const handleDecision = async (action: "retry" | "fix" | "override", phase: number, reason?: string) => {
    try {
      _bridge?.sendDecision({ action, phase, reason });
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
              Autopilot <span className="text-cyan">v{liveVersion}</span>
            </h1>
          </div>
          <div className="h-4 w-px bg-border"></div>
          <div className="flex items-center space-x-4 font-mono text-xs text-text-muted">
            <div>变更: <span className="text-text-bright">{changeName || "\u2014"}</span></div>
            <div>会话: <span className="text-text-bright">{sessionId ? sessionId.slice(0, 8) : "\u2014"}</span></div>
          </div>
        </div>
        <div className="flex items-center space-x-4">
          {/* v7.0: 视图切换按钮 */}
          <div className="flex items-center border border-border rounded overflow-hidden">
            <button
              onClick={() => setActiveView("orchestration")}
              className={`px-2 py-0.5 text-[10px] font-mono transition-colors ${
                activeView === "orchestration"
                  ? "bg-cyan/15 text-cyan border-r border-cyan/30"
                  : "text-text-muted hover:text-text-bright border-r border-border"
              }`}
            >
              编排
            </button>
            <button
              onClick={() => setActiveView("diagnostics")}
              className={`px-2 py-0.5 text-[10px] font-mono transition-colors ${
                activeView === "diagnostics"
                  ? "bg-cyan/15 text-cyan"
                  : "text-text-muted hover:text-text-bright"
              }`}
            >
              诊断
            </button>
          </div>
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
                {activeView === "orchestration" ? (
                  <>
                    {/* v7.0: 编排视图 — PhasePipelineOverview + ReportCard + Kanban */}
                    <div className="h-[40%] overflow-auto">
                      <ParallelKanban />
                    </div>
                    <div className="h-[20%] overflow-auto p-4">
                      <PhaseResultsTable />
                    </div>
                    <div className="h-[40%] overflow-auto p-4 space-y-3">
                      <ReportCard />
                    </div>
                  </>
                ) : (
                  <>
                    {/* 诊断视图 — LogWorkbench (二级面板) */}
                    <div className="h-full">
                      <LogWorkbench />
                    </div>
                  </>
                )}
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
