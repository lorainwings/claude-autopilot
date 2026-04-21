#!/usr/bin/env bash
# test_agent_install_synthesizer.sh — Verify autopilot-agents install flow
# registers the Phase 1 SynthesizerAgent role (v6+ topology) with the correct
# recommendation chain and agent-class constraint.
#
# Background: spec-autopilot Phase 1 redesign Task 7 — builds on Task 1
# (which added the install template field + Phase→config-key mapping) and
# enforces:
#   - recommendation chain: OMC "architect" > "Plan" > 用户自配
#   - recommended class: architect / judge 类 (禁止 explore 类)
#   - Phase→config key map contains requirements.synthesizer entry

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_test_helpers.sh"

PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENTS_SKILL="$PLUGIN_ROOT/skills/autopilot-agents/SKILL.md"
AGENTS_REFS_DIR="$PLUGIN_ROOT/skills/autopilot-agents/references"

echo "=== autopilot-agents install: synthesizer role registration ==="

assert_file_exists "autopilot-agents SKILL.md present" "$AGENTS_SKILL"

# v6+: protocol content lives in SKILL.md + references/*.md (modular split).
# Aggregate all files so assertions cover the full skill surface.
SKILL_BODY="$(cat "$AGENTS_SKILL" "$AGENTS_REFS_DIR"/*.md 2>/dev/null)"

# --- (a) install 模板写入 synthesizer.agent ---
assert_contains "install template writes phases.requirements.synthesizer.agent" \
  "$SKILL_BODY" "phases.requirements.synthesizer.agent:"

assert_contains "install template binds synthesizer to selected_phase1_synthesizer_agent" \
  "$SKILL_BODY" "selected_phase1_synthesizer_agent"

# --- (b) Phase → config key 映射包含 synthesizer ---
assert_contains "phase map includes phase1-synthesizer" \
  "$SKILL_BODY" "phase1-synthesizer"

assert_contains "phase map routes phase1-synthesizer to phases.requirements.synthesizer.agent" \
  "$SKILL_BODY" "phase1-synthesizer    → phases.requirements.synthesizer.agent"

# --- (c) 推荐链：OMC architect > Plan > 用户自配 ---
# 使用 python 做单行完整匹配，避免多行模式被 grep 拆散
PRIORITY_LINE="$(python3 -c "
import re,sys,io,glob
paths=['$AGENTS_SKILL'] + sorted(glob.glob('$AGENTS_REFS_DIR/*.md'))
body=''.join(open(p,encoding='utf-8').read()+'\n' for p in paths)
hits=[l for l in body.splitlines() if 'synthesizer' in l.lower() or re.search(r'架构师|architect',l,re.I)]
print('\n'.join(hits))
" 2>/dev/null || echo "")"

assert_contains "recommendation chain mentions OMC architect" \
  "$SKILL_BODY" "architect"

assert_contains "recommendation chain mentions Plan as fallback" \
  "$SKILL_BODY" "Plan"

assert_contains "recommendation chain mentions 用户自配 as final fallback" \
  "$SKILL_BODY" "用户自配"

# --- (d) agent 类别约束：architect/judge 类，禁止 explore 类 ---
# 必须出现 architect/judge 类的书面约束，且明确排除 explore
assert_contains "synthesizer recommendation notes architect/judge class" \
  "$SKILL_BODY" "architect/judge"

assert_contains "synthesizer recommendation excludes explore class" \
  "$SKILL_BODY" "非 explore"

# --- (e) 推荐链三段结构相邻出现（架构约束不可被拆散） ---
# 以 awk 抽取首个同时包含 architect + Plan + 用户自配 的单行
CHAIN_OK="$(awk '
  /architect/ && /Plan/ && /用户自配/ {print "FOUND"; exit}
' "$AGENTS_SKILL" "$AGENTS_REFS_DIR"/*.md)"

if [ "$CHAIN_OK" = "FOUND" ]; then
  green "  PASS: recommendation chain OMC architect > Plan > 用户自配 on single line"
  PASS=$((PASS + 1))
else
  red "  FAIL: recommendation chain not on a single contiguous line"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
