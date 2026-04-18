#!/usr/bin/env bash
# mix_a.sh — 有对应 test
set -uo pipefail

if [ "${1:-}" == "yes" ]; then
  exit 0
fi
exit 1
