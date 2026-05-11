#!/usr/bin/env bash
# init-change-dir.sh
# Deterministic change directory initializer — called after Phase 1 determines change_name.
#
# Usage: init-change-dir.sh <project_root> <change_name>
#   project_root: absolute path to project root
#   change_name: kebab-case change name (e.g. "add-user-auth")
#
# Behavior:
#   1. Creates openspec/changes/<name>/context/phase-results/ (mkdir -p)
#   2. Creates openspec/changes/<name>/context/phase-context-snapshots/ (mkdir -p)
#   3. Updates .autopilot-active lock file "change" field from "pending" to actual name
#   4. Idempotent: safe to call multiple times
#
# Exit: 0 on success, 1 on failure

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

PROJECT_ROOT="${1:-}"
CHANGE_NAME="${2:-}"

if [ -z "$PROJECT_ROOT" ] || [ -z "$CHANGE_NAME" ]; then
  echo "[ERROR] Usage: init-change-dir.sh <project_root> <change_name>" >&2
  exit 1
fi

if ! command -v python3 &>/dev/null; then
  echo "[ERROR] python3 required" >&2
  exit 1
fi

CHANGES_DIR="$PROJECT_ROOT/openspec/changes"
CHANGE_DIR="$CHANGES_DIR/$CHANGE_NAME"

# Step 1: Create directory structure
mkdir -p "$CHANGE_DIR/context/phase-results" 2>/dev/null || {
  echo "[ERROR] Failed to create $CHANGE_DIR/context/phase-results/" >&2
  exit 1
}
mkdir -p "$CHANGE_DIR/context/phase-context-snapshots" 2>/dev/null || {
  echo "[ERROR] Failed to create $CHANGE_DIR/context/phase-context-snapshots/" >&2
  exit 1
}

# Step 2: Update lock file "change" field
LOCK_FILE="$CHANGES_DIR/.autopilot-active"
if [ ! -f "$LOCK_FILE" ]; then
  echo "[WARN] Lock file not found at $LOCK_FILE — skipping lock update" >&2
  exit 0
fi

python3 -c "
import json, sys, os

lock_path = sys.argv[1]
change_name = sys.argv[2]

try:
    with open(lock_path) as f:
        data = json.load(f)
except (json.JSONDecodeError, ValueError):
    # Legacy plain-text lock file — overwrite with JSON
    data = {}

# Update change field (supports both 'change' and 'change_name' for compat)
old_change = data.get('change', data.get('change_name', 'pending'))
data['change'] = change_name
# Remove legacy field if present
data.pop('change_name', None)

# Atomic write
tmp_path = lock_path + '.tmp'
with open(tmp_path, 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
os.replace(tmp_path, lock_path)

if old_change == 'pending':
    print(f'[INIT] Lock file updated: change=\"{change_name}\" (was \"pending\")')
else:
    print(f'[INIT] Lock file change field: \"{change_name}\" (was \"{old_change}\")')
" "$LOCK_FILE" "$CHANGE_NAME"

exit $?
