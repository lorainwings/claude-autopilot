/**
 * TelemetryDashboard — V2 右侧遥测面板
 * 会话指标(SVG环形图)、阶段耗时条、门禁统计
 * 数据源: Zustand Store (events) → derived selectors
 */

import { useState, useEffect, useMemo, memo } from "react";
import { useStore, selectPhaseDurations, selectTotalElapsedMs, selectGateStats, selectActivePhaseIndices } from "../store";
import type { ModelRoutingState, ServerHealth, ParallelPlanSummary } from "../store";

function formatDuration(ms: number): string {
  const totalSec = Math.floor(ms / 1000);
  const min = Math.floor(totalSec / 60);
  const sec = totalSec % 60;
  const hours = Math.floor(min / 60);
  const remainMin = min % 60;
  return `${String(hours).padStart(2, "0")}:${String(remainMin).padStart(2, "0")}:${String(sec).padStart(2, "0")}`;
}

function formatShortDuration(ms: number): string {
  const totalSec = Math.floor(ms / 1000);
  const min = Math.floor(totalSec / 60);
  const sec = totalSec % 60;
  if (min === 0 && sec === 0) return "--:--";
  return `${min}:${String(sec).padStart(2, "0")}`;
}

export const TelemetryDashboard = memo(function TelemetryDashboard() {
  const events = useStore((s) => s.events);
  const latestStatus = useStore((s) => s.latestStatus);
  const modelRouting = useStore((s) => s.modelRouting);
  const modelRoutingHistory = useStore((s) => s.modelRoutingHistory);
  const serverHealth = useStore((s) => s.serverHealth);
  const parallelPlan = useStore((s) => s.parallelPlan);

  // G9: Force re-render every second when a phase is running
  // tick is included in useMemo deps so Date.now()-based selectors recompute
  const [tick, setTick] = useState(0);

  const phaseDurations = useMemo(() => selectPhaseDurations(events), [events, tick]);
  const totalElapsedMs = useMemo(() => selectTotalElapsedMs(events), [events, tick]);
  const gateStats = useMemo(() => selectGateStats(events), [events]);

  const hasRunning = phaseDurations.some((p) => p.status === "running");
  useEffect(() => {
    if (!hasRunning) return;
    const timer = setInterval(() => setTick((t) => t + 1), 1000);
    return () => clearInterval(timer);
  }, [hasRunning]);

  const activePhaseIndices = useMemo(() => selectActivePhaseIndices(events), [events]);
  const totalPhaseCount = activePhaseIndices.length;
  const completedPhases = phaseDurations.filter(
    (p) => p.status === "ok" || p.status === "warning"
  ).length;
  const totalRetries = useMemo(
    () => events.filter(
      (e) => e.type === "task_progress" && (e.payload as Record<string, unknown>).status === "retrying"
    ).length,
    [events]
  );

  // SVG ring chart computation
  const circumference = 2 * Math.PI * 58; // r=58
  const completionRatio = totalPhaseCount > 0 ? completedPhases / totalPhaseCount : 0;
  const strokeDashoffset = circumference * (1 - completionRatio);

  // Max duration for bar chart scaling
  const maxDuration = Math.max(...phaseDurations.map((p) => p.durationMs), 1);

  return (
    <aside className="w-[360px] bg-abyss border-l border-border flex flex-col p-4 space-y-4 overflow-y-auto shrink-0">
      {/* Card 0: Runtime Telemetry */}
      <section className="bg-deep border border-border p-4 rounded-lg">
        <h3 className="font-display text-[10px] font-bold text-text-bright uppercase mb-4 flex items-center">
          <span className="w-2 h-2 rounded-full bg-cyan mr-2"></span> 运行遥测
        </h3>
        {latestStatus ? (
          <div className="space-y-2 text-[11px] font-mono">
            <div className="flex justify-between gap-3">
              <span className="text-text-muted shrink-0">模型</span>
              <span className="text-text-bright truncate">{latestStatus.model || "--"}</span>
            </div>
            <div className="flex justify-between gap-3">
              <span className="text-text-muted shrink-0">目录</span>
              <span className="text-text-bright truncate">{latestStatus.cwd || "--"}</span>
            </div>
            <div className="flex justify-between gap-3">
              <span className="text-text-muted shrink-0">成本</span>
              <span className="text-text-bright truncate">{latestStatus.cost || "--"}</span>
            </div>
            <div className="flex justify-between gap-3">
              <span className="text-text-muted shrink-0">Worktree</span>
              <span className="text-text-bright truncate">{latestStatus.worktree || "--"}</span>
            </div>
            <div className="text-text-muted">Transcript</div>
            <div className="text-text-bright break-all text-[10px]">{latestStatus.transcript_path || "--"}</div>
          </div>
        ) : (
          <div className="space-y-2">
            <div className="text-[11px] font-mono text-text-muted">未接入 statusLine 或当前会话暂无遥测</div>
            <div className="mt-2 px-2 py-1.5 bg-surface border border-amber/30 rounded text-[10px] text-amber font-mono">
              <div className="font-bold mb-1">安装 statusLine Hook:</div>
              <code className="text-[9px] text-text-bright break-all">
                bash plugins/spec-autopilot/runtime/scripts/install-statusline-config.sh
              </code>
            </div>
          </div>
        )}
        {/* 服务状态指示区域 (v5.4) */}
        <ServerHealthBar health={serverHealth} />
      </section>

      {/* Card 0.5: Model Routing — v5.4 可观测性闭环 */}
      <ModelRoutingCard routing={modelRouting} history={modelRoutingHistory} />

      {/* Card 1: Session Metrics */}
      <section className="bg-deep border border-border p-4 rounded-lg">
        <h3 className="font-display text-[10px] font-bold text-text-bright uppercase mb-4 flex items-center">
          <span className="w-2 h-2 rounded-full bg-cyan mr-2"></span> 会话指标
        </h3>
        <div className="flex justify-center mb-4 relative">
          {/* Circular Ring Chart (SVG) */}
          <svg className="w-32 h-32 transform -rotate-90">
            <circle cx="64" cy="64" fill="transparent" r="58" style={{ stroke: "var(--color-surface)" }} strokeWidth="8"></circle>
            <circle
              cx="64" cy="64" fill="transparent" r="58"
              style={{ stroke: "var(--color-cyan)" }} strokeWidth="8"
              strokeDasharray={circumference}
              strokeDashoffset={strokeDashoffset}
              strokeLinecap="round"
              className="transition-all duration-1000 ease-out"
            ></circle>
          </svg>
          <div className="absolute inset-0 flex flex-col items-center justify-center">
            <span className="font-mono text-xl font-bold text-white leading-none">{formatDuration(totalElapsedMs)}</span>
            <span className="text-[9px] text-text-muted uppercase font-bold mt-1">总耗时</span>
          </div>
        </div>
        <div className="grid grid-cols-2 gap-y-3 text-[11px] font-mono">
          <div className="text-text-muted">已完成阶段</div>
          <div className="text-right text-text-bright">{completedPhases} / {totalPhaseCount}</div>
          <div className="text-text-muted">总重试次数</div>
          <div className="text-right text-amber font-bold">{totalRetries}</div>
          <div className="text-text-muted">通过门禁</div>
          <div className="text-right text-emerald font-bold">{gateStats.passed}</div>
          <div className="text-text-muted">阻断门禁</div>
          <div className="text-right text-rose font-bold">{gateStats.blocked}</div>
        </div>
      </section>

      {/* Card 2: Phase Duration */}
      <section className="bg-deep border border-border p-4 rounded-lg">
        <h3 className="font-display text-[10px] font-bold text-text-bright uppercase mb-4 flex items-center">
          <span className="w-2 h-2 rounded-full bg-violet mr-2"></span> 阶段耗时
        </h3>
        <div className="space-y-2">
          {phaseDurations.map((p) => {
            const barWidth = p.durationMs > 0 ? Math.max((p.durationMs / maxDuration) * 100, 2) : 0;
            const isRunning = p.status === "running";
            const barColor = isRunning ? "bg-cyan shadow-[0_0_8px_rgba(0,217,255,0.4)]" : "bg-cyan";

            return (
              <div key={p.phase} className="flex items-center text-[10px] font-mono">
                <span className="w-6 text-text-muted">P{p.phase}</span>
                <div className="flex-1 h-2 bg-border mx-2 overflow-hidden rounded-full">
                  <div
                    className={`h-full ${barColor} transition-all duration-500`}
                    style={{ width: `${barWidth}%` }}
                  ></div>
                </div>
                <span className={isRunning ? "text-cyan font-bold" : "text-text-muted"}>
                  {formatShortDuration(p.durationMs)}
                </span>
              </div>
            );
          })}
        </div>
      </section>

      {/* Card 3: Gate Statistics */}
      <section className="bg-deep border border-border p-4 rounded-lg flex space-x-4">
        <div className="w-20 h-20 rounded-full border-4 border-emerald border-l-rose flex items-center justify-center shrink-0">
          <span className="text-[10px] font-bold text-text-bright">{gateStats.passRate}% 通过</span>
        </div>
        <div className="flex-1">
          <h3 className="font-display text-[10px] font-bold text-text-bright uppercase mb-2">门禁统计</h3>
          <div className="space-y-1 text-[11px] font-mono">
            <div className="flex justify-between items-center">
              <span className="text-emerald">通过</span>
              <span>{gateStats.passed}</span>
            </div>
            <div className="flex justify-between items-center">
              <span className="text-rose">阻断</span>
              <span>{gateStats.blocked}</span>
            </div>
            <div className="flex justify-between items-center">
              <span className="text-text-muted">待定</span>
              <span>{gateStats.pending}</span>
            </div>
          </div>
        </div>
      </section>

      {/* Card 4: Parallel Scheduling (v5.5) */}
      <ParallelSchedulingCard plan={parallelPlan} />
    </aside>
  );
});

// --- Server Health Bar (v5.4) ---

const HEALTH_ITEMS: { key: keyof ServerHealth; label: string }[] = [
  { key: "httpOk", label: "HTTP" },
  { key: "wsConnected", label: "WS" },
  { key: "telemetryAvailable", label: "Telemetry" },
  { key: "transcriptAvailable", label: "Transcript" },
  { key: "statusLineInstalled", label: "StatusLine" },
];

const ServerHealthBar = memo(function ServerHealthBar({ health }: { health: ServerHealth }) {
  return (
    <div className="mt-3 pt-3 border-t border-border">
      <div className="flex flex-wrap gap-x-3 gap-y-1">
        {HEALTH_ITEMS.map(({ key, label }) => (
          <div key={key} className="flex items-center gap-1 text-[10px] font-mono">
            <span className={`w-1.5 h-1.5 rounded-full ${health[key] ? "bg-emerald" : "bg-text-muted"}`}></span>
            <span className={health[key] ? "text-emerald" : "text-text-muted"}>{label}</span>
          </div>
        ))}
      </div>
    </div>
  );
});

// --- Model Routing Card (v5.4) ---

const STATUS_BADGE: Record<string, { label: string; color: string; dot: string }> = {
  requested: { label: "已请求", color: "text-amber", dot: "bg-amber" },
  effective: { label: "已确认", color: "text-emerald", dot: "bg-emerald" },
  fallback: { label: "已降级", color: "text-rose", dot: "bg-rose" },
  unknown: { label: "未知", color: "text-text-muted", dot: "bg-text-muted" },
  unsupported: { label: "不支持", color: "text-rose", dot: "bg-rose" },
};

const ModelRoutingCard = memo(function ModelRoutingCard({
  routing,
  history,
}: {
  routing: ModelRoutingState;
  history: ModelRoutingState[];
}) {
  const badge = STATUS_BADGE[routing.model_status] ?? STATUS_BADGE.unknown!;
  const hasData = routing.updated_at !== null;

  return (
    <section className="bg-deep border border-border p-4 rounded-lg">
      <h3 className="font-display text-[10px] font-bold text-text-bright uppercase mb-4 flex items-center justify-between">
        <span className="flex items-center">
          <span className="w-2 h-2 rounded-full bg-amber mr-2"></span> 模型路由
        </span>
        {hasData && (
          <span className={`flex items-center text-[9px] font-mono ${badge.color}`}>
            <span className={`w-1.5 h-1.5 rounded-full ${badge.dot} mr-1`}></span>
            {badge.label}
          </span>
        )}
      </h3>
      {hasData ? (
        <div className="space-y-2 text-[11px] font-mono">
          <div className="flex justify-between gap-3">
            <span className="text-text-muted shrink-0">请求模型</span>
            <span className="text-amber truncate">{routing.requested_model ?? "--"}</span>
          </div>
          <div className="flex justify-between gap-3">
            <span className="text-text-muted shrink-0">请求层级</span>
            <span className="text-text-bright truncate">{routing.requested_tier ?? "--"} / {routing.requested_effort ?? "--"}</span>
          </div>
          <div className="flex justify-between gap-3">
            <span className="text-text-muted shrink-0">实际模型</span>
            <span className={`truncate ${routing.model_status === "effective" ? "text-emerald" : routing.model_status === "fallback" ? "text-rose" : "text-text-muted"}`}>
              {routing.effective_model ?? routing.fallback_model ?? "unknown"}
            </span>
          </div>
          {routing.fallback_applied && (
            <div className="flex justify-between gap-3">
              <span className="text-text-muted shrink-0">降级模型</span>
              <span className="text-rose truncate">{routing.fallback_model ?? "--"}</span>
            </div>
          )}
          {routing.routing_reason && (
            <div className="mt-1">
              <span className="text-text-muted text-[10px]">路由理由</span>
              <div className="text-[10px] text-text-bright break-words mt-0.5">{routing.routing_reason}</div>
            </div>
          )}
          {routing.capability_note && (
            <div className="mt-1 px-2 py-1 bg-surface border border-amber/30 rounded text-[10px] text-amber">
              {routing.capability_note}
            </div>
          )}
          {routing.inference_source && (
            <div className="flex justify-between gap-3 text-[10px]">
              <span className="text-text-muted shrink-0">推断来源</span>
              <span className="text-text-bright">{routing.inference_source}</span>
            </div>
          )}
          <div className="flex justify-between gap-3 text-[10px]">
            <span className="text-text-muted shrink-0">Phase / Agent</span>
            <span className="text-text-bright">P{routing.phase}{routing.agent_id ? ` / ${routing.agent_id}` : ""}</span>
          </div>
          {/* 路由历史（折叠显示最近 5 条） */}
          {history.length > 1 && (
            <details className="mt-2">
              <summary className="text-[10px] text-text-muted cursor-pointer hover:text-cyan">路由历史 ({history.length})</summary>
              <div className="mt-1 space-y-1 max-h-32 overflow-y-auto">
                {history.slice(-5).reverse().map((h, i) => (
                  <div key={i} className="flex items-center gap-2 text-[10px]">
                    <span className={`w-1.5 h-1.5 rounded-full ${(STATUS_BADGE[h.model_status] ?? STATUS_BADGE.unknown!).dot}`}></span>
                    <span className="text-text-muted">P{h.phase}</span>
                    <span className="text-text-bright">{h.requested_model}</span>
                    <span className="text-text-muted">→</span>
                    <span className={h.model_status === "fallback" ? "text-rose" : "text-emerald"}>
                      {h.effective_model ?? h.fallback_model ?? "?"}
                    </span>
                  </div>
                ))}
              </div>
            </details>
          )}
        </div>
      ) : (
        <div className="text-[11px] font-mono text-text-muted">暂无模型路由事件</div>
      )}
    </section>
  );
});

// --- Parallel Scheduling Card (v5.5) ---

const SCHEDULER_BADGE: Record<string, { label: string; color: string; dot: string }> = {
  batch_parallel: { label: "批次并行", color: "text-cyan", dot: "bg-cyan" },
  serial: { label: "串行", color: "text-amber", dot: "bg-amber" },
  unknown: { label: "未知", color: "text-text-muted", dot: "bg-text-muted" },
};

const ParallelSchedulingCard = memo(function ParallelSchedulingCard({
  plan,
}: {
  plan: ParallelPlanSummary;
}) {
  const badge = SCHEDULER_BADGE[plan.scheduler_decision] ?? SCHEDULER_BADGE.unknown!;
  const hasData = plan.updated_at !== null;

  return (
    <section className="bg-deep border border-border p-4 rounded-lg">
      <h3 className="font-display text-[10px] font-bold text-text-bright uppercase mb-4 flex items-center justify-between">
        <span className="flex items-center">
          <span className="w-2 h-2 rounded-full bg-cyan mr-2"></span> 并行调度
        </span>
        {hasData && (
          <span className={`flex items-center text-[9px] font-mono ${badge.color}`}>
            <span className={`w-1.5 h-1.5 rounded-full ${badge.dot} mr-1`}></span>
            {badge.label}
          </span>
        )}
      </h3>
      {hasData ? (
        <div className="space-y-2 text-[11px] font-mono">
          <div className="flex justify-between gap-3">
            <span className="text-text-muted shrink-0">调度策略</span>
            <span className={`truncate ${badge.color}`}>{plan.scheduler_decision}</span>
          </div>
          <div className="flex justify-between gap-3">
            <span className="text-text-muted shrink-0">总任务数</span>
            <span className="text-text-bright">{plan.total_tasks}</span>
          </div>
          <div className="flex justify-between gap-3">
            <span className="text-text-muted shrink-0">批次数</span>
            <span className="text-text-bright">{plan.batch_count}</span>
          </div>
          <div className="flex justify-between gap-3">
            <span className="text-text-muted shrink-0">最大并行度</span>
            <span className="text-cyan font-bold">{plan.max_parallelism}</span>
          </div>
          {plan.current_batch_index !== null && (
            <div className="flex justify-between gap-3">
              <span className="text-text-muted shrink-0">当前批次</span>
              <span className="text-cyan font-bold">#{plan.current_batch_index}</span>
            </div>
          )}
          {plan.fallback_to_serial && plan.fallback_reason && (
            <div className="mt-1 px-2 py-1 bg-surface border border-amber/30 rounded text-[10px] text-amber">
              <span className="font-bold">降级原因: </span>{plan.fallback_reason}
            </div>
          )}
        </div>
      ) : (
        <div className="text-[11px] font-mono text-text-muted">暂无并行调度事件</div>
      )}
    </section>
  );
});
