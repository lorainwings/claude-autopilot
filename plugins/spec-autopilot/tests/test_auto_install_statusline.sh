#!/usr/bin/env bash
# test_auto_install_statusline.sh — stale path detection + $CLAUDE_PLUGIN_ROOT resilience
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"

echo "--- auto-install statusline (stale detection + env var) ---"

# ---------------------------------------------------------------
# 1. Fresh install: no prior config → installs with ${CLAUDE_PLUGIN_ROOT:-...} format
# ---------------------------------------------------------------
echo "1. Fresh install writes CLAUDE_PLUGIN_ROOT format"

TMP1=$(mktemp -d)
trap 'rm -rf "$TMP1"' EXIT
git -C "$TMP1" init >/dev/null 2>&1
mkdir -p "$TMP1/.claude"
touch "$TMP1/.claude/autopilot.config.yaml"

bash "$SCRIPT_DIR/auto-install-statusline.sh" <<EOF
{"cwd":"$TMP1"}
EOF
EXIT_CODE=$?
assert_exit "1a. auto-install exits 0" 0 "$EXIT_CODE"

SETTINGS1="$TMP1/.claude/settings.local.json"
assert_file_exists "1b. settings.local.json created" "$SETTINGS1"

CONTENT1=$(cat "$SETTINGS1" 2>/dev/null || true)
assert_contains "1c. command uses CLAUDE_PLUGIN_ROOT" "$CONTENT1" 'CLAUDE_PLUGIN_ROOT'
assert_contains "1d. command has absolute fallback" "$CONTENT1" 'runtime/scripts/statusline-collector.sh'

# ---------------------------------------------------------------
# 2. Stale path: existing config points to non-existent file → re-installs
# ---------------------------------------------------------------
echo ""
echo "2. Stale path triggers re-install"

TMP2=$(mktemp -d)
# update trap to clean both
trap 'rm -rf "$TMP1" "$TMP2"' EXIT
git -C "$TMP2" init >/dev/null 2>&1
mkdir -p "$TMP2/.claude"
touch "$TMP2/.claude/autopilot.config.yaml"

# Write a stale config with a non-existent absolute path
cat > "$TMP2/.claude/settings.local.json" <<'STALE'
{
  "statusLine": {
    "type": "command",
    "command": "bash /nonexistent/old-version/5.0.0/runtime/scripts/statusline-collector.sh",
    "padding": 1
  }
}
STALE

bash "$SCRIPT_DIR/auto-install-statusline.sh" <<EOF
{"cwd":"$TMP2"}
EOF
EXIT_CODE=$?
assert_exit "2a. auto-install exits 0 on stale" 0 "$EXIT_CODE"

CONTENT2=$(cat "$TMP2/.claude/settings.local.json" 2>/dev/null || true)
assert_not_contains "2b. stale path removed" "$CONTENT2" '/nonexistent/old-version'
assert_contains "2c. re-installed with CLAUDE_PLUGIN_ROOT" "$CONTENT2" 'CLAUDE_PLUGIN_ROOT'

# ---------------------------------------------------------------
# 3. Valid config: existing config with valid path → skip (no re-install)
# ---------------------------------------------------------------
echo ""
echo "3. Valid config is not overwritten"

TMP3=$(mktemp -d)
trap 'rm -rf "$TMP1" "$TMP2" "$TMP3"' EXIT
git -C "$TMP3" init >/dev/null 2>&1
mkdir -p "$TMP3/.claude"
touch "$TMP3/.claude/autopilot.config.yaml"

# Write a valid config pointing to the actual collector script
REAL_COLLECTOR="$SCRIPT_DIR/statusline-collector.sh"
cat > "$TMP3/.claude/settings.local.json" <<VALID
{
  "statusLine": {
    "type": "command",
    "command": "bash $REAL_COLLECTOR",
    "padding": 1
  }
}
VALID

BEFORE=$(cat "$TMP3/.claude/settings.local.json")
bash "$SCRIPT_DIR/auto-install-statusline.sh" <<EOF
{"cwd":"$TMP3"}
EOF
EXIT_CODE=$?
assert_exit "3a. auto-install exits 0 on valid" 0 "$EXIT_CODE"

AFTER=$(cat "$TMP3/.claude/settings.local.json")
if [ "$BEFORE" = "$AFTER" ]; then
  green "  PASS: 3b. valid config not overwritten"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3b. valid config was unexpectedly overwritten"
  FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------
# 4. Env var format: config with ${CLAUDE_PLUGIN_ROOT} → skip stale check
# ---------------------------------------------------------------
echo ""
echo "4. Env var format skips stale check"

TMP4=$(mktemp -d)
trap 'rm -rf "$TMP1" "$TMP2" "$TMP3" "$TMP4"' EXIT
git -C "$TMP4" init >/dev/null 2>&1
mkdir -p "$TMP4/.claude"
touch "$TMP4/.claude/autopilot.config.yaml"

# Write config with env var format (path may not exist locally, but that's OK)
cat > "$TMP4/.claude/settings.local.json" <<'ENVVAR'
{
  "statusLine": {
    "type": "command",
    "command": "bash ${CLAUDE_PLUGIN_ROOT:-/some/fallback}/runtime/scripts/statusline-collector.sh",
    "padding": 1
  }
}
ENVVAR

BEFORE4=$(cat "$TMP4/.claude/settings.local.json")
bash "$SCRIPT_DIR/auto-install-statusline.sh" <<EOF
{"cwd":"$TMP4"}
EOF
EXIT_CODE=$?
assert_exit "4a. auto-install exits 0 on env var format" 0 "$EXIT_CODE"

AFTER4=$(cat "$TMP4/.claude/settings.local.json")
if [ "$BEFORE4" = "$AFTER4" ]; then
  green "  PASS: 4b. env var format config not overwritten"
  PASS=$((PASS + 1))
else
  red "  FAIL: 4b. env var format config was unexpectedly overwritten"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0
