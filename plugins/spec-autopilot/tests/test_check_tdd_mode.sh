#!/usr/bin/env bash
# test_check_tdd_mode.sh — check-tdd-mode.sh 确定性 TDD 模式检测测试
# 覆盖：正常路径 + 边界条件 + 错误路径
set -euo pipefail

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_DIR="$TEST_DIR/../runtime/scripts"

# shellcheck source=_test_helpers.sh
source "$TEST_DIR/_test_helpers.sh"

echo "=== check-tdd-mode.sh ==="

# ── Setup: 创建临时项目目录 ──
TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# ────────────────────────────────────────
# 1. 正常路径：config 中 tdd_mode: true + full 模式 → TDD_SKIP
# ────────────────────────────────────────
echo "--- 1. tdd_mode=true + mode=full → TDD_SKIP ---"
PROJ1="$TMPDIR_ROOT/proj1"
mkdir -p "$PROJ1/.claude"
cat > "$PROJ1/.claude/autopilot.config.yaml" <<'YAML'
version: "1.0"
default_mode: "full"
phases:
  implementation:
    tdd_mode: true
    tdd_refactor: true
YAML

output=$(bash "$SCRIPT_DIR/check-tdd-mode.sh" "$PROJ1" 2>/dev/null)
assert_contains "1a. tdd_mode=true + full → TDD_SKIP" "$output" "TDD_SKIP"

# ────────────────────────────────────────
# 2. 正常路径：config 中 tdd_mode: false → TDD_DISPATCH
# ────────────────────────────────────────
echo "--- 2. tdd_mode=false → TDD_DISPATCH ---"
PROJ2="$TMPDIR_ROOT/proj2"
mkdir -p "$PROJ2/.claude"
cat > "$PROJ2/.claude/autopilot.config.yaml" <<'YAML'
version: "1.0"
default_mode: "full"
phases:
  implementation:
    tdd_mode: false
YAML

output=$(bash "$SCRIPT_DIR/check-tdd-mode.sh" "$PROJ2" 2>/dev/null)
assert_contains "2a. tdd_mode=false → TDD_DISPATCH" "$output" "TDD_DISPATCH"

# ────────────────────────────────────────
# 3. 正常路径：tdd_mode: true 但 mode=lite → TDD_DISPATCH（TDD 仅 full 模式生效）
# ────────────────────────────────────────
echo "--- 3. tdd_mode=true + mode=lite → TDD_DISPATCH ---"
PROJ3="$TMPDIR_ROOT/proj3"
mkdir -p "$PROJ3/.claude"
cat > "$PROJ3/.claude/autopilot.config.yaml" <<'YAML'
version: "1.0"
default_mode: "lite"
phases:
  implementation:
    tdd_mode: true
YAML

output=$(bash "$SCRIPT_DIR/check-tdd-mode.sh" "$PROJ3" 2>/dev/null)
assert_contains "3a. tdd_mode=true + lite → TDD_DISPATCH" "$output" "TDD_DISPATCH"

# ────────────────────────────────────────
# 4. 边界条件：无 config 文件 → TDD_DISPATCH（默认 tdd_mode=false）
# ────────────────────────────────────────
echo "--- 4. no config file → TDD_DISPATCH ---"
PROJ4="$TMPDIR_ROOT/proj4"
mkdir -p "$PROJ4"

output=$(bash "$SCRIPT_DIR/check-tdd-mode.sh" "$PROJ4" 2>/dev/null)
assert_contains "4a. no config → TDD_DISPATCH" "$output" "TDD_DISPATCH"

# ────────────────────────────────────────
# 5. 边界条件：config 中无 tdd_mode 字段 → TDD_DISPATCH
# ────────────────────────────────────────
echo "--- 5. config without tdd_mode field → TDD_DISPATCH ---"
PROJ5="$TMPDIR_ROOT/proj5"
mkdir -p "$PROJ5/.claude"
cat > "$PROJ5/.claude/autopilot.config.yaml" <<'YAML'
version: "1.0"
default_mode: "full"
phases:
  implementation:
    serial_task:
      max_retries_per_task: 3
YAML

output=$(bash "$SCRIPT_DIR/check-tdd-mode.sh" "$PROJ5" 2>/dev/null)
assert_contains "5a. missing tdd_mode → TDD_DISPATCH" "$output" "TDD_DISPATCH"

# ────────────────────────────────────────
# 6. 边界条件：锁文件 tdd_mode 优先于 config
# ────────────────────────────────────────
echo "--- 6. lock file tdd_mode overrides config ---"
PROJ6="$TMPDIR_ROOT/proj6"
mkdir -p "$PROJ6/.claude" "$PROJ6/openspec/changes"
# config 中 tdd_mode=false
cat > "$PROJ6/.claude/autopilot.config.yaml" <<'YAML'
version: "1.0"
default_mode: "full"
phases:
  implementation:
    tdd_mode: false
YAML
# 锁文件中 tdd_mode=true + mode=full
cat > "$PROJ6/openspec/changes/.autopilot-active" <<'JSON'
{"change":"test","pid":"12345","started":"2026-01-01T00:00:00Z","tdd_mode":true,"mode":"full"}
JSON

output=$(bash "$SCRIPT_DIR/check-tdd-mode.sh" "$PROJ6" 2>/dev/null)
assert_contains "6a. lock tdd_mode=true overrides config=false → TDD_SKIP" "$output" "TDD_SKIP"

# ────────────────────────────────────────
# 7. 边界条件：锁文件 mode=lite 覆盖 config full → TDD_DISPATCH
# ────────────────────────────────────────
echo "--- 7. lock file mode=lite overrides config full ---"
PROJ7="$TMPDIR_ROOT/proj7"
mkdir -p "$PROJ7/.claude" "$PROJ7/openspec/changes"
cat > "$PROJ7/.claude/autopilot.config.yaml" <<'YAML'
version: "1.0"
default_mode: "full"
phases:
  implementation:
    tdd_mode: true
YAML
cat > "$PROJ7/openspec/changes/.autopilot-active" <<'JSON'
{"change":"test","pid":"12345","started":"2026-01-01T00:00:00Z","mode":"lite"}
JSON

output=$(bash "$SCRIPT_DIR/check-tdd-mode.sh" "$PROJ7" 2>/dev/null)
assert_contains "7a. lock mode=lite → TDD_DISPATCH even with tdd_mode=true config" "$output" "TDD_DISPATCH"

# ────────────────────────────────────────
# 8. 错误路径：畸形 config 文件 → TDD_DISPATCH（降级到默认值）
# ────────────────────────────────────────
echo "--- 8. malformed config → TDD_DISPATCH ---"
PROJ8="$TMPDIR_ROOT/proj8"
mkdir -p "$PROJ8/.claude"
echo "this is not valid YAML {{{{" > "$PROJ8/.claude/autopilot.config.yaml"

output=$(bash "$SCRIPT_DIR/check-tdd-mode.sh" "$PROJ8" 2>/dev/null)
assert_contains "8a. malformed config → TDD_DISPATCH" "$output" "TDD_DISPATCH"

# ────────────────────────────────────────
# 9. 边界条件：tdd_mode=true + mode=minimal → TDD_DISPATCH
# ────────────────────────────────────────
echo "--- 9. tdd_mode=true + mode=minimal → TDD_DISPATCH ---"
PROJ9="$TMPDIR_ROOT/proj9"
mkdir -p "$PROJ9/.claude"
cat > "$PROJ9/.claude/autopilot.config.yaml" <<'YAML'
version: "1.0"
default_mode: "minimal"
phases:
  implementation:
    tdd_mode: true
YAML

output=$(bash "$SCRIPT_DIR/check-tdd-mode.sh" "$PROJ9" 2>/dev/null)
assert_contains "9a. tdd_mode=true + minimal → TDD_DISPATCH" "$output" "TDD_DISPATCH"

# ────────────────────────────────────────
# 10. P1 一致性验证：config=false + lock=true 时，get_tdd_mode 统一返回 true
# （验证 _common.sh get_tdd_mode 与 check-tdd-mode.sh 结果一致）
# ────────────────────────────────────────
echo "--- 10. P1 consistency: get_tdd_mode matches check-tdd-mode.sh ---"
PROJ10="$TMPDIR_ROOT/proj10"
mkdir -p "$PROJ10/.claude" "$PROJ10/openspec/changes"
cat > "$PROJ10/.claude/autopilot.config.yaml" <<'YAML'
version: "1.0"
default_mode: "full"
phases:
  implementation:
    tdd_mode: false
YAML
cat > "$PROJ10/openspec/changes/.autopilot-active" <<'JSON'
{"change":"test","pid":"12345","started":"2026-01-01T00:00:00Z","tdd_mode":true,"mode":"full"}
JSON

# check-tdd-mode.sh 应返回 TDD_SKIP
tdd_result=$(bash "$SCRIPT_DIR/check-tdd-mode.sh" "$PROJ10" 2>/dev/null)
assert_contains "10a. check-tdd-mode → TDD_SKIP" "$tdd_result" "TDD_SKIP"

# get_tdd_mode 应返回 true（与 check-tdd-mode.sh 一致）
get_result=$(bash -c "source '$SCRIPT_DIR/_common.sh' && get_tdd_mode '$PROJ10'" 2>/dev/null)
assert_contains "10b. get_tdd_mode → true (consistent)" "$get_result" "true"

# ────────────────────────────────────────
# 11. P2 子目录敏感：不传参数时从 git repo root 自动解析
# ────────────────────────────────────────
echo "--- 11. P2 auto-resolve: no arg uses resolve_project_root ---"
PROJ11="$TMPDIR_ROOT/proj11"
mkdir -p "$PROJ11/.claude" "$PROJ11/subdir/deep"
cat > "$PROJ11/.claude/autopilot.config.yaml" <<'YAML'
version: "1.0"
default_mode: "full"
phases:
  implementation:
    tdd_mode: true
YAML
# 通过 AUTOPILOT_PROJECT_ROOT 模拟 resolve_project_root 行为
output=$(AUTOPILOT_PROJECT_ROOT="$PROJ11" bash "$SCRIPT_DIR/check-tdd-mode.sh" 2>/dev/null)
assert_contains "11a. AUTOPILOT_PROJECT_ROOT resolves correctly → TDD_SKIP" "$output" "TDD_SKIP"

# 传入子目录路径应找不到 config → TDD_DISPATCH
output_sub=$(bash "$SCRIPT_DIR/check-tdd-mode.sh" "$PROJ11/subdir/deep" 2>/dev/null)
assert_contains "11b. subdir as arg → TDD_DISPATCH (no config there)" "$output_sub" "TDD_DISPATCH"

# ── Summary ──
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0
