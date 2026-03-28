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

# --- Extract subagent_type for audit trail (P1-5) ---
SUBAGENT_TYPE=""
if [[ "$STDIN_DATA" =~ \"subagent_type\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
  SUBAGENT_TYPE="${BASH_REMATCH[1]}"
fi

# --- Extract owned_files / owned_artifacts from prompt (governance WS-E) ---
OWNED_ARTIFACTS="[]"
if command -v python3 &>/dev/null; then
  OWNED_ARTIFACTS=$(python3 -c "
import re, sys, json
data = sys.argv[1]
# 查找 prompt 中的 owned_files 声明
m = re.search(r'owned_files[\"\\s:]*\\[([^\\]]{0,2000})\\]', data)
if m:
    raw = m.group(1)
    files = [f.strip().strip('\"').strip(\"'\") for f in raw.split(',') if f.strip()]
    print(json.dumps(files[:50]))
else:
    # 查找 '文件所有权' 段落中的文件列表
    m2 = re.search(r'(?:文件所有权|独占所有权)[^\\n]*\\n((?:[-*]\\s+[^\\n]+\\n?){0,20})', data)
    if m2:
        lines = m2.group(1).strip().split('\\n')
        files = []
        for line in lines:
            path = re.sub(r'^[-*\\s]+', '', line).strip().strip('\`')
            if path and '/' in path:
                files.append(path)
        print(json.dumps(files[:50]))
    else:
        print('[]')
" "$STDIN_DATA" 2>/dev/null) || OWNED_ARTIFACTS="[]"
fi

# --- Resolve agent priority via rules-scanner (governance WS-E) ---
SELECTION_REASON="phase_marker_dispatch"
RESOLVED_PRIORITY="normal"
FALLBACK_REASON=""

if command -v python3 &>/dev/null; then
  # 尝试读取 rules-scanner 缓存或直接调用
  RULES_CACHE="$PROJECT_ROOT/logs/.rules-scanner-cache.json"
  AGENT_POLICY_RESULT=""
  if [ -f "$RULES_CACHE" ]; then
    AGENT_POLICY_RESULT=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    agent_name = sys.argv[2]
    phase = int(sys.argv[3])
    pmap = data.get('agent_priority_map', {})
    if agent_name in pmap:
        a = pmap[agent_name]
        # 检查 forbidden_phases
        if phase in a.get('forbidden_phases', []):
            print(json.dumps({'reason': 'agent_policy_match', 'priority': a['priority'], 'forbidden': True}))
        elif phase in a.get('required_phases', []):
            print(json.dumps({'reason': 'agent_policy_required', 'priority': a['priority'], 'forbidden': False}))
        else:
            print(json.dumps({'reason': 'agent_policy_match', 'priority': a['priority'], 'forbidden': False}))
    elif not pmap:
        print(json.dumps({'reason': 'no_agents_dir', 'priority': 'normal', 'forbidden': False, 'fallback': '.claude/agents/ not found, using default priority'}))
    else:
        print(json.dumps({'reason': 'agent_not_in_policy', 'priority': 'normal', 'forbidden': False, 'fallback': f'{agent_name} not defined in .claude/agents/'}))
except Exception as e:
    print(json.dumps({'reason': 'policy_read_error', 'priority': 'normal', 'forbidden': False, 'fallback': str(e)}))
" "$RULES_CACHE" "$SUBAGENT_TYPE" "$PHASE" 2>/dev/null) || true
  fi

  if [ -n "$AGENT_POLICY_RESULT" ]; then
    _policy_reason=$(echo "$AGENT_POLICY_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('reason',''))" 2>/dev/null) || true
    _policy_priority=$(echo "$AGENT_POLICY_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('priority','normal'))" 2>/dev/null) || true
    _policy_fallback=$(echo "$AGENT_POLICY_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('fallback',''))" 2>/dev/null) || true
    [ -n "$_policy_reason" ] && SELECTION_REASON="$_policy_reason"
    [ -n "$_policy_priority" ] && RESOLVED_PRIORITY="$_policy_priority"
    [ -n "$_policy_fallback" ] && FALLBACK_REASON="$_policy_fallback"
  fi
fi

# --- Write active agent marker (for WS4 tool_use correlation) ---
# Uses per-phase marker file to reduce collision in parallel dispatch.
# Global file is also written for backward compat (last-writer-wins in parallel).
ACTIVE_AGENT_DIR="$PROJECT_ROOT/logs"
mkdir -p "$ACTIVE_AGENT_DIR" 2>/dev/null || true
echo "$AGENT_ID" >"$ACTIVE_AGENT_DIR/.active-agent-id" 2>/dev/null || true
echo "$AGENT_ID" >"$ACTIVE_AGENT_DIR/.active-agent-phase-${PHASE}" 2>/dev/null || true
if [ -n "$SESSION_ID" ]; then
  SESSION_AGENT_FILE=$(get_session_agent_marker_file "$PROJECT_ROOT" "$SESSION_ID")
  echo "$AGENT_ID" >"$SESSION_AGENT_FILE" 2>/dev/null || true
fi

# --- Record dispatch timestamp for duration calculation (millisecond precision) ---
DISPATCH_TS_FILE="$PROJECT_ROOT/logs/.agent-dispatch-ts-${AGENT_ID}"
python3 -c "import time; print(int(time.time()*1000))" >"$DISPATCH_TS_FILE" 2>/dev/null || date +%s000 >"$DISPATCH_TS_FILE" 2>/dev/null || true

# --- Build dispatch payload with full audit trail (governance WS-E) ---
DISPATCH_PAYLOAD=$(python3 -c "
import json, sys
payload = {
    'background': sys.argv[1] == 'true',
    'selection_reason': sys.argv[2],
    'resolved_priority': sys.argv[3],
    'owned_artifacts': json.loads(sys.argv[4]),
}
if sys.argv[5]:
    payload['subagent_type'] = sys.argv[5]
if sys.argv[6]:
    payload['fallback_reason'] = sys.argv[6]
print(json.dumps(payload, ensure_ascii=False))
" "$IS_BG" "$SELECTION_REASON" "$RESOLVED_PRIORITY" "$OWNED_ARTIFACTS" "$SUBAGENT_TYPE" "$FALLBACK_REASON" 2>/dev/null) || {
  # Bash fallback if python3 fails
  DISPATCH_PAYLOAD="{\"background\":$IS_BG,\"selection_reason\":\"$SELECTION_REASON\",\"resolved_priority\":\"$RESOLVED_PRIORITY\""
  [ -n "$SUBAGENT_TYPE" ] && DISPATCH_PAYLOAD="$DISPATCH_PAYLOAD,\"subagent_type\":\"$SUBAGENT_TYPE\""
  [ -n "$FALLBACK_REASON" ] && DISPATCH_PAYLOAD="$DISPATCH_PAYLOAD,\"fallback_reason\":\"$FALLBACK_REASON\""
  DISPATCH_PAYLOAD="$DISPATCH_PAYLOAD}"
}

# --- Write agent-dispatch-record.json for governance audit (WS-E) ---
DISPATCH_RECORD_DIR="$PROJECT_ROOT/logs"
DISPATCH_RECORD_FILE="$DISPATCH_RECORD_DIR/agent-dispatch-record.json"
python3 -c "
import json, sys, os
record_file = sys.argv[1]
agent_id = sys.argv[2]
phase = int(sys.argv[3])
session_id = sys.argv[10] if len(sys.argv) > 10 and sys.argv[10] else ''
new_entry = {
    'agent_id': agent_id,
    'agent_class': sys.argv[4] or 'default',
    'phase': phase,
    'selection_reason': sys.argv[5],
    'resolved_priority': sys.argv[6],
    'owned_artifacts': json.loads(sys.argv[7]),
    'background': sys.argv[8] == 'true',
    'scanned_sources': [],
    'required_validators': ['json_envelope', 'anti_rationalization', 'code_constraint'],
}
if session_id:
    new_entry['session_id'] = session_id
if sys.argv[9]:
    new_entry['fallback_reason'] = sys.argv[9]

# 尝试读取 rules-scanner 缓存中的 scanned_sources
cache_file = os.path.join(os.path.dirname(record_file), '.rules-scanner-cache.json')
if os.path.isfile(cache_file):
    try:
        with open(cache_file) as f:
            cache = json.load(f)
        new_entry['scanned_sources'] = cache.get('scanned_sources', [])
    except Exception:
        pass

# 追加到现有记录
records = []
if os.path.isfile(record_file):
    try:
        with open(record_file) as f:
            records = json.load(f)
        if not isinstance(records, list):
            records = [records]
    except Exception:
        records = []
records.append(new_entry)
# 保留最近 100 条记录
records = records[-100:]
with open(record_file, 'w') as f:
    json.dump(records, f, indent=2, ensure_ascii=False)
" "$DISPATCH_RECORD_FILE" "$AGENT_ID" "$PHASE" "$SUBAGENT_TYPE" "$SELECTION_REASON" "$RESOLVED_PRIORITY" "$OWNED_ARTIFACTS" "$IS_BG" "$FALLBACK_REASON" "$SESSION_ID" 2>/dev/null || true

# --- Emit agent_dispatch event (log errors to stderr, never deny) ---
bash "$SCRIPT_DIR/emit-agent-event.sh" agent_dispatch "$PHASE" "$MODE" "$AGENT_ID" "$AGENT_LABEL" "$DISPATCH_PAYLOAD" >/dev/null 2>&1 ||
  echo "WARNING: agent_dispatch event emission failed for $AGENT_ID" >&2

exit 0
