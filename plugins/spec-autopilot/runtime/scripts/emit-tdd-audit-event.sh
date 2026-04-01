#!/usr/bin/env bash
# emit-tdd-audit-event.sh — 发射 tdd_audit 事件 (工作包 I)
# 用法: emit-tdd-audit-event.sh <changes_dir> <change_name> <mode> <session_id>
#
# Phase 5 完成后调用，收集 TDD RED-GREEN-REFACTOR 审计摘要
set -euo pipefail

CHANGES_DIR="${1:?用法: emit-tdd-audit-event.sh <changes_dir> <change_name> <mode> <session_id>}"
CHANGE_NAME="${2:?缺少 change_name}"
MODE="${3:?缺少 mode}"
SESSION_ID="${4:?缺少 session_id}"

CONTEXT_DIR="$CHANGES_DIR/$CHANGE_NAME/context"
CHECKPOINT_DIR="$CHANGES_DIR/$CHANGE_NAME/checkpoints"

# 默认值
cycle_count=0
red_violations=0
green_violations=0
refactor_rollbacks=0
red_commands="[]"
green_commands="[]"

# 从 Phase 5 task checkpoint 收集 TDD 审计数据
if [[ -d "$CHECKPOINT_DIR" ]]; then
  for cp in "$CHECKPOINT_DIR"/phase-5-task-*.json; do
    [[ -f "$cp" ]] || continue

    # 提取 TDD 证据
    tdd_step=$(jq -r '.tdd_step // ""' "$cp" 2>/dev/null || echo "")
    exit_code=$(jq -r '.exit_code // ""' "$cp" 2>/dev/null || echo "")
    command=$(jq -r '.command // ""' "$cp" 2>/dev/null || echo "")

    case "$tdd_step" in
      red)
        cycle_count=$((cycle_count + 1))
        if [[ "$exit_code" == "0" ]]; then
          red_violations=$((red_violations + 1))
        fi
        if [[ -n "$command" ]]; then
          red_commands=$(echo "$red_commands" | jq --arg cmd "$command" '. + [$cmd]')
        fi
        ;;
      green)
        if [[ "$exit_code" != "0" ]]; then
          green_violations=$((green_violations + 1))
        fi
        if [[ -n "$command" ]]; then
          green_commands=$(echo "$green_commands" | jq --arg cmd "$command" '. + [$cmd]')
        fi
        ;;
      refactor)
        # 检查是否有回滚标记
        rollback=$(jq -r '.rollback // false' "$cp" 2>/dev/null || echo "false")
        if [[ "$rollback" == "true" ]]; then
          refactor_rollbacks=$((refactor_rollbacks + 1))
        fi
        ;;
    esac
  done
fi

# 从 tdd-audit.json 读取（如果存在更权威的来源）
if [[ -f "$CONTEXT_DIR/tdd-audit.json" ]]; then
  cycle_count=$(jq -r '.cycle_count // 0' "$CONTEXT_DIR/tdd-audit.json" 2>/dev/null || echo "$cycle_count")
  red_violations=$(jq -r '.red_violations // 0' "$CONTEXT_DIR/tdd-audit.json" 2>/dev/null || echo "$red_violations")
  green_violations=$(jq -r '.green_violations // 0' "$CONTEXT_DIR/tdd-audit.json" 2>/dev/null || echo "$green_violations")
  refactor_rollbacks=$(jq -r '.refactor_rollbacks // 0' "$CONTEXT_DIR/tdd-audit.json" 2>/dev/null || echo "$refactor_rollbacks")
  red_commands=$(jq -c '.red_commands // []' "$CONTEXT_DIR/tdd-audit.json" 2>/dev/null || echo "$red_commands")
  green_commands=$(jq -c '.green_commands // []' "$CONTEXT_DIR/tdd-audit.json" 2>/dev/null || echo "$green_commands")
fi

# 构建事件 payload
PAYLOAD=$(jq -n \
  --argjson cycle_count "$cycle_count" \
  --argjson red_violations "$red_violations" \
  --argjson green_violations "$green_violations" \
  --argjson refactor_rollbacks "$refactor_rollbacks" \
  --argjson red_commands "$red_commands" \
  --argjson green_commands "$green_commands" \
  '{
    cycle_count: $cycle_count,
    red_violations: $red_violations,
    green_violations: $green_violations,
    refactor_rollbacks: $refactor_rollbacks,
    red_commands: $red_commands,
    green_commands: $green_commands
  }')

# 发射事件
EVENTS_FILE="$CHANGES_DIR/$CHANGE_NAME/logs/events.jsonl"
mkdir -p "$(dirname "$EVENTS_FILE")"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
EVENT_ID="tdd-audit-$(date +%s%N 2>/dev/null || date +%s)"

jq -n -c \
  --arg type "tdd_audit" \
  --argjson phase 5 \
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
    phase_label: "代码实施",
    total_phases: 8,
    payload: $payload
  }' >>"$EVENTS_FILE"

# 同时写入 state-snapshot 的 tdd_audit
if [[ -f "$CONTEXT_DIR/state-snapshot.json" ]]; then
  TMP_SNAPSHOT=$(mktemp)
  jq --argjson audit "$PAYLOAD" '.tdd_audit = $audit' "$CONTEXT_DIR/state-snapshot.json" >"$TMP_SNAPSHOT" &&
    mv "$TMP_SNAPSHOT" "$CONTEXT_DIR/state-snapshot.json"
fi

echo "$PAYLOAD"
