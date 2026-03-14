/**
 * GateBlockCard — V2 赛博朋克门禁阻断弹窗
 * 重中之重：Retry/Fix/Override 按钮精准绑定 ws-bridge 决策发送接口
 * 新增 fix_instructions 输入框
 * 数据源: Zustand Store (events, decisionAcked)
 */

import { useState } from "react";
import { useStore } from "../store";
import { AlertTriangle, RotateCcw, Wrench, Zap } from "lucide-react";

interface GateBlockCardProps {
  onDecision?: (action: "retry" | "fix" | "override", phase: number, reason?: string) => void;
}

export function GateBlockCard({ onDecision }: GateBlockCardProps) {
  const { events, decisionAcked } = useStore();
  const [loading, setLoading] = useState<string | null>(null);
  const [fixInstructions, setFixInstructions] = useState("");

  const blockEvents = events.filter((e) => e.type === "gate_block");
  if (blockEvents.length === 0) return null;

  const latest = blockEvents[blockEvents.length - 1]!;

  // G1 fix: Check if this block has been resolved by a subsequent gate_pass on the same phase
  const passEvents = events.filter((e) => e.type === "gate_pass" && e.phase === latest.phase);
  const latestPass = passEvents.length > 0 ? passEvents[passEvents.length - 1]! : null;
  if (latestPass && latestPass.sequence > latest.sequence) return null;

  // v5.2: Decision ACK received — hide the card immediately
  if (decisionAcked) return null;
  const { phase, phase_label, payload } = latest;

  const handleDecision = async (action: "retry" | "fix" | "override") => {
    setLoading(action);
    try {
      const reason = action === "fix" && fixInstructions.trim()
        ? fixInstructions.trim()
        : undefined;
      await onDecision?.(action, phase, reason);
      setLoading(null);
    } catch (error) {
      console.error("Decision failed:", error);
      setLoading(null);
    }
  };

  return (
    <div className="bg-deep border border-rose/50 rounded-lg overflow-hidden shadow-[0_0_30px_rgba(244,63,94,0.3)] animate-pulse-soft">
      {/* Header */}
      <div className="bg-gradient-to-r from-rose/20 to-rose/5 px-4 py-3 border-b border-rose/30 flex items-center space-x-3">
        <AlertTriangle className="w-5 h-5 text-rose" />
        <div>
          <h3 className="font-display text-[10px] font-bold text-rose uppercase tracking-widest">门禁阻断</h3>
          <div className="text-[10px] font-mono text-text-muted mt-0.5">
            阶段 {phase} &mdash; {phase_label}
          </div>
        </div>
        <div className="ml-auto">
          <span className="text-xs font-mono font-bold text-rose">
            {String(payload.gate_score ?? "--")}/8
          </span>
        </div>
      </div>

      {/* Body */}
      <div className="p-4 space-y-3">
        {typeof payload.error_message === "string" && (
          <div className="text-[11px] text-rose/80 bg-rose/5 border-l-2 border-rose/40 p-2 font-mono leading-relaxed">
            {payload.error_message}
          </div>
        )}

        {/* Fix Instructions Input */}
        <div className="space-y-1">
          <label className="text-[9px] text-text-muted uppercase font-display tracking-wider">修复指令 (可选)</label>
          <textarea
            value={fixInstructions}
            onChange={(e) => setFixInstructions(e.target.value)}
            placeholder="输入修复指令，将发送给底层引擎..."
            className="w-full bg-void border border-border text-[11px] text-text-bright font-mono p-2 rounded resize-none h-16 focus:border-cyan focus:outline-none placeholder:text-text-muted/50"
          />
        </div>

        {/* Action Buttons */}
        <div className="grid grid-cols-3 gap-2">
          <button
            onClick={() => handleDecision("retry")}
            disabled={loading !== null}
            className="flex items-center justify-center space-x-1.5 px-3 py-2 bg-cyan/10 border border-cyan/30 text-cyan text-[10px] font-bold uppercase tracking-wider rounded hover:bg-cyan/20 disabled:opacity-40 disabled:cursor-not-allowed transition-all"
          >
            <RotateCcw className="w-3 h-3" />
            <span>{loading === "retry" ? "..." : "重试"}</span>
          </button>
          <button
            onClick={() => handleDecision("fix")}
            disabled={loading !== null}
            className="flex items-center justify-center space-x-1.5 px-3 py-2 bg-amber/10 border border-amber/30 text-amber text-[10px] font-bold uppercase tracking-wider rounded hover:bg-amber/20 disabled:opacity-40 disabled:cursor-not-allowed transition-all"
          >
            <Wrench className="w-3 h-3" />
            <span>{loading === "fix" ? "..." : "修复"}</span>
          </button>
          <button
            onClick={() => handleDecision("override")}
            disabled={loading !== null}
            className="flex items-center justify-center space-x-1.5 px-3 py-2 bg-rose/10 border border-rose/30 text-rose text-[10px] font-bold uppercase tracking-wider rounded hover:bg-rose/20 disabled:opacity-40 disabled:cursor-not-allowed transition-all"
          >
            <Zap className="w-3 h-3" />
            <span>{loading === "override" ? "..." : "强制"}</span>
          </button>
        </div>
      </div>
    </div>
  );
}
