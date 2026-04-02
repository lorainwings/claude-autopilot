#!/usr/bin/env bash
# setup-hooks.sh
# Activates the tracked .githooks/ directory as the Git hooks source.
# Run once after cloning, or re-run to verify the setup.
#
# Usage:
#   bash scripts/setup-hooks.sh
#
# What it does:
#   1. Sets core.hooksPath to .githooks/ (local config only)
#   2. Verifies .githooks/pre-commit and .githooks/pre-push exist and are executable
#   3. Warns if stale .git/hooks/pre-commit exists

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$REPO_ROOT" ]; then
  echo "Error: not inside a git repository." >&2
  exit 1
fi

cd "$REPO_ROOT"

HOOKS_DIR=".githooks"
HOOK_FILES=("$HOOKS_DIR/pre-commit" "$HOOKS_DIR/pre-push")

# --- Verify tracked hooks exist ---
for HOOK_FILE in "${HOOK_FILES[@]}"; do
  if [ ! -f "$HOOK_FILE" ]; then
    echo "Error: $HOOK_FILE not found. Ensure the repo is fully checked out." >&2
    exit 1
  fi

  # --- Ensure executable ---
  if [ ! -x "$HOOK_FILE" ]; then
    chmod +x "$HOOK_FILE"
    echo "Fixed: set executable bit on $HOOK_FILE"
  fi
done

# --- Set core.hooksPath ---
CURRENT=$(git config --local core.hooksPath 2>/dev/null || true)
if [ "$CURRENT" = "$HOOKS_DIR" ]; then
  echo "Git hooks already configured: core.hooksPath = $HOOKS_DIR"
else
  git config --local core.hooksPath "$HOOKS_DIR"
  echo "Configured: core.hooksPath = $HOOKS_DIR"
fi

# --- Warn about stale .git/hooks/pre-commit ---
if [ -f ".git/hooks/pre-commit" ] && [ ! -L ".git/hooks/pre-commit" ]; then
  echo ""
  echo "Warning: stale .git/hooks/pre-commit detected."
  echo "  Git will now use .githooks/pre-commit instead (via core.hooksPath)."
  echo "  The stale file is harmless but can be removed:"
  echo "    rm .git/hooks/pre-commit"
fi

echo ""
echo "Done. Git hooks are now sourced from .githooks/"
