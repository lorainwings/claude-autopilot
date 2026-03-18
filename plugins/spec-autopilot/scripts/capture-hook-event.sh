#!/usr/bin/env bash
# capture-hook-event.sh
# Generic raw hook capture bridge for GUI observability.
# Usage: capture-hook-event.sh <hook_name>
# Input: raw Claude hook JSON from stdin
# Output: silent; appends wrapped record to logs/sessions/<session>/raw/hooks.jsonl

set -uo pipefail

HOOK_NAME="${1:-unknown}"
STDIN_DATA=""
if [ ! -t 0 ]; then
  STDIN_DATA=$(cat)
fi
[ -z "$STDIN_DATA" ] && exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

PROJECT_ROOT=$(python3 -c '
import json, os, sys, subprocess
data = json.loads(sys.stdin.read())
cwd = data.get("cwd")
# cwd may be a subdirectory; always resolve to git repo root
start_dir = cwd if isinstance(cwd, str) and cwd else os.getcwd()
try:
    root = subprocess.check_output(
        ["git", "rev-parse", "--show-toplevel"],
        cwd=start_dir, stderr=subprocess.DEVNULL
    ).decode().strip()
    if root:
        print(root)
    else:
        raise ValueError
except Exception:
    env_root = os.environ.get("AUTOPILOT_PROJECT_ROOT")
    print(env_root if env_root else start_dir)
' <<< "$STDIN_DATA" 2>/dev/null) || PROJECT_ROOT="$(resolve_project_root)"

[ -n "$PROJECT_ROOT" ] || PROJECT_ROOT="$(resolve_project_root)"

SESSION_ID=$(python3 -c '
import json, sys
data = json.loads(sys.stdin.read())
val = data.get("session_id")
if isinstance(val, str) and val:
    print(val)
' <<< "$STDIN_DATA" 2>/dev/null) || SESSION_ID=""

if [ -z "$SESSION_ID" ]; then
  LOCK_FILE="$PROJECT_ROOT/openspec/changes/.autopilot-active"
  SESSION_ID=$(read_lock_json_field "$LOCK_FILE" "session_id" "")
fi
[ -n "$SESSION_ID" ] || SESSION_ID="unknown"

SESSION_KEY=$(sanitize_session_key "$SESSION_ID")
SESSION_DIR="$PROJECT_ROOT/logs/sessions/$SESSION_KEY"
RAW_DIR="$SESSION_DIR/raw"
mkdir -p "$RAW_DIR" 2>/dev/null || exit 0

ACTIVE_AGENT_ID=""
ACTIVE_AGENT_FILE=$(get_session_agent_marker_file "$PROJECT_ROOT" "$SESSION_ID")
if [ -f "$ACTIVE_AGENT_FILE" ]; then
  ACTIVE_AGENT_ID=$(head -1 "$ACTIVE_AGENT_FILE" 2>/dev/null | tr -d '[:space:]')
elif [ -f "$PROJECT_ROOT/logs/.active-agent-id" ]; then
  ACTIVE_AGENT_ID=$(head -1 "$PROJECT_ROOT/logs/.active-agent-id" 2>/dev/null | tr -d '[:space:]')
fi

export AUTOPILOT_CAPTURE_HOOK_NAME="$HOOK_NAME"
export AUTOPILOT_CAPTURE_PROJECT_ROOT="$PROJECT_ROOT"
export AUTOPILOT_CAPTURE_SESSION_ID="$SESSION_ID"
export AUTOPILOT_CAPTURE_SESSION_KEY="$SESSION_KEY"
export AUTOPILOT_CAPTURE_ACTIVE_AGENT_ID="$ACTIVE_AGENT_ID"
export AUTOPILOT_CAPTURE_RAW_DIR="$RAW_DIR"
STDIN_FILE=$(mktemp "${TMPDIR:-/tmp}/autopilot-hook.XXXXXX")
printf "%s" "$STDIN_DATA" > "$STDIN_FILE"
trap 'rm -f "$STDIN_FILE"' EXIT
export AUTOPILOT_CAPTURE_STDIN_FILE="$STDIN_FILE"

python3 - <<'PY' >/dev/null 2>&1 || true
import json
import os
from datetime import datetime, timezone
from pathlib import Path

hook_name = os.environ.get("AUTOPILOT_CAPTURE_HOOK_NAME", "unknown")
project_root = os.environ.get("AUTOPILOT_CAPTURE_PROJECT_ROOT", "")
session_id = os.environ.get("AUTOPILOT_CAPTURE_SESSION_ID", "unknown")
session_key = os.environ.get("AUTOPILOT_CAPTURE_SESSION_KEY", "unknown")
active_agent_id = os.environ.get("AUTOPILOT_CAPTURE_ACTIVE_AGENT_ID", "")
raw_dir = Path(os.environ.get("AUTOPILOT_CAPTURE_RAW_DIR", "."))
stdin_file = os.environ.get("AUTOPILOT_CAPTURE_STDIN_FILE", "")

try:
    data = json.loads(Path(stdin_file).read_text(encoding="utf-8"))
except Exception:
    raise SystemExit(0)

captured_at = datetime.now(timezone.utc).isoformat()
record = {
    "source": "hook",
    "hook_name": hook_name,
    "captured_at": captured_at,
    "project_root": project_root,
    "session_id": session_id,
    "session_key": session_key,
    "cwd": data.get("cwd"),
    "transcript_path": data.get("transcript_path"),
    "agent_transcript_path": data.get("agent_transcript_path"),
    "active_agent_id": active_agent_id or None,
    "data": data,
}

hooks_file = raw_dir / "hooks.jsonl"
with hooks_file.open("a", encoding="utf-8") as fh:
    fh.write(json.dumps(record, ensure_ascii=False) + "\n")

meta = {
    "session_id": session_id,
    "session_key": session_key,
    "project_root": project_root,
    "cwd": data.get("cwd"),
    "last_hook_name": hook_name,
    "last_seen_at": captured_at,
    "transcript_path": data.get("transcript_path"),
}
if data.get("agent_transcript_path"):
    meta["agent_transcript_path"] = data.get("agent_transcript_path")

meta_file = raw_dir.parent / "meta.json"
if meta_file.exists():
    try:
        existing = json.loads(meta_file.read_text(encoding="utf-8"))
        if isinstance(existing, dict):
            existing.update({k: v for k, v in meta.items() if v not in (None, "")})
            meta = existing
    except Exception:
        pass
meta_file.write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
PY

exit 0
