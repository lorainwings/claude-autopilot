#!/usr/bin/env bash
# feedback-loop-inject.sh — C4 闭环回灌：将 risk-report 中 severity>=warn 的失败条目
# 转为 sub-agent task envelope 的 prior_risks[] JSON 数组。
#
# Usage:
#   feedback-loop-inject.sh --change-root <path> --phase <N>
#
# 行为：
#   - 报告不存在 → stdout `[]`，exit 0
#   - 报告存在 → 解析 scored_rubrics，过滤 (severity in {warn,block} AND passed=false)
#                输出 JSON 数组，每项含 check_id / severity / evidence / reasoning / source_phase
#
# Stdout: JSON 数组
# Stderr: 诊断

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
  # fail-open: 无报告 → 空数组（调用方需独立判定是否需要 risk-scan-gate.sh）
  echo "[]"
  exit 0
fi

python3 - "$REPORT" "$PHASE" <<'PY'
import json
import sys

path = sys.argv[1]
phase = sys.argv[2]

try:
    with open(path) as f:
        data = json.load(f)
except Exception as e:
    print("[]")
    sys.stderr.write(f"WARN: cannot parse {path}: {e}\n")
    sys.exit(0)

scored = data.get("scored_rubrics", [])
out = []
for item in scored:
    if not isinstance(item, dict):
        continue
    sev = item.get("severity", "")
    passed = item.get("passed", True)
    if sev in ("warn", "block") and passed is False:
        out.append({
            "check_id": item.get("check_id", ""),
            "severity": sev,
            "evidence": item.get("evidence", ""),
            "reasoning": item.get("reasoning", ""),
            "source_phase": phase,
        })

print(json.dumps(out, ensure_ascii=False))
PY
