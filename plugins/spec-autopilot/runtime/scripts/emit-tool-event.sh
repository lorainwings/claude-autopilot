#!/usr/bin/env bash
# emit-tool-event.sh
# PostToolUse catch-all hook — emits tool_use events to events.jsonl
# Reads tool invocation from stdin JSON, extracts key params, writes event.
# Performance target: < 50ms (pure bash fast path for session detection)
#
# Stdin: Claude Code PostToolUse JSON (tool_name, tool_input, tool_result etc.)
# Output: Appends one JSON line to logs/events.jsonl (no stdout — hook must be silent)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

# --- Read stdin first (before PROJECT_ROOT resolution, so cwd can inform it) ---
STDIN_DATA=""
if [ ! -t 0 ]; then
  STDIN_DATA=$(cat)
fi

# --- Resolve PROJECT_ROOT: stdin cwd > PROJECT_ROOT_QUICK env > git fallback ---
# Mirrors _hook_preamble.sh:33 pattern: parse cwd from stdin JSON as highest priority
_STDIN_CWD=""
if [ -n "$STDIN_DATA" ]; then
  _STDIN_CWD=$(echo "$STDIN_DATA" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
fi
if [ -n "$_STDIN_CWD" ]; then
  PROJECT_ROOT="$_STDIN_CWD"
elif [ -n "${PROJECT_ROOT_QUICK:-}" ]; then
  PROJECT_ROOT="$PROJECT_ROOT_QUICK"
else
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

# --- Fast path: skip if no active autopilot session ---
if ! has_active_autopilot "$PROJECT_ROOT"; then
  exit 0
fi

# --- Extract tool_name from stdin JSON (pure bash regex) ---
TOOL_NAME=""
if [[ "$STDIN_DATA" =~ \"tool_name\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
  TOOL_NAME="${BASH_REMATCH[1]}"
fi
[ -z "$TOOL_NAME" ] && exit 0

# --- Extract key_param based on tool type ---
KEY_PARAM=""
case "$TOOL_NAME" in
  Bash)
    # Extract command field from tool_input — up to 300 chars for meaningful diagnostics
    if [[ "$STDIN_DATA" =~ \"command\"[[:space:]]*:[[:space:]]*\"([^\"]{0,300}) ]]; then
      KEY_PARAM="${BASH_REMATCH[1]}"
    fi
    ;;
  Read)
    if [[ "$STDIN_DATA" =~ \"file_path\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
      KEY_PARAM="${BASH_REMATCH[1]}"
    fi
    ;;
  Write | Edit)
    if [[ "$STDIN_DATA" =~ \"file_path\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
      KEY_PARAM="${BASH_REMATCH[1]}"
    fi
    ;;
  Glob)
    if [[ "$STDIN_DATA" =~ \"pattern\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
      KEY_PARAM="${BASH_REMATCH[1]}"
    fi
    ;;
  Grep)
    if [[ "$STDIN_DATA" =~ \"pattern\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
      KEY_PARAM="${BASH_REMATCH[1]}"
    fi
    ;;
  Agent)
    if [[ "$STDIN_DATA" =~ \"description\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
      KEY_PARAM="${BASH_REMATCH[1]}"
    fi
    ;;
esac

# --- Extract output_preview (first 500 chars of result/stdout) ---
OUTPUT_PREVIEW=""
if [[ "$STDIN_DATA" =~ \"stdout\"[[:space:]]*:[[:space:]]*\"([^\"]{0,500}) ]]; then
  OUTPUT_PREVIEW="${BASH_REMATCH[1]}"
elif [[ "$STDIN_DATA" =~ \"output\"[[:space:]]*:[[:space:]]*\"([^\"]{0,500}) ]]; then
  OUTPUT_PREVIEW="${BASH_REMATCH[1]}"
fi

# --- Infer current phase from last phase_start in events.jsonl ---
EVENTS_FILE="$PROJECT_ROOT/logs/events.jsonl"
CURRENT_PHASE=0
if [ -f "$EVENTS_FILE" ]; then
  # Read last phase_start event — pure bash + tail for speed
  local_line=$(grep '"phase_start"' "$EVENTS_FILE" 2>/dev/null | tail -1)
  if [ -n "$local_line" ] && [[ "$local_line" =~ \"phase\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
    CURRENT_PHASE="${BASH_REMATCH[1]}"
  fi
fi

# --- Read active agent_id from marker file (WS4.A: tool_use ↔ agent correlation) ---
CURRENT_AGENT_ID=""
CURRENT_SESSION_ID=""
if [[ "$STDIN_DATA" =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
  CURRENT_SESSION_ID="${BASH_REMATCH[1]}"
fi
if [ -z "$CURRENT_SESSION_ID" ]; then
  CURRENT_SESSION_ID="${AUTOPILOT_SESSION_ID:-}"
fi
if [ -z "$CURRENT_SESSION_ID" ] && [ -f "$PROJECT_ROOT/openspec/changes/.autopilot-active" ]; then
  CURRENT_SESSION_ID=$(read_lock_json_field "$PROJECT_ROOT/openspec/changes/.autopilot-active" "session_id" "")
fi
ACTIVE_AGENT_FILE="$PROJECT_ROOT/logs/.active-agent-id"
if [ -n "$CURRENT_SESSION_ID" ]; then
  SESSION_AGENT_FILE=$(get_session_agent_marker_file "$PROJECT_ROOT" "$CURRENT_SESSION_ID")
  if [ -f "$SESSION_AGENT_FILE" ]; then
    CURRENT_AGENT_ID=$(head -1 "$SESSION_AGENT_FILE" 2>/dev/null | tr -d '[:space:]')
  fi
fi
if [ -z "$CURRENT_AGENT_ID" ] && [ -f "$ACTIVE_AGENT_FILE" ]; then
  CURRENT_AGENT_ID=$(head -1 "$ACTIVE_AGENT_FILE" 2>/dev/null | tr -d '[:space:]')
fi

# --- Resolve context fields (pure bash fast path — avoid python3 forks) ---
LOCK_FILE="$PROJECT_ROOT/openspec/changes/.autopilot-active"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Pure bash JSON field extractor: read_json_field <file> <key> <default>
_read_json_field() {
  local file="$1" key="$2" default="${3:-}"
  [ -f "$file" ] || {
    echo "$default"
    return
  }
  local content
  content=$(cat "$file" 2>/dev/null) || {
    echo "$default"
    return
  }
  if [[ "$content" =~ \"$key\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo "$default"
  fi
}

CHANGE_NAME="${AUTOPILOT_CHANGE_NAME:-}"
[ -z "$CHANGE_NAME" ] && CHANGE_NAME=$(_read_json_field "$LOCK_FILE" "change" "unknown")

SESSION_ID="${AUTOPILOT_SESSION_ID:-}"
[ -z "$SESSION_ID" ] && SESSION_ID=$(_read_json_field "$LOCK_FILE" "session_id" "")
[ -z "$SESSION_ID" ] && SESSION_ID=$(date +%s)

MODE_VAL=$(_read_json_field "$LOCK_FILE" "mode" "full")
PHASE_LABEL=$(get_phase_label "$CURRENT_PHASE")
TOTAL_PHASES=$(get_total_phases "$MODE_VAL")
SEQUENCE=$(next_event_sequence "$PROJECT_ROOT")

# --- Extract exit_code for Bash tool ---
EXIT_CODE=""
if [ "$TOOL_NAME" = "Bash" ] && [[ "$STDIN_DATA" =~ \"exit_code\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
  EXIT_CODE="${BASH_REMATCH[1]}"
fi

# --- Build event JSON ---
# Use python3 for safe JSON construction (already required by autopilot)
EVENT_JSON=$(python3 -c "
import json, sys

event = {
    'type': 'tool_use',
    'phase': int(sys.argv[1]),
    'mode': sys.argv[2],
    'timestamp': sys.argv[3],
    'change_name': sys.argv[4],
    'session_id': sys.argv[5],
    'phase_label': sys.argv[6],
    'total_phases': int(sys.argv[7]),
    'sequence': int(sys.argv[8]),
    'payload': {
        'tool_name': sys.argv[9],
    }
}

key_param = sys.argv[10]
if key_param:
    event['payload']['key_param'] = key_param

exit_code = sys.argv[11]
if exit_code:
    event['payload']['exit_code'] = int(exit_code)

output_preview = sys.argv[12]
if output_preview:
    event['payload']['output_preview'] = output_preview[:500]

agent_id = sys.argv[13] if len(sys.argv) > 13 else ''
if agent_id:
    event['payload']['agent_id'] = agent_id

print(json.dumps(event, ensure_ascii=False))
" "$CURRENT_PHASE" "$MODE_VAL" "$TIMESTAMP" "$CHANGE_NAME" "$SESSION_ID" "$PHASE_LABEL" "$TOTAL_PHASES" "$SEQUENCE" "$TOOL_NAME" "$KEY_PARAM" "$EXIT_CODE" "$OUTPUT_PREVIEW" "$CURRENT_AGENT_ID" 2>/dev/null)

if [ -z "$EVENT_JSON" ]; then
  exit 0
fi

# Append to events.jsonl (silent — no stdout for PostToolUse hooks)
EVENTS_DIR="$PROJECT_ROOT/logs"
mkdir -p "$EVENTS_DIR" 2>/dev/null || true
echo "$EVENT_JSON" >>"$EVENTS_FILE" 2>/dev/null || true

exit 0
