#!/usr/bin/env bash
# test_model_routing_observability.sh — 模型路由可观测性测试 (v5.4)
# 覆盖: emit 三种事件类型、GUI store 消费、事件写入 events.jsonl
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 模型路由可观测性测试 (v5.4) ---"
setup_autopilot_fixture

# ── 工具函数 ──
extract_json_field() {
  local json="$1" field="$2"
  python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('$field', d.get('payload',{}).get('$field','')))" <<< "$json" 2>/dev/null || echo ""
}

extract_payload_field() {
  local json="$1" field="$2"
  python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('payload',{}).get('$field',''))" <<< "$json" 2>/dev/null || echo ""
}

# =============================================================================
# A. emit-model-routing-event.sh 三种事件类型
# =============================================================================
echo ""
echo "--- A. 三种事件类型发射 ---"

EMIT_ROOT=$(mktemp -d)
mkdir -p "$EMIT_ROOT/openspec/changes" "$EMIT_ROOT/logs"
echo '{"change":"test-mr","session_id":"sess-mr-001","mode":"full"}' > "$EMIT_ROOT/openspec/changes/.autopilot-active"

# A1. model_routing (默认)
ROUTING_JSON='{"selected_tier":"deep","selected_model":"opus","selected_effort":"high","routing_reason":"Phase 1 default","escalated_from":null,"fallback_applied":false,"fallback_model":null}'
output=$(bash "$SCRIPT_DIR/emit-model-routing-event.sh" "$EMIT_ROOT" 1 full "$ROUTING_JSON" "" 2>/dev/null)
event_type=$(extract_json_field "$output" "type")
assert_exit "A1. model_routing 事件类型" 0 $?
if [ "$event_type" = "model_routing" ]; then
  green "  PASS: A1. type=model_routing"
  PASS=$((PASS + 1))
else
  red "  FAIL: A1. expected type=model_routing, got '$event_type'"
  FAIL=$((FAIL + 1))
fi
tier=$(extract_payload_field "$output" "selected_tier")
assert_contains "A1. payload.selected_tier=deep" "$tier" "deep"

# A2. model_effective
EFFECTIVE_JSON='{"effective_model":"claude-opus-4-1","effective_tier":"deep","inference_source":"statusline","requested_model":"opus","match":true}'
output=$(bash "$SCRIPT_DIR/emit-model-routing-event.sh" "$EMIT_ROOT" 1 full "$EFFECTIVE_JSON" "agent-p1" "model_effective" 2>/dev/null)
event_type=$(extract_json_field "$output" "type")
if [ "$event_type" = "model_effective" ]; then
  green "  PASS: A2. type=model_effective"
  PASS=$((PASS + 1))
else
  red "  FAIL: A2. expected type=model_effective, got '$event_type'"
  FAIL=$((FAIL + 1))
fi
eff_model=$(extract_payload_field "$output" "effective_model")
assert_contains "A2. payload.effective_model=claude-opus-4-1" "$eff_model" "claude-opus-4-1"
agent_id=$(extract_payload_field "$output" "agent_id")
assert_contains "A2. payload.agent_id=agent-p1" "$agent_id" "agent-p1"

# A3. model_fallback
FALLBACK_JSON='{"requested_model":"opus","fallback_model":"sonnet","fallback_reason":"Rate limit exceeded"}'
output=$(bash "$SCRIPT_DIR/emit-model-routing-event.sh" "$EMIT_ROOT" 5 full "$FALLBACK_JSON" "" "model_fallback" 2>/dev/null)
event_type=$(extract_json_field "$output" "type")
if [ "$event_type" = "model_fallback" ]; then
  green "  PASS: A3. type=model_fallback"
  PASS=$((PASS + 1))
else
  red "  FAIL: A3. expected type=model_fallback, got '$event_type'"
  FAIL=$((FAIL + 1))
fi
fb_reason=$(extract_payload_field "$output" "fallback_reason")
assert_contains "A3. payload.fallback_reason 包含 Rate limit" "$fb_reason" "Rate limit"

# A4. 无效事件类型拒绝
output=$(bash "$SCRIPT_DIR/emit-model-routing-event.sh" "$EMIT_ROOT" 1 full '{}' "" "model_invalid" 2>&1)
code=$?
if [ "$code" -ne 0 ]; then
  green "  PASS: A4. 无效事件类型 → exit ≠ 0"
  PASS=$((PASS + 1))
else
  red "  FAIL: A4. 无效事件类型应 exit ≠ 0 (got exit 0)"
  FAIL=$((FAIL + 1))
fi

# =============================================================================
# B. events.jsonl 追加验证
# =============================================================================
echo ""
echo "--- B. events.jsonl 追加验证 ---"

# B1. 检查 events.jsonl 有 3 条事件（A1 + A2 + A3）
line_count=$(wc -l < "$EMIT_ROOT/logs/events.jsonl" | tr -d ' ')
if [ "$line_count" -ge 3 ]; then
  green "  PASS: B1. events.jsonl 至少 3 行 (got $line_count)"
  PASS=$((PASS + 1))
else
  red "  FAIL: B1. events.jsonl 行数不足 (expected >= 3, got $line_count)"
  FAIL=$((FAIL + 1))
fi

# B2. 验证包含三种事件类型
has_routing=$(grep -c '"model_routing"' "$EMIT_ROOT/logs/events.jsonl" || true)
has_effective=$(grep -c '"model_effective"' "$EMIT_ROOT/logs/events.jsonl" || true)
has_fallback=$(grep -c '"model_fallback"' "$EMIT_ROOT/logs/events.jsonl" || true)
if [ "$has_routing" -ge 1 ] && [ "$has_effective" -ge 1 ] && [ "$has_fallback" -ge 1 ]; then
  green "  PASS: B2. events.jsonl 包含三种事件类型"
  PASS=$((PASS + 1))
else
  red "  FAIL: B2. 缺少事件类型 (routing=$has_routing, effective=$has_effective, fallback=$has_fallback)"
  FAIL=$((FAIL + 1))
fi

# =============================================================================
# C. 默认事件类型向后兼容
# =============================================================================
echo ""
echo "--- C. 向后兼容 ---"

# C1. 不传 event_type 参数 → 默认 model_routing
COMPAT_ROOT=$(mktemp -d)
mkdir -p "$COMPAT_ROOT/openspec/changes" "$COMPAT_ROOT/logs"
echo '{"change":"test-compat","session_id":"sess-compat","mode":"full"}' > "$COMPAT_ROOT/openspec/changes/.autopilot-active"

output=$(bash "$SCRIPT_DIR/emit-model-routing-event.sh" "$COMPAT_ROOT" 1 full '{"selected_tier":"fast","selected_model":"haiku"}' 2>/dev/null)
event_type=$(extract_json_field "$output" "type")
if [ "$event_type" = "model_routing" ]; then
  green "  PASS: C1. 默认 event_type=model_routing（向后兼容）"
  PASS=$((PASS + 1))
else
  red "  FAIL: C1. 默认事件类型不是 model_routing (got '$event_type')"
  FAIL=$((FAIL + 1))
fi

rm -rf "$COMPAT_ROOT"

# =============================================================================
# D. model_effective match=false 场景（平台限制）
# =============================================================================
echo ""
echo "--- D. 平台限制场景 ---"

# D1. match=false 表示实际模型与请求不一致
MISMATCH_JSON='{"effective_model":"claude-sonnet-4-5","effective_tier":"standard","inference_source":"statusline","requested_model":"opus","match":false}'
output=$(bash "$SCRIPT_DIR/emit-model-routing-event.sh" "$EMIT_ROOT" 1 full "$MISMATCH_JSON" "" "model_effective" 2>/dev/null)
match_val=$(extract_payload_field "$output" "match")
if [ "$match_val" = "False" ] || [ "$match_val" = "false" ]; then
  green "  PASS: D1. match=false 正确传递"
  PASS=$((PASS + 1))
else
  red "  FAIL: D1. match 字段异常 (got '$match_val')"
  FAIL=$((FAIL + 1))
fi

rm -rf "$EMIT_ROOT"

teardown_autopilot_fixture
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0
