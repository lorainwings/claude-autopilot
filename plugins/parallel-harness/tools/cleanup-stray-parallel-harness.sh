#!/usr/bin/env bash
# cleanup-stray-parallel-harness.sh
# Scan a search root for ".parallel-harness/" directories that look stray
# (no .created-by anchor, no parallel-harness usage in the project's
# .claude settings or .claude-plugin manifest) and offer to remove them.
#
# Usage:
#   tools/cleanup-stray-parallel-harness.sh [SEARCH_ROOT] [--dry-run] [--yes]
#
# Defaults:
#   SEARCH_ROOT = $HOME
#   Without --yes: prompt before each removal.
#   With --dry-run: list candidates only, never delete.
#
# Exit codes:
#   0 success (whether or not anything was removed)
#   1 invalid arguments
#   2 search root missing

set -uo pipefail

DRY_RUN=0
ASSUME_YES=0
SEARCH_ROOT=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --yes | -y) ASSUME_YES=1 ;;
    -h | --help)
      sed -n '2,18p' "$0"
      exit 0
      ;;
    --*)
      printf "unknown flag: %s\n" "$1" >&2
      exit 1
      ;;
    *)
      if [ -z "$SEARCH_ROOT" ]; then
        SEARCH_ROOT="$1"
      else
        printf "unexpected argument: %s\n" "$1" >&2
        exit 1
      fi
      ;;
  esac
  shift
done

SEARCH_ROOT="${SEARCH_ROOT:-$HOME}"
if [ ! -d "$SEARCH_ROOT" ]; then
  printf "search root not found: %s\n" "$SEARCH_ROOT" >&2
  exit 2
fi

command -v python3 >/dev/null 2>&1 || {
  printf "python3 is required\n" >&2
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD_DIR="$(cd "$SCRIPT_DIR/../runtime/scripts" && pwd)"
export PH_GUARD_DIR="$GUARD_DIR"
export PH_SEARCH_ROOT="$SEARCH_ROOT"

# Collect candidate paths via python so we can reuse the guard helper.
CANDIDATES=$(
python3 - <<'PY'
import os
import sys
from pathlib import Path

sys.path.insert(0, os.environ["PH_GUARD_DIR"])
from _ph_project_guard import _settings_reference_parallel_harness  # noqa: WPS437

root = Path(os.environ["PH_SEARCH_ROOT"]).resolve()
seen: set[Path] = set()

# os.walk to skip into nested .parallel-harness without recursing into them.
for current, dirs, _files in os.walk(root, topdown=True, followlinks=False):
    # Prune common heavy/irrelevant trees for speed.
    dirs[:] = [
        d for d in dirs
        if d not in {"node_modules", ".git", ".venv", "venv", "dist", "build"}
    ]
    if ".parallel-harness" in dirs:
        ph_dir = Path(current) / ".parallel-harness"
        project_root = Path(current)
        if ph_dir in seen:
            continue
        seen.add(ph_dir)
        marker = ph_dir / ".created-by"
        intentional = marker.exists() or _settings_reference_parallel_harness(project_root)
        status = "kept" if intentional else "stray"
        print(f"{status}\t{ph_dir}")
        # Don't descend into .parallel-harness itself
        dirs.remove(".parallel-harness")
PY
)

STRAY_COUNT=0
KEPT_COUNT=0
REMOVED_COUNT=0

while IFS=$'\t' read -r status path; do
  [ -n "${status:-}" ] || continue
  case "$status" in
    kept)
      KEPT_COUNT=$((KEPT_COUNT + 1))
      printf "[keep ]  %s\n" "$path"
      ;;
    stray)
      STRAY_COUNT=$((STRAY_COUNT + 1))
      printf "[stray]  %s\n" "$path"
      if [ "$DRY_RUN" -eq 1 ]; then
        continue
      fi
      if [ "$ASSUME_YES" -ne 1 ]; then
        printf "  remove? [y/N] "
        read -r answer </dev/tty || answer=""
        case "${answer:-}" in
          y | Y | yes | YES) ;;
          *) continue ;;
        esac
      fi
      rm -rf -- "$path" && REMOVED_COUNT=$((REMOVED_COUNT + 1))
      ;;
  esac
done <<<"$CANDIDATES"

printf "\nsummary: kept=%d  stray=%d  removed=%d  (search_root=%s)\n" \
  "$KEPT_COUNT" "$STRAY_COUNT" "$REMOVED_COUNT" "$SEARCH_ROOT"
