#!/usr/bin/env bash
# test_model_routing_escalation.sh — 模型路由升级与回退测试
# 覆盖: retry escalation、fallback、dispatch 路由结果
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 模型路由升级与回退测试 ---"
setup_autopilot_fixture

# ── 工具函数 ──
extract_json_field() {
  local json="$1" field="$2"
  python3 -c "import json,sys; print(json.load(sys.stdin).get('$field',''))" <<<"$json" 2>/dev/null || echo ""
}

EMPTY_ROOT=$(mktemp -d)

# =============================================================================
# A. 升级链测试 (Escalation)
# =============================================================================
echo ""
echo "--- A. 升级链 ---"

# A1. fast + retry_count=1 -> 升级到 standard
output=$(bash "$SCRIPT_DIR/resolve-model-routing.sh" "$EMPTY_ROOT" 2 medium feature 1 false 2>/dev/null)
assert_json_field "A1. fast + retry=1 -> standard" "$output" "selected_tier" "standard"
assert_json_field "A1. escalated_from=fast" "$output" "escalated_from" "fast"

# A2. deep + retry_count=2 -> 仍为 deep（Phase 5 默认 deep，不再升级）
output=$(bash "$SCRIPT_DIR/resolve-model-routing.sh" "$EMPTY_ROOT" 5 medium feature 2 false 2>/dev/null)
assert_json_field "A2. deep + retry=2 -> 仍 deep" "$output" "selected_tier" "deep"
escalated=$(extract_json_field "$output" "escalated_from")
if [ "$escalated" = "None" ] || [ "$escalated" = "" ]; then
  green "  PASS: A2. escalated_from=None (deep 不自动升级)"
  PASS=$((PASS + 1))
else
  red "  FAIL: A2. escalated_from 应为 None (got '$escalated')"
  FAIL=$((FAIL + 1))
fi

# A3. deep + retry_count=3 -> 仍为 deep（不自动升级）
output=$(bash "$SCRIPT_DIR/resolve-model-routing.sh" "$EMPTY_ROOT" 1 medium feature 3 false 2>/dev/null)
assert_json_field "A3. deep + retry=3 -> 仍 deep" "$output" "selected_tier" "deep"

# A4. fast + retry_count=0 -> 不升级
output=$(bash "$SCRIPT_DIR/resolve-model-routing.sh" "$EMPTY_ROOT" 2 medium feature 0 false 2>/dev/null)
assert_json_field "A4. fast + retry=0 -> 不升级" "$output" "selected_tier" "fast"
escalated=$(extract_json_field "$output" "escalated_from")
if [ "$escalated" = "None" ] || [ "$escalated" = "" ]; then
  green "  PASS: A4. escalated_from=None"
  PASS=$((PASS + 1))
else
  red "  FAIL: A4. escalated_from 应为 None (got '$escalated')"
  FAIL=$((FAIL + 1))
fi

rm -rf "$EMPTY_ROOT"

# =============================================================================
# B. 配置级 escalate_on_failure_to 覆盖
# =============================================================================
echo ""
echo "--- B. escalate_on_failure_to 覆盖 ---"

ESC_ROOT=$(mktemp -d)
mkdir -p "$ESC_ROOT/.claude"

cat >"$ESC_ROOT/.claude/autopilot.config.yaml" <<'YAML'
version: "1.0"
model_routing:
  enabled: true
  phases:
    phase_5:
      tier: fast
      escalate_on_failure_to: deep
services: {}
phases:
  requirements:
    agent: "ba"
  testing:
    agent: "qa"
    gate:
      min_test_count_per_type: 3
      required_test_types: [unit]
  implementation:
    serial_task:
      max_retries_per_task: 3
  reporting:
    coverage_target: 80
    zero_skip_required: true
test_suites:
  unit:
    command: "npm test"
YAML

# B1. Phase 5 + retry=1 -> escalate_on_failure_to=deep 覆盖
output=$(bash "$SCRIPT_DIR/resolve-model-routing.sh" "$ESC_ROOT" 5 medium feature 1 false 2>/dev/null)
assert_json_field "B1. escalate_on_failure_to=deep 覆盖" "$output" "selected_tier" "deep"
assert_contains "B1. routing_reason 包含 escalate_on_failure_to" "$output" "escalate_on_failure_to"

# B2. Phase 5 + retry=0 -> 按配置 tier=fast
output=$(bash "$SCRIPT_DIR/resolve-model-routing.sh" "$ESC_ROOT" 5 medium feature 0 false 2>/dev/null)
assert_json_field "B2. 无 retry 时按配置 tier=fast" "$output" "selected_tier" "fast"

rm -rf "$ESC_ROOT"

# =============================================================================
# C. 事件发射测试
# =============================================================================
echo ""
echo "--- C. 事件发射 ---"

EVT_ROOT=$(mktemp -d)
mkdir -p "$EVT_ROOT/openspec/changes"
mkdir -p "$EVT_ROOT/logs"
echo '{"change":"test-routing","session_id":"test-session-123"}' >"$EVT_ROOT/openspec/changes/.autopilot-active"

# C1. 发射 model_routing 事件
routing_json='{"selected_tier":"deep","selected_model":"opus","selected_effort":"high","routing_reason":"test","escalated_from":null,"fallback_applied":false}'
output=$(bash "$SCRIPT_DIR/emit-model-routing-event.sh" "$EVT_ROOT" 1 full "$routing_json" "phase1-requirements" 2>/dev/null)

assert_contains "C1. 事件类型为 model_routing" "$output" "model_routing"
assert_contains "C1. 事件包含 selected_tier" "$output" "selected_tier"
assert_contains "C1. 事件包含 selected_model" "$output" "selected_model"
assert_contains "C1. 事件包含 routing_reason" "$output" "routing_reason"

# C2. 事件写入 events.jsonl
if [ -f "$EVT_ROOT/logs/events.jsonl" ]; then
  line_count=$(wc -l <"$EVT_ROOT/logs/events.jsonl")
  if [ "$line_count" -ge 1 ]; then
    green "  PASS: C2. 事件已写入 events.jsonl ($line_count 行)"
    PASS=$((PASS + 1))
  else
    red "  FAIL: C2. events.jsonl 为空"
    FAIL=$((FAIL + 1))
  fi
else
  red "  FAIL: C2. events.jsonl 未创建"
  FAIL=$((FAIL + 1))
fi

rm -rf "$EVT_ROOT"

# =============================================================================
# D. Dispatch 路由选择测试（多 phase 路由差异化）
# =============================================================================
echo ""
echo "--- D. 多 phase 路由差异化 ---"

# D1. 至少 2 个 phase 使用不同模型档位（Phase 1=deep, 2=fast, 5=deep）
D1_ROOT=$(mktemp -d)
tier_1=$(bash "$SCRIPT_DIR/resolve-model-routing.sh" "$D1_ROOT" 1 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['selected_tier'])" 2>/dev/null)
tier_2=$(bash "$SCRIPT_DIR/resolve-model-routing.sh" "$D1_ROOT" 2 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['selected_tier'])" 2>/dev/null)
tier_5=$(bash "$SCRIPT_DIR/resolve-model-routing.sh" "$D1_ROOT" 5 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['selected_tier'])" 2>/dev/null)
tier_6=$(bash "$SCRIPT_DIR/resolve-model-routing.sh" "$D1_ROOT" 6 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['selected_tier'])" 2>/dev/null)

unique_tiers=$(echo -e "$tier_1\n$tier_2\n$tier_5\n$tier_6" | sort -u | wc -l | tr -d ' ')
if [ "$unique_tiers" -ge 2 ]; then
  green "  PASS: D1. 多 phase 路由差异化 (phase1=$tier_1, phase2=$tier_2, phase5=$tier_5, phase6=$tier_6, unique=$unique_tiers)"
  PASS=$((PASS + 1))
else
  red "  FAIL: D1. 模型档位差异不足 (phase1=$tier_1, phase2=$tier_2, phase5=$tier_5, phase6=$tier_6, unique=$unique_tiers)"
  FAIL=$((FAIL + 1))
fi

rm -rf "$D1_ROOT"

# =============================================================================
# E. enabled=false 测试
# =============================================================================
echo ""
echo "--- E. enabled=false ---"

DISABLED_ROOT=$(mktemp -d)
mkdir -p "$DISABLED_ROOT/.claude"

cat >"$DISABLED_ROOT/.claude/autopilot.config.yaml" <<'YAML'
version: "1.0"
model_routing:
  enabled: false
  phases:
    phase_1:
      tier: fast
services: {}
phases:
  requirements:
    agent: "ba"
  testing:
    agent: "qa"
    gate:
      min_test_count_per_type: 3
      required_test_types: [unit]
  implementation:
    serial_task:
      max_retries_per_task: 3
  reporting:
    coverage_target: 80
    zero_skip_required: true
test_suites:
  unit:
    command: "npm test"
YAML

# E1. enabled=false -> 回退到默认路由（忽略配置的 phase_1: fast）
output=$(bash "$SCRIPT_DIR/resolve-model-routing.sh" "$DISABLED_ROOT" 1 2>/dev/null)
assert_json_field "E1. enabled=false -> 默认 phase 1 deep" "$output" "selected_tier" "deep"

rm -rf "$DISABLED_ROOT"

teardown_autopilot_fixture
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
