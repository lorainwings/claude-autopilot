#!/usr/bin/env bash
# reinject-state-after-compact.sh
# Hook: SessionStart(compact)
# Purpose: After context compaction, re-inject saved autopilot state into Claude's context.
#
# Official guidance (hooks-guide):
#   "Use a SessionStart hook with a compact matcher to re-inject critical context
#    after every compaction."
#
# v7.0: Prioritizes state-snapshot.json (统一控制面工件) over autopilot-state.md.
#        Verifies snapshot_hash consistency before injecting structured state.
#        Supports v7.0 新增字段: mode, current_phase, executed_phases, skipped_phases,
#        recovery_source, report_state, active_agents, model_routing 等.
#        Falls back to markdown only if JSON is missing or corrupted.

set -uo pipefail

# --- Source shared utilities ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

# --- Determine project root (prefer stdin.cwd → git toplevel → pwd) ---
PROJECT_ROOT=""
if [ ! -t 0 ]; then
  _STDIN_DATA=$(cat)
  _STDIN_CWD=$(echo "$_STDIN_DATA" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
  if [ -n "$_STDIN_CWD" ]; then
    PROJECT_ROOT=$(git -C "$_STDIN_CWD" rev-parse --show-toplevel 2>/dev/null || echo "$_STDIN_CWD")
  fi
fi
[ -n "$PROJECT_ROOT" ] || PROJECT_ROOT="$(resolve_project_root)"
CHANGES_DIR="$PROJECT_ROOT/openspec/changes"

# --- Project relevance guard: non-autopilot projects exit early ---
is_autopilot_project "$PROJECT_ROOT" || exit 0

if [ ! -d "$CHANGES_DIR" ]; then
  exit 0
fi

# --- Find active change directory ---
# Priority 1: Use lock file to identify the active change (reliable)
CHANGE_DIR=""
STATE_FILE=""
SNAPSHOT_JSON=""
LOCK_FILE="$CHANGES_DIR/.autopilot-active"
if [ -f "$LOCK_FILE" ]; then
  ACTIVE_NAME=$(parse_lock_file "$LOCK_FILE")
  if [ -n "$ACTIVE_NAME" ] && [ -d "$CHANGES_DIR/$ACTIVE_NAME" ]; then
    CHANGE_DIR="$CHANGES_DIR/$ACTIVE_NAME"
    candidate_md="$CHANGE_DIR/context/autopilot-state.md"
    candidate_json="$CHANGE_DIR/context/state-snapshot.json"
    [ -f "$candidate_md" ] && STATE_FILE="$candidate_md"
    [ -f "$candidate_json" ] && SNAPSHOT_JSON="$candidate_json"
  fi
fi

# Priority 2: Fallback to mtime-based search (when lock file missing)
if [ -z "$STATE_FILE" ] && [ -z "$SNAPSHOT_JSON" ]; then
  LATEST_MTIME=0
  for state in "$CHANGES_DIR"/*/context/autopilot-state.md; do
    [ -f "$state" ] || continue
    mtime=$(stat -f "%m" "$state" 2>/dev/null || stat -c "%Y" "$state" 2>/dev/null || echo 0)
    if [ "$mtime" -gt "$LATEST_MTIME" ]; then
      LATEST_MTIME=$mtime
      STATE_FILE="$state"
      CHANGE_DIR="$(dirname "$(dirname "$state")")"
    fi
  done
  # Also check for state-snapshot.json in the same change dir
  if [ -n "$CHANGE_DIR" ] && [ -f "$CHANGE_DIR/context/state-snapshot.json" ]; then
    SNAPSHOT_JSON="$CHANGE_DIR/context/state-snapshot.json"
  fi
fi

if [ -z "$STATE_FILE" ] && [ -z "$SNAPSHOT_JSON" ]; then
  exit 0
fi

# --- v7.0: 优先使用结构化 state-snapshot.json（主路径）---
SNAPSHOT_VALID=false
if [ -n "$SNAPSHOT_JSON" ] && [ -f "$SNAPSHOT_JSON" ] && command -v python3 &>/dev/null; then
  SNAPSHOT_OUTPUT=$(python3 -c "
import json, sys, hashlib

snapshot_file = sys.argv[1]
try:
    with open(snapshot_file) as f:
        data = json.load(f)

    # 验证 schema_version（兼容 6.0 和 7.0）
    sv = data.get('schema_version', '')
    if sv not in ('6.0', '7.0', '7.1'):
        print('INVALID:schema_version_mismatch', file=sys.stderr)
        sys.exit(1)

    # 验证 snapshot_hash 一致性
    stored_hash = data.get('snapshot_hash', '')
    if not stored_hash:
        print('INVALID:no_snapshot_hash', file=sys.stderr)
        sys.exit(1)

    # 重新计算 hash（排除 snapshot_hash 字段本身）
    verify_data = {k: v for k, v in data.items() if k != 'snapshot_hash'}
    verify_content = json.dumps(verify_data, sort_keys=True, ensure_ascii=False)
    computed_hash = hashlib.sha256(verify_content.encode('utf-8')).hexdigest()[:16]

    if computed_hash != stored_hash:
        print(f'INVALID:hash_mismatch stored={stored_hash} computed={computed_hash}', file=sys.stderr)
        sys.exit(1)

    # 提取结构化字段
    change_name = data.get('change_name', 'unknown')
    # v7.0: 优先使用 'mode' 字段，回退到 'execution_mode'
    mode = data.get('mode') or data.get('execution_mode', 'full')
    gate_frontier = data.get('gate_frontier', 0)
    last_completed = data.get('last_completed_phase', 0)
    next_action = data.get('next_action', {})
    next_phase = next_action.get('phase', 1)
    anchor_sha = data.get('anchor_sha') or ''
    req_hash = data.get('requirement_packet_hash') or ''
    phase_results = data.get('phase_results', {})
    active_tasks = data.get('active_tasks', [])
    tasks_progress = data.get('tasks_progress', {})
    phase5_tasks = data.get('phase5_task_details', [])
    snapshot_hash = stored_hash

    # v7.0 新增字段（向后兼容：缺失时提供默认值）
    current_phase = data.get('current_phase', next_phase)
    executed_phases = data.get('executed_phases', [])
    skipped_phases = data.get('skipped_phases', [])
    recovery_source_saved = data.get('recovery_source', 'fresh')
    recovery_reason = data.get('recovery_reason')
    resume_from_phase = data.get('resume_from_phase')
    discarded_artifacts = data.get('discarded_artifacts', [])
    replay_required_tasks = data.get('replay_required_tasks', [])
    report_state = data.get('report_state')
    active_agents = data.get('active_agents', [])
    model_routing = data.get('model_routing')
    recovery_confidence = data.get('recovery_confidence', 'high')

    # v7.0+: 验证所有新字段的存在性（v7.0+ schema 需要）
    if sv in ('7.0', '7.1'):
        required_v7_fields = ['mode', 'current_phase', 'executed_phases', 'skipped_phases',
                              'recovery_source', 'report_state', 'active_agents', 'active_tasks',
                              'discarded_artifacts', 'replay_required_tasks']
        missing_fields = [f for f in required_v7_fields if f not in data]
        if missing_fields:
            print(f'WARNING: v7.0 schema missing fields: {missing_fields}', file=sys.stderr)

    # v7.0: 恢复时将 recovery_source 设置为 snapshot_resume
    actual_recovery_source = 'snapshot_resume'

    print('=== AUTOPILOT STATE RESTORED (STRUCTURED) ===')
    print()
    print(f'Structured recovery from state-snapshot.json v{sv} (hash={snapshot_hash})')
    print(f'Recovery source: {actual_recovery_source} (saved as: {recovery_source_saved})')
    print()
    print(f'## Control State')
    print(f'- Change: {change_name}')
    print(f'- Mode: {mode}')
    print(f'- Current phase: {current_phase}')
    print(f'- Gate frontier: Phase {gate_frontier}')
    print(f'- Last completed: Phase {last_completed}')
    print(f'- Next action: Phase {next_phase} ({next_action.get(\"type\", \"resume\")})')
    print(f'- Recovery source: {actual_recovery_source}')
    print(f'- Recovery confidence: {recovery_confidence}')
    if req_hash:
        print(f'- Requirement packet hash: {req_hash}')
    if anchor_sha:
        print(f'- Anchor SHA: {anchor_sha}')
    print(f'- Snapshot hash: {snapshot_hash} (verified)')
    print()

    # v7.0: 已执行/跳过阶段
    if executed_phases:
        print(f'## Executed Phases: {executed_phases}')
        print()
    if skipped_phases:
        print(f'## Skipped Phases (mode={mode}): {skipped_phases}')
        print()

    # Phase results table
    print('## Phase Results')
    print('| Phase | Status | Summary |')
    print('|-------|--------|---------|')
    phase_names = {'1': 'Requirements', '2': 'OpenSpec', '3': 'FF Generate', '4': 'Test Design', '5': 'Implementation', '6': 'Test Report', '7': 'Archive'}
    for pnum_str in sorted(phase_results.keys(), key=int):
        pr = phase_results[pnum_str]
        name = phase_names.get(pnum_str, f'Phase {pnum_str}')
        status = pr.get('status', 'pending')
        summary = (pr.get('summary', '') or '')[:80]
        print(f'| {pnum_str}. {name} | {status} | {summary or \"-\"} |')
    print()

    # v7.0: Report state
    if report_state and any(v for v in report_state.values() if v):
        print('## Report State')
        if report_state.get('report_format'):
            print(f'- Format: {report_state[\"report_format\"]}')
        if report_state.get('report_path'):
            print(f'- Path: {report_state[\"report_path\"]}')
        if report_state.get('report_url'):
            print(f'- URL: {report_state[\"report_url\"]}')
        if report_state.get('allure_results_dir'):
            print(f'- Allure results: {report_state[\"allure_results_dir\"]}')
        if report_state.get('suite_results'):
            print(f'- Suite results: available')
        anomalies = report_state.get('anomaly_alerts', [])
        if anomalies:
            print(f'- Anomaly alerts: {len(anomalies)} alert(s)')
        print()

    # Active tasks
    if active_tasks:
        print('## Active Tasks (in-progress)')
        for at in active_tasks:
            print(f'- Phase {at[\"phase\"]}: sub-step={at[\"step\"]}')
        print()

    # v7.0: Active agents
    if active_agents:
        print('## Active Agents')
        for ag in active_agents:
            print(f'- Agent {ag.get(\"id\", \"unknown\")}: phase={ag.get(\"phase\")}, task={ag.get(\"task\")}')
        print()

    # v7.0: Model routing
    if model_routing:
        print('## Model Routing')
        if isinstance(model_routing, dict) and model_routing.get('raw_config'):
            print(f'  {model_routing[\"raw_config\"][:200]}')
        else:
            print(f'  {json.dumps(model_routing)[:200]}')
        print()

    # Task progress
    if tasks_progress.get('completed', 0) > 0 or tasks_progress.get('remaining', 0) > 0:
        print(f'## Tasks: {tasks_progress.get(\"completed\", 0)} completed, {tasks_progress.get(\"remaining\", 0)} remaining')
        print()

    # Phase 5 task details
    if phase5_tasks:
        print('## Phase 5 Task Details')
        print('| Task | Status | Summary |')
        print('|------|--------|---------|')
        for td in phase5_tasks:
            print(f'| {td[\"number\"]} | {td[\"status\"]} | {td.get(\"summary\", \"-\")} |')
        print()

    # v7.0: Discarded artifacts / replay required tasks
    if discarded_artifacts:
        print('## Discarded Artifacts')
        for da in discarded_artifacts:
            print(f'- Phase {da.get(\"phase\")}: {da.get(\"file\")} ({da.get(\"reason\", \"\")})')
        print()
    if replay_required_tasks:
        print('## Replay Required Tasks')
        for rt in replay_required_tasks:
            print(f'- Phase {rt.get(\"phase\")}: step={rt.get(\"step\")} ({rt.get(\"reason\", \"\")})')
        print()

    print('=== DETERMINISTIC RECOVERY INSTRUCTION ===')
    print()
    print(f'ACTION REQUIRED: Resume autopilot from Phase {next_phase} (mode: {mode}, change: {change_name}).')
    print(f'Recovery source: {actual_recovery_source}')
    if active_tasks:
        at = active_tasks[-1]
        print(f'NOTE: Phase {at[\"phase\"]} was in-progress at sub-step \"{at[\"step\"]}\" when compaction occurred.')
    print()
    print('Steps:')
    print(f'1. Re-read config: .claude/autopilot.config.yaml')
    print(f'2. Call Skill(spec-autopilot:autopilot-gate) for Phase {next_phase}')
    print(f'3. If gate passes, call Skill(spec-autopilot:autopilot-dispatch) and dispatch Phase {next_phase}')
    print(f'4. DO NOT re-execute any Phase marked ok or warning in the Phase Results table above')
    if next_phase == 5:
        print(f'5. Phase 5 in-progress: scan phase5-tasks/ for task-level recovery point before dispatching')
    print()
    print('=== END AUTOPILOT STATE ===')
    print()
except Exception as e:
    print(f'INVALID:{e}', file=sys.stderr)
    sys.exit(1)
" "$SNAPSHOT_JSON" 2>/dev/null)

  if [ $? -eq 0 ] && [ -n "$SNAPSHOT_OUTPUT" ]; then
    SNAPSHOT_VALID=true
    echo ""
    echo "$SNAPSHOT_OUTPUT"
    exit 0
  fi
fi

# --- Fallback: use autopilot-state.md (legacy path) ---
if [ -z "$STATE_FILE" ] || [ ! -f "$STATE_FILE" ]; then
  # v6.0: If snapshot JSON existed but was invalid, warn about fail-closed
  if [ -n "$SNAPSHOT_JSON" ] && [ -f "$SNAPSHOT_JSON" ]; then
    echo ""
    echo "=== WARNING: SNAPSHOT HASH VERIFICATION FAILED ==="
    echo ""
    echo "state-snapshot.json exists but failed integrity check."
    echo "Falling back to autopilot-state.md (legacy markdown recovery)."
    echo "Recovery confidence: LOW — recommend manual verification before continuing."
    echo ""
  fi
  exit 0
fi

echo ""
echo "=== AUTOPILOT STATE RESTORED AFTER CONTEXT COMPACTION (LEGACY) ==="
echo ""

# v6.0: Warn if structured snapshot was expected but failed
if [ -n "$SNAPSHOT_JSON" ] && [ -f "$SNAPSHOT_JSON" ]; then
  echo "WARNING: state-snapshot.json failed hash verification. Using legacy markdown recovery."
  echo "Recovery confidence: MEDIUM — state-snapshot.json should be the primary control state."
  echo ""
fi

cat "$STATE_FILE"

# v5.3: Output all phase context snapshots for reasoning continuity (v5.8: all snapshots, not just latest)
SNAPSHOTS_DIR="$(dirname "$STATE_FILE")/phase-context-snapshots"
if [ -d "$SNAPSHOTS_DIR" ]; then
  SNAP_COUNT=0
  TOTAL_CHARS=0
  MAX_TOTAL_CHARS=4000 # Total budget across all snapshots
  for snap in "$SNAPSHOTS_DIR"/phase-*-context.md; do
    [ -f "$snap" ] || continue
    SNAP_COUNT=$((SNAP_COUNT + 1))
  done

  if [ "$SNAP_COUNT" -gt 0 ]; then
    echo ""
    echo "--- Phase Context Snapshots ($SNAP_COUNT phases) ---"
    echo ""
    for snap in $(ls -1 "$SNAPSHOTS_DIR"/phase-*-context.md 2>/dev/null | sort); do
      [ -f "$snap" ] || continue
      SNAP_SIZE=$(wc -c <"$snap" 2>/dev/null || echo 0)
      REMAINING=$((MAX_TOTAL_CHARS - TOTAL_CHARS))
      if [ "$REMAINING" -le 100 ]; then
        echo "... (remaining snapshots truncated, see files in phase-context-snapshots/)"
        break
      fi
      echo "### $(basename "$snap")"
      if [ "$SNAP_SIZE" -le "$REMAINING" ]; then
        cat "$snap"
        TOTAL_CHARS=$((TOTAL_CHARS + SNAP_SIZE))
      else
        head -c "$REMAINING" "$snap"
        TOTAL_CHARS=$MAX_TOTAL_CHARS
        echo ""
        echo "... (truncated)"
      fi
      echo ""
    done
    echo "--- End Phase Context Snapshots ---"
  fi
fi

# v5.8: Deterministic recovery instruction — tell orchestrator exactly what to do next
echo ""
echo "=== DETERMINISTIC RECOVERY INSTRUCTION ==="
echo ""
# Extract next_phase from state file (POSIX-compatible — no grep -P which is GNU-only)
NEXT_PHASE=$(sed -n 's/.*\*\*Next phase to execute\*\*: \([0-9][0-9]*\).*/\1/p' "$STATE_FILE" 2>/dev/null | head -1)
EXEC_MODE=$(sed -n 's/.*\*\*Execution mode\*\*: `\([a-zA-Z_]*\)`.*/\1/p' "$STATE_FILE" 2>/dev/null | head -1)
[ -z "$EXEC_MODE" ] && EXEC_MODE="full"
CHANGE_NAME_RESTORE=$(sed -n 's/.*\*\*Active change\*\*: `\([^`]*\)`.*/\1/p' "$STATE_FILE" 2>/dev/null | head -1)
# v5.9: Extract in-progress phase sub-step for fine-grained recovery
IN_PROGRESS_PHASE=$(sed -n 's/.*\*\*Current in-progress phase\*\*: \([0-9][0-9]*\).*/\1/p' "$STATE_FILE" 2>/dev/null | head -1)
IN_PROGRESS_SUBSTEP=$(sed -n 's/.*\*\*Current in-progress phase\*\*: [0-9]* (sub-step: \(.*\))/\1/p' "$STATE_FILE" 2>/dev/null | head -1)

if [ -n "$NEXT_PHASE" ]; then
  echo "ACTION REQUIRED: Resume autopilot from Phase ${NEXT_PHASE} (mode: ${EXEC_MODE}, change: ${CHANGE_NAME_RESTORE})."
  if [ -n "$IN_PROGRESS_PHASE" ] && [ "$IN_PROGRESS_PHASE" = "$NEXT_PHASE" ] && [ -n "$IN_PROGRESS_SUBSTEP" ]; then
    echo "NOTE: Phase ${IN_PROGRESS_PHASE} was in-progress at sub-step '${IN_PROGRESS_SUBSTEP}' when compaction occurred."
  fi
  echo ""
  echo "Steps:"
  echo "1. Re-read config: .claude/autopilot.config.yaml"
  echo "2. Call Skill(spec-autopilot:autopilot-gate) for Phase ${NEXT_PHASE}"
  echo "3. If gate passes, call Skill(spec-autopilot:autopilot-dispatch) and dispatch Phase ${NEXT_PHASE}"
  echo "4. DO NOT re-execute any Phase marked 'ok' or 'warning' in the Phase Status table above"
  if [ "$NEXT_PHASE" = "5" ]; then
    echo "5. Phase 5 in-progress: scan phase5-tasks/ for task-level recovery point before dispatching"
  fi
else
  echo "ACTION REQUIRED: Read autopilot-state.md above and resume from the next incomplete phase."
  echo "DO NOT re-execute completed phases."
fi

echo ""
echo "=== END AUTOPILOT STATE ==="
echo ""

exit 0
