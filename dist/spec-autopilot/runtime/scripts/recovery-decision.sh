#!/usr/bin/env bash
# recovery-decision.sh — Deterministic recovery scanning script
#
# Usage: recovery-decision.sh <changes_dir> <mode> [--change <name>]
# Exit: 0 (always — never blocks)
# Output: JSON on stdout
#
# Pure read-only: does NOT modify any files or git state.
# Scans checkpoints, lock file, git state, state-snapshot.json, and computes recovery options.
#
# v7.0:
#   - 读取 state-snapshot.json 作为首要恢复控制态
#   - 输出 recovery_source 字段，优先级:
#     snapshot hash 有效 → "snapshot_resume", checkpoint → "checkpoint_resume",
#     progress → "progress_resume", 无 → "fresh"
#   - checkpoint 扫描只作为灾备 fallback，不再与 snapshot 同级
#   - hash 有效时恢复只走 snapshot 路径
#   - 输出 resume_from_phase, discarded_artifacts, replay_required_tasks,
#     recovery_reason, recovery_confidence
#   - Hash consistency verification for fail-closed recovery
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
  true | True | 1 | yes) AUTO_CONTINUE_SINGLE_CANDIDATE="true" ;;
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
GIT_STATE='{"rebase_in_progress":false,"merge_in_progress":false,"worktree_residuals":[],"uncommitted_changes":false}'
if [ -d "$PROJECT_ROOT/.git" ] 2>/dev/null; then
  REBASE_IN_PROGRESS=false
  MERGE_IN_PROGRESS=false
  WORKTREE_RESIDUALS="[]"
  UNCOMMITTED_CHANGES=false

  [ -d "$PROJECT_ROOT/.git/rebase-merge" ] || [ -d "$PROJECT_ROOT/.git/rebase-apply" ] && REBASE_IN_PROGRESS=true
  [ -f "$PROJECT_ROOT/.git/MERGE_HEAD" ] && MERGE_IN_PROGRESS=true

  # v5.8: Check for uncommitted changes (worktree recovery consistency)
  if command -v git &>/dev/null; then
    if ! git -C "$PROJECT_ROOT" diff --quiet 2>/dev/null || ! git -C "$PROJECT_ROOT" diff --cached --quiet 2>/dev/null; then
      UNCOMMITTED_CHANGES=true
    fi
  fi

  # Detect worktree residuals (v5.1.51: use python3 for safe JSON with spaces in paths)
  if command -v git &>/dev/null; then
    WORKTREE_RESIDUALS=$(git -C "$PROJECT_ROOT" worktree list 2>/dev/null | grep "autopilot-task" | awk '{print $1}' | python3 -c "
import json, sys
paths = [line.strip() for line in sys.stdin if line.strip()]
print(json.dumps(paths))
" 2>/dev/null) || WORKTREE_RESIDUALS="[]"
    [ -z "$WORKTREE_RESIDUALS" ] && WORKTREE_RESIDUALS="[]"
  fi

  GIT_STATE="{\"rebase_in_progress\":${REBASE_IN_PROGRESS},\"merge_in_progress\":${MERGE_IN_PROGRESS},\"worktree_residuals\":${WORKTREE_RESIDUALS},\"uncommitted_changes\":${UNCOMMITTED_CHANGES}}"
fi

# --- Detect fixup commits (scoped to current session, not entire history) ---
HAS_FIXUP_COMMITS=false
FIXUP_COMMIT_COUNT=0
ANCHOR_SHA=""
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
    FIXUP_COMMIT_COUNT=$(git -C "$PROJECT_ROOT" log --oneline --format='%s' "${ANCHOR_SHA}..HEAD" 2>/dev/null | grep -c "^fixup! " 2>/dev/null) || FIXUP_COMMIT_COUNT=0
  else
    # No valid anchor — clear it and fall back to last 50 commits
    ANCHOR_SHA=""
    FIXUP_COMMIT_COUNT=$(git -C "$PROJECT_ROOT" log --oneline --format='%s' -50 2>/dev/null | grep -c "^fixup! " 2>/dev/null) || FIXUP_COMMIT_COUNT=0
  fi
  [ "$FIXUP_COMMIT_COUNT" -gt 0 ] && HAS_FIXUP_COMMITS=true
fi

# --- Scan all change directories ---
CHANGES_JSON=$(python3 -c "
import json, sys, os, glob

changes_dir = sys.argv[1]
mode = sys.argv[2]
scripts_dir = sys.argv[3] if len(sys.argv) > 3 else ''

# import _phase_graph for consistent phase sequences
phases = None
if scripts_dir:
    try:
        import importlib.util
        _pg_spec = importlib.util.spec_from_file_location('_phase_graph', os.path.join(scripts_dir, '_phase_graph.py'))
        if _pg_spec and _pg_spec.loader:
            _pg = importlib.util.module_from_spec(_pg_spec)
            _pg_spec.loader.exec_module(_pg)
            phases = _pg.get_phase_sequence(mode)
    except Exception:
        pass

if phases is None:
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

    # v7.0: 读取 state-snapshot.json（如果可用）
    state_snapshot = None
    snapshot_file = os.path.join(change_path, 'context', 'state-snapshot.json')
    if os.path.isfile(snapshot_file):
        try:
            import hashlib
            with open(snapshot_file) as fh:
                sdata = json.load(fh)
            stored_hash = sdata.get('snapshot_hash', '')
            verify_data = {k: v for k, v in sdata.items() if k != 'snapshot_hash'}
            verify_content = json.dumps(verify_data, sort_keys=True, ensure_ascii=False)
            computed_hash = hashlib.sha256(verify_content.encode('utf-8')).hexdigest()[:16]
            hash_valid = (computed_hash == stored_hash) if stored_hash else False
            state_snapshot = {
                'exists': True,
                'hash_valid': hash_valid,
                'schema_version': sdata.get('schema_version', '6.0'),
                'snapshot_hash': stored_hash,
                'gate_frontier': sdata.get('gate_frontier', 0),
                'next_action': sdata.get('next_action', {}),
                'requirement_packet_hash': sdata.get('requirement_packet_hash'),
                'last_completed_phase': sdata.get('last_completed_phase', 0),
                # v7.0 新增字段
                'mode': sdata.get('mode') or sdata.get('execution_mode', 'full'),
                'current_phase': sdata.get('current_phase'),
                'executed_phases': sdata.get('executed_phases', []),
                'skipped_phases': sdata.get('skipped_phases', []),
                'recovery_source': sdata.get('recovery_source', 'fresh'),
                'recovery_reason': sdata.get('recovery_reason'),
                'resume_from_phase': sdata.get('resume_from_phase'),
                'discarded_artifacts': sdata.get('discarded_artifacts', []),
                'replay_required_tasks': sdata.get('replay_required_tasks', []),
                'report_state': sdata.get('report_state'),
                'active_agents': sdata.get('active_agents', []),
                'active_tasks': sdata.get('active_tasks', []),
                'model_routing': sdata.get('model_routing'),
                'recovery_confidence': sdata.get('recovery_confidence', 'high'),
            }
        except Exception:
            state_snapshot = {'exists': True, 'hash_valid': False, 'schema_version': '', 'snapshot_hash': '', 'gate_frontier': 0, 'next_action': {}, 'requirement_packet_hash': None, 'last_completed_phase': 0, 'mode': 'full', 'current_phase': None, 'executed_phases': [], 'skipped_phases': [], 'recovery_source': 'fresh', 'recovery_reason': None, 'resume_from_phase': None, 'discarded_artifacts': [], 'replay_required_tasks': [], 'report_state': None, 'active_agents': [], 'active_tasks': [], 'model_routing': None, 'recovery_confidence': 'low'}

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
            'checkpoint_scan': [],
            'state_snapshot': state_snapshot,
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
        'checkpoint_scan': checkpoint_scan,
        'state_snapshot': state_snapshot,
    })

print(json.dumps(changes))
" "$CHANGES_DIR" "$MODE" "$SCRIPT_DIR" 2>/dev/null) || CHANGES_JSON="[]"

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
anchor_sha = sys.argv[9] if len(sys.argv) > 9 and sys.argv[9] else None
scripts_dir = sys.argv[10] if len(sys.argv) > 10 else ''

# import _phase_graph for consistent phase sequences
phase_seq = None
if scripts_dir:
    try:
        import importlib.util, os
        _pg_spec = importlib.util.spec_from_file_location('_phase_graph', os.path.join(scripts_dir, '_phase_graph.py'))
        if _pg_spec and _pg_spec.loader:
            _pg = importlib.util.module_from_spec(_pg_spec)
            _pg_spec.loader.exec_module(_pg)
            phase_seq = _pg.get_phase_sequence(mode)
    except Exception:
        pass

if phase_seq is None:
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
    Handles gaps correctly: P1=ok, P2=ok, P3=missing, P4=ok -> returns 3 (the gap).\"\"\"
    for p in seq:
        cs = [x for x in change_data.get('checkpoint_scan', []) if x['phase'] == p]
        if not cs or cs[0]['status'] not in ('ok', 'warning'):
            return p
    return None  # all done

def phase5_tasks_incomplete(change_data):
    \"\"\"Check if Phase 5 has incomplete tasks.\"\"\"
    for pf in change_data.get('progress_files', []):
        if pf['phase'] == 5 and pf['status'] == 'in_progress':
            return True
    return False

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
# v7.0: 恢复元数据（含 recovery_source 优先级逻辑）
resume_from_phase = 1
discarded_artifacts = []
replay_required_tasks = []
recovery_reason = 'fresh_start'
recovery_confidence = 'high'
# v7.0: recovery_source 优先级:
#   snapshot hash 有效 -> snapshot_resume
#   checkpoint 存在 -> checkpoint_resume (灾备 fallback)
#   progress 存在 -> progress_resume
#   无 -> fresh
recovery_source = 'fresh'

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
        state_snap = sc.get('state_snapshot')

        # v7.0: snapshot hash 有效 → 恢复只走 snapshot 路径（首要路径）
        if state_snap and state_snap.get('exists') and state_snap.get('hash_valid'):
            snap_next = state_snap.get('next_action', {}).get('phase')
            snap_gate = state_snap.get('gate_frontier', 0)
            if snap_next is not None:
                cont = {'phase': snap_next, 'label': phase_labels.get(snap_next, 'Unknown')}
                if snap_next in progress_map:
                    cont['sub_step'] = progress_map[snap_next]['step']
                recovery_options['continue'] = cont
                recommended_phase = snap_next
                resume_from_phase = snap_next
                recovery_reason = 'state_snapshot_resume'
                recovery_confidence = 'high'
                recovery_source = 'snapshot_resume'
            # specify_range from snapshot gate_frontier
            completed_phases = []
            for p in phase_seq:
                if p > snap_gate:
                    break
                completed_phases.append(p)
            recovery_options['specify_range'] = completed_phases

        elif has_final_checkpoints:
            # v7.0: checkpoint 扫描作为灾备 fallback（snapshot 不可用时）
            # Use first_incomplete_phase — correctly handles gaps
            fip = first_incomplete_phase(sc, phase_seq)
            if fip is not None:
                cont = {'phase': fip, 'label': phase_labels.get(fip, 'Unknown')}
                # Attach sub-step from progress file if available for this phase
                if fip in progress_map:
                    cont['sub_step'] = progress_map[fip]['step']
                recovery_options['continue'] = cont
                recommended_phase = fip
                resume_from_phase = fip
                recovery_reason = 'checkpoint_resume'
                recovery_confidence = 'medium' if sc.get('has_gaps') else 'high'
                recovery_source = 'checkpoint_resume'
            else:
                recommended_phase = sc['last_valid_phase']  # all done
                resume_from_phase = sc['last_valid_phase']
                recovery_reason = 'all_complete'

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
            resume_from_phase = recovery_phase
            recovery_reason = 'progress_resume'
            recovery_confidence = 'medium'
            recovery_source = 'progress_resume'

        # v7.0: Compute discarded_artifacts (phases after resume point that have artifacts)
        for p in phase_seq:
            if p >= resume_from_phase:
                cs_list = [x for x in sc.get('checkpoint_scan', []) if x['phase'] == p]
                if cs_list and cs_list[0].get('file') and cs_list[0]['status'] not in ('ok', 'warning'):
                    discarded_artifacts.append({'phase': p, 'file': cs_list[0]['file'], 'reason': f'Phase {p} incomplete/failed'})

        # v7.0: Compute replay_required_tasks
        if resume_from_phase == 5 and phase5_tasks_incomplete(sc):
            for pf in sc.get('progress_files', []):
                if pf['phase'] == 5 and pf['status'] == 'in_progress':
                    replay_required_tasks.append({'phase': 5, 'step': pf['step'], 'reason': 'Phase 5 task incomplete'})

        # v7.0: snapshot hash 不一致时 fail-closed
        if state_snap and state_snap.get('exists') and not state_snap.get('hash_valid'):
            recovery_confidence = 'low'
            recovery_reason = 'snapshot_hash_mismatch'
            recovery_source = 'fresh'  # hash 失败时不信任 snapshot，降级为 fresh

# --- Compute git_risk_level ---
# rebase_in_progress or merge_in_progress -> high; worktree_residuals -> medium; has fixup -> low; else -> none
if git_state.get('rebase_in_progress') or git_state.get('merge_in_progress'):
    git_risk_level = 'high'
elif git_state.get('worktree_residuals', []):
    git_risk_level = 'medium'
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
    num_candidates = len([c for c in changes if c['total_checkpoints'] > 0 or c.get('phase1_interim') is not None])
    no_ambiguity = (num_candidates <= 1) or (selected is not None)
    no_git_risk = git_risk_level == 'none'
    is_continue_path = True  # recovery_options.continue exists

    if no_ambiguity and no_git_risk and is_continue_path and auto_continue_cfg:
        auto_continue_eligible = True
        recovery_interaction_required = False

# v7.0: Override auto_continue if snapshot hash failed
if recovery_confidence == 'low':
    auto_continue_eligible = False
    recovery_interaction_required = True

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
    'fixup_squash_safe': has_fixup_commits and git_risk_level != 'high' and bool(anchor_sha) and not git_state.get('rebase_in_progress', False) and not git_state.get('merge_in_progress', False) and not git_state.get('worktree_residuals', []),
    'anchor_sha': anchor_sha,
    'anchor_needs_rebuild': bool(has_fixup_commits) and not bool(anchor_sha),
    'recovery_interaction_required': recovery_interaction_required,
    'auto_continue_eligible': auto_continue_eligible,
    'git_risk_level': git_risk_level,
    # v7.0: 增强恢复元数据（含 recovery_source）
    'recovery_source': recovery_source,
    'resume_from_phase': resume_from_phase,
    'discarded_artifacts': discarded_artifacts,
    'replay_required_tasks': replay_required_tasks,
    'recovery_reason': recovery_reason,
    'recovery_confidence': recovery_confidence,
}

print(json.dumps(result, ensure_ascii=False))
" "$CHANGES_JSON" "$MODE" "$SELECTED_CHANGE" "$LOCK_JSON" "$GIT_STATE" "$HAS_FIXUP_COMMITS" "$FIXUP_COMMIT_COUNT" "$AUTO_CONTINUE_SINGLE_CANDIDATE" "$ANCHOR_SHA" "$SCRIPT_DIR" 2>/dev/null)

if [ -n "$RESULT_JSON" ]; then
  echo "$RESULT_JSON"
else
  echo '{"status":"error","message":"Failed to compute recovery decision"}'
fi

exit 0
