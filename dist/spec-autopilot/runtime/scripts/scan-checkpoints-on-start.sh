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
  exit 0 # SessionStart: fail silently, don't block session
fi

found_any=false

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
      # P0-4: Validate JSON integrity before using checkpoint
      if ! validate_checkpoint_integrity "$checkpoint_file"; then
        continue
      fi
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

    # v4.1: mode-aware resume suggestion
    local lock_file="$CHANGES_DIR/.autopilot-active"
    local mode=""
    if [ -f "${lock_file}" ]; then
      mode=$(python3 -c "
import json
try:
    with open('${lock_file}') as f: data = json.load(f)
    print(data.get('mode', 'full'))
except: print('full')
" 2>/dev/null || echo "full")
    fi
    if [ -z "$mode" ]; then
      mode="full"
    fi

    # v5.6: Use _phase_graph.py for consistent mode-aware phase sequence
    local -a phases_seq
    local _pg_json
    _pg_json=$(python3 "$SCRIPT_DIR/_phase_graph.py" get_phase_sequence "$mode" 2>/dev/null) || _pg_json=""
    if [ -n "$_pg_json" ] && [ "$_pg_json" != "[]" ]; then
      read -ra phases_seq <<<"$(echo "$_pg_json" | python3 -c "import json,sys; print(' '.join(str(x) for x in json.load(sys.stdin)))" 2>/dev/null)"
    else
      case "$mode" in
        lite) phases_seq=(1 5 6 7) ;;
        minimal) phases_seq=(1 5 7) ;;
        *) phases_seq=(1 2 3 4 5 6 7) ;;
      esac
    fi

    # Calculate suggested resume phase from mode-aware sequence
    local suggested_resume=1
    for i in "${!phases_seq[@]}"; do
      if [ "${phases_seq[$i]}" -eq "$last_phase" ]; then
        local next_idx=$((i + 1))
        if [ "$next_idx" -lt "${#phases_seq[@]}" ]; then
          suggested_resume="${phases_seq[$next_idx]}"
        else
          suggested_resume="done"
        fi
        break
      fi
    done

    echo ""
    echo "Change: $change_name"
    echo "  Last successful phase: $last_phase ($last_status)"
    if [ "$suggested_resume" = "done" ]; then
      echo "  Suggested resume: All phases complete"
    else
      echo "  Suggested resume: Phase $suggested_resume (mode: $mode)"
    fi
    echo "  Checkpoints:"
    for cp in "${checkpoints[@]}"; do
      echo "$cp"
    done

    # v5.3: Scan progress files inline (avoid double loop)
    for progress_file in "$phase_results_dir"/phase-*-progress.json; do
      [ -f "$progress_file" ] || continue
      local pg_name pg_step pg_status
      pg_name=$(basename "$progress_file")
      pg_step=""
      pg_status=""
      if command -v python3 &>/dev/null; then
        pg_step=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f: d = json.load(f)
    print(d.get('step',''))
except: pass
" "$progress_file" 2>/dev/null || true)
        pg_status=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f: d = json.load(f)
    print(d.get('status',''))
except: pass
" "$progress_file" 2>/dev/null || true)
      fi
      if [ -n "$pg_step" ]; then
        echo "  Sub-step progress: $pg_name → step=$pg_step status=$pg_status"
      fi
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

  # v5.3: Git rebase intermediate state detection
  if [ -d "$PROJECT_ROOT/.git/rebase-merge" ]; then
    echo "WARNING: Git rebase in progress detected (.git/rebase-merge exists)."
    echo "  Recovery will abort rebase before resuming."
    echo ""
  fi

  # v5.3: Worktree residual detection
  WORKTREE_RESIDUAL=$(git -C "$PROJECT_ROOT" worktree list 2>/dev/null | grep "autopilot-task" || true)
  if [ -n "$WORKTREE_RESIDUAL" ]; then
    echo "WARNING: Residual autopilot worktrees detected:"
    echo "$WORKTREE_RESIDUAL" | sed 's/^/  /'
    echo "  Consider cleaning up with: git worktree remove <path>"
    echo ""
  fi

  echo ""
  echo "Use autopilot to resume from the last checkpoint."
  echo "================================="
fi

exit 0
