#!/usr/bin/env bash
set -uo pipefail

STDIN_DATA=""
if [ ! -t 0 ]; then
  STDIN_DATA=$(cat)
fi

[ -n "$STDIN_DATA" ] || {
  printf "[harness] ready"
  exit 0
}

command -v python3 >/dev/null 2>&1 || {
  printf "[harness] telemetry unavailable"
  exit 0
}

export PH_STATUSLINE_STDIN="$STDIN_DATA"
PH_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PH_SCRIPT_DIR

STATUS_LINE="$(
python3 - <<'PY' 2>/dev/null
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, os.environ.get("PH_SCRIPT_DIR", ""))
from _ph_project_guard import is_parallel_harness_project, resolve_project_root


def sanitize_session_key(value: str) -> str:
    key = re.sub(r"[^A-Za-z0-9._-]+", "-", value or "unknown")
    key = key.strip(".-")
    return key or "unknown"


stdin_data = os.environ.get("PH_STATUSLINE_STDIN", "")
if not stdin_data:
    print("[harness] ready")
    raise SystemExit(0)

try:
    payload = json.loads(stdin_data)
except Exception:
    print("[harness] ready")
    raise SystemExit(0)

cwd = payload.get("cwd") if isinstance(payload.get("cwd"), str) else ""
project_root = resolve_project_root(cwd)

# Passive observer guard: never create .parallel-harness/ in projects that
# do not actually use the plugin. Prevents user-scope statusLine from
# polluting every git repo on the machine.
if not is_parallel_harness_project(project_root):
    print("[harness] ready")
    raise SystemExit(0)

session_id = payload.get("session_id") if isinstance(payload.get("session_id"), str) else "unknown"
session_key = sanitize_session_key(session_id)
timestamp = datetime.now(timezone.utc).isoformat()

base_dir = Path(project_root) / ".parallel-harness" / "data" / "plugin-observability" / "sessions" / session_key
raw_dir = base_dir / "raw"
raw_dir.mkdir(parents=True, exist_ok=True)

raw_record = {
    "source": "statusline",
    "captured_at": timestamp,
    "project_root": project_root,
    "session_id": session_id,
    "session_key": session_key,
    "cwd": cwd or None,
    "data": payload,
}
with (raw_dir / "statusline.jsonl").open("a", encoding="utf-8") as fh:
    fh.write(json.dumps(raw_record, ensure_ascii=False) + "\n")

events_path = base_dir / "skill-events.jsonl"
if not events_path.exists():
    print("[harness] ready")
    raise SystemExit(0)

lines = [line for line in events_path.read_text(encoding="utf-8").splitlines() if line.strip()]
if not lines:
    print("[harness] ready")
    raise SystemExit(0)

latest = None
for line in reversed(lines):
    try:
        record = json.loads(line)
    except Exception:
        continue
    if record.get("session_id") != session_id:
        continue
    latest = record
    break

if latest is None:
    print("[harness] ready")
    raise SystemExit(0)

skill_name = str(latest.get("skill_name") or "unknown")
short_name = skill_name.split(":", 1)[-1]
completion_status = latest.get("completion_status")

if completion_status == "failed":
    print(f"[harness] skill {short_name} failed")
else:
    print(f"[harness] skill {short_name}")
PY
)" || STATUS_LINE="[harness] ready"

printf "%s" "${STATUS_LINE:-[harness] ready}"
exit 0
