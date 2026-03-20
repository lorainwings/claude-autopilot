#!/usr/bin/env bash
# auto-emit-agent-complete.sh
# Hook: PostToolUse(^Task$)
# Purpose: Automatically emit agent_complete events when autopilot Task completions are detected.
#          Runs alongside post-task-validator.sh — never blocks, purely observational.
#
# Mechanism:
#   1. Detect autopilot Task via phase marker (<!-- autopilot-phase:N -->)
#   2. Skip checkpoint-writer Tasks (internal infrastructure)
#   3. Extract phase number and compute duration from dispatch timestamp
#   4. Extract status from Task output JSON envelope
#   5. Clear active agent marker (logs/.active-agent-id)
#   6. Call emit-agent-event.sh agent_complete
#
# Output: Always exit 0 (never block). Observational hook only.
# Timeout: 5s

set -uo pipefail

# --- Source preamble (reads stdin, checks session, sets PROJECT_ROOT_QUICK) ---
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_hook_preamble.sh"

# --- Layer 1: Check for autopilot phase marker ---
if ! has_phase_marker; then
  exit 0
fi

# --- Skip checkpoint-writer Tasks ---
if echo "$STDIN_DATA" | grep -q 'checkpoint-writer'; then
  exit 0
fi

# --- Skip lockfile-writer Tasks ---
if echo "$STDIN_DATA" | grep -q 'lockfile-writer'; then
  exit 0
fi

# --- Extract phase number from marker ---
PHASE=""
if [[ "$STDIN_DATA" =~ autopilot-phase:([0-9]+) ]]; then
  PHASE="${BASH_REMATCH[1]}"
fi
[ -z "$PHASE" ] && exit 0

# --- Read execution mode from lock file ---
PROJECT_ROOT="$PROJECT_ROOT_QUICK"
LOCK_FILE="$PROJECT_ROOT/openspec/changes/.autopilot-active"
MODE="full"
SESSION_ID=""
if [ -f "$LOCK_FILE" ]; then
  # Read lock file once to avoid TOCTOU
  _LOCK_CONTENT=$(cat "$LOCK_FILE" 2>/dev/null) || _LOCK_CONTENT=""
  if [[ "$_LOCK_CONTENT" =~ \"mode\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
    MODE="${BASH_REMATCH[1]}"
  fi
  if [[ "$_LOCK_CONTENT" =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
    SESSION_ID="${BASH_REMATCH[1]}"
  fi
fi
if [ -z "$SESSION_ID" ] && [[ "$STDIN_DATA" =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
  SESSION_ID="${BASH_REMATCH[1]}"
fi

# --- Extract agent label from Task description ---
AGENT_LABEL=""
if [[ "$STDIN_DATA" =~ \"description\"[[:space:]]*:[[:space:]]*\"([^\"]{0,120}) ]]; then
  AGENT_LABEL="${BASH_REMATCH[1]}"
fi
[ -z "$AGENT_LABEL" ] && AGENT_LABEL="Phase ${PHASE} Agent"

# --- Generate agent_id slug (must match dispatch logic, unicode-safe) ---
SLUG=""
if command -v python3 &>/dev/null; then
  SLUG=$(python3 -c "
import re, sys, unicodedata
label = sys.argv[1]
nfkd = unicodedata.normalize('NFKD', label)
chars = []
for c in nfkd:
    if c.isascii() and c.isalnum():
        chars.append(c.lower())
    elif '\u4e00' <= c <= '\u9fff':
        chars.append(c)
    else:
        if chars and chars[-1] != '-':
            chars.append('-')
slug = ''.join(chars).strip('-')[:40]
print(slug if slug else 'agent')
" "$AGENT_LABEL" 2>/dev/null) || true
fi
if [ -z "$SLUG" ]; then
  SLUG=$(echo "$AGENT_LABEL" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//' | head -c 40)
  [ -z "$SLUG" ] && SLUG="agent"
fi
AGENT_ID="phase${PHASE}-${SLUG}"

# --- Extract status/summary/artifacts from Task output JSON envelope ---
# PostToolUse stdin nests the agent's response inside tool_response (string field).
# The JSON envelope {status, summary, artifacts} is INSIDE that string.
# Strategy: use python3 for reliable nested JSON extraction, with bash regex fallback.
STATUS="ok"
SUMMARY=""
OUTPUT_FILES=""
if command -v python3 &>/dev/null; then
  _EXTRACTED=$(python3 -c "
import json, sys, re
try:
    data = json.loads(sys.stdin.read())
    # tool_response may be a string containing the agent's output
    resp = data.get('tool_response', '') or ''
    if isinstance(resp, dict):
        resp = json.dumps(resp)
    # Search for JSON envelope in the response text
    # Match the outermost {...} containing 'status'
    for m in re.finditer(r'\{[^{}]*\"status\"\s*:\s*\"[^\"]+\"[^{}]*\}', str(resp)):
        try:
            env = json.loads(m.group())
            s = env.get('status', '')
            if s in ('ok','warning','blocked','failed'):
                print(f'STATUS={s}')
                sm = env.get('summary', '')
                if sm:
                    print(f'SUMMARY={sm[:120]}')
                arts = env.get('artifacts', [])
                if isinstance(arts, list) and arts:
                    print('ARTIFACTS=' + json.dumps(arts, ensure_ascii=False))
                break
        except (json.JSONDecodeError, ValueError):
            continue
except Exception:
    pass
" <<<"$STDIN_DATA" 2>/dev/null) || true
  if [ -n "$_EXTRACTED" ]; then
    _line=""
    while IFS= read -r _line; do
      case "$_line" in
        STATUS=*) STATUS="${_line#STATUS=}" ;;
        SUMMARY=*) SUMMARY="${_line#SUMMARY=}" ;;
        ARTIFACTS=*) OUTPUT_FILES="${_line#ARTIFACTS=}" ;;
      esac
    done <<<"$_EXTRACTED"
  fi
else
  # Bash regex fallback: search in full stdin (less reliable, matches first occurrence)
  if [[ "$STDIN_DATA" =~ \"status\"[[:space:]]*:[[:space:]]*\"(ok|warning|blocked|failed)\" ]]; then
    STATUS="${BASH_REMATCH[1]}"
  fi
  if [[ "$STDIN_DATA" =~ \"summary\"[[:space:]]*:[[:space:]]*\"([^\"]{0,120}) ]]; then
    SUMMARY="${BASH_REMATCH[1]}"
  fi
fi

# --- Compute duration from dispatch timestamp (millisecond precision) ---
DURATION_MS=0
DISPATCH_TS_FILE="$PROJECT_ROOT/logs/.agent-dispatch-ts-${AGENT_ID}"
if [ -f "$DISPATCH_TS_FILE" ]; then
  DISPATCH_TS=$(head -1 "$DISPATCH_TS_FILE" 2>/dev/null | tr -d '[:space:]')
  if [ -n "$DISPATCH_TS" ]; then
    NOW_MS=$(python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null || echo "$(date +%s)000")
    DURATION_MS=$((NOW_MS - DISPATCH_TS))
    [ "$DURATION_MS" -lt 0 ] && DURATION_MS=0
  fi
  # Cleanup dispatch timestamp file
  rm -f "$DISPATCH_TS_FILE" 2>/dev/null || true
fi

# --- Clear active agent markers ---
rm -f "$PROJECT_ROOT/logs/.active-agent-id" 2>/dev/null || true
rm -f "$PROJECT_ROOT/logs/.active-agent-phase-${PHASE}" 2>/dev/null || true
if [ -n "$SESSION_ID" ]; then
  SESSION_AGENT_FILE=$(get_session_agent_marker_file "$PROJECT_ROOT" "$SESSION_ID")
  rm -f "$SESSION_AGENT_FILE" 2>/dev/null || true
fi

# --- Build payload JSON (use python3 for safe construction) ---
PAYLOAD=$(python3 -c "
import json, sys
p = {'status': sys.argv[1], 'duration_ms': int(sys.argv[2])}
summary = sys.argv[3]
if summary:
    p['summary'] = summary
output_files = sys.argv[4]
if output_files:
    try:
        p['output_files'] = json.loads(output_files)
    except (json.JSONDecodeError, ValueError):
        pass
print(json.dumps(p, ensure_ascii=False))
" "$STATUS" "$DURATION_MS" "$SUMMARY" "$OUTPUT_FILES" 2>/dev/null) || PAYLOAD="{\"status\":\"${STATUS}\",\"duration_ms\":${DURATION_MS}}"

# --- Emit agent_complete event (log errors to stderr, never block) ---
bash "$SCRIPT_DIR/emit-agent-event.sh" agent_complete "$PHASE" "$MODE" "$AGENT_ID" "$AGENT_LABEL" "$PAYLOAD" >/dev/null 2>&1 ||
  echo "WARNING: agent_complete event emission failed for $AGENT_ID" >&2

# --- v5.4: Emit model_fallback when task failed and fallback_model is available ---
if [ "$STATUS" = "failed" ] || [ "$STATUS" = "blocked" ]; then
  _EVENTS_FILE="$PROJECT_ROOT/logs/events.jsonl"
  if [ -f "$_EVENTS_FILE" ] && command -v python3 &>/dev/null; then
    _FB_JSON=$(python3 -c "
import json, sys, os

events_file = sys.argv[1]
phase = int(sys.argv[2])
session_id = sys.argv[3]
agent_id = sys.argv[4]
status = sys.argv[5]

lines = []
try:
    with open(events_file, 'r') as f:
        lines = f.readlines()[-100:]
except Exception:
    sys.exit(0)

# Find last model_routing for this phase+session+agent that has fallback_model
for line in reversed(lines):
    line = line.strip()
    if not line or 'model_routing' not in line:
        continue
    try:
        ev = json.loads(line)
        if ev.get('type') != 'model_routing':
            continue
        if ev.get('phase') != phase:
            continue
        if session_id and ev.get('session_id') != session_id:
            continue
        payload = ev.get('payload', {})
        # Match agent_id: when we know the current agent, reject any event
        # that doesn't carry the same agent_id (including untagged events).
        ev_agent = payload.get('agent_id', '')
        if agent_id and ev_agent != agent_id:
            continue
        fb = payload.get('fallback_model')
        if fb and fb not in ('null', 'None', ''):
            result = {
                'requested_model': payload.get('selected_model', ''),
                'fallback_model': fb,
                'fallback_reason': f'Task {agent_id} completed with status={status}',
            }
            print(json.dumps(result, ensure_ascii=False))
        break
    except Exception:
        continue
" "$_EVENTS_FILE" "$PHASE" "$SESSION_ID" "$AGENT_ID" "$STATUS" 2>/dev/null) || _FB_JSON=""
    if [ -n "$_FB_JSON" ]; then
      bash "$SCRIPT_DIR/emit-model-routing-event.sh" "$PROJECT_ROOT" "$PHASE" "$MODE" "$_FB_JSON" "$AGENT_ID" "model_fallback" >/dev/null 2>&1 || true
    fi
  fi
fi

exit 0
