#!/usr/bin/env bash
# learn-episode-schema-validate.sh
# 校验 L1 Episode JSON 是否满足 episode-schema.md 定义的必填字段
#
# 用法:
#   learn-episode-schema-validate.sh --file <path-to-episode.json>
#   learn-episode-schema-validate.sh --stdin  # 从 stdin 读取 JSON
#
# 退出码:
#   0 — schema 合法
#   1 — schema 非法（stderr 输出原因）
#   2 — 参数/环境错误

set -uo pipefail

MODE=""
FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --file)
      MODE="file"
      FILE="${2:-}"
      shift 2
      ;;
    --stdin)
      MODE="stdin"
      shift
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [ -z "$MODE" ]; then
  echo "must specify --file <path> or --stdin" >&2
  exit 2
fi

if [ "$MODE" = "file" ]; then
  if [ ! -f "$FILE" ]; then
    echo "file not found: $FILE" >&2
    exit 2
  fi
  JSON_INPUT=$(cat "$FILE")
else
  JSON_INPUT=$(cat)
fi

python3 - "$JSON_INPUT" <<'PY'
import json
import sys

REQUIRED = [
  "version",
  "run_id",
  "phase",
  "phase_name",
  "mode",
  "goal",
  "timestamp_start",
  "timestamp_end",
  "duration_ms",
  "gate_result",
  "actions",
]
ALLOWED_GATE = {"ok", "warning", "blocked", "failed"}
ALLOWED_MODE = {"parallel", "serial", "tdd"}

raw = sys.argv[1] if len(sys.argv) > 1 else ""
try:
  data = json.loads(raw)
except Exception as e:
  print("invalid json: {}".format(e), file=sys.stderr)
  sys.exit(1)

if not isinstance(data, dict):
  print("episode must be a JSON object", file=sys.stderr)
  sys.exit(1)

missing = [k for k in REQUIRED if k not in data]
if missing:
  print("missing required fields: {}".format(missing), file=sys.stderr)
  sys.exit(1)

if data["gate_result"] not in ALLOWED_GATE:
  print("invalid gate_result: {}".format(data["gate_result"]), file=sys.stderr)
  sys.exit(1)

if data["mode"] not in ALLOWED_MODE:
  print("invalid mode: {}".format(data["mode"]), file=sys.stderr)
  sys.exit(1)

if not isinstance(data["actions"], list):
  print("actions must be a list", file=sys.stderr)
  sys.exit(1)

if data["gate_result"] in ("blocked", "failed"):
  if "failure_trace" not in data or not isinstance(data["failure_trace"], dict):
    print("failure_trace required when gate_result in {blocked, failed}", file=sys.stderr)
    sys.exit(1)
  if "reflection" not in data or not data["reflection"]:
    print("reflection required when gate_result in {blocked, failed}", file=sys.stderr)
    sys.exit(1)

sys.exit(0)
PY
