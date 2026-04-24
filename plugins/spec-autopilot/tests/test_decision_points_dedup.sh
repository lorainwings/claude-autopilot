#!/usr/bin/env bash
# test_decision_points_dedup.sh — Verify SynthesizerAgent prompt enforces
# semantic decision_points dedup: similar topics across scan/research paths
# must be merged into a single merged_decision_point with evidence_refs
# spanning all sources; contradictory topics go into verdict.conflicts[].
#
# Background: spec-autopilot Phase 1 redesign Task 12 — strengthens the
# task_boundary.your_scope wording in parallel-phase1.md and adds a
# few-shot example to anchor the Synthesizer's arbitration behavior.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_test_helpers.sh"

PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PARALLEL_DOC="$PLUGIN_ROOT/skills/autopilot/references/parallel-phase1.md"

echo "=== Phase 1 SynthesizerAgent decision_points dedup Tests ==="

# Pre-flight
assert_file_exists "parallel-phase1.md present" "$PARALLEL_DOC"

PARALLEL_BODY="$(cat "$PARALLEL_DOC")"

# --- (a) task_boundary.your_scope explicit semantic aggregation wording ---
assert_contains "scope mentions 相似 topic 合并" \
  "$PARALLEL_BODY" "相似 topic 合并"
assert_contains "scope requires evidence_refs 保留所有源路径" \
  "$PARALLEL_BODY" "evidence_refs 中保留所有源路径"
assert_contains "scope names 同主题不同推荐 trigger" \
  "$PARALLEL_BODY" "同主题不同推荐"
# conflicts[] routing instruction (explicit arrow → conflicts)
if grep -E -q -- "同主题不同推荐.*(写入|→|->).*conflicts" "$PARALLEL_DOC"; then
  green "  PASS: scope routes contradictory recommendations into conflicts[]"
  PASS=$((PASS + 1))
else
  red "  FAIL: scope missing explicit '同主题不同推荐 → conflicts[]' routing"
  FAIL=$((FAIL + 1))
fi

# --- (b) Few-shot example block present (conflict case) ---
assert_contains "few-shot input topic 数据库选型 present" \
  "$PARALLEL_BODY" "数据库选型"
assert_contains "few-shot input topic DB choice present" \
  "$PARALLEL_BODY" "DB choice"
assert_contains "few-shot output uses deferred_to_user resolution" \
  "$PARALLEL_BODY" "deferred_to_user"
if grep -F -q -- "merged_decision_points: []" "$PARALLEL_DOC"; then
  green "  PASS: few-shot conflict case empties merged_decision_points"
  PASS=$((PASS + 1))
else
  red "  FAIL: few-shot missing 'merged_decision_points: []'"
  FAIL=$((FAIL + 1))
fi
# Both source tags must appear in the conflict few-shot
if grep -E -q -- "source:\s*scan" "$PARALLEL_DOC" &&
  grep -E -q -- "source:\s*research" "$PARALLEL_DOC"; then
  green "  PASS: few-shot lists both scan + research sources"
  PASS=$((PASS + 1))
else
  red "  FAIL: few-shot missing scan or research source tag"
  FAIL=$((FAIL + 1))
fi

# --- (c) Positive dedup example: evidence_refs from BOTH scan: and research: ---
# The existing verdict example shows this shape; task 12 keeps/reinforces it.
assert_contains "positive example uses scan: evidence_refs prefix" \
  "$PARALLEL_BODY" "scan:"
assert_contains "positive example uses research: evidence_refs prefix" \
  "$PARALLEL_BODY" "research:"
# merged_decision_points entry must coexist with evidence_refs containing
# at least one cross-source merged item (regex spans a small window).
if python3 - "$PARALLEL_DOC" <<'PY'; then
import re, sys, pathlib
body = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
# Find any merged_decision_points JSON-ish block whose evidence_refs list
# contains BOTH a scan:... ref AND a research:... ref.
pat = re.compile(
    r'"?evidence_refs"?\s*:\s*\[[^\]]*scan:[^\]]*research:[^\]]*\]'
    r'|"?evidence_refs"?\s*:\s*\[[^\]]*research:[^\]]*scan:[^\]]*\]',
    re.S,
)
sys.exit(0 if pat.search(body) else 1)
PY
  green "  PASS: merged entry shows evidence_refs merging scan + research"
  PASS=$((PASS + 1))
else
  red "  FAIL: no merged_decision_points entry with scan+research evidence_refs"
  FAIL=$((FAIL + 1))
fi

# --- (d) Few-shot block is syntactically labeled (grep anchor) ---
if grep -E -q -- "INPUT decision_points" "$PARALLEL_DOC"; then
  green "  PASS: few-shot labeled with INPUT decision_points anchor"
  PASS=$((PASS + 1))
else
  red "  FAIL: few-shot INPUT decision_points anchor missing"
  FAIL=$((FAIL + 1))
fi
if grep -E -q -- "OUTPUT" "$PARALLEL_DOC"; then
  green "  PASS: few-shot labeled with OUTPUT anchor"
  PASS=$((PASS + 1))
else
  red "  FAIL: few-shot OUTPUT anchor missing"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
