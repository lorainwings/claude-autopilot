#!/usr/bin/env bash
# test_collect_metrics.sh — Regression tests for collect-metrics.sh checkpoint selection
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"

METRICS_SCRIPT="$SCRIPT_DIR/collect-metrics.sh"

setup_metrics_project() {
  local tmpdir
  tmpdir=$(mktemp -d)
  local project_root="$tmpdir/project"
  local change_dir="$project_root/openspec/changes/test-feature"
  local phase_results="$change_dir/context/phase-results"

  mkdir -p "$phase_results"
  cat > "$project_root/openspec/changes/.autopilot-active" <<'EOF'
{"change":"test-feature","mode":"full","session_id":"metrics-test"}
EOF

  echo "$project_root"
}

echo "--- collect-metrics latest checkpoint selection ---"

PROJECT_ROOT=$(setup_metrics_project)
PHASE_RESULTS="$PROJECT_ROOT/openspec/changes/test-feature/context/phase-results"

cat > "$PHASE_RESULTS/phase-5-zeta.json" <<'EOF'
{"status":"warning","_metrics":{"duration_seconds":7,"retry_count":1}}
EOF
cat > "$PHASE_RESULTS/phase-5-alpha.json" <<'EOF'
{"status":"ok","_metrics":{"duration_seconds":42,"retry_count":3}}
EOF
touch -t 202601010101 "$PHASE_RESULTS/phase-5-zeta.json"
touch -t 202601010102 "$PHASE_RESULTS/phase-5-alpha.json"

cat > "$PHASE_RESULTS/phase-6.5-zeta.json" <<'EOF'
{"status":"warning","_metrics":{"duration_seconds":5,"retry_count":0}}
EOF
cat > "$PHASE_RESULTS/phase-6.5-alpha.json" <<'EOF'
{"status":"ok","_metrics":{"duration_seconds":17,"retry_count":0}}
EOF
touch -t 202601010101 "$PHASE_RESULTS/phase-6.5-zeta.json"
touch -t 202601010102 "$PHASE_RESULTS/phase-6.5-alpha.json"

output=$(bash "$METRICS_SCRIPT" "$PROJECT_ROOT" 2>/dev/null)

phase5_duration=$(printf '%s' "$output" | python3 -c "import json,sys; data=json.load(sys.stdin); phase=next(p for p in data['phases'] if p['phase']==5); print(phase['duration_seconds'])")
phase5_status=$(printf '%s' "$output" | python3 -c "import json,sys; data=json.load(sys.stdin); phase=next(p for p in data['phases'] if p['phase']==5); print(phase['status'])")
phase65_duration=$(printf '%s' "$output" | python3 -c "import json,sys; data=json.load(sys.stdin); phase=next(p for p in data['phases'] if p['phase']==6.5); print(phase['duration_seconds'])")

if [ "$phase5_duration" = "42" ]; then
  green "  PASS: latest mtime wins for phase 5"
  PASS=$((PASS + 1))
else
  red "  FAIL: phase 5 duration should come from newest checkpoint (got $phase5_duration)"
  FAIL=$((FAIL + 1))
fi

if [ "$phase5_status" = "ok" ]; then
  green "  PASS: latest phase 5 status selected"
  PASS=$((PASS + 1))
else
  red "  FAIL: phase 5 status should be ok (got $phase5_status)"
  FAIL=$((FAIL + 1))
fi

if [ "$phase65_duration" = "17" ]; then
  green "  PASS: latest mtime wins for phase 6.5"
  PASS=$((PASS + 1))
else
  red "  FAIL: phase 6.5 duration should come from newest checkpoint (got $phase65_duration)"
  FAIL=$((FAIL + 1))
fi

rm -rf "$(dirname "$PROJECT_ROOT")"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
