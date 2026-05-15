#!/usr/bin/env bash
# collect-phase-timing.sh
# Utility: Extracts timestamps from phase checkpoint files and computes
#          per-phase duration. Outputs a JSON summary to stdout.
#
# Usage: bash collect-phase-timing.sh [project_root]
# Output: JSON with { phases: [...], totals: { total_duration_seconds } }
#
# Dependencies: jq, _common.sh
# Phase 7 companion to collect-metrics.sh — focuses on wall-clock timing.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

PROJECT_ROOT="${1:-$(resolve_project_root)}"
CHANGES_DIR="$PROJECT_ROOT/openspec/changes"

# --- Locate active change directory ---
change_dir=$(find_active_change "$CHANGES_DIR" "yes") || {
  echo '{"phases":[],"totals":{"total_duration_seconds":0},"error":"no_active_change"}'
  exit 0
}

phase_results_dir="${change_dir}context/phase-results"

if [ ! -d "$phase_results_dir" ]; then
  echo '{"phases":[],"totals":{"total_duration_seconds":0},"error":"no_phase_results_dir"}'
  exit 0
fi

# --- Check jq availability ---
if ! command -v jq &>/dev/null; then
  echo '{"phases":[],"totals":{"total_duration_seconds":0},"error":"jq_not_found"}'
  exit 1
fi

# --- Collect timing from each checkpoint ---
phases_json="[]"
total_duration=0

# Scan standard phases 1-7 plus sub-phases (5.5, 6.5)
for checkpoint_file in "$phase_results_dir"/phase-*.json; do
  [ -f "$checkpoint_file" ] || continue

  # Validate JSON before processing
  if ! jq empty "$checkpoint_file" 2>/dev/null; then
    continue
  fi

  # Extract phase number from filename (e.g., phase-1-requirements.json → 1)
  basename_file=$(basename "$checkpoint_file")
  phase_num=$(echo "$basename_file" | sed -n 's/^phase-\([0-9.]*\)-.*/\1/p')
  [ -z "$phase_num" ] && continue

  # Try _metrics first (preferred source)
  has_metrics=$(jq 'has("_metrics")' "$checkpoint_file" 2>/dev/null)

  if [ "$has_metrics" = "true" ]; then
    duration=$(jq -r '._metrics.duration_seconds // 0' "$checkpoint_file")
    start_time=$(jq -r '._metrics.start_time // ""' "$checkpoint_file")
    end_time=$(jq -r '._metrics.end_time // ""' "$checkpoint_file")
  else
    # Fallback: use timestamp field, duration unknown without pair
    duration=0
    start_time=$(jq -r '.timestamp // ""' "$checkpoint_file")
    end_time=""
  fi

  status=$(jq -r '.status // "unknown"' "$checkpoint_file")
  summary=$(jq -r '.summary // ""' "$checkpoint_file")

  # Ensure duration is numeric
  if ! echo "$duration" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
    duration=0
  fi

  # Build phase entry
  phase_entry=$(jq -n \
    --arg pn "$phase_num" \
    --argjson dur "$duration" \
    --arg st "$start_time" \
    --arg et "$end_time" \
    --arg status "$status" \
    --arg summary "$summary" \
    --arg file "$basename_file" \
    '{
      phase: ($pn | tonumber),
      duration_seconds: $dur,
      start_time: $st,
      end_time: $et,
      status: $status,
      summary: $summary,
      checkpoint_file: $file
    }')

  phases_json=$(echo "$phases_json" | jq --argjson entry "$phase_entry" '. + [$entry]')

  # Accumulate total (use awk for arithmetic, output integer when possible)
  total_duration=$(echo "$total_duration $duration" | awk '{
    v = $1 + $2
    if (v == int(v)) printf "%d", v
    else printf "%.2f", v
  }')
done

# --- Sort phases by phase number ---
phases_json=$(echo "$phases_json" | jq 'sort_by(.phase)')

# --- Compute additional timing insights ---
phases_count=$(echo "$phases_json" | jq 'length')

# Find slowest phase
slowest_phase=""
if [ "$phases_count" -gt 0 ]; then
  slowest_phase=$(echo "$phases_json" | jq -r 'max_by(.duration_seconds) | "Phase \(.phase) (\(.duration_seconds)s)"')
fi

# --- Assemble final output ---
jq -n \
  --argjson phases "$phases_json" \
  --argjson total "$total_duration" \
  --argjson count "$phases_count" \
  --arg slowest "$slowest_phase" \
  '{
    phases: $phases,
    totals: {
      total_duration_seconds: $total,
      phases_measured: $count,
      slowest_phase: $slowest
    }
  }'

exit 0
