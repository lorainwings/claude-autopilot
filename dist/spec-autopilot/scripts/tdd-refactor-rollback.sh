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

# --- Step 2: Stash → Checkout → Pop ---
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$PROJECT_ROOT" ]; then
  echo '{"status":"error","reason":"Not inside a git repository."}'
  exit 1
fi

# Stash any uncommitted changes
STASH_OUTPUT=$(git -C "$PROJECT_ROOT" stash push -m "tdd-refactor-rollback-temp" 2>&1)
STASH_CREATED=false
if echo "$STASH_OUTPUT" | grep -q "Saved working directory"; then
  STASH_CREATED=true
fi

# Rollback working tree
if ! git -C "$PROJECT_ROOT" checkout -- . 2>&1; then
  # Restore stash if checkout failed
  if [ "$STASH_CREATED" = "true" ]; then
    git -C "$PROJECT_ROOT" stash pop 2>/dev/null || true
  fi
  echo '{"status":"error","reason":"git checkout -- . failed. Working tree may be in a conflicted state."}'
  exit 1
fi

# Pop stash if we created one
if [ "$STASH_CREATED" = "true" ]; then
  if ! git -C "$PROJECT_ROOT" stash pop 2>&1; then
    echo '{"status":"warning","reason":"Rollback succeeded but stash pop failed. Manual resolution may be needed. Stash ref: tdd-refactor-rollback-temp"}'
    exit 0
  fi
fi

echo '{"status":"ok","reason":"REFACTOR rollback completed successfully."}'
exit 0
