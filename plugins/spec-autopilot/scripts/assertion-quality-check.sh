#!/usr/bin/env bash
# ┌─────────────────────────────────────────────────────────────┐
# │ DEPRECATED since v5.1                                       │
# │ Replaced by: unified-write-edit-check.sh                    │
# │ Planned removal: next major version                         │
# │ NOT registered in hooks.json — retained for compatibility   │
# └─────────────────────────────────────────────────────────────┘
# assertion-quality-check.sh
# Hook: PostToolUse(Write|Edit) — 拦截恒真/恒假断言 (TD-1)
# Purpose: Detect tautological assertions in test files that provide no real coverage.
#          Patterns: expect(true).toBe(true), assert True, assertEquals(1,1), etc.
# Performance: Pure grep, no python3 fork (~2ms)
# Output: PostToolUse decision: "block" on violation.

# --- Common preamble: stdin read, SCRIPT_DIR, _common.sh, Layer 0 bypass ---
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_hook_preamble.sh"

# --- Fast bypass: only during active phases ---
CHANGES_DIR="$PROJECT_ROOT_QUICK/openspec/changes"
LOCK_FILE="$CHANGES_DIR/.autopilot-active"
[ -f "$LOCK_FILE" ] || exit 0

CHANGE_NAME=$(parse_lock_file "$LOCK_FILE")
[ -z "$CHANGE_NAME" ] && exit 0
PHASE_RESULTS="$CHANGES_DIR/$CHANGE_NAME/context/phase-results"
[ -d "$PHASE_RESULTS" ] || exit 0

# Only check after Phase 1 is done (i.e., we're in active development)
PHASE1_CP=$(find_checkpoint "$PHASE_RESULTS" 1)
[ -z "$PHASE1_CP" ] && exit 0
PHASE1_STATUS=$(read_checkpoint_status "$PHASE1_CP")
[ "$PHASE1_STATUS" != "ok" ] && [ "$PHASE1_STATUS" != "warning" ] && exit 0

# --- Extract file_path from stdin (pure bash, ~1ms) ---
FILE_PATH=$(echo "$STDIN_DATA" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
[ -z "$FILE_PATH" ] && exit 0

# --- Only check test files ---
IS_TEST="no"
case "$FILE_PATH" in
  *test*|*spec*|*Test*|*Spec*)
    IS_TEST="yes" ;;
esac
[ "$IS_TEST" != "yes" ] && exit 0

# --- Check file exists ---
[ -f "$FILE_PATH" ] || exit 0

# --- Scan for tautological assertion patterns ---
# Each pattern matches a self-evident assertion that tests nothing
VIOLATIONS=""

# JavaScript/TypeScript: expect(true).toBe(true), expect(false).toBe(false)
# expect(1).toBe(1), expect("x").toBe("x"), expect(null).toBeNull()
JS_TAUTOLOGY=$(grep -nE 'expect\((true|false|1|0|"[^"]*"|'\''[^'\'']*'\'')\)\.(toBe|toEqual|toStrictEqual)\(\1\)' "$FILE_PATH" 2>/dev/null | head -3)
[ -n "$JS_TAUTOLOGY" ] && VIOLATIONS="${VIOLATIONS}${JS_TAUTOLOGY}; "

# expect(true).toBeTruthy(), expect(false).toBeFalsy()
JS_TRUTHY=$(grep -nE 'expect\(true\)\.toBeTruthy\(\)|expect\(false\)\.toBeFalsy\(\)' "$FILE_PATH" 2>/dev/null | head -3)
[ -n "$JS_TRUTHY" ] && VIOLATIONS="${VIOLATIONS}${JS_TRUTHY}; "

# Python: assert True, assert not False, assertEqual(1, 1)
PY_TAUTOLOGY=$(grep -nE '^\s*(assert\s+True|assert\s+not\s+False|self\.assert(True|Equal)\s*\(\s*(True|1|0)\s*,?\s*(True|1|0)?\s*\))' "$FILE_PATH" 2>/dev/null | head -3)
[ -n "$PY_TAUTOLOGY" ] && VIOLATIONS="${VIOLATIONS}${PY_TAUTOLOGY}; "

# Java/Kotlin: assertEquals(1, 1), assertTrue(true), assertFalse(false)
JAVA_TAUTOLOGY=$(grep -nE '(assertEquals|assertSame)\s*\(\s*(true|false|1|0|"[^"]*")\s*,\s*\2\s*\)|assertTrue\s*\(\s*true\s*\)|assertFalse\s*\(\s*false\s*\)' "$FILE_PATH" 2>/dev/null | head -3)
[ -n "$JAVA_TAUTOLOGY" ] && VIOLATIONS="${VIOLATIONS}${JAVA_TAUTOLOGY}; "

# Generic: 1 == 1, true == true in assertions
GENERIC_TAUTOLOGY=$(grep -nE '(assert|expect|check).*\b(true\s*==\s*true|false\s*==\s*false|1\s*==\s*1|0\s*==\s*0)\b' "$FILE_PATH" 2>/dev/null | head -3)
[ -n "$GENERIC_TAUTOLOGY" ] && VIOLATIONS="${VIOLATIONS}${GENERIC_TAUTOLOGY}; "

if [ -n "$VIOLATIONS" ]; then
  # Truncate and escape for JSON
  VIOLATIONS_SHORT=$(echo "$VIOLATIONS" | head -c 400 | sed 's/"/\\"/g' | tr '\n' ' ')

  cat <<EOF
{
  "decision": "block",
  "reason": "Tautological assertions detected in ${FILE_PATH##*/}: ${VIOLATIONS_SHORT}. These assertions (e.g. expect(true).toBe(true)) test nothing and create a false sense of coverage. Replace with meaningful assertions that verify actual behavior.",
  "fix_suggestion": "Replace tautological assertions with real tests: assert the return value of function calls, check state changes, verify side effects. Every assertion must test actual behavior."
}
EOF
  exit 0
fi

exit 0
