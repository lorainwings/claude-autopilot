#!/usr/bin/env bash
# test_generate_doc_fix.sh — 验证 generate-doc-fix-patch.sh 的候选转 patch 能力
#
# 测试覆盖：
#   1. R2 candidate → 生成 auto patch 且能 git apply --check
#   2. R1 candidate → 生成 manual suggestion.md
#   3. 空候选清单 → 0 patch exit 0
#   4. 缺失候选文件 → clear error + exit 1
#   5. INDEX.json schema 验证

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_test_helpers.sh
source "$SCRIPT_DIR/_test_helpers.sh"

PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GEN="$PLUGIN_ROOT/runtime/scripts/generate-doc-fix-patch.sh"

if [ ! -x "$GEN" ]; then
  red "generate-doc-fix-patch.sh missing or not executable: $GEN"
  exit 1
fi

# 初始化一个最小 repo（带 git 以便 git apply --check 可用）
setup_repo() {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/plugins/spec-autopilot/runtime/scripts"
  mkdir -p "$tmp/plugins/spec-autopilot/skills/sample-skill"
  cat >"$tmp/plugins/spec-autopilot/runtime/scripts/.dist-include" <<'EOF'
# allowlist
existing.sh
EOF
  touch "$tmp/plugins/spec-autopilot/runtime/scripts/brand-new.sh"
  echo "# Sample Skill" >"$tmp/plugins/spec-autopilot/skills/sample-skill/SKILL.md"
  echo "# README" >"$tmp/plugins/spec-autopilot/README.md"
  (cd "$tmp" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -q -m init) || true
  echo "$tmp"
}

write_candidates() {
  # $1: tmpdir, $2: JSON literal
  local tmp="$1" payload="$2"
  printf '%s' "$payload" >"$tmp/.drift-candidates.json"
}

green "=== test_generate_doc_fix.sh ==="

# Case 1: R2 auto patch
TMP1=$(setup_repo)
write_candidates "$TMP1" '{
  "timestamp":"2026-04-18T00:00:00Z",
  "checks":[
    {"rule_id":"R2","severity":"warn",
     "source_file":"plugins/spec-autopilot/runtime/scripts/brand-new.sh",
     "target_file":"plugins/spec-autopilot/runtime/scripts/.dist-include",
     "reason":"new script not registered",
     "evidence":"brand-new.sh"}
  ]}'
OUT1=$(AUTOPILOT_PROJECT_ROOT="$TMP1" "$GEN" \
  --candidates-file "$TMP1/.drift-candidates.json" \
  --output-dir "$TMP1/.docs-fix-patches" 2>&1 || true)
RC1=$?
assert_exit "1a. R2 → exit 0" 0 $RC1
assert_file_exists "1b. INDEX.json created" "$TMP1/.docs-fix-patches/INDEX.json"
# 找到 auto patch
PATCH1=$(ls "$TMP1/.docs-fix-patches"/*.patch 2>/dev/null | head -1 || true)
assert_contains "1c. patch file exists" "$PATCH1" ".patch"
if [ -n "$PATCH1" ]; then
  (cd "$TMP1" && git apply --check "$PATCH1" 2>&1) &&
    {
      green "  PASS: 1d. patch applies cleanly"
      PASS=$((PASS + 1))
    } ||
    {
      red "  FAIL: 1d. patch does not apply"
      FAIL=$((FAIL + 1))
    }
fi
assert_contains "1e. summary stdout" "$OUT1" "patches"
rm -rf "$TMP1"

# Case 2: R1 → suggestion.md
TMP2=$(setup_repo)
write_candidates "$TMP2" '{
  "timestamp":"2026-04-18T00:00:00Z",
  "checks":[
    {"rule_id":"R1","severity":"warn",
     "source_file":"plugins/spec-autopilot/skills/sample-skill/SKILL.md",
     "target_file":"plugins/spec-autopilot/README.md",
     "reason":"SKILL.md changed without README update",
     "evidence":"manual"}
  ]}'
AUTOPILOT_PROJECT_ROOT="$TMP2" "$GEN" \
  --candidates-file "$TMP2/.drift-candidates.json" \
  --output-dir "$TMP2/.docs-fix-patches" >/dev/null 2>&1
RC2=$?
assert_exit "2a. R1 → exit 0" 0 $RC2
SUG2=$(ls "$TMP2/.docs-fix-patches"/*.suggestion.md 2>/dev/null | head -1 || true)
assert_contains "2b. suggestion.md exists" "$SUG2" ".suggestion.md"
if [ -n "$SUG2" ]; then
  assert_file_contains "2c. suggestion mentions target README" "$SUG2" "README.md"
  assert_file_contains "2d. suggestion mentions rule R1" "$SUG2" "R1"
fi
rm -rf "$TMP2"

# Case 3: empty candidates
TMP3=$(setup_repo)
write_candidates "$TMP3" '{"timestamp":"2026-04-18T00:00:00Z","checks":[]}'
OUT3=$(AUTOPILOT_PROJECT_ROOT="$TMP3" "$GEN" \
  --candidates-file "$TMP3/.drift-candidates.json" \
  --output-dir "$TMP3/.docs-fix-patches" 2>&1 || true)
RC3=$?
assert_exit "3a. empty → exit 0" 0 $RC3
assert_contains "3b. 0 patches message" "$OUT3" "0"
rm -rf "$TMP3"

# Case 4: missing candidates file
TMP4=$(setup_repo)
set +e
OUT4=$(AUTOPILOT_PROJECT_ROOT="$TMP4" "$GEN" \
  --candidates-file "$TMP4/.drift-candidates.json" \
  --output-dir "$TMP4/.docs-fix-patches" 2>&1)
RC4=$?
set -e
assert_exit "4a. missing file → exit 1" 1 $RC4
assert_contains "4b. clear error message" "$OUT4" "not found"
rm -rf "$TMP4"

# Case 5: INDEX.json schema
TMP5=$(setup_repo)
write_candidates "$TMP5" '{
  "timestamp":"2026-04-18T00:00:00Z",
  "checks":[
    {"rule_id":"R2","severity":"warn",
     "source_file":"plugins/spec-autopilot/runtime/scripts/brand-new.sh",
     "target_file":"plugins/spec-autopilot/runtime/scripts/.dist-include",
     "reason":"x","evidence":"brand-new.sh"},
    {"rule_id":"R1","severity":"warn",
     "source_file":"plugins/spec-autopilot/skills/sample-skill/SKILL.md",
     "target_file":"plugins/spec-autopilot/README.md",
     "reason":"y","evidence":"m"}
  ]}'
AUTOPILOT_PROJECT_ROOT="$TMP5" "$GEN" \
  --candidates-file "$TMP5/.drift-candidates.json" \
  --output-dir "$TMP5/.docs-fix-patches" >/dev/null 2>&1
SCHEMA_OK=$(python3 -c "
import json,sys
d=json.load(open('$TMP5/.docs-fix-patches/INDEX.json'))
assert 'patches' in d and isinstance(d['patches'], list)
assert len(d['patches']) == 2
types=sorted({p['type'] for p in d['patches']})
assert types == ['auto','manual'], types
for p in d['patches']:
  for k in ('id','type','target','apply_cmd'):
    assert k in p, k
print('OK')
" 2>&1 || echo FAIL)
assert_contains "5a. INDEX schema validates" "$SCHEMA_OK" "OK"
rm -rf "$TMP5"

green "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
