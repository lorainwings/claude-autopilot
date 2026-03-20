#!/usr/bin/env bash
# recovery-decision.sh — Deterministic recovery scanning script
#
# Usage: recovery-decision.sh <changes_dir> <mode> [--change <name>]
# Exit: 0 (always — never blocks)
# Output: JSON on stdout
#
# Pure read-only: does NOT modify any files or git state.
# Scans checkpoints, lock file, git state, and computes recovery options.
#
# Fix v5.6.2:
#   - last_valid_phase stops at first gap (consistent with _common.sh)
#   - progress files provide sub_step in recovery_options.continue
#   - specify_range only includes actually-completed phases (no gap phases)
#   - interim/progress-only changes correctly set recovery phase

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

# --- Read configuration (env var only initially; config file read after arg parsing) ---
# recovery.auto_continue_single_candidate (default: true)
AUTO_CONTINUE_SINGLE_CANDIDATE="${AUTOPILOT_RECOVERY_AUTO_CONTINUE_SINGLE_CANDIDATE:-}"

# --- Parse arguments ---
CHANGES_DIR="${1:-}"
CLI_MODE="${2:-full}"
SELECTED_CHANGE=""

if [ -z "$CHANGES_DIR" ]; then
  echo '{"status":"error","message":"Usage: recovery-decision.sh <changes_dir> <mode> [--change <name>]"}'
  exit 0
fi

shift 2 || true
while [ $# -gt 0 ]; do
  case "$1" in
    --change)
      SELECTED_CHANGE="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

# --- Validate changes directory ---
if [ ! -d "$CHANGES_DIR" ]; then
  echo '{"status":"error","message":"Changes directory does not exist: '"$CHANGES_DIR"'"}'
  exit 0
fi

# Derive project root
PROJECT_ROOT=$(echo "$CHANGES_DIR" | sed 's|/openspec/changes$||')
[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# --- Resolve config: read from config file if env var not set ---
if [ -z "$AUTO_CONTINUE_SINGLE_CANDIDATE" ]; then
  AUTO_CONTINUE_SINGLE_CANDIDATE=$(read_config_value "$PROJECT_ROOT" "recovery.auto_continue_single_candidate" "true" 2>/dev/null) || AUTO_CONTINUE_SINGLE_CANDIDATE="true"
fi
case "$AUTO_CONTINUE_SINGLE_CANDIDATE" in
  true|True|1|yes) AUTO_CONTINUE_SINGLE_CANDIDATE="true" ;;
  *) AUTO_CONTINUE_SINGLE_CANDIDATE="false" ;;
esac

# --- Read lock file status ---
LOCK_FILE="$CHANGES_DIR/.autopilot-active"
LOCK_JSON='{"exists":false,"mode":"","anchor_sha":"","session_id":""}'
if [ -f "$LOCK_FILE" ]; then
  LOCK_JSON=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    print(json.dumps({
        'exists': True,
        'mode': data.get('mode', ''),
        'anchor_sha': data.get('anchor_sha', ''),
        'session_id': data.get('session_id', '')
    }))
except Exception:
    print(json.dumps({'exists': True, 'mode': '', 'anchor_sha': '', 'session_id': ''}))
" "$LOCK_FILE" 2>/dev/null) || LOCK_JSON='{"exists":true,"mode":"","anchor_sha":"","session_id":""}'
fi

# --- Resolve effective mode (lockfile mode takes priority) ---
LOCK_MODE=$(echo "$LOCK_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('mode',''))" 2>/dev/null) || true
if [ -n "$LOCK_MODE" ] && [ "$LOCK_MODE" != "" ]; then
  MODE="$LOCK_MODE"
else
  MODE="$CLI_MODE"
fi

# --- Detect git state ---
GIT_STATE='{"rebase_in_progress":false,"merge_in_progress":false,"worktree_residuals":[]}'
if [ -d "$PROJECT_ROOT/.git" ] 2>/dev/null; then
  REBASE_IN_PROGRESS=false
  MERGE_IN_PROGRESS=false
  WORKTREE_RESIDUALS="[]"

  [ -d "$PROJECT_ROOT/.git/rebase-merge" ] || [ -d "$PROJECT_ROOT/.git/rebase-apply" ] && REBASE_IN_PROGRESS=true
  [ -f "$PROJECT_ROOT/.git/MERGE_HEAD" ] && MERGE_IN_PROGRESS=true

  # Detect worktree residuals
  if command -v git &>/dev/null; then
    WORKTREE_RESIDUALS=$(git -C "$PROJECT_ROOT" worktree list 2>/dev/null | grep "autopilot-task" | awk '{print "\"" $1 "\""}' | paste -sd',' - 2>/dev/null) || true
    [ -n "$WORKTREE_RESIDUALS" ] && WORKTREE_RESIDUALS="[$WORKTREE_RESIDUALS]" || WORKTREE_RESIDUALS="[]"
  fi

  GIT_STATE="{\"rebase_in_progress\":${REBASE_IN_PROGRESS},\"merge_in_progress\":${MERGE_IN_PROGRESS},\"worktree_residuals\":${WORKTREE_RESIDUALS}}"
fi

# --- Detect fixup commits (scoped to current session, not entire history) ---
HAS_FIXUP_COMMITS=false
FIXUP_COMMIT_COUNT=0
if [ -d "$PROJECT_ROOT/.git" ] 2>/dev/null && command -v git &>/dev/null; then
  # Try to scope fixup scan to commits since anchor_sha (autopilot session start)
  ANCHOR_SHA=""
  if [ -f "$LOCK_FILE" ]; then
    ANCHOR_SHA=$(python3 -c "import json,sys
try:
    with open(sys.argv[1]) as f: print(json.load(f).get('anchor_sha',''))
except: pass" "$LOCK_FILE" 2>/dev/null) || true
  fi
  if [ -n "$ANCHOR_SHA" ] && git -C "$PROJECT_ROOT" rev-parse --verify "${ANCHOR_SHA}^{commit}" &>/dev/null; then
    # Scan only commits since anchor (current autopilot session)
    FIXUP_COMMIT_COUNT=$(git -C "$PROJECT_ROOT" log --oneline --format="%s" "${ANCHOR_SHA}..HEAD" 2>/dev/null | grep -c "^fixup! " 2>/dev/null) || FIXUP_COMMIT_COUNT=0
  else
    # No anchor — fall back to last 50 commits (bounded, not entire history)
    FIXUP_COMMIT_COUNT=$(git -C "$PROJECT_ROOT" log --oneline --format="%s" -50 2>/dev/null | grep -c "^fixup! " 2>/dev/null) || FIXUP_COMMIT_COUNT=0
  fi
  [ "$FIXUP_COMMIT_COUNT" -gt 0 ] && HAS_FIXUP_COMMITS=true
fi

# --- Scan all change directories ---
CHANGES_JSON=$(python3 -c "
import json, sys, os, glob

changes_dir = sys.argv[1]
mode = sys.argv[2]

# Determine phase sequence
if mode == 'lite':
    phases = [1, 5, 6, 7]
elif mode == 'minimal':
    phases = [1, 5, 7]
else:
    phases = [1, 2, 3, 4, 5, 6, 7]

phase_labels = {0:'Environment Setup',1:'Requirements',2:'OpenSpec',3:'Fast-Forward',4:'Test Design',5:'Implementation',6:'Test Report',7:'Archive'}

changes = []
for entry in sorted(os.listdir(changes_dir)):
    if entry.startswith('.') or entry.startswith('_'):
        continue
    change_path = os.path.join(changes_dir, entry)
    if not os.path.isdir(change_path):
        continue

    pr_dir = os.path.join(change_path, 'context', 'phase-results')

    # Phase 1 interim
    phase1_interim = None
    if os.path.isdir(pr_dir):
        interim_files = glob.glob(os.path.join(pr_dir, 'phase-1-interim.json'))
        if interim_files:
            try:
                with open(interim_files[0]) as fh:
                    idata = json.load(fh)
                phase1_interim = {'stage': idata.get('stage', 'unknown'), 'status': idata.get('status', 'unknown')}
            except Exception:
                pass

    # Progress files
    progress_files = []
    if os.path.isdir(pr_dir):
        prog_pattern = os.path.join(pr_dir, 'phase-*-progress.json')
        for pf in sorted(glob.glob(prog_pattern)):
            try:
                with open(pf) as fh:
                    pdata = json.load(fh)
                fname = os.path.basename(pf)
                parts = fname.replace('phase-', '').replace('-progress.json', '')
                phase_num = int(parts)
                progress_files.append({
                    'phase': phase_num,
                    'step': pdata.get('step', 'unknown'),
                    'status': pdata.get('status', 'unknown')
                })
            except Exception:
                pass

    if not os.path.isdir(pr_dir):
        changes.append({
            'name': entry,
            'last_valid_phase': 0,
            'last_valid_label': 'None',
            'total_checkpoints': 0,
            'has_gaps': False,
            'gap_phases': [],
            'phase7_status': None,
            'phase1_interim': phase1_interim,
            'progress_files': progress_files,
            'checkpoint_scan': []
        })
        continue

    # Scan checkpoints — last_valid stops at first gap (consistent with _common.sh)
    checkpoint_scan = []
    last_valid = 0
    total_checkpoints = 0
    gap_phases = []
    first_valid_seen = False

    for p in phases:
        pattern = os.path.join(pr_dir, f'phase-{p}-*.json')
        files = sorted(glob.glob(pattern), key=lambda f: os.path.getmtime(f), reverse=True)
        files = [f for f in files if not f.endswith('.tmp') and not f.endswith('-progress.json') and not f.endswith('-interim.json')]
        if files:
            try:
                with open(files[0]) as fh:
                    data = json.load(fh)
                status = data.get('status', 'unknown')
                checkpoint_scan.append({'phase': p, 'file': os.path.basename(files[0]), 'status': status})
                total_checkpoints += 1
                if status in ('ok', 'warning'):
                    if first_valid_seen and gap_phases:
                        # Valid after gap — record it in scan but do NOT advance last_valid
                        pass
                    else:
                        first_valid_seen = True
                        last_valid = p
                else:
                    if first_valid_seen:
                        gap_phases.append(p)
            except (json.JSONDecodeError, OSError):
                checkpoint_scan.append({'phase': p, 'file': os.path.basename(files[0]), 'status': 'error'})
                if first_valid_seen:
                    gap_phases.append(p)
        else:
            checkpoint_scan.append({'phase': p, 'file': None, 'status': 'missing'})
            if first_valid_seen:
                gap_phases.append(p)

    # Phase 7 status
    phase7_status = None
    for cs in checkpoint_scan:
        if cs['phase'] == 7 and cs['status'] != 'missing':
            phase7_status = cs['status']

    changes.append({
        'name': entry,
        'last_valid_phase': last_valid,
        'last_valid_label': phase_labels.get(last_valid, 'Unknown'),
        'total_checkpoints': total_checkpoints,
        'has_gaps': len(gap_phases) > 0,
        'gap_phases': gap_phases,
        'phase7_status': phase7_status,
        'phase1_interim': phase1_interim,
        'progress_files': progress_files,
        'checkpoint_scan': checkpoint_scan
    })

print(json.dumps(changes))
" "$CHANGES_DIR" "$MODE" 2>/dev/null) || CHANGES_JSON="[]"

# --- Compute recovery options ---
RESULT_JSON=$(python3 -c "
import json, sys

changes = json.loads(sys.argv[1])
mode = sys.argv[2]
selected = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else None
lock_file = json.loads(sys.argv[4])
git_state = json.loads(sys.argv[5])
has_fixup_commits = sys.argv[6] == 'true'
fixup_commit_count = int(sys.argv[7])
auto_continue_cfg = sys.argv[8] == 'true'

# Phase sequence and labels
if mode == 'lite':
    phase_seq = [1, 5, 6, 7]
elif mode == 'minimal':
    phase_seq = [1, 5, 7]
else:
    phase_seq = [1, 2, 3, 4, 5, 6, 7]

phase_labels = {0:'Environment Setup',1:'Requirements',2:'OpenSpec',3:'Fast-Forward',4:'Test Design',5:'Implementation',6:'Test Report',7:'Archive'}

def next_phase(current, seq):
    found = False
    for p in seq:
        if found:
            return p
        if p == current:
            found = True
    return None  # done

def first_incomplete_phase(change_data, seq):
    \"\"\"Find the first phase that is not ok/warning — this is where recovery should start.
    Handles gaps correctly: P1=ok, P2=ok, P3=missing, P4=ok → returns 3 (the gap).\"\"\"
    for p in seq:
        cs = [x for x in change_data.get('checkpoint_scan', []) if x['phase'] == p]
        if not cs or cs[0]['status'] not in ('ok', 'warning'):
            return p
    return None  # all done

# has_checkpoints also considers interim and progress files
has_checkpoints = any(c['total_checkpoints'] > 0 for c in changes)
has_partial_progress = any(c.get('phase1_interim') is not None or len(c.get('progress_files', [])) > 0 for c in changes)

# Auto-select if --change specified or only one change with checkpoints/progress
selected_change = None
if selected:
    for c in changes:
        if c['name'] == selected:
            selected_change = c['name']
            break
elif len(changes) == 1:
    selected_change = changes[0]['name']
elif has_checkpoints or has_partial_progress:
    candidates = [c for c in changes if c['total_checkpoints'] > 0 or c.get('phase1_interim') is not None or len(c.get('progress_files', [])) > 0]
    if len(candidates) == 1:
        selected_change = candidates[0]['name']

# Compute recovery options for selected change
recovery_options = {'continue': None, 'specify_range': [], 'reset': {'phase': 1}}
recommended_phase = 1

if selected_change:
    sc = None
    for c in changes:
        if c['name'] == selected_change:
            sc = c
            break
    if sc:
        has_final_checkpoints = sc['total_checkpoints'] > 0
        has_interim = sc.get('phase1_interim') is not None
        has_progress = len(sc.get('progress_files', [])) > 0
        progress_map = {pf['phase']: pf for pf in sc.get('progress_files', [])}

        if has_final_checkpoints:
            # Use first_incomplete_phase — correctly handles gaps
            fip = first_incomplete_phase(sc, phase_seq)
            if fip is not None:
                cont = {'phase': fip, 'label': phase_labels.get(fip, 'Unknown')}
                # Attach sub-step from progress file if available for this phase
                if fip in progress_map:
                    cont['sub_step'] = progress_map[fip]['step']
                recovery_options['continue'] = cont
                recommended_phase = fip
            else:
                recommended_phase = sc['last_valid_phase']  # all done

            # specify_range: only actually-completed phases (stop at last_valid, no gap phases)
            lvp = sc['last_valid_phase']
            completed_phases = []
            for p in phase_seq:
                if p > lvp:
                    break
                cs = [x for x in sc.get('checkpoint_scan', []) if x['phase'] == p]
                if cs and cs[0]['status'] in ('ok', 'warning'):
                    completed_phases.append(p)
            recovery_options['specify_range'] = completed_phases

        elif has_interim or has_progress:
            # Interim/progress only — determine correct recovery phase
            # Use the highest phase that has progress, not hardcode to 1
            recovery_phase = 1
            if has_progress:
                max_progress_phase = max(pf['phase'] for pf in sc.get('progress_files', []))
                # Only use if this phase is in the mode's sequence
                if max_progress_phase in phase_seq:
                    recovery_phase = max_progress_phase
            cont = {'phase': recovery_phase, 'label': phase_labels.get(recovery_phase, 'Unknown')}
            if recovery_phase in progress_map:
                cont['sub_step'] = progress_map[recovery_phase]['step']
            if has_interim and recovery_phase == 1:
                cont['interim_stage'] = sc['phase1_interim']['stage']
            recovery_options['continue'] = cont
            recommended_phase = recovery_phase

# --- Compute git_risk_level ---
# rebase_in_progress or merge_in_progress → high; has fixup → low; else → none
if git_state.get('rebase_in_progress') or git_state.get('merge_in_progress'):
    git_risk_level = 'high'
elif has_fixup_commits:
    git_risk_level = 'low'
else:
    git_risk_level = 'none'

# --- Compute auto_continue_eligible ---
# Conditions: exactly one clear recoverable candidate + no multi-candidate ambiguity
#           + no dangerous git state (rebase/merge) + recovery path is non-destructive continue
auto_continue_eligible = False
recovery_interaction_required = True

if selected_change is not None and recovery_options.get('continue') is not None:
    # Single candidate determined (no ambiguity)
    num_candidates = len([c for c in changes if c['total_checkpoints'] > 0 or c.get('phase1_interim') is not None or len(c.get('progress_files', [])) > 0])
    no_ambiguity = (num_candidates <= 1) or (selected is not None)
    no_dangerous_git = git_risk_level != 'high'
    is_continue_path = True  # recovery_options.continue exists

    if no_ambiguity and no_dangerous_git and is_continue_path and auto_continue_cfg:
        auto_continue_eligible = True
        recovery_interaction_required = False

result = {
    'status': 'ok',
    'has_checkpoints': has_checkpoints or has_partial_progress,
    'changes': changes,
    'selected_change': selected_change,
    'recommended_recovery_phase': recommended_phase,
    'recovery_options': recovery_options,
    'git_state': git_state,
    'lock_file': lock_file,
    'effective_mode': mode,
    'has_fixup_commits': has_fixup_commits,
    'fixup_commit_count': fixup_commit_count,
    'recovery_interaction_required': recovery_interaction_required,
    'auto_continue_eligible': auto_continue_eligible,
    'git_risk_level': git_risk_level
}

print(json.dumps(result, ensure_ascii=False))
" "$CHANGES_JSON" "$MODE" "$SELECTED_CHANGE" "$LOCK_JSON" "$GIT_STATE" "$HAS_FIXUP_COMMITS" "$FIXUP_COMMIT_COUNT" "$AUTO_CONTINUE_SINGLE_CANDIDATE" 2>/dev/null)

if [ -n "$RESULT_JSON" ]; then
  echo "$RESULT_JSON"
else
  echo '{"status":"error","message":"Failed to compute recovery decision"}'
fi

exit 0
