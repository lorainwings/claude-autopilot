#!/usr/bin/env bash
# rebuild-anchor.sh — Deterministic anchor commit rebuild
#
# Usage: rebuild-anchor.sh <project_root> <lock_file>
# Creates a new anchor commit and atomically updates the lock file's anchor_sha field.
# Exit: 0 = success, 1 = failure (fail-closed: archive MUST NOT proceed on failure)
# Stdout: new anchor SHA on success
#
# v6.0: Failure is a hard block for archive. No skip/degrade option.

set -uo pipefail

PROJECT_ROOT="${1:-}"
LOCK_FILE="${2:-}"

if [ -z "$PROJECT_ROOT" ] || [ -z "$LOCK_FILE" ]; then
  echo "ERROR: Usage: rebuild-anchor.sh <project_root> <lock_file>" >&2
  exit 1
fi

if [ ! -d "$PROJECT_ROOT/.git" ]; then
  echo "ERROR: Not a git repository: $PROJECT_ROOT. Anchor rebuild requires git." >&2
  exit 1
fi

if [ ! -f "$LOCK_FILE" ]; then
  echo "ERROR: Lock file not found: $LOCK_FILE. Cannot rebuild anchor without active session." >&2
  exit 1
fi

# Verify working tree is clean before creating anchor
DIRTY=$(git -C "$PROJECT_ROOT" status --porcelain 2>/dev/null || echo "")
if [ -n "$DIRTY" ]; then
  echo "ERROR: Working tree has uncommitted changes. Commit or stash before anchor rebuild." >&2
  echo "Dirty files:" >&2
  echo "$DIRTY" >&2
  exit 1
fi

# Create new empty anchor commit
NEW_SHA=$(git -C "$PROJECT_ROOT" commit --allow-empty -m 'autopilot: anchor (recovery)' 2>&1) || {
  echo "ERROR: Failed to create anchor commit: $NEW_SHA" >&2
  exit 1
}

# Get the new commit SHA
NEW_SHA=$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null) || {
  echo "ERROR: Failed to get new commit SHA" >&2
  exit 1
}

FULL_SHA=$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null) || {
  echo "ERROR: Failed to get full commit SHA" >&2
  exit 1
}

# Atomically update lock file anchor_sha field
python3 -c "
import json, sys, os, tempfile

lock_path = sys.argv[1]
new_sha = sys.argv[2]

try:
    with open(lock_path, 'r') as f:
        data = json.load(f)
except Exception as e:
    print(f'ERROR: Failed to read lock file: {e}', file=sys.stderr)
    sys.exit(1)

data['anchor_sha'] = new_sha

# Atomic write: write to temp file, then rename
dir_name = os.path.dirname(lock_path)
try:
    fd, tmp_path = tempfile.mkstemp(dir=dir_name, suffix='.tmp')
    with os.fdopen(fd, 'w') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write('\n')
    os.replace(tmp_path, lock_path)
except Exception as e:
    print(f'ERROR: Failed to update lock file: {e}', file=sys.stderr)
    # Clean up temp file if it exists
    try:
        os.unlink(tmp_path)
    except Exception:
        pass
    sys.exit(1)
" "$LOCK_FILE" "$FULL_SHA" || exit 1

echo "$FULL_SHA"
exit 0
