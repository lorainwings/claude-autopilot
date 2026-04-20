#!/usr/bin/env bash
# test_phase1_resume_on_failure.sh — Verify Phase 1 unifies single-path
# Agent failures into resume + narrowed-retry protocol, eliminating any
# fallback to "AI 内置知识".
#
# Background: spec-autopilot Phase 1 redesign Task 16 — replaces
# "搜索失败 → 回退到 AI 内置知识" silent degradation with explicit
# narrowed retry, second-failure escalation via AskUserQuestion.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_test_helpers.sh"

PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DETAIL_DOC="$PLUGIN_ROOT/skills/autopilot/references/phase1-requirements-detail.md"
CORE_DOC="$PLUGIN_ROOT/skills/autopilot/references/phase1-requirements.md"

echo "=== Phase 1 Resume + Narrowed Retry Protocol Tests ==="

assert_file_exists "phase1-requirements-detail.md present" "$DETAIL_DOC"
assert_file_exists "phase1-requirements.md present" "$CORE_DOC"

DETAIL_BODY="$(cat "$DETAIL_DOC")"
CORE_BODY="$(cat "$CORE_DOC")"

# --- detail doc: fallback wording removed ---
assert_not_contains "detail doc no longer falls back to AI 内置知识 on failure" \
  "$DETAIL_BODY" "回退到 AI 内置知识"

# --- detail doc: failure unified protocol references core doc ---
assert_contains "detail doc declares 失败统一协议" \
  "$DETAIL_BODY" "失败统一协议"
assert_contains "detail doc cross-references core doc" \
  "$DETAIL_BODY" "phase1-requirements.md"
assert_contains "detail doc references 单路 Agent 失败统一处理 章节" \
  "$DETAIL_BODY" "单路 Agent 失败统一处理"

# --- core doc: new unified failure-handling section header ---
assert_contains "core doc has 单路 Agent 失败统一处理 section" \
  "$CORE_BODY" "## 单路 Agent 失败统一处理"

# --- core doc: narrowed retry contract ---
assert_contains "core doc mentions 窄化重派" \
  "$CORE_BODY" "窄化重派"
assert_contains "core doc injects previous_failure into retry prompt" \
  "$CORE_BODY" "previous_failure"
assert_contains "core doc references partial_output field" \
  "$CORE_BODY" "partial_output"

# --- core doc: second-failure escalation ---
assert_contains "core doc escalates via AskUserQuestion on second failure" \
  "$CORE_BODY" "AskUserQuestion"
if grep -E -q -- '第二次失败.*AskUserQuestion|AskUserQuestion 升级' "$CORE_DOC"; then
  green "  PASS: core doc wires second-failure escalation to AskUserQuestion"
  PASS=$((PASS + 1))
else
  red "  FAIL: core doc missing 第二次失败 → AskUserQuestion 升级 wiring"
  FAIL=$((FAIL + 1))
fi

# --- core doc: skip-path side effects ---
assert_contains "core doc downgrades verdict.confidence by 0.2 on skip" \
  "$CORE_BODY" "0.2"
if grep -F -q -- '[NEEDS CLARIFICATION:' "$CORE_DOC"; then
  green "  PASS: core doc appends [NEEDS CLARIFICATION] on skip-path"
  PASS=$((PASS + 1))
else
  red "  FAIL: core doc missing [NEEDS CLARIFICATION] marker on skip-path"
  FAIL=$((FAIL + 1))
fi
assert_contains "core doc sets verdict.requires_human=true on skip" \
  "$CORE_BODY" "requires_human"

# --- core doc: anti-pattern禁止行为 list ---
assert_contains "core doc has 禁止行为 anti-pattern list" \
  "$CORE_BODY" "禁止行为"
# Three explicit禁止 items: fallback, silent retries > 2, skipping retry on first failure
ANTI_COUNT=$(grep -cE '^- ❌' "$CORE_DOC" || true)
if [ "$ANTI_COUNT" -ge 3 ]; then
  green "  PASS: core doc enumerates >=3 ❌ anti-patterns (found $ANTI_COUNT)"
  PASS=$((PASS + 1))
else
  red "  FAIL: core doc missing 禁止行为 anti-pattern items (found $ANTI_COUNT, need >=3)"
  FAIL=$((FAIL + 1))
fi

# --- core doc: must NOT preserve legacy positive-tone fallback wording ---
# The phrase appears under ❌禁止行为 (negated). Ensure no positive-tone fallback exists.
if grep -E -q -- '回退到 AI 内置知识' "$CORE_DOC"; then
  red "  FAIL: core doc still mentions 回退到 AI 内置知识 (legacy fallback wording)"
  FAIL=$((FAIL + 1))
else
  green "  PASS: core doc free of legacy 回退到 AI 内置知识 wording"
  PASS=$((PASS + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
