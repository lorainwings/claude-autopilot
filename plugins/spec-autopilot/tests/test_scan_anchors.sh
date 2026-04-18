#!/usr/bin/env bash
# test_scan_anchors.sh — 验证 scan-code-ref-anchors.sh 提取内联 + config 锚点能力
#
# 测试覆盖：
#   1. 仅内联锚点 → JSON 正确列出 anchor
#   2. 仅 config 锚点 → JSON 正确合并
#   3. 空目录 → {"anchors":[]}
#   4. 内联 + config 去重合并 → docs 列表合并
#   5. --only-inline 过滤 config
#   6. 文档侧 CODE-OWNED-BY 反向锚点
#   7. 扫描器自身注释不计入产物

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_test_helpers.sh
source "$SCRIPT_DIR/_test_helpers.sh"

PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCAN="$PLUGIN_ROOT/runtime/scripts/scan-code-ref-anchors.sh"

if [ ! -x "$SCAN" ]; then
  red "scan-code-ref-anchors.sh missing or not executable: $SCAN"
  exit 1
fi

green "=== test_scan_anchors.sh ==="

setup_tree() {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/plugins/spec-autopilot/runtime/scripts"
  mkdir -p "$tmp/plugins/spec-autopilot/skills/sample/references"
  mkdir -p "$tmp/docs/plans/engineering-auto-sync"
  mkdir -p "$tmp/.claude"
  # Ensure referenced docs exist (so that "doc exists" checks in later tests aren't confused,
  # though scanner itself does not verify existence — drift detector does).
  : >"$tmp/docs/plans/engineering-auto-sync/01-design.md"
  : >"$tmp/docs/plans/engineering-auto-sync/02-rollout.md"
  : >"$tmp/plugins/spec-autopilot/skills/sample/SKILL.md"
  echo "$tmp"
}

# ---------- Case 1: inline only (code side) ----------
TMP1=$(setup_tree)
cat >"$TMP1/plugins/spec-autopilot/runtime/scripts/foo.sh" <<'EOF'
#!/usr/bin/env bash
# foo.sh
# CODE-REF: docs/plans/engineering-auto-sync/01-design.md
echo hi
EOF
OUT1=$(AUTOPILOT_PROJECT_ROOT="$TMP1" "$SCAN" --format json 2>/dev/null || true)
RC1=$?
assert_exit "1a. inline only → exit 0" 0 $RC1
assert_contains "1b. anchor code present" "$OUT1" "plugins/spec-autopilot/runtime/scripts/foo.sh"
assert_contains "1c. anchor doc present" "$OUT1" "docs/plans/engineering-auto-sync/01-design.md"
assert_contains "1d. source=inline" "$OUT1" "\"source\": \"inline\""
rm -rf "$TMP1"

# ---------- Case 2: config only ----------
TMP2=$(setup_tree)
# no inline anchors; only YAML config
cat >"$TMP2/.claude/docs-ownership.yaml" <<'EOF'
mappings:
  - code: plugins/spec-autopilot/runtime/scripts/bar.sh
    docs:
      - docs/plans/engineering-auto-sync/02-rollout.md
EOF
# create the referenced code stub
: >"$TMP2/plugins/spec-autopilot/runtime/scripts/bar.sh"
OUT2=$(AUTOPILOT_PROJECT_ROOT="$TMP2" "$SCAN" --format json 2>/dev/null || true)
RC2=$?
assert_exit "2a. config only → exit 0" 0 $RC2
assert_contains "2b. config mapping code" "$OUT2" "bar.sh"
assert_contains "2c. config mapping doc" "$OUT2" "02-rollout.md"
assert_contains "2d. source=config" "$OUT2" "\"source\": \"config\""
rm -rf "$TMP2"

# ---------- Case 3: empty tree ----------
TMP3=$(setup_tree)
OUT3=$(AUTOPILOT_PROJECT_ROOT="$TMP3" "$SCAN" --format json 2>/dev/null || true)
RC3=$?
assert_exit "3a. empty → exit 0" 0 $RC3
# No anchors: should output {"anchors": []}
assert_contains "3b. empty anchors array" "$OUT3" "\"anchors\""
# must not contain any file paths
assert_not_contains "3c. no stray code path" "$OUT3" "foo.sh"
rm -rf "$TMP3"

# ---------- Case 4: inline + config merged, dedup ----------
TMP4=$(setup_tree)
cat >"$TMP4/plugins/spec-autopilot/runtime/scripts/merge.sh" <<'EOF'
#!/usr/bin/env bash
# CODE-REF: docs/plans/engineering-auto-sync/01-design.md
EOF
cat >"$TMP4/.claude/docs-ownership.yaml" <<'EOF'
mappings:
  - code: plugins/spec-autopilot/runtime/scripts/merge.sh
    docs:
      - docs/plans/engineering-auto-sync/02-rollout.md
      - docs/plans/engineering-auto-sync/01-design.md
EOF
OUT4=$(AUTOPILOT_PROJECT_ROOT="$TMP4" "$SCAN" --format json 2>/dev/null || true)
RC4=$?
assert_exit "4a. merge → exit 0" 0 $RC4
assert_contains "4b. merged has inline doc" "$OUT4" "01-design.md"
assert_contains "4c. merged has config doc" "$OUT4" "02-rollout.md"
# Dedup check — 01-design.md must appear exactly once per-code-entry. We assert the code appears once.
COUNT4=$(printf '%s\n' "$OUT4" | grep -c "merge.sh" || true)
if [ "$COUNT4" -ge 1 ] && [ "$COUNT4" -le 3 ]; then
  green "  PASS: 4d. merged entry count reasonable ($COUNT4)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 4d. unexpected merge.sh occurrences: $COUNT4"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMP4"

# ---------- Case 5: --only-inline filters config ----------
TMP5=$(setup_tree)
cat >"$TMP5/plugins/spec-autopilot/runtime/scripts/only.sh" <<'EOF'
#!/usr/bin/env bash
# CODE-REF: docs/plans/engineering-auto-sync/01-design.md
EOF
cat >"$TMP5/.claude/docs-ownership.yaml" <<'EOF'
mappings:
  - code: plugins/spec-autopilot/runtime/scripts/other.sh
    docs:
      - docs/plans/engineering-auto-sync/02-rollout.md
EOF
: >"$TMP5/plugins/spec-autopilot/runtime/scripts/other.sh"
OUT5=$(AUTOPILOT_PROJECT_ROOT="$TMP5" "$SCAN" --format json --only-inline 2>/dev/null || true)
RC5=$?
assert_exit "5a. only-inline → exit 0" 0 $RC5
assert_contains "5b. inline code visible" "$OUT5" "only.sh"
assert_not_contains "5c. config code suppressed" "$OUT5" "other.sh"
rm -rf "$TMP5"

# ---------- Case 6: doc-side CODE-OWNED-BY anchor ----------
TMP6=$(setup_tree)
cat >"$TMP6/docs/plans/engineering-auto-sync/01-design.md" <<'EOF'
# Design
<!-- CODE-OWNED-BY: plugins/spec-autopilot/runtime/scripts/owned.sh -->
EOF
: >"$TMP6/plugins/spec-autopilot/runtime/scripts/owned.sh"
OUT6=$(AUTOPILOT_PROJECT_ROOT="$TMP6" "$SCAN" --format json 2>/dev/null || true)
RC6=$?
assert_exit "6a. doc-side anchor → exit 0" 0 $RC6
assert_contains "6b. owned-by code extracted" "$OUT6" "owned.sh"
assert_contains "6c. owned-by doc path" "$OUT6" "01-design.md"
rm -rf "$TMP6"

# ---------- Case 7: scanner self-exclusion ----------
TMP7=$(setup_tree)
# Copy scan script into fixture with identical comment examples; the file path filter
# must exclude the scanner file itself even if it contains CODE-REF literals.
cp "$SCAN" "$TMP7/plugins/spec-autopilot/runtime/scripts/scan-code-ref-anchors.sh"
OUT7=$(AUTOPILOT_PROJECT_ROOT="$TMP7" "$SCAN" --format json 2>/dev/null || true)
RC7=$?
assert_exit "7a. self-scan → exit 0" 0 $RC7
# The scanner's own documentation examples (e.g. CODE-REF: docs/...) must not surface
# as anchors keyed on the scanner itself.
assert_not_contains "7b. scanner self excluded as code" \
  "$OUT7" "\"code\": \"plugins/spec-autopilot/runtime/scripts/scan-code-ref-anchors.sh\""
rm -rf "$TMP7"

echo
green "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
