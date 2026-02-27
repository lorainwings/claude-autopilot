#!/usr/bin/env bash
# scan-checkpoints-on-start.sh
# Hook: SessionStart
# Purpose: Scan openspec/changes/*/context/phase-results/ for existing checkpoints
#          and output a summary. Enables cross-session recovery awareness.
# Exit codes: 0 (informational only, never blocks)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CHANGES_DIR="$PROJECT_ROOT/openspec/changes"

if [ ! -d "$CHANGES_DIR" ]; then
  exit 0
fi

found_any=false

for change_dir in "$CHANGES_DIR"/*/; do
  [ -d "$change_dir" ] || continue
  [[ "$(basename "$change_dir")" == _* ]] && continue

  phase_results_dir="${change_dir}context/phase-results"
  [ -d "$phase_results_dir" ] || continue

  change_name=$(basename "$change_dir")
  checkpoints=()
  last_phase=0
  last_status=""

  for phase_num in 2 3 4 5 6; do
    checkpoint_file=$(ls "$phase_results_dir"/phase-${phase_num}-*.json 2>/dev/null | head -1)

    if [ -n "$checkpoint_file" ] && [ -f "$checkpoint_file" ]; then
      status=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    print(data.get('status', 'unknown'))
except:
    print('error')
" "$checkpoint_file" 2>/dev/null || echo "error")

      summary=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    print(data.get('summary', 'N/A')[:60])
except:
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
done

if [ "$found_any" = true ]; then
  echo ""
  echo "Use autopilot to resume from the last checkpoint."
  echo "================================="
fi

exit 0
