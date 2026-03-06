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

# --- Constraint loading cache ---
# File: /tmp/autopilot-constraints-${PROJECT_ROOT_HASH}.json
# Persists for the duration of the autopilot session.

# Load code constraints from config or CLAUDE.md, with file-based caching
# Usage: load_constraints <project_root>
# Output: JSON on stdout with keys: forbidden_files, forbidden_patterns, allowed_dirs, max_lines, found
# Cache: results cached in /tmp/autopilot-constraints-<hash>.json for 10 minutes
load_constraints() {
  local root="$1"
  [ -z "$root" ] && return 1

  # Cache key from project root path
  local cache_key
  cache_key=$(echo "$root" | md5sum 2>/dev/null | cut -d' ' -f1 || echo "$root" | md5 2>/dev/null | cut -d' ' -f1 || echo "nocache")
  local cache_file="/tmp/autopilot-constraints-${cache_key}.json"

  # Check cache freshness (10 min TTL)
  if [ -f "$cache_file" ]; then
    local cache_age=0
    local now_epoch
    now_epoch=$(date +%s)
    local cache_mtime
    if [[ "$(uname)" == "Darwin" ]]; then
      cache_mtime=$(stat -f "%m" "$cache_file" 2>/dev/null || echo 0)
    else
      cache_mtime=$(stat -c "%Y" "$cache_file" 2>/dev/null || echo 0)
    fi
    cache_age=$((now_epoch - cache_mtime))
    if [ "$cache_age" -lt 600 ]; then
      cat "$cache_file"
      return 0
    fi
  fi

  # Generate constraints via python3
  command -v python3 &>/dev/null || { echo '{"found":false}'; return 0; }

  local result
  result=$(python3 -c "
import json, os, re, sys

root = sys.argv[1]
forbidden_files, forbidden_patterns, allowed_dirs = [], [], []
max_lines = 800
found = False

# Priority 1: config.yaml code_constraints
cfg = os.path.join(root, '.claude', 'autopilot.config.yaml')
if os.path.isfile(cfg):
    try:
        with open(cfg) as f:
            txt = f.read()
        cc = re.search(r'^code_constraints:\s*$', txt, re.MULTILINE)
        if cc:
            sec = txt[cc.end():]
            nt = re.search(r'^\S', sec, re.MULTILINE)
            sec = sec[:nt.start()] if nt else sec
            def parse_list(key):
                m = re.search(rf'^( +){key}:\s*\n', sec, re.MULTILINE)
                if not m:
                    return []
                indent = m.group(1)
                start = m.end()
                end_m = re.search(rf'^{re.escape(indent)}[a-z_]', sec[start:], re.MULTILINE)
                block = sec[start:start + end_m.start()] if end_m else sec[start:]
                items = []
                for obj_m in re.finditer(r'-\s+pattern:\s*[\"\x27]?([^\"\x27}\n]+)[\"\x27]?', block):
                    v = obj_m.group(1).strip()
                    if v:
                        items.append(v)
                if not items:
                    for x in re.finditer(r'-\s+(.+)', block):
                        v = x.group(1).strip().strip('\x22\x27')
                        if v and not v.startswith('pattern:') and not v.startswith('message:'):
                            items.append(v)
                return items
            forbidden_files = parse_list('forbidden_files')
            forbidden_patterns = parse_list('forbidden_patterns')
            allowed_dirs = parse_list('allowed_dirs')
            ml = re.search(r'max_file_lines:\s*(\d+)', sec)
            if ml:
                max_lines = int(ml.group(1))
            found = True
    except Exception as e:
        print(f'WARNING: load_constraints config: {e}', file=sys.stderr)

# Priority 2: CLAUDE.md fallback
if not found:
    cmd = os.path.join(root, 'CLAUDE.md')
    if os.path.isfile(cmd):
        try:
            with open(cmd) as f:
                md = f.read()
            for m in re.finditer(r'[\x60|]([a-zA-Z0-9_.-]+\.[a-zA-Z]{1,5})[\x60|]\s*.*禁', md):
                forbidden_files.append(m.group(1))
            for m in re.finditer(r'禁[^|]*[\x60|]([a-zA-Z0-9_.-]+\.[a-zA-Z]{1,5})[\x60|]', md):
                forbidden_files.append(m.group(1))
            for m in re.finditer(r'[\x60|]([a-zA-Z][a-zA-Z0-9_() ]{2,30})[\x60|]\s*.*(?:禁止|禁)', md):
                p = m.group(1).strip()
                if len(p) > 2:
                    forbidden_patterns.append(p)
            found = bool(forbidden_files or forbidden_patterns)
        except Exception:
            pass

# Priority 3: .claude/rules/ extraction (NEW - enhanced constraint detection)
if not found or True:  # Always try to supplement from rules
    rules_dir = os.path.join(root, '.claude', 'rules')
    if os.path.isdir(rules_dir):
        import glob as g
        for md_path in sorted(g.glob(os.path.join(rules_dir, '*.md'))):
            try:
                with open(md_path, 'r', errors='ignore') as f:
                    content = f.read(50_000)
                # Extract forbidden patterns from table rows
                for m in re.finditer(r'\|\s*\x60([^\x60]+)\x60\s*\|\s*\x60([^\x60]+)\x60\s*\|', content):
                    left, right = m.group(1).strip(), m.group(2).strip()
                    line_start = content.rfind('\n', 0, m.start()) + 1
                    line = content[line_start:m.end()]
                    if re.search(r'禁止|禁|替代|forbidden|replace', line, re.IGNORECASE):
                        if '.' in left and len(left) < 30:
                            forbidden_files.append(left)
                        elif len(left) > 2:
                            forbidden_patterns.append(left)
                        found = True
                # Extract from explicit forbidden markers
                for m in re.finditer(r'(?:禁止|❌|禁)\s*(?:使用\s*)?[\x60]([^\x60]+)[\x60]', content):
                    pat = m.group(1).strip()
                    if len(pat) > 1:
                        if '.' in pat and len(pat) < 30:
                            forbidden_files.append(pat)
                        else:
                            forbidden_patterns.append(pat)
                        found = True
            except Exception:
                continue

# Deduplicate
forbidden_files = list(dict.fromkeys(forbidden_files))
forbidden_patterns = list(dict.fromkeys(forbidden_patterns))

print(json.dumps({
    'found': found or bool(forbidden_files or forbidden_patterns),
    'forbidden_files': forbidden_files,
    'forbidden_patterns': forbidden_patterns,
    'allowed_dirs': allowed_dirs,
    'max_lines': max_lines,
}))
" "$root" 2>/dev/null) || result='{"found":false}'

  # Write cache
  echo "$result" > "$cache_file" 2>/dev/null || true
  echo "$result"
}

# Check a single file against loaded constraints
# Usage: echo '<constraints_json>' | check_file_constraints <file_path> <project_root>
# Output: JSON array of violations on stdout (empty array = no violations)
check_file_constraints() {
  local file_path="$1"
  local root="$2"

  command -v python3 &>/dev/null || { echo '[]'; return 0; }

  python3 -c "
import json, os, re, sys

file_path = sys.argv[1]
root = sys.argv[2]

try:
    constraints = json.load(sys.stdin)
except (json.JSONDecodeError, ValueError):
    print('[]')
    sys.exit(0)

if not constraints.get('found'):
    print('[]')
    sys.exit(0)

forbidden_files = constraints.get('forbidden_files', [])
forbidden_patterns = constraints.get('forbidden_patterns', [])
allowed_dirs = constraints.get('allowed_dirs', [])
max_lines = constraints.get('max_lines', 800)

rel = os.path.relpath(file_path, root) if os.path.isabs(file_path) else file_path
base = os.path.basename(rel)

violations = []

# Forbidden file name
for ff in forbidden_files:
    if base == ff or rel.endswith(ff):
        violations.append(f'Forbidden file: {rel} (matches \"{ff}\")')

# Directory scope
if allowed_dirs and not any(rel.startswith(d) for d in allowed_dirs):
    violations.append(f'Out of scope: {rel} (allowed: {allowed_dirs})')

# File line count + forbidden patterns
fp = os.path.join(root, rel) if not os.path.isabs(file_path) else file_path
if os.path.isfile(fp):
    try:
        with open(fp, 'r', errors='ignore') as f:
            content = f.read(100_000)
        lc = content.count('\n') + (1 if content and not content.endswith('\n') else 0)
        if lc > max_lines:
            violations.append(f'File too long: {rel} ({lc} lines > {max_lines})')
        for pat in forbidden_patterns:
            if re.search(re.escape(pat), content):
                violations.append(f'Forbidden pattern \"{pat}\" in {rel}')
    except Exception:
        pass

print(json.dumps(violations))
" "$file_path" "$root"
}

# Extract project root from stdin JSON or git
# Usage: extract_project_root <stdin_data>
# Output: project root path on stdout
extract_project_root() {
  local stdin_data="$1"
  local root=""

  # Try extracting from JSON cwd field (fast bash regex)
  root=$(echo "$stdin_data" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

  if [ -z "$root" ]; then
    root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi

  echo "$root"
}

# Standard Hook bypass checks (lock file + phase marker)
# Usage: should_bypass_hook <stdin_data> <project_root> <phase_pattern>
# Returns: 0 if should bypass (exit 0), 1 if should continue checking
# phase_pattern: regex like "5" or "[456]" or "[0-9]"
should_bypass_hook() {
  local stdin_data="$1"
  local project_root="$2"
  local phase_pattern="$3"

  # Bypass if no active autopilot
  has_active_autopilot "$project_root" || return 0

  # Bypass if no matching phase marker in prompt
  echo "$stdin_data" | grep -q "\"prompt\"[[:space:]]*:[[:space:]]*\"<!-- autopilot-phase:${phase_pattern}" || return 0

  return 1
}
