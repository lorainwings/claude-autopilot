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

# --- Unified project root resolution ---
# Priority: $AUTOPILOT_PROJECT_ROOT > git rev-parse > pwd
# Usage: resolve_project_root
# Returns: absolute path on stdout
resolve_project_root() {
  if [ -n "${AUTOPILOT_PROJECT_ROOT:-}" ] && [ -d "$AUTOPILOT_PROJECT_ROOT" ]; then
    echo "$AUTOPILOT_PROJECT_ROOT"
    return 0
  fi
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

# --- Resolve openspec/changes directory ---
# Usage: resolve_changes_dir
# Returns: path on stdout, exit 1 if not found
resolve_changes_dir() {
  local root
  root=$(resolve_project_root)
  local changes="$root/openspec/changes"
  if [ -d "$changes" ]; then
    echo "$changes"
    return 0
  fi
  return 1
}

# --- Resolve active change directory (convenience wrapper) ---
# Usage: resolve_active_change_dir
# Returns: path on stdout, exit 1 if not found
resolve_active_change_dir() {
  local changes_dir
  changes_dir=$(resolve_changes_dir) || return 1
  find_active_change "$changes_dir"
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

# --- Validate checkpoint JSON integrity ---
# Usage: validate_checkpoint_integrity <checkpoint_file>
# Returns: 0 if valid JSON with required "status" field, 1 if corrupted
# Side effect: removes corrupted checkpoint files and any leftover .tmp files
validate_checkpoint_integrity() {
  local file="$1"
  [ -f "$file" ] || return 1

  # Clean up any leftover .tmp files alongside this checkpoint
  local tmp_file="${file%.json}.tmp"
  [ -f "$tmp_file" ] && rm -f "$tmp_file"

  # Validate JSON structure and required "status" field
  python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    if 'status' not in data:
        sys.exit(1)
    sys.exit(0)
except (json.JSONDecodeError, ValueError, OSError):
    sys.exit(1)
" "$file" 2>/dev/null
  local rc=$?
  if [ $rc -ne 0 ]; then
    local backup_dir="$(dirname "$file")/.corrupted-backups"
    mkdir -p "$backup_dir" 2>/dev/null || true
    local ts=$(date +%Y%m%d_%H%M%S 2>/dev/null || echo "unknown")
    if mv "$file" "$backup_dir/$(basename "$file").corrupted.${ts}" 2>/dev/null; then
      echo "WARNING: Corrupted checkpoint backed up: $file → $backup_dir/" >&2
    else
      rm -f "$file"
      echo "WARNING: Corrupted checkpoint removed: $file" >&2
    fi
    return 1
  fi
  return 0
}

# --- Scan all checkpoints by phase order ---
# Usage: scan_all_checkpoints <phase_results_dir> [mode]
# Returns: JSON array on stdout with each phase's checkpoint status
# Example output: [{"phase":1,"file":"phase-1-requirements.json","status":"ok"},...]
scan_all_checkpoints() {
  local dir="$1"
  local mode="${2:-full}"

  # Determine which phases to scan based on mode
  local phases
  case "$mode" in
    lite) phases="1 5 6 7" ;;
    minimal) phases="1 5 7" ;;
    *) phases="1 2 3 4 5 6 7" ;;
  esac

  python3 -c "
import json, sys, os, glob
phase_results_dir = sys.argv[1]
phases = [int(p) for p in sys.argv[2].split()]
results = []
for p in phases:
    pattern = os.path.join(phase_results_dir, f'phase-{p}-*.json')
    files = sorted(glob.glob(pattern), key=lambda f: os.path.getmtime(f), reverse=True)
    # Exclude .tmp files
    files = [f for f in files if not f.endswith('.tmp') and not f.endswith('-progress.json') and not f.endswith('-interim.json')]
    if files:
        try:
            with open(files[0]) as fh:
                data = json.load(fh)
            results.append({
                'phase': p,
                'file': os.path.basename(files[0]),
                'status': data.get('status', 'unknown')
            })
        except (json.JSONDecodeError, OSError):
            results.append({'phase': p, 'file': os.path.basename(files[0]), 'status': 'error'})
    else:
        results.append({'phase': p, 'file': None, 'status': 'missing'})
print(json.dumps(results))
" "$dir" "$phases" 2>/dev/null || echo "[]"
}

# --- Get last valid phase number ---
# Usage: get_last_valid_phase <phase_results_dir> [mode]
# Returns: last phase number with status ok/warning on stdout, or 0 if none found
get_last_valid_phase() {
  local dir="$1"
  local mode="${2:-full}"

  local phases
  case "$mode" in
    lite) phases="1 5 6 7" ;;
    minimal) phases="1 5 7" ;;
    *) phases="1 2 3 4 5 6 7" ;;
  esac

  python3 -c "
import json, sys, os, glob
phase_results_dir = sys.argv[1]
phases = [int(p) for p in sys.argv[2].split()]
last_valid = 0
for p in phases:
    pattern = os.path.join(phase_results_dir, f'phase-{p}-*.json')
    files = sorted(glob.glob(pattern), key=lambda f: os.path.getmtime(f), reverse=True)
    files = [f for f in files if not f.endswith('.tmp') and not f.endswith('-progress.json') and not f.endswith('-interim.json')]
    if files:
        try:
            with open(files[0]) as fh:
                data = json.load(fh)
            if data.get('status') in ('ok', 'warning'):
                last_valid = p
            else:
                break  # failed/blocked/error = gap, stop scanning
        except (json.JSONDecodeError, OSError):
            break  # corrupted = gap, stop scanning
    else:
        if last_valid > 0:
            break  # missing after valid = gap, stop scanning
print(last_valid)
" "$dir" "$phases" 2>/dev/null || echo "0"
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
  [ -f "$lock_file" ] || {
    echo "$default_val"
    return 0
  }

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
    full) echo 8 ;;
    lite) echo 5 ;;
    minimal) echo 4 ;;
    *) echo 8 ;;
  esac
}

# --- Sanitize session identifiers for filesystem-safe marker paths ---
# Usage: sanitize_session_key <session_id>
# Returns: sanitized key on stdout
sanitize_session_key() {
  local raw="${1:-unknown}"
  local sanitized
  sanitized=$(printf "%s" "$raw" | tr -c '[:alnum:]._-' '_' | sed 's/^_//; s/_$//')
  [ -n "$sanitized" ] && echo "$sanitized" || echo "unknown"
}

# --- Get session-scoped active agent marker path ---
# Usage: get_session_agent_marker_file <project_root> <session_id>
# Returns: marker file path on stdout
get_session_agent_marker_file() {
  local project_root="$1"
  local session_id="${2:-unknown}"
  local session_key
  session_key=$(sanitize_session_key "$session_id")
  echo "$project_root/logs/.active-agent-session-${session_key}"
}

# --- Auto-increment event sequence counter ---
# Usage: next_event_sequence <project_root>
# Returns: next sequence number on stdout (1-based)
# Thread-safe via mkdir atomic lock with bounded retry
next_event_sequence() {
  local project_root="$1"
  local seq_file="$project_root/logs/.event_sequence"
  local lock_dir="$project_root/logs/.event_sequence.lk"
  local max_attempts="${AUTOPILOT_EVENT_SEQ_RETRIES:-200}"
  local attempt=0
  local acquired=0
  mkdir -p "$(dirname "$seq_file")" 2>/dev/null || true

  while [ "$attempt" -lt "$max_attempts" ]; do
    if mkdir "$lock_dir" 2>/dev/null; then
      acquired=1
      break
    fi
    # Stale lock detection: if lock dir older than 30s, force remove
    if [ "$attempt" -eq 10 ] && [ -d "$lock_dir" ]; then
      local lock_age=0
      if [[ "$(uname)" == "Darwin" ]]; then
        lock_age=$(($(date +%s) - $(stat -f "%m" "$lock_dir" 2>/dev/null || echo "$(date +%s)")))
      else
        lock_age=$(($(date +%s) - $(stat -c "%Y" "$lock_dir" 2>/dev/null || echo "$(date +%s)")))
      fi
      if [ "$lock_age" -gt 30 ]; then
        rmdir "$lock_dir" 2>/dev/null || rm -rf "$lock_dir" 2>/dev/null || true
      fi
    fi
    attempt=$((attempt + 1))
    sleep 0.005
  done

  if [ "$acquired" -eq 1 ]; then
    local current=0
    [ -f "$seq_file" ] && current=$(cat "$seq_file" 2>/dev/null | tr -d '[:space:]') || true
    [ -z "$current" ] && current=0
    local next=$((current + 1))
    printf "%s\n" "$next" >"$seq_file"
    printf "%s\n" "$next"
    rmdir "$lock_dir" 2>/dev/null || true
    return 0
  fi

  local ts_ms
  ts_ms=$(python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null || date +%s000)
  echo "${ts_ms}$$"
}

# --- Get gap phases (missing/failed between valid checkpoints) ---
# Usage: get_gap_phases <phase_results_dir> [mode]
# Returns: JSON array of gap phase numbers on stdout, e.g. [3, 4]
# A gap is a phase that is missing/failed/error after the first valid phase
get_gap_phases() {
  local dir="$1"
  local mode="${2:-full}"

  local phases
  case "$mode" in
    lite) phases="1 5 6 7" ;;
    minimal) phases="1 5 7" ;;
    *) phases="1 2 3 4 5 6 7" ;;
  esac

  python3 -c "
import json, sys, os, glob
phase_results_dir = sys.argv[1]
phases = [int(p) for p in sys.argv[2].split()]
gaps = []
first_valid_seen = False
for p in phases:
    pattern = os.path.join(phase_results_dir, f'phase-{p}-*.json')
    files = sorted(glob.glob(pattern), key=lambda f: os.path.getmtime(f), reverse=True)
    files = [f for f in files if not f.endswith('.tmp') and not f.endswith('-progress.json') and not f.endswith('-interim.json')]
    if files:
        try:
            with open(files[0]) as fh:
                data = json.load(fh)
            if data.get('status') in ('ok', 'warning'):
                first_valid_seen = True
            elif first_valid_seen:
                gaps.append(p)
        except (json.JSONDecodeError, OSError):
            if first_valid_seen:
                gaps.append(p)
    else:
        if first_valid_seen:
            gaps.append(p)
print(json.dumps(gaps))
" "$dir" "$phases" 2>/dev/null || echo "[]"
}

# --- Get phase sequence for a given mode ---
# Usage: get_phase_sequence <mode>
# Returns: space-separated phase numbers (e.g. "1 2 3 4 5 6 7")
get_phase_sequence() {
  case "${1:-full}" in
    lite) echo "1 5 6 7" ;;
    minimal) echo "1 5 7" ;;
    *) echo "1 2 3 4 5 6 7" ;;
  esac
}

# --- Get next phase in sequence ---
# Usage: get_next_phase_in_sequence <current_phase> <mode>
# Returns: next phase number, or "done" if current is the last phase
get_next_phase_in_sequence() {
  local current="$1"
  local mode="${2:-full}"
  local seq
  seq=$(get_phase_sequence "$mode")

  local found=false
  for p in $seq; do
    if [ "$found" = "true" ]; then
      echo "$p"
      return 0
    fi
    [ "$p" = "$current" ] && found=true
  done
  echo "done"
}

# --- Read phase commit SHA from git history ---
# Usage: read_phase_commit_sha <project_root> <phase> <change_name>
# Returns: commit SHA on stdout, or empty string if not found
# Uses git log --grep to find the checkpoint commit (backward compatible)
read_phase_commit_sha() {
  local project_root="$1"
  local phase="$2"
  local change_name="$3"

  local sha
  # Tier 1: exact autopilot commit format (current branch)
  sha=$(git -C "$project_root" log --grep="^autopilot:.*Phase ${phase}\b" --grep="${change_name}" --all-match --format="%H" -1 2>/dev/null) || true
  # Tier 2: fixup commit with change_name (current branch)
  if [ -z "$sha" ]; then
    sha=$(git -C "$project_root" log --grep="^fixup!.*${change_name}.*Phase ${phase}\b" --format="%H" -1 2>/dev/null) || true
  fi
  # Tier 3: broad --all (backward compatible with old commits)
  if [ -z "$sha" ]; then
    sha=$(git -C "$project_root" log --all --grep="Phase ${phase}" --grep="autopilot.*${change_name}" --all-match --format="%H" -1 2>/dev/null) || true
  fi
  echo "$sha"
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
# Fallback: AUTOPILOT_PHASE_ID env var (for env-var-based phase detection)
has_phase_marker() {
  local pattern="${1:-[0-9]}"
  echo "$STDIN_DATA" | grep -q '"prompt"[[:space:]]*:[[:space:]]*"<!-- autopilot-phase:'"$pattern" && return 0
  # Fallback: AUTOPILOT_PHASE_ID env var
  if [ -n "${AUTOPILOT_PHASE_ID:-}" ]; then
    echo "${AUTOPILOT_PHASE_ID}" | grep -qE "^${pattern}" && return 0
  fi
  return 1
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
