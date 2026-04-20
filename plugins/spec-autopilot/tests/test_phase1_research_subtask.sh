#!/usr/bin/env bash
# test_phase1_research_subtask.sh — Verify Phase 1 ResearchAgent prompt
# absorbed the former third-path web-search agent as a depth=deep conditional
# subtask, with explicit task & tool boundaries and deprecation note.
#
# Background: spec-autopilot Phase 1 redesign Task 4 — eliminates the standalone
# web_search Agent (D2 root cause) and folds web research into ResearchAgent.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_test_helpers.sh"

PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PARALLEL_DOC="$PLUGIN_ROOT/skills/autopilot/references/parallel-phase1.md"
DETAIL_DOC="$PLUGIN_ROOT/skills/autopilot/references/phase1-requirements-detail.md"

echo "=== Phase 1 ResearchAgent Web-Search Merge Tests ==="

# Pre-flight: target docs exist
assert_file_exists "parallel-phase1.md present" "$PARALLEL_DOC"
assert_file_exists "phase1-requirements-detail.md present" "$DETAIL_DOC"

PARALLEL_BODY="$(cat "$PARALLEL_DOC")"
DETAIL_BODY="$(cat "$DETAIL_DOC")"

# --- (a) depth=deep triggers WebSearch in ResearchAgent ---
# The ResearchAgent prompt section MUST mention WebSearch gated by depth=deep.
if grep -E -q -- "(WebSearch|websearch_quota).*deep|deep.*WebSearch" "$PARALLEL_DOC"; then
  green "  PASS: parallel-phase1 mentions WebSearch gated by depth=deep"
  PASS=$((PASS + 1))
else
  red "  FAIL: parallel-phase1 missing depth=deep WebSearch gating"
  FAIL=$((FAIL + 1))
fi

# --- (b) depth=standard explicitly excludes WebSearch ---
# We require an explicit zero quota for non-deep depth.
assert_contains "websearch quota=0 for standard depth" \
  "$PARALLEL_BODY" "0 if depth=standard"

# --- (c) task_boundary names what ResearchAgent is NOT covering ---
assert_contains "task_boundary names ScanAgent ownership" \
  "$PARALLEL_BODY" "ScanAgent"
assert_contains "task_boundary names SynthesizerAgent ownership" \
  "$PARALLEL_BODY" "SynthesizerAgent"
assert_contains "task_boundary uses YAML key" \
  "$PARALLEL_BODY" "task_boundary:"
assert_contains "tool_boundary uses YAML key" \
  "$PARALLEL_BODY" "tool_boundary:"

# --- (d) standalone web-search Agent removed from parallel_tasks ---
assert_not_contains "web-search task removed from parallel_tasks" \
  "$PARALLEL_BODY" 'name: "web-search"'
assert_not_contains "web-search RESOLVED placeholder removed" \
  "$PARALLEL_BODY" "RESOLVED_WEBSEARCH_AGENT"
# The active dispatch directive `agent: config...web_search.agent` must be gone.
# Mentions inside the Deprecation Notice are allowed (they refer to the legacy field).
if grep -E -q -- "^[[:space:]]*agent:[[:space:]]*config\.phases\.requirements\.research\.web_search\.agent" "$PARALLEL_DOC"; then
  red "  FAIL: parallel-phase1 still has active 'agent: config...web_search.agent' directive"
  FAIL=$((FAIL + 1))
else
  green "  PASS: no active web_search.agent dispatch directive"
  PASS=$((PASS + 1))
fi

# --- (e) deprecation note appended ---
assert_contains "deprecation note present in parallel-phase1" \
  "$PARALLEL_BODY" "web_search Agent 已合并至 ResearchAgent"

# --- (f) detail doc removed standalone web-research envelope section ---
assert_not_contains "detail doc removed 联网调研返回信封 section" \
  "$DETAIL_BODY" "联网调研返回信封"
assert_not_contains "detail doc removed 联网调研产出格式 section" \
  "$DETAIL_BODY" "联网调研产出格式"
# Active dispatch templates must not output to web-research-findings.md.
# Allow only deprecation prose. Check no `输出到` directive references it.
if grep -E -q -- "(输出.*to|output.*to|Write.*to).*web-research-findings\.md|web-research-findings\.md.*(子 Agent 自行写入|输出结构化)" "$PARALLEL_DOC"; then
  red "  FAIL: parallel-phase1 still has active write directive to web-research-findings.md"
  FAIL=$((FAIL + 1))
else
  green "  PASS: parallel-phase1 has no active write directive to web-research-findings.md"
  PASS=$((PASS + 1))
fi

# --- (g) ResearchAgent prompt explicitly gates tasks 5/6/7 to depth=deep ---
# Task 5 (web search) was previously default; must now be deep-only.
if grep -E -q -- "(任务 5|Task 5|### 5\.).{0,80}depth.{0,5}=.{0,5}deep" "$DETAIL_DOC"; then
  green "  PASS: detail doc gates task 5 (web search) to depth=deep"
  PASS=$((PASS + 1))
else
  # Accept alternative phrasing: explicit "当且仅当 depth=deep" near the web-search task
  if grep -B1 -A4 "Web 搜索调研\|联网调研" "$DETAIL_DOC" | grep -q "depth = deep\|depth=deep\|depth >= deep"; then
    green "  PASS: detail doc gates web search to depth=deep (alt phrasing)"
    PASS=$((PASS + 1))
  else
    red "  FAIL: detail doc does not gate web search task to depth=deep"
    FAIL=$((FAIL + 1))
  fi
fi

# --- (h) envelope schema reference present in YAML block ---
assert_contains "envelope_schema points at research-envelope schema path" \
  "$PARALLEL_BODY" "runtime/schemas/research-envelope.schema.json"

# --- (i) research-envelope schema file exists on disk and is valid JSON ---
RESEARCH_ENVELOPE_SCHEMA="$PLUGIN_ROOT/runtime/schemas/research-envelope.schema.json"
assert_file_exists "research-envelope.schema.json present on disk" "$RESEARCH_ENVELOPE_SCHEMA"
if command -v jq >/dev/null 2>&1; then
  if jq -e . "$RESEARCH_ENVELOPE_SCHEMA" >/dev/null 2>&1; then
    green "  PASS: research-envelope.schema.json is valid JSON (jq)"
    PASS=$((PASS + 1))
  else
    red "  FAIL: research-envelope.schema.json failed jq parse"
    FAIL=$((FAIL + 1))
  fi
  # Top-level keys promised by parallel-phase1 contract
  if jq -e '.properties.web_search_summary.properties.search_decision and .properties.web_search_summary.properties.queries_executed and .properties.web_search_summary.properties.highlights and .properties.web_search_summary.properties.skip_reason' "$RESEARCH_ENVELOPE_SCHEMA" >/dev/null 2>&1; then
    green "  PASS: research-envelope schema declares web_search_summary required subfields"
    PASS=$((PASS + 1))
  else
    red "  FAIL: research-envelope schema missing web_search_summary subfields"
    FAIL=$((FAIL + 1))
  fi
else
  yellow "  SKIP: jq not installed; skipping research-envelope JSON parse check" 2>/dev/null || echo "  SKIP: jq not installed; skipping research-envelope JSON parse check"
fi

# --- (j) detail doc must not reintroduce the deprecated max_queries field ---
assert_not_contains "detail doc removed legacy web_search.max_queries reference" \
  "$DETAIL_BODY" "web_search.max_queries"
assert_not_contains "parallel-phase1 removed legacy web_search.max_queries reference" \
  "$PARALLEL_BODY" "web_search.max_queries"

# --- (k) detail doc must not Read web-research-findings.md (merged into research-findings.md) ---
if grep -E -q -- "Read:[[:space:]]*[^[:space:]]*web-research-findings\.md" "$DETAIL_DOC"; then
  red "  FAIL: detail doc still has 'Read: ... web-research-findings.md' directive"
  FAIL=$((FAIL + 1))
else
  green "  PASS: detail doc has no Read directive targeting web-research-findings.md"
  PASS=$((PASS + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
