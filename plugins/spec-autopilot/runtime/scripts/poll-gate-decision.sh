#!/usr/bin/env bash
# poll-gate-decision.sh
# v5.1 双向反控: Gate 阻断后轮询 GUI 决策响应
# Purpose: 在 gate_block 事件发射后，写入 decision-request.json 并轮询 decision.json
#          直到收到合法的 Override/Retry/Fix 指令或超时
#
# Usage:
#   poll-gate-decision.sh <change_dir> <phase> <mode> <block_reason_json>
#   change_dir: openspec/changes/<name>/ (with trailing slash)
#   phase: 0-7
#   mode: full | lite | minimal
#   block_reason_json: JSON with blocked_step, error_message etc.
#
# Output:
#   On decision found: prints decision JSON to stdout, exit 0
#   On timeout: prints timeout JSON to stdout, exit 1
#   On error: prints error to stderr, exit 2

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

CHANGE_DIR="${1:-}"
PHASE="${2:-}"
MODE="${3:-full}"
BLOCK_REASON_JSON="${4:-'{}'}"

if [ -z "$CHANGE_DIR" ] || [ -z "$PHASE" ]; then
  echo "Usage: poll-gate-decision.sh <change_dir> <phase> <mode> <block_reason_json>" >&2
  exit 2
fi

# --- Configuration ---
PROJECT_ROOT="${PROJECT_ROOT_QUICK:-$(resolve_project_root)}"
POLL_TIMEOUT=$(read_config_value "$PROJECT_ROOT" "gui.decision_poll_timeout" "300")
POLL_INTERVAL=1
GUI_PORT=$(read_config_value "$PROJECT_ROOT" "gui.port" "9527")
GUI_WS_PORT="${AUTOPILOT_WS_PORT:-$((GUI_PORT + 1))}"
START_GUI_SERVER_SCRIPT="${START_GUI_SERVER_SCRIPT:-$SCRIPT_DIR/start-gui-server.sh}"

CONTEXT_DIR="${CHANGE_DIR}context"
DECISION_REQUEST_FILE="${CONTEXT_DIR}/decision-request.json"
DECISION_FILE="${CONTEXT_DIR}/decision.json"

sanitize_project_root() {
  python3 -c "
import pathlib, sys
path = sys.argv[1]
home = str(pathlib.Path.home())
if path.startswith(home):
    path = '~' + path[len(home):]
print(path)
" "$1" 2>/dev/null || printf '%s\n' "$1"
}

gui_server_available_for_project() {
  local info_resp resp_root sanitized_root

  curl -sf --max-time 1 "http://localhost:${GUI_PORT}/api/health" >/dev/null 2>&1 || return 1
  info_resp=$(curl -sf --max-time 1 "http://localhost:${GUI_PORT}/api/info" 2>/dev/null) || return 1
  resp_root=$(printf '%s' "$info_resp" | python3 -c "import json,sys; print(json.load(sys.stdin).get('projectRoot',''))" 2>/dev/null) || resp_root=""
  [ -n "$resp_root" ] || return 1

  sanitized_root=$(sanitize_project_root "$PROJECT_ROOT")
  [ "$resp_root" = "$sanitized_root" ]
}

OVERRIDE_ALLOWED=$(python3 -c "
import json, sys

phase = int(sys.argv[1])
mode = sys.argv[2]
raw_reason = sys.argv[3]

allowed = True
if phase == 5 and mode == 'full':
    allowed = False
elif phase == 6 and mode in ('full', 'lite'):
    allowed = False

try:
    payload = json.loads(raw_reason) if raw_reason else {}
    if isinstance(payload, dict) and isinstance(payload.get('override_allowed'), bool):
        allowed = payload['override_allowed']
except Exception:
    pass

print('true' if allowed else 'false')
" "$PHASE" "$MODE" "$BLOCK_REASON_JSON" 2>/dev/null || echo "true")

# --- Step 1: Write decision-request.json ---
TIMESTAMP=$(python3 -c "from datetime import datetime,timezone; print(datetime.now(timezone.utc).isoformat())" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$CONTEXT_DIR" 2>/dev/null || true

python3 -c "
import json, sys

phase = int(sys.argv[1])
mode = sys.argv[2]
override_allowed = sys.argv[5].lower() == 'true'

# Compute denial reason (single source of truth for GUI)
override_denied_reason = ''
if not override_allowed:
    if phase == 5 and mode == 'full':
        override_denied_reason = 'Phase 4 -> 5 gate: override forbidden'
    elif phase == 6 and mode in ('full', 'lite'):
        override_denied_reason = 'Phase 5 -> 6 gate: override forbidden'
    else:
        override_denied_reason = 'Override denied by gate policy'

request = {
    'phase': phase,
    'mode': mode,
    'gate_result': 'blocked',
    'timestamp': sys.argv[3],
    'awaiting_decision': True,
    'override_allowed': override_allowed,
    'override_denied_reason': override_denied_reason,
}

# Merge block reason payload
try:
    reason = json.loads(sys.argv[4]) if sys.argv[4] else {}
    if isinstance(reason, dict):
        request.update(reason)
except (json.JSONDecodeError, ValueError):
    request['error_message'] = sys.argv[4]

with open(sys.argv[6], 'w') as f:
    json.dump(request, f, ensure_ascii=False, indent=2)
" "$PHASE" "$MODE" "$TIMESTAMP" "$BLOCK_REASON_JSON" "$OVERRIDE_ALLOWED" "$DECISION_REQUEST_FILE" 2>/dev/null

if [ $? -ne 0 ]; then
  echo "ERROR: Failed to write decision-request.json" >&2
  exit 2
fi

# --- Step 2: Emit decision_pending event to event bus ---
bash "$SCRIPT_DIR/emit-phase-event.sh" "gate_decision_pending" "$PHASE" "$MODE" \
  "{\"awaiting_decision\":true,\"timeout_seconds\":$POLL_TIMEOUT}" 2>/dev/null || true

# --- Step 2.5: GUI reachability pre-check (v8.1, v9.1 respect opt-out) ---
# If GUI is not reachable, bootstrap the dashboard asynchronously.
# Respect auto_continue_on_gui_unavailable config (default true).
# When set to false, skip auto_continue and fall through to normal polling
# (which will time out — this is the fail-closed behaviour the user wants).
AUTO_CONTINUE_ON_GUI_UNAVAILABLE=$(read_config_value "$PROJECT_ROOT" "gui.auto_continue_on_gui_unavailable" "true")

if ! gui_server_available_for_project; then
  GUI_BOOTSTRAP_OUTPUT=$(AUTOPILOT_HTTP_PORT="${AUTOPILOT_HTTP_PORT:-$GUI_PORT}" AUTOPILOT_WS_PORT="$GUI_WS_PORT" \
    bash "$START_GUI_SERVER_SCRIPT" --no-wait "$PROJECT_ROOT" 2>/dev/null || true)
  GUI_BOOTSTRAP_JSON=$(echo "$GUI_BOOTSTRAP_OUTPUT" | grep '^GUI_SERVER_JSON:' | tail -1 | sed 's/^GUI_SERVER_JSON://')

  GUI_STATUS=$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('status','starting'))" \
    "${GUI_BOOTSTRAP_JSON:-{}}" 2>/dev/null || echo "starting")
  DASHBOARD_URL=$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('http_url',''))" \
    "${GUI_BOOTSTRAP_JSON:-{}}" 2>/dev/null || echo "")
  WS_URL=$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('ws_url',''))" \
    "${GUI_BOOTSTRAP_JSON:-{}}" 2>/dev/null || echo "")
  HEALTH_URL=$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('health_url',''))" \
    "${GUI_BOOTSTRAP_JSON:-{}}" 2>/dev/null || echo "")

  [ -z "$DASHBOARD_URL" ] && DASHBOARD_URL="http://localhost:${GUI_PORT}"
  [ -z "$WS_URL" ] && WS_URL="ws://localhost:${GUI_WS_PORT}"
  [ -z "$HEALTH_URL" ] && HEALTH_URL="http://localhost:${GUI_PORT}/api/health"

  if [ "$AUTO_CONTINUE_ON_GUI_UNAVAILABLE" = "true" ]; then
    # Auto-continue: clear decision request and proceed immediately
    rm -f "$DECISION_REQUEST_FILE" 2>/dev/null || true

    EVENT_PAYLOAD=$(printf '{"action":"auto_continue","elapsed_seconds":0,"reason":"gui_dashboard_bootstrap","gui_status":"%s","dashboard_url":"%s","health_url":"%s","ws_url":"%s"}' \
      "$GUI_STATUS" "$DASHBOARD_URL" "$HEALTH_URL" "$WS_URL")
    bash "$SCRIPT_DIR/emit-phase-event.sh" "gate_decision_received" "$PHASE" "$MODE" \
      "$EVENT_PAYLOAD" 2>/dev/null || true

    printf '{"action":"auto_continue","phase":%s,"elapsed_seconds":0,"reason":"gui_dashboard_bootstrap","gui_status":"%s","dashboard_url":"%s","health_url":"%s","ws_url":"%s"}\n' \
      "$PHASE" "$GUI_STATUS" "$DASHBOARD_URL" "$HEALTH_URL" "$WS_URL"
    exit 0
  fi
  # else: auto_continue_on_gui_unavailable=false — fall through to normal polling (fail-closed)
fi

# --- Step 3: Poll for decision.json ---
ELAPSED=0

while [ "$ELAPSED" -lt "$POLL_TIMEOUT" ]; do
  if [ -f "$DECISION_FILE" ]; then
    # Validate decision format
    DECISION=$(python3 -c "
import json, sys

try:
    with open(sys.argv[1]) as f:
        decision = json.load(f)

    action = decision.get('action', '').lower()
    if action not in ('override', 'retry', 'fix', 'auto_continue'):
        print(json.dumps({'error': f'Invalid action: {action}. Must be: override, retry, fix, auto_continue'}))
        sys.exit(1)
    if action == 'override' and sys.argv[3].lower() != 'true':
        print(json.dumps({'error': 'Override is forbidden for this gate. Use retry or fix instead.'}))
        sys.exit(1)

    # Normalize
    decision['action'] = action
    decision.setdefault('phase', int(sys.argv[2]))
    decision.setdefault('timestamp', '')
    decision.setdefault('reason', '')

    print(json.dumps(decision, ensure_ascii=False))
except json.JSONDecodeError as e:
    print(json.dumps({'error': f'Invalid JSON in decision.json: {e}'}))
    sys.exit(1)
except Exception as e:
    print(json.dumps({'error': str(e)}))
    sys.exit(1)
" "$DECISION_FILE" "$PHASE" "$OVERRIDE_ALLOWED" 2>/dev/null)

    VALIDATE_EXIT=$?

    if [ $VALIDATE_EXIT -eq 0 ] && [ -n "$DECISION" ]; then
      # Clean up decision files (atomic: remove response first, then request)
      rm -f "$DECISION_FILE" 2>/dev/null || true
      rm -f "$DECISION_REQUEST_FILE" 2>/dev/null || true

      # Emit decision_received event
      ACTION=$(echo "$DECISION" | python3 -c "import json,sys; print(json.load(sys.stdin).get('action','unknown'))" 2>/dev/null || echo "unknown")
      bash "$SCRIPT_DIR/emit-phase-event.sh" "gate_decision_received" "$PHASE" "$MODE" \
        "{\"action\":\"$ACTION\",\"elapsed_seconds\":$ELAPSED}" 2>/dev/null || true

      # Output decision to stdout
      echo "$DECISION"
      exit 0
    fi

    # Invalid decision file — remove and keep polling (GUI may be mid-write)
    rm -f "$DECISION_FILE" 2>/dev/null || true
  fi

  sleep "$POLL_INTERVAL"
  ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

# --- Timeout ---
rm -f "$DECISION_REQUEST_FILE" 2>/dev/null || true

echo "{\"action\":\"timeout\",\"phase\":$PHASE,\"elapsed_seconds\":$ELAPSED}"
exit 1
