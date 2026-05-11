#!/usr/bin/env bash
# validate-phase1-complete.sh
# L2 Hook supplement: validates Phase 1 outputs are complete before Phase 2 dispatch.
#
# Called by check-predecessor-checkpoint.sh as an additional gate for Phase 2.
# Can also be called standalone by the main thread before Phase 2-3 fast path.
#
# Usage: validate-phase1-complete.sh <project_root>
#
# Checks:
#   1. context/phase-results/phase-1-requirements.json exists + status ok/warning
#   2. context/requirement-packet.json exists + contains "goal" and "sha256" fields
#   3. Lock file "change" field is not "pending" or empty
#
# Output: JSON on stdout
#   Success: {"valid": true}
#   Failure: {"valid": false, "reason": "...", "fix_hint": "..."}
#
# Exit: 0 always (caller reads JSON to decide)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

PROJECT_ROOT="${1:-$(resolve_project_root)}"

fail() {
  local reason="$1"
  local hint="${2:-}"
  python3 -c "
import json, sys
print(json.dumps({'valid': False, 'reason': sys.argv[1], 'fix_hint': sys.argv[2]}, ensure_ascii=False))
" "$reason" "$hint"
  exit 0
}

if ! command -v python3 &>/dev/null; then
  fail "python3 not found" "Install python3"
fi

CHANGES_DIR="$PROJECT_ROOT/openspec/changes"
if [ ! -d "$CHANGES_DIR" ]; then
  fail "openspec/changes/ directory not found" "Run Phase 0 init first"
fi

# Check 1: Lock file change field
LOCK_FILE="$CHANGES_DIR/.autopilot-active"
if [ ! -f "$LOCK_FILE" ]; then
  fail "Lock file .autopilot-active not found" "Phase 0 must create the lock file"
fi

LOCK_CHANGE=$(parse_lock_file "$LOCK_FILE")
if [ -z "$LOCK_CHANGE" ] || [ "$LOCK_CHANGE" = "pending" ]; then
  fail "Lock file 'change' field is '${LOCK_CHANGE:-empty}'. Phase 1 must call init-change-dir.sh to set the actual change name." \
    "Run: bash \${CLAUDE_PLUGIN_ROOT}/runtime/scripts/init-change-dir.sh \"$PROJECT_ROOT\" \"<change_name>\""
fi

CHANGE_DIR="$CHANGES_DIR/$LOCK_CHANGE"
if [ ! -d "$CHANGE_DIR" ]; then
  fail "Change directory '$LOCK_CHANGE' does not exist" "init-change-dir.sh should have created it"
fi

# Check 2: Phase 1 checkpoint
PHASE_RESULTS="$CHANGE_DIR/context/phase-results"
if [ ! -d "$PHASE_RESULTS" ]; then
  fail "context/phase-results/ directory not found in change '$LOCK_CHANGE'" \
    "init-change-dir.sh should have created it. Run: bash \${CLAUDE_PLUGIN_ROOT}/runtime/scripts/init-change-dir.sh \"$PROJECT_ROOT\" \"$LOCK_CHANGE\""
fi

PHASE1_FILE=$(find_checkpoint "$PHASE_RESULTS" 1)
if [ -z "$PHASE1_FILE" ] || [ ! -f "$PHASE1_FILE" ]; then
  fail "Phase 1 checkpoint not found in $PHASE_RESULTS" \
    "Phase 1 must write checkpoint via write-checkpoint.sh before Phase 2 can start"
fi

PHASE1_STATUS=$(read_checkpoint_status "$PHASE1_FILE")
if [ "$PHASE1_STATUS" != "ok" ] && [ "$PHASE1_STATUS" != "warning" ]; then
  fail "Phase 1 checkpoint status is '$PHASE1_STATUS' (must be ok/warning)" \
    "Re-run Phase 1 to produce a valid checkpoint"
fi

# Check 3: requirement-packet.json
PACKET_FILE="$CHANGE_DIR/context/requirement-packet.json"
if [ ! -f "$PACKET_FILE" ]; then
  fail "requirement-packet.json not found at $CHANGE_DIR/context/" \
    "Phase 1 PackagerAgent must produce context/requirement-packet.json"
fi

PACKET_VALID=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    has_goal = 'goal' in data and isinstance(data['goal'], str) and len(data['goal']) >= 3
    has_sha = 'sha256' in data and isinstance(data['sha256'], str) and len(data['sha256']) == 64
    if not has_goal:
        print('missing_goal')
    elif not has_sha:
        print('missing_sha256')
    else:
        print('valid')
except Exception as e:
    print(f'parse_error:{e}')
" "$PACKET_FILE" 2>/dev/null || echo "python_error")

case "$PACKET_VALID" in
  valid) ;;
  missing_goal)
    fail "requirement-packet.json missing required 'goal' field (string, min 3 chars)" \
      "PackagerAgent must produce a valid packet per runtime/schemas/requirement-packet.schema.json"
    ;;
  missing_sha256)
    fail "requirement-packet.json missing required 'sha256' field (64 hex chars)" \
      "PackagerAgent must compute sha256 of canonicalized packet"
    ;;
  *)
    fail "requirement-packet.json is invalid: $PACKET_VALID" \
      "Regenerate via PackagerAgent"
    ;;
esac

# All checks passed
echo '{"valid": true}'
exit 0
