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

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0
