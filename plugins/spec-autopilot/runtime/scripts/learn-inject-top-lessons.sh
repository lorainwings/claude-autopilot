#!/usr/bin/env bash
# learn-inject-top-lessons.sh
# Phase 0 注入：返回 top-3 历史教训 JSON 数组
#
# 用法:
#   learn-inject-top-lessons.sh --raw-requirement "..." [--episodes-root DIR] [--top N]
#
# 输出: stdout 打印 JSON 数组 [{lesson_id, title, severity, evidence_count, injection_text}]
# 失败时仍输出 `[]`，退出码非零仅保留给参数错误
#
# 退出码:
#   0 — 正常（包含无数据情形）
#   2 — 参数错误

set -uo pipefail

RAW_REQUIREMENT=""
EPISODES_ROOT=""
TOP_N="3"

while [ $# -gt 0 ]; do
  case "$1" in
    --raw-requirement)
      RAW_REQUIREMENT="${2:-}"
      shift 2
      ;;
    --episodes-root)
      EPISODES_ROOT="${2:-}"
      shift 2
      ;;
    --top)
      TOP_N="${2:-3}"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [ -z "$EPISODES_ROOT" ]; then
  PROJECT_ROOT="${AUTOPILOT_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  EPISODES_ROOT="$PROJECT_ROOT/docs/reports"
fi

python3 - "$EPISODES_ROOT" "$TOP_N" "$RAW_REQUIREMENT" <<'PY'
import glob
import hashlib
import json
import os
import sys

root, top_n, _raw = sys.argv[1], int(sys.argv[2]), sys.argv[3]

if not os.path.isdir(root):
  print("[]")
  sys.exit(0)

pattern = os.path.join(root, "*", "episodes", "*.json")
files = sorted(glob.glob(pattern))

clusters = {}
for fp in files:
  try:
    with open(fp, "r", encoding="utf-8") as f:
      ep = json.load(f)
  except Exception:
    continue  # 损坏 JSON 忽略
  if not isinstance(ep, dict):
    continue
  if ep.get("gate_result") not in ("blocked", "failed"):
    continue
  ft = ep.get("failure_trace") or {}
  root_cause = ft.get("root_cause") or "unknown"
  phase = ep.get("phase") or "phase?"
  failed_gate = ft.get("failed_gate") or "unknown"
  key = "{}::{}::{}".format(phase, root_cause, failed_gate)
  pattern_id = hashlib.sha1(key.encode("utf-8")).hexdigest()[:12]
  cluster = clusters.setdefault(pattern_id, {
    "lesson_id": pattern_id,
    "title": "{} @ {}".format(root_cause, phase),
    "severity": "high" if ep.get("gate_result") == "failed" else "medium",
    "evidence_count": 0,
    "representative_reflection": ep.get("reflection") or "",
    "phase": phase,
  })
  cluster["evidence_count"] += 1
  # 保留最新 reflection
  cluster["representative_reflection"] = ep.get("reflection") or cluster["representative_reflection"]

ordered = sorted(clusters.values(), key=lambda c: c["evidence_count"], reverse=True)
out = []
for c in ordered[:top_n]:
  out.append({
    "lesson_id": c["lesson_id"],
    "title": c["title"],
    "severity": c["severity"],
    "evidence_count": c["evidence_count"],
    "injection_text": "[learned:{}] {} — {}".format(
      c["lesson_id"], c["title"], c["representative_reflection"].replace("\n", " ")[:240]
    ),
  })

print(json.dumps(out, ensure_ascii=False))
PY
