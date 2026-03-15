#!/usr/bin/env bash
# _common.sh
# Shared utility functions for autopilot hook scripts.
# Source this file at the top of each hook script:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/_common.sh"

# --- Check if autopilot session is active (lock file exists) ---
# Usage: has_active_autopilot [project_root]
# Returns: exit 0 if active, exit 1 if not
# Performance: Pure bash, no python3 fork (~1ms)
has_active_autopilot() {
  local project_root="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  local changes_dir="$project_root/openspec/changes"
  [ -d "$changes_dir" ] || return 1
  # 检查根目录锁文件
  [ -f "$changes_dir/.autopilot-active" ] && return 0
  # 检查子目录锁文件（兼容旧版）
  local found
  found=$(find "$changes_dir" -maxdepth 2 -name '.autopilot-active' -print -quit 2>/dev/null)
  [ -n "$found" ] && return 0
  return 1
}

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
    # macOS: stat -f "%m", Linux: stat -c "%Y"
    # Cannot use || fallback because Linux stat -f succeeds with wrong output
    if [[ "$(uname)" == "Darwin" ]]; then
      mtime=$(stat -f "%m" "$dir" 2>/dev/null || echo 0)
    else
      mtime=$(stat -c "%Y" "$dir" 2>/dev/null || echo 0)
    fi
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

# --- Read config value from autopilot.config.yaml ---
# Usage: read_config_value <project_root> <dotted.key.path> [default]
# Returns: config value on stdout, or default if not found
# Strategy: PyYAML priority → regex fallback → default
# NOTE: Only for scalar values (string/number/boolean). For nested objects/lists,
#       use _envelope_parser.py's read_config_value() via importlib in Python context.
read_config_value() {
  local project_root="$1"
  local key_path="$2"
  local default_val="${3:-}"
  local config_file="$project_root/.claude/autopilot.config.yaml"

  if [ ! -f "$config_file" ]; then
    echo "$default_val"
    return 0
  fi

  local result
  result=$(python3 -c "
import sys, os

config_path = sys.argv[1]
key_path = sys.argv[2]
default = sys.argv[3] if len(sys.argv) > 3 else ''

# Strategy 1: PyYAML
try:
    import yaml
    with open(config_path) as f:
        data = yaml.safe_load(f) or {}
    parts = key_path.split('.')
    current = data
    for part in parts:
        if isinstance(current, dict) and part in current:
            current = current[part]
        else:
            print(default)
            sys.exit(0)
    print(current if current is not None else default)
    sys.exit(0)
except ImportError:
    pass
except Exception:
    print(default)
    sys.exit(0)

# Strategy 2: Regex fallback
import re
try:
    with open(config_path) as f:
        content = f.read()
    parts = key_path.split('.')
    # Walk nested YAML structure using indentation
    search_text = content
    for i, part in enumerate(parts):
        if i < len(parts) - 1:
            # Find section header and extract its block
            pattern = rf'^(\s*){re.escape(part)}:\s*$'
            m = re.search(pattern, search_text, re.MULTILINE)
            if not m:
                print(default)
                sys.exit(0)
            indent = m.group(1)
            block_start = m.end()
            # Find next key at same or lower indentation
            next_key = re.search(rf'^{re.escape(indent)}[a-zA-Z_]', search_text[block_start:], re.MULTILINE)
            search_text = search_text[block_start:block_start + next_key.start()] if next_key else search_text[block_start:]
        else:
            # Find leaf value
            pattern = rf'^\s*{re.escape(part)}:\s*(.+?)\s*$'
            m = re.search(pattern, search_text, re.MULTILINE)
            if m:
                val = m.group(1).strip().strip('\"').strip(\"'\")
                print(val)
                sys.exit(0)
            print(default)
            sys.exit(0)
    print(default)
except Exception:
    print(default)
" "$config_file" "$key_path" "$default_val" 2>/dev/null) || result="$default_val"

  echo "$result"
}

# --- Read a specific field from the lock file JSON ---
# Usage: read_lock_json_field <lock_file_path> <field_name> [default]
# Returns: field value on stdout, or default if not found
read_lock_json_field() {
  local lock_file="$1"
  local field="$2"
  local default_val="${3:-}"
  [ -f "$lock_file" ] || { echo "$default_val"; return 0; }

  local result
  result=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    print(data.get(sys.argv[2], ''))
except Exception:
    pass
" "$lock_file" "$field" 2>/dev/null) || true
  [ -n "$result" ] && echo "$result" || echo "$default_val"
}

# --- Get human-readable phase label ---
# Usage: get_phase_label <phase_number>
# Returns: label string on stdout
get_phase_label() {
  case "${1:-}" in
    0) echo "Environment Setup" ;;
    1) echo "Requirements" ;;
    2) echo "OpenSpec" ;;
    3) echo "Fast-Forward" ;;
    4) echo "Test Design" ;;
    5) echo "Implementation" ;;
    6) echo "Test Report" ;;
    7) echo "Archive" ;;
    *) echo "Unknown" ;;
  esac
}

# --- Get total phases count for a given mode ---
# Usage: get_total_phases <mode>
# Returns: phase count on stdout (full=8, lite=5, minimal=4)
get_total_phases() {
  case "${1:-full}" in
    full)    echo 8 ;;
    lite)    echo 5 ;;
    minimal) echo 4 ;;
    *)       echo 8 ;;
  esac
}

# --- Auto-increment event sequence counter ---
# Usage: next_event_sequence <project_root>
# Returns: next sequence number on stdout (1-based)
# Thread-safe via mkdir atomic lock (works on both Linux and macOS)
next_event_sequence() {
  local project_root="$1"
  local seq_file="$project_root/logs/.event_sequence"
  local lock_dir="$project_root/logs/.event_sequence.lk"
  mkdir -p "$(dirname "$seq_file")" 2>/dev/null || true

  # mkdir is atomic on all POSIX systems — use as a spinlock
  local attempts=0
  while ! mkdir "$lock_dir" 2>/dev/null; do
    attempts=$((attempts + 1))
    if [ $attempts -ge 50 ]; then
      # 5s timeout (50 × 0.1s) — fallback to timestamp-based sequence
      echo "WARNING: lock timeout after 5s, using fallback sequence" >&2
      local ns; ns=$(date +%N 2>/dev/null)
      case "$ns" in *[!0-9]*|'') ns=$RANDOM ;; esac
      echo "$(date +%s)${ns}"
      return 0
    fi
    sleep 0.1
  done

  local current=0
  [ -f "$seq_file" ] && current=$(cat "$seq_file" 2>/dev/null | tr -d '[:space:]') || true
  [ -z "$current" ] && current=0
  local next=$((current + 1))
  echo "$next" > "$seq_file"
  echo "$next"

  # Release lock
  rmdir "$lock_dir" 2>/dev/null
}

# --- Check if current Task is a background agent ---
# Usage: is_background_agent
# Reads from global $STDIN_DATA. Returns 0 if run_in_background=true, 1 otherwise.
is_background_agent() {
  echo "$STDIN_DATA" | grep -q '"run_in_background"[[:space:]]*:[[:space:]]*true'
}

# --- Check if Task prompt contains autopilot phase marker ---
# Usage: has_phase_marker [phase_pattern]
# Args:
#   phase_pattern: optional regex digit pattern (default: [0-9])
# Reads from global $STDIN_DATA. Returns 0 if marker found, 1 otherwise.
has_phase_marker() {
  local pattern="${1:-[0-9]}"
  echo "$STDIN_DATA" | grep -q '"prompt"[[:space:]]*:[[:space:]]*"<!-- autopilot-phase:'"$pattern"
}

# --- Require python3 for hook execution ---
# Usage: require_python3 [hook_type]
# Args:
#   hook_type: "block" (PostToolUse, outputs block JSON) or "deny" (PreToolUse, outputs deny JSON)
# If python3 is missing, outputs appropriate JSON and returns 1.
# Returns 0 if python3 is available.
require_python3() {
  local hook_type="${1:-block}"
  if command -v python3 &>/dev/null; then
    return 0
  fi
  if [ "$hook_type" = "deny" ]; then
    cat <<'DENY_JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "python3 is required for autopilot gate hooks but not found in PATH"
  }
}
DENY_JSON
  else
    cat <<'BLOCK_JSON'
{
  "decision": "block",
  "reason": "python3 is required for autopilot hook validation but not found in PATH. Install python3 to continue."
}
BLOCK_JSON
  fi
  return 1
}
