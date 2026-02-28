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

# Process a single change directory and collect checkpoint info.
# Extracted to function so `local` is valid.
process_change_dir() {
  local change_dir="$1"
  local phase_results_dir="${change_dir}context/phase-results"
  [ -d "$phase_results_dir" ] || return 0

  local change_name
  change_name=$(basename "$change_dir")
  local checkpoints=()
  local last_phase=0
  local last_status=""

  for phase_num in 2 3 4 5 6; do
    local find_results=""
    find_results=$(find "$phase_results_dir" -maxdepth 1 -name "phase-${phase_num}-*.json" -type f 2>/dev/null) || true
    local checkpoint_file=""
    if [ -n "$find_results" ]; then
      checkpoint_file=$(echo "$find_results" | tr '\n' '\0' | xargs -0 ls -t 2>/dev/null | head -1) || true
    fi

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
    echo "  Suggested resume: Phase $((last_phase + 1))"
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
