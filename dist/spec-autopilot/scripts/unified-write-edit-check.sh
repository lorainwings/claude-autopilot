#!/usr/bin/env bash
# unified-write-edit-check.sh
# v5.1 Unified PostToolUse(Write|Edit) Hook
# Purpose: Single entry point combining 3 previously separate hooks into one process,
#          reducing fork overhead from ~35s (3 serial hooks) to ~5s (1 hook).
#
# Combines:
#   1. write-edit-constraint-check.sh  → Code constraint validation (Phase 5)
#   2. banned-patterns-check.sh        → TODO/FIXME/HACK detection (Phase 4/5/6)
#   3. assertion-quality-check.sh      → Tautological assertion detection (Phase 4/5/6)
#   4. [v5.1] TDD phase isolation      → RED/GREEN file type enforcement (Phase 5 TDD)
#
# Output: PostToolUse decision: "block" on first violation found.
# Performance: Single preamble + shared phase detection + sequential checks.

# --- Common preamble: stdin read, SCRIPT_DIR, _common.sh, Layer 0 bypass ---
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_hook_preamble.sh"

# ============================================================
# SHARED PHASE DETECTION (run once for all checks)
# ============================================================

CHANGES_DIR="$PROJECT_ROOT_QUICK/openspec/changes"
LOCK_FILE="$CHANGES_DIR/.autopilot-active"
[ -f "$LOCK_FILE" ] || exit 0

CHANGE_NAME=$(parse_lock_file "$LOCK_FILE")
[ -z "$CHANGE_NAME" ] && exit 0
PHASE_RESULTS="$CHANGES_DIR/$CHANGE_NAME/context/phase-results"
[ -d "$PHASE_RESULTS" ] || exit 0

# Check Phase 1 completed (required for all checks)
PHASE1_CP=$(find_checkpoint "$PHASE_RESULTS" 1)
[ -z "$PHASE1_CP" ] && exit 0
PHASE1_STATUS=$(read_checkpoint_status "$PHASE1_CP")
[ "$PHASE1_STATUS" != "ok" ] && [ "$PHASE1_STATUS" != "warning" ] && exit 0

# Determine if we're in Phase 5 specifically (for constraint check + TDD gate)
PHASE4_CP=$(find_checkpoint "$PHASE_RESULTS" 4)
PHASE3_CP=$(find_checkpoint "$PHASE_RESULTS" 3)

IN_PHASE5="no"
if [ -n "$PHASE4_CP" ]; then
  PHASE5_CP=$(find_checkpoint "$PHASE_RESULTS" 5)
  if [ -z "$PHASE5_CP" ]; then
    IN_PHASE5="yes"
  else
    STATUS=$(read_checkpoint_status "$PHASE5_CP")
    [ "$STATUS" != "ok" ] && IN_PHASE5="yes"
  fi
elif [ -n "$PHASE3_CP" ] && [ -n "$PHASE1_CP" ]; then
  TDD_MODE_VAL=$(read_config_value "$PROJECT_ROOT_QUICK" "phases.implementation.tdd_mode" "false")
  if [ "$TDD_MODE_VAL" = "true" ]; then
    PHASE5_CP=$(find_checkpoint "$PHASE_RESULTS" 5)
    if [ -z "$PHASE5_CP" ]; then
      IN_PHASE5="yes"
    else
      STATUS=$(read_checkpoint_status "$PHASE5_CP")
      [ "$STATUS" != "ok" ] && IN_PHASE5="yes"
    fi
  fi
elif [ -n "$PHASE1_CP" ]; then
  # Only Phase 1 checkpoint exists. Distinguish full vs lite/minimal:
  # - full mode: we're in Phase 2 or 3, NOT Phase 5 → do not set IN_PHASE5
  # - lite/minimal: Phase 5 follows directly after Phase 1
  LOCK_MODE=$(read_lock_json_field "$LOCK_FILE" "mode" "full")
  if [ "$LOCK_MODE" != "full" ]; then
    PHASE5_CP=$(find_checkpoint "$PHASE_RESULTS" 5)
    if [ -z "$PHASE5_CP" ]; then
      IN_PHASE5="yes"
    else
      STATUS=$(read_checkpoint_status "$PHASE5_CP")
      [ "$STATUS" != "ok" ] && IN_PHASE5="yes"
    fi
  fi
fi

# ============================================================
# SHARED FILE PATH EXTRACTION (run once)
# ============================================================

FILE_PATH=$(echo "$STDIN_DATA" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
[ -z "$FILE_PATH" ] && exit 0

BASENAME=$(basename "$FILE_PATH")

# ============================================================
# CHECK 0: Sub-Agent State Isolation (v5.1 SA-2 fix, pure bash, ~1ms)
# Blocks Phase 5 sub-agent writes to openspec/ and checkpoint paths.
# Checkpoint writers use Bash tool (not Write), so they bypass this hook.
# ============================================================

if [ "$IN_PHASE5" = "yes" ]; then
  PROTECTED_PATH_HIT="no"
  case "$FILE_PATH" in
    # Block writes to checkpoint / phase-results
    *context/phase-results/*) PROTECTED_PATH_HIT="yes" ;;
    # Block writes to openspec internal state (but NOT tasks.md which sub-agents may mark)
    *openspec/changes/*/context/*.json) PROTECTED_PATH_HIT="yes" ;;
    *openspec/changes/*/.autopilot-active) PROTECTED_PATH_HIT="yes" ;;
  esac

  # Narrow exception: .tdd-stage is written by main thread via Bash, but just in case
  case "$FILE_PATH" in
    *context/.tdd-stage) PROTECTED_PATH_HIT="no" ;;
  esac

  if [ "$PROTECTED_PATH_HIT" = "yes" ]; then
    cat <<EOF
{
  "decision": "block",
  "reason": "State isolation violation: Write to protected path '${BASENAME}' blocked during Phase 5. Sub-agents must NOT modify openspec/ or checkpoint files. Only the main orchestrator (via checkpoint-writer Bash commands) may write to these paths.",
  "fix_suggestion": "Write implementation code to the project's source directories, not to openspec/ or phase-results/. Checkpoint management is handled by the orchestrator."
}
EOF
    exit 0
  fi
fi

# ============================================================
# CHECK 1: TDD Phase Isolation (Phase 5 only, pure bash, ~1ms)
# ============================================================

if [ "$IN_PHASE5" = "yes" ]; then
  TDD_STAGE_FILE="$CHANGES_DIR/$CHANGE_NAME/context/.tdd-stage"
  if [ -f "$TDD_STAGE_FILE" ]; then
    TDD_STAGE=$(cat "$TDD_STAGE_FILE" 2>/dev/null | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')

    IS_TEST_FILE="no"
    case "$BASENAME" in
      *.test.* | *.spec.* | *_test.* | *_spec.* | *Test.* | *Spec.*) IS_TEST_FILE="yes" ;;
    esac
    case "$FILE_PATH" in
      */__tests__/* | */test/* | */tests/* | */spec/* | *_test/* | *_spec/*) IS_TEST_FILE="yes" ;;
    esac

    case "$TDD_STAGE" in
      red)
        if [ "$IS_TEST_FILE" = "no" ]; then
          echo '{"decision":"block","reason":"TDD RED stage violation: only test files can be written during RED. File '"$BASENAME"' appears to be an implementation file. Move to GREEN stage before writing implementation code."}'
          exit 0
        fi
        ;;
      green)
        if [ "$IS_TEST_FILE" = "yes" ]; then
          echo '{"decision":"block","reason":"TDD GREEN stage violation: test files cannot be modified during GREEN. File '"$BASENAME"' appears to be a test file. Fix the implementation to make tests pass — do NOT modify the test."}'
          exit 0
        fi
        ;;
    esac
  fi
fi

# ============================================================
# CHECK 2: Banned Patterns — TODO/FIXME/HACK (pure grep, ~2ms)
# ============================================================

# Skip non-source files
SKIP_BANNED="no"
case "$FILE_PATH" in
  *.md|*.txt|*.json|*.yaml|*.yml|*.toml|*.ini|*.cfg|*.conf|*.lock|*.log)
    SKIP_BANNED="yes" ;;
  */CHANGELOG*|*/changelog*|*/LICENSE*|*/README*)
    SKIP_BANNED="yes" ;;
  *openspec/*|*context/*|*phase-results/*)
    SKIP_BANNED="yes" ;;
esac

if [ "$SKIP_BANNED" = "no" ] && [ -f "$FILE_PATH" ]; then
  MATCHES=$(grep -inE '(TODO:|FIXME:|HACK:)' "$FILE_PATH" 2>/dev/null | head -5)
  if [ -n "$MATCHES" ]; then
    MATCH_COUNT=$(grep -cinE '(TODO:|FIXME:|HACK:)' "$FILE_PATH" 2>/dev/null || echo 0)
    MATCHES_ESCAPED=$(echo "$MATCHES" | head -3 | sed 's/"/\\"/g' | tr '\n' '; ' | sed 's/; $//')
    cat <<EOF
{
  "decision": "block",
  "reason": "Banned placeholder patterns detected (${MATCH_COUNT} occurrences) in ${BASENAME}: ${MATCHES_ESCAPED}. Remove all TODO:/FIXME:/HACK: placeholders and implement the actual logic.",
  "fix_suggestion": "Delete TODO/FIXME/HACK comments and implement the actual functionality. Autopilot sub-agents must not leave placeholder code."
}
EOF
    exit 0
  fi
fi

# ============================================================
# CHECK 3: Assertion Quality — Tautological assertions (pure grep, ~2ms)
# ============================================================

IS_TEST="no"
case "$FILE_PATH" in
  *test*|*spec*|*Test*|*Spec*|*__tests__*)
    IS_TEST="yes" ;;
esac

if [ "$IS_TEST" = "yes" ] && [ -f "$FILE_PATH" ]; then
  VIOLATIONS=""

  # JavaScript/TypeScript tautologies
  JS_TAUTOLOGY=$(grep -nE 'expect\((true|false|1|0|"[^"]*"|'\''[^'\'']*'\'')\)\.(toBe|toEqual|toStrictEqual)\(\1\)' "$FILE_PATH" 2>/dev/null | head -3)
  [ -n "$JS_TAUTOLOGY" ] && VIOLATIONS="${VIOLATIONS}${JS_TAUTOLOGY}; "

  JS_TRUTHY=$(grep -nE 'expect\(true\)\.toBeTruthy\(\)|expect\(false\)\.toBeFalsy\(\)' "$FILE_PATH" 2>/dev/null | head -3)
  [ -n "$JS_TRUTHY" ] && VIOLATIONS="${VIOLATIONS}${JS_TRUTHY}; "

  # Python tautologies
  PY_TAUTOLOGY=$(grep -nE '^\s*(assert\s+True|assert\s+not\s+False|self\.assert(True|Equal)\s*\(\s*(True|1|0)\s*,?\s*(True|1|0)?\s*\))' "$FILE_PATH" 2>/dev/null | head -3)
  [ -n "$PY_TAUTOLOGY" ] && VIOLATIONS="${VIOLATIONS}${PY_TAUTOLOGY}; "

  # Java/Kotlin tautologies
  JAVA_TAUTOLOGY=$(grep -nE '(assertEquals|assertSame)\s*\(\s*(true|false|1|0|"[^"]*")\s*,\s*\2\s*\)|assertTrue\s*\(\s*true\s*\)|assertFalse\s*\(\s*false\s*\)' "$FILE_PATH" 2>/dev/null | head -3)
  [ -n "$JAVA_TAUTOLOGY" ] && VIOLATIONS="${VIOLATIONS}${JAVA_TAUTOLOGY}; "

  # Generic tautologies
  GENERIC_TAUTOLOGY=$(grep -nE '(assert|expect|check).*\b(true\s*==\s*true|false\s*==\s*false|1\s*==\s*1|0\s*==\s*0)\b' "$FILE_PATH" 2>/dev/null | head -3)
  [ -n "$GENERIC_TAUTOLOGY" ] && VIOLATIONS="${VIOLATIONS}${GENERIC_TAUTOLOGY}; "

  if [ -n "$VIOLATIONS" ]; then
    VIOLATIONS_SHORT=$(echo "$VIOLATIONS" | head -c 400 | sed 's/"/\\"/g' | tr '\n' ' ')
    cat <<EOF
{
  "decision": "block",
  "reason": "Tautological assertions detected in ${BASENAME}: ${VIOLATIONS_SHORT}. These assertions test nothing and create a false sense of coverage. Replace with meaningful assertions that verify actual behavior.",
  "fix_suggestion": "Replace tautological assertions with real tests: assert the return value of function calls, check state changes, verify side effects."
}
EOF
    exit 0
  fi
fi

# ============================================================
# CHECK 4: Code Constraints (Phase 5 only, requires python3)
# ============================================================

if [ "$IN_PHASE5" = "yes" ]; then
  command -v python3 &>/dev/null || exit 0

  python3 -c "
import importlib.util, json, os, sys

_script_dir = os.environ.get('SCRIPT_DIR', '.')
_spec = importlib.util.spec_from_file_location('_cl', os.path.join(_script_dir, '_constraint_loader.py'))
_cl = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_cl)

file_path = '''$FILE_PATH'''
root = '''$PROJECT_ROOT_QUICK'''

constraints = _cl.load_constraints(root)
if not constraints['found'] and not constraints['forbidden_files'] and not constraints['forbidden_patterns']:
    sys.exit(0)

violations = _cl.check_file_violations(file_path, root, constraints)
if violations:
    shown = violations[:5]
    extra = f' (+{len(violations)-5} more)' if len(violations) > 5 else ''
    print(json.dumps({
        'decision': 'block',
        'reason': f'Write/Edit constraint violations ({len(violations)}): ' + '; '.join(shown) + extra + '. Fix before proceeding.'
    }))

sys.exit(0)
"
fi

exit 0
