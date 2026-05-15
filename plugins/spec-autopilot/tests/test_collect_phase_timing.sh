#!/usr/bin/env bash
# test_collect_phase_timing.sh
# Tests for collect-phase-timing.sh
#
# Covers:
#   1. Normal path: checkpoints with _metrics → correct timing calculation
#   2. Boundary: no checkpoint files → empty result
#   3. Error path: malformed JSON → graceful skip

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"

# --- Test helpers ---
PASS=0
FAIL=0
TOTAL=0

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name (expected='$expected', actual='$actual')"
  fi
}

assert_json_field() {
  local name="$1" json="$2" field="$3" expected="$4"
  local actual
  actual=$(echo "$json" | jq -r "$field" 2>/dev/null)
  assert_eq "$name" "$expected" "$actual"
}

assert_exit() {
  local name="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [ "$expected" -eq "$actual" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: $name (exit=$actual)"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name (expected exit=$expected, actual exit=$actual)"
  fi
}

# --- Setup temp project ---
setup_temp_project() {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/openspec/changes/test-change/context/phase-results"
  # Create a minimal lock file
  cat > "$tmp/openspec/changes/.autopilot-active" <<'LOCK'
{
  "change": "test-change",
  "session_id": "test-session",
  "mode": "full",
  "pid": 1
}
LOCK
  echo "$tmp"
}

cleanup_temp() {
  [ -n "${1:-}" ] && rm -rf "$1"
}

# ============================================================
# Test 1: Normal path — checkpoints with _metrics
# ============================================================
echo "--- Test 1: checkpoints with _metrics → correct timing ---"

TMP1=$(setup_temp_project)
PR1="$TMP1/openspec/changes/test-change/context/phase-results"

cat > "$PR1/phase-1-requirements.json" <<'EOF'
{
  "status": "ok",
  "summary": "Phase 1 done",
  "artifacts": [],
  "risks": [],
  "next_ready": true,
  "timestamp": "2026-05-15T10:00:00+08:00",
  "phase": 1,
  "_metrics": {
    "start_time": "2026-05-15T10:00:00+08:00",
    "end_time": "2026-05-15T10:05:30+08:00",
    "duration_seconds": 330
  }
}
EOF

cat > "$PR1/phase-5-implement.json" <<'EOF'
{
  "status": "ok",
  "summary": "Phase 5 done",
  "artifacts": [],
  "risks": [],
  "next_ready": true,
  "timestamp": "2026-05-15T10:10:00+08:00",
  "phase": 5,
  "_metrics": {
    "start_time": "2026-05-15T10:05:30+08:00",
    "end_time": "2026-05-15T10:10:00+08:00",
    "duration_seconds": 270
  }
}
EOF

OUTPUT1=$(bash "$SCRIPT_DIR/collect-phase-timing.sh" "$TMP1" 2>/dev/null)
EXIT1=$?

assert_exit "1a. script exits 0" 0 "$EXIT1"
assert_json_field "1b. phases array length is 2" "$OUTPUT1" '.phases | length' "2"
assert_json_field "1c. phase 1 duration is 330" "$OUTPUT1" '.phases[0].duration_seconds' "330"
assert_json_field "1d. phase 5 duration is 270" "$OUTPUT1" '.phases[1].duration_seconds' "270"
assert_json_field "1e. total duration is 600" "$OUTPUT1" '.totals.total_duration_seconds' "600"

cleanup_temp "$TMP1"

# ============================================================
# Test 2: Boundary — no checkpoint files → empty result
# ============================================================
echo "--- Test 2: no checkpoints → empty result ---"

TMP2=$(setup_temp_project)

OUTPUT2=$(bash "$SCRIPT_DIR/collect-phase-timing.sh" "$TMP2" 2>/dev/null)
EXIT2=$?

assert_exit "2a. script exits 0" 0 "$EXIT2"
assert_json_field "2b. phases array is empty" "$OUTPUT2" '.phases | length' "0"
assert_json_field "2c. total duration is 0" "$OUTPUT2" '.totals.total_duration_seconds' "0"

cleanup_temp "$TMP2"

# ============================================================
# Test 3: Error path — malformed checkpoint JSON → graceful skip
# ============================================================
echo "--- Test 3: malformed JSON → graceful skip ---"

TMP3=$(setup_temp_project)
PR3="$TMP3/openspec/changes/test-change/context/phase-results"

echo "NOT VALID JSON {{{" > "$PR3/phase-1-requirements.json"

cat > "$PR3/phase-5-implement.json" <<'EOF'
{
  "status": "ok",
  "summary": "Phase 5 done",
  "artifacts": [],
  "risks": [],
  "next_ready": true,
  "timestamp": "2026-05-15T10:10:00+08:00",
  "phase": 5,
  "_metrics": {
    "start_time": "2026-05-15T10:05:00+08:00",
    "end_time": "2026-05-15T10:10:00+08:00",
    "duration_seconds": 300
  }
}
EOF

OUTPUT3=$(bash "$SCRIPT_DIR/collect-phase-timing.sh" "$TMP3" 2>/dev/null)
EXIT3=$?

assert_exit "3a. script exits 0 despite malformed JSON" 0 "$EXIT3"
assert_json_field "3b. only valid checkpoint counted" "$OUTPUT3" '.phases | length' "1"
assert_json_field "3c. phase 5 duration correct" "$OUTPUT3" '.phases[0].duration_seconds' "300"

cleanup_temp "$TMP3"

# --- Summary ---
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
