#!/usr/bin/env bash
# detect-ralph-loop.sh
# Purpose: Detect ralph-loop plugin availability for Phase 5 dispatch.
# Output (stdout): "available" | "fallback" | "blocked"
#
# Usage: bash detect-ralph-loop.sh [project_root]
#
# Checks all 3 settings scopes (official spec):
#   1. ~/.claude/settings.json              (user scope)
#   2. <project>/.claude/settings.json      (project scope)
#   3. <project>/.claude/settings.local.json (local scope)
# Then checks autopilot.config.yaml for fallback config.

set -uo pipefail

PROJECT_ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
CONFIG_FILE="$PROJECT_ROOT/.claude/autopilot.config.yaml"

# All settings files to check (in priority order: local > project > user)
SETTINGS_FILES=(
  "$PROJECT_ROOT/.claude/settings.local.json"
  "$PROJECT_ROOT/.claude/settings.json"
  "$HOME/.claude/settings.json"
)

# Check if ralph-loop plugin is enabled in any settings scope
ralph_loop_enabled() {
  if ! command -v python3 &>/dev/null; then
    return 1
  fi

  for settings_file in "${SETTINGS_FILES[@]}"; do
    if [ ! -f "$settings_file" ]; then
      continue
    fi

    python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    plugins = data.get('enabledPlugins', [])
    found = any('ralph-loop' in str(p) for p in plugins)
    sys.exit(0 if found else 1)
except Exception:
    sys.exit(1)
" "$settings_file" 2>/dev/null && return 0
  done

  return 1
}

# Check if fallback is enabled in autopilot.config.yaml
# Uses regex-based parsing to avoid PyYAML dependency
fallback_enabled() {
  if [ ! -f "$CONFIG_FILE" ]; then
    return 1
  fi

  if ! command -v python3 &>/dev/null; then
    return 1
  fi

  python3 -c "
import re, sys

with open(sys.argv[1]) as f:
    content = f.read()

# Try PyYAML first if available
try:
    import yaml
    data = yaml.safe_load(content)
    fb = data.get('phases', {}).get('implementation', {}).get('ralph_loop', {}).get('fallback_enabled', False)
    sys.exit(0 if fb else 1)
except ImportError:
    pass

# Regex fallback: match fallback_enabled with various YAML true values
# Handles: 'true', 'True', 'TRUE', 'yes', 'Yes', 'on', 'On'
# Ignores commented lines and unrelated keys
for line in content.splitlines():
    stripped = line.strip()
    if stripped.startswith('#'):
        continue
    m = re.match(r'fallback_enabled\s*:\s*(true|yes|on)\s*$', stripped, re.IGNORECASE)
    if m:
        sys.exit(0)

sys.exit(1)
" "$CONFIG_FILE" 2>/dev/null
}

# Main detection logic
if ralph_loop_enabled; then
  echo "available"
elif fallback_enabled; then
  echo "fallback"
else
  echo "blocked"
fi
