#!/usr/bin/env bash
# test_phase1_early_interrupt.sh — D11 / Task 17 contract verification
# Verifies that both Phase 1 envelope schemas accept an optional `interrupt`
# field (severity ∈ {blocker,warning}, reason ≥ 5 chars) and that the
# autopilot-phase1-requirements SKILL.md documents the early-interrupt
# protocol (blocker → abort parallel cohort + AskUserQuestion; warning → log).

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
SCHEMAS_DIR="$(cd "$TEST_DIR/../runtime/schemas" && pwd)"
SKILL_MD="$(cd "$TEST_DIR/../skills/autopilot-phase1-requirements" && pwd)/SKILL.md"
# shellcheck disable=SC1091
source "$TEST_DIR/_test_helpers.sh"
# shellcheck disable=SC1091
source "$TEST_DIR/_fixtures.sh"

HOOK="$SCRIPT_DIR/validate-phase1-envelope.sh"
SCAN_SCHEMA="$SCHEMAS_DIR/phase1-scan-envelope.schema.json"
RESEARCH_SCHEMA="$SCHEMAS_DIR/phase1-research-envelope.schema.json"

echo "=== Phase 1 early-interrupt protocol tests (D11 / Task 17) ==="

assert_file_exists "scan envelope schema present"     "$SCAN_SCHEMA"
assert_file_exists "research envelope schema present" "$RESEARCH_SCHEMA"
assert_file_exists "phase1-requirements SKILL.md present" "$SKILL_MD"

# ---------------------------------------------------------------------------
# Schema assertions (use python for structural checks)
# ---------------------------------------------------------------------------

schema_has_interrupt() {
  python3 -c "
import json,sys
p=json.load(open(sys.argv[1]))
it=p.get('properties',{}).get('interrupt')
ok=(isinstance(it,dict)
    and it.get('type')=='object'
    and 'severity' in it.get('required',[])
    and 'reason'   in it.get('required',[])
    and it['properties']['severity'].get('enum')==['blocker','warning']
    and it['properties']['reason'].get('minLength',0)>=5)
sys.exit(0 if ok else 1)
" "$1"
}

schema_interrupt_not_top_required() {
  python3 -c "
import json,sys
p=json.load(open(sys.argv[1]))
sys.exit(1 if 'interrupt' in p.get('required',[]) else 0)
" "$1"
}

exit_code=0; schema_has_interrupt "$SCAN_SCHEMA" || exit_code=$?
assert_exit "scan schema: interrupt{severity,reason} present" 0 "$exit_code"

exit_code=0; schema_has_interrupt "$RESEARCH_SCHEMA" || exit_code=$?
assert_exit "research schema: interrupt{severity,reason} present" 0 "$exit_code"

exit_code=0; schema_interrupt_not_top_required "$SCAN_SCHEMA" || exit_code=$?
assert_exit "scan schema: interrupt NOT in top-level required" 0 "$exit_code"

exit_code=0; schema_interrupt_not_top_required "$RESEARCH_SCHEMA" || exit_code=$?
assert_exit "research schema: interrupt NOT in top-level required" 0 "$exit_code"

# severity enum strict equality
python3 -c "
import json,sys
for f in sys.argv[1:]:
    p=json.load(open(f))
    e=p['properties']['interrupt']['properties']['severity']['enum']
    assert e==['blocker','warning'], (f,e)
" "$SCAN_SCHEMA" "$RESEARCH_SCHEMA"
assert_exit "both schemas: severity enum is exactly [blocker,warning]" 0 "$?"

# ---------------------------------------------------------------------------
# SKILL.md documentation assertions
# ---------------------------------------------------------------------------

assert_file_contains "SKILL.md: 早停 interrupt 协议 step header" "$SKILL_MD" "早停 interrupt 协议"
assert_file_contains "SKILL.md: 立即中断未完成路 wording"          "$SKILL_MD" "立即中断未完成路"
assert_file_contains "SKILL.md: Task abort wording"                "$SKILL_MD" "Task abort"
assert_file_contains "SKILL.md: AskUserQuestion instruction"       "$SKILL_MD" "AskUserQuestion"
assert_file_contains "SKILL.md: interrupt.reason reference"        "$SKILL_MD" "interrupt.reason"
assert_file_contains "SKILL.md: blocker severity branch"           "$SKILL_MD" "severity == \"blocker\""
assert_file_contains "SKILL.md: warning severity branch"           "$SKILL_MD" "severity == \"warning\""
assert_file_contains "SKILL.md: warning 仅记录 log-only flow"       "$SKILL_MD" "仅记录"
assert_file_contains "SKILL.md: 禁止忽略 interrupt"                 "$SKILL_MD" "忽略 interrupt"

# ---------------------------------------------------------------------------
# Hook smoke: validate that interrupt payloads flow through L2 as expected
# ---------------------------------------------------------------------------

setup_autopilot_fixture

run_hook() { echo "$1" | bash "$HOOK" 2>/dev/null; }

wrap_event() {
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

BLOCK_NEEDLE='"decision": "block"'

# Valid scan envelope with blocker interrupt → MUST pass (interrupt is optional
# and schema-compliant; early-stop is an orchestration decision, not L2 block).
SCAN_WITH_BLOCKER='{"status":"blocked","summary":"Blocker detected during scan.","decision_points":[],"tech_constraints":[],"key_files":[],"output_files":["context/project-context.md"],"interrupt":{"severity":"blocker","reason":"tech stack X not supported"}}'
event=$(wrap_event "1-scan" "$SCAN_WITH_BLOCKER")
exit_code=0
output=$(run_hook "$event") || exit_code=$?
assert_exit "scan with blocker interrupt → exit 0" 0 "$exit_code"
assert_not_contains "scan with blocker interrupt → no block" "$output" "$BLOCK_NEEDLE"

# Invalid severity value → schema violation → block
SCAN_BAD_SEVERITY='{"status":"ok","summary":"Scan complete but bad interrupt.","decision_points":[],"tech_constraints":[],"key_files":[],"output_files":["context/project-context.md"],"interrupt":{"severity":"unknown","reason":"something"}}'
event=$(wrap_event "1-scan" "$SCAN_BAD_SEVERITY")
exit_code=0
output=$(run_hook "$event") || exit_code=$?
assert_exit "scan with unknown severity → exit 0" 0 "$exit_code"
assert_contains "scan with unknown severity → block" "$output" "$BLOCK_NEEDLE"

# Missing required `reason` → block
SCAN_MISSING_REASON='{"status":"ok","summary":"Scan complete missing reason.","decision_points":[],"tech_constraints":[],"key_files":[],"output_files":["context/project-context.md"],"interrupt":{"severity":"blocker"}}'
event=$(wrap_event "1-scan" "$SCAN_MISSING_REASON")
exit_code=0
output=$(run_hook "$event") || exit_code=$?
assert_exit "scan missing interrupt.reason → exit 0" 0 "$exit_code"
assert_contains "scan missing interrupt.reason → block" "$output" "$BLOCK_NEEDLE"

# Research envelope with warning interrupt → pass
RESEARCH_WITH_WARNING='{"status":"warning","summary":"Research completed with caveats.","decision_points":[],"tech_constraints":[],"complexity":"small","key_files":[],"output_file":"context/research-findings.md","interrupt":{"severity":"warning","reason":"API rate limit hit partway"}}'
event=$(wrap_event "1-research" "$RESEARCH_WITH_WARNING")
exit_code=0
output=$(run_hook "$event") || exit_code=$?
assert_exit "research with warning interrupt → exit 0" 0 "$exit_code"
assert_not_contains "research with warning interrupt → no block" "$output" "$BLOCK_NEEDLE"

teardown_autopilot_fixture

echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
