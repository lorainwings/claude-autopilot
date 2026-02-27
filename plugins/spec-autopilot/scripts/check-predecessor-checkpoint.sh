#!/usr/bin/env bash
# check-predecessor-checkpoint.sh
# Hook: PreToolUse(Task)
# Purpose: Before dispatching a sub-Agent, verify the predecessor phase checkpoint
#          exists and has status=ok/warning. Prevents phase skipping.
#
# Detection: Only processes Task calls whose prompt starts with
#            <!-- autopilot-phase:N -->. All other Task calls are immediately allowed.
#
# Exit codes: 0=allow, 2=block

set -euo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CHANGES_DIR="$PROJECT_ROOT/openspec/changes"

# Read stdin JSON (PreToolUse receives: {"tool_name":"Task","tool_input":{...}})
STDIN_DATA=""
if [ ! -t 0 ]; then
  STDIN_DATA=$(cat)
fi

if [ -z "$STDIN_DATA" ]; then
  exit 0
fi

# Extract phase number from <!-- autopilot-phase:N --> marker in tool_input.prompt
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

# --- From here on, this is an autopilot Task for Phase $TARGET_PHASE ---

# Find active change directory (most recently modified)
find_active_change() {
  local latest=""
  local latest_time=0

  if [ ! -d "$CHANGES_DIR" ]; then
    return 1
  fi

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

# Get the last successful checkpoint phase number
get_last_checkpoint_phase() {
  local phase_results_dir="$1"
  local last_phase=0

  for phase_num in 2 3 4 5 6; do
    local pattern="$phase_results_dir/phase-${phase_num}-*.json"
    local checkpoint_file
    checkpoint_file=$(ls $pattern 2>/dev/null | head -1)

    if [ -n "$checkpoint_file" ] && [ -f "$checkpoint_file" ]; then
      local status
      status=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    print(data.get('status', 'unknown'))
except Exception:
    print('error')
" "$checkpoint_file" 2>/dev/null || echo "error")

      if [ "$status" = "ok" ] || [ "$status" = "warning" ]; then
        last_phase=$phase_num
      fi
    fi
  done

  echo $last_phase
}

# Main logic
main() {
  local change_dir
  change_dir=$(find_active_change) || exit 0  # No active change, allow

  local phase_results_dir="${change_dir}context/phase-results"

  if [ ! -d "$phase_results_dir" ]; then
    # No phase results yet, allow (Phase 2 is starting fresh)
    exit 0
  fi

  local last_phase
  last_phase=$(get_last_checkpoint_phase "$phase_results_dir")

  # Check if skipping phases (target > last_phase + 1, and target >= 3)
  if [ "$TARGET_PHASE" -ge 3 ] && [ "$TARGET_PHASE" -gt $((last_phase + 1)) ]; then
    echo "BLOCKED: Cannot start Phase $TARGET_PHASE. Last completed phase is $last_phase. Phase $((last_phase + 1)) must complete first." >&2
    exit 2
  fi

  # Special gate: Phase 5 requires Phase 4 test_counts validation
  if [ "$TARGET_PHASE" -eq 5 ]; then
    local phase4_file
    phase4_file=$(ls "$phase_results_dir"/phase-4-*.json 2>/dev/null | head -1)

    if [ -n "$phase4_file" ] && [ -f "$phase4_file" ]; then
      local test_counts_valid
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
        echo "BLOCKED: Phase 4 test_counts gate failed. Each test type must have >= 5 test cases." >&2
        exit 2
      fi
    fi
  fi

  # Special gate: Phase 6 requires Phase 5 zero_skip_check
  if [ "$TARGET_PHASE" -eq 6 ]; then
    local phase5_file
    phase5_file=$(ls "$phase_results_dir"/phase-5-*.json 2>/dev/null | head -1)

    if [ -n "$phase5_file" ] && [ -f "$phase5_file" ]; then
      local zero_skip_passed
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
        echo "BLOCKED: Phase 5 zero_skip_check gate failed. All tests must pass with zero skips." >&2
        exit 2
      fi
    fi

    # Also check tasks.md completion
    local tasks_file="${change_dir}tasks.md"

    if [ -f "$tasks_file" ]; then
      local unchecked
      unchecked=$(grep -c '\- \[ \]' "$tasks_file" 2>/dev/null || echo "0")
      if [ "$unchecked" -gt 0 ]; then
        echo "BLOCKED: tasks.md has $unchecked incomplete tasks. All must be [x] before Phase 6." >&2
        exit 2
      fi
    fi
  fi

  # All checks passed
  exit 0
}

main "$@"
