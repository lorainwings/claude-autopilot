/**
 * OrchestrationPanel — v5.9 编排驾驶舱 (orchestration-first)
 * 主窗口核心面板：目标、phase、gate、agent、模型、恢复、归档、上下文预算
 * 替代旧版 telemetry-first 布局，成为主信息视图
 */

import { memo, useMemo } from "react";
import { useStore, selectGateStats } from "../store";
import type {
  DecisionLifecycle,
  ModelRoutingState,
  ServerHealth,
  AgentInfo,
  OrchestrationOverview,
  RecoverySource,
} from "../store";

const PHASE_LABELS: Record<number, string> = {
  0: "环境初始化",
  1: "需求理解",
  2: "OpenSpec 创建",
  3: "快速生成",
  4: "测试设计",
  5: "代码实施",
  6: "测试报告",
  7: "归档清理",
};

// --- 决策状态颜色 ---
const STATE_COLORS: Record<string, string> = {
  idle: "text-text-muted",
  pending: "text-amber",
  accepted: "text-cyan",
  applied: "text-emerald",
  superseded: "text-text-muted",
  expired: "text-rose",
};

// --- 模型状态标记 ---
const MODEL_STATUS_BADGE: Record<string, { label: string; color: string }> = {
  requested: { label: "已请求", color: "text-amber" },
  effective: { label: "已确认", color: "text-emerald" },
  fallback: { label: "已降级", color: "text-rose" },
  unknown: { label: "未知", color: "text-text-muted" },
  unsupported: { label: "不支持", color: "text-rose" },
};

// --- 小型信息行组件 ---
function InfoRow({
  label,
  value,
  valueColor,
}: {
  label: string;
  value: string;
  valueColor?: string;
}) {
  return (
    <div className="flex justify-between items-center gap-2 text-[11px] font-mono">
      <span className="text-text-muted shrink-0">{label}</span>
      <span className={`truncate ${valueColor || "text-text-bright"}`}>
        {value}
      </span>
    </div>
  );
}

// --- 区段标题 ---
function SectionHeader({
  title,
  dotColor,
}: {
  title: string;
  dotColor?: string;
}) {
  return (
    <div className="flex items-center gap-2 mb-2">
      <span
        className={`w-1.5 h-1.5 rounded-full ${dotColor || "bg-cyan"}`}
      ></span>
      <span className="font-display text-[10px] font-bold text-text-bright uppercase tracking-wider">
        {title}
      </span>
    </div>
  );
}

// --- 目标与 Phase 核心区 ---
const GoalPhaseSection = memo(function GoalPhaseSection({
  orchestration,
  currentPhase,
  mode,
  changeName,
}: {
  orchestration: OrchestrationOverview;
  currentPhase: number | null;
  mode: string | null;
  changeName: string | null;
}) {
  const phaseLabel =
    currentPhase !== null ? PHASE_LABELS[currentPhase] || "" : "";

  return (
    <div className="px-3 py-3 border-b border-border space-y-2">
      <SectionHeader title="当前目标" dotColor="bg-cyan" />
      <div className="text-[12px] font-mono text-text-bright font-bold leading-snug">
        {orchestration.goalSummary || changeName || "等待启动..."}
      </div>
      <div className="flex items-center gap-3 text-[10px] font-mono">
        {currentPhase !== null ? (
          <span className="px-2 py-0.5 bg-cyan/15 text-cyan border border-cyan/30 rounded font-bold">
            P{currentPhase} {phaseLabel}
          </span>
        ) : (
          <span className="text-text-muted">Phase: --</span>
        )}
        {mode && (
          <span className="px-1.5 py-0.5 border border-border text-text-muted rounded text-[9px] uppercase">
            {mode === "full" ? "全模式" : mode === "lite" ? "精简" : "最小"}
          </span>
        )}
      </div>
      {orchestration.currentSubStep && (
        <div className="text-[10px] font-mono text-text-muted">
          Sub-step: {orchestration.currentSubStep}
        </div>
      )}
    </div>
  );
});

// --- Gate 状态区 ---
const GateSection = memo(function GateSection({
  gateStats,
  gateFrontierReason,
}: {
  gateStats: { passed: number; blocked: number; pending: number };
  gateFrontierReason: string | null;
}) {
  const hasBlock = gateFrontierReason !== null;

  return (
    <div className="px-3 py-2 border-b border-border space-y-1">
      <SectionHeader
        title="Gate 状态"
        dotColor={hasBlock ? "bg-rose" : "bg-emerald"}
      />
      {hasBlock ? (
        <div className="space-y-1">
          <div className="flex items-center gap-2">
            <span className="text-[10px] font-bold text-rose uppercase">
              BLOCKED
            </span>
          </div>
          <div className="text-[10px] font-mono text-rose/80 leading-snug line-clamp-2">
            {gateFrontierReason}
          </div>
        </div>
      ) : (
        <div className="flex items-center gap-3 text-[10px] font-mono">
          <span className="text-emerald">
            {gateStats.passed} 通过
          </span>
          {gateStats.blocked > 0 && (
            <span className="text-rose">{gateStats.blocked} 阻断</span>
          )}
          {gateStats.pending > 0 && (
            <span className="text-text-muted">
              {gateStats.pending} 待定
            </span>
          )}
        </div>
      )}
    </div>
  );
});

// --- Agent 概览区 ---
const AgentSection = memo(function AgentSection({
  agentMap,
}: {
  agentMap: Map<string, AgentInfo>;
}) {
  const agents = useMemo(() => Array.from(agentMap.values()), [agentMap]);
  const activeAgents = agents.filter((a) => a.status === "dispatched");
  const completedAgents = agents.filter(
    (a) => a.status === "ok" || a.status === "warning"
  );
  const failedAgents = agents.filter(
    (a) => a.status === "failed" || a.status === "blocked"
  );

  if (agents.length === 0) {
    return (
      <div className="px-3 py-2 border-b border-border">
        <SectionHeader title="Agent" dotColor="bg-violet" />
        <div className="text-[10px] font-mono text-text-muted">
          暂无 Agent 调度
        </div>
      </div>
    );
  }

  return (
    <div className="px-3 py-2 border-b border-border space-y-1.5">
      <SectionHeader title="Agent" dotColor="bg-violet" />
      <div className="flex gap-3 text-[10px] font-mono">
        {activeAgents.length > 0 && (
          <span className="text-violet animate-pulse">
            {activeAgents.length} 运行中
          </span>
        )}
        {completedAgents.length > 0 && (
          <span className="text-emerald">
            {completedAgents.length} 完成
          </span>
        )}
        {failedAgents.length > 0 && (
          <span className="text-rose">{failedAgents.length} 失败</span>
        )}
      </div>
      {/* 活跃 agent 列表 */}
      {activeAgents.length > 0 && (
        <div className="space-y-1">
          {activeAgents.slice(0, 3).map((a) => (
            <div
              key={a.agent_id}
              className="flex items-center gap-2 text-[9px] font-mono"
            >
              <span className="w-1.5 h-1.5 rounded-full bg-violet animate-pulse"></span>
              <span className="text-text-bright truncate">
                {a.agent_label}
              </span>
              <span className="text-text-muted">P{a.phase}</span>
            </div>
          ))}
          {activeAgents.length > 3 && (
            <div className="text-[9px] text-text-muted font-mono">
              ...+{activeAgents.length - 3} 更多
            </div>
          )}
        </div>
      )}
    </div>
  );
});

// --- 模型路由区 ---
const ModelSection = memo(function ModelSection({
  routing,
}: {
  routing: ModelRoutingState;
}) {
  const badge = MODEL_STATUS_BADGE[routing.model_status] ??
    MODEL_STATUS_BADGE.unknown!;
  const hasData = routing.updated_at !== null;

  if (!hasData) {
    return (
      <div className="px-3 py-2 border-b border-border">
        <SectionHeader title="模型路由" dotColor="bg-amber" />
        <div className="text-[10px] font-mono text-text-muted">
          暂无路由事件
        </div>
      </div>
    );
  }

  return (
    <div className="px-3 py-2 border-b border-border space-y-1">
      <div className="flex items-center justify-between">
        <SectionHeader title="模型路由" dotColor="bg-amber" />
        <span className={`text-[9px] font-mono font-bold ${badge.color}`}>
          {badge.label}
        </span>
      </div>
      <InfoRow
        label="请求"
        value={`${routing.requested_model ?? "--"} (${routing.requested_tier ?? "--"})`}
        valueColor="text-amber"
      />
      <InfoRow
        label="实际"
        value={
          routing.effective_model ?? routing.fallback_model ?? "unknown"
        }
        valueColor={
          routing.model_status === "fallback"
            ? "text-rose"
            : routing.model_status === "effective"
              ? "text-emerald"
              : "text-text-muted"
        }
      />
      {routing.fallback_applied && routing.fallback_reason && (
        <div className="text-[9px] font-mono text-rose/80 truncate">
          降级: {routing.fallback_reason}
        </div>
      )}
      {routing.capability_note && (
        <div className="text-[9px] font-mono text-amber/80 leading-snug">
          {routing.capability_note}
        </div>
      )}
    </div>
  );
});

// --- 恢复状态区 (v7.0 — 结构化恢复来源) ---
const RECOVERY_LABELS: Record<string, { label: string; color: string }> = {
  fresh: { label: "全新启动", color: "text-emerald" },
  snapshot_resume: { label: "快照恢复", color: "text-cyan" },
  checkpoint_resume: { label: "检查点恢复", color: "text-amber" },
  progress_resume: { label: "进度恢复", color: "text-amber" },
  snapshot_hash_mismatch: { label: "快照哈希不匹配", color: "text-rose" },
};

const RecoverySection = memo(function RecoverySection({
  recoverySource,
  recoveryReason,
}: {
  recoverySource: RecoverySource | null;
  recoveryReason?: string | null;
}) {
  const info = recoverySource ? RECOVERY_LABELS[recoverySource] : null;

  return (
    <div className="px-3 py-2 border-b border-border">
      <SectionHeader title="恢复状态" dotColor="bg-cyan" />
      <div className="text-[10px] font-mono">
        {info ? (
          <span className={`font-bold ${info.color}`}>{info.label}</span>
        ) : (
          <span className="text-text-muted">--</span>
        )}
      </div>
      {recoveryReason && (
        <div className="text-[9px] font-mono text-text-muted mt-0.5 truncate">
          {recoveryReason}
        </div>
      )}
    </div>
  );
});

// --- 上下文预算 ---
const ContextBudgetSection = memo(function ContextBudgetSection({
  budget,
}: {
  budget: OrchestrationOverview["contextBudget"];
}) {
  if (!budget) return null;

  const riskColor =
    budget.risk === "high"
      ? "text-rose"
      : budget.risk === "medium"
        ? "text-amber"
        : "text-emerald";
  const barColor =
    budget.risk === "high"
      ? "bg-rose"
      : budget.risk === "medium"
        ? "bg-amber"
        : "bg-cyan";

  return (
    <div className="px-3 py-2 border-b border-border space-y-1">
      <SectionHeader title="上下文预算" dotColor="bg-violet" />
      <div className="flex items-center gap-2">
        <div className="flex-1 h-1.5 bg-border rounded-full overflow-hidden">
          <div
            className={`h-full ${barColor} transition-all duration-500`}
            style={{ width: `${Math.min(budget.percent, 100)}%` }}
          ></div>
        </div>
        <span className={`text-[10px] font-mono font-bold ${riskColor}`}>
          {budget.percent}%
        </span>
      </div>
    </div>
  );
});

// --- 归档准备 ---
const ArchiveSection = memo(function ArchiveSection({
  archiveReadiness,
}: {
  archiveReadiness: OrchestrationOverview["archiveReadiness"];
}) {
  if (!archiveReadiness) return null;

  return (
    <div className="px-3 py-2 border-b border-border space-y-1">
      <SectionHeader title="归档状态" dotColor="bg-cyan" />
      <div className="space-y-0.5 text-[10px] font-mono">
        <div className="flex items-center gap-2">
          <span
            className={`w-1.5 h-1.5 rounded-full ${archiveReadiness.fixupComplete ? "bg-emerald" : "bg-text-muted"}`}
          ></span>
          <span
            className={
              archiveReadiness.fixupComplete
                ? "text-emerald"
                : "text-text-muted"
            }
          >
            Fixup {archiveReadiness.fixupComplete ? "完成" : "未完成"}
          </span>
        </div>
        <div className="flex items-center gap-2">
          <span
            className={`w-1.5 h-1.5 rounded-full ${archiveReadiness.reviewGatePassed ? "bg-emerald" : "bg-text-muted"}`}
          ></span>
          <span
            className={
              archiveReadiness.reviewGatePassed
                ? "text-emerald"
                : "text-text-muted"
            }
          >
            Review Gate{" "}
            {archiveReadiness.reviewGatePassed ? "通过" : "未通过"}
          </span>
        </div>
        <div className="flex items-center gap-2">
          <span
            className={`w-1.5 h-1.5 rounded-full ${archiveReadiness.ready ? "bg-emerald" : "bg-amber"}`}
          ></span>
          <span
            className={`font-bold ${archiveReadiness.ready ? "text-emerald" : "text-amber"}`}
          >
            {archiveReadiness.ready ? "可归档" : "未就绪"}
          </span>
        </div>
      </div>
    </div>
  );
});

// --- 服务健康区 ---
const HealthSection = memo(function HealthSection({
  health,
}: {
  health: ServerHealth;
}) {
  const items: { key: keyof ServerHealth; label: string }[] = [
    { key: "httpOk", label: "HTTP" },
    { key: "wsConnected", label: "WS" },
    { key: "telemetryAvailable", label: "Telemetry" },
    { key: "transcriptAvailable", label: "Transcript" },
    { key: "statusLineInstalled", label: "StatusLine" },
  ];

  return (
    <div className="px-3 py-2 border-b border-border">
      <SectionHeader title="服务健康" dotColor="bg-emerald" />
      <div className="flex flex-wrap gap-x-3 gap-y-0.5">
        {items.map(({ key, label }) => (
          <div
            key={key}
            className="flex items-center gap-1 text-[9px] font-mono"
          >
            <span
              className={`w-1.5 h-1.5 rounded-full ${health[key] ? "bg-emerald" : "bg-text-muted"}`}
            ></span>
            <span
              className={health[key] ? "text-emerald" : "text-text-muted"}
            >
              {label}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
});

// --- 决策状态区 ---
const DecisionSection = memo(function DecisionSection({
  lifecycle,
}: {
  lifecycle: DecisionLifecycle | null;
}) {
  if (!lifecycle) return null;

  const color = STATE_COLORS[lifecycle.state] || "text-text-muted";

  return (
    <div className="px-3 py-2 border-b border-border">
      <SectionHeader title="决策状态" dotColor="bg-amber" />
      <div className="flex items-center gap-2 text-[10px] font-mono">
        <span className={`font-bold ${color}`}>
          {lifecycle.state.toUpperCase()}
        </span>
        <span className="text-text-muted">({lifecycle.action})</span>
        <span className="text-text-muted/60">P{lifecycle.phase}</span>
      </div>
    </div>
  );
});

// --- 主面板 ---
export const OrchestrationPanel = memo(function OrchestrationPanel() {
  const changeName = useStore((s) => s.changeName);
  const currentPhase = useStore((s) => s.currentPhase);
  const mode = useStore((s) => s.mode);
  const events = useStore((s) => s.events);
  const decisionLifecycle = useStore((s) => s.decisionLifecycle);
  const recoverySource = useStore((s) => s.recoverySource);
  const agentMap = useStore((s) => s.agentMap);
  const modelRouting = useStore((s) => s.modelRouting);
  const serverHealth = useStore((s) => s.serverHealth);
  const orchestration = useStore((s) => s.orchestration);

  const gateStats = useMemo(() => selectGateStats(events), [events]);

  return (
    <div className="flex flex-col h-full bg-abyss overflow-y-auto">
      {/* 目标 + Phase */}
      <GoalPhaseSection
        orchestration={orchestration}
        currentPhase={currentPhase}
        mode={mode}
        changeName={changeName}
      />

      {/* Gate 状态 */}
      <GateSection
        gateStats={gateStats}
        gateFrontierReason={orchestration.gateFrontierReason}
      />

      {/* Agent 概览 */}
      <AgentSection agentMap={agentMap} />

      {/* 模型路由 */}
      <ModelSection routing={modelRouting} />

      {/* 恢复来源 */}
      <RecoverySection
        recoverySource={orchestration.recoverySource ?? recoverySource}
        recoveryReason={orchestration.recoveryReason}
      />

      {/* 上下文预算 */}
      <ContextBudgetSection budget={orchestration.contextBudget} />

      {/* 归档准备 */}
      <ArchiveSection archiveReadiness={orchestration.archiveReadiness} />

      {/* 服务健康 */}
      <HealthSection health={serverHealth} />

      {/* 决策状态 */}
      <DecisionSection lifecycle={decisionLifecycle} />

      {/* Requirement Packet Hash */}
      {orchestration.requirementPacketHash && (
        <div className="px-3 py-2 border-b border-border">
          <SectionHeader title="需求包" dotColor="bg-cyan" />
          <div className="text-[9px] font-mono text-text-muted truncate">
            {orchestration.requirementPacketHash}
          </div>
        </div>
      )}

      {/* v7.1: 需求清晰度 */}
      {orchestration.clarityScore != null && (
        <div className="px-3 py-2 border-b border-border">
          <SectionHeader title="需求清晰度" dotColor="bg-emerald" />
          <div className="flex items-center gap-2 mt-1">
            <div className="flex-1 h-1.5 bg-surface-hover rounded-full overflow-hidden">
              <div
                className="h-full bg-emerald rounded-full transition-all"
                style={{ width: `${Math.round(orchestration.clarityScore * 100)}%` }}
              />
            </div>
            <span className="text-[9px] font-mono text-text-muted">
              {Math.round(orchestration.clarityScore * 100)}%
            </span>
          </div>
          {orchestration.discussionRounds != null && (
            <div className="text-[9px] text-text-muted mt-0.5">
              {orchestration.discussionRounds} 轮讨论
              {orchestration.challengeAgentsActivated && orchestration.challengeAgentsActivated.length > 0 && (
                <span className="ml-1">
                  · 挑战: {orchestration.challengeAgentsActivated.join(', ')}
                </span>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
});
