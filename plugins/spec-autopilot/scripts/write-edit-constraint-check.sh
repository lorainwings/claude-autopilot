#!/usr/bin/env bash
# write-edit-constraint-check.sh
# Hook: PostToolUse(Write|Edit) — Phase 5 直接文件写入约束检查
# Uses shared constraint loading from _common.sh (v3.1.0: deduplication).
# Output: PostToolUse decision: "block" on violation.

set -uo pipefail

# --- Read stdin JSON ---
STDIN_DATA=""
if [ ! -t 0 ]; then
  STDIN_DATA=$(cat)
fi
[ -z "$STDIN_DATA" ] && exit 0

# --- Source shared utilities ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

# --- Fast bypass Layer 0: lock file ---
PROJECT_ROOT=$(extract_project_root "$STDIN_DATA")
has_active_autopilot "$PROJECT_ROOT" || exit 0

# --- Fast bypass Layer 1: Phase 5 detection ---
CHANGES_DIR="$PROJECT_ROOT/openspec/changes"
LOCK_FILE="$CHANGES_DIR/.autopilot-active"
[ -f "$LOCK_FILE" ] || exit 0

CHANGE_NAME=$(parse_lock_file "$LOCK_FILE")
[ -z "$CHANGE_NAME" ] && exit 0
PHASE_RESULTS="$CHANGES_DIR/$CHANGE_NAME/context/phase-results"
[ -d "$PHASE_RESULTS" ] || exit 0

PHASE4_CP=$(find_checkpoint "$PHASE_RESULTS" 4)
[ -z "$PHASE4_CP" ] && exit 0

PHASE5_CP=$(find_checkpoint "$PHASE_RESULTS" 5)
if [ -n "$PHASE5_CP" ]; then
  STATUS=$(read_checkpoint_status "$PHASE5_CP")
  [ "$STATUS" = "ok" ] && exit 0
fi

# --- Fast bypass Layer 2: extract file_path ---
FILE_PATH=$(echo "$STDIN_DATA" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
[ -z "$FILE_PATH" ] && exit 0

# --- Dependency check ---
command -v python3 &>/dev/null || exit 0

# --- Load constraints (cached) and check file ---
CONSTRAINTS=$(load_constraints "$PROJECT_ROOT")
VIOLATIONS=$(echo "$CONSTRAINTS" | check_file_constraints "$FILE_PATH" "$PROJECT_ROOT")

# --- Output result if violations found ---
python3 -c "
import json, sys
violations = json.loads(sys.argv[1])
if violations:
    shown = violations[:5]
    extra = f' (+{len(violations)-5} more)' if len(violations) > 5 else ''
    print(json.dumps({
        'decision': 'block',
        'reason': f'Write/Edit constraint violations ({len(violations)}): ' + '; '.join(shown) + extra + '. Fix before proceeding.'
    }))
" "$VIOLATIONS" 2>/dev/null

exit 0
