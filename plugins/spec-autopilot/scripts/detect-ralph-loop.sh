#!/usr/bin/env bash
# detect-ralph-loop.sh
# Purpose: Detect ralph-loop plugin availability for Phase 5 dispatch.
# Output (stdout): "available" | "fallback" | "blocked"
#
# Usage: bash detect-ralph-loop.sh [project_root]
#
# Checks:
#   1. .claude/settings.json → enabledPlugins contains ralph-loop
#   2. autopilot.config.yaml → phases.implementation.ralph_loop.fallback_enabled

set -euo pipefail

PROJECT_ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

SETTINGS_FILE="$PROJECT_ROOT/.claude/settings.json"
CONFIG_FILE="$PROJECT_ROOT/.claude/autopilot.config.yaml"

# Check if ralph-loop plugin is enabled in settings.json
ralph_loop_enabled() {
  if [ ! -f "$SETTINGS_FILE" ]; then
    return 1
  fi

  python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    plugins = data.get('enabledPlugins', [])
    # Check if any plugin path contains 'ralph-loop'
    found = any('ralph-loop' in p for p in plugins)
    sys.exit(0 if found else 1)
except Exception:
    sys.exit(1)
" "$SETTINGS_FILE" 2>/dev/null
}

# Check if fallback is enabled in autopilot.config.yaml
fallback_enabled() {
  if [ ! -f "$CONFIG_FILE" ]; then
    return 1
  fi

  python3 -c "
import sys
try:
    import yaml
    with open(sys.argv[1]) as f:
        data = yaml.safe_load(f)
    fb = data.get('phases', {}).get('implementation', {}).get('ralph_loop', {}).get('fallback_enabled', False)
    sys.exit(0 if fb else 1)
except ImportError:
    # Fallback: simple text search if PyYAML not available
    with open(sys.argv[1]) as f:
        content = f.read()
    if 'fallback_enabled: true' in content or 'fallback_enabled: True' in content:
        sys.exit(0)
    sys.exit(1)
except Exception:
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
