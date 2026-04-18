#!/usr/bin/env bash
# test_detect_anchor_drift.sh — 验证 detect-anchor-drift.sh 的 R6/R7/R8 规则
#
# 测试覆盖：
#   1. R6: code 锚点指向不存在 doc → warn
#   2. R7: doc CODE-OWNED-BY 指向不存在 code → warn
#   3. R8: code staged 但配对 doc 未 staged → candidate
#   4. R8 反例: code + doc 同入 staging → 无 R8 candidate
#   5. 空 staging → 0 candidate
#   6. deleted-files 含被引用 code → 报警
#   7. 无锚点仓库 → 0 candidate, exit 0

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_test_helpers.sh
source "$SCRIPT_DIR/_test_helpers.sh"

PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DRIFT="$PLUGIN_ROOT/runtime/scripts/detect-anchor-drift.sh"

if [ ! -x "$DRIFT" ]; then
  red "detect-anchor-drift.sh missing or not executable: $DRIFT"
  exit 1
fi

green "=== test_detect_anchor_drift.sh ==="

setup_tree() {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/plugins/spec-autopilot/runtime/scripts"
  mkdir -p "$tmp/docs/plans/engineering-auto-sync"
  mkdir -p "$tmp/.claude"
  echo "$tmp"
}

# ---------- Case 1: R6 doc missing ----------
TMP1=$(setup_tree)
cat >"$TMP1/plugins/spec-autopilot/runtime/scripts/r6.sh" <<'EOF'
#!/usr/bin/env bash
# CODE-REF: docs/plans/engineering-auto-sync/does-not-exist.md
EOF
OUT1=$(AUTOPILOT_PROJECT_ROOT="$TMP1" "$DRIFT" 2>&1 || true)
RC1=$?
assert_exit "1a. R6 → exit 0" 0 $RC1
assert_contains "1b. R6 fired" "$OUT1" "R6"
assert_file_exists "1c. candidates file" "$TMP1/.cache/spec-autopilot/anchor-drift-candidates.json"
rm -rf "$TMP1"

# ---------- Case 2: R7 doc points to missing code ----------
TMP2=$(setup_tree)
cat >"$TMP2/docs/plans/engineering-auto-sync/01-design.md" <<'EOF'
# Design
<!-- CODE-OWNED-BY: plugins/spec-autopilot/runtime/scripts/ghost.sh -->
EOF
OUT2=$(AUTOPILOT_PROJECT_ROOT="$TMP2" "$DRIFT" 2>&1 || true)
RC2=$?
assert_exit "2a. R7 → exit 0" 0 $RC2
assert_contains "2b. R7 fired" "$OUT2" "R7"
rm -rf "$TMP2"

# ---------- Case 3: R8 staged code without paired doc ----------
TMP3=$(setup_tree)
cat >"$TMP3/plugins/spec-autopilot/runtime/scripts/r8.sh" <<'EOF'
#!/usr/bin/env bash
# CODE-REF: docs/plans/engineering-auto-sync/01-design.md
EOF
: >"$TMP3/docs/plans/engineering-auto-sync/01-design.md"
OUT3=$(AUTOPILOT_PROJECT_ROOT="$TMP3" "$DRIFT" \
  --changed-files "plugins/spec-autopilot/runtime/scripts/r8.sh" 2>&1 || true)
RC3=$?
assert_exit "3a. R8 → exit 0" 0 $RC3
assert_contains "3b. R8 fired" "$OUT3" "R8"
rm -rf "$TMP3"

# ---------- Case 4: R8 counter — both staged ----------
TMP4=$(setup_tree)
cat >"$TMP4/plugins/spec-autopilot/runtime/scripts/r8pair.sh" <<'EOF'
#!/usr/bin/env bash
# CODE-REF: docs/plans/engineering-auto-sync/01-design.md
EOF
: >"$TMP4/docs/plans/engineering-auto-sync/01-design.md"
OUT4=$(AUTOPILOT_PROJECT_ROOT="$TMP4" "$DRIFT" \
  --changed-files "plugins/spec-autopilot/runtime/scripts/r8pair.sh docs/plans/engineering-auto-sync/01-design.md" 2>&1 || true)
RC4=$?
assert_exit "4a. both staged → exit 0" 0 $RC4
assert_not_contains "4b. no R8" "$OUT4" "\"rule_id\": \"R8\""
rm -rf "$TMP4"

# ---------- Case 5: empty staging ----------
TMP5=$(setup_tree)
OUT5=$(AUTOPILOT_PROJECT_ROOT="$TMP5" "$DRIFT" --changed-files "" 2>&1 || true)
RC5=$?
assert_exit "5a. empty staging → exit 0" 0 $RC5
assert_contains "5b. zero count" "$OUT5" "ANCHOR_DRIFT_CANDIDATES=0"
rm -rf "$TMP5"

# ---------- Case 6: deleted-files contains referenced code ----------
TMP6=$(setup_tree)
cat >"$TMP6/docs/plans/engineering-auto-sync/01-design.md" <<'EOF'
# Design
<!-- CODE-OWNED-BY: plugins/spec-autopilot/runtime/scripts/gone.sh -->
EOF
# gone.sh does NOT exist in tree — simulating deletion
OUT6=$(AUTOPILOT_PROJECT_ROOT="$TMP6" "$DRIFT" \
  --deleted-files "plugins/spec-autopilot/runtime/scripts/gone.sh" 2>&1 || true)
RC6=$?
assert_exit "6a. deleted-files → exit 0" 0 $RC6
# Deletion of a referenced code must trigger a warning (R7 style: doc orphaned)
assert_contains "6b. anchor drift warning on deletion" "$OUT6" "gone.sh"
rm -rf "$TMP6"

# ---------- Case 7: no anchors anywhere ----------
TMP7=$(setup_tree)
echo "#!/usr/bin/env bash" >"$TMP7/plugins/spec-autopilot/runtime/scripts/plain.sh"
OUT7=$(AUTOPILOT_PROJECT_ROOT="$TMP7" "$DRIFT" 2>&1 || true)
RC7=$?
assert_exit "7a. no anchors → exit 0" 0 $RC7
assert_contains "7b. zero candidates" "$OUT7" "ANCHOR_DRIFT_CANDIDATES=0"
rm -rf "$TMP7"

echo
green "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
