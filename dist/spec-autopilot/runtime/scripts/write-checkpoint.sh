#!/usr/bin/env bash
# write-checkpoint.sh
# Deterministic checkpoint writer — the ONLY sanctioned way to persist phase checkpoints.
#
# Usage: write-checkpoint.sh <project_root> <phase> '<json_envelope>'
#   project_root: absolute path to project root
#   phase: phase number (1-7)
#   json_envelope: JSON string with at minimum {status, summary}
#
# Behavior:
#   1. Resolves active change directory from lock file
#   2. Creates context/phase-results/ if missing (mkdir -p)
#   3. Appends timestamp + phase fields to envelope
#   4. Atomic write: tmp → validate → mv
#   5. Outputs [CP] log on success, [ERROR] on failure
#
# Exit: 0 on success, 1 on failure (fail-closed: caller must handle)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

PROJECT_ROOT="${1:-}"
PHASE="${2:-}"
ENVELOPE_JSON="${3:-}"

if [ -z "$PROJECT_ROOT" ] || [ -z "$PHASE" ] || [ -z "$ENVELOPE_JSON" ]; then
  echo "[ERROR] Usage: write-checkpoint.sh <project_root> <phase> '<json_envelope>'" >&2
  exit 1
fi

if ! command -v python3 &>/dev/null; then
  echo "[ERROR] python3 required for checkpoint writing" >&2
  exit 1
fi

CHANGES_DIR="$PROJECT_ROOT/openspec/changes"
if [ ! -d "$CHANGES_DIR" ]; then
  echo "[ERROR] openspec/changes/ directory not found at $PROJECT_ROOT" >&2
  exit 1
fi

CHANGE_DIR=$(find_active_change "$CHANGES_DIR") || {
  echo "[ERROR] No active change directory found. Is .autopilot-active lock file present with valid 'change' field?" >&2
  exit 1
}

PHASE_RESULTS_DIR="$CHANGE_DIR/context/phase-results"
mkdir -p "$PHASE_RESULTS_DIR" 2>/dev/null || {
  echo "[ERROR] Failed to create $PHASE_RESULTS_DIR" >&2
  exit 1
}

PHASE_SLUG=$(get_phase_label "$PHASE" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
CHECKPOINT_FILE="$PHASE_RESULTS_DIR/phase-${PHASE}-${PHASE_SLUG}.json"
TMP_FILE="${CHECKPOINT_FILE}.tmp"

python3 -c "
import json, sys, os
from datetime import datetime, timezone

phase = int(sys.argv[1])
envelope_str = sys.argv[2]
checkpoint_file = sys.argv[3]
tmp_file = sys.argv[4]

# Parse envelope
try:
    envelope = json.loads(envelope_str)
except (json.JSONDecodeError, ValueError) as e:
    print(f'[ERROR] Invalid JSON envelope: {e}', file=sys.stderr)
    sys.exit(1)

# Validate required fields
if 'status' not in envelope:
    print('[ERROR] Envelope missing required field: status', file=sys.stderr)
    sys.exit(1)
if 'summary' not in envelope:
    print('[ERROR] Envelope missing required field: summary', file=sys.stderr)
    sys.exit(1)

valid_statuses = ('ok', 'warning', 'blocked', 'failed')
if envelope['status'] not in valid_statuses:
    print(f'[ERROR] Invalid status \"{envelope[\"status\"]}\". Must be one of: {valid_statuses}', file=sys.stderr)
    sys.exit(1)

# Append metadata
envelope['phase'] = phase
envelope['timestamp'] = datetime.now(timezone.utc).isoformat()

# Atomic write: tmp → validate → mv
os.makedirs(os.path.dirname(tmp_file), exist_ok=True)
with open(tmp_file, 'w') as f:
    json.dump(envelope, f, indent=2, ensure_ascii=False)

# Validate tmp file
try:
    with open(tmp_file) as f:
        readback = json.load(f)
    assert readback.get('status') == envelope['status']
except Exception as e:
    os.unlink(tmp_file)
    print(f'[ERROR] Checkpoint validation failed: {e}', file=sys.stderr)
    sys.exit(1)

# Atomic rename
os.replace(tmp_file, checkpoint_file)

# Final verification
if not os.path.isfile(checkpoint_file):
    print(f'[ERROR] Checkpoint file not found after rename: {checkpoint_file}', file=sys.stderr)
    sys.exit(1)

print(f'[CP] {os.path.basename(checkpoint_file)} written successfully')
" "$PHASE" "$ENVELOPE_JSON" "$CHECKPOINT_FILE" "$TMP_FILE"

exit $?
