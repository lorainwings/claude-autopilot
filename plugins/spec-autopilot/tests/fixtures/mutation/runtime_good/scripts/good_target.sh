#!/usr/bin/env bash
# good_target.sh — 包含多种可变异的 pattern
set -uo pipefail

check_value() {
  local v="$1"
  if [ "$v" == "ok" ]; then
    return 0
  fi
  return 1
}

check_value "${1:-}"
