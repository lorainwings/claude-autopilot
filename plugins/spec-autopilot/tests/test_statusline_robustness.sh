#!/usr/bin/env bash
# test_statusline_robustness.sh — Statusline 安装与健康检查鲁棒性测试
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- statusline robustness ---"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# ========================================================================
# 1. health-check: 无 settings 文件 → healthy=false, issues 含 "settings_missing"
# ========================================================================
echo "# 1. health-check: no settings file"
PROJ1="$TMP_DIR/proj1"
mkdir -p "$PROJ1"
HC_OUT=$(bash "$SCRIPT_DIR/statusline-health-check.sh" --project-root "$PROJ1" 2>/dev/null)
HC_EXIT=$?
assert_exit "1. health-check exits 0 even when unhealthy" 0 "$HC_EXIT"
assert_contains "1. healthy=false" "$HC_OUT" '"healthy":false'
# shellcheck disable=SC2016
assert_contains '1. issues 含 settings_missing' "$HC_OUT" 'settings_missing'

# ========================================================================
# 2. health-check: settings 存在但 command 路径不存在 → healthy=false
# ========================================================================
echo "# 2. health-check: stale command path"
PROJ2="$TMP_DIR/proj2"
mkdir -p "$PROJ2/.claude"
cat > "$PROJ2/.claude/settings.local.json" <<JSON
{
  "statusLine": {
    "type": "command",
    "command": "bash /nonexistent/path/statusline-collector.sh"
  }
}
JSON
HC_OUT2=$(bash "$SCRIPT_DIR/statusline-health-check.sh" --project-root "$PROJ2" 2>/dev/null)
assert_contains "2. healthy=false for stale path" "$HC_OUT2" '"healthy":false'
assert_contains "2. issues 含 command_path_invalid" "$HC_OUT2" 'command_path_invalid'

# ========================================================================
# 3. health-check: 一切正常 → healthy=true
# ========================================================================
echo "# 3. health-check: all good"
PROJ3="$TMP_DIR/proj3"
mkdir -p "$PROJ3/.claude" "$PROJ3/logs/sessions"
# 写入正确配置（使用真实 collector 路径）
cat > "$PROJ3/.claude/settings.local.json" <<JSON
{
  "statusLine": {
    "type": "command",
    "command": "bash $SCRIPT_DIR/statusline-collector.sh"
  }
}
JSON
HC_OUT3=$(bash "$SCRIPT_DIR/statusline-health-check.sh" --project-root "$PROJ3" 2>/dev/null)
assert_contains "3. healthy=true" "$HC_OUT3" '"healthy":true'

# ========================================================================
# 4. auto-install: 首次安装成功 + health check 通过
# ========================================================================
echo "# 4. auto-install: fresh install"
PROJ4="$TMP_DIR/proj4"
mkdir -p "$PROJ4/.claude" "$PROJ4/openspec"
# 初始化 git 以避免 git rev-parse 失败（隔离临时仓库）
git -C "$PROJ4" init -q 2>/dev/null || true
AI_OUT=$(echo '{"cwd":"'"$PROJ4"'"}' | AUTOPILOT_PROJECT_ROOT="$PROJ4" bash "$SCRIPT_DIR/auto-install-statusline.sh" 2>/dev/null)
AI_EXIT=$?
assert_exit "4. auto-install exits 0" 0 "$AI_EXIT"
assert_contains "4. auto-install 输出安装信息" "$AI_OUT" 'GUI telemetry is now active'
assert_file_exists "4. settings.local.json created" "$PROJ4/.claude/settings.local.json"
# 验证健康检查通过
HC_OUT4=$(bash "$SCRIPT_DIR/statusline-health-check.sh" --project-root "$PROJ4" 2>/dev/null)
assert_contains "4. post-install healthy=true" "$HC_OUT4" '"healthy":true'

# ========================================================================
# 5. auto-install: stale config 自动重新安装
# ========================================================================
echo "# 5. auto-install: stale config re-install"
PROJ5="$TMP_DIR/proj5"
mkdir -p "$PROJ5/.claude" "$PROJ5/openspec"
git -C "$PROJ5" init -q 2>/dev/null || true
# 写入 stale 配置（路径不存在）
cat > "$PROJ5/.claude/settings.local.json" <<JSON
{
  "statusLine": {
    "type": "command",
    "command": "bash /nonexistent/old-version/statusline-collector.sh"
  }
}
JSON
AI_OUT5=$(echo '{"cwd":"'"$PROJ5"'"}' | AUTOPILOT_PROJECT_ROOT="$PROJ5" bash "$SCRIPT_DIR/auto-install-statusline.sh" 2>/dev/null)
assert_contains "5. stale config 触发重新安装" "$AI_OUT5" 're-installed'

# ========================================================================
# 6. auto-install: 安装结果写入 statusline-install.json
# ========================================================================
echo "# 6. auto-install: install log written"
PROJ6="$TMP_DIR/proj6"
mkdir -p "$PROJ6/.claude" "$PROJ6/openspec"
git -C "$PROJ6" init -q 2>/dev/null || true
echo '{"cwd":"'"$PROJ6"'"}' | AUTOPILOT_PROJECT_ROOT="$PROJ6" bash "$SCRIPT_DIR/auto-install-statusline.sh" >/dev/null 2>&1
INSTALL_LOG="$PROJ6/logs/statusline-install.json"
assert_file_exists "6. statusline-install.json created" "$INSTALL_LOG"
if [ -f "$INSTALL_LOG" ]; then
  LOG_CONTENT=$(cat "$INSTALL_LOG")
  assert_contains "6. log 含 installed 字段" "$LOG_CONTENT" '"installed"'
  assert_contains "6. log 含 timestamp 字段" "$LOG_CONTENT" '"timestamp"'
fi

# ========================================================================
# 7. install-config: 写入后 JSON 格式验证
# ========================================================================
echo "# 7. install-config: JSON validation"
PROJ7="$TMP_DIR/proj7"
mkdir -p "$PROJ7/.claude"
git -C "$PROJ7" init -q 2>/dev/null || true
bash "$SCRIPT_DIR/install-statusline-config.sh" --project-root "$PROJ7" --scope local >/dev/null 2>&1
SETTINGS7="$PROJ7/.claude/settings.local.json"
assert_file_exists "7. settings file created" "$SETTINGS7"
# 用 python3 验证 JSON 有效性
python3 -m json.tool "$SETTINGS7" >/dev/null 2>&1
JSON_VALID=$?
assert_exit "7. generated JSON is valid" 0 "$JSON_VALID"

# ========================================================================
# 8. install-config: CLAUDE_PLUGIN_ROOT 解析为绝对路径
# ========================================================================
echo "# 8. install-config: absolute path in fallback"
PROJ8="$TMP_DIR/proj8"
mkdir -p "$PROJ8/.claude"
git -C "$PROJ8" init -q 2>/dev/null || true
bash "$SCRIPT_DIR/install-statusline-config.sh" --project-root "$PROJ8" --scope local >/dev/null 2>&1
SETTINGS8="$PROJ8/.claude/settings.local.json"
COMMAND8=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('statusLine',{}).get('command',''))" "$SETTINGS8" 2>/dev/null)
# fallback 路径应为绝对路径（以 / 开头）
# fallback 路径应为绝对路径（以 / 开头），且不含 ../ 相对引用
assert_contains "8. fallback 含绝对路径" "$COMMAND8" ':-/'
# 验证路径不含相对引用 (用 python 检查以避免 grep 正则问题)
HAS_DOTDOT=$(python3 -c "import sys; sys.exit(0 if '../' not in sys.argv[1] else 1)" "$COMMAND8" 2>/dev/null && echo "no" || echo "yes")
if [ "$HAS_DOTDOT" = "no" ]; then
  green "  PASS: 8. 不含相对路径引用 (no '../' found)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 8. 不含相对路径引用 (found '../' in command)"
  FAIL=$((FAIL + 1))
fi

# ========================================================================
# 9. install-config: 安装前备份已有文件
# ========================================================================
echo "# 9. install-config: backup existing settings"
PROJ9="$TMP_DIR/proj9"
mkdir -p "$PROJ9/.claude"
git -C "$PROJ9" init -q 2>/dev/null || true
echo '{"existing": true}' > "$PROJ9/.claude/settings.local.json"
bash "$SCRIPT_DIR/install-statusline-config.sh" --project-root "$PROJ9" --scope local >/dev/null 2>&1
BAK_FILE="$PROJ9/.claude/settings.local.json.bak"
assert_file_exists "9. backup file created" "$BAK_FILE"
if [ -f "$BAK_FILE" ]; then
  BAK_CONTENT=$(cat "$BAK_FILE")
  assert_contains "9. backup 包含原始内容" "$BAK_CONTENT" '"existing"'
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0
