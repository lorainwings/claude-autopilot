#!/usr/bin/env bash
# test_gui_store_cap.sh — Regression test for GUI store event cap limits
# Verifies: critical events capped at 200, regular events capped at 800
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/_test_helpers.sh"

echo "--- GUI store event cap tests ---"

# Skip if bun not available (CI may not have GUI deps)
if ! command -v bun &>/dev/null; then
  echo "  SKIP: bun not available"
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

GUI_DIR="$(cd "$TEST_DIR/../gui" && pwd)"
if [ ! -d "$GUI_DIR/node_modules" ]; then
  echo "  SKIP: gui/node_modules not installed"
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

# Write a temp TypeScript file inside gui/ so bun resolves imports correctly
TMPFILE="$GUI_DIR/_test_cap_$$.ts"
trap 'rm -f "$TMPFILE"' EXIT

cat > "$TMPFILE" << 'TSEOF'
import { useStore } from "./src/store/index.ts";

// Helper to create mock events
function makeEvents(count: number, type: string, startSeq: number) {
  return Array.from({ length: count }, (_, i) => ({
    sequence: startSeq + i,
    type: type,
    phase: 1,
    mode: "full" as const,
    session_id: "test",
    change_name: "test",
    total_phases: 8,
    timestamp: new Date().toISOString(),
    phase_label: "test",
    payload: {},
  }));
}

const store = useStore;

// Test 1: 250 critical events should be capped to 200
store.getState().addEvents(makeEvents(250, "phase_start", 1));
const afterCritical = store.getState().events;
const critCount = afterCritical.filter((e) => e.type === "phase_start").length;

// Test 2: Reset and add 900 regular + 50 critical
store.getState().reset();
store.getState().addEvents(makeEvents(50, "gate_block", 1));
store.getState().addEvents(makeEvents(900, "tool_use", 100));
const afterMixed = store.getState().events;
const mixedCrit = afterMixed.filter((e) => e.type === "gate_block").length;
const mixedReg = afterMixed.filter((e) => e.type === "tool_use").length;
const total = afterMixed.length;

console.log(JSON.stringify({ critCount, mixedCrit, mixedReg, total }));
TSEOF

# Run the temp file with bun (inside gui/ for correct module resolution)
RESULT=$(cd "$GUI_DIR" && bun run "$TMPFILE" 2>/dev/null)

if [ -z "$RESULT" ]; then
  # bun and node_modules both exist, so a runtime failure is a real error
  red "  FAIL: bun run produced no output (module resolution or runtime error)"
  FAIL=$((FAIL + 1))
  echo "Results: $PASS passed, $FAIL failed"
  exit 1
fi

# Parse results
CRIT_COUNT=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['critCount'])" 2>/dev/null || echo "")
MIXED_CRIT=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['mixedCrit'])" 2>/dev/null || echo "")
MIXED_REG=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['mixedReg'])" 2>/dev/null || echo "")
TOTAL=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['total'])" 2>/dev/null || echo "")

# Test 1: 250 critical → capped to 200
if [ "$CRIT_COUNT" = "200" ]; then
  green "  PASS: 1. critical events capped at 200 (250 → 200)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 1. critical events cap (expected 200, got '$CRIT_COUNT')"
  FAIL=$((FAIL + 1))
fi

# Test 2: 50 critical + 900 regular → 50 critical + 800 regular = 850
if [ "$MIXED_CRIT" = "50" ]; then
  green "  PASS: 2a. critical events under cap preserved (50)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2a. critical under cap (expected 50, got '$MIXED_CRIT')"
  FAIL=$((FAIL + 1))
fi

if [ "$MIXED_REG" = "800" ]; then
  green "  PASS: 2b. regular events capped at 800 (900 → 800)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2b. regular events cap (expected 800, got '$MIXED_REG')"
  FAIL=$((FAIL + 1))
fi

if [ "$TOTAL" = "850" ]; then
  green "  PASS: 2c. total events = 850 (50 critical + 800 regular)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2c. total events (expected 850, got '$TOTAL')"
  FAIL=$((FAIL + 1))
fi

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
