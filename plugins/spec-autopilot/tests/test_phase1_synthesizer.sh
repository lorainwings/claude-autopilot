#!/usr/bin/env bash
# test_phase1_synthesizer.sh — Verify Phase 1 introduces a third serial
# SynthesizerAgent path that reconciles ScanAgent + ResearchAgent envelopes
# into a verdict.json, producing merged_decision_points + conflicts +
# ambiguities with [NEEDS CLARIFICATION] markers.
#
# Background: spec-autopilot Phase 1 redesign Task 5 — adds SynthesizerAgent
# as the post-parallel arbitration layer aligned with
# runtime/schemas/synthesizer-verdict.schema.json.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_test_helpers.sh"

PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PARALLEL_DOC="$PLUGIN_ROOT/skills/autopilot/references/parallel-phase1.md"
DETAIL_DOC="$PLUGIN_ROOT/skills/autopilot/references/phase1-requirements-detail.md"
SKILL_DOC="$PLUGIN_ROOT/skills/autopilot-phase1-requirements/SKILL.md"
DISPATCH_DOC="$PLUGIN_ROOT/skills/autopilot/references/dispatch-phase-prompts.md"
VERDICT_SCHEMA="$PLUGIN_ROOT/runtime/schemas/synthesizer-verdict.schema.json"

echo "=== Phase 1 SynthesizerAgent Tests ==="

# Pre-flight
assert_file_exists "parallel-phase1.md present" "$PARALLEL_DOC"
assert_file_exists "phase1-requirements-detail.md present" "$DETAIL_DOC"
assert_file_exists "autopilot-phase1-requirements SKILL.md present" "$SKILL_DOC"
assert_file_exists "dispatch-phase-prompts.md present" "$DISPATCH_DOC"
assert_file_exists "synthesizer-verdict.schema.json present" "$VERDICT_SCHEMA"

PARALLEL_BODY="$(cat "$PARALLEL_DOC")"
DETAIL_BODY="$(cat "$DETAIL_DOC")"
SKILL_BODY="$(cat "$SKILL_DOC")"
DISPATCH_BODY="$(cat "$DISPATCH_DOC")"

# --- (a) SynthesizerAgent declared as third parallel/serial path ---
assert_contains "parallel-phase1 declares synthesizer_agent YAML block" \
  "$PARALLEL_BODY" "synthesizer_agent:"
assert_contains "synthesizer triggers_after scan+research" \
  "$PARALLEL_BODY" "triggers_after"
assert_contains "synthesizer reads config synthesizer.agent field" \
  "$PARALLEL_BODY" "phases.requirements.synthesizer.agent"

# --- (b) verdict.json path documented ---
assert_contains "parallel-phase1 references context/phase1-verdict.json" \
  "$PARALLEL_BODY" "context/phase1-verdict.json"
assert_contains "parallel-phase1 references synthesizer-verdict schema" \
  "$PARALLEL_BODY" "runtime/schemas/synthesizer-verdict.schema.json"

# --- (c) conflict detection requirement ---
# Synthesizer prompt must require verdict.conflicts be non-empty when the
# two paths produce contradictory decision_points.
if grep -E -q -- "verdict\.conflicts|conflicts.*非空|冲突.*conflicts" "$PARALLEL_DOC"; then
  green "  PASS: parallel-phase1 requires verdict.conflicts on contradictions"
  PASS=$((PASS + 1))
else
  red "  FAIL: parallel-phase1 missing conflict detection requirement"
  FAIL=$((FAIL + 1))
fi
assert_contains "synthesizer cross-path conflict detection described" \
  "$PARALLEL_BODY" "跨路冲突检测"

# --- (d) Synthesizer has Read authority on context/*.md full text ---
assert_contains "synthesizer allowed tools include Read" \
  "$PARALLEL_BODY" "allowed:"
if grep -E -q -- "allowed:.*\[.*Read" "$PARALLEL_DOC"; then
  green "  PASS: synthesizer allowed tools explicitly include Read"
  PASS=$((PASS + 1))
else
  red "  FAIL: synthesizer allowed tools missing Read"
  FAIL=$((FAIL + 1))
fi
assert_contains "synthesizer reads full context/*.md" \
  "$PARALLEL_BODY" "context/project-context.md"
assert_contains "synthesizer reads research-findings full text" \
  "$PARALLEL_BODY" "research-findings.md"

# --- (e) Synthesizer produces ambiguities with NEEDS CLARIFICATION markers ---
assert_contains "synthesizer emits NEEDS CLARIFICATION markers" \
  "$PARALLEL_BODY" "NEEDS CLARIFICATION"
assert_contains "synthesizer merged_decision_points field" \
  "$PARALLEL_BODY" "merged_decision_points"

# --- (f) SKILL.md Step 1.2 orchestration updated ---
assert_contains "SKILL.md mentions SynthesizerAgent serial dispatch" \
  "$SKILL_BODY" "SynthesizerAgent"
assert_contains "SKILL.md reads phase1-verdict.json" \
  "$SKILL_BODY" "phase1-verdict.json"
if grep -E -q -- "verdict\.(requires_human|ambiguities)" "$SKILL_DOC"; then
  green "  PASS: SKILL.md branches on verdict.requires_human / ambiguities"
  PASS=$((PASS + 1))
else
  red "  FAIL: SKILL.md missing verdict-driven AskUserQuestion branch"
  FAIL=$((FAIL + 1))
fi
assert_contains "SKILL.md BA consumes verdict.merged_decision_points" \
  "$SKILL_BODY" "merged_decision_points"

# --- (g) dispatch-phase-prompts marker ---
assert_contains "dispatch-phase-prompts declares autopilot-phase:1-synthesizer marker" \
  "$DISPATCH_BODY" "autopilot-phase:1-synthesizer"

# --- (h) tool_boundary forbidden list prevents WebSearch / business Edit ---
assert_contains "synthesizer forbids WebSearch" \
  "$PARALLEL_BODY" "WebSearch"
if grep -E -q -- "forbidden:.*\[.*WebSearch" "$PARALLEL_DOC"; then
  green "  PASS: synthesizer forbidden list explicitly bans WebSearch"
  PASS=$((PASS + 1))
else
  red "  FAIL: synthesizer forbidden list missing WebSearch ban"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
