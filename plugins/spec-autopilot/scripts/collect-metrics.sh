#!/usr/bin/env bash
# collect-metrics.sh
# Utility: Collects execution metrics from phase checkpoint files.
# Called from Phase 7 to generate a metrics summary.
#
# Usage: bash collect-metrics.sh [project_root]
# Output: JSON summary on stdout

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

PROJECT_ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
CHANGES_DIR="$PROJECT_ROOT/openspec/changes"

# Find active change
change_dir=$(find_active_change "$CHANGES_DIR" "yes") || {
  echo '{"error":"no_active_change","phases":[],"totals":{}}'
  exit 0
}

phase_results_dir="${change_dir}context/phase-results"

if [ ! -d "$phase_results_dir" ]; then
  echo '{"error":"no_phase_results","phases":[],"totals":{}}'
  exit 0
fi

# Collect metrics using python3
if ! command -v python3 &>/dev/null; then
  echo '{"error":"python3_not_found","phases":[],"totals":{}}'
  exit 0
fi

python3 -c "
import json, sys, os, glob

phase_dir = sys.argv[1]
phases = []
total_duration = 0
total_retries = 0

for phase_num in range(1, 8):
    pattern = os.path.join(phase_dir, f'phase-{phase_num}-*.json')
    files = sorted(glob.glob(pattern))
    if not files:
        continue

    try:
        with open(files[-1]) as f:
            data = json.load(f)
    except Exception:
        continue

    metrics = data.get('_metrics', {})
    duration = metrics.get('duration_seconds', 0)
    retries = metrics.get('retry_count', 0)

    phases.append({
        'phase': phase_num,
        'status': data.get('status', 'unknown'),
        'duration_seconds': duration,
        'retry_count': retries,
        'start_time': metrics.get('start_time', ''),
        'end_time': metrics.get('end_time', ''),
    })

    if isinstance(duration, (int, float)):
        total_duration += duration
    if isinstance(retries, int):
        total_retries += retries

result = {
    'phases': phases,
    'totals': {
        'total_duration_seconds': total_duration,
        'total_retries': total_retries,
        'phases_completed': len(phases),
    }
}
print(json.dumps(result, indent=2))
" "$phase_results_dir"

exit 0
