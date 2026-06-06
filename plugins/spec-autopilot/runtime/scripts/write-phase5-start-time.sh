#!/usr/bin/env bash
# write-phase5-start-time.sh — 记录 Phase 5 开始时间（供 wall-clock 超时 Hook 使用）
# 用法: bash write-phase5-start-time.sh <change_dir>
set -uo pipefail
CHANGE_DIR="${1:?Usage: $0 <change_dir>}"
mkdir -p "${CHANGE_DIR}/context/phase-results"
python3 -c "
from datetime import datetime, timezone
print(datetime.now(timezone.utc).isoformat())
" >"${CHANGE_DIR}/context/phase-results/phase5-start-time.txt"
