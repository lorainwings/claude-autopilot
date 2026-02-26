#!/usr/bin/env bash
# check-predecessor-checkpoint.sh
# Hook: PreToolUse(Task)
# Purpose: Before dispatching a sub-Agent, verify the predecessor phase checkpoint
#          exists and has status=ok/warning. Prevents phase skipping.
# Exit codes: 0=allow, 2=block

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CHANGES_DIR="$PROJECT_ROOT/openspec/changes"

# Find active change directory (most recently modified)
find_active_change() {
  local latest=""
  local latest_time=0

  if [ ! -d "$CHANGES_DIR" ]; then
    return 1
  fi

  for dir in "$CHANGES_DIR"/*/; do
    [ -d "$dir" ] || continue
    # Skip archive-like directories
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
    with open('$checkpoint_file') as f:
        data = json.load(f)
    print(data.get('status', 'unknown'))
except:
    print('error')
" 2>/dev/null || echo "error")

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

  # Read the Task prompt from stdin to detect which phase is being dispatched
  # The hook receives tool input via environment or stdin
  local task_input="${TOOL_INPUT:-}"

  if [ -z "$task_input" ]; then
    # No way to determine target phase, allow
    exit 0
  fi

  # Extract phase number from prompt (look for "阶段 N" or "Phase N" patterns)
  local target_phase
  target_phase=$(echo "$task_input" | grep -oE '(Phase|阶段)\s*[0-9]+' | head -1 | grep -oE '[0-9]+' || echo "")

  if [ -z "$target_phase" ]; then
    # Cannot determine target phase from prompt, allow
    exit 0
  fi

  # Check if skipping phases (target > last_phase + 1, and target >= 3)
  if [ "$target_phase" -ge 3 ] && [ "$target_phase" -gt $((last_phase + 1)) ]; then
    echo "BLOCKED: Cannot start Phase $target_phase. Last completed phase is $last_phase. Phase $((last_phase + 1)) must complete first." >&2
    exit 2
  fi

  # Special gate: Phase 5 requires Phase 4 test_counts validation
  if [ "$target_phase" -eq 5 ]; then
    local phase4_file
    phase4_file=$(ls "$phase_results_dir"/phase-4-*.json 2>/dev/null | head -1)

    if [ -n "$phase4_file" ] && [ -f "$phase4_file" ]; then
      local test_counts_valid
      test_counts_valid=$(python3 -c "
import json, sys
try:
    with open('$phase4_file') as f:
        data = json.load(f)
    counts = data.get('test_counts', {})
    min_count = 5
    all_valid = all(counts.get(t, 0) >= min_count for t in ['unit', 'api', 'e2e', 'ui'])
    print('true' if all_valid else 'false')
except:
    print('false')
" 2>/dev/null || echo "false")

      if [ "$test_counts_valid" = "false" ]; then
        echo "BLOCKED: Phase 4 test_counts gate failed. Each test type must have >= 5 test cases." >&2
        exit 2
      fi
    fi
  fi

  # Special gate: Phase 6 requires Phase 5 zero_skip_check
  if [ "$target_phase" -eq 6 ]; then
    local phase5_file
    phase5_file=$(ls "$phase_results_dir"/phase-5-*.json 2>/dev/null | head -1)

    if [ -n "$phase5_file" ] && [ -f "$phase5_file" ]; then
      local zero_skip_passed
      zero_skip_passed=$(python3 -c "
import json, sys
try:
    with open('$phase5_file') as f:
        data = json.load(f)
    zsc = data.get('zero_skip_check', {})
    print('true' if zsc.get('passed', False) else 'false')
except:
    print('false')
" 2>/dev/null || echo "false")

      if [ "$zero_skip_passed" = "false" ]; then
        echo "BLOCKED: Phase 5 zero_skip_check gate failed. All tests must pass with zero skips." >&2
        exit 2
      fi
    fi

    # Also check tasks.md completion
    local change_name
    change_name=$(basename "$change_dir")
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
