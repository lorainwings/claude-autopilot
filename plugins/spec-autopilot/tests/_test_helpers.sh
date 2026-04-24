#!/usr/bin/env bash
# _test_helpers.sh — Shared assertion functions for spec-autopilot test suite
# Extracted from test-hooks.sh:15-50

PASS=0
FAIL=0

green() { printf "\033[32m%s\033[0m\n" "$1"; }
red() { printf "\033[31m%s\033[0m\n" "$1"; }

# Seed active-agent-state.json with (session_key, phase, agent_id).
# Delegates to production `agent_state_dispatch` so fields stay aligned with
# real hook writes (global.updated_at, sessions[key].dispatched_at, etc.) —
# any future schema change is caught by tests without further helper edits.
# Usage: set_active_agent_state <project_root> <session_key> <phase> <agent_id>
set_active_agent_state() {
  local project_root="$1" session_key="${2:-}" phase="${3:-0}" agent_id="${4:-}"
  [ -z "$agent_id" ] && return 0
  local _agent_state_sh
  _agent_state_sh="$(cd "$(dirname "${BASH_SOURCE[0]}")/../runtime/scripts" && pwd)/_agent_state.sh"
  # shellcheck source=/dev/null
  source "$_agent_state_sh"
  agent_state_dispatch "$project_root" "$session_key" "$phase" "$agent_id"
}

# Clear any active-agent-state entries for the given phase (global + phases[<phase>]).
# Preserves unrelated session entries for parallel scenarios.
# Usage: clear_active_agent_phase <project_root> <phase>
clear_active_agent_phase() {
  local project_root="$1" phase="${2:-0}"
  local path="$project_root/logs/.active-agent-state.json"
  [ -f "$path" ] || return 0
  AGS_PATH="$path" AGS_PHASE="$phase" python3 - <<'PY' 2>/dev/null || true
import json, os
path = os.environ["AGS_PATH"]
phase = os.environ["AGS_PHASE"]
try:
    state = json.load(open(path))
except (FileNotFoundError, json.JSONDecodeError):
    raise SystemExit(0)
state.get("phases", {}).pop(str(phase), None)
if state.get("global", {}).get("phase") == int(phase) if str(phase).isdigit() else False:
    state["global"] = {}
json.dump(state, open(path, "w"), ensure_ascii=False, indent=2)
PY
}

# Remove active-agent-state entirely. Usage: reset_active_agent_state <project_root>
reset_active_agent_state() {
  local project_root="$1"
  rm -f "$project_root/logs/.active-agent-state.json" \
    "$project_root/logs/.agent-state.lock" 2>/dev/null || true
}

assert_exit() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" -eq "$expected" ]; then
    green "  PASS: $name (exit $actual)"
    PASS=$((PASS + 1))
  else
    red "  FAIL: $name (expected exit $expected, got $actual)"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local name="$1" haystack="$2" needle="$3"
  # Use here-string (<<<) instead of echo|grep pipe to avoid SIGPIPE
  # when grep -q closes stdin early under pipefail (Ubuntu/GNU bash).
  if grep -q -- "$needle" <<<"$haystack"; then
    green "  PASS: $name (contains '$needle')"
    PASS=$((PASS + 1))
  else
    red "  FAIL: $name (missing '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local name="$1" haystack="$2" needle="$3"
  # Use here-string (<<<) instead of echo|grep pipe to avoid SIGPIPE
  # when grep -q closes stdin early under pipefail (Ubuntu/GNU bash).
  if ! grep -q -- "$needle" <<<"$haystack"; then
    green "  PASS: $name (correctly missing '$needle')"
    PASS=$((PASS + 1))
  else
    red "  FAIL: $name (unexpectedly contains '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

assert_json_field() {
  local name="$1" json="$2" field="$3" expected="$4"
  local actual
  actual=$(python3 -c "import json,sys; print(json.load(sys.stdin).get('$field',''))" <<<"$json" 2>/dev/null || echo "")
  if [ "$actual" = "$expected" ]; then
    green "  PASS: $name (.$field == '$expected')"
    PASS=$((PASS + 1))
  else
    red "  FAIL: $name (.$field: expected '$expected', got '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  local name="$1" filepath="$2"
  if [ -f "$filepath" ]; then
    green "  PASS: $name (file exists)"
    PASS=$((PASS + 1))
  else
    red "  FAIL: $name (file not found: $filepath)"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_contains() {
  local name="$1" filepath="$2" needle="$3"
  if grep -q -- "$needle" "$filepath"; then
    green "  PASS: $name (contains '$needle')"
    PASS=$((PASS + 1))
  else
    red "  FAIL: $name (missing '$needle' in $filepath)"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_not_contains() {
  local name="$1" filepath="$2" needle="$3"
  if ! grep -q -- "$needle" "$filepath"; then
    green "  PASS: $name (correctly missing '$needle')"
    PASS=$((PASS + 1))
  else
    red "  FAIL: $name (unexpectedly contains '$needle' in $filepath)"
    FAIL=$((FAIL + 1))
  fi
}
