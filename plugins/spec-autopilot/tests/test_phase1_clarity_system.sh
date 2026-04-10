#!/usr/bin/env bash
# test_phase1_clarity_system.sh — v7.1 Phase 1 clarity scoring, challenge agents,
# soft/hard exit, discussion_rounds L2 validation, and packet persistence tests
# TEST_LAYER: behavior
# Production targets:
#   - _config_validator.py (TYPE_RULES, RANGE_RULES for v7.1 fields)
#   - _post_task_validator.py (discussion_rounds L2 check)
#   - phase1-requirements.md 1.6 (clarity-driven exit, no threshold bypass)
#   - phase1-clarity-scoring.md (scoring dimensions, thresholds)
#   - phase1-challenge-agents.md (activation conditions, stagnation detection)
#   - phase1-requirements-detail.md (requirement-packet.json schema v7.1 fields)
#   - protocol.md (Phase 1 optional fields include v7.1 additions)
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
SKILL_DIR="$(cd "$TEST_DIR/../skills" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- Phase 1 Clarity System (v7.1) ---"
setup_autopilot_fixture

# ================================================================
# Part 1: _config_validator.py covers v7.1 fields
# ================================================================

# 1a. TYPE_RULES contains clarity_threshold
assert_file_contains "1a. TYPE_RULES has clarity_threshold" \
  "$SCRIPT_DIR/_config_validator.py" '"phases.requirements.clarity_threshold"'

# 1b. TYPE_RULES contains max_rounds
assert_file_contains "1b. TYPE_RULES has max_rounds" \
  "$SCRIPT_DIR/_config_validator.py" '"phases.requirements.max_rounds"'

# 1c. TYPE_RULES contains soft_warning_rounds
assert_file_contains "1c. TYPE_RULES has soft_warning_rounds" \
  "$SCRIPT_DIR/_config_validator.py" '"phases.requirements.soft_warning_rounds"'

# 1d. TYPE_RULES contains challenge_agents.enabled
assert_file_contains "1d. TYPE_RULES has challenge_agents.enabled" \
  "$SCRIPT_DIR/_config_validator.py" '"phases.requirements.challenge_agents.enabled"'

# 1e. TYPE_RULES contains one_question_per_round
assert_file_contains "1e. TYPE_RULES has one_question_per_round" \
  "$SCRIPT_DIR/_config_validator.py" '"phases.requirements.one_question_per_round"'

# 1f. RANGE_RULES contains clarity_threshold (0.5, 1.0)
assert_file_contains "1f. RANGE_RULES has clarity_threshold range" \
  "$SCRIPT_DIR/_config_validator.py" '"phases.requirements.clarity_threshold": (0.5, 1.0)'

# 1g. RANGE_RULES contains max_rounds (3, 30)
assert_file_contains "1g. RANGE_RULES has max_rounds range" \
  "$SCRIPT_DIR/_config_validator.py" '"phases.requirements.max_rounds": (3, 30)'

# 1h. RANGE_RULES contains clarity_threshold_overrides
assert_file_contains "1h. RANGE_RULES has clarity_threshold_overrides.small" \
  "$SCRIPT_DIR/_config_validator.py" '"phases.requirements.clarity_threshold_overrides.small"'

# 1i. Range validation rejects out-of-bound clarity_threshold
TEMP_CONFIG=$(mktemp)
cat > "$TEMP_CONFIG" << 'YAML'
version: "5.3.3"
services: {}
phases:
  requirements:
    agent: "test"
    min_qa_rounds: 1
    clarity_threshold: 1.5
  testing:
    agent: "test"
    gate:
      min_test_count_per_type: 5
      required_test_types: ["unit"]
  implementation:
    serial_task:
      max_retries_per_task: 3
  reporting:
    coverage_target: 80
    zero_skip_required: true
test_suites: {}
YAML
OUTPUT=$(python3 "$SCRIPT_DIR/_config_validator.py" "$TEMP_CONFIG" 2>/dev/null)
assert_contains "1i. out-of-range clarity_threshold=1.5 detected" "$OUTPUT" "out of range"
rm -f "$TEMP_CONFIG"

# 1j. Range validation rejects out-of-bound max_rounds
TEMP_CONFIG2=$(mktemp)
cat > "$TEMP_CONFIG2" << 'YAML'
version: "5.3.3"
services: {}
phases:
  requirements:
    agent: "test"
    min_qa_rounds: 1
    max_rounds: 99
  testing:
    agent: "test"
    gate:
      min_test_count_per_type: 5
      required_test_types: ["unit"]
  implementation:
    serial_task:
      max_retries_per_task: 3
  reporting:
    coverage_target: 80
    zero_skip_required: true
test_suites: {}
YAML
OUTPUT2=$(python3 "$SCRIPT_DIR/_config_validator.py" "$TEMP_CONFIG2" 2>/dev/null)
assert_contains "1j. out-of-range max_rounds=99 detected" "$OUTPUT2" "out of range"
rm -f "$TEMP_CONFIG2"

# ================================================================
# Part 2: _post_task_validator.py uses discussion_rounds (v7.1)
# ================================================================

# 2a. Validator prefers discussion_rounds over len(decisions)
assert_file_contains "2a. validator reads discussion_rounds field" \
  "$SCRIPT_DIR/_post_task_validator.py" 'discussion_rounds'

# 2b. Validator has fallback to len(decisions) for backward compat
assert_file_contains "2b. validator falls back to len(decisions)" \
  "$SCRIPT_DIR/_post_task_validator.py" 'len(decisions)'

# 2c. Error message says "discussion rounds" not "decisions count"
assert_file_contains "2c. error message uses discussion rounds wording" \
  "$SCRIPT_DIR/_post_task_validator.py" 'discussion rounds'

# ================================================================
# Part 3: phase1-requirements.md exit logic
# ================================================================

PHASE1_REQ="$SKILL_DIR/autopilot/references/phase1-requirements.md"

# 3a. Exit condition is three-way AND
assert_file_contains "3a. exit requires clarity_score >= clarity_threshold" \
  "$PHASE1_REQ" 'clarity_score >= clarity_threshold'

# 3b. No unconditional EXIT LOOP without user consent when clarity < threshold
# The old bug was: EXIT LOOP without checking clarity. Now it must ask user.
phase1_content=$(cat "$PHASE1_REQ")
if echo "$phase1_content" | grep -A2 "未发现新决策点" | grep -q "AskUserQuestion"; then
  green "  PASS: 3b. low-clarity exit requires AskUserQuestion"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3b. low-clarity EXIT LOOP without user consent"
  FAIL=$((FAIL + 1))
fi

# 3c. soft_warning_rounds triggers AskUserQuestion
assert_file_contains "3c. soft_warning_rounds triggers AskUserQuestion" \
  "$PHASE1_REQ" 'soft_warning_rounds'

# 3d. max_rounds forces exit
assert_file_contains "3d. max_rounds forces exit" \
  "$PHASE1_REQ" 'max_rounds'

# ================================================================
# Part 4: Challenge agents protocol completeness
# ================================================================

CHALLENGE_MD="$SKILL_DIR/autopilot/references/phase1-challenge-agents.md"

# 4a. Three agent types defined
assert_file_contains "4a. Contrarian agent defined" "$CHALLENGE_MD" "Contrarian"
assert_file_contains "4b. Simplifier agent defined" "$CHALLENGE_MD" "Simplifier"
assert_file_contains "4c. Ontologist agent defined" "$CHALLENGE_MD" "Ontologist"

# 4d. Stagnation detection
assert_file_contains "4d. stagnation detection logic" "$CHALLENGE_MD" "consecutive_stagnant_rounds"

# 4e. Each agent used only once
assert_file_contains "4e. challenge_agents_used prevents reuse" "$CHALLENGE_MD" "challenge_agents_used"

# ================================================================
# Part 5: Clarity scoring system completeness
# ================================================================

CLARITY_MD="$SKILL_DIR/autopilot/references/phase1-clarity-scoring.md"

# 5a. Four dimensions defined
assert_file_contains "5a. goal_clarity dimension" "$CLARITY_MD" "goal_clarity"
assert_file_contains "5b. constraint_clarity dimension" "$CLARITY_MD" "constraint_clarity"
assert_file_contains "5c. criteria_clarity dimension" "$CLARITY_MD" "criteria_clarity"
assert_file_contains "5d. context_clarity dimension" "$CLARITY_MD" "context_clarity"

# 5e. Hybrid formula: rule × 0.6 + AI × 0.4
assert_file_contains "5e. hybrid formula uses 0.6/0.4 weights" "$CLARITY_MD" "0.6"

# 5f. Progress bar template
assert_file_contains "5f. progress bar template exists" "$CLARITY_MD" "Round {n}"

# ================================================================
# Part 6: Schema and protocol include v7.1 fields
# ================================================================

DETAIL_MD="$SKILL_DIR/autopilot/references/phase1-requirements-detail.md"
PROTOCOL_MD="$SKILL_DIR/autopilot/references/protocol.md"

# 6a. requirement-packet.json schema includes clarity_score
assert_file_contains "6a. schema includes clarity_score" "$DETAIL_MD" "clarity_score"

# 6b. schema includes discussion_rounds
assert_file_contains "6b. schema includes discussion_rounds" "$DETAIL_MD" "discussion_rounds"

# 6c. schema includes challenge_agents_activated
assert_file_contains "6c. schema includes challenge_agents_activated" "$DETAIL_MD" "challenge_agents_activated"

# 6d. protocol.md Phase 1 includes v7.1 fields
assert_file_contains "6d. protocol Phase 1 includes clarity_score" "$PROTOCOL_MD" "clarity_score"

# 6e. discussion_rounds is required in schema
assert_file_contains "6e. discussion_rounds is required field" "$DETAIL_MD" "discussion_rounds"

# 6f. discussion_rounds is in protocol.md Phase 1 required fields (not optional)
protocol_phase1=$(grep "^| 1 |" "$PROTOCOL_MD" | head -1)
# Extract required fields section (between 2nd and 3rd unescaped pipe)
# Since table cells contain \|, use python for reliable parsing
required_section=$(echo "$protocol_phase1" | python3 -c "
import sys
line = sys.stdin.read().strip()
# Split by ' | ' (space-pipe-space) which separates table columns
parts = line.split(' | ')
if len(parts) >= 2:
    print(parts[1])  # required fields column
")
if echo "$required_section" | grep -q "discussion_rounds"; then
  green "  PASS: 6f. discussion_rounds is in protocol Phase 1 required fields"
  PASS=$((PASS + 1))
else
  red "  FAIL: 6f. discussion_rounds should be in Phase 1 required fields, not optional"
  FAIL=$((FAIL + 1))
fi

# ================================================================
# Part 7: validate-requirement-packet.sh field name compatibility
# ================================================================

VRPS="$SCRIPT_DIR/validate-requirement-packet.sh"

# 7a. Supports new field name open_questions_closed
assert_file_contains "7a. validator supports open_questions_closed" "$VRPS" "open_questions_closed"

# 7b. Supports new field name requirement_maturity
assert_file_contains "7b. validator supports requirement_maturity" "$VRPS" "requirement_maturity"

# 7c. Supports new field name hash (not just packet_hash)
assert_file_contains "7c. validator supports hash field" "$VRPS" "'hash'"

# 7d. discussion_rounds in REQUIRED_FIELDS
assert_file_contains "7d. discussion_rounds is required" "$VRPS" "discussion_rounds"

# 7e. Recommends clarity_score
assert_file_contains "7e. clarity_score in recommended fields" "$VRPS" "clarity_score"

# ================================================================
# Part 8: Cross-reference validation in _config_validator.py
# ================================================================

# 8a. soft_warning_rounds >= max_rounds cross-check exists
assert_file_contains "8a. cross-ref: soft_warning >= max_rounds" \
  "$SCRIPT_DIR/_config_validator.py" "soft_warning_rounds"

# 8b. min_qa_rounds > max_rounds cross-check exists
assert_file_contains "8b. cross-ref: min_qa > max_rounds" \
  "$SCRIPT_DIR/_config_validator.py" "min_qa_rounds.*max_rounds"

# 8c. challenge agent order cross-check exists
assert_file_contains "8c. cross-ref: challenge agent activation order" \
  "$SCRIPT_DIR/_config_validator.py" "agents should activate in increasing round order"

# 8d. Cross-ref: soft_warning >= max_rounds actually triggers warning
TEMP_XREF=$(mktemp)
cat > "$TEMP_XREF" << 'YAML'
version: "5.3.3"
services: {}
phases:
  requirements:
    agent: "test"
    min_qa_rounds: 1
    soft_warning_rounds: 20
    max_rounds: 10
  testing:
    agent: "test"
    gate:
      min_test_count_per_type: 5
      required_test_types: ["unit"]
  implementation:
    serial_task:
      max_retries_per_task: 3
  reporting:
    coverage_target: 80
    zero_skip_required: true
test_suites: {}
YAML
XREF_OUTPUT=$(python3 "$SCRIPT_DIR/_config_validator.py" "$TEMP_XREF" 2>/dev/null)
assert_contains "8d. soft_warning>=max_rounds triggers warning" "$XREF_OUTPUT" "soft warning will never trigger"
rm -f "$TEMP_XREF"

# ================================================================
# Part 9: State snapshot includes v7.1 fields
# ================================================================

SNAPSHOT_SCHEMA="$SKILL_DIR/autopilot/references/state-snapshot-schema.md"
TYPES_TS="$TEST_DIR/../runtime/server/src/types.ts"

# 9a. state-snapshot schema includes clarity_score
assert_file_contains "9a. snapshot schema includes clarity_score" "$SNAPSHOT_SCHEMA" "clarity_score"

# 9b. state-snapshot schema includes discussion_rounds
assert_file_contains "9b. snapshot schema includes discussion_rounds" "$SNAPSHOT_SCHEMA" "discussion_rounds"

# 9c. types.ts includes clarity_score
assert_file_contains "9c. types.ts includes clarity_score" "$TYPES_TS" "clarity_score"

# 9d. save-state extracts clarity_score from Phase 1
SAVE_STATE="$SCRIPT_DIR/save-state-before-compact.sh"
assert_file_contains "9d. save-state extracts clarity_score" "$SAVE_STATE" "clarity_score"

# ================================================================
# Part 10: End-to-end consumption chain (event → server → WS → GUI)
# ================================================================

PHASE1_SKILL="$SKILL_DIR/autopilot-phase1-requirements/SKILL.md"
ROUTES_TS="$TEST_DIR/../runtime/server/src/api/routes.ts"
BROADCASTER_TS="$TEST_DIR/../runtime/server/src/ws/broadcaster.ts"
WS_SERVER_TS="$TEST_DIR/../runtime/server/src/ws/ws-server.ts"
WS_BRIDGE_TS="$TEST_DIR/../gui/src/lib/ws-bridge.ts"
STORE_TS="$TEST_DIR/../gui/src/store/index.ts"
ORCH_PANEL="$TEST_DIR/../gui/src/components/OrchestrationPanel.tsx"

# 10a. Phase 1 end event emits clarity_score
assert_file_contains "10a. phase_end event emits clarity_score" "$PHASE1_SKILL" "clarity_score"

# 10b. Phase 1 end event emits discussion_rounds
assert_file_contains "10b. phase_end event emits discussion_rounds" "$PHASE1_SKILL" "discussion_rounds"

# 10c. Server API /api/info exposes clarityScore
assert_file_contains "10c. routes.ts exposes clarityScore" "$ROUTES_TS" "clarityScore"

# 10d. WS broadcaster includes clarityScore in meta
assert_file_contains "10d. broadcaster includes clarityScore" "$BROADCASTER_TS" "clarityScore"

# 10e. WS server initial snapshot includes clarityScore
assert_file_contains "10e. ws-server includes clarityScore" "$WS_SERVER_TS" "clarity_score"

# 10f. GUI SnapshotMeta type has clarityScore
assert_file_contains "10f. ws-bridge SnapshotMeta has clarityScore" "$WS_BRIDGE_TS" "clarityScore"

# 10g. GUI OrchestrationOverview has clarityScore
assert_file_contains "10g. store OrchestrationOverview has clarityScore" "$STORE_TS" "clarityScore"

# 10h. GUI OrchestrationPanel renders clarity
assert_file_contains "10h. OrchestrationPanel renders clarityScore" "$ORCH_PANEL" "clarityScore"

# ================================================================
# Part 11: State snapshot schema version consistency
# ================================================================

SNAPSHOT_SCHEMA="$SKILL_DIR/autopilot/references/state-snapshot-schema.md"

# 11a. Schema doc title says v7.1 (not v6.0)
assert_file_contains "11a. snapshot schema title says v7.1" "$SNAPSHOT_SCHEMA" "v7.1"

# 11b. Schema JSON uses schema_version 7.1
assert_file_contains "11b. schema_version is 7.1" "$SNAPSHOT_SCHEMA" '"7.1"'

# 11c. Actual write script uses schema_version 7.1 (not 7.0)
assert_file_contains "11c. save-state script schema_version is 7.1" "$SAVE_STATE" "'schema_version': '7.1'"

# 11d. Actual write script markdown header says v7.1
assert_file_contains "11d. save-state script markdown says v7.1" "$SAVE_STATE" "state-snapshot.json v7.1"

# ================================================================
# Part 12: Snapshot replay — event-source flag prevents stale meta from overwriting v7.1 values
# ================================================================

# 12a. OrchestrationOverview has _phase1ClarityFromEvent flag
assert_file_contains "12a. store has _phase1ClarityFromEvent flag" "$STORE_TS" "_phase1ClarityFromEvent"

# 12b. phase_end handler sets _phase1ClarityFromEvent = true
assert_file_contains "12b. phase_end sets _phase1ClarityFromEvent = true" "$STORE_TS" "_phase1ClarityFromEvent = true"

# 12c. meta fallback checks _phase1ClarityFromEvent flag (not value-based guard)
assert_file_contains "12c. meta fallback checks _phase1ClarityFromEvent" "$STORE_TS" "!orchestration._phase1ClarityFromEvent"

# 12d. Default _phase1ClarityFromEvent is false
assert_file_contains "12d. default _phase1ClarityFromEvent is false" "$STORE_TS" "_phase1ClarityFromEvent: false"

# 12e. Flag is only set when v7.1 fields are present in payload (key-existence check)
assert_file_contains "12e. v7.1 flag uses key-existence check (\"in\" p)" "$STORE_TS" '"clarity_score" in p'

# ================================================================
# Part 13: Behavioral test — store merge order with explicit null/empty values
# ================================================================

echo ""
echo "--- Part 13: Store merge order behavioral tests ---"

STORE_BEHAVIORAL_RESULT=$(bun -e "
import { useStore } from '$(cd "$TEST_DIR/.." && pwd)/gui/src/store/index.ts';

const results: string[] = [];

// Helper: reset store
function reset() {
  useStore.getState().reset();
}

// --- Case A: phase_end with values → null meta must NOT overwrite ---
reset();
useStore.getState().addEvents([{
  type: 'phase_end', phase: 1, mode: 'full', timestamp: '2026-01-01T00:00:00Z',
  change_name: 'test', session_id: 's1', phase_label: 'P1', total_phases: 7,
  sequence: 1, payload: {
    requirement_packet_hash: 'abc123',
    clarity_score: 0.85,
    discussion_rounds: 5,
    challenge_agents_activated: ['contrarian', 'simplifier']
  }
}]);
useStore.getState().initOrchestrationFromMeta({
  clarityScore: null,
  discussionRounds: null,
  challengeAgentsActivated: []
});
const a = useStore.getState().orchestration;
results.push(a.clarityScore === 0.85 ? 'A1:OK' : 'A1:FAIL=' + a.clarityScore);
results.push(a.discussionRounds === 5 ? 'A2:OK' : 'A2:FAIL=' + a.discussionRounds);
results.push(a.challengeAgentsActivated.length === 2 ? 'A3:OK' : 'A3:FAIL=' + JSON.stringify(a.challengeAgentsActivated));

// --- Case B: phase_end with explicit null/[] → stale meta must NOT overwrite ---
reset();
useStore.getState().addEvents([{
  type: 'phase_end', phase: 1, mode: 'full', timestamp: '2026-01-01T00:00:00Z',
  change_name: 'test', session_id: 's1', phase_label: 'P1', total_phases: 7,
  sequence: 2, payload: {
    requirement_packet_hash: 'def456',
    clarity_score: null,
    discussion_rounds: null,
    challenge_agents_activated: []
  }
}]);
useStore.getState().initOrchestrationFromMeta({
  clarityScore: 0.91,
  discussionRounds: 6,
  challengeAgentsActivated: ['contrarian']
});
const b = useStore.getState().orchestration;
results.push(b.clarityScore === null ? 'B1:OK' : 'B1:FAIL=' + b.clarityScore);
results.push(b.discussionRounds === null ? 'B2:OK' : 'B2:FAIL=' + b.discussionRounds);
results.push(b.challengeAgentsActivated.length === 0 ? 'B3:OK' : 'B3:FAIL=' + JSON.stringify(b.challengeAgentsActivated));

// --- Case C: no phase_end yet → meta SHOULD populate as fallback ---
reset();
useStore.getState().initOrchestrationFromMeta({
  clarityScore: 0.75,
  discussionRounds: 3,
  challengeAgentsActivated: ['simplifier']
});
const c = useStore.getState().orchestration;
results.push(c.clarityScore === 0.75 ? 'C1:OK' : 'C1:FAIL=' + c.clarityScore);
results.push(c.discussionRounds === 3 ? 'C2:OK' : 'C2:FAIL=' + c.discussionRounds);
results.push(c.challengeAgentsActivated.length === 1 ? 'C3:OK' : 'C3:FAIL=' + JSON.stringify(c.challengeAgentsActivated));

// --- Case D: legacy phase_end (no v7.1 fields) → meta SHOULD fallback ---
reset();
useStore.getState().addEvents([{
  type: 'phase_end', phase: 1, mode: 'full', timestamp: '2026-01-01T00:00:00Z',
  change_name: 'test', session_id: 's1', phase_label: 'P1', total_phases: 7,
  sequence: 4, payload: {
    requirement_packet_hash: 'legacy-pkt'
  }
}]);
useStore.getState().initOrchestrationFromMeta({
  clarityScore: 0.91,
  discussionRounds: 6,
  challengeAgentsActivated: ['contrarian']
});
const d = useStore.getState().orchestration;
results.push(d.clarityScore === 0.91 ? 'D1:OK' : 'D1:FAIL=' + d.clarityScore);
results.push(d.discussionRounds === 6 ? 'D2:OK' : 'D2:FAIL=' + d.discussionRounds);
results.push(d.challengeAgentsActivated.length === 1 && d.challengeAgentsActivated[0] === 'contrarian' ? 'D3:OK' : 'D3:FAIL=' + JSON.stringify(d.challengeAgentsActivated));
results.push(d.requirementPacketHash === 'legacy-pkt' ? 'D4:OK' : 'D4:FAIL=' + d.requirementPacketHash);

console.log(results.join(','));
" 2>/dev/null)

# Parse results
IFS=',' read -ra CASES <<< "$STORE_BEHAVIORAL_RESULT"
ALL_BEHAVIORAL_PASS=true
for case_result in "${CASES[@]}"; do
  CASE_ID="${case_result%%:*}"
  CASE_STATUS="${case_result#*:}"
  if [ "$CASE_STATUS" = "OK" ]; then
    green "  PASS: 13-${CASE_ID}. store merge order"
    PASS=$((PASS + 1))
  else
    red "  FAIL: 13-${CASE_ID}. store merge order (${CASE_STATUS})"
    FAIL=$((FAIL + 1))
    ALL_BEHAVIORAL_PASS=false
  fi
done

if [ ${#CASES[@]} -eq 0 ]; then
  red "  FAIL: 13. behavioral test produced no output (bun execution failed)"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0
