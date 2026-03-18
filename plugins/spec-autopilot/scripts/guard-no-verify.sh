#!/usr/bin/env bash
# guard-no-verify.sh
# Hook: PreToolUse(Bash)
# Purpose: Block git commands that bypass pre-commit hooks (--no-verify / -n).
#          This is the LAST LINE OF DEFENSE — if git's pre-commit hook is bypassed,
#          the commit goes through unchecked. This hook prevents the bypass itself.
#
# Scope: ALL Bash tool invocations (no Layer 0 autopilot-active bypass).
#        This guard protects the repository at all times, not just during autopilot.
#
# Output: JSON with hookSpecificOutput.permissionDecision on deny.
#         Plain exit 0 on allow.

set -uo pipefail

# --- Read stdin JSON ---
STDIN_DATA=""
if [ ! -t 0 ]; then
  STDIN_DATA=$(cat)
fi
[ -z "$STDIN_DATA" ] && exit 0

# --- Repo scope check: only guard THIS repository (~2ms) ---
# Extract cwd from stdin JSON, resolve its git root, check for our plugin marker.
# Other repositories are not affected.
CWD=$(echo "$STDIN_DATA" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
if [ -n "$CWD" ]; then
  GIT_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || true)
else
  GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
fi
[ -z "$GIT_ROOT" ] && exit 0
[ -f "$GIT_ROOT/plugins/spec-autopilot/hooks/hooks.json" ] || exit 0

# --- Extract command from tool_input (pure bash, ~1ms) ---
# Format: {"tool_input":{"command":"..."}}
COMMAND=$(echo "$STDIN_DATA" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
[ -z "$COMMAND" ] && exit 0

# --- Detect --no-verify bypass in git commands ---
# Patterns to block:
#   1. git <subcommand> --no-verify
#   2. git commit -<flags>n  (short form: -n = --no-verify for commit)
#   3. git -c commit.noVerify=true ...
#   4. GIT_NO_VERIFY environment variable

BLOCKED=""
REASON=""

# Pattern 1: --no-verify flag on any git command
if echo "$COMMAND" | grep -qE '\bgit\b.*--no-verify\b'; then
  BLOCKED="yes"
  REASON="--no-verify flag detected. Git hooks must not be bypassed."
fi

# Pattern 2: git commit -n (short form of --no-verify)
# Match: git commit ... -n or -<other_flags>n (e.g., -amn, -nm)
# Avoid false positives: only match when 'git commit' is present
if [ -z "$BLOCKED" ]; then
  if echo "$COMMAND" | grep -qE '\bgit\b\s+commit\b' && echo "$COMMAND" | grep -qE '\s-[a-zA-Z]*n'; then
    BLOCKED="yes"
    REASON="git commit -n (short for --no-verify) detected. Git hooks must not be bypassed."
  fi
fi

# Pattern 3: git -c commit.noVerify=true
if [ -z "$BLOCKED" ]; then
  if echo "$COMMAND" | grep -qiE '\bgit\b.*-c\s+commit\.noVerify\s*=\s*true'; then
    BLOCKED="yes"
    REASON="commit.noVerify=true config override detected. Git hooks must not be bypassed."
  fi
fi

# Pattern 4: GIT_NO_VERIFY or HUSKY=0 environment variable
if [ -z "$BLOCKED" ]; then
  if echo "$COMMAND" | grep -qE '(GIT_NO_VERIFY|HUSKY\s*=\s*0)\b'; then
    BLOCKED="yes"
    REASON="Hook-bypass environment variable detected. Git hooks must not be bypassed."
  fi
fi

# --- Output deny if blocked ---
if [ "$BLOCKED" = "yes" ]; then
  # Escape reason for JSON
  REASON_ESCAPED=$(echo "$REASON" | sed 's/"/\\"/g')
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "[guard-no-verify] ${REASON_ESCAPED} Remove the flag and let git hooks validate your commit."
  }
}
EOF
  exit 0
fi

# All checks passed — allow
exit 0
