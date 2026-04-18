#!/usr/bin/env bash
# engineering-sync-gate.sh — 工程化自动同步聚合入口
#
# 职责：
#   - 并行调用 detect-doc-drift.sh + detect-test-rot.sh
#   - 汇总到 .engineering-sync-report.json
#   - 根据 autopilot.config.yaml 的 engineering_auto_sync.enabled 决定模式
#
# 输入：
#   --changed-files "<staged files>" [--deleted-files "<deleted files>"]
#
# 输出：
#   stdout: ENGINEERING_SYNC_MODE=warn|block / 摘要
#   file: <project_root>/.engineering-sync-report.json
#
# 退出码：
#   0: soft 模式（默认）或 enabled=true 但无候选
#   1: enabled=true 且发现候选（block 模式）

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "$SCRIPT_DIR/_common.sh"

CHANGED_FILES=""
DELETED_FILES=""
while [ $# -gt 0 ]; do
  case "$1" in
    --changed-files)
      CHANGED_FILES="${2:-}"
      shift 2
      ;;
    --deleted-files)
      DELETED_FILES="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

PROJECT_ROOT=$(resolve_project_root)
REPORT_FILE="$PROJECT_ROOT/.engineering-sync-report.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# --- 读 config ---
ENABLED=$(read_config_value "$PROJECT_ROOT" "engineering_auto_sync.enabled" "false")
MODE="warn"
if [ "$ENABLED" = "true" ]; then
  MODE="block"
fi

# --- 调用子检测器 ---
DOC_OUT=$(AUTOPILOT_PROJECT_ROOT="$PROJECT_ROOT" \
  "$SCRIPT_DIR/detect-doc-drift.sh" --changed-files "$CHANGED_FILES" 2>&1 || true)
ROT_OUT=$(AUTOPILOT_PROJECT_ROOT="$PROJECT_ROOT" \
  "$SCRIPT_DIR/detect-test-rot.sh" --changed-files "$CHANGED_FILES" --deleted-files "$DELETED_FILES" 2>&1 || true)

DOC_COUNT=$(echo "$DOC_OUT" | grep -oE 'DRIFT_CANDIDATES=[0-9]+' | head -1 | sed 's/DRIFT_CANDIDATES=//')
ROT_COUNT=$(echo "$ROT_OUT" | grep -oE 'ROT_CANDIDATES=[0-9]+' | head -1 | sed 's/ROT_CANDIDATES=//')
DOC_COUNT="${DOC_COUNT:-0}"
ROT_COUNT="${ROT_COUNT:-0}"

# --- 聚合报告 ---
DRIFT_FILE="$PROJECT_ROOT/.drift-candidates.json"
ROT_FILE="$PROJECT_ROOT/.test-rot-candidates.json"

python3 -c "
import json, os
report = {
  'timestamp': '$TIMESTAMP',
  'mode': '$MODE',
  'enabled': $([ "$ENABLED" = "true" ] && echo "True" || echo "False"),
  'doc_drift': {'count': $DOC_COUNT, 'candidates': []},
  'test_rot': {'count': $ROT_COUNT, 'candidates': []},
}
for key, path in [('doc_drift', '$DRIFT_FILE'), ('test_rot', '$ROT_FILE')]:
    if os.path.exists(path):
        try:
            with open(path) as f:
                data = json.load(f)
            report[key]['candidates'] = data.get('checks', [])
        except Exception:
            pass
with open('$REPORT_FILE', 'w') as f:
    json.dump(report, f, indent=2)
"

TOTAL=$((DOC_COUNT + ROT_COUNT))
echo "ENGINEERING_SYNC_MODE=$MODE"
echo "DRIFT_CANDIDATES=$DOC_COUNT"
echo "ROT_CANDIDATES=$ROT_COUNT"
echo "TOTAL_CANDIDATES=$TOTAL"

if [ "$MODE" = "block" ] && [ "$TOTAL" -gt 0 ]; then
  echo "ENGINEERING_SYNC_RESULT=blocked"
  echo "See $REPORT_FILE for details."
  exit 1
fi

echo "ENGINEERING_SYNC_RESULT=ok"
exit 0
