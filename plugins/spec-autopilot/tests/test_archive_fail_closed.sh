#!/usr/bin/env bash
# test_archive_fail_closed.sh — Archive fail-closed 黑盒测试
# 验证 fixup/anchor/autosquash 失败时归档被硬阻断
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
SKILL_DIR="$(cd "$TEST_DIR/../skills" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- Archive fail-closed: fixup/anchor/autosquash hard block ---"
setup_autopilot_fixture

# --- 1. Phase 7 SKILL.md + references: fixup 完整性检查是硬阻断而非 warning ---
PHASE7_SKILL="$SKILL_DIR/autopilot-phase7-archive/SKILL.md"
PHASE7_REFS_DIR="$SKILL_DIR/autopilot-phase7-archive/references"

# v9.2: SKILL 拆分后，关键字段定义分布在 SKILL.md 和 references/ 中，合并搜索
phase7_content=$(cat "$PHASE7_SKILL")
if [ -d "$PHASE7_REFS_DIR" ]; then
  for ref_file in "$PHASE7_REFS_DIR"/*.md; do
    [ -f "$ref_file" ] && phase7_content="$phase7_content"$'\n'"$(cat "$ref_file")"
  done
fi
assert_contains "1a: fixup 不完整 → 硬阻断" "$phase7_content" '硬阻断归档'

# 1b. 不再有 "[WARNING] fixup" 的警告级别描述
assert_not_contains "1b: 无 warning 级 fixup 提示" "$phase7_content" '\[WARNING\] fixup 完整性检查'

# 1c. fixup completeness 写入 archive-readiness.json
assert_contains "1c: fixup_completeness 在 archive-readiness.json 中" "$phase7_content" 'fixup_completeness'

# --- 2. Phase 7 SKILL.md: anchor 重建失败是硬阻断 ---
# 2a. 不再有"跳过 autosquash，保留所有 fixup commits 完成归档"选项
assert_not_contains "2a: 无跳过 autosquash 保留 fixup 选项" "$phase7_content" '跳过 autosquash，保留所有 fixup commits 完成归档'

# 2b. anchor 失败描述为硬阻断
assert_contains "2b: anchor 失败 → 硬阻断" "$phase7_content" 'anchor 重建失败.*归档中止'

# --- 3. Phase 7 SKILL.md: autosquash 失败是硬阻断 ---
# 3a. autosquash 失败不再保留 fixup commits
assert_not_contains "3a: 无保留 fixup commits 降级" "$phase7_content" '保留 fixup commits，警告用户'

# 3b. autosquash 失败描述为硬阻断
assert_contains "3b: autosquash 失败 → 硬阻断" "$phase7_content" 'autosquash 失败.*归档中止'

# --- 4. Phase 7 SKILL.md: archive-readiness.json 完整字段定义 ---
# 4a. archive-readiness.json 包含所有关键检查字段
assert_contains "4a: all_checkpoints_ok 字段" "$phase7_content" 'all_checkpoints_ok'
assert_contains "4b: fixup_completeness 字段" "$phase7_content" 'fixup_completeness'
assert_contains "4c: anchor_valid 字段" "$phase7_content" 'anchor_valid'
assert_contains "4d: worktree_clean 字段" "$phase7_content" 'worktree_clean'
assert_contains "4e: review_findings_clear 字段" "$phase7_content" 'review_findings_clear'
assert_contains "4f: zero_skip_passed 字段" "$phase7_content" 'zero_skip_passed'

# --- 5. rebuild-anchor.sh: 脚本行为验证 ---
# 5a. 不传参数 → 退出码 1
exit_code=0
bash "$SCRIPT_DIR/rebuild-anchor.sh" 2>/dev/null || exit_code=$?
assert_exit "5a: rebuild-anchor 无参数 → exit 1" 1 $exit_code

# 5b. 不存在的项目目录 → 退出码 1
exit_code=0
bash "$SCRIPT_DIR/rebuild-anchor.sh" "/nonexistent/path" "/tmp/lock.json" 2>/dev/null || exit_code=$?
assert_exit "5b: rebuild-anchor 无效目录 → exit 1" 1 $exit_code

# 5c. 实际 rebuild-anchor 测试（在临时 git repo 中）
TMPDIR_ANCHOR=$(mktemp -d)
TMPDIR_ANCHOR_LOCK=$(mktemp -d)
(
  cd "$TMPDIR_ANCHOR" || exit 1
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "init" > README.md
  git add README.md
  git commit -q --no-verify -m "initial commit"
) 2>/dev/null
# lock file 放在 git repo 外面，避免脏工作区检查误判
echo '{"change":"test","anchor_sha":"invalid_sha"}' > "$TMPDIR_ANCHOR_LOCK/lock.json"

# 5c: 有效的 git repo + lock file → 成功重建
exit_code=0
NEW_SHA=$(bash "$SCRIPT_DIR/rebuild-anchor.sh" "$TMPDIR_ANCHOR" "$TMPDIR_ANCHOR_LOCK/lock.json" 2>/dev/null) || exit_code=$?
assert_exit "5c: rebuild-anchor 有效场景 → exit 0" 0 $exit_code

# 5d: lock file 中 anchor_sha 已更新
if [ $exit_code -eq 0 ] && [ -n "$NEW_SHA" ]; then
  UPDATED_SHA=$(python3 -c "import json; print(json.load(open('$TMPDIR_ANCHOR_LOCK/lock.json'))['anchor_sha'])" 2>/dev/null || echo "")
  if [ "$UPDATED_SHA" = "$NEW_SHA" ]; then
    green "  PASS: 5d: lock file anchor_sha 已更新为 $NEW_SHA"
    PASS=$((PASS + 1))
  else
    red "  FAIL: 5d: lock file anchor_sha 未正确更新 (expected '$NEW_SHA', got '$UPDATED_SHA')"
    FAIL=$((FAIL + 1))
  fi
else
  red "  FAIL: 5d: rebuild-anchor 未返回有效 SHA"
  FAIL=$((FAIL + 1))
fi

REBUILT_SUBJECT=$(git -C "$TMPDIR_ANCHOR" log -1 --format='%s' 2>/dev/null || echo "")
assert_contains "5d2: rebuild-anchor commit subject keeps start marker" "$REBUILT_SUBJECT" 'autopilot: start test'

# 5e: rebuild-anchor 在脏工作区时应该失败（v6.0 新增）
(
  cd "$TMPDIR_ANCHOR" || exit 1
  echo "dirty" > untracked_file.txt
  git add untracked_file.txt  # stage but don't commit
) 2>/dev/null
exit_code=0
bash "$SCRIPT_DIR/rebuild-anchor.sh" "$TMPDIR_ANCHOR" "$TMPDIR_ANCHOR_LOCK/lock.json" 2>/dev/null || exit_code=$?
assert_exit "5e: rebuild-anchor 脏工作区 → exit 1" 1 $exit_code

rm -rf "$TMPDIR_ANCHOR" "$TMPDIR_ANCHOR_LOCK"

# --- 6. "禁止自动归档" 声明已移除 ---
assert_not_contains "6a: 无禁止自动归档声明" "$phase7_content" '禁止自动归档.*必须经过用户明确确认'

# --- 7. archive-readiness 自动归档逻辑存在 ---
assert_contains "7a: archive-readiness overall=ready → 自动归档" "$phase7_content" 'auto-archiving'
assert_contains "7b: archive-readiness overall=blocked → 硬阻断" "$phase7_content" 'BLOCKED'

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0
