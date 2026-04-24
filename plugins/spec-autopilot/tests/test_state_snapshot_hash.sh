#!/usr/bin/env bash
# test_state_snapshot_hash.sh — Tests for state-snapshot.json hash consistency
# Verifies: snapshot generation, hash verification, compact/restore round-trip,
#           corrupted snapshot fail-closed, recovery-decision integration
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- State Snapshot Hash Consistency tests ---"

# Helper: create a compact test env with checkpoints
setup_snapshot_test() {
  local tmpdir
  tmpdir=$(mktemp -d)
  local changes_dir="$tmpdir/openspec/changes"
  mkdir -p "$changes_dir"
  (cd "$tmpdir" && git init -q 2>/dev/null) || true
  (cd "$tmpdir" && git config user.email "test@ci.local" && git config user.name "CI Test") || true
  echo "$tmpdir"
}

add_snapshot_change() {
  local tmpdir="$1"
  local name="$2"
  shift 2
  local pr="$tmpdir/openspec/changes/$name/context/phase-results"
  mkdir -p "$pr"
  for spec in "$@"; do
    local phase="${spec%%:*}"
    local status="${spec##*:}"
    local slug
    case "$phase" in
      1) slug="requirements" ;;
      2) slug="openspec" ;;
      3) slug="ff" ;;
      4) slug="testing" ;;
      5) slug="implement" ;;
      6) slug="report" ;;
      7) slug="summary" ;;
      *) slug="unknown" ;;
    esac
    echo "{\"status\":\"$status\",\"summary\":\"Phase $phase done\"}" >"$pr/phase-${phase}-${slug}.json"
  done
}

# 1. save-state-before-compact generates state-snapshot.json
echo "  1. Compact generates state-snapshot.json"
TMPDIR=$(setup_snapshot_test)
add_snapshot_change "$TMPDIR" "feat-snap" "1:ok" "2:ok"
echo '{"change":"feat-snap","mode":"full","pid":"99999","started":"2026-01-01T00:00:00Z","anchor_sha":"abc123"}' \
  >"$TMPDIR/openspec/changes/.autopilot-active"
echo '{"cwd":"'"$TMPDIR"'"}' | bash "$SCRIPT_DIR/save-state-before-compact.sh" 2>/dev/null
SNAP_FILE="$TMPDIR/openspec/changes/feat-snap/context/state-snapshot.json"
if [ -f "$SNAP_FILE" ]; then
  green "  PASS: 1a. state-snapshot.json created"
  PASS=$((PASS + 1))
else
  red "  FAIL: 1a. state-snapshot.json not created"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 2. Snapshot contains required fields
echo "  2. Snapshot contains all required control fields"
TMPDIR=$(setup_snapshot_test)
add_snapshot_change "$TMPDIR" "feat-fields" "1:ok" "2:ok" "3:ok"
echo '{"change":"feat-fields","mode":"full","pid":"99999","started":"2026-01-01T00:00:00Z","anchor_sha":"def456"}' \
  >"$TMPDIR/openspec/changes/.autopilot-active"
echo '{"cwd":"'"$TMPDIR"'"}' | bash "$SCRIPT_DIR/save-state-before-compact.sh" 2>/dev/null
SNAP_FILE="$TMPDIR/openspec/changes/feat-fields/context/state-snapshot.json"
if [ -f "$SNAP_FILE" ]; then
  FIELDS_OK=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
required = ['schema_version', 'snapshot_hash', 'gate_frontier', 'next_action',
            'phase_results', 'requirement_packet_hash', 'change_name',
            'execution_mode', 'last_completed_phase', 'phase_sequence']
missing = [k for k in required if k not in d]
if missing:
    print('MISSING:' + ','.join(missing))
else:
    print('OK')
" "$SNAP_FILE" 2>/dev/null)
  if [ "$FIELDS_OK" = "OK" ]; then
    green "  PASS: 2a. all required fields present"
    PASS=$((PASS + 1))
  else
    red "  FAIL: 2a. $FIELDS_OK"
    FAIL=$((FAIL + 1))
  fi
  # Check gate_frontier value
  GF=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['gate_frontier'])" "$SNAP_FILE" 2>/dev/null)
  if [ "$GF" = "3" ]; then
    green "  PASS: 2b. gate_frontier=3 (last ok phase)"
    PASS=$((PASS + 1))
  else
    red "  FAIL: 2b. gate_frontier (got $GF, expected 3)"
    FAIL=$((FAIL + 1))
  fi
  # Check next_action
  NA=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['next_action']['phase'])" "$SNAP_FILE" 2>/dev/null)
  if [ "$NA" = "4" ]; then
    green "  PASS: 2c. next_action.phase=4"
    PASS=$((PASS + 1))
  else
    red "  FAIL: 2c. next_action.phase (got $NA, expected 4)"
    FAIL=$((FAIL + 1))
  fi
  # Check schema_version
  SV=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['schema_version'])" "$SNAP_FILE" 2>/dev/null)
  if [ "$SV" = "7.1" ]; then
    green "  PASS: 2d. schema_version=7.1"
    PASS=$((PASS + 1))
  else
    red "  FAIL: 2d. schema_version (got $SV)"
    FAIL=$((FAIL + 1))
  fi
fi
rm -rf "$TMPDIR"

# 3. Snapshot hash is valid (self-consistent)
echo "  3. Snapshot hash self-consistency"
TMPDIR=$(setup_snapshot_test)
add_snapshot_change "$TMPDIR" "feat-hash" "1:ok" "2:ok"
echo '{"change":"feat-hash","mode":"full","pid":"99999","started":"2026-01-01T00:00:00Z"}' \
  >"$TMPDIR/openspec/changes/.autopilot-active"
echo '{"cwd":"'"$TMPDIR"'"}' | bash "$SCRIPT_DIR/save-state-before-compact.sh" 2>/dev/null
SNAP_FILE="$TMPDIR/openspec/changes/feat-hash/context/state-snapshot.json"
HASH_CHECK=$(python3 -c "
import json, sys, hashlib
with open(sys.argv[1]) as f:
    data = json.load(f)
stored_hash = data.get('snapshot_hash', '')
verify_data = {k: v for k, v in data.items() if k != 'snapshot_hash'}
verify_content = json.dumps(verify_data, sort_keys=True, ensure_ascii=False)
computed_hash = hashlib.sha256(verify_content.encode('utf-8')).hexdigest()[:16]
if computed_hash == stored_hash:
    print('MATCH')
else:
    print(f'MISMATCH stored={stored_hash} computed={computed_hash}')
" "$SNAP_FILE" 2>/dev/null)
if [ "$HASH_CHECK" = "MATCH" ]; then
  green "  PASS: 3a. snapshot_hash verified (self-consistent)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3a. $HASH_CHECK"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 4. Tampered snapshot → hash mismatch detected
echo "  4. Tampered snapshot → hash mismatch"
TMPDIR=$(setup_snapshot_test)
add_snapshot_change "$TMPDIR" "feat-tamper" "1:ok" "2:ok"
echo '{"change":"feat-tamper","mode":"full","pid":"99999","started":"2026-01-01T00:00:00Z"}' \
  >"$TMPDIR/openspec/changes/.autopilot-active"
echo '{"cwd":"'"$TMPDIR"'"}' | bash "$SCRIPT_DIR/save-state-before-compact.sh" 2>/dev/null
SNAP_FILE="$TMPDIR/openspec/changes/feat-tamper/context/state-snapshot.json"
# Tamper: change gate_frontier
python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
data['gate_frontier'] = 99  # tamper
with open(sys.argv[1], 'w') as f:
    json.dump(data, f)
" "$SNAP_FILE" 2>/dev/null
HASH_CHECK=$(python3 -c "
import json, sys, hashlib
with open(sys.argv[1]) as f:
    data = json.load(f)
stored_hash = data.get('snapshot_hash', '')
verify_data = {k: v for k, v in data.items() if k != 'snapshot_hash'}
verify_content = json.dumps(verify_data, sort_keys=True, ensure_ascii=False)
computed_hash = hashlib.sha256(verify_content.encode('utf-8')).hexdigest()[:16]
if computed_hash != stored_hash:
    print('MISMATCH_DETECTED')
else:
    print('MATCH_UNEXPECTED')
" "$SNAP_FILE" 2>/dev/null)
if [ "$HASH_CHECK" = "MISMATCH_DETECTED" ]; then
  green "  PASS: 4a. tampered snapshot hash mismatch detected"
  PASS=$((PASS + 1))
else
  red "  FAIL: 4a. tampered snapshot not detected ($HASH_CHECK)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 5. reinject-state-after-compact uses snapshot JSON (structured path)
echo "  5. Reinject uses state-snapshot.json when available"
TMPDIR=$(setup_snapshot_test)
add_snapshot_change "$TMPDIR" "feat-reinject" "1:ok" "2:ok"
echo '{"change":"feat-reinject","mode":"full","pid":"99999","started":"2026-01-01T00:00:00Z","anchor_sha":"abc"}' \
  >"$TMPDIR/openspec/changes/.autopilot-active"
echo '{"cwd":"'"$TMPDIR"'"}' | bash "$SCRIPT_DIR/save-state-before-compact.sh" 2>/dev/null
# Now run reinject from that dir
REINJECT_OUTPUT=$(cd "$TMPDIR" && bash "$SCRIPT_DIR/reinject-state-after-compact.sh" 2>/dev/null)
if grep -q "STRUCTURED" <<<"$REINJECT_OUTPUT"; then
  green "  PASS: 5a. reinject uses structured path"
  PASS=$((PASS + 1))
else
  red "  FAIL: 5a. reinject did not use structured path"
  FAIL=$((FAIL + 1))
fi
if grep -q "verified" <<<"$REINJECT_OUTPUT"; then
  green "  PASS: 5b. reinject shows hash verified"
  PASS=$((PASS + 1))
else
  red "  FAIL: 5b. reinject missing hash verification message"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 6. reinject falls back to markdown when snapshot tampered
echo "  6. Reinject fallback to markdown on tampered snapshot"
TMPDIR=$(setup_snapshot_test)
add_snapshot_change "$TMPDIR" "feat-fallback" "1:ok" "2:ok"
echo '{"change":"feat-fallback","mode":"full","pid":"99999","started":"2026-01-01T00:00:00Z"}' \
  >"$TMPDIR/openspec/changes/.autopilot-active"
echo '{"cwd":"'"$TMPDIR"'"}' | bash "$SCRIPT_DIR/save-state-before-compact.sh" 2>/dev/null
# Tamper the snapshot
SNAP_FILE="$TMPDIR/openspec/changes/feat-fallback/context/state-snapshot.json"
python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
data['gate_frontier'] = 99
with open(sys.argv[1], 'w') as f:
    json.dump(data, f)
" "$SNAP_FILE" 2>/dev/null
REINJECT_OUTPUT=$(cd "$TMPDIR" && bash "$SCRIPT_DIR/reinject-state-after-compact.sh" 2>/dev/null)
if grep -q "LEGACY" <<<"$REINJECT_OUTPUT"; then
  green "  PASS: 6a. reinject falls back to legacy on tampered snapshot"
  PASS=$((PASS + 1))
else
  red "  FAIL: 6a. reinject did not fall back to legacy"
  FAIL=$((FAIL + 1))
fi
if grep -q "hash verification" <<<"$REINJECT_OUTPUT"; then
  green "  PASS: 6b. reinject warns about hash verification failure"
  PASS=$((PASS + 1))
else
  red "  FAIL: 6b. reinject missing hash warning"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 7. recovery-decision.sh includes state_snapshot in output
echo "  7. Recovery decision includes state_snapshot"
TMPDIR=$(setup_snapshot_test)
add_snapshot_change "$TMPDIR" "feat-rd" "1:ok" "2:ok"
echo '{"change":"feat-rd","mode":"full","pid":"99999","started":"2026-01-01T00:00:00Z"}' \
  >"$TMPDIR/openspec/changes/.autopilot-active"
echo '{"cwd":"'"$TMPDIR"'"}' | bash "$SCRIPT_DIR/save-state-before-compact.sh" 2>/dev/null
OUTPUT=$(bash "$SCRIPT_DIR/recovery-decision.sh" "$TMPDIR/openspec/changes" "full" 2>/dev/null)
SNAP_EXISTS=$(echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); c=[x for x in d['changes'] if x['name']=='feat-rd'][0]; ss=c.get('state_snapshot',{}); print(ss.get('exists',False))" 2>/dev/null)
SNAP_VALID=$(echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); c=[x for x in d['changes'] if x['name']=='feat-rd'][0]; ss=c.get('state_snapshot',{}); print(ss.get('hash_valid',False))" 2>/dev/null)
if [ "$SNAP_EXISTS" = "True" ]; then
  green "  PASS: 7a. state_snapshot.exists=True"
  PASS=$((PASS + 1))
else
  red "  FAIL: 7a. state_snapshot.exists (got $SNAP_EXISTS)"
  FAIL=$((FAIL + 1))
fi
if [ "$SNAP_VALID" = "True" ]; then
  green "  PASS: 7b. state_snapshot.hash_valid=True"
  PASS=$((PASS + 1))
else
  red "  FAIL: 7b. state_snapshot.hash_valid (got $SNAP_VALID)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 8. recovery-decision uses snapshot for recovery when hash valid
echo "  8. Recovery uses snapshot for high-confidence resume"
TMPDIR=$(setup_snapshot_test)
add_snapshot_change "$TMPDIR" "feat-conf" "1:ok" "2:ok"
echo '{"change":"feat-conf","mode":"full","pid":"99999","started":"2026-01-01T00:00:00Z"}' \
  >"$TMPDIR/openspec/changes/.autopilot-active"
echo '{"cwd":"'"$TMPDIR"'"}' | bash "$SCRIPT_DIR/save-state-before-compact.sh" 2>/dev/null
OUTPUT=$(bash "$SCRIPT_DIR/recovery-decision.sh" "$TMPDIR/openspec/changes" "full" 2>/dev/null)
REASON=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('recovery_reason',''))" 2>/dev/null)
CONFIDENCE=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('recovery_confidence',''))" 2>/dev/null)
if [ "$REASON" = "state_snapshot_resume" ]; then
  green "  PASS: 8a. recovery_reason=state_snapshot_resume"
  PASS=$((PASS + 1))
else
  red "  FAIL: 8a. recovery_reason (got '$REASON', expected 'state_snapshot_resume')"
  FAIL=$((FAIL + 1))
fi
if [ "$CONFIDENCE" = "high" ]; then
  green "  PASS: 8b. recovery_confidence=high"
  PASS=$((PASS + 1))
else
  red "  FAIL: 8b. recovery_confidence (got '$CONFIDENCE', expected 'high')"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 9. Tampered snapshot → recovery_confidence=low, fail-closed
echo "  9. Tampered snapshot → recovery_confidence=low (fail-closed)"
TMPDIR=$(setup_snapshot_test)
add_snapshot_change "$TMPDIR" "feat-fc" "1:ok" "2:ok"
echo '{"change":"feat-fc","mode":"full","pid":"99999","started":"2026-01-01T00:00:00Z"}' \
  >"$TMPDIR/openspec/changes/.autopilot-active"
echo '{"cwd":"'"$TMPDIR"'"}' | bash "$SCRIPT_DIR/save-state-before-compact.sh" 2>/dev/null
# Tamper the snapshot
SNAP_FILE="$TMPDIR/openspec/changes/feat-fc/context/state-snapshot.json"
python3 -c "
import json
with open('$SNAP_FILE') as f: d = json.load(f)
d['gate_frontier'] = 99
with open('$SNAP_FILE', 'w') as f: json.dump(d, f)
"
OUTPUT=$(bash "$SCRIPT_DIR/recovery-decision.sh" "$TMPDIR/openspec/changes" "full" 2>/dev/null)
CONFIDENCE=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('recovery_confidence',''))" 2>/dev/null)
REASON=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('recovery_reason',''))" 2>/dev/null)
AUTO_CONT=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('auto_continue_eligible',True))" 2>/dev/null)
if [ "$CONFIDENCE" = "low" ]; then
  green "  PASS: 9a. recovery_confidence=low (tampered)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 9a. recovery_confidence (got '$CONFIDENCE', expected 'low')"
  FAIL=$((FAIL + 1))
fi
if [ "$REASON" = "snapshot_hash_mismatch" ]; then
  green "  PASS: 9b. recovery_reason=snapshot_hash_mismatch"
  PASS=$((PASS + 1))
else
  red "  FAIL: 9b. recovery_reason (got '$REASON')"
  FAIL=$((FAIL + 1))
fi
if [ "$AUTO_CONT" = "False" ]; then
  green "  PASS: 9c. auto_continue_eligible=False (fail-closed)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 9c. auto_continue_eligible (got '$AUTO_CONT', expected False)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 10. requirement_packet_hash is computed from phase-1 checkpoint
echo "  10. Requirement packet hash computed"
TMPDIR=$(setup_snapshot_test)
add_snapshot_change "$TMPDIR" "feat-rph" "1:ok" "2:ok"
echo '{"change":"feat-rph","mode":"full","pid":"99999","started":"2026-01-01T00:00:00Z"}' \
  >"$TMPDIR/openspec/changes/.autopilot-active"
echo '{"cwd":"'"$TMPDIR"'"}' | bash "$SCRIPT_DIR/save-state-before-compact.sh" 2>/dev/null
SNAP_FILE="$TMPDIR/openspec/changes/feat-rph/context/state-snapshot.json"
RPH=$(python3 -c "import json; d=json.load(open('$SNAP_FILE')); print(d.get('requirement_packet_hash',''))" 2>/dev/null)
if [ -n "$RPH" ] && [ ${#RPH} -eq 16 ]; then
  green "  PASS: 10a. requirement_packet_hash present (16 chars: $RPH)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 10a. requirement_packet_hash (got '$RPH')"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 11. save-phase-context.sh generates JSON snapshot alongside markdown
echo "  11. Phase context generates JSON snapshot"
setup_autopilot_fixture
CHANGE_DIR="$REPO_ROOT/openspec/changes/test-fixture"
mkdir -p "$CHANGE_DIR/context/phase-results"
bash "$SCRIPT_DIR/save-phase-context.sh" 1 full '{"summary":"Test summary","decisions":["Use API"],"constraints":["Low latency"]}' 2>/dev/null
JSON_SNAP="$CHANGE_DIR/context/phase-context-snapshots/phase-1-context.json"
if [ -f "$JSON_SNAP" ]; then
  green "  PASS: 11a. phase context JSON snapshot created"
  PASS=$((PASS + 1))
else
  red "  FAIL: 11a. phase context JSON snapshot not created"
  FAIL=$((FAIL + 1))
fi
if [ -f "$JSON_SNAP" ]; then
  HASH_OK=$(python3 -c "
import json, hashlib
with open('$JSON_SNAP') as f: d = json.load(f)
stored = d.get('content_hash', '')
verify = {k:v for k,v in d.items() if k != 'content_hash'}
computed = hashlib.sha256(json.dumps(verify, sort_keys=True, ensure_ascii=False).encode()).hexdigest()[:16]
print('OK' if computed == stored else 'FAIL')
" 2>/dev/null)
  if [ "$HASH_OK" = "OK" ]; then
    green "  PASS: 11b. phase context JSON hash verified"
    PASS=$((PASS + 1))
  else
    red "  FAIL: 11b. phase context JSON hash mismatch"
    FAIL=$((FAIL + 1))
  fi
fi
rm -rf "$CHANGE_DIR" 2>/dev/null || true
teardown_autopilot_fixture

# 12. clean-phase-artifacts removes state-snapshot.json on full reset
echo "  12. Clean artifacts removes state-snapshot.json"
TMPDIR=$(setup_snapshot_test)
add_snapshot_change "$TMPDIR" "feat-clean" "1:ok" "2:ok"
echo '{"change":"feat-clean","mode":"full","pid":"99999","started":"2026-01-01T00:00:00Z"}' \
  >"$TMPDIR/openspec/changes/.autopilot-active"
echo '{"cwd":"'"$TMPDIR"'"}' | bash "$SCRIPT_DIR/save-state-before-compact.sh" 2>/dev/null
SNAP_FILE="$TMPDIR/openspec/changes/feat-clean/context/state-snapshot.json"
STATE_MD="$TMPDIR/openspec/changes/feat-clean/context/autopilot-state.md"
# Verify files exist before cleanup
if [ -f "$SNAP_FILE" ] && [ -f "$STATE_MD" ]; then
  green "  PASS: 12a. pre-cleanup: both files exist"
  PASS=$((PASS + 1))
else
  red "  FAIL: 12a. pre-cleanup: files missing (snap=$([ -f "$SNAP_FILE" ] && echo Y || echo N), md=$([ -f "$STATE_MD" ] && echo Y || echo N))"
  FAIL=$((FAIL + 1))
fi
bash "$SCRIPT_DIR/clean-phase-artifacts.sh" 1 full "$TMPDIR/openspec/changes/feat-clean" 2>/dev/null
if [ ! -f "$SNAP_FILE" ] && [ ! -f "$STATE_MD" ]; then
  green "  PASS: 12b. post-cleanup: both files removed"
  PASS=$((PASS + 1))
else
  red "  FAIL: 12b. post-cleanup: files remain (snap=$([ -f "$SNAP_FILE" ] && echo Y || echo N), md=$([ -f "$STATE_MD" ] && echo Y || echo N))"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 13. recovery-decision.sh outputs v6.0 enhanced fields
echo "  13. Recovery decision outputs v6.0 enhanced fields"
TMPDIR=$(setup_snapshot_test)
add_snapshot_change "$TMPDIR" "feat-v6" "1:ok" "2:ok"
echo '{"change":"feat-v6","mode":"full","pid":"99999","started":"2026-01-01T00:00:00Z"}' \
  >"$TMPDIR/openspec/changes/.autopilot-active"
echo '{"cwd":"'"$TMPDIR"'"}' | bash "$SCRIPT_DIR/save-state-before-compact.sh" 2>/dev/null
OUTPUT=$(bash "$SCRIPT_DIR/recovery-decision.sh" "$TMPDIR/openspec/changes" "full" 2>/dev/null)
V6_FIELDS=$(echo "$OUTPUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
required = ['resume_from_phase', 'discarded_artifacts', 'replay_required_tasks', 'recovery_reason', 'recovery_confidence']
missing = [k for k in required if k not in d]
print('OK' if not missing else 'MISSING:' + ','.join(missing))
" 2>/dev/null)
if [ "$V6_FIELDS" = "OK" ]; then
  green "  PASS: 13a. all v6.0 enhanced fields present"
  PASS=$((PASS + 1))
else
  red "  FAIL: 13a. $V6_FIELDS"
  FAIL=$((FAIL + 1))
fi
RESUME=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('resume_from_phase',0))" 2>/dev/null)
if [ "$RESUME" = "3" ]; then
  green "  PASS: 13b. resume_from_phase=3"
  PASS=$((PASS + 1))
else
  red "  FAIL: 13b. resume_from_phase (got '$RESUME', expected 3)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
