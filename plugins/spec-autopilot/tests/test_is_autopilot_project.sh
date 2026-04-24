#!/usr/bin/env bash
# test_is_autopilot_project.sh — coverage for _common.sh::is_autopilot_project()
# Guards against regressions in the "OR" semantics (openspec/ OR .claude/autopilot.config.yaml).
# Without this, a future change flipping to "AND" or dropping a branch would only
# surface indirectly via unrelated end-to-end tests.
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
# shellcheck source=../runtime/scripts/_common.sh
source "$SCRIPT_DIR/_common.sh"

echo "--- is_autopilot_project ---"

# Case 1: neither marker → not an autopilot project
TMP_NEITHER=$(mktemp -d)
trap 'rm -rf "$TMP_NEITHER" "${TMP_OPENSPEC:-}" "${TMP_CONFIG:-}" "${TMP_BOTH:-}" "${TMP_EMPTY_CONFIG:-}"' EXIT
if is_autopilot_project "$TMP_NEITHER"; then
  red "  FAIL: 1. neither marker → expected non-zero, got 0"
  FAIL=$((FAIL + 1))
else
  green "  PASS: 1. neither marker → correctly rejected"
  PASS=$((PASS + 1))
fi

# Case 2: only openspec/ directory → recognized
TMP_OPENSPEC=$(mktemp -d)
mkdir -p "$TMP_OPENSPEC/openspec"
if is_autopilot_project "$TMP_OPENSPEC"; then
  green "  PASS: 2. openspec/ only → recognized"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2. openspec/ only → expected 0, got non-zero"
  FAIL=$((FAIL + 1))
fi

# Case 3: only .claude/autopilot.config.yaml → recognized
TMP_CONFIG=$(mktemp -d)
mkdir -p "$TMP_CONFIG/.claude"
printf "phases:\n  requirements:\n    agent: x\n" >"$TMP_CONFIG/.claude/autopilot.config.yaml"
if is_autopilot_project "$TMP_CONFIG"; then
  green "  PASS: 3. config yaml only → recognized"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3. config yaml only → expected 0, got non-zero"
  FAIL=$((FAIL + 1))
fi

# Case 4: both present → recognized (no priority needed, OR semantics)
TMP_BOTH=$(mktemp -d)
mkdir -p "$TMP_BOTH/openspec" "$TMP_BOTH/.claude"
printf "phases: {}\n" >"$TMP_BOTH/.claude/autopilot.config.yaml"
if is_autopilot_project "$TMP_BOTH"; then
  green "  PASS: 4. both markers → recognized"
  PASS=$((PASS + 1))
else
  red "  FAIL: 4. both markers → expected 0, got non-zero"
  FAIL=$((FAIL + 1))
fi

# Case 5: empty config file still counts (file existence is the condition)
TMP_EMPTY_CONFIG=$(mktemp -d)
mkdir -p "$TMP_EMPTY_CONFIG/.claude"
: >"$TMP_EMPTY_CONFIG/.claude/autopilot.config.yaml"
if is_autopilot_project "$TMP_EMPTY_CONFIG"; then
  green "  PASS: 5. empty config file → still recognized (by existence)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 5. empty config file → expected 0, got non-zero"
  FAIL=$((FAIL + 1))
fi

# Case 6: .claude/ directory without config yaml → NOT recognized
TMP_PARTIAL=$(mktemp -d)
mkdir -p "$TMP_PARTIAL/.claude"
if is_autopilot_project "$TMP_PARTIAL"; then
  red "  FAIL: 6. .claude/ without config yaml → unexpectedly recognized"
  FAIL=$((FAIL + 1))
else
  green "  PASS: 6. .claude/ without config yaml → correctly rejected"
  PASS=$((PASS + 1))
fi
rm -rf "$TMP_PARTIAL"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
