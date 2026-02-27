#!/usr/bin/env bash
# check-predecessor-checkpoint.sh
# Hook: PreToolUse(Task)
# Purpose: Before dispatching a sub-Agent, verify the predecessor phase checkpoint
#          exists and has status=ok/warning. Prevents phase skipping.
#
# Detection: Only processes Task calls whose prompt contains
#            <!-- autopilot-phase:N -->. All other Task calls exit 0 immediately.
#
# Output: JSON with hookSpecificOutput.permissionDecision on deny (official spec).
#         Plain exit 0 on allow.

set -uo pipefail
# NOTE: no `set -e` — we handle errors explicitly to avoid pipefail + ls crashes.

# --- Dependency check ---
if ! command -v python3 &>/dev/null; then
  # Cannot validate without python3 → block to be safe (fail-closed)
  cat <<'DENY_JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "python3 is required for autopilot gate hooks but not found in PATH"
  }
}
DENY_JSON
  exit 0
fi

# --- Read stdin JSON ---
STDIN_DATA=""
if [ ! -t 0 ]; then
  STDIN_DATA=$(cat)
fi

if [ -z "$STDIN_DATA" ]; then
  exit 0
fi

# --- Extract project root from stdin cwd (preferred) or git fallback ---
PROJECT_ROOT=$(echo "$STDIN_DATA" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get('cwd', ''))
except Exception:
    pass
" 2>/dev/null || echo "")

if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

CHANGES_DIR="$PROJECT_ROOT/openspec/changes"

# --- Extract phase number from marker ---
TARGET_PHASE=$(echo "$STDIN_DATA" | python3 -c "
import json, sys, re
try:
    data = json.load(sys.stdin)
    prompt = data.get('tool_input', {}).get('prompt', '')
    m = re.search(r'<!--\s*autopilot-phase:(\d+)\s*-->', prompt)
    if m:
        print(m.group(1))
except Exception:
    pass
" 2>/dev/null || echo "")

# No marker → not an autopilot Task, allow immediately
if [ -z "$TARGET_PHASE" ]; then
  exit 0
fi

# --- Helper: output deny JSON and exit 0 (fail-closed) ---
deny() {
  local reason="$1"
  local json_output
  json_output=$(python3 -c "
import json, sys
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'deny',
        'permissionDecisionReason': sys.argv[1]
    }
}))
" "$reason" 2>/dev/null) || true

  if [ -n "$json_output" ]; then
    echo "$json_output"
  else
    # Fallback: hardcoded JSON if python3 fails (fail-closed, never allow)
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Autopilot gate check failed (internal error)"}}'
  fi
  exit 0
}

# --- Find active change directory ---
# Uses the most recently modified checkpoint file to determine active change,
# falling back to directory mtime if no checkpoints exist.
find_active_change() {
  if [ ! -d "$CHANGES_DIR" ]; then
    return 1
  fi

  # First try: find the change with the most recent checkpoint file
  local latest_file=""
  local latest_dir=""
  local find_results
  find_results=$(find "$CHANGES_DIR" -path "*/context/phase-results/phase-*.json" -type f 2>/dev/null) || true
  if [ -n "$find_results" ]; then
    latest_file=$(echo "$find_results" | xargs ls -t 2>/dev/null | head -1) || true
  fi

  if [ -n "$latest_file" ]; then
    # Extract change dir: .../changes/<name>/context/phase-results/file.json → .../changes/<name>/
    latest_dir=$(echo "$latest_file" | sed 's|/context/phase-results/.*||')
    if [ -d "$latest_dir" ]; then
      echo "${latest_dir}/"
      return 0
    fi
  fi

  # Fallback: most recently modified change directory
  local latest=""
  local latest_time=0

  for dir in "$CHANGES_DIR"/*/; do
    [ -d "$dir" ] || continue
    [[ "$(basename "$dir")" == _* ]] && continue

    local mtime
    mtime=$(stat -f "%m" "$dir" 2>/dev/null || stat -c "%Y" "$dir" 2>/dev/null || echo 0)
    if [ "$mtime" -gt "$latest_time" ]; then
      latest_time=$mtime
      latest="$dir"
    fi
  done

  if [ -n "$latest" ]; then
    echo "$latest"
    return 0
  fi
  return 1
}

# --- Find latest checkpoint file for a phase (by mtime, not alphabetical) ---
find_checkpoint() {
  local dir="$1"
  local phase="$2"
  local results
  results=$(find "$dir" -maxdepth 1 -name "phase-${phase}-*.json" -type f 2>/dev/null) || true
  if [ -n "$results" ]; then
    echo "$results" | xargs ls -t 2>/dev/null | head -1
  fi
}

# --- Read checkpoint status ---
read_checkpoint_status() {
  local file="$1"
  python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    print(data.get('status', 'unknown'))
except Exception:
    print('error')
" "$file" 2>/dev/null || echo "error"
}

# --- Get the last successful checkpoint phase number ---
get_last_checkpoint_phase() {
  local phase_results_dir="$1"
  local last_phase=0

  for phase_num in 2 3 4 5 6; do
    local checkpoint_file
    checkpoint_file=$(find_checkpoint "$phase_results_dir" "$phase_num")

    if [ -n "$checkpoint_file" ] && [ -f "$checkpoint_file" ]; then
      local status
      status=$(read_checkpoint_status "$checkpoint_file")
      if [ "$status" = "ok" ] || [ "$status" = "warning" ]; then
        last_phase=$phase_num
      fi
    fi
  done

  echo $last_phase
}

# === Main logic ===

change_dir=$(find_active_change) || exit 0  # No active change, allow

phase_results_dir="${change_dir}context/phase-results"

if [ ! -d "$phase_results_dir" ]; then
  # No phase results yet → Phase 2 starting fresh
  exit 0
fi

last_phase=$(get_last_checkpoint_phase "$phase_results_dir")

# Check sequential ordering (target > last_phase + 1, and target >= 3)
if [ "$TARGET_PHASE" -ge 3 ] && [ "$TARGET_PHASE" -gt $((last_phase + 1)) ]; then
  deny "Cannot start Phase $TARGET_PHASE. Last completed phase is $last_phase. Phase $((last_phase + 1)) must complete first."
fi

# Special gate: Phase 5 requires Phase 4 test_counts validation
if [ "$TARGET_PHASE" -eq 5 ]; then
  phase4_file=$(find_checkpoint "$phase_results_dir" 4)

  if [ -n "$phase4_file" ] && [ -f "$phase4_file" ]; then
    test_counts_valid=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    counts = data.get('test_counts', {})
    min_count = 5
    all_valid = all(counts.get(t, 0) >= min_count for t in ['unit', 'api', 'e2e', 'ui'])
    print('true' if all_valid else 'false')
except Exception:
    print('false')
" "$phase4_file" 2>/dev/null || echo "false")

    if [ "$test_counts_valid" = "false" ]; then
      deny "Phase 4 test_counts gate failed. Each test type (unit, api, e2e, ui) must have >= 5 test cases."
    fi
  fi
fi

# Special gate: Phase 6 requires Phase 5 zero_skip_check
if [ "$TARGET_PHASE" -eq 6 ]; then
  phase5_file=$(find_checkpoint "$phase_results_dir" 5)

  if [ -n "$phase5_file" ] && [ -f "$phase5_file" ]; then
    zero_skip_passed=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    zsc = data.get('zero_skip_check', {})
    print('true' if zsc.get('passed', False) else 'false')
except Exception:
    print('false')
" "$phase5_file" 2>/dev/null || echo "false")

    if [ "$zero_skip_passed" = "false" ]; then
      deny "Phase 5 zero_skip_check gate failed. All tests must pass with zero skips."
    fi
  fi

  # Also check tasks.md completion
  tasks_file="${change_dir}tasks.md"
  if [ -f "$tasks_file" ]; then
    unchecked=$(grep -c '\- \[ \]' "$tasks_file" 2>/dev/null || echo "0")
    if [ "$unchecked" -gt 0 ]; then
      deny "tasks.md has $unchecked incomplete tasks. All must be [x] before Phase 6."
    fi
  fi
fi

# All checks passed
exit 0
