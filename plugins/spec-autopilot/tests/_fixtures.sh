#!/usr/bin/env bash
# _fixtures.sh — Shared test fixtures for spec-autopilot test suite
# Extracted from test-hooks.sh:55-75

# Resolve repo root from test directory
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIXTURE_LOCK_DIR="$REPO_ROOT/openspec/changes"
FIXTURE_LOCK_FILE="$FIXTURE_LOCK_DIR/.autopilot-active"
FIXTURE_LOCK_CREATED=false

setup_autopilot_fixture() {
  mkdir -p "$FIXTURE_LOCK_DIR"
  if [ ! -f "$FIXTURE_LOCK_FILE" ]; then
    echo '{"change":"test-fixture","pid":"99999","started":"2026-01-01T00:00:00Z"}' > "$FIXTURE_LOCK_FILE"
    FIXTURE_LOCK_CREATED=true
  fi
}

teardown_autopilot_fixture() {
  if [ "$FIXTURE_LOCK_CREATED" = "true" ] && [ -f "$FIXTURE_LOCK_FILE" ]; then
    rm -f "$FIXTURE_LOCK_FILE"
    rmdir "$FIXTURE_LOCK_DIR" 2>/dev/null || true
    rmdir "$REPO_ROOT/openspec" 2>/dev/null || true
  fi
}

setup_phase_results() {
  local base_dir="$1"
  mkdir -p "$base_dir/openspec/changes/test-feature/context/phase-results"
}
