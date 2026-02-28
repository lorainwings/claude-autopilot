#!/usr/bin/env bash
# _common.sh
# Shared utility functions for autopilot hook scripts.
# Source this file at the top of each hook script:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/_common.sh"

# --- Parse lock file (JSON or legacy plain text) ---
# Usage: parse_lock_file <lock_file_path>
# Returns: change name on stdout, or empty string on failure
# Requires: python3 (falls back gracefully)
parse_lock_file() {
  local lock_file="$1"
  [ -f "$lock_file" ] || return 1

  local active_name
  active_name=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    print(data.get('change', ''))
except (json.JSONDecodeError, KeyError):
    with open(sys.argv[1]) as f:
        print(f.read().strip())
except Exception:
    pass
" "$lock_file" 2>/dev/null) || true
  echo "$active_name" | tr -d '[:space:]'
}

# --- Find active change directory ---
# Usage: find_active_change <changes_dir> [trailing_slash]
# Args:
#   changes_dir: path to openspec/changes/
#   trailing_slash: "yes" to append trailing /, "no" (default) to omit
# Returns: path on stdout, exit 0 on success, exit 1 on failure
find_active_change() {
  local changes_dir="$1"
  local trailing_slash="${2:-no}"

  if [ ! -d "$changes_dir" ]; then
    return 1
  fi

  local _append=""
  [ "$trailing_slash" = "yes" ] && _append="/"

  # Priority 0: Read lock file written by autopilot Phase 0
  local lock_file="$changes_dir/.autopilot-active"
  if [ -f "$lock_file" ]; then
    local active_name
    active_name=$(parse_lock_file "$lock_file")
    if [ -n "$active_name" ] && [ -d "$changes_dir/$active_name" ]; then
      echo "$changes_dir/$active_name${_append}"
      return 0
    fi
  fi

  # Priority 1: find the change with the most recent checkpoint file
  local latest_file=""
  local find_results
  find_results=$(find "$changes_dir" -path "*/context/phase-results/phase-*.json" -type f 2>/dev/null) || true
  if [ -n "$find_results" ]; then
    latest_file=$(echo "$find_results" | tr '\n' '\0' | xargs -0 ls -t 2>/dev/null | head -1) || true
  fi

  if [ -n "$latest_file" ]; then
    local latest_dir
    latest_dir=$(echo "$latest_file" | sed 's|/context/phase-results/.*||')
    if [ -d "$latest_dir" ]; then
      echo "${latest_dir}${_append}"
      return 0
    fi
  fi

  # Fallback: most recently modified change directory
  local latest=""
  local latest_time=0
  for dir in "$changes_dir"/*/; do
    [ -d "$dir" ] || continue
    [[ "$(basename "$dir")" == _* ]] && continue
    local mtime
    mtime=$(stat -f "%m" "$dir" 2>/dev/null || stat -c "%Y" "$dir" 2>/dev/null || echo 0)
    if [ "$mtime" -gt "$latest_time" ]; then
      latest_time=$mtime
      latest="${dir%/}"
    fi
  done

  if [ -n "$latest" ]; then
    echo "${latest}${_append}"
    return 0
  fi
  return 1
}

# --- Read checkpoint status ---
# Usage: read_checkpoint_status <file_path>
# Returns: status string (ok/warning/blocked/failed/error/unknown)
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

# --- Find latest checkpoint file for a phase ---
# Usage: find_checkpoint <phase_results_dir> <phase_number>
# Returns: path to checkpoint file on stdout, or empty string
find_checkpoint() {
  local dir="$1"
  local phase="$2"
  local results
  results=$(find "$dir" -maxdepth 1 -name "phase-${phase}-*.json" -type f 2>/dev/null) || true
  if [ -n "$results" ]; then
    echo "$results" | tr '\n' '\0' | xargs -0 ls -t 2>/dev/null | head -1
  fi
}
