#!/usr/bin/env bash
# test_install_statusline_chain.sh — chain mode preserves existing statusLine + health-check detects collector
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"

echo "--- install statusline (chain mode + health check) ---"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
git -C "$TMP_DIR" init >/dev/null 2>&1

CLAUDE_DIR="$TMP_DIR/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.local.json"
mkdir -p "$CLAUDE_DIR"

# --- Pre-seed: existing statusLine from a different plugin ---
EXISTING_CMD='bash -c "echo [other-plugin] running"'
cat >"$SETTINGS_FILE" <<JSON
{
  "\$schema": "https://json.schemastore.org/claude-code-settings.json",
  "statusLine": {
    "type": "command",
    "command": $(printf '%s' "$EXISTING_CMD" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))"),
    "padding": 1
  }
}
JSON

# --- Install in chain mode ---
OUTPUT=$(bash "$SCRIPT_DIR/install-statusline-config.sh" --scope local --project-root "$TMP_DIR" --mode chain 2>&1)
EXIT_CODE=$?
assert_exit "chain install exits 0" 0 "$EXIT_CODE"

CONTENT=$(cat "$SETTINGS_FILE")
assert_contains "chain command references collector" "$CONTENT" "statusline-collector.sh"
assert_contains "chain command preserves existing (base64)" "$CONTENT" "PREV_B64="
assert_contains "settings remain valid JSON" "$CONTENT" '"statusLine"'

# --- JSON validity ---
if python3 -m json.tool "$SETTINGS_FILE" >/dev/null 2>&1; then
  green "  PASS: settings is valid JSON after chain install"
  PASS=$((PASS + 1))
else
  red "  FAIL: settings JSON corrupted"
  FAIL=$((FAIL + 1))
fi

# --- Health check should now report healthy (collector in chain) ---
HEALTH_OUT=$(bash "$SCRIPT_DIR/statusline-health-check.sh" --project-root "$TMP_DIR" 2>/dev/null)
assert_contains "health check reports healthy" "$HEALTH_OUT" '"healthy":true'
if echo "$HEALTH_OUT" | grep -q "autopilot_collector_not_in_chain"; then
  red "  FAIL: not_in_chain falsely reported after chain install"
  FAIL=$((FAIL + 1))
else
  green "  PASS: not_in_chain not reported"
  PASS=$((PASS + 1))
fi

# --- Negative case: settings without spec-autopilot collector should report not-in-chain ---
cat >"$SETTINGS_FILE" <<'JSON'
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "statusLine": {
    "type": "command",
    "command": "bash -c 'echo [foreign-only]'",
    "padding": 1
  }
}
JSON

NEG_OUT=$(bash "$SCRIPT_DIR/statusline-health-check.sh" --project-root "$TMP_DIR" 2>/dev/null)
assert_contains "negative case reports unhealthy" "$NEG_OUT" '"healthy":false'
assert_contains "negative case lists not_in_chain" "$NEG_OUT" "autopilot_collector_not_in_chain"

# --- Replace mode bypasses chain detection ---
bash "$SCRIPT_DIR/install-statusline-config.sh" --scope local --project-root "$TMP_DIR" --mode replace >/dev/null 2>&1
REPLACE_CONTENT=$(cat "$SETTINGS_FILE")
if echo "$REPLACE_CONTENT" | grep -q "PREV_B64="; then
  red "  FAIL: replace mode should not chain"
  FAIL=$((FAIL + 1))
else
  green "  PASS: replace mode overwrites cleanly"
  PASS=$((PASS + 1))
fi
assert_contains "replace mode still has collector" "$REPLACE_CONTENT" "statusline-collector.sh"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
