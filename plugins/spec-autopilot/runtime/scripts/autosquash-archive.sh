#!/usr/bin/env bash
# autosquash-archive.sh — Consolidate all git autosquash operations for Phase 7 archive
#
# Usage: autosquash-archive.sh <session_cwd> <anchor_sha> <change_name> [allow_non_autopilot_fixups]
#
# Performs fixup completeness check, commits working tree residuals,
# validates/rebuilds anchor, and executes git autosquash rebase.
#
# Output: JSON to stdout with status, anchor_sha, squash_count, non_autopilot_fixups, error
# Exit: 0 always (status conveyed via JSON), except 1 for usage errors
#
# WP-5: Extracted from autopilot-phase7-archive/SKILL.md Step 4.b

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

# --- Input validation ---
SESSION_CWD="${1:-}"
ANCHOR_SHA="${2:-}"
CHANGE_NAME="${3:-}"
ALLOW_NON_AUTOPILOT_FIXUPS="${4:-false}"

if [ -z "$SESSION_CWD" ] || [ -z "$ANCHOR_SHA" ] || [ -z "$CHANGE_NAME" ]; then
  cat <<'EOF'
{"status":"blocked","anchor_sha":"","squash_count":0,"non_autopilot_fixups":[],"error":"Usage: autosquash-archive.sh <session_cwd> <anchor_sha> <change_name> [allow_non_autopilot_fixups]"}
EOF
  exit 1
fi

if [ ! -d "$SESSION_CWD" ]; then
  printf '{"status":"blocked","anchor_sha":"%s","squash_count":0,"non_autopilot_fixups":[],"error":"session_cwd directory not found: %s"}\n' \
    "$ANCHOR_SHA" "$SESSION_CWD"
  exit 1
fi

if [ ! -d "$SESSION_CWD/.git" ]; then
  printf '{"status":"blocked","anchor_sha":"%s","squash_count":0,"non_autopilot_fixups":[],"error":"Not a git repository: %s"}\n' \
    "$ANCHOR_SHA" "$SESSION_CWD"
  exit 1
fi

# --- Helpers ---
emit_result() {
  local status="$1"
  local anchor="$2"
  local count="$3"
  local fixups_json="$4"
  local error="$5"
  printf '{"status":"%s","anchor_sha":"%s","squash_count":%d,"non_autopilot_fixups":%s,"error":"%s"}\n' \
    "$status" "$anchor" "$count" "$fixups_json" "$error"
}

collect_fixup_log() {
  git -C "${SESSION_CWD}" log --oneline --format='%s' "${ANCHOR_SHA}..HEAD" 2>/dev/null || true
}

count_fixups_since_anchor() {
  local log_output="$1"
  local count=0
  if [ -n "$log_output" ]; then
    count=$(echo "$log_output" | grep -c "^fixup! " || true)
    [ -z "$count" ] && count=0
  fi
  echo "$count"
}

restore_stash_after_rebuild() {
  local stashed="${1:-0}"
  if [ "$stashed" -eq 1 ]; then
    if ! git -C "${SESSION_CWD}" stash pop --index >/dev/null 2>&1; then
      emit_result "blocked" "$ANCHOR_SHA" 0 "[]" \
        "Anchor rebuilt, but restoring stashed working tree changes failed. Resolve git stash state before retrying archive."
      return 1
    fi
  fi
  return 0
}

# --- Step 0: Anchor validation / rebuild ---
if ! git -C "${SESSION_CWD}" rev-parse --verify "${ANCHOR_SHA}^{commit}" >/dev/null 2>&1; then
  RECOVERED_ANCHOR=$(git -C "${SESSION_CWD}" log --format='%H' \
    --grep="^autopilot: start ${CHANGE_NAME}$" \
    --max-count=1 2>/dev/null || true)
  if [ -n "$RECOVERED_ANCHOR" ] && git -C "${SESSION_CWD}" merge-base --is-ancestor "$RECOVERED_ANCHOR" HEAD 2>/dev/null; then
    ANCHOR_SHA="$RECOVERED_ANCHOR"
  else
    LOCK_FILE="${SESSION_CWD}/openspec/changes/.autopilot-active"
    if [ ! -f "$LOCK_FILE" ]; then
      emit_result "blocked" "$ANCHOR_SHA" 0 "[]" \
        "Anchor SHA invalid and lock file is missing. Cannot rebuild anchor."
      exit 0
    fi

    STASHED_FOR_REBUILD=0
    DIRTY_STATE=$(git -C "${SESSION_CWD}" status --porcelain 2>/dev/null || echo "")
    if [ -n "$DIRTY_STATE" ]; then
      if ! git -C "${SESSION_CWD}" stash push --include-untracked -m "autopilot-anchor-rebuild" >/dev/null 2>&1; then
        emit_result "blocked" "$ANCHOR_SHA" 0 "[]" \
          "Anchor SHA invalid and temporary stash for rebuild failed."
        exit 0
      fi
      STASHED_FOR_REBUILD=1
    fi

    NEW_ANCHOR=""
    if [ -x "$SCRIPT_DIR/rebuild-anchor.sh" ]; then
      NEW_ANCHOR=$(bash "$SCRIPT_DIR/rebuild-anchor.sh" "${SESSION_CWD}" "$LOCK_FILE" 2>/dev/null) || true
    fi

    if [ -n "$NEW_ANCHOR" ] && git -C "${SESSION_CWD}" rev-parse --verify "${NEW_ANCHOR}^{commit}" >/dev/null 2>&1; then
      ANCHOR_SHA="$NEW_ANCHOR"
      restore_stash_after_rebuild "$STASHED_FOR_REBUILD" || exit 0
    else
      restore_stash_after_rebuild "$STASHED_FOR_REBUILD" >/dev/null 2>&1 || true
      emit_result "blocked" "$ANCHOR_SHA" 0 "[]" \
        "Anchor SHA invalid and rebuild failed. Cannot proceed with autosquash."
      exit 0
    fi
  fi
fi

# --- Step 1: Fixup completeness check ---
PHASE_RESULTS_DIR="${SESSION_CWD}/openspec/changes/${CHANGE_NAME}/context/phase-results"

CHECKPOINT_COUNT=0
if [ -d "$PHASE_RESULTS_DIR" ]; then
  # shellcheck disable=SC2010
  CHECKPOINT_COUNT=$(ls "${PHASE_RESULTS_DIR}"/phase-*.json 2>/dev/null |
    grep -v '\.tmp$' |
    grep -v 'interim' |
    grep -v 'progress' |
    wc -l | tr -d ' ')
fi

FIXUP_LOG=$(collect_fixup_log)
FIXUP_COUNT=$(count_fixups_since_anchor "$FIXUP_LOG")

if [ "$FIXUP_COUNT" -lt "$CHECKPOINT_COUNT" ]; then
  emit_result "blocked" "$ANCHOR_SHA" 0 "[]" \
    "Fixup count ($FIXUP_COUNT) < checkpoint count ($CHECKPOINT_COUNT). Not all phases have fixup commits."
  exit 0
fi

# --- Step 2: Commit working tree residuals ---
if ! git -C "${SESSION_CWD}" add -A >/dev/null 2>&1; then
  emit_result "blocked" "$ANCHOR_SHA" 0 "[]" \
    "Failed to stage working tree residuals before autosquash."
  exit 0
fi

if ! git -C "${SESSION_CWD}" diff --cached --quiet 2>/dev/null; then
  if ! git -C "${SESSION_CWD}" commit --no-verify -q --fixup="${ANCHOR_SHA}" \
    -m "fixup! autopilot: start ${CHANGE_NAME} — final" >/dev/null 2>&1; then
    emit_result "blocked" "$ANCHOR_SHA" 0 "[]" \
      "Failed to create final fixup commit for archive residuals."
    exit 0
  fi
fi

# --- Step 3: Non-autopilot fixup check ---
FIXUP_LOG=$(collect_fixup_log)
NON_AP_FIXUPS=""
if [ -n "$FIXUP_LOG" ]; then
  NON_AP_FIXUPS=$(echo "$FIXUP_LOG" |
    grep "^fixup! " |
    grep -v "^fixup! autopilot:" || true)
fi

NON_AP_JSON="[]"
if [ -n "$NON_AP_FIXUPS" ]; then
  NON_AP_JSON=$(python3 -c "
import json, sys
lines = [l.strip() for l in sys.stdin if l.strip()]
print(json.dumps(lines))
" <<<"$NON_AP_FIXUPS" 2>/dev/null || echo "[]")
fi

if [ -n "$NON_AP_FIXUPS" ] && [ "$ALLOW_NON_AUTOPILOT_FIXUPS" != "true" ]; then
  SQUASH_LOG=$(collect_fixup_log)
  SQUASH_COUNT=$(count_fixups_since_anchor "$SQUASH_LOG")
  emit_result "needs_confirmation" "$ANCHOR_SHA" "$SQUASH_COUNT" "$NON_AP_JSON" ""
  exit 0
fi

# --- Step 5: Execute autosquash ---
SQUASH_LOG=$(collect_fixup_log)
SQUASH_COUNT=$(count_fixups_since_anchor "$SQUASH_LOG")

if (cd "${SESSION_CWD}" && GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash "${ANCHOR_SHA}~1") 2>/dev/null; then
  emit_result "ok" "$ANCHOR_SHA" "$SQUASH_COUNT" "[]" ""
else
  git -C "${SESSION_CWD}" rebase --abort 2>/dev/null || true
  emit_result "blocked" "$ANCHOR_SHA" "$SQUASH_COUNT" "[]" \
    "Autosquash rebase failed. Rebase aborted."
fi
