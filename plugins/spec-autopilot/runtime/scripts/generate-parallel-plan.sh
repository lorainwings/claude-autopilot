#!/usr/bin/env bash
# generate-parallel-plan.sh
# 生成并行计划: 读取任务列表, 构建文件所有权图, 检测冲突, 输出 parallel_plan.json
#
# Usage:
#   generate-parallel-plan.sh [tasks_json_file]
#   cat tasks.json | generate-parallel-plan.sh
#
# Input: JSON array of tasks:
#   [{"task_name": "task-1", "affected_files": ["a.ts","b.ts"], "depends_on": [], "domain": "frontend"}]
#
# Output: parallel_plan.json on stdout
#
# 核心逻辑使用 Python3 实现 (Union-Find 分组 + 拓扑排序)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 读取任务列表: 从文件参数或 stdin
TASKS_JSON=""
if [ -n "${1:-}" ] && [ -f "$1" ]; then
  TASKS_JSON=$(cat "$1")
elif [ ! -t 0 ]; then
  TASKS_JSON=$(cat)
else
  echo "ERROR: 需要从文件参数或 stdin 提供任务列表 JSON" >&2
  exit 1
fi

if [ -z "$TASKS_JSON" ]; then
  echo "ERROR: 任务列表为空" >&2
  exit 1
fi

# 核心逻辑: Python3 Union-Find + 拓扑排序 + batch 生成
python3 -c '
import json, sys
from datetime import datetime, timezone
from collections import defaultdict, deque

def main():
    try:
        tasks = json.loads(sys.argv[1])
    except (json.JSONDecodeError, ValueError) as e:
        print(json.dumps({
            "plan_version": "1.0",
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "parallel_enabled": False,
            "total_tasks": 0,
            "tasks": [],
            "dependency_graph": {},
            "batches": [],
            "max_parallelism": 0,
            "fallback_to_serial": True,
            "fallback_reason": f"JSON 解析失败: {str(e)}",
            "scheduler_decision": "serial"
        }))
        return

    if not tasks or not isinstance(tasks, list):
        print(json.dumps({
            "plan_version": "1.0",
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "parallel_enabled": False,
            "total_tasks": 0,
            "tasks": [],
            "dependency_graph": {},
            "batches": [],
            "max_parallelism": 0,
            "fallback_to_serial": True,
            "fallback_reason": "任务列表为空或格式无效",
            "scheduler_decision": "serial"
        }))
        return

    task_names = [t["task_name"] for t in tasks]
    task_map = {t["task_name"]: t for t in tasks}
    n = len(tasks)

    # --- 1. 构建文件所有权图 (Union-Find) ---
    parent = list(range(n))
    rank = [0] * n

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra == rb:
            return
        if rank[ra] < rank[rb]:
            ra, rb = rb, ra
        parent[rb] = ra
        if rank[ra] == rank[rb]:
            rank[ra] += 1

    # v5.7: 诊断 — 检测 affected_files 缺失（输出到 JSON diagnostics 字段）
    diagnostics = []
    missing_af = [t["task_name"] for t in tasks if not t.get("affected_files")]
    if missing_af:
        diagnostics.append(f"{len(missing_af)}/{n} tasks 缺少 affected_files: {missing_af[:5]}")

    # 文件 -> 任务索引映射
    file_to_tasks = defaultdict(list)
    for i, t in enumerate(tasks):
        for f in t.get("affected_files", []):
            file_to_tasks[f].append(i)

    # 文件冲突检测: 同一文件被多个任务修改 -> 不能在同一 batch
    file_conflicts = {}
    for f, task_indices in file_to_tasks.items():
        if len(task_indices) > 1:
            file_conflicts[f] = [task_names[i] for i in task_indices]

    # --- 2. 构建依赖图 ---
    # 显式依赖 (depends_on)
    dep_graph = defaultdict(set)  # task_name -> set of dependencies
    for t in tasks:
        tn = t["task_name"]
        for dep in t.get("depends_on", []):
            if dep in task_map:
                dep_graph[tn].add(dep)

    # 文件冲突隐式依赖: 共享文件的任务之间按顺序添加依赖
    for f, task_indices in file_to_tasks.items():
        if len(task_indices) > 1:
            sorted_indices = sorted(task_indices)
            for j in range(1, len(sorted_indices)):
                later = task_names[sorted_indices[j]]
                earlier = task_names[sorted_indices[j - 1]]
                dep_graph[later].add(earlier)

    # 序列化依赖图
    dep_graph_serializable = {tn: sorted(deps) for tn, deps in dep_graph.items() if deps}

    # --- 3. 拓扑排序 + batch 生成 ---
    # 计算入度
    in_degree = {tn: 0 for tn in task_names}
    reverse_graph = defaultdict(set)
    for tn, deps in dep_graph.items():
        in_degree.setdefault(tn, 0)
        for d in deps:
            in_degree[tn] = in_degree.get(tn, 0) + 1
            reverse_graph[d].add(tn)

    # 检测循环依赖
    completed = set()
    remaining = set(task_names)
    batches = []
    batch_index = 0

    while remaining:
        # 找到所有入度为 0 的任务 (就绪任务)
        ready = []
        for tn in sorted(remaining):
            all_deps_done = all(d in completed for d in dep_graph.get(tn, set()))
            if all_deps_done:
                ready.append(tn)

        if not ready:
            # 循环依赖 -> fallback
            print(json.dumps({
                "plan_version": "1.0",
                "generated_at": datetime.now(timezone.utc).isoformat(),
                "parallel_enabled": False,
                "total_tasks": n,
                "tasks": tasks,
                "dependency_graph": dep_graph_serializable,
                "batches": batches,
                "max_parallelism": 0,
                "fallback_to_serial": True,
                "fallback_reason": f"检测到循环依赖，剩余任务: {sorted(remaining)}",
                "scheduler_decision": "serial"
            }))
            return

        # 判断 batch 内是否可并行
        can_parallel = len(ready) > 1
        if can_parallel:
            # 检查 batch 内任务是否有文件冲突
            batch_files = set()
            has_conflict = False
            for tn in ready:
                t = task_map[tn]
                t_files = set(t.get("affected_files", []))
                if batch_files & t_files:
                    has_conflict = True
                    break
                batch_files |= t_files

            if has_conflict:
                reason = "file ownership conflict within batch"
                can_parallel = False
            else:
                reason = "no file ownership conflict"
        else:
            reason = "single task in batch" if len(ready) == 1 else "depends on previous batch"

        batches.append({
            "batch_index": batch_index,
            "tasks": ready,
            "can_parallel": can_parallel,
            "reason": reason,
        })

        completed |= set(ready)
        remaining -= set(ready)
        batch_index += 1

    # --- 4. 计算最终决策 ---
    max_parallelism = max((len(b["tasks"]) for b in batches), default=0)
    any_parallel = any(b["can_parallel"] for b in batches)

    # 全依赖链检测: 每个 batch 都只有 1 个任务
    all_single = all(len(b["tasks"]) == 1 for b in batches)
    fallback_to_serial = all_single and n > 1
    fallback_reason = None
    if fallback_to_serial:
        fallback_reason = f"所有 {n} 个任务形成线性依赖链，无法并行"

    if fallback_to_serial:
        scheduler_decision = "serial"
    elif any_parallel:
        scheduler_decision = "batch_parallel"
    else:
        scheduler_decision = "serial"

    plan = {
        "plan_version": "1.0",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "parallel_enabled": not fallback_to_serial,
        "total_tasks": n,
        "tasks": tasks,
        "dependency_graph": dep_graph_serializable,
        "batches": batches,
        "max_parallelism": max_parallelism,
        "fallback_to_serial": fallback_to_serial,
        "fallback_reason": fallback_reason,
        "scheduler_decision": scheduler_decision,
        "diagnostics": diagnostics,
    }

    print(json.dumps(plan, ensure_ascii=False))

main()
' "$TASKS_JSON" 2>/dev/null

exit $?
