#!/usr/bin/env bash
# learn-episode-write.sh
# L1 Episode 写入器
#
# 读取 Phase checkpoint JSON → 构造 L1 Episode → 写入
#   docs/reports/{version}/episodes/{phase}.json
#
# 用法:
#   learn-episode-write.sh --phase phase5 --checkpoint path/to/phase5.json \
#                          [--version v5.9.0] [--out-dir DIR] [--run-id ID]
#
# 退出码:
#   0 — episode 写入成功（schema 通过）
#   1 — checkpoint 缺失 / schema 失败
#   2 — 参数错误

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$SCRIPT_DIR/learn-episode-schema-validate.sh"

PHASE=""
CHECKPOINT=""
VERSION=""
OUT_DIR=""
RUN_ID=""

while [ $# -gt 0 ]; do
  case "$1" in
    --phase)
      PHASE="${2:-}"
      shift 2
      ;;
    --checkpoint)
      CHECKPOINT="${2:-}"
      shift 2
      ;;
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --out-dir)
      OUT_DIR="${2:-}"
      shift 2
      ;;
    --run-id)
      RUN_ID="${2:-}"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [ -z "$PHASE" ] || [ -z "$CHECKPOINT" ]; then
  echo "usage: learn-episode-write.sh --phase <phase> --checkpoint <path>" >&2
  exit 2
fi

if [ ! -f "$CHECKPOINT" ]; then
  echo "checkpoint not found: $CHECKPOINT" >&2
  exit 1
fi

VERSION="${VERSION:-unversioned}"
if [ -z "$OUT_DIR" ]; then
  PROJECT_ROOT="${AUTOPILOT_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  OUT_DIR="$PROJECT_ROOT/docs/reports/$VERSION/episodes"
fi

mkdir -p "$OUT_DIR"

RUN_ID="${RUN_ID:-run-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
EPISODE_PATH="$OUT_DIR/${PHASE}.json"

EPISODE_JSON=$(
  python3 - "$CHECKPOINT" "$PHASE" "$RUN_ID" <<'PY'
import json
import os
import sys
import time

checkpoint_path, phase, run_id = sys.argv[1], sys.argv[2], sys.argv[3]

try:
  with open(checkpoint_path, "r", encoding="utf-8") as f:
    cp = json.load(f)
except Exception as e:
  print("cannot parse checkpoint: {}".format(e), file=sys.stderr)
  sys.exit(1)

if not isinstance(cp, dict):
  print("checkpoint must be json object", file=sys.stderr)
  sys.exit(1)

gate_result = cp.get("status", cp.get("gate_result", "ok"))
if gate_result not in ("ok", "warning", "blocked", "failed"):
  gate_result = "ok"

mode = cp.get("mode") or "serial"
if mode not in ("parallel", "serial", "tdd"):
  mode = "serial"

ts_start = cp.get("timestamp_start") or time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
ts_end = cp.get("timestamp_end") or time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
duration_ms = int(cp.get("duration_ms", 0) or 0)

actions = cp.get("actions") or []
if not isinstance(actions, list):
  actions = []

episode = {
  "version": "1.0",
  "run_id": run_id,
  "phase": phase,
  "phase_name": cp.get("phase_name") or phase,
  "mode": mode,
  "goal": cp.get("goal") or cp.get("summary") or "",
  "timestamp_start": ts_start,
  "timestamp_end": ts_end,
  "duration_ms": duration_ms,
  "gate_result": gate_result,
  "actions": actions,
}

if gate_result in ("blocked", "failed"):
  ftrace = cp.get("failure_trace")
  if not isinstance(ftrace, dict):
    ftrace = {
      "root_cause": cp.get("root_cause") or "unknown",
      "failed_gate": cp.get("failed_gate") or "unknown",
      "evidence": cp.get("evidence") or cp.get("summary") or "",
    }
  episode["failure_trace"] = ftrace
  # Reflexion-style 自然语言反思（占位：若无 AI 反思则合成默认）
  reflection = cp.get("reflection")
  if not reflection:
    reflection = (
      "Observation: {}\n"
      "Reasoning: phase {} failed at gate {} due to {}.\n"
      "Plan: next run must verify this root_cause before dispatch."
    ).format(
      ftrace.get("evidence", ""),
      phase,
      ftrace.get("failed_gate", ""),
      ftrace.get("root_cause", ""),
    )
  episode["reflection"] = reflection
else:
  fp = cp.get("success_fingerprint")
  if isinstance(fp, (str, dict)):
    episode["success_fingerprint"] = fp if isinstance(fp, str) else json.dumps(fp, ensure_ascii=False)

print(json.dumps(episode, ensure_ascii=False, indent=2))
PY
)
PY_EXIT=$?
if [ $PY_EXIT -ne 0 ]; then
  exit 1
fi

# Schema validation
if ! printf '%s' "$EPISODE_JSON" | bash "$VALIDATOR" --stdin; then
  echo "episode schema validation failed" >&2
  exit 1
fi

printf '%s\n' "$EPISODE_JSON" >"$EPISODE_PATH"

# 占位：调用 claude-mem MCP create_observations（dry-run 打印到 stderr）
OBS_TYPE="phase_reflection"
case "$(printf '%s' "$EPISODE_JSON" | python3 -c "import json,sys;print(json.load(sys.stdin)['gate_result'])" 2>/dev/null)" in
  blocked | failed) OBS_TYPE="failure_pattern" ;;
  ok) OBS_TYPE="success_pattern" ;;
esac

if [ "${LEARN_DRY_RUN:-1}" = "1" ]; then
  echo "[learn-episode-write] dry-run create_observations obs_type=$OBS_TYPE run_id=$RUN_ID path=$EPISODE_PATH" >&2
fi

echo "$EPISODE_PATH"
