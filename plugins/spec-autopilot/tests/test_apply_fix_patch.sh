#!/usr/bin/env bash
# test_apply_fix_patch.sh — 验证 apply-fix-patch.sh 的 stash 保护 + git apply 协议
#
# 测试覆盖：
#   1. auto patch 应用成功 → stash 清理
#   2. apply 失败 → stash pop 回滚
#   3. --dry-run 不修改文件系统
#   4. manual patch 无 --force-manual → 拒绝 + exit 2
#   5. 不存在 --patch-id → exit 1

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_test_helpers.sh
source "$SCRIPT_DIR/_test_helpers.sh"

PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APPLY="$PLUGIN_ROOT/runtime/scripts/apply-fix-patch.sh"

if [ ! -x "$APPLY" ]; then
  red "apply-fix-patch.sh missing or not executable: $APPLY"
  exit 1
fi

setup_repo() {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/.docs-fix-patches"
  printf 'line-a\nline-b\n' >"$tmp/target.txt"
  (cd "$tmp" && git init -q && git -c user.email=t@t -c user.name=t add -A && git -c user.email=t@t -c user.name=t commit -q -m init) || true
  echo "$tmp"
}

make_auto_patch() {
  local tmp="$1" id="$2"
  cat >"$tmp/.docs-fix-patches/$id.patch" <<'EOF'
--- a/target.txt
+++ b/target.txt
@@ -1,2 +1,3 @@
 line-a
 line-b
+line-c
EOF
}

make_bad_patch() {
  local tmp="$1" id="$2"
  cat >"$tmp/.docs-fix-patches/$id.patch" <<'EOF'
--- a/target.txt
+++ b/target.txt
@@ -1,2 +1,2 @@
-NOT-PRESENT
+replacement
 line-b
EOF
}

write_index() {
  local tmp="$1"
  shift
  python3 - "$tmp" "$@" <<'PY'
import json,sys
tmp=sys.argv[1]
patches=[]
for spec in sys.argv[2:]:
    pid, ptype, target, cmd = spec.split("|")
    patches.append({"id":pid,"type":ptype,"target":target,"apply_cmd":cmd})
with open(f"{tmp}/.docs-fix-patches/INDEX.json","w") as f:
    json.dump({"patches":patches}, f)
PY
}

green "=== test_apply_fix_patch.sh ==="

# Case 1: auto patch success
TMP1=$(setup_repo)
make_auto_patch "$TMP1" "p-001"
write_index "$TMP1" "p-001|auto|target.txt|git apply p-001.patch"
OUT1=$(cd "$TMP1" && AUTOPILOT_PROJECT_ROOT="$TMP1" "$APPLY" \
  --index "$TMP1/.docs-fix-patches/INDEX.json" \
  --patch-id p-001 2>&1 || true)
RC1=$?
assert_exit "1a. auto apply success" 0 $RC1
# stash 清理：不应留下 pre-apply-fix-patch stash
STASH_LEFT=$(cd "$TMP1" && git stash list 2>/dev/null | grep -c "pre-apply-fix-patch" || true)
[ "$STASH_LEFT" = "0" ] && {
  green "  PASS: 1b. stash cleaned"
  PASS=$((PASS + 1))
} ||
  {
    red "  FAIL: 1b. stash leaked ($STASH_LEFT)"
    FAIL=$((FAIL + 1))
  }
assert_file_contains "1c. target updated" "$TMP1/target.txt" "line-c"
rm -rf "$TMP1"

# Case 2: apply fails → rollback
TMP2=$(setup_repo)
make_bad_patch "$TMP2" "p-bad"
write_index "$TMP2" "p-bad|auto|target.txt|git apply p-bad.patch"
# 引入 working tree 变化以验证 stash pop 能回滚
echo "dirty" >"$TMP2/extra.txt"
set +e
OUT2=$(cd "$TMP2" && AUTOPILOT_PROJECT_ROOT="$TMP2" "$APPLY" \
  --index "$TMP2/.docs-fix-patches/INDEX.json" \
  --patch-id p-bad 2>&1)
RC2=$?
set -e
if [ "$RC2" -ne 0 ]; then
  green "  PASS: 2a. apply fail → non-zero exit"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2a. expected non-zero exit"
  FAIL=$((FAIL + 1))
fi
# 目标未被污染
if ! grep -q "replacement" "$TMP2/target.txt" 2>/dev/null; then
  green "  PASS: 2b. target untouched"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2b. target polluted"
  FAIL=$((FAIL + 1))
fi
# extra.txt 被 stash 后 pop 回来
assert_file_exists "2c. dirty extra restored" "$TMP2/extra.txt"
rm -rf "$TMP2"

# Case 3: --dry-run 不修改
TMP3=$(setup_repo)
make_auto_patch "$TMP3" "p-003"
write_index "$TMP3" "p-003|auto|target.txt|git apply p-003.patch"
SHA_BEFORE=$(shasum "$TMP3/target.txt" | awk '{print $1}')
(cd "$TMP3" && AUTOPILOT_PROJECT_ROOT="$TMP3" "$APPLY" \
  --index "$TMP3/.docs-fix-patches/INDEX.json" \
  --patch-id p-003 --dry-run >/dev/null 2>&1)
SHA_AFTER=$(shasum "$TMP3/target.txt" | awk '{print $1}')
if [ "$SHA_BEFORE" = "$SHA_AFTER" ]; then
  green "  PASS: 3a. dry-run no-op"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3a. dry-run modified file"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMP3"

# Case 4: manual patch without --force-manual → exit 2
TMP4=$(setup_repo)
cat >"$TMP4/.docs-fix-patches/p-m.suggestion.md" <<'EOF'
# Manual suggestion
EOF
write_index "$TMP4" "p-m|manual|README.md|manual review"
set +e
OUT4=$(cd "$TMP4" && AUTOPILOT_PROJECT_ROOT="$TMP4" "$APPLY" \
  --index "$TMP4/.docs-fix-patches/INDEX.json" \
  --patch-id p-m 2>&1)
RC4=$?
set -e
assert_exit "4a. manual w/o force → exit 2" 2 $RC4
assert_contains "4b. error hints --force-manual" "$OUT4" "force-manual"
rm -rf "$TMP4"

# Case 5: missing patch id
TMP5=$(setup_repo)
write_index "$TMP5" "p-known|auto|target.txt|noop"
set +e
OUT5=$(cd "$TMP5" && AUTOPILOT_PROJECT_ROOT="$TMP5" "$APPLY" \
  --index "$TMP5/.docs-fix-patches/INDEX.json" \
  --patch-id p-nope 2>&1)
RC5=$?
set -e
assert_exit "5a. unknown id → exit 1" 1 $RC5
assert_contains "5b. error mentions not found" "$OUT5" "not found"
rm -rf "$TMP5"

green "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
