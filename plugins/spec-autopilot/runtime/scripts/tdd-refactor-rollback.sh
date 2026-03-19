#!/usr/bin/env bash
# tdd-refactor-rollback.sh
# Deterministic 3-step rollback for TDD REFACTOR stage.
#
# Steps:
#   1. Validate current TDD stage is REFACTOR (via .tdd-stage file)
#   2. git stash push (save unrelated changes) → git checkout -- . (rollback) → git stash pop (restore)
#   3. Edge cases: skip pop when stash is empty; output JSON error on checkout failure
#
# Usage: bash tdd-refactor-rollback.sh <change_dir>
# Output: JSON on stdout

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

# --- Validate arguments ---
if [ $# -lt 1 ]; then
  echo '{"status":"error","reason":"Usage: tdd-refactor-rollback.sh <change_dir>"}'
  exit 1
fi

CHANGE_DIR="$1"
TDD_STAGE_FILE="$CHANGE_DIR/context/.tdd-stage"

# --- Step 1: Validate REFACTOR stage ---
if [ ! -f "$TDD_STAGE_FILE" ]; then
  echo '{"status":"error","reason":"No .tdd-stage file found. TDD mode may not be active."}'
  exit 1
fi

CURRENT_STAGE=$(cat "$TDD_STAGE_FILE" 2>/dev/null | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
if [ "$CURRENT_STAGE" != "refactor" ]; then
  echo "{\"status\":\"error\",\"reason\":\"Current TDD stage is '${CURRENT_STAGE}', not REFACTOR. Rollback only allowed during REFACTOR stage.\"}"
  exit 1
fi

# --- Step 2: File-level rollback using .tdd-refactor-files ---
REFACTOR_FILES="$CHANGE_DIR/context/.tdd-refactor-files"

if [ ! -f "$REFACTOR_FILES" ] || [ ! -s "$REFACTOR_FILES" ]; then
  echo '{"status":"ok","reason":"No refactor files recorded. Nothing to rollback."}'
  exit 0
fi

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$PROJECT_ROOT" ]; then
  echo '{"status":"error","reason":"Not inside a git repository."}'
  exit 1
fi

# Deduplicate file list
FILE_LIST=$(sort -u "$REFACTOR_FILES")
ROLLED_BACK=0
ERRORS=""

while IFS= read -r file; do
  [ -z "$file" ] && continue
  # Check if the file is tracked by git
  if git -C "$PROJECT_ROOT" ls-files --error-unmatch "$file" >/dev/null 2>&1; then
    # Tracked file → restore from HEAD
    if git -C "$PROJECT_ROOT" checkout -- "$file" 2>/dev/null; then
      ROLLED_BACK=$((ROLLED_BACK + 1))
    else
      ERRORS="${ERRORS}Failed to checkout: ${file}; "
    fi
  else
    # Untracked new file → remove
    if [ -f "$file" ]; then
      rm "$file" 2>/dev/null && ROLLED_BACK=$((ROLLED_BACK + 1)) || ERRORS="${ERRORS}Failed to remove: ${file}; "
    fi
  fi
done <<<"$FILE_LIST"

# Clean up the refactor files list
rm -f "$REFACTOR_FILES"

if [ -n "$ERRORS" ]; then
  ERRORS_ESCAPED=$(echo "$ERRORS" | sed 's/"/\\"/g')
  echo "{\"status\":\"warning\",\"reason\":\"Rolled back ${ROLLED_BACK} file(s) with errors: ${ERRORS_ESCAPED}\"}"
  exit 0
fi

echo "{\"status\":\"ok\",\"reason\":\"REFACTOR rollback completed. ${ROLLED_BACK} file(s) restored.\"}"
exit 0
