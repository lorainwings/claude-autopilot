#!/usr/bin/env bash
# test_e2e_checkpoint_recovery.sh — E2E: Crash recovery → checkpoint resume
# Verifies the complete checkpoint scan → recovery point determination flow
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"
source "$SCRIPT_DIR/_common.sh"

echo "--- E2E-2. Checkpoint recovery integration tests ---"

RECOVERY_DIR=$(mktemp -d)
trap "rm -rf $RECOVERY_DIR" EXIT

# E2E-2a. Fresh project (no checkpoints) → get_last_valid_phase returns 0
result=$(get_last_valid_phase "$RECOVERY_DIR" "full")
if [ "$result" = "0" ]; then
  green "  PASS: E2E-2a. fresh project → last_valid_phase = 0"
  PASS=$((PASS + 1))
else
  red "  FAIL: E2E-2a. fresh project (got '$result')"
  FAIL=$((FAIL + 1))
fi

# E2E-2b. Phase 1+2 complete → recovery starts from Phase 3
echo '{"status":"ok","summary":"Requirements confirmed"}' > "$RECOVERY_DIR/phase-1-requirements.json"
echo '{"status":"ok","summary":"OpenSpec created"}' > "$RECOVERY_DIR/phase-2-openspec.json"
result=$(get_last_valid_phase "$RECOVERY_DIR" "full")
if [ "$result" = "2" ]; then
  green "  PASS: E2E-2b. Phase 1+2 done → last_valid = 2"
  PASS=$((PASS + 1))
else
  red "  FAIL: E2E-2b. Phase 1+2 (got '$result')"
  FAIL=$((FAIL + 1))
fi

# E2E-2c. Phase 3 failed → recovery still at Phase 2
echo '{"status":"failed","summary":"FF generation failed"}' > "$RECOVERY_DIR/phase-3-ff.json"
result=$(get_last_valid_phase "$RECOVERY_DIR" "full")
if [ "$result" = "2" ]; then
  green "  PASS: E2E-2c. Phase 3 failed → last_valid stays at 2"
  PASS=$((PASS + 1))
else
  red "  FAIL: E2E-2c. Phase 3 failed (got '$result')"
  FAIL=$((FAIL + 1))
fi

# E2E-2d. scan_all_checkpoints returns complete picture
result=$(scan_all_checkpoints "$RECOVERY_DIR" "full")
# Verify Phase 1 = ok, Phase 2 = ok, Phase 3 = failed, Phase 4-7 = missing
p1_status=$(echo "$result" | python3 -c "import json,sys; d=json.load(sys.stdin); print([x['status'] for x in d if x['phase']==1][0])" 2>/dev/null)
p3_status=$(echo "$result" | python3 -c "import json,sys; d=json.load(sys.stdin); print([x['status'] for x in d if x['phase']==3][0])" 2>/dev/null)
p4_status=$(echo "$result" | python3 -c "import json,sys; d=json.load(sys.stdin); print([x['status'] for x in d if x['phase']==4][0])" 2>/dev/null)
if [ "$p1_status" = "ok" ] && [ "$p3_status" = "failed" ] && [ "$p4_status" = "missing" ]; then
  green "  PASS: E2E-2d. scan_all_checkpoints returns complete picture"
  PASS=$((PASS + 1))
else
  red "  FAIL: E2E-2d. scan results (p1=$p1_status, p3=$p3_status, p4=$p4_status)"
  FAIL=$((FAIL + 1))
fi

# E2E-2e. Corrupted checkpoint → validate_checkpoint_integrity removes it
echo "this is not json" > "$RECOVERY_DIR/phase-4-testing.json"
validate_checkpoint_integrity "$RECOVERY_DIR/phase-4-testing.json" 2>/dev/null
if [ ! -f "$RECOVERY_DIR/phase-4-testing.json" ]; then
  green "  PASS: E2E-2e. corrupted checkpoint removed"
  PASS=$((PASS + 1))
else
  red "  FAIL: E2E-2e. corrupted checkpoint still exists"
  FAIL=$((FAIL + 1))
fi

# E2E-2f. .tmp residual cleanup during validation
echo '{"status":"ok"}' > "$RECOVERY_DIR/phase-5-implement.json"
echo "temp residual" > "$RECOVERY_DIR/phase-5-implement.tmp"
validate_checkpoint_integrity "$RECOVERY_DIR/phase-5-implement.json" 2>/dev/null
if [ ! -f "$RECOVERY_DIR/phase-5-implement.tmp" ]; then
  green "  PASS: E2E-2f. .tmp residual cleaned up"
  PASS=$((PASS + 1))
else
  red "  FAIL: E2E-2f. .tmp still exists"
  FAIL=$((FAIL + 1))
fi

# E2E-2g. Lite mode skips Phase 2/3/4
result=$(get_last_valid_phase "$RECOVERY_DIR" "lite")
# In lite mode only phases 1,5,6,7 are scanned; phase 1=ok, phase 5=ok → last_valid=5
if [ "$result" = "5" ]; then
  green "  PASS: E2E-2g. lite mode → last_valid = 5 (skips 2,3,4)"
  PASS=$((PASS + 1))
else
  red "  FAIL: E2E-2g. lite mode (got '$result')"
  FAIL=$((FAIL + 1))
fi

# E2E-2h. Warning status counts as valid for recovery
echo '{"status":"warning","summary":"Tests passed with warnings"}' > "$RECOVERY_DIR/phase-6-report.json"
result=$(get_last_valid_phase "$RECOVERY_DIR" "lite")
if [ "$result" = "6" ]; then
  green "  PASS: E2E-2h. warning status counts as valid"
  PASS=$((PASS + 1))
else
  red "  FAIL: E2E-2h. warning status (got '$result')"
  FAIL=$((FAIL + 1))
fi

# E2E-2i. find_checkpoint finds latest file for phase
echo '{"status":"ok"}' > "$RECOVERY_DIR/phase-1-requirements.json"
result=$(find_checkpoint "$RECOVERY_DIR" 1)
if [ -n "$result" ] && echo "$result" | grep -q "phase-1-requirements.json"; then
  green "  PASS: E2E-2i. find_checkpoint locates phase-1"
  PASS=$((PASS + 1))
else
  red "  FAIL: E2E-2i. find_checkpoint (got '$result')"
  FAIL=$((FAIL + 1))
fi

# E2E-2j. Progress files excluded from scan_all_checkpoints
echo '{"step":"research_dispatched"}' > "$RECOVERY_DIR/phase-1-progress.json"
result=$(scan_all_checkpoints "$RECOVERY_DIR" "full")
# Phase 1 should still show the requirements.json, not the progress file
p1_file=$(echo "$result" | python3 -c "import json,sys; d=json.load(sys.stdin); print([x['file'] for x in d if x['phase']==1][0])" 2>/dev/null)
if [ "$p1_file" = "phase-1-requirements.json" ]; then
  green "  PASS: E2E-2j. progress files excluded from scan"
  PASS=$((PASS + 1))
else
  red "  FAIL: E2E-2j. progress file included (got '$p1_file')"
  FAIL=$((FAIL + 1))
fi

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0
