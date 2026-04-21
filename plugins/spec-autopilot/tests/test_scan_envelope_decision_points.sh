#!/usr/bin/env bash
# test_scan_envelope_decision_points.sh — Task C14
# Assert ScanAgent envelope schema + parallel-phase1.md contract carry
# decision_points (required) and conflicts_detected (optional) fields.

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
SCHEMAS_DIR="$(cd "$TEST_DIR/../runtime/schemas" && pwd)"
REFS_DIR="$(cd "$TEST_DIR/../skills/autopilot/references" && pwd)"
# shellcheck disable=SC1091
source "$TEST_DIR/_test_helpers.sh"
# shellcheck disable=SC1091
source "$TEST_DIR/_fixtures.sh"

SCHEMA="$SCHEMAS_DIR/phase1-scan-envelope.schema.json"
DOC="$REFS_DIR/parallel-phase1.md"
HOOK="$SCRIPT_DIR/validate-phase1-envelope.sh"

echo "=== C14: Scan envelope decision_points / conflicts_detected ==="

# 1. Schema file has decision_points in required[]
python3 - "$SCHEMA" <<'PY'
import json, sys
schema = json.load(open(sys.argv[1]))
req = schema.get("required", [])
assert "decision_points" in req, f"decision_points must be required; got {req}"
PY
assert_exit "decision_points listed in schema required[]" 0 $?

# 2. Schema file defines conflicts_detected property
python3 - "$SCHEMA" <<'PY'
import json, sys
schema = json.load(open(sys.argv[1]))
props = schema.get("properties", {})
cd = props.get("conflicts_detected")
assert cd is not None, "conflicts_detected property must be defined"
assert cd.get("type") == "array", "conflicts_detected must be array"
item = cd.get("items", {})
assert item.get("type") == "object", "conflicts_detected items must be objects"
item_req = item.get("required", [])
for key in ("topic", "description", "severity"):
    assert key in item_req, f"conflicts_detected item missing required '{key}'"
sev_enum = item.get("properties", {}).get("severity", {}).get("enum", [])
for lvl in ("low", "medium", "high"):
    assert lvl in sev_enum, f"severity enum missing '{lvl}'"
PY
assert_exit "conflicts_detected property schema is well-formed" 0 $?

# 3. Schema description no longer advertises "will move to required after Task C14"
assert_file_not_contains "schema description drops C14 migration note" \
  "$SCHEMA" "will move to required after Task C14 lands"

# 4. parallel-phase1.md contains ScanAgent four-field contract block
assert_file_contains "doc defines ScanAgent 四要素契约 header" \
  "$DOC" "ScanAgent 四要素契约"

# 5. ScanAgent contract references scan envelope schema
assert_file_contains "doc ScanAgent contract cites scan envelope schema" \
  "$DOC" "phase1-scan-envelope.schema.json"

# 6. ScanAgent contract cites the auto_scan.agent config (no hardcoded name)
assert_file_contains "doc ScanAgent contract cites config-driven agent" \
  "$DOC" "config.phases.requirements.auto_scan.agent"

# 7. ScanAgent contract mentions decision_points emission
assert_file_contains "doc ScanAgent contract mentions decision_points" \
  "$DOC" "decision_points"

# 8. ScanAgent contract mentions conflicts_detected emission rule
assert_file_contains "doc ScanAgent contract mentions conflicts_detected" \
  "$DOC" "conflicts_detected"

# 9. ScanAgent conflict emission wording present
assert_file_contains "doc ScanAgent documents project-pattern vs requirement conflict rule" \
  "$DOC" "项目模式与需求冲突"

# --- Hook behavior: required enforcement ---
setup_autopilot_fixture

run_hook() { echo "$1" | bash "$HOOK" 2>/dev/null; }
BLOCK_NEEDLE='"decision": "block"'

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

# 10. Scan envelope WITHOUT decision_points → block (required enforced)
SCAN_NO_DP='{"status":"ok","summary":"Scan without decision_points.","tech_constraints":["Node >= 18"],"existing_patterns":["service-layer"],"key_files":["src/index.ts"],"output_files":["context/project-context.md"]}'
event=$(wrap_event "1-scan" "$SCAN_NO_DP")
exit_code=0
output=$(run_hook "$event") || exit_code=$?
assert_exit "scan missing decision_points → hook exit 0" 0 "$exit_code"
assert_contains "scan missing decision_points → block" "$output" "$BLOCK_NEEDLE"
assert_contains "scan missing decision_points → error cites decision_points" "$output" "decision_points"

# 11. Scan envelope WITH decision_points + empty conflicts_detected[] → pass
SCAN_OK='{"status":"ok","summary":"Scan with decision_points and empty conflicts.","decision_points":[{"topic":"状态管理","options":["Redux","Zustand"],"recommendation":"保留 Redux"}],"conflicts_detected":[],"tech_constraints":["Node >= 18"],"existing_patterns":["service-layer"],"key_files":["src/index.ts"],"output_files":["context/project-context.md","context/existing-patterns.md","context/tech-constraints.md"]}'
event=$(wrap_event "1-scan" "$SCAN_OK")
exit_code=0
output=$(run_hook "$event") || exit_code=$?
assert_exit "scan with decision_points + empty conflicts → hook exit 0" 0 "$exit_code"
assert_not_contains "scan with decision_points + empty conflicts → no block" "$output" "$BLOCK_NEEDLE"

# 12. Scan envelope with populated conflicts_detected[] → pass
SCAN_CONFLICT='{"status":"warning","summary":"Scan detected pattern conflict with requirement.","decision_points":[{"topic":"数据库","options":["sqlite","postgres"],"recommendation":"postgres"}],"conflicts_detected":[{"topic":"数据库选型","description":"现有模式使用 sqlite 但新需求要求 postgres 多租户","severity":"high","related_decision_point":"数据库"}],"tech_constraints":["Node >= 18"],"existing_patterns":["single-tenant"],"key_files":["src/db.ts"],"output_files":["context/project-context.md","context/existing-patterns.md","context/tech-constraints.md"]}'
event=$(wrap_event "1-scan" "$SCAN_CONFLICT")
exit_code=0
output=$(run_hook "$event") || exit_code=$?
assert_exit "scan with populated conflicts_detected → hook exit 0" 0 "$exit_code"
assert_not_contains "scan with populated conflicts_detected → no block" "$output" "$BLOCK_NEEDLE"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
