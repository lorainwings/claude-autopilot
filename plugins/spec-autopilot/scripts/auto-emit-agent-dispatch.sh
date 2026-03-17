#!/usr/bin/env bash
# auto-emit-agent-dispatch.sh
# Hook: PreToolUse(^Task$)
# Purpose: Automatically emit agent_dispatch events when autopilot Task dispatches are detected.
#          Runs alongside check-predecessor-checkpoint.sh — never denies, purely observational.
#
# Mechanism:
#   1. Detect autopilot Task via phase marker (<!-- autopilot-phase:N -->)
#   2. Skip checkpoint-writer Tasks (internal infrastructure)
#   3. Extract phase number and agent label from Task prompt
#   4. Generate stable agent_id: "phase{N}-{slug}"
#   5. Write active agent marker to logs/.active-agent-id (for WS4 tool_use correlation)
#   6. Call emit-agent-event.sh agent_dispatch
#
# Output: Always exit 0 (never deny). Observational hook only.
# Timeout: 5s

set -uo pipefail

# --- Read stdin JSON (PreToolUse: reads stdin directly, not via _hook_preamble.sh) ---
# NOTE: _hook_preamble.sh is designed for PostToolUse. For PreToolUse we replicate
# the same pattern inline to maintain the STDIN_DATA + PROJECT_ROOT_QUICK + Layer 0 contract.
STDIN_DATA=""
if [ ! -t 0 ]; then
  STDIN_DATA=$(cat)
fi
[ -z "$STDIN_DATA" ] && exit 0

# --- Set up shared infrastructure ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

# --- Extract project root (pure bash, ~1ms) ---
PROJECT_ROOT_QUICK=$(echo "$STDIN_DATA" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
if [ -z "$PROJECT_ROOT_QUICK" ]; then
  PROJECT_ROOT_QUICK="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

# --- Layer 0 bypass: no active autopilot session ---
has_active_autopilot "$PROJECT_ROOT_QUICK" || exit 0

# --- Layer 1: Check for autopilot phase marker ---
if ! echo "$STDIN_DATA" | grep -q '"prompt"[[:space:]]*:[[:space:]]*"<!-- autopilot-phase:[0-9]'; then
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

# --- Generate agent_id slug (unicode-safe) ---
# Use python3 for CJK-safe slugification, with bash fallback
SLUG=""
if command -v python3 &>/dev/null; then
  SLUG=$(python3 -c "
import re, sys, unicodedata
label = sys.argv[1]
# Normalize unicode, transliterate to ASCII where possible
nfkd = unicodedata.normalize('NFKD', label)
# Keep ASCII alphanumeric + CJK unified ideographs (U+4E00-U+9FFF)
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
  # Bash fallback: ASCII-only
  SLUG=$(echo "$AGENT_LABEL" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//' | head -c 40)
  [ -z "$SLUG" ] && SLUG="agent"
fi
AGENT_ID="phase${PHASE}-${SLUG}"

# --- Check if background agent ---
IS_BG=false
if echo "$STDIN_DATA" | grep -q '"run_in_background"[[:space:]]*:[[:space:]]*true'; then
  IS_BG=true
fi

# --- Write active agent marker (for WS4 tool_use correlation) ---
# Uses per-phase marker file to reduce collision in parallel dispatch.
# Global file is also written for backward compat (last-writer-wins in parallel).
ACTIVE_AGENT_DIR="$PROJECT_ROOT/logs"
mkdir -p "$ACTIVE_AGENT_DIR" 2>/dev/null || true
echo "$AGENT_ID" > "$ACTIVE_AGENT_DIR/.active-agent-id" 2>/dev/null || true
echo "$AGENT_ID" > "$ACTIVE_AGENT_DIR/.active-agent-phase-${PHASE}" 2>/dev/null || true
if [ -n "$SESSION_ID" ]; then
  SESSION_AGENT_FILE=$(get_session_agent_marker_file "$PROJECT_ROOT" "$SESSION_ID")
  echo "$AGENT_ID" > "$SESSION_AGENT_FILE" 2>/dev/null || true
fi

# --- Record dispatch timestamp for duration calculation (millisecond precision) ---
DISPATCH_TS_FILE="$PROJECT_ROOT/logs/.agent-dispatch-ts-${AGENT_ID}"
python3 -c "import time; print(int(time.time()*1000))" > "$DISPATCH_TS_FILE" 2>/dev/null || date +%s000 > "$DISPATCH_TS_FILE" 2>/dev/null || true

# --- Emit agent_dispatch event (log errors to stderr, never deny) ---
bash "$SCRIPT_DIR/emit-agent-event.sh" agent_dispatch "$PHASE" "$MODE" "$AGENT_ID" "$AGENT_LABEL" "{\"background\":$IS_BG}" >/dev/null 2>&1 ||
  echo "WARNING: agent_dispatch event emission failed for $AGENT_ID" >&2

exit 0
