#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../scripts/mix_a.sh"

if ! bash "$TARGET" yes >/dev/null 2>&1; then
  echo "FAIL"
  exit 1
fi
if bash "$TARGET" no >/dev/null 2>&1; then
  echo "FAIL"
  exit 1
fi
echo "PASS"
