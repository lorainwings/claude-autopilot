#!/usr/bin/env bash
# learn-promote-candidate.sh
# L3 晋升候选扫描器
#
# 扫描 docs/reports/*/episodes/*.json，按 (phase, root_cause, failed_gate) 聚类，
# 命中 ≥ 3 且无成功 fingerprint 反例 → 输出 docs/learned/candidates/{pattern_id}.md
#
# 用法:
#   learn-promote-candidate.sh [--episodes-root DIR] [--out-dir DIR] [--threshold N]
#
# 退出码:
#   0 — 正常（不论是否产生候选）
#   2 — 参数错误

set -uo pipefail

EPISODES_ROOT=""
OUT_DIR=""
THRESHOLD="3"

while [ $# -gt 0 ]; do
  case "$1" in
    --episodes-root)
      EPISODES_ROOT="${2:-}"
      shift 2
      ;;
    --out-dir)
      OUT_DIR="${2:-}"
      shift 2
      ;;
    --threshold)
      THRESHOLD="${2:-3}"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

PROJECT_ROOT="${AUTOPILOT_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
EPISODES_ROOT="${EPISODES_ROOT:-$PROJECT_ROOT/docs/reports}"
OUT_DIR="${OUT_DIR:-$PROJECT_ROOT/docs/learned/candidates}"

mkdir -p "$OUT_DIR"

python3 - "$EPISODES_ROOT" "$OUT_DIR" "$THRESHOLD" <<'PY'
import glob
import hashlib
import json
import os
import sys

root, out_dir, threshold = sys.argv[1], sys.argv[2], int(sys.argv[3])

if not os.path.isdir(root):
  print(json.dumps({"candidates": [], "reason": "no episodes root"}))
  sys.exit(0)

pattern = os.path.join(root, "*", "episodes", "*.json")
files = sorted(glob.glob(pattern))

clusters = {}
counters = {}  # success_fingerprint counters: pattern_id -> count

for fp in files:
  try:
    with open(fp, "r", encoding="utf-8") as f:
      ep = json.load(f)
  except Exception:
    continue
  if not isinstance(ep, dict):
    continue
  phase = ep.get("phase") or "phase?"
  ft = ep.get("failure_trace") or {}
  root_cause = ft.get("root_cause") or ""
  failed_gate = ft.get("failed_gate") or ""

  if ep.get("gate_result") in ("blocked", "failed") and root_cause:
    key = "{}::{}::{}".format(phase, root_cause, failed_gate)
    pid = hashlib.sha1(key.encode("utf-8")).hexdigest()[:12]
    c = clusters.setdefault(pid, {
      "pattern_id": pid,
      "phase": phase,
      "root_cause": root_cause,
      "failed_gate": failed_gate,
      "hit_count": 0,
      "evidence_episodes": [],
      "last_seen": ep.get("timestamp_end", ""),
      "representative_reflection": ep.get("reflection", ""),
    })
    c["hit_count"] += 1
    c["evidence_episodes"].append(fp)
    if ep.get("timestamp_end", "") > c["last_seen"]:
      c["last_seen"] = ep.get("timestamp_end", "")
      c["representative_reflection"] = ep.get("reflection", c["representative_reflection"])
  elif ep.get("gate_result") == "ok":
    fp_field = ep.get("success_fingerprint") or ""
    # success_fingerprint 中若包含 root_cause 字符串，视为对应失败模式的反例
    if isinstance(fp_field, str) and fp_field:
      counters[phase + "::" + fp_field] = counters.get(phase + "::" + fp_field, 0) + 1

# 应用反例抵消
candidates = []
for pid, c in clusters.items():
  effective = c["hit_count"]
  for k, n in counters.items():
    if k.startswith(c["phase"] + "::") and c["root_cause"] in k:
      effective -= n
  if effective >= threshold:
    candidates.append((pid, c, effective))

written = []
for pid, c, effective in candidates:
  out_path = os.path.join(out_dir, "{}.md".format(pid))
  body = []
  body.append("---")
  body.append("pattern_id: {}".format(pid))
  body.append("phase: {}".format(c["phase"]))
  body.append("root_cause: {}".format(c["root_cause"]))
  body.append("failed_gate: {}".format(c["failed_gate"]))
  body.append("hit_count: {}".format(effective))
  body.append("last_seen: {}".format(c["last_seen"]))
  body.append("status: pending_review")
  body.append("---")
  body.append("")
  body.append("# 习得规则候选: {}".format(c["root_cause"]))
  body.append("")
  body.append("## 失败证据")
  body.append("")
  for ep_path in c["evidence_episodes"]:
    body.append("- {}".format(ep_path))
  body.append("")
  body.append("## 代表性反思")
  body.append("")
  body.append("```")
  body.append(c["representative_reflection"] or "(无反思)")
  body.append("```")
  body.append("")
  body.append("## 审核检查清单")
  body.append("")
  body.append("- [ ] 根因归因准确")
  body.append("- [ ] 建议规则可执行")
  body.append("- [ ] 无现有规则已覆盖")
  body.append("- [ ] 无反例未考虑")
  with open(out_path, "w", encoding="utf-8") as f:
    f.write("\n".join(body) + "\n")
  written.append(out_path)

print(json.dumps({
  "candidates": written,
  "cluster_count": len(clusters),
  "promoted": len(written),
  "threshold": threshold,
}, ensure_ascii=False))
PY
