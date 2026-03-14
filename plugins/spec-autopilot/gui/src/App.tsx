/**
 * App — 主应用组件
 * 集成 WSBridge、Zustand store、所有子组件
 */

import { useEffect } from "react";
import { WSBridge } from "./lib/ws-bridge";
import { useStore } from "./store";
import { PhaseTimeline } from "./components/PhaseTimeline";
import { GateBlockCard } from "./components/GateBlockCard";
import { VirtualTerminal } from "./components/VirtualTerminal";
import { ParallelKanban } from "./components/ParallelKanban";

const wsBridge = new WSBridge();

export function App() {
  const { connected, setConnected, addEvents, setDecisionAcked, changeName, sessionId } = useStore();

  useEffect(() => {
    wsBridge.connect();

    const unsubscribe = wsBridge.onEvents((events) => {
      addEvents(events);
    });

    // v5.2: Listen for decision_ack to dismiss GateBlockCard
    const unsubscribeAck = wsBridge.onDecisionAck(() => {
      setDecisionAcked(true);
      // Reset after a new gate_block event may arrive
      setTimeout(() => setDecisionAcked(false), 500);
    });

    const checkConnection = setInterval(() => {
      setConnected(wsBridge.connected);
    }, 1000);

    return () => {
      clearInterval(checkConnection);
      unsubscribe();
      unsubscribeAck();
      wsBridge.disconnect();
    };
  }, [addEvents, setConnected, setDecisionAcked]);

  const handleDecision = async (action: "retry" | "fix" | "override", phase: number) => {
    try {
      wsBridge.sendDecision({ action, phase });
    } catch (error) {
      console.error("Failed to send decision:", error);
      throw error;
    }
  };

  return (
    <div className="app">
      <header className="app-header">
        <h1>🚀 Autopilot Dashboard</h1>
        <div className="header-info">
          <span className="change-name">{changeName || "—"}</span>
          <span className="session-id">{sessionId || "—"}</span>
          <span className={`connection-status ${connected ? "connected" : "disconnected"}`}>
            {connected ? "● Connected" : "○ Disconnected"}
          </span>
        </div>
      </header>

      <main className="app-main">
        <section className="section-timeline">
          <PhaseTimeline />
        </section>

        <section className="section-sidebar">
          <GateBlockCard onDecision={handleDecision} />
          <ParallelKanban />
        </section>

        <section className="section-terminal">
          <VirtualTerminal />
        </section>
      </main>
    </div>
  );
}
