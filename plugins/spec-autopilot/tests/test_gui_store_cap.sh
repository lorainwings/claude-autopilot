#!/usr/bin/env bash
# test_gui_store_cap.sh — Regression test for GUI store event cap limits
# Verifies: critical events capped at 400, regular events capped at 2400
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

cat >"$TMPFILE" <<'TSEOF'
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

// Test 1: 450 critical events should be capped to 400
store.getState().addEvents(makeEvents(450, "phase_start", 1));
const afterCritical = store.getState().events;
const critCount = afterCritical.filter((e) => e.type === "phase_start").length;

// Test 2: Reset and add 2600 regular + 50 critical
store.getState().reset();
store.getState().addEvents(makeEvents(50, "gate_block", 1));
store.getState().addEvents(makeEvents(2600, "tool_use", 100));
const afterMixed = store.getState().events;
const mixedCrit = afterMixed.filter((e) => e.type === "gate_block").length;
const mixedReg = afterMixed.filter((e) => e.type === "tool_use").length;
const total = afterMixed.length;

// Test 3: Orchestration state extraction
store.getState().reset();
store.getState().addEvents([
  {
    sequence: 1, type: "session_start", phase: 0, mode: "full" as const,
    session_id: "test-orch", change_name: "feat-login", total_phases: 8,
    timestamp: new Date().toISOString(), phase_label: "init",
    payload: { goal_summary: "实现登录功能" },
  },
  {
    sequence: 2, type: "gate_block", phase: 1, mode: "full" as const,
    session_id: "test-orch", change_name: "feat-login", total_phases: 8,
    timestamp: new Date().toISOString(), phase_label: "requirements",
    payload: { reason: "测试覆盖率不足", error_message: "coverage < 80%" },
  },
  {
    sequence: 3, type: "status_snapshot", phase: 1, mode: "full" as const,
    session_id: "test-orch", change_name: "feat-login", total_phases: 8,
    timestamp: new Date().toISOString(), phase_label: "requirements",
    payload: { context_window: { percent: 75 } },
  },
  {
    sequence: 4, type: "archive_readiness", phase: 7, mode: "full" as const,
    session_id: "test-orch", change_name: "feat-login", total_phases: 8,
    timestamp: new Date().toISOString(), phase_label: "archive",
    payload: { fixup_complete: true, review_gate_passed: false, ready: false },
  },
]);
const orch = store.getState().orchestration;
const orchGoal = orch.goalSummary;
const orchGateFrontier = orch.gateFrontierReason;
const orchContextPct = orch.contextBudget?.percent ?? -1;
const orchContextRisk = orch.contextBudget?.risk ?? "none";
const orchArchiveReady = orch.archiveReadiness?.ready ?? null;
const orchFixupComplete = orch.archiveReadiness?.fixupComplete ?? null;

console.log(JSON.stringify({
  critCount, mixedCrit, mixedReg, total,
  orchGoal, orchGateFrontier, orchContextPct, orchContextRisk,
  orchArchiveReady, orchFixupComplete,
}));
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
ORCH_GOAL=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['orchGoal'])" 2>/dev/null || echo "")
ORCH_GATE=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['orchGateFrontier'])" 2>/dev/null || echo "")
ORCH_CTX_PCT=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['orchContextPct'])" 2>/dev/null || echo "")
ORCH_CTX_RISK=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['orchContextRisk'])" 2>/dev/null || echo "")
ORCH_ARCHIVE_READY=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['orchArchiveReady'])" 2>/dev/null || echo "")
ORCH_FIXUP=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['orchFixupComplete'])" 2>/dev/null || echo "")

# Test 1: 450 critical → capped to 400
if [ "$CRIT_COUNT" = "400" ]; then
  green "  PASS: 1. critical events capped at 400 (450 → 400)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 1. critical events cap (expected 400, got '$CRIT_COUNT')"
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

if [ "$MIXED_REG" = "2400" ]; then
  green "  PASS: 2b. regular events capped at 2400 (2600 → 2400)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2b. regular events cap (expected 2400, got '$MIXED_REG')"
  FAIL=$((FAIL + 1))
fi

if [ "$TOTAL" = "2450" ]; then
  green "  PASS: 2c. total events = 2450 (50 critical + 2400 regular)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2c. total events (expected 2450, got '$TOTAL')"
  FAIL=$((FAIL + 1))
fi

# Test 3: Orchestration state extraction
echo ""
echo "  [3] Orchestration state extraction"

if [ "$ORCH_GOAL" = "实现登录功能" ]; then
  green "  PASS: 3a. goalSummary extracted from session_start"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3a. goalSummary (expected '实现登录功能', got '$ORCH_GOAL')"
  FAIL=$((FAIL + 1))
fi

if [ "$ORCH_GATE" = "测试覆盖率不足" ]; then
  green "  PASS: 3b. gateFrontierReason extracted from gate_block"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3b. gateFrontierReason (expected '测试覆盖率不足', got '$ORCH_GATE')"
  FAIL=$((FAIL + 1))
fi

if [ "$ORCH_CTX_PCT" = "75" ]; then
  green "  PASS: 3c. contextBudget.percent extracted from status_snapshot"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3c. contextBudget.percent (expected 75, got '$ORCH_CTX_PCT')"
  FAIL=$((FAIL + 1))
fi

if [ "$ORCH_CTX_RISK" = "medium" ]; then
  green "  PASS: 3d. contextBudget.risk calculated as medium (60 < 75 <= 80)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3d. contextBudget.risk (expected 'medium', got '$ORCH_CTX_RISK')"
  FAIL=$((FAIL + 1))
fi

if [ "$ORCH_ARCHIVE_READY" = "False" ]; then
  green "  PASS: 3e. archiveReadiness.ready = false"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3e. archiveReadiness.ready (expected False, got '$ORCH_ARCHIVE_READY')"
  FAIL=$((FAIL + 1))
fi

if [ "$ORCH_FIXUP" = "True" ]; then
  green "  PASS: 3f. archiveReadiness.fixupComplete = true"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3f. archiveReadiness.fixupComplete (expected True, got '$ORCH_FIXUP')"
  FAIL=$((FAIL + 1))
fi

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
