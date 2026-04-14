#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECTOR_SCRIPT="$SCRIPT_DIR/statusline-collector.sh"
[ -f "$COLLECTOR_SCRIPT" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

STDIN_DATA=""
if [ ! -t 0 ]; then
  STDIN_DATA=$(cat)
fi

export PH_AUTO_INSTALL_STDIN="$STDIN_DATA"

PROJECT_ROOT="$(
python3 - <<'PY' 2>/dev/null
import json
import os
import subprocess
import sys

stdin_data = os.environ.get("PH_AUTO_INSTALL_STDIN", "")
cwd = ""
if stdin_data:
    try:
        payload = json.loads(stdin_data)
        if isinstance(payload.get("cwd"), str):
            cwd = payload["cwd"]
    except Exception:
        pass

start_dir = cwd or os.getcwd()
try:
    root = subprocess.check_output(
        ["git", "rev-parse", "--show-toplevel"],
        cwd=start_dir,
        stderr=subprocess.DEVNULL,
        text=True,
    ).strip()
    print(root or start_dir)
except Exception:
    print(start_dir)
PY
)" || PROJECT_ROOT=""
[ -n "$PROJECT_ROOT" ] || PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# --- Project relevance guard: only install in projects that use parallel-harness ---
[ -d "$PROJECT_ROOT/.parallel-harness" ] || exit 0

CLAUDE_DIR="$PROJECT_ROOT/.claude"
LOCAL_SETTINGS="$CLAUDE_DIR/settings.local.json"
PROJECT_SETTINGS="$CLAUDE_DIR/settings.json"
USER_SETTINGS="${HOME}/.claude/settings.json"

# Only skip if the harness collector is ALREADY configured in statusLine command.
# If the user added/changed/removed a custom statusLine since last install,
# we must re-install to keep chaining current.
harness_collector_installed() {
  local file="$1"
  [ -f "$file" ] || return 1
  python3 -c '
import json
import sys
try:
    data = json.loads(open(sys.argv[1], encoding="utf-8").read())
    cmd = str(data.get("statusLine", {}).get("command", ""))
    if "statusline-collector.sh" in cmd and "parallel-harness" in cmd:
        raise SystemExit(0)
except SystemExit:
    raise
except Exception:
    pass
raise SystemExit(1)
' "$file" 2>/dev/null
}

# Detect existing statusLine command at any scope for chaining
existing_statusline_command() {
  for file in "$@"; do
    [ -f "$file" ] || continue
    python3 -c '
import json
import sys
try:
    data = json.loads(open(sys.argv[1], encoding="utf-8").read())
    cmd = str(data.get("statusLine", {}).get("command", ""))
    # Skip if empty or already our collector
    if cmd and not ("statusline-collector.sh" in cmd and "parallel-harness" in cmd):
        print(cmd)
        raise SystemExit(0)
except SystemExit:
    raise
except Exception:
    pass
raise SystemExit(1)
' "$file" 2>/dev/null && return 0
  done
  return 1
}

EXISTING_CMD=$(existing_statusline_command "$LOCAL_SETTINGS" "$PROJECT_SETTINGS" "$USER_SETTINGS" 2>/dev/null || true)

# Skip if already installed — no bridge file to check chain target against,
# so just verify the collector command is present.
if harness_collector_installed "$LOCAL_SETTINGS"; then
  exit 0
fi

if [ -n "$EXISTING_CMD" ]; then
  bash "$SCRIPT_DIR/install-statusline-config.sh" --project-root "$PROJECT_ROOT" --scope local --chain-with "$EXISTING_CMD" >/dev/null 2>&1 || exit 0
else
  bash "$SCRIPT_DIR/install-statusline-config.sh" --project-root "$PROJECT_ROOT" --scope local >/dev/null 2>&1 || exit 0
fi

echo "[parallel-harness] statusLine auto-installed for skill observability."
exit 0
