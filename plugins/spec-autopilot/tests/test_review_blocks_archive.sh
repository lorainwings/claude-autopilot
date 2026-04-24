#!/usr/bin/env bash
# test_review_blocks_archive.sh — WS-E: Review findings fail-closed gate test
# Verifies:
#   1. Phase 7 post-task-validator blocks when blocking review findings exist
#   2. Phase 7 passes when no blocking findings exist
#   3. Phase 7 passes when blocking findings are resolved
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"

echo "--- WS-E: Review findings block archive (fail-closed) ---"

# Self-contained temp directory
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Setup autopilot fixture in TMPDIR
mkdir -p "$TMPDIR/.claude"
CHANGE_DIR="$TMPDIR/openspec/changes/test-feature/context/phase-results"
mkdir -p "$CHANGE_DIR"
echo '{"change":"test-feature","pid":"99999","started":"2026-01-01T00:00:00Z"}' \
  >"$TMPDIR/openspec/changes/.autopilot-active"

# Phase 1-6 checkpoints (all ok)
echo '{"status":"ok","summary":"Req done","decisions":[{"point":"x","choice":"y"}],"requirement_type":"feature"}' \
  >"$CHANGE_DIR/phase-1-requirements.json"
echo '{"status":"ok","summary":"OpenSpec done","artifacts":["spec.md"],"alternatives":["alt1"]}' \
  >"$CHANGE_DIR/phase-2-openspec.json"
echo '{"status":"ok","summary":"FF done","plan":"impl plan","test_strategy":"unit+e2e"}' \
  >"$CHANGE_DIR/phase-3-ff.json"
echo '{"status":"ok","summary":"Tests designed","test_counts":{"unit":5},"sad_path_counts":{"unit":2},"dry_run_results":{"unit":0},"test_pyramid":{"unit_pct":100,"e2e_pct":0},"change_coverage":{"change_points":["A"],"tested_points":["A"],"coverage_pct":100,"untested_points":[]},"artifacts":["t.py"]}' \
  >"$CHANGE_DIR/phase-4-test.json"
echo '{"status":"ok","summary":"Impl done","test_results_path":"report.html","tasks_completed":[1],"zero_skip_check":{"passed":true},"artifacts":["src/main.py"]}' \
  >"$CHANGE_DIR/phase-5-implementation.json"
echo '{"status":"ok","summary":"Tests pass","pass_rate":100,"report_path":"report.html","report_format":"html","artifacts":["report.html"]}' \
  >"$CHANGE_DIR/phase-6-test-report.json"

# === Test 1: Blocking review findings → Phase 7 blocked ===
cat >"$CHANGE_DIR/phase-6.5-code-review.json" <<'REVIEW'
{
  "status": "blocked",
  "summary": "Critical security issue found",
  "findings": [
    {
      "severity": "critical",
      "file": "src/auth.py",
      "line": 42,
      "message": "Hardcoded API key detected",
      "evidence": "API_KEY = 'sk-1234...'",
      "blocking": true,
      "owner": "code-reviewer"
    },
    {
      "severity": "minor",
      "file": "src/utils.py",
      "line": 10,
      "message": "Unused import",
      "evidence": "import os  # not used",
      "blocking": false,
      "owner": "code-reviewer"
    }
  ],
  "metrics": {"files_reviewed": 5, "findings_count": {"critical": 1, "minor": 1}}
}
REVIEW

# Build Phase 7 Task input
PHASE7_INPUT='{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:7 -->\nArchive and summarize"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Archive complete\",\"artifacts\":[\"archive.md\"]}","cwd":"'"$TMPDIR"'"}'

exit_code=0
output=$(echo "$PHASE7_INPUT" | bash "$SCRIPT_DIR/post-task-validator.sh" 2>/dev/null) || exit_code=$?
assert_exit "1a. Phase 7 with blocking findings → exit 0 (hook itself)" 0 $exit_code
assert_contains "1b. Phase 7 blocked by review findings" "$output" "block"
assert_contains "1c. blocking reason mentions review" "$output" "critical"

# === Test 2: No blocking findings → Phase 7 passes ===
cat >"$CHANGE_DIR/phase-6.5-code-review.json" <<'REVIEW'
{
  "status": "ok",
  "summary": "All clear",
  "findings": [
    {
      "severity": "minor",
      "file": "src/utils.py",
      "line": 10,
      "message": "Unused import",
      "evidence": "import os",
      "blocking": false,
      "owner": "code-reviewer"
    }
  ],
  "metrics": {"files_reviewed": 5, "findings_count": {"minor": 1}}
}
REVIEW

exit_code=0
output=$(echo "$PHASE7_INPUT" | bash "$SCRIPT_DIR/post-task-validator.sh" 2>/dev/null) || exit_code=$?
assert_exit "2a. Phase 7 without blocking findings → exit 0" 0 $exit_code
assert_not_contains "2b. Phase 7 not blocked when no blocking findings" "$output" "Review findings block"

# === Test 3: No review checkpoint at all → Phase 7 passes (review is optional) ===
rm -f "$CHANGE_DIR/phase-6.5-code-review.json"
exit_code=0
output=$(echo "$PHASE7_INPUT" | bash "$SCRIPT_DIR/post-task-validator.sh" 2>/dev/null) || exit_code=$?
assert_exit "3a. Phase 7 without review checkpoint → exit 0" 0 $exit_code
assert_not_contains "3b. Phase 7 not blocked when no review" "$output" "Review findings block"

# === Test 4: Review findings with resolved blocking → Phase 7 passes ===
cat >"$CHANGE_DIR/phase-6.5-code-review.json" <<'REVIEW'
{
  "status": "ok",
  "summary": "Issues resolved",
  "findings": [
    {
      "severity": "critical",
      "file": "src/auth.py",
      "line": 42,
      "message": "Hardcoded API key detected",
      "evidence": "API_KEY = 'sk-1234...'",
      "blocking": true,
      "resolved": true,
      "owner": "code-reviewer"
    }
  ],
  "metrics": {"files_reviewed": 5, "findings_count": {"critical": 1}}
}
REVIEW

exit_code=0
output=$(echo "$PHASE7_INPUT" | bash "$SCRIPT_DIR/post-task-validator.sh" 2>/dev/null) || exit_code=$?
assert_exit "4a. Phase 7 with resolved blocking findings → exit 0" 0 $exit_code
assert_not_contains "4b. Phase 7 not blocked when findings resolved" "$output" "Review findings block"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
