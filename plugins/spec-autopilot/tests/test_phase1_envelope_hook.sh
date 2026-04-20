#!/usr/bin/env bash
# test_phase1_envelope_hook.sh — L2 hook schema validation for Phase 1 sub-markers
# Target: runtime/scripts/validate-phase1-envelope.sh + associated schemas

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
SCHEMAS_DIR="$(cd "$TEST_DIR/../runtime/schemas" && pwd)"
# shellcheck disable=SC1091
source "$TEST_DIR/_test_helpers.sh"
# shellcheck disable=SC1091
source "$TEST_DIR/_fixtures.sh"

HOOK="$SCRIPT_DIR/validate-phase1-envelope.sh"

echo "=== Phase 1 L2 envelope hook tests ==="

# --- Pre-flight: script + schemas present ---
assert_file_exists "hook script present" "$HOOK"
assert_file_exists "phase1-scan-envelope schema present" "$SCHEMAS_DIR/phase1-scan-envelope.schema.json"
assert_file_exists "phase1-research-envelope schema present" "$SCHEMAS_DIR/phase1-research-envelope.schema.json"
assert_file_exists "synthesizer-verdict schema present" "$SCHEMAS_DIR/synthesizer-verdict.schema.json"

# Activate autopilot session so Layer 0 bypass does not short-circuit
setup_autopilot_fixture

run_hook() {
  echo "$1" | bash "$HOOK" 2>/dev/null
}

BLOCK_NEEDLE='"decision": "block"'

# Fixtures: valid envelopes for each marker ---------------------------------
VALID_SCAN='{"status":"ok","summary":"Scanned repo and extracted steering context.","decision_points":[{"topic":"状态管理选型","options":["Redux","Zustand"],"recommendation":"保留 Redux"}],"tech_constraints":["Node >= 18"],"existing_patterns":["service-layer"],"key_files":["src/store.ts"],"complexity":"medium","output_files":["context/project-context.md","context/existing-patterns.md","context/tech-constraints.md"]}'

VALID_RESEARCH='{"status":"ok","summary":"Research across 5 libs completed.","decision_points":[{"topic":"http client","options":["axios","fetch"],"recommendation":"fetch"}],"tech_constraints":["no extra runtime deps"],"complexity":"small","key_files":["src/net.ts"],"output_file":"context/research-findings.md"}'

VALID_SYNTH='{"coverage_ok":true,"conflicts":[],"confidence":0.87,"requires_human":false,"ambiguities":[],"rationale":"两路 envelope 无冲突，合并 3 个决策点。","merged_decision_points":[{"topic":"x","options":["a","b"],"recommendation":"a","evidence_refs":["scan:x"]}]}'

wrap_event() {
  # $1 = marker suffix (1-scan / 1-research / 1-synthesizer)
  # $2 = tool_response string (escaped JSON fragment)
  local marker="$1" response="$2"
  python3 -c "
import json,sys
print(json.dumps({
  'tool_name':'Task',
  'cwd':'$REPO_ROOT',
  'tool_input':{'description':'phase1 sub','prompt':'<!-- autopilot-phase:$marker -->\nGo.'},
  'tool_response': sys.argv[1],
}, ensure_ascii=False))
" "$response"
}

# 1. Happy path: valid envelopes → no block -----------------------------------
for pair in "1-scan:$VALID_SCAN" "1-research:$VALID_RESEARCH" "1-synthesizer:$VALID_SYNTH"; do
  marker="${pair%%:*}"
  env_json="${pair#*:}"
  event=$(wrap_event "$marker" "$env_json")
  exit_code=0
  output=$(run_hook "$event") || exit_code=$?
  assert_exit "$marker valid envelope → exit 0" 0 "$exit_code"
  assert_not_contains "$marker valid → no block" "$output" "$BLOCK_NEEDLE"
done

# 2. No phase-1 marker → hook is pass-through ---------------------------------
event=$(python3 -c "
import json
print(json.dumps({
  'tool_name':'Task',
  'cwd':'$REPO_ROOT',
  'tool_input':{'description':'random','prompt':'<!-- autopilot-phase:3 -->\nGo.'},
  'tool_response':'garbage text no json',
}))
")
exit_code=0
output=$(run_hook "$event") || exit_code=$?
assert_exit "non-phase1 marker → exit 0" 0 "$exit_code"
assert_not_contains "non-phase1 marker → no block" "$output" "block"

# 3. Empty stdin → exit 0 no output -------------------------------------------
exit_code=0
output=$(echo "" | bash "$HOOK" 2>/dev/null) || exit_code=$?
assert_exit "empty stdin → exit 0" 0 "$exit_code"
assert_not_contains "empty stdin → no block" "$output" "block"

# 4. Empty tool_response with phase1 marker → block ---------------------------
event=$(wrap_event "1-scan" "")
exit_code=0
output=$(run_hook "$event") || exit_code=$?
assert_exit "scan empty response → exit 0" 0 "$exit_code"
assert_contains "scan empty response → block" "$output" "$BLOCK_NEEDLE"

# 5. No JSON object in response → block ---------------------------------------
event=$(wrap_event "1-research" "I finished but forgot to emit JSON.")
exit_code=0
output=$(run_hook "$event") || exit_code=$?
assert_exit "research no-JSON → exit 0" 0 "$exit_code"
assert_contains "research no-JSON → block" "$output" "$BLOCK_NEEDLE"

# 6. Schema violations → block (one failure per marker) -----------------------

# 6a. scan missing required `output_files`
BAD_SCAN='{"status":"ok","summary":"Scanned repo but no output listed.","decision_points":[],"tech_constraints":[],"existing_patterns":[]}'
event=$(wrap_event "1-scan" "$BAD_SCAN")
exit_code=0
output=$(run_hook "$event") || exit_code=$?
assert_exit "scan missing output_files → exit 0" 0 "$exit_code"
assert_contains "scan missing output_files → block" "$output" "$BLOCK_NEEDLE"
assert_contains "scan block mentions output_files" "$output" "output_files"

# 6a-bis. scan missing required `tech_constraints` → block
#   (guards against accidental removal of tech_constraints from required[]
#    while decision_points/existing_patterns remain optional pre-C14.)
BAD_SCAN_NO_TECH='{"status":"ok","summary":"Scanned repo and got output files.","key_files":["a.ts"],"output_files":["context/project-context.md"]}'
event=$(wrap_event "1-scan" "$BAD_SCAN_NO_TECH")
exit_code=0
output=$(run_hook "$event") || exit_code=$?
assert_exit "scan missing tech_constraints → exit 0" 0 "$exit_code"
assert_contains "scan missing tech_constraints → block" "$output" "$BLOCK_NEEDLE"
assert_contains "scan block mentions tech_constraints" "$output" "tech_constraints"

# 6a-ter. scan WITHOUT decision_points + existing_patterns but all other required
#   fields present → passes (pre-C14 these two fields are optional; schema still
#   validates them when present). Regression guard for schema contract drift.
MIN_SCAN='{"status":"ok","summary":"Minimal valid scan pre-C14 without optional decision_points.","tech_constraints":["Node >= 18"],"key_files":["src/index.ts"],"output_files":["context/project-context.md","context/existing-patterns.md","context/tech-constraints.md"]}'
event=$(wrap_event "1-scan" "$MIN_SCAN")
exit_code=0
output=$(run_hook "$event") || exit_code=$?
assert_exit "scan without decision_points/existing_patterns → exit 0" 0 "$exit_code"
assert_not_contains "scan without decision_points/existing_patterns → no block" "$output" "$BLOCK_NEEDLE"

# 6b. research: bad status enum
BAD_RESEARCH='{"status":"done","summary":"Research across 5 libs completed.","decision_points":[],"tech_constraints":[],"complexity":"small","key_files":[],"output_file":"context/research-findings.md"}'
event=$(wrap_event "1-research" "$BAD_RESEARCH")
exit_code=0
output=$(run_hook "$event") || exit_code=$?
assert_exit "research bad status → exit 0" 0 "$exit_code"
assert_contains "research bad status → block" "$output" "$BLOCK_NEEDLE"

# 6c. synthesizer: missing rationale + bad confidence type
BAD_SYNTH='{"coverage_ok":true,"conflicts":[],"confidence":"high","requires_human":false,"ambiguities":[],"merged_decision_points":[]}'
event=$(wrap_event "1-synthesizer" "$BAD_SYNTH")
exit_code=0
output=$(run_hook "$event") || exit_code=$?
assert_exit "synth bad envelope → exit 0" 0 "$exit_code"
assert_contains "synth bad envelope → block" "$output" "$BLOCK_NEEDLE"
assert_contains "synth block mentions rationale" "$output" "rationale"

# 7. Marker can appear in description field too --------------------------------
event=$(python3 -c "
import json
print(json.dumps({
  'tool_name':'Task',
  'cwd':'$REPO_ROOT',
  'tool_input':{'description':'<!-- autopilot-phase:1-scan --> boundary run','prompt':'Body'},
  'tool_response':'not json at all',
}))
")
exit_code=0
output=$(run_hook "$event") || exit_code=$?
assert_exit "marker-in-description → exit 0" 0 "$exit_code"
assert_contains "marker-in-description → block when invalid" "$output" "$BLOCK_NEEDLE"

teardown_autopilot_fixture

echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
