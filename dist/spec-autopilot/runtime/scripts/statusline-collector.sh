#!/usr/bin/env bash
# statusline-collector.sh
# Collect Claude Code status line JSON for GUI telemetry while printing a compact status line.
# Usage: statusline-collector.sh

set -uo pipefail

STDIN_DATA=""
if [ ! -t 0 ]; then
  STDIN_DATA=$(cat)
fi

if [ -z "$STDIN_DATA" ]; then
  printf "[autopilot] idle"
  exit 0
fi

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
' <<<"$STDIN_DATA" 2>/dev/null) || PROJECT_ROOT="$(resolve_project_root)"
[ -n "$PROJECT_ROOT" ] || PROJECT_ROOT="$(resolve_project_root)"

# Pre-extract session_id and sanitize using shared _common.sh function
SESSION_ID=$(python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); v=d.get("session_id",""); print(v if isinstance(v,str) and v else "unknown")' <<<"$STDIN_DATA" 2>/dev/null) || SESSION_ID="unknown"
SESSION_KEY=$(sanitize_session_key "$SESSION_ID")

export AUTOPILOT_STATUS_PROJECT_ROOT="$PROJECT_ROOT"
export AUTOPILOT_STATUS_SESSION_ID="$SESSION_ID"
export AUTOPILOT_STATUS_SESSION_KEY="$SESSION_KEY"
STDIN_FILE=$(mktemp "${TMPDIR:-/tmp}/autopilot-statusline.XXXXXX")
printf "%s" "$STDIN_DATA" >"$STDIN_FILE"
trap 'rm -f "$STDIN_FILE"' EXIT
export AUTOPILOT_STATUS_STDIN_FILE="$STDIN_FILE"

STATUS_LINE=$(
  python3 - <<'PY'
import json
import os
from datetime import datetime, timezone
from pathlib import Path

def get_any(d, *names):
    for name in names:
        val = d.get(name)
        if val not in (None, ""):
            return val
    return None

try:
    data = json.loads(Path(os.environ.get("AUTOPILOT_STATUS_STDIN_FILE", "")).read_text(encoding="utf-8"))
except Exception:
    print("[autopilot] telemetry-error")
    raise SystemExit(0)

project_root = os.environ.get("AUTOPILOT_STATUS_PROJECT_ROOT", "")
session_id = os.environ.get("AUTOPILOT_STATUS_SESSION_ID") or get_any(data, "session_id") or "unknown"
session_key = os.environ.get("AUTOPILOT_STATUS_SESSION_KEY") or "unknown"
captured_at = datetime.now(timezone.utc).isoformat()

raw_dir = Path(project_root) / "logs" / "sessions" / session_key / "raw"
raw_dir.mkdir(parents=True, exist_ok=True)

record = {
    "source": "statusline",
    "captured_at": captured_at,
    "project_root": project_root,
    "session_id": session_id,
    "session_key": session_key,
    "cwd": get_any(data, "cwd"),
    "transcript_path": get_any(data, "transcript_path"),
    "data": data,
}
with (raw_dir / "statusline.jsonl").open("a", encoding="utf-8") as fh:
    fh.write(json.dumps(record, ensure_ascii=False) + "\n")

meta = {
    "session_id": session_id,
    "session_key": session_key,
    "project_root": project_root,
    "cwd": get_any(data, "cwd"),
    "last_seen_at": captured_at,
    "transcript_path": get_any(data, "transcript_path"),
}
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

model = str(get_any(data, "model") or "--")
context_window = get_any(data, "context_window")
context_pct = "--"
if isinstance(context_window, dict):
    pct = context_window.get("percent") or context_window.get("used_percent")
    if isinstance(pct, (int, float)):
        context_pct = f"{pct:.0f}%"
cost = get_any(data, "cost", "cost_usd", "total_cost_usd")
if isinstance(cost, dict):
    cost = cost.get("total") or cost.get("usd")
cost_label = f"${cost}" if cost not in (None, "") else "--"
cwd = str(get_any(data, "cwd") or ".")
cwd_label = os.path.basename(cwd.rstrip("/")) or cwd

print(f"[autopilot] {model} | ctx {context_pct} | cost {cost_label} | {cwd_label}")
PY
)

printf "%s" "${STATUS_LINE:-[autopilot] telemetry}"

# --- v5.4: Emit model_effective event if autopilot is active ---
# Correlates by session_id + agent_id (from .active-agent-id marker).
# Dedup marker written ONLY after successful emit to avoid lost events.
if has_active_autopilot "$PROJECT_ROOT" 2>/dev/null; then
  _OBSERVED_MODEL=$(python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('model',''))" <<<"$STDIN_DATA" 2>/dev/null) || _OBSERVED_MODEL=""
  if [ -n "$_OBSERVED_MODEL" ]; then
    # Resolve active agent_id for precise correlation in parallel scenarios
    # MUST use the same path as auto-emit-agent-dispatch.sh writer:
    #   get_session_agent_marker_file() → logs/.active-agent-session-{sanitized_key}
    _ACTIVE_AGENT_ID=""
    if [ -n "$SESSION_KEY" ]; then
      _SESSION_AGENT_FILE="$PROJECT_ROOT/logs/.active-agent-session-${SESSION_KEY}"
      [ -f "$_SESSION_AGENT_FILE" ] && _ACTIVE_AGENT_ID=$(head -1 "$_SESSION_AGENT_FILE" 2>/dev/null | tr -d '[:space:]') || true
    fi
    # Fallback to global marker only if session-scoped marker not found
    [ -z "$_ACTIVE_AGENT_ID" ] && [ -f "$PROJECT_ROOT/logs/.active-agent-id" ] && _ACTIVE_AGENT_ID=$(head -1 "$PROJECT_ROOT/logs/.active-agent-id" 2>/dev/null | tr -d '[:space:]') || true

    _EVENTS_FILE="$PROJECT_ROOT/logs/events.jsonl"
    if [ -f "$_EVENTS_FILE" ]; then
      # Python: find matching model_routing, output result JSON, do NOT write marker
      _EFF_RESULT=$(python3 -c "
import json, sys, os

events_file = sys.argv[1]
current_session = sys.argv[2]
observed_model = sys.argv[3]
project_root = sys.argv[4]
active_agent_id = sys.argv[5] if len(sys.argv) > 5 else ''

lines = []
try:
    with open(events_file, 'r') as f:
        lines = f.readlines()[-200:]
except Exception:
    sys.exit(0)

# Find last model_routing event matching session_id AND agent_id (if available)
last_routing = None
for line in reversed(lines):
    line = line.strip()
    if not line or 'model_routing' not in line:
        continue
    try:
        ev = json.loads(line)
        if ev.get('type') != 'model_routing':
            continue
        if ev.get('session_id') != current_session:
            continue
        payload = ev.get('payload', {})
        ev_agent = payload.get('agent_id', '')
        # If we know the active agent, require exact match.
        # Also reject untagged events (no agent_id) when we have a known agent —
        # in parallel scenarios untagged events are ambiguous.
        if active_agent_id:
            if ev_agent != active_agent_id:
                continue
        last_routing = ev
        break
    except Exception:
        continue

if not last_routing:
    sys.exit(0)

# Dedup check (read-only here; marker written by caller after successful emit)
seq = last_routing.get('sequence', 0)
agent_suffix = f'-{active_agent_id}' if active_agent_id else ''
marker_dir = os.path.join(project_root, 'logs', '.model-effective-markers')
marker_file = os.path.join(marker_dir, f'seq-{seq}{agent_suffix}')
if os.path.exists(marker_file):
    sys.exit(0)

payload = last_routing.get('payload', {})
requested = payload.get('selected_model', '')
agent_id = active_agent_id or payload.get('agent_id', '')

match = False
if requested == 'auto':
    match = True
elif requested and requested.lower() in observed_model.lower():
    match = True

eff_tier = 'unknown'
m = observed_model.lower()
if 'haiku' in m: eff_tier = 'fast'
elif 'sonnet' in m: eff_tier = 'standard'
elif 'opus' in m: eff_tier = 'deep'

result = {
    'effective_model': observed_model,
    'effective_tier': eff_tier,
    'inference_source': 'statusline',
    'requested_model': requested,
    'match': match,
    'phase': last_routing.get('phase', 0),
    'mode': last_routing.get('mode', 'full'),
    'agent_id': agent_id,
    '_marker_file': marker_file,
    '_marker_dir': marker_dir,
}
print(json.dumps(result, ensure_ascii=False))
" "$_EVENTS_FILE" "$SESSION_ID" "$_OBSERVED_MODEL" "$PROJECT_ROOT" "$_ACTIVE_AGENT_ID" 2>/dev/null) || _EFF_RESULT=""

      if [ -n "$_EFF_RESULT" ]; then
        _PHASE=$(echo "$_EFF_RESULT" | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('phase',0))" 2>/dev/null) || _PHASE=0
        _MODE=$(echo "$_EFF_RESULT" | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('mode','full'))" 2>/dev/null) || _MODE="full"
        _AGENT_ID=$(echo "$_EFF_RESULT" | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('agent_id',''))" 2>/dev/null) || _AGENT_ID=""
        # Emit first, THEN write dedup marker — avoids lost events on emit failure
        if bash "$SCRIPT_DIR/emit-model-routing-event.sh" "$PROJECT_ROOT" "$_PHASE" "$_MODE" "$_EFF_RESULT" "$_AGENT_ID" "model_effective" >/dev/null 2>&1; then
          # Write dedup marker only on successful emission
          _MARKER_FILE=$(echo "$_EFF_RESULT" | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('_marker_file',''))" 2>/dev/null) || true
          _MARKER_DIR=$(echo "$_EFF_RESULT" | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('_marker_dir',''))" 2>/dev/null) || true
          if [ -n "$_MARKER_FILE" ] && [ -n "$_MARKER_DIR" ]; then
            mkdir -p "$_MARKER_DIR" 2>/dev/null || true
            echo "$_OBSERVED_MODEL" > "$_MARKER_FILE" 2>/dev/null || true
          fi
        fi
      fi
    fi
  fi
fi

exit 0
