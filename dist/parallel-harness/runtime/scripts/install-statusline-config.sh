#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SCOPE="local"
CHAIN_WITH=""

while [ $# -gt 0 ]; do
  case "${1:-}" in
    --scope)
      SCOPE="${2:-local}"
      shift 2
      ;;
    --project-root)
      PROJECT_ROOT="$(cd "${2:-$PROJECT_ROOT}" && pwd)"
      shift 2
      ;;
    --chain-with)
      CHAIN_WITH="${2:-}"
      shift 2
      ;;
    *)
      echo "Usage: install-statusline-config.sh [--scope local|project|user] [--project-root PATH] [--chain-with CMD]" >&2
      exit 1
      ;;
  esac
done

case "$SCOPE" in
  local | project | user) ;;
  *)
    echo "ERROR: invalid scope '$SCOPE' (expected local|project|user)" >&2
    exit 1
    ;;
esac

COLLECTOR_SCRIPT="$SCRIPT_DIR/statusline-collector.sh"
[ -f "$COLLECTOR_SCRIPT" ] || {
  echo "ERROR: collector script not found: $COLLECTOR_SCRIPT" >&2
  exit 1
}

if [ "$SCOPE" = "user" ]; then
  CLAUDE_DIR="${HOME}/.claude"
  SETTINGS_FILE="$CLAUDE_DIR/settings.json"
  BRIDGE_SCRIPT="$CLAUDE_DIR/statusline-parallel-harness.sh"
else
  CLAUDE_DIR="$PROJECT_ROOT/.claude"
  if [ "$SCOPE" = "project" ]; then
    SETTINGS_FILE="$CLAUDE_DIR/settings.json"
  else
    SETTINGS_FILE="$CLAUDE_DIR/settings.local.json"
  fi
  BRIDGE_SCRIPT="$CLAUDE_DIR/statusline-parallel-harness.sh"
fi

mkdir -p "$CLAUDE_DIR"

if [ -n "$CHAIN_WITH" ]; then
  # Escape single quotes for safe embedding in the generated bridge script
  CHAIN_WITH_SAFE=$(printf '%s' "$CHAIN_WITH" | sed "s/'/'\\\\''/g")
  cat >"$BRIDGE_SCRIPT" <<CHAINEOF
#!/usr/bin/env bash
# chain-target: $CHAIN_WITH
set -uo pipefail
INPUT=\$(cat)
HARNESS_OUT=\$(printf '%s' "\$INPUT" | bash "$COLLECTOR_SCRIPT" 2>/dev/null || echo "[harness] ready")
PREV_OUT=\$(printf '%s' "\$INPUT" | bash -c '$CHAIN_WITH_SAFE' 2>/dev/null || true)
if [ -n "\$PREV_OUT" ]; then
  printf "%s | %s" "\$PREV_OUT" "\$HARNESS_OUT"
else
  printf "%s" "\$HARNESS_OUT"
fi
CHAINEOF
else
  cat >"$BRIDGE_SCRIPT" <<EOF
#!/usr/bin/env bash
# chain-target:
set -euo pipefail
exec bash "$COLLECTOR_SCRIPT"
EOF
fi
chmod +x "$BRIDGE_SCRIPT"

python3 - "$SETTINGS_FILE" "$BRIDGE_SCRIPT" <<'PY'
import json
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])
command_path = sys.argv[2]

data = {}
if settings_path.exists():
    try:
        data = json.loads(settings_path.read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            data = {}
    except Exception:
        backup = settings_path.with_suffix(settings_path.suffix + ".bak")
        settings_path.replace(backup)
        data = {}

if "$schema" not in data:
    data["$schema"] = "https://json.schemastore.org/droid-settings.json"

data["statusLine"] = {
    "type": "command",
    "command": command_path,
    "padding": 1,
}

settings_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

if [ "$SCOPE" = "local" ] && git -C "$PROJECT_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  GIT_DIR="$(git -C "$PROJECT_ROOT" rev-parse --git-dir)"
  case "$GIT_DIR" in
    /*) ;;
    *) GIT_DIR="$PROJECT_ROOT/$GIT_DIR" ;;
  esac
  EXCLUDE_FILE="$GIT_DIR/info/exclude"
  touch "$EXCLUDE_FILE"
  if ! grep -qxF '.claude/settings.local.json' "$EXCLUDE_FILE" 2>/dev/null; then
    printf "%s\n" '.claude/settings.local.json' >>"$EXCLUDE_FILE"
  fi
  if ! grep -qxF '.claude/statusline-parallel-harness.sh' "$EXCLUDE_FILE" 2>/dev/null; then
    printf "%s\n" '.claude/statusline-parallel-harness.sh' >>"$EXCLUDE_FILE"
  fi
fi

printf "statusLine installed\n"
printf "scope=%s\n" "$SCOPE"
printf "settings=%s\n" "$SETTINGS_FILE"
printf "bridge=%s\n" "$BRIDGE_SCRIPT"
if [ -n "$CHAIN_WITH" ]; then
  printf "chained_with=%s\n" "$CHAIN_WITH"
fi
