/**
 * OrchestrationPanel — v5.2 编排控制面
 * 修复 Codex P1-6: 主窗口改为 orchestration-first
 * 显示: change/session/mode、当前 phase/sub-step、阻塞 gate、决策状态机、恢复来源
 */

import { memo, useMemo } from "react";
import { useStore, selectGateStats } from "../store";
import type { DecisionLifecycle } from "../store";

const PHASE_LABELS: Record<number, string> = {
  0: "环境初始化", 1: "需求理解", 2: "OpenSpec 创建", 3: "快速生成",
  4: "测试设计", 5: "代码实施", 6: "测试报告", 7: "归档清理",
};

const STATE_COLORS: Record<string, string> = {
  idle: "#6b7280",
  pending: "#f59e0b",
  accepted: "#3b82f6",
  applied: "#10b981",
  superseded: "#6b7280",
  expired: "#ef4444",
};

function DecisionBadge({ lifecycle }: { lifecycle: DecisionLifecycle | null }) {
  if (!lifecycle) {
    return <span style={{ color: "#6b7280", fontSize: 12 }}>无待处理决策</span>;
  }
  const color = STATE_COLORS[lifecycle.state] || "#6b7280";
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
        <span style={{ width: 8, height: 8, borderRadius: "50%", background: color, display: "inline-block" }} />
        <span style={{ color, fontWeight: 600, fontSize: 13 }}>{lifecycle.state.toUpperCase()}</span>
        <span style={{ color: "#9ca3af", fontSize: 11 }}>({lifecycle.action})</span>
      </div>
      <span style={{ color: "#9ca3af", fontSize: 11, fontFamily: "monospace" }}>
        rid: {lifecycle.requestId.slice(0, 8)}… | Phase {lifecycle.phase}
      </span>
    </div>
  );
}

export const OrchestrationPanel = memo(function OrchestrationPanel() {
  const changeName = useStore((s) => s.changeName);
  const sessionId = useStore((s) => s.sessionId);
  const mode = useStore((s) => s.mode);
  const currentPhase = useStore((s) => s.currentPhase);
  const events = useStore((s) => s.events);
  const decisionLifecycle = useStore((s) => s.decisionLifecycle);
  const recoverySource = useStore((s) => s.recoverySource);
  const agentMap = useStore((s) => s.agentMap);
  const taskProgress = useStore((s) => s.taskProgress);

  const gateStats = useMemo(() => selectGateStats(events), [events]);

  // 当前活跃 agent 数量
  const activeAgents = useMemo(() => {
    let count = 0;
    agentMap.forEach((a) => { if (a.status === "dispatched") count++; });
    return count;
  }, [agentMap]);

  // 当前运行中任务
  const runningTasks = useMemo(() => {
    let count = 0;
    taskProgress.forEach((t) => { if (t.status === "running") count++; });
    return count;
  }, [taskProgress]);

  // 活跃 gate_block 事件
  const activeBlock = useMemo(() => {
    const blocks = events.filter((e) => e.type === "gate_block");
    return blocks.length > 0 ? blocks[blocks.length - 1] : null;
  }, [events]);

  const sectionStyle: React.CSSProperties = {
    padding: "8px 12px",
    borderBottom: "1px solid #2d2d2d",
  };
  const labelStyle: React.CSSProperties = {
    color: "#9ca3af", fontSize: 11, textTransform: "uppercase" as const, letterSpacing: "0.05em", marginBottom: 4,
  };
  const valueStyle: React.CSSProperties = {
    color: "#e5e7eb", fontSize: 13, fontFamily: "monospace",
  };

  return (
    <div style={{
      display: "flex", flexDirection: "column",
      background: "#1a1a1a", borderRight: "1px solid #2d2d2d",
      height: "100%", overflow: "auto",
      minWidth: 220,
    }}>
      {/* 标题 */}
      <div style={{ padding: "10px 12px", borderBottom: "1px solid #2d2d2d", fontWeight: 700, fontSize: 13, color: "#e5e7eb" }}>
        编排控制台
      </div>

      {/* Change / Session / Mode */}
      <div style={sectionStyle}>
        <div style={labelStyle}>Change</div>
        <div style={valueStyle}>{changeName || "—"}</div>
        <div style={{ ...labelStyle, marginTop: 6 }}>Session</div>
        <div style={valueStyle}>{sessionId ? sessionId.slice(0, 12) + "…" : "—"}</div>
        <div style={{ ...labelStyle, marginTop: 6 }}>Mode</div>
        <div style={valueStyle}>{mode || "—"}</div>
      </div>

      {/* 当前 Phase */}
      <div style={sectionStyle}>
        <div style={labelStyle}>当前 Phase</div>
        <div style={{ ...valueStyle, fontSize: 16, fontWeight: 700 }}>
          {currentPhase !== null ? `P${currentPhase} — ${PHASE_LABELS[currentPhase] || ""}` : "未启动"}
        </div>
      </div>

      {/* 阻塞 Gate */}
      <div style={sectionStyle}>
        <div style={labelStyle}>Gate 状态</div>
        {activeBlock ? (
          <div style={{ color: "#ef4444", fontSize: 12 }}>
            <div style={{ fontWeight: 600 }}>BLOCKED</div>
            <div style={{ color: "#f87171", fontSize: 11, marginTop: 2 }}>
              {String((activeBlock.payload as Record<string, unknown>)?.reason || "").slice(0, 80)}
            </div>
          </div>
        ) : (
          <div style={{ color: "#10b981", fontSize: 12 }}>
            通过 {gateStats.passed} / 阻断 {gateStats.blocked}
          </div>
        )}
      </div>

      {/* 决策状态机 */}
      <div style={sectionStyle}>
        <div style={labelStyle}>决策状态</div>
        <DecisionBadge lifecycle={decisionLifecycle} />
      </div>

      {/* Agent / 任务 */}
      <div style={sectionStyle}>
        <div style={labelStyle}>活跃 Agent</div>
        <div style={valueStyle}>{activeAgents} 个运行中</div>
        <div style={{ ...labelStyle, marginTop: 6 }}>任务进度</div>
        <div style={valueStyle}>{runningTasks} 个运行中</div>
      </div>

      {/* 恢复来源 */}
      <div style={sectionStyle}>
        <div style={labelStyle}>恢复来源</div>
        <div style={valueStyle}>
          {recoverySource === "recovery" ? "崩溃恢复" : recoverySource === "fresh" ? "全新启动" : "—"}
        </div>
      </div>
    </div>
  );
});
