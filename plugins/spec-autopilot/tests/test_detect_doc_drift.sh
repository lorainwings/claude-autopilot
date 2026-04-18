#!/usr/bin/env bash
# test_detect_doc_drift.sh — 验证 detect-doc-drift.sh 的静态漂移检测能力
#
# 测试覆盖：
#   1. SKILL.md 修改但 README 未同步 → 报告漂移候选 (R1)
#   2. SKILL.md 修改且 README 已同步 → 无漂移
#   3. 新增 runtime 脚本未登记 .dist-include → 报告漂移候选 (R2)
#   4. 新增 runtime 脚本已登记 .dist-include → 无漂移
#   5. CLAUDE.md 修改 → 提示版本标识检查 (R3, info 级别)
#   6. 新增 SKILL.md 但根 README 表格未更新 → 报告漂移候选 (R5)
#   7. 空 staging → exit 0, DRIFT_CANDIDATES=0
#   8. .drift-ignore 抑制特定规则触发

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_test_helpers.sh
source "$SCRIPT_DIR/_test_helpers.sh"

PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DETECT="$PLUGIN_ROOT/runtime/scripts/detect-doc-drift.sh"

if [ ! -x "$DETECT" ]; then
  red "detect-doc-drift.sh missing or not executable: $DETECT"
  exit 1
fi

setup_repo() {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/plugins/spec-autopilot/skills/sample-skill"
  mkdir -p "$tmp/plugins/spec-autopilot/runtime/scripts"
  echo "# Sample Skill" >"$tmp/plugins/spec-autopilot/skills/sample-skill/SKILL.md"
  cat >"$tmp/plugins/spec-autopilot/README.md" <<'EOF'
# spec-autopilot

## Skills

- sample-skill: original description
EOF
  cat >"$tmp/plugins/spec-autopilot/README.zh.md" <<'EOF'
# spec-autopilot

## 技能

- sample-skill: 原始描述
EOF
  echo "# Spec Autopilot CLAUDE" >"$tmp/plugins/spec-autopilot/CLAUDE.md"
  cat >"$tmp/plugins/spec-autopilot/runtime/scripts/.dist-include" <<'EOF'
existing-script.sh
EOF
  cat >"$tmp/README.md" <<'EOF'
# Root README
| Plugin | Version |
|--------|---------|
| sample-skill | 1.0 |
EOF
  cat >"$tmp/README.zh.md" <<'EOF'
# 根 README
| 插件 | 版本 |
|------|------|
| sample-skill | 1.0 |
EOF
  echo "$tmp"
}

green "=== test_detect_doc_drift.sh ==="

# Case 1: SKILL.md modified but README untouched
TMP1=$(setup_repo)
# Pretend SKILL.md is in changed list while README is not
echo "# Sample Skill v2" >"$TMP1/plugins/spec-autopilot/skills/sample-skill/SKILL.md"
OUT1=$(AUTOPILOT_PROJECT_ROOT="$TMP1" "$DETECT" --changed-files "plugins/spec-autopilot/skills/sample-skill/SKILL.md" 2>&1 || true)
RC1=$?
assert_exit "1a. R1 drift detected → exit 0 (warn-only)" 0 $RC1
assert_contains "1b. summary line emitted" "$OUT1" "DRIFT_CANDIDATES="
assert_contains "1c. mentions rule R1" "$OUT1" "R1"
assert_file_exists "1d. drift-candidates.json written" "$TMP1/.cache/spec-autopilot/drift-candidates.json"
rm -rf "$TMP1"

# Case 2: SKILL.md modified AND README modified
TMP2=$(setup_repo)
echo "# Sample Skill v2" >"$TMP2/plugins/spec-autopilot/skills/sample-skill/SKILL.md"
echo "- sample-skill: updated description" >>"$TMP2/plugins/spec-autopilot/README.md"
OUT2=$(AUTOPILOT_PROJECT_ROOT="$TMP2" "$DETECT" --changed-files "plugins/spec-autopilot/skills/sample-skill/SKILL.md plugins/spec-autopilot/README.md" 2>&1 || true)
RC2=$?
assert_exit "2a. R1 satisfied → exit 0" 0 $RC2
assert_not_contains "2b. R1 not in candidates" "$OUT2" "rule_id\":\"R1"
rm -rf "$TMP2"

# Case 3: new runtime script not in .dist-include
TMP3=$(setup_repo)
touch "$TMP3/plugins/spec-autopilot/runtime/scripts/brand-new.sh"
OUT3=$(AUTOPILOT_PROJECT_ROOT="$TMP3" "$DETECT" --changed-files "plugins/spec-autopilot/runtime/scripts/brand-new.sh" 2>&1 || true)
RC3=$?
assert_exit "3a. R2 drift → exit 0" 0 $RC3
assert_contains "3b. mentions R2" "$OUT3" "R2"
rm -rf "$TMP3"

# Case 4: new runtime script registered
TMP4=$(setup_repo)
touch "$TMP4/plugins/spec-autopilot/runtime/scripts/registered.sh"
echo "registered.sh" >>"$TMP4/plugins/spec-autopilot/runtime/scripts/.dist-include"
OUT4=$(AUTOPILOT_PROJECT_ROOT="$TMP4" "$DETECT" --changed-files "plugins/spec-autopilot/runtime/scripts/registered.sh" 2>&1 || true)
RC4=$?
assert_exit "4a. R2 satisfied → exit 0" 0 $RC4
assert_not_contains "4b. R2 not in candidates" "$OUT4" "\"rule_id\":\"R2\""
rm -rf "$TMP4"

# Case 5: CLAUDE.md changed → R3 info-level reminder
TMP5=$(setup_repo)
echo "# Updated CLAUDE" >"$TMP5/plugins/spec-autopilot/CLAUDE.md"
OUT5=$(AUTOPILOT_PROJECT_ROOT="$TMP5" "$DETECT" --changed-files "plugins/spec-autopilot/CLAUDE.md" 2>&1 || true)
RC5=$?
assert_exit "5a. R3 hint → exit 0" 0 $RC5
assert_contains "5b. mentions R3" "$OUT5" "R3"
rm -rf "$TMP5"

# Case 6: new SKILL.md but root README not updated → R5
TMP6=$(setup_repo)
mkdir -p "$TMP6/plugins/spec-autopilot/skills/brand-new-skill"
echo "# Brand New Skill" >"$TMP6/plugins/spec-autopilot/skills/brand-new-skill/SKILL.md"
OUT6=$(AUTOPILOT_PROJECT_ROOT="$TMP6" "$DETECT" --changed-files "plugins/spec-autopilot/skills/brand-new-skill/SKILL.md" 2>&1 || true)
RC6=$?
assert_exit "6a. R5 drift → exit 0" 0 $RC6
assert_contains "6b. mentions R5" "$OUT6" "R5"
rm -rf "$TMP6"

# Case 7: empty staging → 0 candidates
TMP7=$(setup_repo)
OUT7=$(AUTOPILOT_PROJECT_ROOT="$TMP7" "$DETECT" --changed-files "" 2>&1 || true)
RC7=$?
assert_exit "7a. empty staging → exit 0" 0 $RC7
assert_contains "7b. zero candidates" "$OUT7" "DRIFT_CANDIDATES=0"
rm -rf "$TMP7"

# Case 8: .drift-ignore suppresses R1
TMP8=$(setup_repo)
echo "# Sample Skill v2" >"$TMP8/plugins/spec-autopilot/skills/sample-skill/SKILL.md"
cat >"$TMP8/.drift-ignore" <<'EOF'
rule_id:R1
EOF
OUT8=$(AUTOPILOT_PROJECT_ROOT="$TMP8" "$DETECT" --changed-files "plugins/spec-autopilot/skills/sample-skill/SKILL.md" 2>&1 || true)
RC8=$?
assert_exit "8a. ignore active → exit 0" 0 $RC8
assert_not_contains "8b. R1 suppressed" "$OUT8" "\"rule_id\":\"R1\""
rm -rf "$TMP8"

echo
green "Results: $PASS passed, $FAIL failed"

[ "$FAIL" -eq 0 ] || exit 1
exit 0
