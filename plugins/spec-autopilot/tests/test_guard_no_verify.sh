#!/usr/bin/env bash
# test_guard_no_verify.sh — Regression tests for git hook bypass prevention
# Tests two layers:
#   1. guard-no-verify.sh (Claude Code PreToolUse Bash hook)
#   2. setup-hooks.sh (hook activation script)
#   3. End-to-end: fresh clone simulation → setup → commit blocked
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TEST_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"
source "$TEST_DIR/_test_helpers.sh"

GUARD_SCRIPT="$PLUGIN_ROOT/scripts/guard-no-verify.sh"
SETUP_SCRIPT="$REPO_ROOT/scripts/setup-hooks.sh"
GITHOOKS_DIR="$REPO_ROOT/.githooks"

# ============================================
# Part 1: guard-no-verify.sh unit tests
# ============================================
echo "--- guard-no-verify.sh: bypass detection ---"

# Helper: run guard with a given command and cwd
run_guard() {
  local cmd="$1" cwd="${2:-$REPO_ROOT}"
  local escaped_cmd
  escaped_cmd=$(echo "$cmd" | sed 's/"/\\"/g')
  echo "{\"tool_input\":{\"command\":\"${escaped_cmd}\"},\"cwd\":\"${cwd}\"}" | bash "$GUARD_SCRIPT" 2>/dev/null
}

# 1a. --no-verify must be blocked
output=$(run_guard "git commit --no-verify -m \"test\"")
echo "$output" | grep -q '"deny"'
assert_exit "1a. --no-verify blocked" 0 $?

# 1b. -n short flag must be blocked
output=$(run_guard "git commit -n -m \"test\"")
echo "$output" | grep -q '"deny"'
assert_exit "1b. -n short flag blocked" 0 $?

# 1c. -nm combined flags must be blocked
output=$(run_guard "git commit -nm \"test\"")
echo "$output" | grep -q '"deny"'
assert_exit "1c. -nm combined blocked" 0 $?

# 1d. -amn combined flags must be blocked
output=$(run_guard "git commit -amn \"test\"")
echo "$output" | grep -q '"deny"'
assert_exit "1d. -amn combined blocked" 0 $?

# 1e. -c commit.noVerify=true must be blocked
output=$(run_guard "git -c commit.noVerify=true commit -m \"test\"")
echo "$output" | grep -q '"deny"'
assert_exit "1e. -c commit.noVerify=true blocked" 0 $?

# 1f. HUSKY=0 must be blocked
output=$(run_guard "HUSKY=0 git commit -m \"test\"")
echo "$output" | grep -q '"deny"'
assert_exit "1f. HUSKY=0 blocked" 0 $?

# 1g. push --no-verify must be blocked
output=$(run_guard "git push --no-verify")
echo "$output" | grep -q '"deny"'
assert_exit "1g. push --no-verify blocked" 0 $?

echo ""
echo "--- guard-no-verify.sh: legitimate commands ---"

# 2a. Normal commit must pass
output=$(run_guard "git commit -m \"fix: something\"")
[ -z "$output" ]
assert_exit "2a. normal commit allowed" 0 $?

# 2b. Non-git command must pass
output=$(run_guard "ls -la")
[ -z "$output" ]
assert_exit "2b. non-git command allowed" 0 $?

# 2c. git status must pass
output=$(run_guard "git status")
[ -z "$output" ]
assert_exit "2c. git status allowed" 0 $?

echo ""
echo "--- guard-no-verify.sh: repo scope isolation ---"

# 3a. Other repo: --no-verify must be allowed
output=$(run_guard "git commit --no-verify -m \"test\"" "/tmp")
[ -z "$output" ]
assert_exit "3a. other repo --no-verify allowed" 0 $?

# 3b. Non-existent path: must be allowed
output=$(run_guard "git commit --no-verify -m \"test\"" "/nonexistent/path")
[ -z "$output" ]
assert_exit "3b. non-existent path allowed" 0 $?

# ============================================
# Part 2: setup-hooks.sh tests
# ============================================
echo ""
echo "--- setup-hooks.sh: activation script ---"

# 4a. Script exists and is executable
[ -f "$SETUP_SCRIPT" ] && [ -x "$SETUP_SCRIPT" ]
assert_exit "4a. setup-hooks.sh exists and executable" 0 $?

# 4b. .githooks/pre-commit exists in repo
[ -f "$GITHOOKS_DIR/pre-commit" ]
assert_exit "4b. .githooks/pre-commit exists" 0 $?

# 4c. .githooks/pre-commit is executable
[ -x "$GITHOOKS_DIR/pre-commit" ]
assert_exit "4c. .githooks/pre-commit is executable" 0 $?

# 4d. .githooks/pre-commit uses sedi() not raw sed -i ''
sedi_count=$(grep -c "^sedi()" "$GITHOOKS_DIR/pre-commit" || echo 0)
raw_sed_count=$(awk 'NR>13 && /sed -i/' "$GITHOOKS_DIR/pre-commit" | wc -l | tr -d ' ')
[ "$sedi_count" -ge 1 ] && [ "$raw_sed_count" -eq 0 ]
assert_exit "4d. cross-platform sedi() used, no raw sed -i" 0 $?

# ============================================
# Part 3: End-to-end fresh clone simulation
# ============================================
echo ""
echo "--- E2E: fresh clone → setup → commit blocked by CHANGELOG ---"

TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

# 5a. Simulate fresh clone: realistic repo structure
E2E_DIR="$TMP_ROOT/e2e-repo"
mkdir -p "$E2E_DIR/.githooks"
mkdir -p "$E2E_DIR/plugins/spec-autopilot/.claude-plugin"
mkdir -p "$E2E_DIR/plugins/spec-autopilot/hooks"
mkdir -p "$E2E_DIR/scripts"

# Init git repo
git -C "$E2E_DIR" init -q

# Copy tracked hook files
cp "$GITHOOKS_DIR/pre-commit" "$E2E_DIR/.githooks/pre-commit"
chmod +x "$E2E_DIR/.githooks/pre-commit"
cp "$SETUP_SCRIPT" "$E2E_DIR/scripts/setup-hooks.sh"
chmod +x "$E2E_DIR/scripts/setup-hooks.sh"

# Realistic plugin structure (correct .claude-plugin/ subdirectory)
echo '{"version": "1.0.0"}' > "$E2E_DIR/plugins/spec-autopilot/.claude-plugin/plugin.json"
echo '{}' > "$E2E_DIR/plugins/spec-autopilot/hooks/hooks.json"

# Initial commit so we have a HEAD
git -C "$E2E_DIR" add -A
git -C "$E2E_DIR" -c user.name="Test" -c user.email="test@test.com" commit -q -m "initial"

# 5b. Run setup-hooks.sh
setup_output=$(cd "$E2E_DIR" && bash scripts/setup-hooks.sh 2>&1)
setup_exit=$?
assert_exit "5a. setup-hooks.sh runs successfully in fresh repo" 0 $setup_exit

# 5c. Verify core.hooksPath is set
hooks_path=$(git -C "$E2E_DIR" config --local core.hooksPath 2>/dev/null || echo "")
[ "$hooks_path" = ".githooks" ]
assert_exit "5b. core.hooksPath = .githooks after setup" 0 $?

# 5d. Simulate a plugin file change without CHANGELOG.md → must be blocked by CHANGELOG check
echo "// new code" > "$E2E_DIR/plugins/spec-autopilot/app.ts"
git -C "$E2E_DIR" add "$E2E_DIR/plugins/spec-autopilot/app.ts"

commit_exit=0
commit_output=$(git -C "$E2E_DIR" -c user.name="Test" -c user.email="test@test.com" commit -m "test: should be blocked" 2>&1) || commit_exit=$?

# Verify: exit code is non-zero (commit was blocked)
[ "$commit_exit" -ne 0 ]
assert_exit "5c. commit blocked (non-zero exit)" 0 $?

# Verify: blocked SPECIFICALLY by CHANGELOG check, not by some other error
echo "$commit_output" | grep -q "CHANGELOG.md not updated"
assert_exit "5d. blocked reason is CHANGELOG.md missing (not other error)" 0 $?

# ============================================
# Summary
# ============================================
echo ""
echo "=== guard-no-verify + setup-hooks: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
