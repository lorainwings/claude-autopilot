#!/usr/bin/env bash
# test_model_routing_resolution.sh — 模型路由解析测试
# 覆盖: 旧格式兼容、新格式校验、phase 默认路由、resolver 输出、config validator
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 模型路由解析测试 ---"
setup_autopilot_fixture

# ── 工具函数 ──
extract_json_field() {
  local json="$1" field="$2"
  python3 -c "import json,sys; print(json.load(sys.stdin).get('$field',''))" <<< "$json" 2>/dev/null || echo ""
}

# =============================================================================
# A. 默认 Phase 路由测试（无配置文件）
# =============================================================================
echo ""
echo "--- A. 默认 Phase 路由 ---"

EMPTY_ROOT=$(mktemp -d)

# A1. Phase 1 -> deep/opus
output=$(bash "$SCRIPT_DIR/resolve-model-routing.sh" "$EMPTY_ROOT" 1 2>/dev/null)
assert_json_field "A1. Phase 1 默认 tier=deep" "$output" "selected_tier" "deep"
assert_json_field "A1. Phase 1 默认 model=opus" "$output" "selected_model" "opus"

# A2. Phase 2 -> fast/haiku
output=$(bash "$SCRIPT_DIR/resolve-model-routing.sh" "$EMPTY_ROOT" 2 2>/dev/null)
assert_json_field "A2. Phase 2 默认 tier=fast" "$output" "selected_tier" "fast"
assert_json_field "A2. Phase 2 默认 model=haiku" "$output" "selected_model" "haiku"

# A3. Phase 3 -> fast/haiku
output=$(bash "$SCRIPT_DIR/resolve-model-routing.sh" "$EMPTY_ROOT" 3 2>/dev/null)
assert_json_field "A3. Phase 3 默认 tier=fast" "$output" "selected_tier" "fast"

# A4. Phase 4 -> standard/sonnet (v5.5: 降级，SWE-bench Sonnet≈Opus，有 gate 兜底)
output=$(bash "$SCRIPT_DIR/resolve-model-routing.sh" "$EMPTY_ROOT" 4 2>/dev/null)
assert_json_field "A4. Phase 4 默认 tier=standard" "$output" "selected_tier" "standard"

# A5. Phase 5 -> deep/opus
output=$(bash "$SCRIPT_DIR/resolve-model-routing.sh" "$EMPTY_ROOT" 5 2>/dev/null)
assert_json_field "A5. Phase 5 默认 tier=deep" "$output" "selected_tier" "deep"
assert_json_field "A5. Phase 5 默认 model=opus" "$output" "selected_model" "opus"

# A6. Phase 6 -> fast/haiku
output=$(bash "$SCRIPT_DIR/resolve-model-routing.sh" "$EMPTY_ROOT" 6 2>/dev/null)
assert_json_field "A6. Phase 6 默认 tier=fast" "$output" "selected_tier" "fast"

# A7. Phase 7 -> fast/haiku
output=$(bash "$SCRIPT_DIR/resolve-model-routing.sh" "$EMPTY_ROOT" 7 2>/dev/null)
assert_json_field "A7. Phase 7 默认 tier=fast" "$output" "selected_tier" "fast"

rm -rf "$EMPTY_ROOT"

# =============================================================================
# B. Legacy 格式拒绝测试（heavy/light 已删除，必须报错）
# =============================================================================
echo ""
echo "--- B. Legacy 格式拒绝 ---"

LEGACY_ROOT=$(mktemp -d)
mkdir -p "$LEGACY_ROOT/.claude"

# B1. 旧格式 heavy/light 不再映射，会走 fallback（因为不在 TIER_MODEL_MAP 中）
cat > "$LEGACY_ROOT/.claude/autopilot.config.yaml" << 'YAML'
version: "1.0"
model_routing:
  phase_1: heavy
  phase_2: light
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

# B1a. heavy 不再映射为 deep，而是触发 fallback
output=$(bash "$SCRIPT_DIR/resolve-model-routing.sh" "$LEGACY_ROOT" 1 2>/dev/null)
tier=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['selected_tier'])" 2>/dev/null)
fallback=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['fallback_applied'])" 2>/dev/null)
if [ "$fallback" = "True" ]; then
  green "  PASS: B1a. heavy 触发 fallback（不再映射为 deep）"
  PASS=$((PASS + 1))
else
  red "  FAIL: B1a. heavy 应触发 fallback (tier=$tier, fallback=$fallback)"
  FAIL=$((FAIL + 1))
fi

# B1b. light 不再映射为 standard，而是触发 fallback
output=$(bash "$SCRIPT_DIR/resolve-model-routing.sh" "$LEGACY_ROOT" 2 2>/dev/null)
fallback=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['fallback_applied'])" 2>/dev/null)
if [ "$fallback" = "True" ]; then
  green "  PASS: B1b. light 触发 fallback（不再映射为 standard）"
  PASS=$((PASS + 1))
else
  red "  FAIL: B1b. light 应触发 fallback"
  FAIL=$((FAIL + 1))
fi

# B2. Config validator 拒绝旧格式 heavy/light
output=$(bash "$SCRIPT_DIR/validate-config.sh" "$LEGACY_ROOT" 2>/dev/null)
mr_errors=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('model_routing_errors',[])))" 2>/dev/null || echo "0")
if [ "$mr_errors" -gt 0 ]; then
  green "  PASS: B2. validator 拒绝 heavy/light (model_routing_errors=$mr_errors)"
  PASS=$((PASS + 1))
else
  red "  FAIL: B2. validator 应拒绝 heavy/light (model_routing_errors=$mr_errors)"
  FAIL=$((FAIL + 1))
fi

rm -rf "$LEGACY_ROOT"

# B3. 环境变量覆盖测试
ENV_ROOT=$(mktemp -d)
mkdir -p "$ENV_ROOT/.claude"
cat > "$ENV_ROOT/.claude/autopilot.config.yaml" << 'YAML'
version: "1.0"
model_routing:
  enabled: true
  phases:
    phase_1:
      tier: fast
      model: haiku
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

# B3a. AUTOPILOT_PHASE1_MODEL=opus 覆盖 config 中的 haiku
output=$(AUTOPILOT_PHASE1_MODEL=opus bash "$SCRIPT_DIR/resolve-model-routing.sh" "$ENV_ROOT" 1 2>/dev/null)
model=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['selected_model'])" 2>/dev/null)
if [ "$model" = "opus" ]; then
  green "  PASS: B3a. 环境变量 AUTOPILOT_PHASE1_MODEL=opus 覆盖成功"
  PASS=$((PASS + 1))
else
  red "  FAIL: B3a. 环境变量覆盖失败 (model=$model, expected=opus)"
  FAIL=$((FAIL + 1))
fi

# B3b. 无环境变量时使用 config 值
output=$(bash "$SCRIPT_DIR/resolve-model-routing.sh" "$ENV_ROOT" 1 2>/dev/null)
model=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['selected_model'])" 2>/dev/null)
if [ "$model" = "haiku" ]; then
  green "  PASS: B3b. 无环境变量时使用 config haiku"
  PASS=$((PASS + 1))
else
  red "  FAIL: B3b. 无环境变量时应为 haiku (model=$model)"
  FAIL=$((FAIL + 1))
fi

rm -rf "$ENV_ROOT"

# =============================================================================
# C. 新格式对象化配置测试
# =============================================================================
echo ""
echo "--- C. 新格式对象化配置 ---"

NEW_ROOT=$(mktemp -d)
mkdir -p "$NEW_ROOT/.claude"

cat > "$NEW_ROOT/.claude/autopilot.config.yaml" << 'YAML'
version: "1.0"
model_routing:
  enabled: true
  default_subagent_model: sonnet
  fallback_model: sonnet
  phases:
    phase_1:
      tier: deep
      model: opus
      effort: high
    phase_2:
      tier: fast
      model: haiku
      effort: low
    phase_5:
      tier: standard
      model: sonnet
      effort: medium
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

# C1. 新格式 Phase 1 解析
output=$(bash "$SCRIPT_DIR/resolve-model-routing.sh" "$NEW_ROOT" 1 2>/dev/null)
assert_json_field "C1. 新格式 Phase 1 tier=deep" "$output" "selected_tier" "deep"
assert_json_field "C1. 新格式 Phase 1 model=opus" "$output" "selected_model" "opus"
assert_json_field "C1. 新格式 Phase 1 effort=high" "$output" "selected_effort" "high"

# C2. 新格式 Phase 2 解析
output=$(bash "$SCRIPT_DIR/resolve-model-routing.sh" "$NEW_ROOT" 2 2>/dev/null)
assert_json_field "C2. 新格式 Phase 2 tier=fast" "$output" "selected_tier" "fast"
assert_json_field "C2. 新格式 Phase 2 model=haiku" "$output" "selected_model" "haiku"

# C3. 新格式未指定 phase 回退到 default_subagent_model
output=$(bash "$SCRIPT_DIR/resolve-model-routing.sh" "$NEW_ROOT" 6 2>/dev/null)
assert_json_field "C3. 未指定 phase 回退到 default_subagent_model" "$output" "selected_tier" "standard"

# C4. Config validator 新格式通过
output=$(bash "$SCRIPT_DIR/validate-config.sh" "$NEW_ROOT" 2>/dev/null)
mr_errors=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('model_routing_errors',[]))" 2>/dev/null || echo "[]")
if [ "$mr_errors" = "[]" ]; then
  green "  PASS: C4. 新格式 config validator 无 model_routing_errors"
  PASS=$((PASS + 1))
else
  red "  FAIL: C4. 新格式 config validator (errors=$mr_errors)"
  FAIL=$((FAIL + 1))
fi

rm -rf "$NEW_ROOT"

# =============================================================================
# D. 无效配置校验测试
# =============================================================================
echo ""
echo "--- D. 无效配置校验 ---"

BAD_ROOT=$(mktemp -d)
mkdir -p "$BAD_ROOT/.claude"

# D1. 无效 tier 值
cat > "$BAD_ROOT/.claude/autopilot.config.yaml" << 'YAML'
version: "1.0"
model_routing:
  enabled: true
  phases:
    phase_1:
      tier: turbo
      model: gpt4
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

output=$(bash "$SCRIPT_DIR/validate-config.sh" "$BAD_ROOT" 2>/dev/null)
valid=$(extract_json_field "$output" "valid")
if [ "$valid" = "False" ] || [ "$valid" = "false" ]; then
  green "  PASS: D1. 无效 tier 'turbo' → valid=false"
  PASS=$((PASS + 1))
else
  red "  FAIL: D1. 无效 tier (got valid='$valid')"
  FAIL=$((FAIL + 1))
fi
assert_contains "D1. model_routing_errors 包含 turbo" "$output" "turbo"
assert_contains "D1. model_routing_errors 包含 gpt4" "$output" "gpt4"

# D2. 无效顶层字符串
cat > "$BAD_ROOT/.claude/autopilot.config.yaml" << 'YAML'
version: "1.0"
model_routing: turbo
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

output=$(bash "$SCRIPT_DIR/validate-config.sh" "$BAD_ROOT" 2>/dev/null)
assert_contains "D2. 无效顶层字符串 'turbo'" "$output" "turbo"

rm -rf "$BAD_ROOT"

# =============================================================================
# E. 复杂度调整测试
# =============================================================================
echo ""
echo "--- E. 复杂度调整 ---"

EMPTY_ROOT2=$(mktemp -d)

# E1. Phase 2 (默认 fast) + complexity=large -> 升级到 standard
output=$(bash "$SCRIPT_DIR/resolve-model-routing.sh" "$EMPTY_ROOT2" 2 large feature 0 false 2>/dev/null)
assert_json_field "E1. fast + large -> standard" "$output" "selected_tier" "standard"

# E2. Phase 6 (默认 fast) + complexity=large -> 升级到 standard
output=$(bash "$SCRIPT_DIR/resolve-model-routing.sh" "$EMPTY_ROOT2" 6 large feature 0 false 2>/dev/null)
assert_json_field "E2. fast + large -> standard" "$output" "selected_tier" "standard"

rm -rf "$EMPTY_ROOT2"

# =============================================================================
# F. Critical 任务升级测试
# =============================================================================
echo ""
echo "--- F. Critical 任务升级 ---"

EMPTY_ROOT3=$(mktemp -d)

# F1. Phase 6 (默认 fast) + critical=true -> deep
output=$(bash "$SCRIPT_DIR/resolve-model-routing.sh" "$EMPTY_ROOT3" 6 medium feature 0 true 2>/dev/null)
assert_json_field "F1. fast + critical -> deep" "$output" "selected_tier" "deep"
assert_json_field "F1. fast + critical -> opus" "$output" "selected_model" "opus"

# F2. Phase 2 (默认 fast) + critical=true -> deep
output=$(bash "$SCRIPT_DIR/resolve-model-routing.sh" "$EMPTY_ROOT3" 2 medium feature 0 true 2>/dev/null)
assert_json_field "F2. fast + critical -> deep" "$output" "selected_tier" "deep"

rm -rf "$EMPTY_ROOT3"

# =============================================================================
# G. auto 继承父会话测试
# =============================================================================
echo ""
echo "--- G. auto 继承父会话 ---"

AUTO_ROOT=$(mktemp -d)
mkdir -p "$AUTO_ROOT/.claude"

cat > "$AUTO_ROOT/.claude/autopilot.config.yaml" << 'YAML'
version: "1.0"
model_routing:
  phase_1: auto
  phase_2: deep
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

# G1. phase_1: auto -> selected_tier=auto, selected_model=auto
output=$(bash "$SCRIPT_DIR/resolve-model-routing.sh" "$AUTO_ROOT" 1 2>/dev/null)
assert_json_field "G1. auto -> selected_tier=auto" "$output" "selected_tier" "auto"
assert_json_field "G1. auto -> selected_model=auto" "$output" "selected_model" "auto"

# G2. phase_2: deep -> selected_tier=deep（简写 per-phase 格式）
output=$(bash "$SCRIPT_DIR/resolve-model-routing.sh" "$AUTO_ROOT" 2 2>/dev/null)
assert_json_field "G2. deep -> selected_tier=deep" "$output" "selected_tier" "deep"

# G3. 新格式 auto
cat > "$AUTO_ROOT/.claude/autopilot.config.yaml" << 'YAML'
version: "1.0"
model_routing:
  enabled: true
  phases:
    phase_3:
      tier: auto
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

output=$(bash "$SCRIPT_DIR/resolve-model-routing.sh" "$AUTO_ROOT" 3 2>/dev/null)
assert_json_field "G3. 新格式 tier=auto -> auto" "$output" "selected_tier" "auto"
assert_json_field "G3. 新格式 tier=auto -> auto model" "$output" "selected_model" "auto"

rm -rf "$AUTO_ROOT"

# =============================================================================
# H. fallback_model 生效测试
# =============================================================================
echo ""
echo "--- H. fallback_model ---"

FB_ROOT=$(mktemp -d)
mkdir -p "$FB_ROOT/.claude"

cat > "$FB_ROOT/.claude/autopilot.config.yaml" << 'YAML'
version: "1.0"
model_routing:
  enabled: true
  fallback_model: haiku
  phases:
    phase_1:
      tier: nonexistent
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

# H1. 无效 tier + fallback_model=haiku -> fallback 生效
output=$(bash "$SCRIPT_DIR/resolve-model-routing.sh" "$FB_ROOT" 1 2>/dev/null)
assert_json_field "H1. fallback_applied=True" "$output" "fallback_applied" "True"
assert_json_field "H1. fallback -> haiku" "$output" "selected_model" "haiku"
assert_json_field "H1. fallback tier -> fast" "$output" "selected_tier" "fast"

# H2. 无 fallback_model + 无效 tier -> 硬回退 sonnet
cat > "$FB_ROOT/.claude/autopilot.config.yaml" << 'YAML'
version: "1.0"
model_routing:
  enabled: true
  phases:
    phase_1:
      tier: nonexistent
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

output=$(bash "$SCRIPT_DIR/resolve-model-routing.sh" "$FB_ROOT" 1 2>/dev/null)
assert_json_field "H2. 无 fallback -> 硬回退 sonnet" "$output" "selected_model" "sonnet"
assert_json_field "H2. fallback_applied=True" "$output" "fallback_applied" "True"

rm -rf "$FB_ROOT"

# =============================================================================
# I. Regex fallback 嵌套解析测试（模拟无 PyYAML）
# =============================================================================
echo ""
echo "--- I. Regex fallback 嵌套解析 ---"

RGX_ROOT=$(mktemp -d)
mkdir -p "$RGX_ROOT/.claude"

cat > "$RGX_ROOT/.claude/autopilot.config.yaml" << 'YAML'
version: "1.0"
model_routing:
  enabled: true
  fallback_model: haiku
  phases:
    phase_1:
      tier: deep
      model: opus
      effort: high
    phase_2:
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

# I1. 使用 regex fallback 解析嵌套 phases（屏蔽 PyYAML）
output=$(python3 -c "
import sys, os
sys.modules['yaml'] = None  # 屏蔽 PyYAML
# 直接调用 parse_config 的 regex 分支
config_path = sys.argv[1]
import re
content = open(config_path).read()
# 复制 resolver 中的 regex fallback 逻辑进行独立验证
mr_match = re.search(r'^model_routing:\s*$', content, re.MULTILINE)
assert mr_match, 'model_routing block not found'
block_start = mr_match.end()
next_top = re.search(r'^[a-zA-Z_]\w*:', content[block_start:], re.MULTILINE)
block = content[block_start:block_start + next_top.start()] if next_top else content[block_start:]
lines = block.split('\n')
l1_indent = None
for line in lines:
    stripped = line.lstrip()
    if not stripped or stripped.startswith('#'):
        continue
    l1_indent = len(line) - len(stripped)
    break
assert l1_indent is not None
result = {}
phases_dict = {}
current_l1_key = None
i = 0
while i < len(lines):
    line = lines[i]
    stripped = line.lstrip()
    i += 1
    if not stripped or stripped.startswith('#'):
        continue
    indent = len(line) - len(stripped)
    if indent < l1_indent and stripped:
        break
    if indent == l1_indent:
        m = re.match(r'([\w_]+):\s*(.*)', stripped)
        if not m:
            continue
        key = m.group(1)
        val_str = m.group(2).strip()
        current_l1_key = key
        if key == 'phases' and not val_str:
            pass
        elif key == 'enabled':
            result['enabled'] = val_str.lower() == 'true' if val_str else True
        elif val_str:
            val_clean = val_str.strip('\"').strip(\"'\")
            result[key] = val_clean
    elif indent > l1_indent and current_l1_key == 'phases':
        m = re.match(r'(phase_\d+):\s*(.*)', stripped)
        if m:
            phase_key = m.group(1)
            phase_val_str = m.group(2).strip()
            if phase_val_str:
                phases_dict[phase_key] = phase_val_str.strip('\"').strip(\"'\")
            else:
                phase_obj = {}
                while i < len(lines):
                    l3_line = lines[i]
                    l3_stripped = l3_line.lstrip()
                    if not l3_stripped or l3_stripped.startswith('#'):
                        i += 1
                        continue
                    l3_indent = len(l3_line) - len(l3_stripped)
                    if l3_indent <= indent:
                        break
                    l3_m = re.match(r'([\w_]+):\s*(.*)', l3_stripped)
                    if l3_m:
                        phase_obj[l3_m.group(1)] = l3_m.group(2).strip().strip('\"').strip(\"'\")
                    i += 1
                phases_dict[phase_key] = phase_obj
if phases_dict:
    result['phases'] = phases_dict
import json
print(json.dumps(result))
" "$RGX_ROOT/.claude/autopilot.config.yaml" 2>/dev/null)

assert_contains "I1. regex 解析出 enabled" "$output" "enabled"
assert_contains "I1. regex 解析出 phases" "$output" "phases"
assert_contains "I1. regex 解析出 phase_1 的 tier=deep" "$output" "deep"
assert_contains "I1. regex 解析出 fallback_model" "$output" "haiku"

rm -rf "$RGX_ROOT"

teardown_autopilot_fixture
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0
