/**
 * ParallelKanban — V2 水平可滚动任务卡片流
 * 显示 Phase 5 并行任务执行状态
 * 数据源: Zustand Store (taskProgress, currentPhase)
 */

import { useStore } from "../store";

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

export function ParallelKanban() {
  const { taskProgress, currentPhase } = useStore();

  if (currentPhase !== 5 && taskProgress.size === 0) {
    return null;
  }

  const tasks = Array.from(taskProgress.values()).sort((a, b) => a.task_index - b.task_index);
  const passedCount = tasks.filter((t) => t.status === "passed").length;

  // G6: Infer parallel mode from concurrent running tasks, TDD from tdd_step fields
  const runningTasks = tasks.filter((t) => t.status === "running");
  const isParallel = runningTasks.length > 1 || tasks.some((t) => t.task_total > 1);
  const hasTdd = tasks.some((t) => t.tdd_step !== undefined);

  return (
    <section className="h-full border-b border-border flex flex-col p-4 bg-abyss/50 overflow-hidden">
      {/* Header */}
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center space-x-3">
          <div className="font-display text-xs font-bold uppercase tracking-widest text-text-bright">执行流水线</div>
          <div className="h-4 w-px bg-border"></div>
          <div className="text-[10px] font-mono text-cyan">{passedCount}/{tasks.length} 任务已完成</div>
        </div>
        <div className="flex space-x-2">
          {isParallel && (
            <span className="px-2 py-0.5 bg-violet/20 text-violet border border-violet/30 text-[9px] font-bold rounded">并行</span>
          )}
          {hasTdd && (
            <span className="px-2 py-0.5 bg-cyan/20 text-cyan border border-cyan/30 text-[9px] font-bold rounded">TDD 已开启</span>
          )}
        </div>
      </div>

      {/* Task Cards — Horizontal Scroll */}
      {tasks.length === 0 ? (
        <div className="flex-1 flex items-center justify-center text-text-muted text-sm font-mono">
          等待任务分配...
        </div>
      ) : (
        <div className="flex-1 overflow-x-auto overflow-y-hidden flex space-x-4 pb-2">
          {tasks.map((task) => {
            const statusCfg = STATUS_CONFIG[task.status];
            const tddCfg = task.tdd_step ? TDD_STEP_CONFIG[task.tdd_step] : null;
            const isRunning = task.status === "running";
            const borderColor = tddCfg?.borderColor || (task.status === "passed" ? "border-emerald" : "border-border");

            return (
              <div
                key={task.task_name}
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
      )}
    </section>
  );
}
