#!/usr/bin/env bash
# record-skill-tool-event.sh
# Hook bridge for actual Claude plugin sessions.
# Captures deterministic Skill tool invocations from Pre/PostToolUse and writes
# raw hook evidence plus structured per-session JSONL records under
# .parallel-harness/data/plugin-observability/.

set -uo pipefail

HOOK_NAME="${1:-unknown}"
STDIN_DATA=""
if [ ! -t 0 ]; then
  STDIN_DATA=$(cat)
fi

[ -n "$STDIN_DATA" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

export PH_SKILL_HOOK_NAME="$HOOK_NAME"
STDIN_FILE=$(mktemp "${TMPDIR:-/tmp}/ph-skill-hook.XXXXXX")
printf "%s" "$STDIN_DATA" >"$STDIN_FILE"
trap 'rm -f "$STDIN_FILE"' EXIT
export PH_SKILL_STDIN_FILE="$STDIN_FILE"

python3 - <<'PY' >/dev/null 2>&1 || true
import json
import os
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path


def sanitize_session_key(value: str) -> str:
    key = re.sub(r"[^A-Za-z0-9._-]+", "-", value or "unknown")
    key = key.strip(".-")
    return key or "unknown"


def resolve_project_root(cwd: str) -> str:
    if cwd:
        try:
            root = subprocess.check_output(
                ["git", "rev-parse", "--show-toplevel"],
                cwd=cwd,
                stderr=subprocess.DEVNULL,
                text=True,
            ).strip()
            if root:
                return root
        except Exception:
            pass
        return cwd
    return os.getcwd()


def preview(value, limit: int = 240):
    if value is None:
        return None
    if isinstance(value, str):
        text = value
    else:
        try:
            text = json.dumps(value, ensure_ascii=False)
        except Exception:
            text = str(value)
    text = text.strip()
    if not text:
        return None
    if len(text) > limit:
        return text[:limit] + "..."
    return text


def infer_phase(skill_name: str):
    phase_map = {
        "parallel-harness:harness": "orchestration",
        "parallel-harness:harness-plan": "planning",
        "parallel-harness:harness-dispatch": "dispatch",
        "parallel-harness:harness-verify": "verification",
    }
    return phase_map.get(skill_name)


hook_name = os.environ.get("PH_SKILL_HOOK_NAME", "unknown")
stdin_file = os.environ.get("PH_SKILL_STDIN_FILE", "")
if not stdin_file:
    raise SystemExit(0)

try:
    payload = json.loads(Path(stdin_file).read_text(encoding="utf-8"))
except Exception:
    raise SystemExit(0)

if payload.get("tool_name") != "Skill":
    raise SystemExit(0)

tool_input = payload.get("tool_input")
if not isinstance(tool_input, dict):
    tool_input = {}

skill_name = (
    tool_input.get("skill")
    or tool_input.get("skill_name")
    or tool_input.get("name")
    or payload.get("skill")
)
if not isinstance(skill_name, str) or not skill_name.strip():
    skill_name = "unknown"
skill_name = skill_name.strip()

cwd = payload.get("cwd") if isinstance(payload.get("cwd"), str) else ""
project_root = resolve_project_root(cwd)
session_id = payload.get("session_id") if isinstance(payload.get("session_id"), str) else "unknown"
session_key = sanitize_session_key(session_id)
timestamp = datetime.now(timezone.utc).isoformat()
phase_hint = infer_phase(skill_name)
is_parallel_harness_skill = skill_name.startswith("parallel-harness:")

# Only record events for parallel-harness's own skills — avoid polluting
# application projects that don't use parallel-harness with .parallel-harness/ data.
if not is_parallel_harness_skill:
    raise SystemExit(0)

event_type = "skill_tool_requested" if hook_name == "PreToolUse" else (
    "skill_tool_failed" if hook_name == "PostToolUseFailure" else "skill_tool_completed"
)
completion_status = None
if hook_name == "PostToolUse":
    explicit_error = payload.get("tool_error") or payload.get("error")
    if explicit_error:
        completion_status = "failed"
    else:
        completion_status = "completed"
elif hook_name == "PostToolUseFailure":
    completion_status = "failed"

tool_response = (
    payload.get("tool_response")
    if "tool_response" in payload
    else payload.get("tool_result", payload.get("tool_output", payload.get("result")))
)
# PostToolUseFailure carries error/is_interrupt instead of tool_response
error_message = payload.get("error") if hook_name == "PostToolUseFailure" else None
is_interrupt = payload.get("is_interrupt") if hook_name == "PostToolUseFailure" else None

event = {
    "schema_version": "1.0.0",
    "source": "claude_hook",
    "hook_name": hook_name,
    "event_type": event_type,
    "timestamp": timestamp,
    "session_id": session_id,
    "session_key": session_key,
    "project_root": project_root,
    "cwd": cwd or None,
    "transcript_path": payload.get("transcript_path"),
    "tool_name": "Skill",
    "skill_name": skill_name,
    "phase_hint": phase_hint,
    "is_parallel_harness_skill": is_parallel_harness_skill,
    "args_preview": preview(
        tool_input.get("args", tool_input.get("arguments", tool_input.get("prompt")))
    ),
    "response_preview": preview(tool_response) if tool_response else preview(error_message),
    "completion_status": completion_status,
    "error_message": error_message,
    "is_interrupt": is_interrupt,
}

base_dir = Path(project_root) / ".parallel-harness" / "data" / "plugin-observability" / "sessions" / session_key
base_dir.mkdir(parents=True, exist_ok=True)
raw_dir = base_dir / "raw"
raw_dir.mkdir(parents=True, exist_ok=True)

raw_record = {
    "source": "hook",
    "hook_name": hook_name,
    "captured_at": timestamp,
    "project_root": project_root,
    "session_id": session_id,
    "session_key": session_key,
    "cwd": cwd or None,
    "transcript_path": payload.get("transcript_path"),
    "data": payload,
}

with (raw_dir / "hooks.jsonl").open("a", encoding="utf-8") as fh:
    fh.write(json.dumps(raw_record, ensure_ascii=False) + "\n")

event["raw_ref"] = str((raw_dir / "hooks.jsonl").relative_to(Path(project_root)))

with (base_dir / "skill-events.jsonl").open("a", encoding="utf-8") as fh:
    fh.write(json.dumps(event, ensure_ascii=False) + "\n")

meta = {
    "session_id": session_id,
    "session_key": session_key,
    "project_root": project_root,
    "last_seen_at": timestamp,
    "last_hook_name": hook_name,
    "last_skill_name": skill_name,
    "last_phase_hint": phase_hint,
    "last_event_type": event_type,
    "last_completion_status": completion_status,
    "transcript_path": payload.get("transcript_path"),
}
(base_dir / "meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
PY

exit 0
