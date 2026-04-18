#!/usr/bin/env bash
# untested_target.sh — 可变异但无对应 test
set -uo pipefail

run() {
  if [ "$1" == "go" ]; then
    return 0
  fi
  return 1
}

run "${1:-}"
