#!/usr/bin/env bash
# create-lockfile.sh — Create/overwrite the .autopilot-active lockfile
#
# Usage: create-lockfile.sh <session_cwd> <lock_json>
#   session_cwd : project root directory
#   lock_json   : JSON string with lock data
#                 (change, pid, started, session_cwd, anchor_sha, session_id, mode)
#
# Stdout: JSON {"status":"ok|conflict|error","action":"created|overwritten|none","message":"..."}
#
# WP-6: Extracted from autopilot-phase0-init/SKILL.md Step 9 inline Python.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

SESSION_CWD="${1:-}"
LOCK_JSON="${2:-}"

if [ -z "$SESSION_CWD" ] || [ -z "$LOCK_JSON" ]; then
  echo '{"status":"error","action":"none","message":"Usage: create-lockfile.sh <session_cwd> <lock_json>"}'
  exit 1
fi

python3 -c '
import json, os, sys, tempfile

session_cwd = sys.argv[1]
lock_data = json.loads(sys.argv[2])

lock_dir = os.path.join(session_cwd, "openspec/changes")
os.makedirs(lock_dir, exist_ok=True)
lock_path = os.path.join(lock_dir, ".autopilot-active")

result = {"status": "ok", "action": "created"}
if os.path.exists(lock_path):
    try:
        with open(lock_path) as f:
            old = json.load(f)
        old_pid = int(old.get("pid", 0))
        old_sid = old.get("session_id", "")
        try:
            os.kill(old_pid, 0)
            pid_alive = True
        except (ProcessLookupError, PermissionError, OSError):
            pid_alive = False
        if pid_alive and old_sid == lock_data.get("session_id"):
            result = {"status": "conflict", "action": "none", "message": f"PID {old_pid} still alive with same session"}
            print(json.dumps(result))
            sys.exit(0)
        result["action"] = "overwritten"
    except Exception:
        result["action"] = "overwritten"

if result.get("status") != "conflict":
    tmp_fd, tmp_path = tempfile.mkstemp(dir=lock_dir, suffix=".tmp")
    try:
        with os.fdopen(tmp_fd, "w") as f:
            json.dump(lock_data, f, indent=2, ensure_ascii=False)
        os.replace(tmp_path, lock_path)
    except Exception as e:
        try: os.unlink(tmp_path)
        except: pass
        result = {"status": "error", "message": str(e)}

    if result["status"] != "error":
        with open(lock_path) as f:
            json.load(f)  # validate JSON

print(json.dumps(result))
' "$SESSION_CWD" "$LOCK_JSON"
