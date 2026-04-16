#!/usr/bin/env bash
# emit-report-ready-event.sh — 发射 report_ready 事件 (工作包 D)
# 用法: emit-report-ready-event.sh <changes_dir> <change_name> <mode> <session_id>
#
# Phase 6 完成时调用，将测试报告产物信息结构化发射为事件
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

CHANGES_DIR="${1:?用法: emit-report-ready-event.sh <changes_dir> <change_name> <mode> <session_id>}"
CHANGE_NAME="${2:?缺少 change_name}"
MODE="${3:?缺少 mode}"
SESSION_ID="${4:?缺少 session_id}"

CONTEXT_DIR="$CHANGES_DIR/$CHANGE_NAME/context"
REPORT_DIR="$CHANGES_DIR/$CHANGE_NAME/reports"

# 默认值
report_format="none"
report_path=""
report_url=""
allure_results_dir=""
allure_preview_url=""
suite_total=0
suite_passed=0
suite_failed=0
suite_skipped=0
suite_error=0
anomaly_alerts="[]"

# 从 Phase 6 正式 checkpoint 读取报告数据（权威来源）
PHASE6_CHECKPOINT="$CONTEXT_DIR/phase-results/phase-6-report.json"
if [[ -f "$PHASE6_CHECKPOINT" ]]; then
  report_format=$(jq -r '.report_format // "custom"' "$PHASE6_CHECKPOINT" 2>/dev/null || echo "custom")
  report_path=$(jq -r '.report_path // ""' "$PHASE6_CHECKPOINT" 2>/dev/null || echo "")
  report_url=$(jq -r '.report_url // ""' "$PHASE6_CHECKPOINT" 2>/dev/null || echo "")
  # suite_results 在 phase-6-report.json 中是套件数组 [{suite, total, passed, failed, skipped}]，需聚合为总计
  suite_total=$(jq '[.suite_results[]?.total // 0] | add // 0' "$PHASE6_CHECKPOINT" 2>/dev/null || echo "0")
  suite_passed=$(jq '[.suite_results[]?.passed // 0] | add // 0' "$PHASE6_CHECKPOINT" 2>/dev/null || echo "0")
  suite_failed=$(jq '[.suite_results[]?.failed // 0] | add // 0' "$PHASE6_CHECKPOINT" 2>/dev/null || echo "0")
  suite_skipped=$(jq '[.suite_results[]?.skipped // 0] | add // 0' "$PHASE6_CHECKPOINT" 2>/dev/null || echo "0")
  suite_error=$(jq '[.suite_results[]?.error // 0] | add // 0' "$PHASE6_CHECKPOINT" 2>/dev/null || echo "0")
  anomaly_alerts=$(jq -c '.anomaly_alerts // []' "$PHASE6_CHECKPOINT" 2>/dev/null || echo "[]")
  # 从 checkpoint 读取 allure_results_dir（仅当目录实际存在时采用）
  checkpoint_allure_dir=$(jq -r '.allure_results_dir // ""' "$PHASE6_CHECKPOINT" 2>/dev/null || echo "")
  if [[ -n "$checkpoint_allure_dir" && -d "$checkpoint_allure_dir" ]]; then
    allure_results_dir="$checkpoint_allure_dir"
  fi
fi

# 检查 Allure 产物（多路径兼容：change 级 reports/ + 工作目录根 allure-results/）
if [[ -z "$allure_results_dir" ]]; then
  if [[ -d "$REPORT_DIR/allure-results" ]]; then
    allure_results_dir="$REPORT_DIR/allure-results"
    report_format="allure"
  fi
fi
# Phase 6 模板默认输出到工作目录根 allure-results/
PROJECT_ROOT=$(cd "$CHANGES_DIR/../.." 2>/dev/null && pwd || pwd)
if [[ -z "$allure_results_dir" && -d "$PROJECT_ROOT/allure-results" ]]; then
  allure_results_dir="$PROJECT_ROOT/allure-results"
  report_format="allure"
fi

# 检查 Allure 预览服务器
if [[ -f "$CONTEXT_DIR/allure-preview.json" ]]; then
  allure_preview_url=$(jq -r '.url // ""' "$CONTEXT_DIR/allure-preview.json" 2>/dev/null || echo "")
fi

# 检查 JUnit XML
if [[ -d "$REPORT_DIR" ]] && ls "$REPORT_DIR"/*.xml &>/dev/null; then
  if [[ "$report_format" == "none" ]]; then
    report_format="junit"
    report_path="$REPORT_DIR"
  fi
fi

# minimal 模式: 显式标记无报告
if [[ "$MODE" == "minimal" ]]; then
  report_format="none"
  report_path=""
  report_url=""
fi

# 构建事件 payload
PAYLOAD=$(jq -n \
  --arg report_format "$report_format" \
  --arg report_path "$report_path" \
  --arg report_url "$report_url" \
  --arg allure_results_dir "$allure_results_dir" \
  --arg allure_preview_url "$allure_preview_url" \
  --argjson suite_total "$suite_total" \
  --argjson suite_passed "$suite_passed" \
  --argjson suite_failed "$suite_failed" \
  --argjson suite_skipped "$suite_skipped" \
  --argjson suite_error "$suite_error" \
  --argjson anomaly_alerts "$anomaly_alerts" \
  '{
    report_format: $report_format,
    report_path: $report_path,
    report_url: $report_url,
    allure_results_dir: $allure_results_dir,
    allure_preview_url: $allure_preview_url,
    suite_results: {
      total: $suite_total,
      passed: $suite_passed,
      failed: $suite_failed,
      skipped: $suite_skipped,
      error: $suite_error
    },
    anomaly_alerts: $anomaly_alerts
  }')

# 发射事件到 events.jsonl
# 写入 change 级日志（向后兼容）
EVENTS_FILE="$CHANGES_DIR/$CHANGE_NAME/logs/events.jsonl"
mkdir -p "$(dirname "$EVENTS_FILE")"

# 同时写入项目根 logs/events.jsonl（服务端归一化读取源）
PROJECT_ROOT=$(cd "$CHANGES_DIR/../.." 2>/dev/null && pwd || pwd)
PROJECT_EVENTS_DIR="$PROJECT_ROOT/logs"
PROJECT_EVENTS_FILE="$PROJECT_EVENTS_DIR/events.jsonl"
mkdir -p "$PROJECT_EVENTS_DIR" 2>/dev/null || true

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
EVENT_ID="report-ready-$(date +%s%N 2>/dev/null || date +%s)"

# Resolve dynamic sequence / total_phases / phase_label
SEQUENCE=$(next_event_sequence "$PROJECT_ROOT")
TOTAL_PHASES=$(get_total_phases "$MODE")
PHASE_LABEL=$(get_phase_label 6)

EVENT_JSON=$(jq -n -c \
  --arg type "report_ready" \
  --argjson phase 6 \
  --arg mode "$MODE" \
  --arg timestamp "$TIMESTAMP" \
  --arg change_name "$CHANGE_NAME" \
  --arg session_id "$SESSION_ID" \
  --arg event_id "$EVENT_ID" \
  --argjson sequence "$SEQUENCE" \
  --arg phase_label "$PHASE_LABEL" \
  --argjson total_phases "$TOTAL_PHASES" \
  --argjson payload "$PAYLOAD" \
  '{
    type: $type,
    phase: $phase,
    mode: $mode,
    timestamp: $timestamp,
    change_name: $change_name,
    session_id: $session_id,
    event_id: $event_id,
    sequence: $sequence,
    phase_label: $phase_label,
    total_phases: $total_phases,
    payload: $payload
  }')

# 写入 change 级日志（向后兼容）
echo "$EVENT_JSON" >>"$EVENTS_FILE"

# 写入项目根 logs/events.jsonl（服务端归一化读取源）
echo "$EVENT_JSON" >>"$PROJECT_EVENTS_FILE" 2>/dev/null || true

# 同时写入 state-snapshot 的 report_state
if [[ -f "$CONTEXT_DIR/state-snapshot.json" ]]; then
  REPORT_STATE=$(jq -n \
    --arg report_format "$report_format" \
    --arg report_path "$report_path" \
    --arg report_url "$report_url" \
    --arg allure_results_dir "$allure_results_dir" \
    --arg allure_preview_url "$allure_preview_url" \
    --argjson suite_total "$suite_total" \
    --argjson suite_passed "$suite_passed" \
    --argjson suite_failed "$suite_failed" \
    --argjson suite_skipped "$suite_skipped" \
    --argjson suite_error "$suite_error" \
    --argjson anomaly_alerts "$anomaly_alerts" \
    '{
      report_format: $report_format,
      report_path: $report_path,
      report_url: $report_url,
      allure_results_dir: $allure_results_dir,
      allure_preview_url: $allure_preview_url,
      suite_results: {
        total: $suite_total,
        passed: $suite_passed,
        failed: $suite_failed,
        skipped: $suite_skipped,
        error: $suite_error
      },
      anomaly_alerts: $anomaly_alerts
    }')

  # 更新 state-snapshot.json 中的 report_state
  TMP_SNAPSHOT=$(mktemp)
  jq --argjson rs "$REPORT_STATE" '.report_state = $rs' "$CONTEXT_DIR/state-snapshot.json" >"$TMP_SNAPSHOT" &&
    mv "$TMP_SNAPSHOT" "$CONTEXT_DIR/state-snapshot.json"
fi

echo "$PAYLOAD"
