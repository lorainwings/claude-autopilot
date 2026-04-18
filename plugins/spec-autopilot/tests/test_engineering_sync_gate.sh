#!/usr/bin/env bash
# test_engineering_sync_gate.sh — 验证 engineering-sync-gate.sh 聚合入口
#
# 测试覆盖：
#   1. config 缺失 → 默认 disabled，warn-only，exit 0
#   2. config disabled + 漂移 → exit 0 (warn)
#   3. config enabled + 漂移 → exit 1 (block)
#   4. config enabled + 无漂移 → exit 0
#   5. 报告聚合产物 .engineering-sync-report.json 写入

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_test_helpers.sh
source "$SCRIPT_DIR/_test_helpers.sh"

PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GATE="$PLUGIN_ROOT/runtime/scripts/engineering-sync-gate.sh"

if [ ! -x "$GATE" ]; then
  red "engineering-sync-gate.sh missing or not executable: $GATE"
  exit 1
fi

setup_repo() {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/plugins/spec-autopilot/skills/sample"
  mkdir -p "$tmp/plugins/spec-autopilot/runtime/scripts"
  echo "# Sample" >"$tmp/plugins/spec-autopilot/skills/sample/SKILL.md"
  echo "# spec-autopilot" >"$tmp/plugins/spec-autopilot/README.md"
  echo "# spec-autopilot" >"$tmp/plugins/spec-autopilot/README.zh.md"
  echo "# CLAUDE" >"$tmp/plugins/spec-autopilot/CLAUDE.md"
  echo "" >"$tmp/plugins/spec-autopilot/runtime/scripts/.dist-include"
  echo "# Root" >"$tmp/README.md"
  echo "# Root" >"$tmp/README.zh.md"
  mkdir -p "$tmp/.claude"
  echo "$tmp"
}

write_config() {
  local root="$1" enabled="$2"
  cat >"$root/.claude/autopilot.config.yaml" <<EOF
engineering_auto_sync:
  enabled: $enabled
EOF
}

green "=== test_engineering_sync_gate.sh ==="

# Case 1: no config → soft mode
TMP1=$(setup_repo)
echo "# Sample v2" >"$TMP1/plugins/spec-autopilot/skills/sample/SKILL.md"
OUT1=$(AUTOPILOT_PROJECT_ROOT="$TMP1" "$GATE" --changed-files "plugins/spec-autopilot/skills/sample/SKILL.md" 2>&1)
RC1=$?
assert_exit "1a. no config → exit 0 (soft)" 0 $RC1
assert_file_exists "1b. report written" "$TMP1/.cache/spec-autopilot/engineering-sync-report.json"
rm -rf "$TMP1"

# Case 2: disabled + drift → exit 0
TMP2=$(setup_repo)
write_config "$TMP2" "false"
echo "# Sample v2" >"$TMP2/plugins/spec-autopilot/skills/sample/SKILL.md"
OUT2=$(AUTOPILOT_PROJECT_ROOT="$TMP2" "$GATE" --changed-files "plugins/spec-autopilot/skills/sample/SKILL.md" 2>&1)
RC2=$?
assert_exit "2a. disabled → exit 0" 0 $RC2
assert_contains "2b. mode reported" "$OUT2" "ENGINEERING_SYNC_MODE=warn"
rm -rf "$TMP2"

# Case 3: enabled + drift → exit 1
TMP3=$(setup_repo)
write_config "$TMP3" "true"
echo "# Sample v2" >"$TMP3/plugins/spec-autopilot/skills/sample/SKILL.md"
set +e
OUT3=$(AUTOPILOT_PROJECT_ROOT="$TMP3" "$GATE" --changed-files "plugins/spec-autopilot/skills/sample/SKILL.md" 2>&1)
RC3=$?
set -e
assert_exit "3a. enabled + drift → exit 1" 1 $RC3
assert_contains "3b. block mode" "$OUT3" "ENGINEERING_SYNC_MODE=block"
rm -rf "$TMP3"

# Case 4: enabled + no drift → exit 0
TMP4=$(setup_repo)
write_config "$TMP4" "true"
OUT4=$(AUTOPILOT_PROJECT_ROOT="$TMP4" "$GATE" --changed-files "" 2>&1)
RC4=$?
assert_exit "4a. enabled + no drift → exit 0" 0 $RC4
rm -rf "$TMP4"

# Case 5: report contains both subreports
TMP5=$(setup_repo)
write_config "$TMP5" "false"
echo "# Sample v2" >"$TMP5/plugins/spec-autopilot/skills/sample/SKILL.md"
"$GATE" --changed-files "plugins/spec-autopilot/skills/sample/SKILL.md" >/dev/null 2>&1 <<<"" || true
AUTOPILOT_PROJECT_ROOT="$TMP5" "$GATE" --changed-files "plugins/spec-autopilot/skills/sample/SKILL.md" >/dev/null 2>&1 || true
assert_file_contains "5a. report has doc_drift section" "$TMP5/.cache/spec-autopilot/engineering-sync-report.json" "doc_drift"
assert_file_contains "5b. report has test_rot section" "$TMP5/.cache/spec-autopilot/engineering-sync-report.json" "test_rot"
rm -rf "$TMP5"

echo
green "Results: $PASS passed, $FAIL failed"

[ "$FAIL" -eq 0 ] || exit 1
exit 0
