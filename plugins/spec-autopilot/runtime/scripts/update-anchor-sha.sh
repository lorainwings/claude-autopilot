#!/usr/bin/env bash
# update-anchor-sha.sh — Atomically update anchor_sha in the lockfile
#
# Usage: update-anchor-sha.sh <lock_path> <anchor_sha>
#   lock_path  : path to the .autopilot-active lockfile
#   anchor_sha : the git SHA to write
#
# Stdout: JSON {"status":"ok|error","anchor_sha":"...","message":"..."}
#
# WP-6: Extracted from autopilot-phase0-init/SKILL.md Step 10 inline Python.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

LOCK_PATH="${1:-}"
ANCHOR_SHA="${2:-}"

if [ -z "$LOCK_PATH" ] || [ -z "$ANCHOR_SHA" ]; then
  echo '{"status":"error","message":"Usage: update-anchor-sha.sh <lock_path> <anchor_sha>"}'
  exit 1
fi

python3 -c '
import json, os, sys, tempfile

lock_path = sys.argv[1]
anchor_sha = sys.argv[2]

try:
    with open(lock_path) as f:
        data = json.load(f)
except Exception as e:
    print(json.dumps({"status": "error", "message": str(e)}))
    sys.exit(0)

data["anchor_sha"] = anchor_sha

tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(lock_path), suffix=".tmp")
try:
    with os.fdopen(tmp_fd, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    os.replace(tmp_path, lock_path)
    print(json.dumps({"status": "ok", "anchor_sha": anchor_sha}))
except Exception as e:
    try: os.unlink(tmp_path)
    except: pass
    print(json.dumps({"status": "error", "message": str(e)}))
' "$LOCK_PATH" "$ANCHOR_SHA"
