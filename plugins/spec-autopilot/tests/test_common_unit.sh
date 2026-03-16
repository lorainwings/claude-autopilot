#!/usr/bin/env bash
# test_common_unit.sh — Section 19: _common.sh unit tests (extensive)
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 19. _common.sh unit tests ---"
setup_autopilot_fixture

# Need a temp directory for these tests
COMMON_TEST_DIR=$(mktemp -d)
trap "rm -rf $COMMON_TEST_DIR" EXIT

# Source _common.sh
source "$SCRIPT_DIR/_common.sh"

# 19a. parse_lock_file with JSON format
echo '{"change":"my-feature","pid":"12345","started":"2026-01-01T00:00:00Z"}' > "$COMMON_TEST_DIR/lock.json"
result=$(parse_lock_file "$COMMON_TEST_DIR/lock.json")
if [ "$result" = "my-feature" ]; then
  green "  PASS: parse_lock_file JSON format"
  PASS=$((PASS + 1))
else
  red "  FAIL: parse_lock_file JSON format (got '$result')"
  FAIL=$((FAIL + 1))
fi

# 19b. parse_lock_file with legacy plain text
echo "legacy-change-name" > "$COMMON_TEST_DIR/lock.txt"
result=$(parse_lock_file "$COMMON_TEST_DIR/lock.txt")
if [ "$result" = "legacy-change-name" ]; then
  green "  PASS: parse_lock_file legacy plain text"
  PASS=$((PASS + 1))
else
  red "  FAIL: parse_lock_file legacy plain text (got '$result')"
  FAIL=$((FAIL + 1))
fi

# 19c. parse_lock_file with invalid/empty file
echo "" > "$COMMON_TEST_DIR/lock_empty.txt"
result=$(parse_lock_file "$COMMON_TEST_DIR/lock_empty.txt")
if [ -z "$result" ]; then
  green "  PASS: parse_lock_file empty file returns empty"
  PASS=$((PASS + 1))
else
  red "  FAIL: parse_lock_file empty file (got '$result')"
  FAIL=$((FAIL + 1))
fi

# 19d. parse_lock_file with missing file
result=""
parse_lock_file "$COMMON_TEST_DIR/nonexistent.json" || true
result=$(parse_lock_file "$COMMON_TEST_DIR/nonexistent.json" 2>/dev/null || echo "")
if [ -z "$result" ]; then
  green "  PASS: parse_lock_file missing file returns empty"
  PASS=$((PASS + 1))
else
  red "  FAIL: parse_lock_file missing file (got '$result')"
  FAIL=$((FAIL + 1))
fi

# 19e. find_active_change with lock file priority
mkdir -p "$COMMON_TEST_DIR/changes/feature-a"
mkdir -p "$COMMON_TEST_DIR/changes/feature-b"
echo '{"change":"feature-a"}' > "$COMMON_TEST_DIR/changes/.autopilot-active"
result=$(find_active_change "$COMMON_TEST_DIR/changes")
if echo "$result" | grep -q "feature-a"; then
  green "  PASS: find_active_change lock file priority"
  PASS=$((PASS + 1))
else
  red "  FAIL: find_active_change lock file priority (got '$result')"
  FAIL=$((FAIL + 1))
fi

# 19f. find_active_change with trailing slash
result=$(find_active_change "$COMMON_TEST_DIR/changes" "yes")
if [[ "$result" == */ ]]; then
  green "  PASS: find_active_change trailing slash"
  PASS=$((PASS + 1))
else
  red "  FAIL: find_active_change trailing slash (got '$result')"
  FAIL=$((FAIL + 1))
fi

# 19g. find_active_change excludes _prefixed dirs
mkdir -p "$COMMON_TEST_DIR/changes2/_archived"
mkdir -p "$COMMON_TEST_DIR/changes2/real-change"
result=$(find_active_change "$COMMON_TEST_DIR/changes2")
if echo "$result" | grep -q "real-change"; then
  green "  PASS: find_active_change excludes _prefix"
  PASS=$((PASS + 1))
else
  red "  FAIL: find_active_change excludes _prefix (got '$result')"
  FAIL=$((FAIL + 1))
fi

# 19h. read_checkpoint_status with all statuses
for status_val in ok warning blocked failed; do
  echo "{\"status\":\"$status_val\"}" > "$COMMON_TEST_DIR/ckpt_${status_val}.json"
  result=$(read_checkpoint_status "$COMMON_TEST_DIR/ckpt_${status_val}.json")
  if [ "$result" = "$status_val" ]; then
    green "  PASS: read_checkpoint_status '$status_val'"
    PASS=$((PASS + 1))
  else
    red "  FAIL: read_checkpoint_status '$status_val' (got '$result')"
    FAIL=$((FAIL + 1))
  fi
done

# 19i. read_checkpoint_status with invalid JSON
echo "not json at all" > "$COMMON_TEST_DIR/ckpt_bad.json"
result=$(read_checkpoint_status "$COMMON_TEST_DIR/ckpt_bad.json")
if [ "$result" = "error" ]; then
  green "  PASS: read_checkpoint_status invalid JSON returns error"
  PASS=$((PASS + 1))
else
  red "  FAIL: read_checkpoint_status invalid JSON (got '$result')"
  FAIL=$((FAIL + 1))
fi

# 19j. find_checkpoint
mkdir -p "$COMMON_TEST_DIR/phase-results"
echo '{"status":"ok"}' > "$COMMON_TEST_DIR/phase-results/phase-3-ff.json"
result=$(find_checkpoint "$COMMON_TEST_DIR/phase-results" 3)
if [ -n "$result" ] && echo "$result" | grep -q "phase-3-ff.json"; then
  green "  PASS: find_checkpoint finds phase-3"
  PASS=$((PASS + 1))
else
  red "  FAIL: find_checkpoint phase-3 (got '$result')"
  FAIL=$((FAIL + 1))
fi

# 19k. find_checkpoint for missing phase
result=$(find_checkpoint "$COMMON_TEST_DIR/phase-results" 9)
if [ -z "$result" ]; then
  green "  PASS: find_checkpoint missing phase returns empty"
  PASS=$((PASS + 1))
else
  red "  FAIL: find_checkpoint missing phase (got '$result')"
  FAIL=$((FAIL + 1))
fi

# 19l. scan_all_checkpoints returns JSON array with correct statuses
mkdir -p "$COMMON_TEST_DIR/scan-results"
echo '{"status":"ok"}' > "$COMMON_TEST_DIR/scan-results/phase-1-requirements.json"
echo '{"status":"warning"}' > "$COMMON_TEST_DIR/scan-results/phase-2-openspec.json"
result=$(scan_all_checkpoints "$COMMON_TEST_DIR/scan-results" "full")
if echo "$result" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d[0]['status']=='ok' and d[0]['phase']==1" 2>/dev/null; then
  green "  PASS: scan_all_checkpoints phase-1 status=ok"
  PASS=$((PASS + 1))
else
  red "  FAIL: scan_all_checkpoints phase-1 (got '$result')"
  FAIL=$((FAIL + 1))
fi

# 19m. scan_all_checkpoints reports missing phases
if echo "$result" | python3 -c "import json,sys; d=json.load(sys.stdin); missing=[x for x in d if x['status']=='missing']; assert len(missing)>=5" 2>/dev/null; then
  green "  PASS: scan_all_checkpoints reports missing phases"
  PASS=$((PASS + 1))
else
  red "  FAIL: scan_all_checkpoints missing phases (got '$result')"
  FAIL=$((FAIL + 1))
fi

# 19n. get_last_valid_phase returns correct phase number
result=$(get_last_valid_phase "$COMMON_TEST_DIR/scan-results" "full")
if [ "$result" = "2" ]; then
  green "  PASS: get_last_valid_phase returns 2"
  PASS=$((PASS + 1))
else
  red "  FAIL: get_last_valid_phase (got '$result', expected '2')"
  FAIL=$((FAIL + 1))
fi

# 19o. get_last_valid_phase returns 0 when no checkpoints exist
empty_dir=$(mktemp -d)
result=$(get_last_valid_phase "$empty_dir" "full")
if [ "$result" = "0" ]; then
  green "  PASS: get_last_valid_phase empty dir returns 0"
  PASS=$((PASS + 1))
else
  red "  FAIL: get_last_valid_phase empty dir (got '$result')"
  FAIL=$((FAIL + 1))
fi
rm -rf "$empty_dir"

# 19p. scan_all_checkpoints respects mode (lite only scans 1,5,6,7)
result=$(scan_all_checkpoints "$COMMON_TEST_DIR/scan-results" "lite")
phase_count=$(echo "$result" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null)
if [ "$phase_count" = "4" ]; then
  green "  PASS: scan_all_checkpoints lite mode scans 4 phases"
  PASS=$((PASS + 1))
else
  red "  FAIL: scan_all_checkpoints lite mode (got $phase_count phases)"
  FAIL=$((FAIL + 1))
fi

# 19q. validate_checkpoint_integrity with valid checkpoint
echo '{"status":"ok","summary":"test"}' > "$COMMON_TEST_DIR/ckpt_valid.json"
if validate_checkpoint_integrity "$COMMON_TEST_DIR/ckpt_valid.json"; then
  green "  PASS: validate_checkpoint_integrity valid checkpoint"
  PASS=$((PASS + 1))
else
  red "  FAIL: validate_checkpoint_integrity valid checkpoint"
  FAIL=$((FAIL + 1))
fi

# 19r. validate_checkpoint_integrity removes corrupted file
echo "not valid json" > "$COMMON_TEST_DIR/ckpt_corrupt.json"
validate_checkpoint_integrity "$COMMON_TEST_DIR/ckpt_corrupt.json" 2>/dev/null
if [ ! -f "$COMMON_TEST_DIR/ckpt_corrupt.json" ]; then
  green "  PASS: validate_checkpoint_integrity removes corrupted file"
  PASS=$((PASS + 1))
else
  red "  FAIL: validate_checkpoint_integrity did not remove corrupted file"
  FAIL=$((FAIL + 1))
fi

# 19s. validate_checkpoint_integrity cleans up .tmp files
echo '{"status":"ok"}' > "$COMMON_TEST_DIR/ckpt_withtmp.json"
echo "temp" > "$COMMON_TEST_DIR/ckpt_withtmp.tmp"
validate_checkpoint_integrity "$COMMON_TEST_DIR/ckpt_withtmp.json" 2>/dev/null
if [ ! -f "$COMMON_TEST_DIR/ckpt_withtmp.tmp" ]; then
  green "  PASS: validate_checkpoint_integrity cleans .tmp"
  PASS=$((PASS + 1))
else
  red "  FAIL: validate_checkpoint_integrity did not clean .tmp"
  FAIL=$((FAIL + 1))
fi

# 19t. get_phase_label returns correct labels
result=$(get_phase_label 0)
if [ "$result" = "Environment Setup" ]; then
  green "  PASS: get_phase_label 0 = Environment Setup"
  PASS=$((PASS + 1))
else
  red "  FAIL: get_phase_label 0 (got '$result')"
  FAIL=$((FAIL + 1))
fi
result=$(get_phase_label 5)
if [ "$result" = "Implementation" ]; then
  green "  PASS: get_phase_label 5 = Implementation"
  PASS=$((PASS + 1))
else
  red "  FAIL: get_phase_label 5 (got '$result')"
  FAIL=$((FAIL + 1))
fi

# 19u. get_total_phases returns correct counts by mode
result=$(get_total_phases "full")
if [ "$result" = "8" ]; then
  green "  PASS: get_total_phases full = 8"
  PASS=$((PASS + 1))
else
  red "  FAIL: get_total_phases full (got '$result')"
  FAIL=$((FAIL + 1))
fi
result=$(get_total_phases "lite")
if [ "$result" = "5" ]; then
  green "  PASS: get_total_phases lite = 5"
  PASS=$((PASS + 1))
else
  red "  FAIL: get_total_phases lite (got '$result')"
  FAIL=$((FAIL + 1))
fi

# 19v. next_event_sequence returns incrementing numbers
SEQ_TEST_DIR=$(mktemp -d)
result1=$(next_event_sequence "$SEQ_TEST_DIR")
result2=$(next_event_sequence "$SEQ_TEST_DIR")
if [ "$result1" = "1" ] && [ "$result2" = "2" ]; then
  green "  PASS: next_event_sequence increments 1→2"
  PASS=$((PASS + 1))
else
  red "  FAIL: next_event_sequence (got '$result1', '$result2')"
  FAIL=$((FAIL + 1))
fi
rm -rf "$SEQ_TEST_DIR"

# 19w. read_lock_json_field extracts field from JSON lock file
echo '{"change":"my-feat","mode":"lite","anchor_sha":"abc123"}' > "$COMMON_TEST_DIR/lock_fields.json"
result=$(read_lock_json_field "$COMMON_TEST_DIR/lock_fields.json" "mode")
if [ "$result" = "lite" ]; then
  green "  PASS: read_lock_json_field extracts mode"
  PASS=$((PASS + 1))
else
  red "  FAIL: read_lock_json_field mode (got '$result')"
  FAIL=$((FAIL + 1))
fi

# 19x. read_lock_json_field returns default for missing field
result=$(read_lock_json_field "$COMMON_TEST_DIR/lock_fields.json" "nonexistent" "fallback")
if [ "$result" = "fallback" ]; then
  green "  PASS: read_lock_json_field missing field returns default"
  PASS=$((PASS + 1))
else
  red "  FAIL: read_lock_json_field missing field (got '$result')"
  FAIL=$((FAIL + 1))
fi

# 19y. get_last_valid_phase gap detection — Phase 3 missing, Phase 4 ok → returns 2
GAP_TEST_DIR=$(mktemp -d)
mkdir -p "$GAP_TEST_DIR/phase-results"
echo '{"status":"ok"}' > "$GAP_TEST_DIR/phase-results/phase-1-requirements.json"
echo '{"status":"ok"}' > "$GAP_TEST_DIR/phase-results/phase-2-openspec.json"
# Phase 3 deliberately missing
echo '{"status":"ok"}' > "$GAP_TEST_DIR/phase-results/phase-4-testing.json"
result=$(get_last_valid_phase "$GAP_TEST_DIR/phase-results" "full")
if [ "$result" = "2" ]; then
  green "  PASS: 19y. gap detection — returns 2 (stops at missing Phase 3)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 19y. gap detection (got '$result', expected '2')"
  FAIL=$((FAIL + 1))
fi
rm -rf "$GAP_TEST_DIR"

# 19z. validate_checkpoint_integrity creates .corrupted-backups/
CORRUPT_TEST_DIR=$(mktemp -d)
mkdir -p "$CORRUPT_TEST_DIR/phase-results"
echo "not valid json" > "$CORRUPT_TEST_DIR/phase-results/bad-checkpoint.json"
validate_checkpoint_integrity "$CORRUPT_TEST_DIR/phase-results/bad-checkpoint.json" 2>/dev/null
if [ -d "$CORRUPT_TEST_DIR/phase-results/.corrupted-backups" ]; then
  green "  PASS: 19z. corrupted checkpoint backed up to .corrupted-backups/"
  PASS=$((PASS + 1))
else
  red "  FAIL: 19z. .corrupted-backups/ not created"
  FAIL=$((FAIL + 1))
fi
rm -rf "$CORRUPT_TEST_DIR"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0
