#!/usr/bin/env bash
# auto-install-statusline.sh
# Hook: SessionStart (async)
# Purpose: Auto-detect and install statusLine configuration if not already present.
#          Ensures GUI telemetry receives status_snapshot events without manual setup.
#
# Output: stdout text is added to Claude's context (SessionStart behavior).
# Exit codes: 0 (informational only, never blocks)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECTOR_SCRIPT="$SCRIPT_DIR/statusline-collector.sh"
[ -f "$COLLECTOR_SCRIPT" ] || exit 0

# --- Resolve project root ---
STDIN_DATA=""
if [ ! -t 0 ]; then
  STDIN_DATA=$(cat)
fi

PROJECT_ROOT=""
if [ -n "$STDIN_DATA" ]; then
  PROJECT_ROOT=$(echo "$STDIN_DATA" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
fi
[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# --- Project relevance guard: only install in projects that use autopilot ---
[ -d "$PROJECT_ROOT/openspec" ] || [ -f "$PROJECT_ROOT/.claude/autopilot.config.yaml" ] || exit 0

# --- Check if statusLine is already configured in any scope ---
# Priority: local > project > user
CLAUDE_DIR="$PROJECT_ROOT/.claude"
LOCAL_SETTINGS="$CLAUDE_DIR/settings.local.json"
PROJECT_SETTINGS="$CLAUDE_DIR/settings.json"
USER_SETTINGS="${HOME}/.claude/settings.json"

statusline_configured() {
  local file="$1"
  [ -f "$file" ] || return 1
  python3 -c "
import json, sys
try:
    d = json.loads(open(sys.argv[1]).read())
    sl = d.get('statusLine')
    if sl and isinstance(sl, dict) and sl.get('command'):
        sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
" "$file" 2>/dev/null
}

if statusline_configured "$LOCAL_SETTINGS" ||
  statusline_configured "$PROJECT_SETTINGS" ||
  statusline_configured "$USER_SETTINGS"; then
  exit 0
fi

# --- Auto-install statusLine (local scope, non-intrusive) ---
bash "$SCRIPT_DIR/install-statusline-config.sh" --project-root "$PROJECT_ROOT" --scope local >/dev/null 2>&1 || exit 0

echo "[autopilot] statusLine hook auto-installed (scope: local). GUI telemetry is now active."
exit 0
