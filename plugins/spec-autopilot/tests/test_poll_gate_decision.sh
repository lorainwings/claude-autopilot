#!/usr/bin/env bash
# test_poll_gate_decision.sh — Regression tests for gate override safety
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"

POLL_SCRIPT="$SCRIPT_DIR/poll-gate-decision.sh"

setup_poll_project() {
  local tmpdir
  tmpdir=$(mktemp -d)
  local project_root="$tmpdir/project"
  local change_dir="$project_root/openspec/changes/test-feature/"

  mkdir -p "${change_dir}context" "$project_root/.claude" "$project_root/logs"
  cat > "$project_root/.claude/autopilot.config.yaml" <<'EOF'
gui:
  decision_poll_timeout: 5
EOF

  echo "$project_root"
}

echo "--- poll-gate-decision override safety ---"

# 1. full mode Phase 5: override must be rejected and polling must continue
PROJECT_ROOT=$(setup_poll_project)
CHANGE_DIR="$PROJECT_ROOT/openspec/changes/test-feature/"
OUTPUT_FILE="$PROJECT_ROOT/output.json"
PROJECT_ROOT_QUICK="$PROJECT_ROOT" bash "$POLL_SCRIPT" "$CHANGE_DIR" 5 full '{"blocked_step":8,"error_message":"quality floor"}' > "$OUTPUT_FILE" 2>&1 &
PID=$!

sleep 1
REQUEST_JSON=$(cat "${CHANGE_DIR}context/decision-request.json")
assert_contains "full Phase 5 request marks override disallowed" "$REQUEST_JSON" '"override_allowed": false'

cat > "${CHANGE_DIR}context/decision.json" <<'EOF'
{"action":"override","phase":5,"reason":"force it"}
EOF
sleep 1

if kill -0 "$PID" 2>/dev/null; then
  green "  PASS: disallowed override does not terminate polling"
  PASS=$((PASS + 1))
else
  red "  FAIL: polling exited after disallowed override"
  FAIL=$((FAIL + 1))
fi

cat > "${CHANGE_DIR}context/decision.json" <<'EOF'
{"action":"retry","phase":5,"reason":"rerun gate"}
EOF
sleep 1
wait "$PID"
EXIT_CODE=$?
OUTPUT=$(cat "$OUTPUT_FILE")

assert_exit "full Phase 5 falls through to retry after rejecting override" 0 "$EXIT_CODE"
assert_contains "full Phase 5 final action is retry" "$OUTPUT" '"action": "retry"'
rm -rf "$(dirname "$PROJECT_ROOT")"

# 2. minimal mode Phase 5: override remains allowed
PROJECT_ROOT=$(setup_poll_project)
CHANGE_DIR="$PROJECT_ROOT/openspec/changes/test-feature/"
OUTPUT_FILE="$PROJECT_ROOT/output.json"
PROJECT_ROOT_QUICK="$PROJECT_ROOT" bash "$POLL_SCRIPT" "$CHANGE_DIR" 5 minimal '{"blocked_step":2,"error_message":"manual approval"}' > "$OUTPUT_FILE" 2>&1 &
PID=$!

sleep 1
REQUEST_JSON=$(cat "${CHANGE_DIR}context/decision-request.json")
assert_contains "minimal Phase 5 request keeps override allowed" "$REQUEST_JSON" '"override_allowed": true'

cat > "${CHANGE_DIR}context/decision.json" <<'EOF'
{"action":"override","phase":5,"reason":"allowed in minimal"}
EOF
wait "$PID"
EXIT_CODE=$?
OUTPUT=$(cat "$OUTPUT_FILE")

assert_exit "minimal Phase 5 accepts override" 0 "$EXIT_CODE"
assert_contains "minimal Phase 5 returns override action" "$OUTPUT" '"action": "override"'
rm -rf "$(dirname "$PROJECT_ROOT")"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
