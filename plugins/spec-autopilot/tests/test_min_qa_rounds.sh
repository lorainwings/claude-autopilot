#!/usr/bin/env bash
# test_min_qa_rounds.sh — Tests for min_qa_rounds L2 hard block
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- min_qa_rounds L2 Tests ---"

# 2a. RANGE_RULES includes min_qa_rounds (1, 10)
if grep -q '"phases.requirements.min_qa_rounds": (1, 10)' "$SCRIPT_DIR/_config_validator.py"; then
  green "  PASS: 2a. RANGE_RULES contains min_qa_rounds (1, 10)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2a. RANGE_RULES missing min_qa_rounds entry"
  FAIL=$((FAIL + 1))
fi

# 2b. Range validation rejects out-of-bound values
TEMP_CONFIG=$(mktemp)
cat >"$TEMP_CONFIG" <<'YAML'
version: "5.1.2"
services: {}
phases:
  requirements:
    agent: "test"
    min_qa_rounds: 99
  testing:
    agent: "test"
    gate:
      min_test_count_per_type: 5
      required_test_types: ["unit"]
  implementation:
    serial_task:
      max_retries_per_task: 3
  reporting:
    coverage_target: 80
    zero_skip_required: true
test_suites: {}
YAML
OUTPUT=$(python3 "$SCRIPT_DIR/_config_validator.py" "$TEMP_CONFIG" 2>/dev/null)
assert_contains "2b. out-of-range min_qa_rounds=99 detected" "$OUTPUT" "out of range"
rm -f "$TEMP_CONFIG"

# 2c. _post_task_validator.py contains min_qa_rounds check logic (v7.1: uses discussion_rounds)
if grep -q 'min_qa_rounds' "$SCRIPT_DIR/_post_task_validator.py" &&
  grep -q 'discussion rounds.*less than min_qa_rounds' "$SCRIPT_DIR/_post_task_validator.py"; then
  green "  PASS: 2c. _post_task_validator.py has min_qa_rounds block logic"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2c. _post_task_validator.py missing min_qa_rounds check"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
