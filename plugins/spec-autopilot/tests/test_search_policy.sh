#!/usr/bin/env bash
# TEST_LAYER: docs_consistency
# test_search_policy.sh — Section 52: Search policy rule engine
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 52. Search policy rule engine and SKILL.md assertions (v3.3.7) ---"
setup_autopilot_fixture

SKILL_FILE="$SCRIPT_DIR/../../skills/autopilot/SKILL.md"
P1_FILE="$SCRIPT_DIR/../../skills/autopilot-phase1-requirements/references/phase1-requirements.md"
P1_DETAIL_FILE="$SCRIPT_DIR/../../skills/autopilot-phase1-requirements/references/phase1-requirements-detail.md"
PD_FILE="$SCRIPT_DIR/../../skills/autopilot/references/parallel-dispatch.md"
CS_FILE="$SCRIPT_DIR/../../skills/autopilot-setup/references/config-schema.md"

# --- 52a-c: SKILL.md assertions ---
skill_search_line=$(grep '联网搜索决策' "$SKILL_FILE" || true)
assert_contains "52a: SKILL.md has search policy description" "$skill_search_line" '默认执行搜索'

skill_default=$(grep 'search_policy.default: search' "$SKILL_FILE" || true)
assert_contains "52b: SKILL.md default is search" "$skill_default" 'search_policy.default: search'

skill_rules=$(grep '规则引擎执行' "$SKILL_FILE" || true)
assert_contains "52c: SKILL.md mentions rule engine (non-AI)" "$skill_rules" '规则引擎'

# --- 52d-g: phase1-requirements.md assertions ---
p1_default=$(grep 'default: search' "$P1_FILE" "$P1_DETAIL_FILE" 2>/dev/null | head -1 || true)
assert_contains "52d: P1 search_policy default is search" "$p1_default" 'default: search'

p1_skip=$(grep 'skip_when_ALL_true' "$P1_FILE" "$P1_DETAIL_FILE" 2>/dev/null | head -1 || true)
assert_contains "52e: P1 has skip_when_ALL_true rule" "$p1_skip" 'skip_when_ALL_true'

p1_force=$(grep 'force_search_when_ANY_true' "$P1_FILE" "$P1_DETAIL_FILE" 2>/dev/null | head -1 || true)
assert_contains "52f: P1 has force_search_when_ANY_true rule" "$p1_force" 'force_search_when_ANY_true'

p1_no_ai=$(grep '非 AI 自评' "$P1_FILE" "$P1_DETAIL_FILE" 2>/dev/null | head -1 || true)
assert_contains "52g: P1 explicitly states non-AI assessment" "$p1_no_ai" '非 AI 自评'

# --- 52h: competitive analysis in focus_areas ---
cs_competitive=$(grep 'competitive_analysis' "$CS_FILE" || true)
assert_contains "52h: config-schema has competitive_analysis focus area" "$cs_competitive" 'competitive_analysis'

# --- 52i: config default is search ---
cs_default=$(grep 'default: search' "$CS_FILE" || true)
assert_contains "52i: config search_policy default is search" "$cs_default" 'default: search'

# --- 52j: force_search_keywords in config ---
cs_force_kw=$(grep -A15 'force_search_keywords' "$CS_FILE" || true)
assert_contains "52j: config has force_search_keywords with UX" "$cs_force_kw" 'UX'

# --- 52k: parallel-dispatch condition updated ---
pd_condition=$(grep 'search_policy.default' "$PD_FILE" || true)
assert_contains "52k: parallel-dispatch references search_policy.default" "$pd_condition" 'search_policy.default'

# --- 52l-v: Rule engine simulation (11 task types + 3 edge cases) ---
# Simulate the rule engine in bash
evaluate_search_policy() {
  local req="$1"
  local force_kws="竞品 产品 UX 交互 体验 新功能 升级 迁移 安全 auth 加密 CORS XSS JWT migration"
  for kw in $force_kws; do
    if grep -qi "$kw" <<< "$req"; then echo "search"; return; fi
  done
  local skip_kws="修复 fix 重构 refactor 样式 style bugfix"
  local is_internal=false
  for kw in $skip_kws; do
    if grep -qi "$kw" <<< "$req"; then is_internal=true; break; fi
  done
  if [ "$is_internal" = false ]; then echo "search"; return; fi
  local new_kws="新依赖 新库 引入 integrate 新模式"
  for kw in $new_kws; do
    if grep -qi "$kw" <<< "$req"; then echo "search"; return; fi
  done
  echo "skip"
}

# search cases
r=$(evaluate_search_policy "实现 slash 命令的新功能")
assert_contains "52l: 新功能 → search" "$r" "search"

r=$(evaluate_search_policy "改进 UX 交互体验")
assert_contains "52m: UX 改进 → search" "$r" "search"

r=$(evaluate_search_policy "参考竞品 Linear 的产品设计")
assert_contains "52n: 产品设计 → search" "$r" "search"

r=$(evaluate_search_policy "引入 Redis 新依赖")
assert_contains "52o: 新依赖 → search" "$r" "search"

r=$(evaluate_search_policy "微服务迁移方案")
assert_contains "52p: 架构迁移 → search" "$r" "search"

r=$(evaluate_search_policy "JWT auth 鉴权实现")
assert_contains "52q: 安全相关 → search" "$r" "search"

r=$(evaluate_search_policy "升级 Vue 3.5")
assert_contains "52r: 版本升级 → search" "$r" "search"

# skip cases
r=$(evaluate_search_policy "修复按钮点击 bug")
assert_contains "52s: 纯 bug 修复 → skip" "$r" "skip"

r=$(evaluate_search_policy "重构 ChatPanel 组件")
assert_contains "52t: 纯重构 → skip" "$r" "skip"

r=$(evaluate_search_policy "调整按钮样式间距")
assert_contains "52u: 样式微调 → skip" "$r" "skip"

# edge cases: force overrides skip
r=$(evaluate_search_policy "修复 auth 安全漏洞")
assert_contains "52v: 安全 bug (force > skip) → search" "$r" "search"

r=$(evaluate_search_policy "重构认证模块迁移 OAuth2")
assert_contains "52w: 重构+迁移 (force > skip) → search" "$r" "search"

# --- 52x: trust mechanism assertions ---
p1_trust=$(grep '以项目规范为准' "$P1_FILE" "$P1_DETAIL_FILE" 2>/dev/null | head -1 || true)
assert_contains "52x: P1 has trust mechanism (project rules priority)" "$p1_trust" '以项目规范为准'

# --- 52y: search_decision field in envelope ---
p1_envelope=$(grep 'search_decision' "$P1_FILE" "$P1_DETAIL_FILE" 2>/dev/null | head -1 || true)
assert_contains "52y: P1 envelope has search_decision field" "$p1_envelope" 'search_decision'

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0
