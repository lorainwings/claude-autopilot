/**
 * ParallelKanban — 并行任务看板
 * 显示 Phase 5 并行任务执行状态
 */

import { useStore } from "../store";

const TDD_STEP_ICONS = {
  red: "🔴",
  green: "🟢",
  refactor: "🔵",
};

const STATUS_COLORS = {
  running: "bg-blue-500/20 border-blue-500",
  passed: "bg-green-500/20 border-green-500",
  failed: "bg-red-500/20 border-red-500",
  retrying: "bg-yellow-500/20 border-yellow-500",
};

export function ParallelKanban() {
  const { taskProgress, currentPhase } = useStore();

  if (currentPhase !== 5 && taskProgress.size === 0) {
    return null;
  }

  const tasks = Array.from(taskProgress.values()).sort((a, b) => a.task_index - b.task_index);

  return (
    <div className="parallel-kanban p-4 bg-gray-900 rounded-lg border border-gray-700">
      <div className="kanban-header mb-4 flex items-center justify-between">
        <h3 className="text-lg font-semibold text-gray-100">Parallel Tasks</h3>
        <span className="text-sm text-gray-400">
          {tasks.filter((t) => t.status === "passed").length} / {tasks.length}
        </span>
      </div>

      {tasks.length === 0 ? (
        <div className="text-center text-gray-500 py-8">Waiting for tasks...</div>
      ) : (
        <div className="grid grid-cols-1 gap-3">
          {tasks.map((task) => (
            <div
              key={task.task_name}
              className={`task-card p-3 rounded border-l-4 ${STATUS_COLORS[task.status]}`}
            >
              <div className="flex items-start justify-between mb-2">
                <div className="flex-1">
                  <div className="text-sm font-medium text-gray-200 mb-1">{task.task_name}</div>
                  <div className="flex items-center gap-2 text-xs text-gray-400">
                    <span>Task {task.task_index}/{task.task_total}</span>
                    {task.tdd_step && (
                      <span className="flex items-center gap-1">
                        {TDD_STEP_ICONS[task.tdd_step]} {task.tdd_step.toUpperCase()}
                      </span>
                    )}
                  </div>
                </div>
                <div className="text-xs font-semibold text-gray-300 uppercase">
                  {task.status}
                </div>
              </div>

              {task.retry_count !== undefined && task.retry_count > 0 && (
                <div className="text-xs text-yellow-400 mt-1">
                  Retry: {task.retry_count}
                </div>
              )}

              <div className="text-xs text-gray-500 mt-2">
                {new Date(task.timestamp).toLocaleTimeString()}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
