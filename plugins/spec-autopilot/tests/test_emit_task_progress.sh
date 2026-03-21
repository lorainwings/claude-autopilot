#!/usr/bin/env bash
# test_emit_task_progress.sh — emit-task-progress.sh phase 参数测试
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/_test_helpers.sh"

SCRIPT="$PLUGIN_DIR/runtime/scripts/emit-task-progress.sh"

echo "--- emit-task-progress phase 参数 ---"

# 准备临时项目目录（避免污染真实 logs/）
TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT
mkdir -p "$TMPDIR_ROOT/.git"
git -C "$TMPDIR_ROOT" init -q 2>/dev/null || true

# 1. 不传 phase 参数 → 默认 phase=5（向后兼容）
output=$(PROJECT_ROOT_QUICK="$TMPDIR_ROOT" bash "$SCRIPT" "task-1" running 1 3 full "" "0" 2>/dev/null) || true
phase_val=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['phase'])" 2>/dev/null || echo "")
if [ "$phase_val" = "5" ]; then
  green "  PASS: 1. 不传 phase → 默认 phase=5"
  PASS=$((PASS + 1))
else
  red "  FAIL: 1. 不传 phase → 期望 phase=5, 实际 '$phase_val'"
  FAIL=$((FAIL + 1))
fi

# 2. 传 phase=3 → phase=3
output=$(PROJECT_ROOT_QUICK="$TMPDIR_ROOT" bash "$SCRIPT" "task-2" passed 2 3 full "" "0" "3" 2>/dev/null) || true
phase_val=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['phase'])" 2>/dev/null || echo "")
if [ "$phase_val" = "3" ]; then
  green "  PASS: 2. 传 phase=3 → phase=3"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2. 传 phase=3 → 期望 phase=3, 实际 '$phase_val'"
  FAIL=$((FAIL + 1))
fi

# 3. 缺少必填参数 → exit 1
bash "$SCRIPT" "task-only" 2>/dev/null
code=$?
assert_exit "3. 缺少必填参数 → exit 1" 1 "$code"

echo "Results: $PASS passed, $FAIL failed"
