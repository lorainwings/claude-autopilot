#!/usr/bin/env bash
# scan-checkpoints-on-start.sh
# Hook: SessionStart
# Purpose: Scan openspec/changes/*/context/phase-results/ for existing checkpoints
#          and output a summary. Enables cross-session recovery awareness.
#
# Output: stdout text is added to Claude's context (SessionStart behavior).
#         Only outputs if checkpoints exist; zero output for non-autopilot sessions.
# Exit codes: 0 (informational only, never blocks)

set -uo pipefail
# NOTE: no `set -e` — we handle errors explicitly to avoid pipefail crashes.

# --- Source shared utilities ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CHANGES_DIR="$PROJECT_ROOT/openspec/changes"

if [ ! -d "$CHANGES_DIR" ]; then
  exit 0
fi

# Check python3 availability (needed for JSON parsing)
if ! command -v python3 &>/dev/null; then
  exit 0  # SessionStart: fail silently, don't block session
fi

found_any=false

# --- Read execution mode from lock file ---
get_autopilot_mode_for_scan() {
  local lock_file="$CHANGES_DIR/.autopilot-active"
  if [ -f "$lock_file" ]; then
    python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    print(data.get('mode', 'full'))
except Exception:
    print('full')
" "$lock_file" 2>/dev/null || echo "full"
  else
    echo "full"
  fi
}

# --- Get next phase in mode-aware sequence ---
get_next_phase_in_sequence() {
  local mode="$1"
  local last_phase="$2"
  local phases_sequence
  case "$mode" in
    lite)    phases_sequence=(1 5 6 7) ;;
    minimal) phases_sequence=(1 5 7) ;;
    *)       phases_sequence=(1 2 3 4 5 6 7) ;;
  esac

  local found=false
  for p in "${phases_sequence[@]}"; do
    if [ "$found" = true ]; then
      echo "$p"
      return
    fi
    if [ "$p" -eq "$last_phase" ]; then
      found=true
    fi
  done
  # If last_phase is the final one, return "done"
  echo "done"
}

SCAN_MODE=$(get_autopilot_mode_for_scan)

# Process a single change directory and collect checkpoint info.
# Uses find_checkpoint and read_checkpoint_status from _common.sh
process_change_dir() {
  local change_dir="$1"
  local phase_results_dir="${change_dir}context/phase-results"
  [ -d "$phase_results_dir" ] || return 0

  local change_name
  change_name=$(basename "$change_dir")
  local checkpoints=()
  local last_phase=0
  local last_status=""

  for phase_num in 1 2 3 4 5 6 7; do
    local checkpoint_file
    checkpoint_file=$(find_checkpoint "$phase_results_dir" "$phase_num")

    if [ -n "$checkpoint_file" ] && [ -f "$checkpoint_file" ]; then
      local status
      status=$(read_checkpoint_status "$checkpoint_file")

      local summary
      summary=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    print(data.get('summary', 'N/A')[:60])
except Exception:
    print('N/A')
" "$checkpoint_file" 2>/dev/null || echo "N/A")

      checkpoints+=("  Phase $phase_num: [$status] $summary")

      if [ "$status" = "ok" ] || [ "$status" = "warning" ]; then
        last_phase=$phase_num
        last_status=$status
      fi
    fi
  done

  if [ ${#checkpoints[@]} -gt 0 ]; then
    if [ "$found_any" = false ]; then
      echo "=== Autopilot Checkpoint Summary ==="
      found_any=true
    fi

    echo ""
    echo "Change: $change_name"
    echo "  Last successful phase: $last_phase ($last_status)"
    local next_phase
    next_phase=$(get_next_phase_in_sequence "$SCAN_MODE" "$last_phase")
    if [ "$next_phase" = "done" ]; then
      echo "  Status: All phases completed (mode: $SCAN_MODE)"
    else
      echo "  Suggested resume: Phase $next_phase (mode: $SCAN_MODE)"
    fi
    echo "  Checkpoints:"
    for cp in "${checkpoints[@]}"; do
      echo "$cp"
    done
  fi
}

for change_dir in "$CHANGES_DIR"/*/; do
  [ -d "$change_dir" ] || continue
  [[ "$(basename "$change_dir")" == _* ]] && continue
  process_change_dir "$change_dir"
done

if [ "$found_any" = true ]; then
  echo ""
  echo "Use autopilot to resume from the last checkpoint."
  echo "================================="
fi

exit 0
