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

GUARD_SCRIPT="$PLUGIN_ROOT/runtime/scripts/guard-no-verify.sh"
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
# Scope: tests the CHANGELOG gate specifically.
# This uses a minimal repo WITHOUT run_all.sh / build-dist.sh
# so the pre-commit hook skips the test suite and goes straight
# to the CHANGELOG check. The full build chain is tested in
# test_build_dist.sh (including the fresh-clone gui-dist recovery).
# ============================================
echo ""
echo "--- E2E: fresh clone → setup → commit blocked by CHANGELOG ---"

TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

# 5a. Simulate fresh clone: realistic repo structure
E2E_DIR="$TMP_ROOT/e2e-repo"
mkdir -p "$E2E_DIR/.githooks"
mkdir -p "$E2E_DIR/.claude-plugin"
mkdir -p "$E2E_DIR/plugins/spec-autopilot/.claude-plugin"
mkdir -p "$E2E_DIR/plugins/spec-autopilot/hooks"
mkdir -p "$E2E_DIR/plugins/spec-autopilot/tools"
mkdir -p "$E2E_DIR/dist/spec-autopilot"
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
echo '![](https://img.shields.io/badge/version-1.0.0-blue)' > "$E2E_DIR/plugins/spec-autopilot/README.md"
echo '{}' > "$E2E_DIR/plugins/spec-autopilot/hooks/hooks.json"
echo '#!/usr/bin/env bash' > "$E2E_DIR/plugins/spec-autopilot/tools/build-dist.sh"
chmod +x "$E2E_DIR/plugins/spec-autopilot/tools/build-dist.sh"
cat > "$E2E_DIR/.claude-plugin/marketplace.json" << 'MKJSON'
{
  "plugins": [
    {"name": "spec-autopilot", "version": "1.0.0"}
  ]
}
MKJSON

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
# Part 4: marketplace.json version drift regression test
# ============================================
echo ""
echo "--- E2E: marketplace.json version drift → auto-sync ---"

DRIFT_DIR="$TMP_ROOT/drift-repo"
mkdir -p "$DRIFT_DIR/.githooks"
mkdir -p "$DRIFT_DIR/.claude-plugin"
mkdir -p "$DRIFT_DIR/plugins/spec-autopilot/.claude-plugin"
mkdir -p "$DRIFT_DIR/plugins/spec-autopilot/tests"
mkdir -p "$DRIFT_DIR/scripts"

git -C "$DRIFT_DIR" init -q

# Copy hook and setup
cp "$GITHOOKS_DIR/pre-commit" "$DRIFT_DIR/.githooks/pre-commit"
chmod +x "$DRIFT_DIR/.githooks/pre-commit"
cp "$SETUP_SCRIPT" "$DRIFT_DIR/scripts/setup-hooks.sh"

# Plugin at 2.0.0, marketplace deliberately stale at 1.0.0
echo '{"version": "2.0.0"}' > "$DRIFT_DIR/plugins/spec-autopilot/.claude-plugin/plugin.json"
echo '![](https://img.shields.io/badge/version-2.0.0-blue)' > "$DRIFT_DIR/plugins/spec-autopilot/README.md"
cat > "$DRIFT_DIR/.claude-plugin/marketplace.json" << 'MKJSON'
{
  "plugins": [
    {"name": "spec-autopilot", "version": "1.0.0"}
  ]
}
MKJSON
echo -e "# Changelog\n\n## [2.0.0] - 2026-01-01\n\n### Added\n- init" > "$DRIFT_DIR/plugins/spec-autopilot/CHANGELOG.md"

# Stub build-dist.sh + dist dir so pre-commit build step succeeds
mkdir -p "$DRIFT_DIR/plugins/spec-autopilot/tools"
mkdir -p "$DRIFT_DIR/dist/spec-autopilot"
echo '#!/usr/bin/env bash' > "$DRIFT_DIR/plugins/spec-autopilot/tools/build-dist.sh"
chmod +x "$DRIFT_DIR/plugins/spec-autopilot/tools/build-dist.sh"

git -C "$DRIFT_DIR" add -A
git -C "$DRIFT_DIR" -c user.name="Test" -c user.email="test@test.com" commit -q -m "initial"

# Setup hooks
(cd "$DRIFT_DIR" && bash scripts/setup-hooks.sh) >/dev/null 2>&1

# Stage a plugin change + CHANGELOG update
echo "// new feature" > "$DRIFT_DIR/plugins/spec-autopilot/feature.ts"
cat > "$DRIFT_DIR/plugins/spec-autopilot/CHANGELOG.md" << 'CLOG'
# Changelog

## [2.0.1] - 2026-01-02

### Added
- new feature

## [2.0.0] - 2026-01-01

### Added
- init
CLOG
git -C "$DRIFT_DIR" add "$DRIFT_DIR/plugins/spec-autopilot/feature.ts" "$DRIFT_DIR/plugins/spec-autopilot/CHANGELOG.md"

if command -v jq &>/dev/null; then
  drift_exit=0
  drift_output=$(git -C "$DRIFT_DIR" -c user.name="Test" -c user.email="test@test.com" commit -m "feat: test drift sync" 2>&1) || drift_exit=$?

  # 6a. Commit must succeed
  if [ "$drift_exit" -eq 0 ]; then
    green "  PASS: 6a. commit succeeded with marketplace drift"
    PASS=$((PASS + 1))
  else
    red "  FAIL: 6a. commit failed (exit=$drift_exit): $drift_output"
    FAIL=$((FAIL + 1))
  fi

  # 6b. marketplace.json must be exactly 2.0.1 (auto-bumped from plugin.json 2.0.0)
  DRIFT_MKT_VER=$(jq -r '.plugins[] | select(.name == "spec-autopilot") | .version' "$DRIFT_DIR/.claude-plugin/marketplace.json" 2>/dev/null)
  if [ "$DRIFT_MKT_VER" = "2.0.1" ]; then
    green "  PASS: 6b. marketplace.json synced to exact version 2.0.1"
    PASS=$((PASS + 1))
  else
    red "  FAIL: 6b. marketplace.json expected 2.0.1, got '$DRIFT_MKT_VER'"
    FAIL=$((FAIL + 1))
  fi
else
  red "  FAIL: 6a. jq is required but not found"
  FAIL=$((FAIL + 1))
  red "  FAIL: 6b. jq is required but not found"
  FAIL=$((FAIL + 1))
fi

rm -rf "$DRIFT_DIR"

# ============================================
# Part 5: pre-release version auto-bump regression test
# ============================================
echo ""
echo "--- E2E: pre-release version auto-bump ---"

PREREL_DIR="$TMP_ROOT/prerel-repo"
mkdir -p "$PREREL_DIR/.githooks"
mkdir -p "$PREREL_DIR/.claude-plugin"
mkdir -p "$PREREL_DIR/plugins/spec-autopilot/.claude-plugin"
mkdir -p "$PREREL_DIR/plugins/spec-autopilot/tools"
mkdir -p "$PREREL_DIR/dist/spec-autopilot"
mkdir -p "$PREREL_DIR/scripts"

git -C "$PREREL_DIR" init -q

cp "$GITHOOKS_DIR/pre-commit" "$PREREL_DIR/.githooks/pre-commit"
chmod +x "$PREREL_DIR/.githooks/pre-commit"
cp "$SETUP_SCRIPT" "$PREREL_DIR/scripts/setup-hooks.sh"
echo '#!/usr/bin/env bash' > "$PREREL_DIR/plugins/spec-autopilot/tools/build-dist.sh"
chmod +x "$PREREL_DIR/plugins/spec-autopilot/tools/build-dist.sh"

# Plugin at pre-release version 1.0.0-beta.1
echo '{"version": "1.0.0-beta.1"}' > "$PREREL_DIR/plugins/spec-autopilot/.claude-plugin/plugin.json"
echo '![](https://img.shields.io/badge/version-1.0.0--beta.1-blue)' > "$PREREL_DIR/plugins/spec-autopilot/README.md"
cat > "$PREREL_DIR/.claude-plugin/marketplace.json" << 'MKJSON'
{
  "plugins": [
    {"name": "spec-autopilot", "version": "1.0.0-beta.1"}
  ]
}
MKJSON
echo -e "# Changelog\n\n## [1.0.0-beta.1] - 2026-01-01\n\n### Added\n- beta" > "$PREREL_DIR/plugins/spec-autopilot/CHANGELOG.md"

git -C "$PREREL_DIR" add -A
git -C "$PREREL_DIR" -c user.name="Test" -c user.email="test@test.com" commit -q -m "initial"
(cd "$PREREL_DIR" && bash scripts/setup-hooks.sh) >/dev/null 2>&1

# Stage a change + CHANGELOG
echo "// beta feature" > "$PREREL_DIR/plugins/spec-autopilot/beta.ts"
cat > "$PREREL_DIR/plugins/spec-autopilot/CHANGELOG.md" << 'CLOG'
# Changelog

## [1.0.1] - 2026-01-02

### Added
- beta feature

## [1.0.0-beta.1] - 2026-01-01

### Added
- beta
CLOG
git -C "$PREREL_DIR" add "$PREREL_DIR/plugins/spec-autopilot/beta.ts" "$PREREL_DIR/plugins/spec-autopilot/CHANGELOG.md"

prerel_exit=0
prerel_output=$(git -C "$PREREL_DIR" -c user.name="Test" -c user.email="test@test.com" commit -m "feat: pre-release bump" 2>&1) || prerel_exit=$?

# 7a. Commit must succeed (pre-release auto-bump must not crash)
if [ "$prerel_exit" -eq 0 ]; then
  green "  PASS: 7a. commit succeeded with pre-release version"
  PASS=$((PASS + 1))
else
  red "  FAIL: 7a. commit failed (exit=$prerel_exit): $prerel_output"
  FAIL=$((FAIL + 1))
fi

# 7b. Version bumped to 1.0.1 (strip -beta.1 suffix, increment patch)
PREREL_VER=$(jq -r '.version' "$PREREL_DIR/plugins/spec-autopilot/.claude-plugin/plugin.json" 2>/dev/null)
if [ "$PREREL_VER" = "1.0.1" ]; then
  green "  PASS: 7b. plugin.json bumped to 1.0.1 (pre-release stripped)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 7b. plugin.json expected 1.0.1, got '$PREREL_VER'"
  FAIL=$((FAIL + 1))
fi

# 7c. marketplace.json also synced to 1.0.1
PREREL_MKT=$(jq -r '.plugins[] | select(.name == "spec-autopilot") | .version' "$PREREL_DIR/.claude-plugin/marketplace.json" 2>/dev/null)
if [ "$PREREL_MKT" = "1.0.1" ]; then
  green "  PASS: 7c. marketplace.json synced to 1.0.1"
  PASS=$((PASS + 1))
else
  red "  FAIL: 7c. marketplace.json expected 1.0.1, got '$PREREL_MKT'"
  FAIL=$((FAIL + 1))
fi

rm -rf "$PREREL_DIR"

# ============================================
# Summary
# ============================================
echo ""
echo "=== guard-no-verify + setup-hooks: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
