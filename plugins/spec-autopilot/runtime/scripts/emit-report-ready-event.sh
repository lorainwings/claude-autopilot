#!/usr/bin/env bash
# emit-report-ready-event.sh — 发射 report_ready 事件 (工作包 D)
# 用法: emit-report-ready-event.sh <changes_dir> <change_name> <mode> <session_id>
#
# Phase 6 完成时调用，将测试报告产物信息结构化发射为事件
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=emit-phase-event.sh
source "$SCRIPT_DIR/emit-phase-event.sh" 2>/dev/null || true

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

# 扫描报告产物
if [[ -f "$CONTEXT_DIR/test-report.json" ]]; then
  report_format=$(jq -r '.format // "custom"' "$CONTEXT_DIR/test-report.json" 2>/dev/null || echo "custom")
  report_path=$(jq -r '.path // ""' "$CONTEXT_DIR/test-report.json" 2>/dev/null || echo "")
  report_url=$(jq -r '.url // ""' "$CONTEXT_DIR/test-report.json" 2>/dev/null || echo "")
  suite_total=$(jq -r '.suite_results.total // 0' "$CONTEXT_DIR/test-report.json" 2>/dev/null || echo "0")
  suite_passed=$(jq -r '.suite_results.passed // 0' "$CONTEXT_DIR/test-report.json" 2>/dev/null || echo "0")
  suite_failed=$(jq -r '.suite_results.failed // 0' "$CONTEXT_DIR/test-report.json" 2>/dev/null || echo "0")
  suite_skipped=$(jq -r '.suite_results.skipped // 0' "$CONTEXT_DIR/test-report.json" 2>/dev/null || echo "0")
  suite_error=$(jq -r '.suite_results.error // 0' "$CONTEXT_DIR/test-report.json" 2>/dev/null || echo "0")
  anomaly_alerts=$(jq -c '.anomaly_alerts // []' "$CONTEXT_DIR/test-report.json" 2>/dev/null || echo "[]")
fi

# 检查 Allure 产物
if [[ -d "$REPORT_DIR/allure-results" ]]; then
  allure_results_dir="$REPORT_DIR/allure-results"
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
EVENTS_FILE="$CHANGES_DIR/$CHANGE_NAME/logs/events.jsonl"
mkdir -p "$(dirname "$EVENTS_FILE")"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
EVENT_ID="report-ready-$(date +%s%N 2>/dev/null || date +%s)"

jq -n -c \
  --arg type "report_ready" \
  --argjson phase 6 \
  --arg mode "$MODE" \
  --arg timestamp "$TIMESTAMP" \
  --arg change_name "$CHANGE_NAME" \
  --arg session_id "$SESSION_ID" \
  --arg event_id "$EVENT_ID" \
  --argjson payload "$PAYLOAD" \
  '{
    type: $type,
    phase: $phase,
    mode: $mode,
    timestamp: $timestamp,
    change_name: $change_name,
    session_id: $session_id,
    event_id: $event_id,
    sequence: 0,
    phase_label: "测试报告",
    total_phases: 8,
    payload: $payload
  }' >>"$EVENTS_FILE"

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
