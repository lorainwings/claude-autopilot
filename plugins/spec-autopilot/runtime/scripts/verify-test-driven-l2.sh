#!/usr/bin/env bash
# verify-test-driven-l2.sh — Phase 5 L2 test_driven_evidence 验证闭环
#
# 用法: verify-test-driven-l2.sh <task_checkpoint_path>
#
# 由主线程在写入 task checkpoint 后调用，校验 test_driven_evidence 字段完整性。
# 这是非 TDD full 模式下 L2 RED/GREEN 验证的**唯一运行时闭环点**。
#
# 输出 (stdout):
#   JSON: {"status": "ok|warn", "message": "...", "red_verified": bool, "green_verified": bool}
#
# 退出码: 始终 0（不阻断流程，warn 级别由主线程决策）
set -euo pipefail

CHECKPOINT_PATH="${1:?用法: verify-test-driven-l2.sh <task_checkpoint_path>}"

if [[ ! -f "$CHECKPOINT_PATH" ]]; then
  echo '{"status":"warn","message":"task checkpoint file not found","red_verified":false,"green_verified":false}'
  exit 0
fi

# 提取 test_driven_evidence 字段
TDE=$(jq -c '.test_driven_evidence // null' "$CHECKPOINT_PATH" 2>/dev/null || echo "null")

if [[ "$TDE" == "null" ]]; then
  echo '{"status":"warn","message":"test_driven_evidence missing from task checkpoint","red_verified":false,"green_verified":false}'
  exit 0
fi

RED_VERIFIED=$(echo "$TDE" | jq -r '.red_verified // false' 2>/dev/null || echo "false")
GREEN_VERIFIED=$(echo "$TDE" | jq -r '.green_verified // false' 2>/dev/null || echo "false")
VERIFICATION_LAYER=$(echo "$TDE" | jq -r '.verification_layer // "unknown"' 2>/dev/null || echo "unknown")
RED_SKIPPED=$(echo "$TDE" | jq -r '.red_skipped_reason // ""' 2>/dev/null || echo "")

# 构建结果
# 关键: verification_layer 必须是 L2_main_thread 才算 L2 闭环验证通过
# L1_sub_agent 或 unknown 层的证据即使 red/green 都 true 也只能是 warn
if [[ "$VERIFICATION_LAYER" != "L2_main_thread" ]]; then
  jq -n -c \
    --arg status "warn" \
    --arg message "verification_layer is '$VERIFICATION_LAYER' (expected 'L2_main_thread') — L1 evidence cannot close L2 loop" \
    --argjson red "$([[ "$RED_VERIFIED" == "true" ]] && echo "true" || echo "false")" \
    --argjson green "$([[ "$GREEN_VERIFIED" == "true" ]] && echo "true" || echo "false")" \
    '{status: $status, message: $message, red_verified: $red, green_verified: $green}'
elif [[ "$RED_VERIFIED" == "true" && "$GREEN_VERIFIED" == "true" ]]; then
  jq -n -c \
    --arg status "ok" \
    --arg message "L2 RED→GREEN transition verified (layer: $VERIFICATION_LAYER)" \
    --argjson red true \
    --argjson green true \
    '{status: $status, message: $message, red_verified: $red, green_verified: $green}'
elif [[ "$RED_VERIFIED" != "true" && -n "$RED_SKIPPED" ]]; then
  jq -n -c \
    --arg status "warn" \
    --arg message "RED skipped ($RED_SKIPPED) — cannot prove RED→GREEN transition" \
    --argjson red false \
    --argjson green "$([[ "$GREEN_VERIFIED" == "true" ]] && echo "true" || echo "false")" \
    '{status: $status, message: $message, red_verified: $red, green_verified: $green}'
elif [[ "$GREEN_VERIFIED" != "true" ]]; then
  jq -n -c \
    --arg status "warn" \
    --arg message "GREEN not verified — implementation may not satisfy Phase 4 tests" \
    --argjson red "$([[ "$RED_VERIFIED" == "true" ]] && echo "true" || echo "false")" \
    --argjson green false \
    '{status: $status, message: $message, red_verified: $red, green_verified: $green}'
else
  jq -n -c \
    --arg status "warn" \
    --arg message "Unexpected test_driven_evidence state (red=$RED_VERIFIED, green=$GREEN_VERIFIED)" \
    --argjson red "$([[ "$RED_VERIFIED" == "true" ]] && echo "true" || echo "false")" \
    --argjson green "$([[ "$GREEN_VERIFIED" == "true" ]] && echo "true" || echo "false")" \
    '{status: $status, message: $message, red_verified: $red, green_verified: $green}'
fi
