#!/usr/bin/env bash
# risk-scan-gate.sh — autopilot Gate 第 0 步预检
#
# 读取 Critic Agent 产出的 risk-report-phase{N}.json，
# 根据 blocking_count 决定是否放行。
#
# Usage:
#   risk-scan-gate.sh --change-root <path> --phase <N>
#
# Exit codes:
#   0  — 放行 (无 blocking 条目)
#   1  — 阻断 (blocking_count > 0)
#   2  — 报告缺失 (fail-closed)
#   3  — 报告 schema 非法
#
# Stdout: 人类可读摘要
# Stderr: 错误诊断

set -uo pipefail

CHANGE_ROOT=""
PHASE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --change-root)
      CHANGE_ROOT="${2:-}"
      shift 2
      ;;
    --phase)
      PHASE="${2:-}"
      shift 2
      ;;
    -h | --help)
      sed -n '2,15p' "$0"
      exit 0
      ;;
    *)
      echo "ERROR: unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

if [ -z "$CHANGE_ROOT" ] || [ -z "$PHASE" ]; then
  echo "ERROR: --change-root and --phase are required" >&2
  exit 2
fi

REPORT="$CHANGE_ROOT/context/risk-report-phase${PHASE}.json"

if [ ! -f "$REPORT" ]; then
  echo "ERROR: risk report missing: $REPORT" >&2
  echo "fail-closed: dispatch autopilot-risk-scanner Critic Agent first" >&2
  exit 2
fi

# 解析 JSON（用 python3 保证 macOS/Linux 通用）
PARSED=$(
  python3 - "$REPORT" <<'PY' 2>&1
import json
import sys

path = sys.argv[1]
try:
    with open(path) as f:
        data = json.load(f)
except Exception as e:
    print(f"PARSE_ERROR:{e}")
    sys.exit(0)

required = ["phase", "rubric_version", "scored_rubrics", "blocking_count", "recommendation"]
missing = [k for k in required if k not in data]
if missing:
    print(f"SCHEMA_ERROR:missing fields {missing}")
    sys.exit(0)

if not isinstance(data["scored_rubrics"], list):
    print("SCHEMA_ERROR:scored_rubrics must be array")
    sys.exit(0)

print(f"OK:{data['blocking_count']}:{data.get('warning_count', 0)}:{data['recommendation']}")
PY
)

case "$PARSED" in
  PARSE_ERROR:*)
    echo "ERROR: cannot parse risk report JSON: ${PARSED#PARSE_ERROR:}" >&2
    exit 3
    ;;
  SCHEMA_ERROR:*)
    echo "ERROR: risk report schema invalid: ${PARSED#SCHEMA_ERROR:}" >&2
    exit 3
    ;;
  OK:*) ;;
  *)
    echo "ERROR: unexpected parser output: $PARSED" >&2
    exit 3
    ;;
esac

# OK:<blocking>:<warning>:<rec>
IFS=':' read -r _ BLOCKING WARNING REC <<<"$PARSED"

echo "risk-scan-gate: phase=$PHASE blocking=$BLOCKING warning=$WARNING recommendation=$REC"

if [ "$BLOCKING" -gt 0 ]; then
  echo "GATE BLOCKED: $BLOCKING blocking risk(s) detected — review $REPORT" >&2
  exit 1
fi

if [ "$WARNING" -gt 0 ]; then
  echo "gate proceed with $WARNING warning(s) — will be injected as prior_risks[]"
fi

exit 0
