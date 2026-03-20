#!/usr/bin/env bash
# clean-phase-artifacts.sh — Clean phase artifacts from a given phase onward
#
# Usage: clean-phase-artifacts.sh <from_phase> <mode> [change_dir] [--git-target-sha <sha>] [--dry-run]
#
# Cleans all phase-related files for phases >= from_phase:
#   - phase-results/phase-{P}-*.json (including interim/progress)
#   - phase-context-snapshots/phase-{P}-context.md
#   - P=5: phase-results/phase5-tasks/ + context/.tdd-stage + worktree cleanup
#   - P=6: phase-6.5-*.json extra cleanup
#   - *.json.tmp residuals
#   - events.jsonl filtering (removes events with phase >= from_phase)
#
# When --git-target-sha is provided:
#   - Aborts any autopilot-related in-progress rebase/merge
#   - Validates SHA
#   - Temporarily stashes only non-cleanup working changes
#   - git reset --soft <sha>
#   - Restores preserved working changes after cleanup
#
# When --dry-run is provided:
#   - Collects all operations but does not execute them
#   - Outputs JSON manifest of planned actions
#
# Execution order (transactional):
#   1. Git state rollback (abort rebase/merge → preserve non-cleanup WIP → soft reset)
#      → preserve failure aborts git reset, proceeds with file cleanup only
#   2. File cleanup (phase-results + context snapshots)
#   3. Events filtering (atomic write via tempfile + os.replace)
#   4. Restore preserved working changes
#   5. Output JSON summary

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

# --- Parse arguments ---
FROM_PHASE="${1:?Usage: clean-phase-artifacts.sh <from_phase> <mode> [change_dir] [--git-target-sha <sha>] [--dry-run]}"
MODE="${2:-full}"
CHANGE_DIR="${3:-}"
GIT_TARGET_SHA=""
DRY_RUN=false

# Parse optional flags from remaining args
shift 2
[ $# -gt 0 ] && [ -n "$CHANGE_DIR" ] && shift
while [ $# -gt 0 ]; do
  case "$1" in
    --git-target-sha)
      GIT_TARGET_SHA="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    *)
      # If change_dir wasn't set and this doesn't look like a flag, treat as change_dir
      if [ -z "$CHANGE_DIR" ] && [[ "$1" != --* ]]; then
        CHANGE_DIR="$1"
      fi
      shift
      ;;
  esac
done

# --- Determine project root ---
if [ -n "$CHANGE_DIR" ]; then
  # Derive project root from change_dir path: .../openspec/changes/<name> → ...
  PROJECT_ROOT=$(echo "$CHANGE_DIR" | sed 's|/openspec/changes/.*||')
  [ -z "$PROJECT_ROOT" ] && PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
else
  PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  CHANGE_DIR=$(find_active_change "$PROJECT_ROOT/openspec/changes" 2>/dev/null) || {
    echo '{"status":"error","message":"No active change directory found"}' >&2
    exit 1
  }
fi

PHASE_RESULTS="$CHANGE_DIR/context/phase-results"
CONTEXT_SNAPSHOTS="$CHANGE_DIR/context/phase-context-snapshots"
CONTEXT_DIR="$CHANGE_DIR/context"
EVENTS_FILE="$PROJECT_ROOT/logs/events.jsonl"

# Track cleanup stats
FILES_REMOVED=0
EVENTS_FILTERED=0
GIT_RESET_DONE=false
STASH_CREATED=false
STASH_REF=""
STASH_RESTORED=false
REBASE_ABORTED=false
MERGE_ABORTED=false
STATUS="ok"

CHANGE_REL="${CHANGE_DIR#$PROJECT_ROOT/}"
EVENTS_REL=""
case "$EVENTS_FILE" in
  "$PROJECT_ROOT"/*) EVENTS_REL="${EVENTS_FILE#$PROJECT_ROOT/}" ;;
esac

collect_preserve_paths() {
  python3 -c "
import sys

change_rel = sys.argv[1].strip('/')
from_phase = int(sys.argv[2])
events_rel = sys.argv[3].strip('/')
raw_paths = sys.stdin.buffer.read().split(b'\0')

seen = set()
paths = []
for raw in raw_paths:
    if not raw:
        continue
    path = raw.decode('utf-8', 'surrogateescape')
    if path in seen:
        continue
    seen.add(path)
    paths.append(path)

def is_cleanup_path(path: str) -> bool:
    if events_rel and path == events_rel:
        return True

    phase_results_prefix = f'{change_rel}/context/phase-results/'
    snapshots_prefix = f'{change_rel}/context/phase-context-snapshots/'

    if from_phase <= 5 and path == f'{change_rel}/context/.tdd-stage':
        return True

    if path.startswith(phase_results_prefix):
        name = path[len(phase_results_prefix):]
        if from_phase <= 5 and (name == 'phase5-tasks' or name.startswith('phase5-tasks/')):
            return True
        if from_phase <= 6 and name.startswith('phase-6.5-') and (
            name.endswith('.json') or name.endswith('.json.tmp')
        ):
            return True
        for phase in range(from_phase, 8):
            if name.startswith(f'phase-{phase}-') and (
                name.endswith('.json') or name.endswith('.json.tmp')
            ):
                return True

    if path.startswith(snapshots_prefix):
        name = path[len(snapshots_prefix):]
        for phase in range(from_phase, 8):
            if name == f'phase-{phase}-context.md':
                return True

    return False

for path in paths:
    if not is_cleanup_path(path):
        print(path)
" "$CHANGE_REL" "$FROM_PHASE" "$EVENTS_REL"
}

# --- Step 1: Git state rollback (before file cleanup for transactional safety) ---
if [ -n "$GIT_TARGET_SHA" ]; then
  cd "$PROJECT_ROOT" || exit 1

  # Only abort rebase/merge if they appear to be autopilot-related
  if [ -d .git/rebase-merge ] || [ -d .git/rebase-apply ]; then
    is_autopilot_rebase=false
    if [ -f .git/rebase-merge/message ] && grep -q "autopilot" .git/rebase-merge/message 2>/dev/null; then
      is_autopilot_rebase=true
    elif [ -f .git/rebase-apply/msg ] && grep -q "autopilot" .git/rebase-apply/msg 2>/dev/null; then
      is_autopilot_rebase=true
    fi
    if [ "$is_autopilot_rebase" = "true" ]; then
      if [ "$DRY_RUN" = "true" ]; then
        REBASE_ABORTED=true
      else
        echo "WARNING: Aborting autopilot-related rebase" >&2
        git rebase --abort 2>/dev/null || true
        REBASE_ABORTED=true
      fi
    else
      echo "WARNING: Skipping non-autopilot rebase abort (rebase in progress but not autopilot-related)" >&2
    fi
  fi

  # Only abort merge if it appears autopilot-related
  if [ -f .git/MERGE_HEAD ]; then
    is_autopilot_merge=false
    if [ -f .git/MERGE_MSG ] && grep -q "autopilot" .git/MERGE_MSG 2>/dev/null; then
      is_autopilot_merge=true
    fi
    if [ "$is_autopilot_merge" = "true" ]; then
      if [ "$DRY_RUN" = "true" ]; then
        MERGE_ABORTED=true
      else
        echo "WARNING: Aborting autopilot-related merge" >&2
        git merge --abort 2>/dev/null || true
        MERGE_ABORTED=true
      fi
    else
      echo "WARNING: Skipping non-autopilot merge abort (merge in progress but not autopilot-related)" >&2
    fi
  fi

  if [ "$DRY_RUN" = "false" ]; then
    # Validate SHA
    if ! git rev-parse --verify "${GIT_TARGET_SHA}^{commit}" &>/dev/null; then
      echo "{\"status\":\"error\",\"message\":\"Invalid SHA: ${GIT_TARGET_SHA}\",\"rebase_aborted\":${REBASE_ABORTED},\"merge_aborted\":${MERGE_ABORTED}}"
      exit 1
    fi

    # Preserve only non-cleanup working changes so restoring them does not reintroduce cleaned artifacts.
    if ! git diff --quiet HEAD 2>/dev/null || ! git diff --cached --quiet HEAD 2>/dev/null || [ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]; then
      PRESERVE_PATHS=()
      while IFS= read -r preserve_path; do
        PRESERVE_PATHS+=("$preserve_path")
      done < <(
        {
          git diff --name-only -z
          git diff --cached --name-only -z
          git ls-files --others --exclude-standard -z
        } | collect_preserve_paths
      )

      if [ "${#PRESERVE_PATHS[@]}" -gt 0 ]; then
        stash_count_before=$(git stash list 2>/dev/null | wc -l | tr -d ' ')
        git stash push -u -m "autopilot-recovery-$(date +%s)" -- "${PRESERVE_PATHS[@]}" >/dev/null 2>/dev/null
        stash_count_after=$(git stash list 2>/dev/null | wc -l | tr -d ' ')
        if [ "$stash_count_after" -gt "$stash_count_before" ]; then
          STASH_CREATED=true
          STASH_REF=$(git stash list --format="%gd" 2>/dev/null | head -1)
        else
          # Preserve failed — abort git reset to protect user WIP
          echo "WARNING: git stash push failed, skipping git reset to protect working changes" >&2
          GIT_TARGET_SHA=""
        fi
      fi
    fi

    # Soft reset — only if stash succeeded or no changes needed stashing
    if [ -n "$GIT_TARGET_SHA" ]; then
      if ! git reset --soft "$GIT_TARGET_SHA" 2>/dev/null; then
        echo "{\"status\":\"error\",\"message\":\"git reset --soft failed\",\"rebase_aborted\":${REBASE_ABORTED},\"merge_aborted\":${MERGE_ABORTED},\"stash_created\":${STASH_CREATED},\"stash_ref\":\"${STASH_REF}\",\"stash_restored\":${STASH_RESTORED}}"
        exit 1
      fi
      GIT_RESET_DONE=true
    fi
  fi
fi

# --- Step 2: File cleanup ---
# Iterate all phases 1-7 and clean those >= from_phase
for P in 1 2 3 4 5 6 7; do
  [ "$P" -lt "$FROM_PHASE" ] && continue

  # Clean phase-results/phase-{P}-*.json (checkpoint, interim, progress)
  if [ -d "$PHASE_RESULTS" ]; then
    for f in "$PHASE_RESULTS"/phase-${P}-*.json "$PHASE_RESULTS"/phase-${P}-*.json.tmp; do
      if [ -f "$f" ]; then
        [ "$DRY_RUN" = "false" ] && rm -f "$f"
        FILES_REMOVED=$((FILES_REMOVED + 1))
      fi
    done
  fi

  # Clean phase-context-snapshots/phase-{P}-context.md
  if [ -d "$CONTEXT_SNAPSHOTS" ]; then
    snapshot_file="$CONTEXT_SNAPSHOTS/phase-${P}-context.md"
    if [ -f "$snapshot_file" ]; then
      [ "$DRY_RUN" = "false" ] && rm -f "$snapshot_file"
      FILES_REMOVED=$((FILES_REMOVED + 1))
    fi
  fi

  # Phase 5 special: phase5-tasks/ + .tdd-stage + worktree cleanup
  if [ "$P" -eq 5 ]; then
    if [ -d "$PHASE_RESULTS/phase5-tasks" ]; then
      task_count=$(find "$PHASE_RESULTS/phase5-tasks" -type f 2>/dev/null | wc -l | tr -d ' ')
      [ "$DRY_RUN" = "false" ] && rm -rf "$PHASE_RESULTS/phase5-tasks"
      FILES_REMOVED=$((FILES_REMOVED + task_count))
    fi
    if [ -f "$CONTEXT_DIR/.tdd-stage" ]; then
      [ "$DRY_RUN" = "false" ] && rm -f "$CONTEXT_DIR/.tdd-stage"
      FILES_REMOVED=$((FILES_REMOVED + 1))
    fi
    # Worktree cleanup: only remove worktrees belonging to this change
    if [ "$DRY_RUN" = "false" ] && command -v git &>/dev/null; then
      wt_change_name=$(basename "$CHANGE_DIR")
      git worktree list 2>/dev/null | grep "autopilot-task" | while read -r wt_line; do
        wt_path=$(echo "$wt_line" | awk '{print $1}')
        # Only remove if worktree path contains this change's name
        if echo "$wt_path" | grep -q "$wt_change_name"; then
          git worktree remove --force "$wt_path" 2>/dev/null || true
        fi
      done
    fi
  fi

  # Phase 6 special: phase-6.5-*.json
  if [ "$P" -eq 6 ] && [ -d "$PHASE_RESULTS" ]; then
    for f in "$PHASE_RESULTS"/phase-6.5-*.json "$PHASE_RESULTS"/phase-6.5-*.json.tmp; do
      if [ -f "$f" ]; then
        [ "$DRY_RUN" = "false" ] && rm -f "$f"
        FILES_REMOVED=$((FILES_REMOVED + 1))
      fi
    done
  fi
done

# Clean all *.json.tmp residuals in phase-results
if [ -d "$PHASE_RESULTS" ]; then
  for f in "$PHASE_RESULTS"/*.json.tmp; do
    if [ -f "$f" ]; then
      [ "$DRY_RUN" = "false" ] && rm -f "$f"
      FILES_REMOVED=$((FILES_REMOVED + 1))
    fi
  done
fi

# --- Step 3: Events filtering (atomic write) ---
if [ -f "$EVENTS_FILE" ]; then
  ORIGINAL_COUNT=$(wc -l <"$EVENTS_FILE" | tr -d ' ')
  if [ "$DRY_RUN" = "true" ]; then
    # Count how many would be filtered without modifying
    EVENTS_FILTERED=$(python3 -c "
import json, sys
from_phase = int(sys.argv[1])
events_file = sys.argv[2]
count = 0
with open(events_file) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            event = json.loads(line)
            phase = event.get('phase')
            if phase is not None and int(phase) >= from_phase:
                count += 1
        except (json.JSONDecodeError, ValueError, TypeError):
            pass
print(count)
" "$FROM_PHASE" "$EVENTS_FILE" 2>/dev/null) || EVENTS_FILTERED=0
  else
    # Atomic write: write to temp file, then os.replace()
    python3 -c "
import json, sys, os, tempfile

from_phase = int(sys.argv[1])
events_file = sys.argv[2]

kept = []
with open(events_file) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            event = json.loads(line)
            phase = event.get('phase')
            if phase is not None and int(phase) >= from_phase:
                continue
            kept.append(line)
        except (json.JSONDecodeError, ValueError, TypeError):
            kept.append(line)

tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(events_file), suffix='.tmp')
try:
    with os.fdopen(tmp_fd, 'w') as f:
        for line in kept:
            f.write(line + '\n')
    os.replace(tmp_path, events_file)
except Exception:
    try:
        os.unlink(tmp_path)
    except OSError:
        pass
    raise
" "$FROM_PHASE" "$EVENTS_FILE" 2>/dev/null || true
    NEW_COUNT=$(wc -l <"$EVENTS_FILE" | tr -d ' ')
    EVENTS_FILTERED=$((ORIGINAL_COUNT - NEW_COUNT))
  fi
fi

# --- Step 4: Restore preserved working changes ---
if [ "$DRY_RUN" = "false" ] && [ "$STASH_CREATED" = "true" ] && [ -n "$STASH_REF" ]; then
  if git stash apply --index "$STASH_REF" >/dev/null 2>&1; then
    git stash drop "$STASH_REF" >/dev/null 2>&1 || true
    STASH_RESTORED=true
    STASH_REF=""
  else
    STATUS="warning"
    echo "WARNING: Failed to restore preserved working changes from $STASH_REF" >&2
  fi
fi

# --- Step 5: Detect fixup commit status (read-only, never auto-squash) ---
HAS_FIXUP_COMMITS=false
FIXUP_COMMIT_COUNT=0
if [ -d "$PROJECT_ROOT/.git" ] 2>/dev/null && command -v git &>/dev/null; then
  # Scope to last 50 commits to avoid scanning entire history
  FIXUP_COMMIT_COUNT=$(git -C "$PROJECT_ROOT" log --oneline --format='%s' -50 2>/dev/null | grep -c "^fixup! " 2>/dev/null) || FIXUP_COMMIT_COUNT=0
  [ "$FIXUP_COMMIT_COUNT" -gt 0 ] && HAS_FIXUP_COMMITS=true
fi

# --- Step 6: Output JSON summary ---
echo "{\"status\":\"${STATUS}\",\"from_phase\":${FROM_PHASE},\"mode\":\"${MODE}\",\"files_removed\":${FILES_REMOVED},\"events_filtered\":${EVENTS_FILTERED},\"git_reset\":${GIT_RESET_DONE},\"stash_created\":${STASH_CREATED},\"stash_restored\":${STASH_RESTORED},\"stash_ref\":\"${STASH_REF}\",\"rebase_aborted\":${REBASE_ABORTED},\"merge_aborted\":${MERGE_ABORTED},\"dry_run\":${DRY_RUN},\"has_fixup_commits\":${HAS_FIXUP_COMMITS},\"fixup_commit_count\":${FIXUP_COMMIT_COUNT}}"
