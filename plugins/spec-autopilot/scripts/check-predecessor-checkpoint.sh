#!/usr/bin/env bash
# check-predecessor-checkpoint.sh
# Hook: PreToolUse(Task)
# Purpose: Before dispatching a sub-Agent, verify the predecessor phase checkpoint
#          exists and has status=ok/warning. Prevents phase skipping.
#
# Detection: Only processes Task calls whose prompt contains
#            <!-- autopilot-phase:N -->. All other Task calls exit 0 immediately.
#
# Output: JSON with hookSpecificOutput.permissionDecision on deny (official spec).
#         Plain exit 0 on allow.

set -uo pipefail
# NOTE: no `set -e` — we handle errors explicitly to avoid pipefail + ls crashes.

# --- Source shared utilities ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

# --- Read stdin JSON ---
STDIN_DATA=""
if [ ! -t 0 ]; then
  STDIN_DATA=$(cat)
fi

if [ -z "$STDIN_DATA" ]; then
  exit 0
fi

# --- Fast bypass Layer 0: lock file pre-check ---
# 无活跃 autopilot 会话时，跳过所有检查（纯 bash，零 python3 开销）。
# 这避免了非 autopilot Task/Agent 调用被误拦截。
# 尝试从 stdin JSON 中提取 cwd（纯 bash，适配简单路径）
PROJECT_ROOT_QUICK=$(echo "$STDIN_DATA" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
if [ -z "$PROJECT_ROOT_QUICK" ]; then
  PROJECT_ROOT_QUICK="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
if ! has_active_autopilot "$PROJECT_ROOT_QUICK"; then
  exit 0
fi

# --- Fast bypass Layer 1: prompt 首行标记检测 ---
# 仅匹配 JSON 中 prompt 字段以标记开头的情况（dispatch 协议规定标记在 prompt 开头）。
# 排除：prompt 文本内容中引用标记（代码示例、文档等）造成的误判。
if ! echo "$STDIN_DATA" | grep -q '"prompt"[[:space:]]*:[[:space:]]*"<!-- autopilot-phase:[0-9]'; then
  exit 0
fi

# --- Fast bypass Layer 1.5: background agent skip ---
# Agent/Task with run_in_background=true fires hook at launch time,
# before the agent completes. Skip validation for background dispatch.
# NOTE (by design): Phase 2/3/4/6 background dispatch bypasses ALL L2 checks here,
# including Phase 6's zero_skip_check and tasks completion check.
# These validations are guaranteed by Layer 3 (autopilot-gate Skill) which runs
# BEFORE the main thread dispatches the background Task. L2 Hook only fires at
# launch time when the agent hasn't produced output yet, so L2 cannot validate.
if echo "$STDIN_DATA" | grep -q '"run_in_background"[[:space:]]*:[[:space:]]*true'; then
  exit 0
fi

# --- Dependency check (only needed for autopilot Tasks) ---
if ! command -v python3 &>/dev/null; then
  # Cannot validate without python3 → block to be safe (fail-closed)
  cat <<'DENY_JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "python3 is required for autopilot gate hooks but not found in PATH"
  }
}
DENY_JSON
  exit 0
fi

# --- Extract project root from stdin cwd (preferred) or git fallback ---
PROJECT_ROOT=$(echo "$STDIN_DATA" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get('cwd', ''))
except Exception:
    pass
" 2>/dev/null || echo "")

if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

CHANGES_DIR="$PROJECT_ROOT/openspec/changes"

# --- Extract phase number from marker ---
TARGET_PHASE=$(echo "$STDIN_DATA" | python3 -c "
import json, sys, re
try:
    data = json.load(sys.stdin)
    prompt = data.get('tool_input', {}).get('prompt', '')
    m = re.search(r'<!--\s*autopilot-phase:(\d+)\s*-->', prompt)
    if m:
        print(m.group(1))
except Exception:
    pass
" 2>/dev/null || echo "")

# No marker → not an autopilot Task, allow immediately
if [ -z "$TARGET_PHASE" ]; then
  exit 0
fi

# --- Helper: output deny JSON and exit 0 (fail-closed) ---
deny() {
  local reason="$1"
  local json_output
  json_output=$(python3 -c "
import json, sys
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'deny',
        'permissionDecisionReason': sys.argv[1]
    }
}))
" "$reason" 2>/dev/null) || true

  if [ -n "$json_output" ]; then
    echo "$json_output"
  else
    # Fallback: hardcoded JSON if python3 fails (fail-closed, never allow)
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Autopilot gate check failed (internal error)"}}'
  fi
  exit 0
}

# --- Find active change directory (uses _common.sh) ---
# Note: trailing_slash="yes" for backward compatibility with path concatenation below

# --- Checkpoint utilities from _common.sh ---

# --- Get the last successful checkpoint phase number ---
get_last_checkpoint_phase() {
  local phase_results_dir="$1"
  local last_phase=0

  for phase_num in 1 2 3 4 5 6 7; do
    local checkpoint_file
    checkpoint_file=$(find_checkpoint "$phase_results_dir" "$phase_num")

    if [ -n "$checkpoint_file" ] && [ -f "$checkpoint_file" ]; then
      local status
      status=$(read_checkpoint_status "$checkpoint_file")
      if [ "$status" = "error" ]; then
        # Corrupted checkpoint: deny with explicit error
        deny "Checkpoint file $(basename "$checkpoint_file") contains invalid JSON. Possible file corruption. Please inspect and fix or delete the file, then retry."
        return
      fi
      if [ "$status" = "ok" ] || [ "$status" = "warning" ]; then
        last_phase=$phase_num
      fi
    fi
  done

  echo $last_phase
}

# === Read execution mode from lock file ===
get_autopilot_mode() {
  local changes_dir="$1"
  local lock_file="$changes_dir/.autopilot-active"
  if [ -f "$lock_file" ] && command -v python3 &>/dev/null; then
    python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    print(data.get('mode', 'full'))
except Exception:
    print('full')
" "$lock_file" 2>/dev/null || echo "full"
  else
    echo "full"
  fi
}

# === Main logic ===

change_dir=$(find_active_change "$CHANGES_DIR" "yes") || exit 0  # No active change, allow

phase_results_dir="${change_dir}context/phase-results"

if [ ! -d "$phase_results_dir" ]; then
  if [ "$TARGET_PHASE" -le 1 ]; then
    # Phase 1 starting fresh — no predecessor checkpoint needed
    exit 0
  else
    # Phase 2+ requires at least Phase 1 checkpoint to exist
    deny "Phase results directory not found. Phase 1 must complete before Phase $TARGET_PHASE can start."
  fi
fi

last_phase=$(get_last_checkpoint_phase "$phase_results_dir")

# --- Read execution mode (full/lite/minimal) ---
EXEC_MODE=$(get_autopilot_mode "$CHANGES_DIR")

# --- Lazy-load TDD mode (only when full mode needs it) ---
# Avoids ~50ms python3 fork for lite/minimal modes that never use TDD.
TDD_MODE=""
_get_tdd_mode() {
  if [ -z "$TDD_MODE" ]; then
    TDD_MODE=$(read_config_value "$PROJECT_ROOT" "phases.implementation.tdd_mode" "false")
  fi
  echo "$TDD_MODE"
}

# --- Define expected phase sequences per mode ---
# full:    1 → 2 → 3 → 4 → 5 → 6 → 7
# lite:    1 → 5 → 6 → 7
# minimal: 1 → 5 → 7
get_predecessor_phase() {
  local mode="$1"
  local target="$2"
  case "$mode" in
    lite)
      case "$target" in
        5) echo 1 ;;
        6) echo 5 ;;
        7) echo 6 ;;
        *) echo 0 ;;
      esac
      ;;
    minimal)
      case "$target" in
        5) echo 1 ;;
        7) echo 5 ;;
        *) echo 0 ;;
      esac
      ;;
    *)  # full
      # TDD mode check only needed for full mode (lite/minimal skip Phase 4 regardless)
      if [ "$(_get_tdd_mode)" = "true" ] && [ "$target" -eq 5 ]; then
        # TDD mode: Phase 5 depends on Phase 3 (Phase 4 skipped)
        echo 3
      elif [ "$target" -ge 2 ] && [ "$target" -le 7 ]; then
        echo $((target - 1))
      else
        echo 0
      fi
      ;;
  esac
}

PRED_PHASE=$(get_predecessor_phase "$EXEC_MODE" "$TARGET_PHASE")

# Phase 2 independent check (full mode only): verify Phase 1 checkpoint
if [ "$TARGET_PHASE" -eq 2 ]; then
  if [ "$EXEC_MODE" != "full" ]; then
    # lite/minimal skip Phase 2 entirely; Hook should never see Phase 2 dispatch
    deny "Phase 2 is skipped in $EXEC_MODE mode. This dispatch should not occur."
  fi
  phase1_file=$(find_checkpoint "$phase_results_dir" 1)
  if [ -z "$phase1_file" ] || [ ! -f "$phase1_file" ]; then
    deny "Phase 1 checkpoint not found. Phase 1 must complete before Phase 2."
  fi
  phase1_status=$(read_checkpoint_status "$phase1_file")
  if [ "$phase1_status" != "ok" ] && [ "$phase1_status" != "warning" ]; then
    deny "Phase 1 checkpoint status is '$phase1_status'. Must be ok/warning before Phase 2."
  fi
fi

# Phases 3/4 are full-mode only
if [ "$TARGET_PHASE" -eq 3 ] || [ "$TARGET_PHASE" -eq 4 ]; then
  if [ "$EXEC_MODE" != "full" ]; then
    deny "Phase $TARGET_PHASE is skipped in $EXEC_MODE mode. This dispatch should not occur."
  fi
fi

# Check sequential ordering based on mode-aware predecessor
if [ "$TARGET_PHASE" -ge 3 ]; then
  pred_file=$(find_checkpoint "$phase_results_dir" "$PRED_PHASE")
  if [ -z "$pred_file" ] || [ ! -f "$pred_file" ]; then
    deny "Cannot start Phase $TARGET_PHASE. Predecessor Phase $PRED_PHASE checkpoint not found (mode: $EXEC_MODE)."
  fi
  pred_status=$(read_checkpoint_status "$pred_file")
  if [ "$pred_status" != "ok" ] && [ "$pred_status" != "warning" ]; then
    deny "Predecessor Phase $PRED_PHASE status is '$pred_status'. Must be ok/warning before Phase $TARGET_PHASE (mode: $EXEC_MODE)."
  fi

  # v4.1: minimal mode zero_skip_check warning
  if [ "$EXEC_MODE" = "minimal" ] && [ "$TARGET_PHASE" = "7" ]; then
    local zsc_passed
    zsc_passed=$(python3 -c "
import json, sys
try:
    with open('${pred_file}') as f:
        data = json.load(f)
    zsc = data.get('zero_skip_check', {})
    print('true' if zsc.get('passed') is True else 'false')
except: print('false')
" 2>/dev/null || echo "false")
    if [ "$zsc_passed" != "true" ]; then
        echo "[WARNING] minimal mode: zero_skip_check not passed — tests may not have been verified" >&2
    fi
  fi
fi

# Special gate: Phase 5 requires Phase 4 checkpoint ONLY in full mode (non-TDD)
if [ "$TARGET_PHASE" -eq 5 ]; then
  if [ "$EXEC_MODE" = "full" ]; then
    # Check TDD mode (lazy-loaded): accept tdd_mode_override checkpoint or Phase 3
    if [ "$(_get_tdd_mode)" = "true" ]; then
      # TDD mode: Phase 4 is skipped, accept Phase 3 checkpoint or tdd_mode_override
      phase4_file=$(find_checkpoint "$phase_results_dir" 4)
      if [ -n "$phase4_file" ] && [ -f "$phase4_file" ]; then
        # Phase 4 checkpoint exists (tdd_mode_override) — check it's ok
        phase4_status=$(read_checkpoint_status "$phase4_file")
        if [ "$phase4_status" != "ok" ]; then
          deny "Phase 4 TDD override checkpoint status is '$phase4_status'. Expected 'ok'."
        fi
      else
        # No Phase 4 checkpoint — verify Phase 3 exists (predecessor in TDD mode)
        phase3_file=$(find_checkpoint "$phase_results_dir" 3)
        if [ -z "$phase3_file" ] || [ ! -f "$phase3_file" ]; then
          deny "TDD mode: Neither Phase 4 override nor Phase 3 checkpoint found. Phase 3 must complete before Phase 5."
        fi
        phase3_status=$(read_checkpoint_status "$phase3_file")
        if [ "$phase3_status" != "ok" ] && [ "$phase3_status" != "warning" ]; then
          deny "TDD mode: Phase 3 checkpoint status is '$phase3_status'. Must be ok/warning before Phase 5."
        fi
      fi
    else
      # Non-TDD full mode: require Phase 4 checkpoint
      phase4_file=$(find_checkpoint "$phase_results_dir" 4)

    if [ -z "$phase4_file" ] || [ ! -f "$phase4_file" ]; then
      deny "Phase 4 checkpoint not found. Phase 4 must complete before Phase 5."
    fi

    phase4_status=$(read_checkpoint_status "$phase4_file")

    if [ "$phase4_status" != "ok" ]; then
      deny "Phase 4 checkpoint status is '$phase4_status'. Only 'ok' is accepted (Phase 4 protocol: ok or blocked). Re-dispatch Phase 4."
    fi
    fi  # end non-TDD full mode
  else
    # lite/minimal: Phase 5 predecessor is Phase 1
    phase1_file=$(find_checkpoint "$phase_results_dir" 1)
    if [ -z "$phase1_file" ] || [ ! -f "$phase1_file" ]; then
      deny "Phase 1 checkpoint not found. Phase 1 must complete before Phase 5 (mode: $EXEC_MODE)."
    fi
    phase1_status=$(read_checkpoint_status "$phase1_file")
    if [ "$phase1_status" != "ok" ] && [ "$phase1_status" != "warning" ]; then
      deny "Phase 1 checkpoint status is '$phase1_status'. Must be ok/warning before Phase 5 (mode: $EXEC_MODE)."
    fi
  fi
fi

# Special gate: Phase 6 requires Phase 5 zero_skip_check
if [ "$TARGET_PHASE" -eq 6 ]; then
  # minimal mode skips Phase 6 entirely
  if [ "$EXEC_MODE" = "minimal" ]; then
    deny "Phase 6 is skipped in minimal mode. This dispatch should not occur."
  fi

  phase5_file=$(find_checkpoint "$phase_results_dir" 5)

  if [ -n "$phase5_file" ] && [ -f "$phase5_file" ]; then
    zero_skip_passed=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    zsc = data.get('zero_skip_check', {})
    print('true' if zsc.get('passed', False) else 'false')
except Exception:
    print('false')
" "$phase5_file" 2>/dev/null || echo "false")

    if [ "$zero_skip_passed" = "false" ]; then
      deny "Phase 5 zero_skip_check gate failed. All tests must pass with zero skips."
    fi
  fi

  # Check tasks.md completion (full/lite mode — tasks.md exists in full, phase5-task-breakdown.md in lite)
  tasks_file="${change_dir}tasks.md"
  breakdown_file="${change_dir}context/phase5-task-breakdown.md"
  actual_tasks_file=""
  if [ -f "$tasks_file" ]; then
    actual_tasks_file="$tasks_file"
  elif [ -f "$breakdown_file" ]; then
    actual_tasks_file="$breakdown_file"
  fi

  if [ -n "$actual_tasks_file" ]; then
    unchecked=$(grep -c '\- \[ \]' "$actual_tasks_file" 2>/dev/null || echo "0")
    if [ "$unchecked" -gt 0 ]; then
      deny "$(basename "$actual_tasks_file") has $unchecked incomplete tasks. All must be [x] before Phase 6."
    fi
  fi
fi

# Wall-clock timeout: Phase 5 time limit (promoted from skill-only to Hook layer)
# When TARGET_PHASE >= 5, check if Phase 5 has been running too long.
if [ "$TARGET_PHASE" -ge 5 ]; then
  phase5_start_file="${change_dir}context/phase-results/phase5-start-time.txt"
  if [ -f "$phase5_start_file" ]; then
    start_time_str=$(cat "$phase5_start_file" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$start_time_str" ]; then
      # Parse ISO-8601 timestamp to epoch seconds
      elapsed=0
      start_epoch=$(python3 -c "
import sys
from datetime import datetime, timezone
ts = sys.argv[1]
try:
    # Handle Z suffix
    ts = ts.replace('Z', '+00:00')
    dt = datetime.fromisoformat(ts)
    print(int(dt.timestamp()))
except Exception:
    print(0)
" "$start_time_str" 2>/dev/null || echo "0")

      if [ "$start_epoch" -gt 0 ] 2>/dev/null; then
        now_epoch=$(date +%s)
        elapsed=$((now_epoch - start_epoch))
        # Read timeout from config (default: 2 hours)
        timeout_hours=$(read_config_value "$PROJECT_ROOT" "phases.implementation.wall_clock_timeout_hours" "2")
        timeout_seconds=$((timeout_hours * 3600))
        if [ "$elapsed" -gt "$timeout_seconds" ]; then
          deny "Phase 5 wall-clock timeout: running for ${elapsed}s (limit: ${timeout_seconds}s / ${timeout_hours}h). Save progress and investigate."
        fi
      fi
    fi
  fi
fi

# All checks passed
exit 0
