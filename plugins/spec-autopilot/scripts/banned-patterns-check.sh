#!/usr/bin/env bash
# banned-patterns-check.sh
# Hook: PostToolUse(Write|Edit) — 拦截 TODO/FIXME/HACK 占位符 (TD-2)
# Purpose: Scan written/edited file content for banned placeholder patterns.
#          Blocks if TODO:, FIXME:, HACK: (case-insensitive) are found.
# Performance: Pure grep, no python3 fork (~2ms)
# Output: PostToolUse decision: "block" on violation.

# --- Common preamble: stdin read, SCRIPT_DIR, _common.sh, Layer 0 bypass ---
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_hook_preamble.sh"

# --- Fast bypass: only during active phases (Phase 4/5/6) ---
CHANGES_DIR="$PROJECT_ROOT_QUICK/openspec/changes"
LOCK_FILE="$CHANGES_DIR/.autopilot-active"
[ -f "$LOCK_FILE" ] || exit 0

CHANGE_NAME=$(parse_lock_file "$LOCK_FILE")
[ -z "$CHANGE_NAME" ] && exit 0
PHASE_RESULTS="$CHANGES_DIR/$CHANGE_NAME/context/phase-results"
[ -d "$PHASE_RESULTS" ] || exit 0

# Determine current phase: only check during Phase 4/5/6 (code/test generation)
PHASE1_CP=$(find_checkpoint "$PHASE_RESULTS" 1)
[ -z "$PHASE1_CP" ] && exit 0
PHASE1_STATUS=$(read_checkpoint_status "$PHASE1_CP")
[ "$PHASE1_STATUS" != "ok" ] && [ "$PHASE1_STATUS" != "warning" ] && exit 0

# --- Extract file_path from stdin (pure bash, ~1ms) ---
FILE_PATH=$(echo "$STDIN_DATA" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
[ -z "$FILE_PATH" ] && exit 0

# --- Skip non-source files (docs, configs, test fixtures, etc.) ---
case "$FILE_PATH" in
  *.md|*.txt|*.json|*.yaml|*.yml|*.toml|*.ini|*.cfg|*.conf|*.lock|*.log)
    exit 0 ;;
  */CHANGELOG*|*/changelog*|*/LICENSE*|*/README*)
    exit 0 ;;
  *openspec/*|*context/*|*phase-results/*)
    exit 0 ;;
esac

# --- Check file exists ---
[ -f "$FILE_PATH" ] || exit 0

# --- Scan for banned patterns (case-insensitive) ---
# Patterns: TODO:, FIXME:, HACK: (with colon to reduce false positives)
MATCHES=$(grep -inE '(TODO:|FIXME:|HACK:)' "$FILE_PATH" 2>/dev/null | head -5)

if [ -n "$MATCHES" ]; then
  # Count total matches
  MATCH_COUNT=$(grep -cinE '(TODO:|FIXME:|HACK:)' "$FILE_PATH" 2>/dev/null || echo 0)
  # Escape for JSON
  MATCHES_ESCAPED=$(echo "$MATCHES" | head -3 | sed 's/"/\\"/g' | tr '\n' '; ' | sed 's/; $//')

  cat <<EOF
{
  "decision": "block",
  "reason": "Banned placeholder patterns detected (${MATCH_COUNT} occurrences) in ${FILE_PATH##*/}: ${MATCHES_ESCAPED}. Remove all TODO:/FIXME:/HACK: placeholders and implement the actual logic.",
  "fix_suggestion": "Delete TODO/FIXME/HACK comments and implement the actual functionality. Autopilot sub-agents must not leave placeholder code."
}
EOF
  exit 0
fi

exit 0
