#!/usr/bin/env bash
# test_fixup_commit.sh — Section 51: Fixup commit uses git add -A
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 51. Fixup commit uses git add -A, forbids explicit lockfile add (v3.3.5 regression) ---"
setup_autopilot_fixture

SKILL_FILE="$SCRIPT_DIR/../skills/autopilot/SKILL.md"

# 51a: Step 5+7 Checkpoint Agent section contains "必须使用 git add -A"
step7_git=$(grep -A20 'Step 5+7.*Checkpoint Agent' "$SKILL_FILE" || true)
assert_contains "51a: Step 7 mandates git add -A" "$step7_git" '必须使用.*git add -A'

# 51b: Step 5+7 contains explicit prohibition of adding .autopilot-active
assert_contains "51b: Step 7 forbids explicit add of lockfile" "$step7_git" '禁止显式.*git add.*autopilot-active'

# 51c: Real git simulation — .gitignore blocks explicit add of .autopilot-active
TMPDIR_51=$(mktemp -d)
(
  cd "$TMPDIR_51"
  git init -q
  git commit --allow-empty -q -m "init"
  mkdir -p openspec/changes
  echo '.autopilot-active' >> .gitignore
  git add .gitignore && git commit -q -m "add gitignore"

  # Create lock file (should be ignored by git)
  echo '{"change":"test"}' > openspec/changes/.autopilot-active

  # Attempt explicit add — should fail (exit 1)
  explicit_exit=0
  git add openspec/changes/.autopilot-active 2>/dev/null || explicit_exit=$?
  echo "EXPLICIT_ADD_EXIT=$explicit_exit"

  # Attempt git add -A — should succeed and NOT stage the ignored file
  git add -A 2>/dev/null
  add_a_exit=$?
  echo "ADD_A_EXIT=$add_a_exit"

  # Verify .autopilot-active is NOT staged
  staged=$(git diff --cached --name-only | grep '.autopilot-active' || true)
  if [ -z "$staged" ]; then
    echo "LOCKFILE_NOT_STAGED=true"
  else
    echo "LOCKFILE_NOT_STAGED=false"
  fi
) > "$TMPDIR_51/output.txt" 2>&1

RESULTS_51=$(cat "$TMPDIR_51/output.txt")
assert_contains "51c: explicit git add of ignored lockfile fails" "$RESULTS_51" "EXPLICIT_ADD_EXIT=1"
assert_contains "51d: git add -A succeeds" "$RESULTS_51" "ADD_A_EXIT=0"
assert_contains "51e: git add -A does not stage ignored lockfile" "$RESULTS_51" "LOCKFILE_NOT_STAGED=true"

rm -rf "$TMPDIR_51"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0
