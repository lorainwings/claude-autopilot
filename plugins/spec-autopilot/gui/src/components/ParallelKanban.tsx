/**
 * ParallelKanban — V2 水平可滚动任务卡片流
 * 显示并行任务执行状态 + Agent 生命周期卡片
 * v5.3: 可展开 Agent 卡片 + 工具调用计数
 * v5.8: 按 Phase 分组显示任务，避免跨 Phase 同名任务混排
 * 数据源: Zustand Store (taskProgress, agentMap, currentPhase, events)
 */

import { useState, useMemo } from "react";
import { useStore } from "../store";
import { selectPhaseDurations, selectGateStats } from "../store";
import type { AgentInfo, ParallelPlanSummary } from "../store";
import type { AutopilotEvent } from "../lib/ws-bridge";

const TDD_STEP_CONFIG = {
  red: { icon: "\uD83D\uDD34", label: "失败测试", color: "text-rose", borderColor: "border-rose", bgPulse: "bg-rose/5" },
  green: { icon: "\uD83D\uDFE2", label: "通过", color: "text-emerald", borderColor: "border-emerald", bgPulse: "" },
  refactor: { icon: "\uD83D\uDD35", label: "重构", color: "text-violet", borderColor: "border-violet", bgPulse: "bg-violet/5" },
} as const;

const STATUS_CONFIG = {
  running: { label: "进行中", color: "text-violet", bgColor: "bg-elevated", dot: true },
  passed: { label: "通过", color: "text-emerald", bgColor: "bg-deep", dot: false },
  failed: { label: "失败", color: "text-rose", bgColor: "bg-deep", dot: false },
  retrying: { label: "重试中", color: "text-amber", bgColor: "bg-deep", dot: false },
} as const;

const AGENT_STATUS_BADGE: Record<AgentInfo["status"], { icon: string; color: string; label: string }> = {
  dispatched: { icon: "\u25CF", color: "text-violet animate-pulse", label: "运行中" },
  ok: { icon: "\u2713", color: "text-emerald", label: "完成" },
  warning: { icon: "\u26A0", color: "text-amber", label: "警告" },
  blocked: { icon: "\u2716", color: "text-rose", label: "阻断" },
  failed: { icon: "\u2716", color: "text-rose", label: "失败" },
};

function formatDuration(ms?: number): string {
  if (ms == null) return "--";
  if (ms < 1000) return `${ms}ms`;
  const s = Math.round(ms / 1000);
  if (s < 60) return `${s}s`;
  return `${Math.floor(s / 60)}m${s % 60}s`;
}

function ToolEventRow({ event }: { event: AutopilotEvent }) {
  const p = event.payload as Record<string, unknown>;
  const toolName = (p.tool_name as string) || "--";
  const keyParam = (p.key_param as string) || "";
  const exitCode = p.exit_code as number | undefined;
  const ts = new Date(event.timestamp).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" });

  return (
    <div className="flex items-center justify-between text-[9px] font-mono text-text-muted py-0.5 border-b border-border/30 last:border-0">
      <div className="flex items-center space-x-2 truncate flex-1">
        <span className="text-cyan font-bold shrink-0">{toolName}</span>
        {keyParam && <span className="truncate text-text-muted/70">{keyParam.slice(0, 60)}</span>}
      </div>
      <div className="flex items-center space-x-2 shrink-0 ml-2">
        {exitCode != null && (
          <span className={exitCode === 0 ? "text-emerald" : "text-rose"}>exit={exitCode}</span>
        )}
        <span>{ts}</span>
      </div>
    </div>
  );
}

const PHASE_LABELS: Record<number, string> = {
  1: "需求分析",
  2: "OpenSpec",
  3: "Fast-Forward",
  4: "测试设计",
  5: "实施",
  6: "报告",
  7: "归档",
};

export function ParallelKanban() {
  const { taskProgress, agentMap, events, parallelPlan, currentPhase, mode } = useStore();
  const [expandedAgentId, setExpandedAgentId] = useState<string | null>(null);

  if (taskProgress.size === 0 && agentMap.size === 0) {
    return <PhasePipelineOverview events={events} currentPhase={currentPhase} mode={mode} />;
  }

  // v5.8: 按 phase 分组任务
  const tasksByPhase = useMemo(() => {
    const groups = new Map<number, typeof allTasks>();
    const allTasks = Array.from(taskProgress.values());
    for (const t of allTasks) {
      const phase = t.phase;
      if (!groups.has(phase)) groups.set(phase, []);
      groups.get(phase)!.push(t);
    }
    // 每组内按 task_index 排序
    for (const [, tasks] of groups) {
      tasks.sort((a, b) => a.task_index - b.task_index);
    }
    // 按 phase 编号排序返回
    return Array.from(groups.entries()).sort(([a], [b]) => a - b);
  }, [taskProgress]);

  const allTasks = Array.from(taskProgress.values());
  const agents = Array.from(agentMap.values());
  const passedCount = allTasks.filter((t) => t.status === "passed").length;

  // 优先使用 parallelPlan 状态判断并行模式（比推断更准确）
  const isParallelFromPlan = parallelPlan.updated_at !== null && parallelPlan.scheduler_decision === "batch_parallel";
  const isParallel = isParallelFromPlan || allTasks.some((t) => t.task_total > 1);
  const hasTdd = allTasks.some((t) => t.tdd_step !== undefined);
  const hasAgents = agents.length > 0;

  // Memoize per-agent tool counts and events to avoid O(agents * events) per render
  const agentToolData = useMemo(() => {
    const counts = new Map<string, number>();
    const eventsMap = new Map<string, AutopilotEvent[]>();
    for (const e of events) {
      if (e.type !== "tool_use") continue;
      const agentId = (e.payload as Record<string, unknown>).agent_id as string | undefined;
      if (!agentId) continue;
      counts.set(agentId, (counts.get(agentId) || 0) + 1);
      const list = eventsMap.get(agentId);
      if (list) list.push(e);
      else eventsMap.set(agentId, [e]);
    }
    return { counts, eventsMap };
  }, [events]);

  return (
    <section className="h-full border-b border-border flex flex-col p-4 bg-abyss/50 overflow-hidden">
      {/* Header */}
      <div className="flex items-center justify-between mb-2">
        <div className="flex items-center space-x-3">
          <div className="font-display text-xs font-bold uppercase tracking-widest text-text-bright">执行流水线</div>
          <div className="h-4 w-px bg-border"></div>
          <div className="text-[10px] font-mono text-cyan">
            {allTasks.length > 0 ? `${passedCount}/${allTasks.length} 任务已完成` : `${agents.length} Agent`}
          </div>
        </div>
        <div className="flex space-x-2">
          {isParallel && (
            <span className="px-2 py-0.5 bg-violet/20 text-violet border border-violet/30 text-[9px] font-bold rounded">并行</span>
          )}
          {hasTdd && (
            <span className="px-2 py-0.5 bg-cyan/20 text-cyan border border-cyan/30 text-[9px] font-bold rounded">TDD 已开启</span>
          )}
          {hasAgents && (
            <span className="px-2 py-0.5 bg-violet/20 text-violet border border-violet/30 text-[9px] font-bold rounded">Agent</span>
          )}
        </div>
      </div>

      {/* Parallel Plan Info Bar (v5.8) */}
      <ParallelPlanInfoBar plan={parallelPlan} />

      {/* Task + Agent Cards — Horizontal Scroll */}
      {allTasks.length === 0 && agents.length === 0 ? (
        <div className="flex-1 flex items-center justify-center text-text-muted text-sm font-mono">
          等待任务分配...
        </div>
      ) : (
        <div className="flex-1 overflow-x-auto overflow-y-hidden flex space-x-4 pb-2">
          {/* Agent Cards */}
          {agents.map((agent) => {
            const badge = AGENT_STATUS_BADGE[agent.status];
            const isActive = agent.status === "dispatched";
            const borderColor = isActive ? "border-violet" : agent.status === "ok" ? "border-emerald" : agent.status === "failed" || agent.status === "blocked" ? "border-rose" : "border-amber";
            const isExpanded = expandedAgentId === agent.agent_id;
            const toolCount = agentToolData.counts.get(agent.agent_id) || 0;
            const toolEvents = isExpanded ? (agentToolData.eventsMap.get(agent.agent_id) || []) : [];

            return (
              <div
                key={agent.agent_id}
                className={`${isExpanded ? "w-96" : "w-64"} shrink-0 ${isActive ? "bg-elevated" : "bg-deep"} border-l-4 ${borderColor} p-3 flex flex-col justify-between relative overflow-hidden cursor-pointer transition-all duration-200`}
                onClick={() => setExpandedAgentId(isExpanded ? null : agent.agent_id)}
              >
                {isActive && (
                  <div className="absolute inset-0 bg-violet/5 animate-pulse-soft"></div>
                )}

                <div className="relative z-10">
                  <div className="flex justify-between items-start mb-2">
                    <span className={`text-[11px] font-mono font-bold ${isActive ? "text-white" : badge.color}`}>
                      {agent.agent_label}
                    </span>
                    <div className="flex items-center space-x-2">
                      {isActive && toolCount > 0 && (
                        <span className="text-[9px] bg-violet/20 text-violet px-1 rounded font-mono">
                          {toolCount} 工具调用
                        </span>
                      )}
                      <span className={`text-[9px] ${badge.color} font-bold`}>
                        {badge.icon} {badge.label}
                      </span>
                    </div>
                  </div>

                  <div className="text-[9px] font-mono text-text-muted mb-2">
                    Phase {agent.phase} | {agent.agent_id}
                  </div>

                  {agent.summary && (
                    <div className={`text-[9px] font-mono text-text-muted ${isExpanded ? "" : "truncate"}`}>
                      {isExpanded ? agent.summary : agent.summary.slice(0, 80)}
                    </div>
                  )}

                  {/* Expanded panel */}
                  {isExpanded && (
                    <div className="mt-3 border-t border-border/50 pt-2 space-y-2">
                      {/* Duration breakdown */}
                      {agent.duration_ms != null && (
                        <div className="text-[9px] font-mono text-text-muted">
                          耗时: {formatDuration(agent.duration_ms)}
                        </div>
                      )}

                      {/* Output files */}
                      {agent.output_files && agent.output_files.length > 0 && (
                        <div>
                          <div className="text-[9px] font-mono text-cyan mb-1">产出文件:</div>
                          {agent.output_files.map((f, i) => (
                            <div key={i} className="text-[9px] font-mono text-text-muted truncate pl-2">
                              {f}
                            </div>
                          ))}
                        </div>
                      )}

                      {/* Related tool_use events */}
                      {toolEvents.length > 0 && (
                        <div>
                          <div className="text-[9px] font-mono text-cyan mb-1">
                            工具调用 ({toolEvents.length}):
                          </div>
                          <div className="max-h-32 overflow-y-auto">
                            {toolEvents.slice(-20).map((ev, i) => (
                              <ToolEventRow key={i} event={ev} />
                            ))}
                            {toolEvents.length > 20 && (
                              <div className="text-[9px] font-mono text-text-muted/50 text-center py-1">
                                ...{toolEvents.length - 20} 条更早记录已折叠
                              </div>
                            )}
                          </div>
                        </div>
                      )}
                    </div>
                  )}
                </div>

                <div className="relative z-10 flex items-center justify-between text-[9px] font-mono text-text-muted mt-2">
                  <span>{formatDuration(agent.duration_ms)}</span>
                  <span>
                    {new Date(agent.complete_time || agent.dispatch_time).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" })}
                  </span>
                </div>
              </div>
            );
          })}

          {/* v5.8: Task Cards grouped by Phase */}
          {tasksByPhase.map(([phase, tasks]) => (
            <div key={`phase-${phase}`} className="shrink-0 flex flex-col">
              {/* Phase group header */}
              {tasksByPhase.length > 1 && (
                <div className="text-[9px] font-mono text-text-muted mb-1 px-1">
                  Phase {phase}: {PHASE_LABELS[phase] || `Phase ${phase}`}
                </div>
              )}
              <div className="flex space-x-3">
                {tasks.map((task) => {
                  const statusCfg = STATUS_CONFIG[task.status];
                  const tddCfg = task.tdd_step ? TDD_STEP_CONFIG[task.tdd_step] : null;
                  const isRunning = task.status === "running";
                  const borderColor = tddCfg?.borderColor || (task.status === "passed" ? "border-emerald" : "border-border");

                  return (
                    <div
                      key={`p${phase}:${task.task_name}`}
                      className={`w-64 shrink-0 ${statusCfg.bgColor} border-l-4 ${borderColor} p-3 flex flex-col justify-between relative overflow-hidden`}
                    >
                      {/* Running pulse overlay */}
                      {isRunning && tddCfg && (
                        <div className={`absolute inset-0 ${tddCfg.bgPulse} animate-pulse-soft`}></div>
                      )}

                      <div className="relative z-10">
                        <div className="flex justify-between items-start mb-2">
                          <span className={`text-[11px] font-mono font-bold ${isRunning ? "text-white" : statusCfg.color}`}>
                            {task.task_name}
                          </span>
                          <div className="flex items-center space-x-1">
                            {task.retry_count !== undefined && task.retry_count > 0 && (
                              <span className="text-[9px] bg-amber/20 text-amber px-1 rounded">
                                &#8635; 重试中
                              </span>
                            )}
                            {task.status === "passed" ? (
                              <span className="text-[9px] bg-emerald/10 text-emerald px-1 rounded">&#10003; 通过</span>
                            ) : isRunning ? (
                              <span className={`text-[9px] ${statusCfg.color} animate-pulse font-bold`}>&#9679; {statusCfg.label}</span>
                            ) : task.status === "failed" ? (
                              <span className="text-[9px] bg-rose/10 text-rose px-1 rounded">&#10007; 失败</span>
                            ) : null}
                          </div>
                        </div>

                        {/* Progress bar */}
                        <div className="w-full bg-border h-1 mb-3">
                          <div
                            className={`h-full ${
                              task.status === "passed"
                                ? "bg-emerald w-full"
                                : task.status === "failed"
                                  ? "bg-rose w-full"
                                  : tddCfg
                                    ? `${tddCfg.color === "text-rose" ? "bg-rose" : tddCfg.color === "text-violet" ? "bg-violet" : "bg-emerald"} w-[65%]`
                                    : "bg-border w-0"
                            } ${isRunning ? "shadow-[0_0_8px_rgba(139,92,246,0.6)]" : ""}`}
                          ></div>
                        </div>
                      </div>

                      <div className="relative z-10 flex items-center justify-between text-[9px] font-mono text-text-muted">
                        <span className={`${tddCfg?.color || "text-text-muted"} font-bold`}>
                          {tddCfg ? `${tddCfg.icon} ${tddCfg.label}` : `[${task.task_index}/${task.task_total}]`}
                        </span>
                        <span className={isRunning ? "text-white" : ""}>
                          {new Date(task.timestamp).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" })}
                        </span>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          ))}
        </div>
      )}
    </section>
  );
}

// --- Phase Pipeline Overview (P2-1: orchestration state when no tasks/agents) ---
const PHASE_STATUS_CONFIG = {
  pending: { icon: "\u25CB", color: "text-text-muted", bg: "bg-border/20" },
  running: { icon: "\u25CF", color: "text-violet animate-pulse", bg: "bg-violet/10" },
  ok: { icon: "\u2713", color: "text-emerald", bg: "bg-emerald/10" },
  warning: { icon: "\u26A0", color: "text-amber", bg: "bg-amber/10" },
  blocked: { icon: "\u2716", color: "text-rose", bg: "bg-rose/10" },
  failed: { icon: "\u2716", color: "text-rose", bg: "bg-rose/10" },
} as const;

const ALL_LABELS = [
  "环境初始化", "需求理解", "OpenSpec 创建", "快速生成",
  "测试设计", "代码实施", "测试报告", "归档清理",
];

function PhasePipelineOverview({ events, currentPhase, mode }: {
  events: AutopilotEvent[];
  currentPhase: number | null;
  mode: "full" | "lite" | "minimal" | null;
}) {
  const phaseDurations = useMemo(() => selectPhaseDurations(events), [events]);
  const gateStats = useMemo(() => selectGateStats(events), [events]);
  const hasEvents = events.length > 0;

  return (
    <section className="h-full border-b border-border flex flex-col p-4 bg-abyss/50 overflow-hidden">
      <div className="flex items-center justify-between mb-3">
        <div className="flex items-center space-x-3">
          <div className="font-display text-xs font-bold uppercase tracking-widest text-text-bright">编排流水线</div>
          {mode && (
            <>
              <div className="h-4 w-px bg-border"></div>
              <span className="text-[10px] font-mono text-cyan">{mode.toUpperCase()}</span>
            </>
          )}
          {currentPhase != null && (
            <>
              <div className="h-4 w-px bg-border"></div>
              <span className="text-[10px] font-mono text-violet">Phase {currentPhase}: {ALL_LABELS[currentPhase] || `Phase ${currentPhase}`}</span>
            </>
          )}
        </div>
        {hasEvents && (
          <div className="flex space-x-3 text-[9px] font-mono text-text-muted">
            <span className="text-emerald">{gateStats.passed} 通过</span>
            {gateStats.blocked > 0 && <span className="text-rose">{gateStats.blocked} 阻断</span>}
            {gateStats.passRate > 0 && <span className="text-cyan">{gateStats.passRate}% 通过率</span>}
          </div>
        )}
      </div>

      {!hasEvents ? (
        <div className="flex-1 flex items-center justify-center text-text-muted text-sm font-mono">
          等待编排启动...
        </div>
      ) : (
        <div className="flex-1 flex flex-col justify-center space-y-1">
          {phaseDurations.map((pd) => {
            const cfg = PHASE_STATUS_CONFIG[pd.status];
            const isActive = pd.status === "running";
            return (
              <div
                key={pd.phase}
                className={`flex items-center px-3 py-1.5 rounded ${cfg.bg} ${isActive ? "ring-1 ring-violet/30" : ""}`}
              >
                <span className={`w-4 text-center text-[10px] ${cfg.color}`}>{cfg.icon}</span>
                <span className="text-[10px] font-mono text-text-muted w-6 ml-2">P{pd.phase}</span>
                <span className={`text-[10px] font-mono flex-1 ${isActive ? "text-text-bright" : "text-text-muted"}`}>
                  {pd.label}
                </span>
                <span className={`text-[9px] font-mono ${cfg.color} font-bold w-12 text-right`}>
                  {pd.status === "pending" ? "--" : pd.status}
                </span>
                <span className="text-[9px] font-mono text-text-muted/60 w-16 text-right">
                  {pd.durationMs > 0 ? formatDuration(pd.durationMs) : "--"}
                </span>
              </div>
            );
          })}
        </div>
      )}
    </section>
  );
}

// --- Parallel Plan Info Bar (v5.8) ---
function ParallelPlanInfoBar({ plan }: { plan: ParallelPlanSummary }) {
  if (!plan.updated_at) return null;

  const isFallback = plan.fallback_to_serial;
  const decisionColor = isFallback ? "text-amber" : plan.scheduler_decision === "batch_parallel" ? "text-cyan" : "text-text-muted";

  return (
    <div className="mb-3 flex items-center flex-wrap gap-3 text-[9px] font-mono text-text-muted border border-border/40 bg-deep/50 px-2 py-1 rounded">
      <span className={`font-bold ${decisionColor}`}>{plan.scheduler_decision}</span>
      <span className="text-border">|</span>
      <span>{plan.total_tasks} tasks / {plan.batch_count} batches</span>
      <span className="text-border">|</span>
      <span className="text-cyan">max ‖{plan.max_parallelism}</span>
      {plan.current_batch_index !== null && (
        <>
          <span className="text-border">|</span>
          <span className="text-violet">batch #{plan.current_batch_index}</span>
        </>
      )}
      {isFallback && plan.fallback_reason && (
        <>
          <span className="text-border">|</span>
          <span className="text-amber">⚠ {plan.fallback_reason.slice(0, 60)}</span>
        </>
      )}
      {plan.diagnostics.length > 0 && (
        <>
          <span className="text-border">|</span>
          <span className="text-amber/70">{plan.diagnostics[0]!.slice(0, 60)}</span>
        </>
      )}
    </div>
  );
}
