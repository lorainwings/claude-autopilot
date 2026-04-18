#!/usr/bin/env bash
# mix_b.sh — 无对应 test
set -uo pipefail

if [ "${1:-}" == "ok" ]; then
  return 0 2>/dev/null || exit 0
fi
exit 1
