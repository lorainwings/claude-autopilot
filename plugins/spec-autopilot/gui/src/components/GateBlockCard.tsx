/**
 * GateBlockCard — 门禁阻断卡片
 * 显示最近的 gate_block 事件详情，并提供决策按钮
 */

import { useState } from "react";
import { useStore } from "../store";

interface GateBlockCardProps {
  onDecision?: (action: "retry" | "fix" | "override", phase: number) => void;
}

export function GateBlockCard({ onDecision }: GateBlockCardProps) {
  const { events } = useStore();
  const [loading, setLoading] = useState<string | null>(null);

  const blockEvents = events.filter((e) => e.type === "gate_block");
  if (blockEvents.length === 0) return null;

  const latest = blockEvents[blockEvents.length - 1];
  const { phase, phase_label, payload } = latest;

  const handleDecision = async (action: "retry" | "fix" | "override") => {
    setLoading(action);
    try {
      await onDecision?.(action, phase);
      setTimeout(() => setLoading(null), 2000);
    } catch (error) {
      console.error("Decision failed:", error);
      setLoading(null);
    }
  };

  return (
    <div className="gate-block-card p-4 bg-red-900/20 rounded-lg border border-red-500/50 mb-4">
      <div className="card-header flex items-center gap-2 mb-3">
        <span className="text-2xl">🚫</span>
        <h3 className="text-lg font-semibold text-red-400">Gate Blocked</h3>
      </div>
      <div className="card-body space-y-2 mb-4">
        <div className="text-sm text-gray-300">
          <span className="text-gray-500">Phase:</span> {phase_label}
        </div>
        <div className="text-sm text-gray-300">
          <span className="text-gray-500">Score:</span> {payload.gate_score || "—"}
        </div>
        {payload.error_message && (
          <div className="text-sm text-red-300 bg-red-950/50 p-2 rounded mt-2">
            {String(payload.error_message)}
          </div>
        )}
      </div>

      <div className="card-actions flex gap-2">
        <button
          onClick={() => handleDecision("retry")}
          disabled={loading !== null}
          className="flex-1 px-3 py-2 bg-blue-600 hover:bg-blue-700 disabled:bg-gray-600 disabled:cursor-not-allowed text-white text-sm font-medium rounded transition-colors"
        >
          {loading === "retry" ? "⏳ Sending..." : "🔄 Retry"}
        </button>
        <button
          onClick={() => handleDecision("fix")}
          disabled={loading !== null}
          className="flex-1 px-3 py-2 bg-yellow-600 hover:bg-yellow-700 disabled:bg-gray-600 disabled:cursor-not-allowed text-white text-sm font-medium rounded transition-colors"
        >
          {loading === "fix" ? "⏳ Sending..." : "🔧 Fix"}
        </button>
        <button
          onClick={() => handleDecision("override")}
          disabled={loading !== null}
          className="flex-1 px-3 py-2 bg-orange-600 hover:bg-orange-700 disabled:bg-gray-600 disabled:cursor-not-allowed text-white text-sm font-medium rounded transition-colors"
        >
          {loading === "override" ? "⏳ Sending..." : "⚡ Override"}
        </button>
      </div>
    </div>
  );
}
