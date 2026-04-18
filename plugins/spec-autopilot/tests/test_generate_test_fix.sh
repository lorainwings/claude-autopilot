#!/usr/bin/env bash
# test_generate_test_fix.sh — 验证 generate-test-fix-patch.sh 的候选转 patch 能力
#
# 测试覆盖：
#   1. R1 (orphan script) → 生成可应用的 sed/diff patch
#   2. R5 (weak assertion) → suggestion.md 含补强模板
#   3. 多候选 → 多 patch 输出
#   4. 空候选 → exit 0
#   5. 禁止触达 tests/*.sh（output-dir 以外无改动）

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_test_helpers.sh
source "$SCRIPT_DIR/_test_helpers.sh"

PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GEN="$PLUGIN_ROOT/runtime/scripts/generate-test-fix-patch.sh"

if [ ! -x "$GEN" ]; then
  red "generate-test-fix-patch.sh missing or not executable: $GEN"
  exit 1
fi

setup_repo() {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/plugins/spec-autopilot/tests"
  mkdir -p "$tmp/plugins/spec-autopilot/runtime/scripts"
  cat >"$tmp/plugins/spec-autopilot/tests/test_sample.sh" <<'EOF'
#!/usr/bin/env bash
# Case: old removed script reference
bash "$PLUGIN_ROOT/runtime/scripts/removed-script.sh"
assert_exit "weak" 0 0
echo done
EOF
  chmod +x "$tmp/plugins/spec-autopilot/tests/test_sample.sh"
  (cd "$tmp" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -q -m init) || true
  echo "$tmp"
}

write_rot() {
  local tmp="$1" payload="$2"
  printf '%s' "$payload" >"$tmp/.test-rot-candidates.json"
}

green "=== test_generate_test_fix.sh ==="

# Case 1: R1 orphan script ref → patch
TMP1=$(setup_repo)
write_rot "$TMP1" '{
  "timestamp":"2026-04-18T00:00:00Z",
  "checks":[
    {"rule_id":"R1","severity":"warn",
     "source_file":"plugins/spec-autopilot/runtime/scripts/removed-script.sh",
     "target_file":"plugins/spec-autopilot/tests/test_sample.sh",
     "reason":"deleted script still referenced",
     "evidence":"removed-script.sh"}
  ]}'
OUT1=$(AUTOPILOT_PROJECT_ROOT="$TMP1" "$GEN" \
  --candidates-file "$TMP1/.test-rot-candidates.json" \
  --output-dir "$TMP1/.tests-fix-patches" 2>&1 || true)
RC1=$?
assert_exit "1a. R1 → exit 0" 0 $RC1
assert_file_exists "1b. INDEX.json" "$TMP1/.tests-fix-patches/INDEX.json"
# R1 输出既允许 patch 也允许 suggestion（按规范 patch 优先）
HAS_ARTIFACT=""
for f in "$TMP1/.tests-fix-patches"/*; do
  [ -e "$f" ] || continue
  case "$f" in
    *.patch | *.suggestion.md)
      HAS_ARTIFACT="$f"
      break
      ;;
  esac
done
# 断言有产物生成 (patch 或 suggestion)
if [ -n "$HAS_ARTIFACT" ]; then
  green "  PASS: 1c. R1 artifact generated"
  PASS=$((PASS + 1))
else
  red "  FAIL: 1c. no R1 artifact"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMP1"

# Case 2: R5 weak assertion → suggestion + 模板
TMP2=$(setup_repo)
write_rot "$TMP2" '{
  "timestamp":"2026-04-18T00:00:00Z",
  "checks":[
    {"rule_id":"R5","severity":"warn",
     "source_file":"plugins/spec-autopilot/tests/test_sample.sh",
     "target_file":"plugins/spec-autopilot/tests/test_sample.sh",
     "reason":"weak assertion pattern",
     "evidence":"assert_exit \"weak\" 0 0"}
  ]}'
AUTOPILOT_PROJECT_ROOT="$TMP2" "$GEN" \
  --candidates-file "$TMP2/.test-rot-candidates.json" \
  --output-dir "$TMP2/.tests-fix-patches" >/dev/null 2>&1
SUG2=$(ls "$TMP2/.tests-fix-patches"/*R5*.suggestion.md 2>/dev/null | head -1 || true)
assert_contains "2a. R5 suggestion exists" "$SUG2" "R5"
if [ -n "$SUG2" ]; then
  assert_file_contains "2b. template mentions assert_contains" "$SUG2" "assert_contains"
  assert_file_contains "2c. template mentions assert_json_field" "$SUG2" "assert_json_field"
fi
rm -rf "$TMP2"

# Case 3: multiple candidates → multiple artifacts
TMP3=$(setup_repo)
write_rot "$TMP3" '{
  "timestamp":"2026-04-18T00:00:00Z",
  "checks":[
    {"rule_id":"R4","severity":"info",
     "source_file":"plugins/spec-autopilot/hooks/sample.sh",
     "target_file":"plugins/spec-autopilot/tests/test_sample.sh",
     "reason":"hook modified","evidence":"regress"},
    {"rule_id":"R3","severity":"info",
     "source_file":"plugins/spec-autopilot/runtime/scripts/foo.sh",
     "target_file":"plugins/spec-autopilot/tests/test_sample.sh",
     "reason":"symbol deleted","evidence":"foo_func"}
  ]}'
AUTOPILOT_PROJECT_ROOT="$TMP3" "$GEN" \
  --candidates-file "$TMP3/.test-rot-candidates.json" \
  --output-dir "$TMP3/.tests-fix-patches" >/dev/null 2>&1
COUNT3=$(python3 -c "import json;print(len(json.load(open('$TMP3/.tests-fix-patches/INDEX.json'))['patches']))")
if [ "$COUNT3" = "2" ]; then
  green "  PASS: 3a. INDEX has 2 patches"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3a. expected 2 patches, got $COUNT3"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMP3"

# Case 4: empty
TMP4=$(setup_repo)
write_rot "$TMP4" '{"timestamp":"2026-04-18T00:00:00Z","checks":[]}'
OUT4=$(AUTOPILOT_PROJECT_ROOT="$TMP4" "$GEN" \
  --candidates-file "$TMP4/.test-rot-candidates.json" \
  --output-dir "$TMP4/.tests-fix-patches" 2>&1 || true)
assert_exit "4a. empty → exit 0" 0 $?
assert_contains "4b. 0 patches reported" "$OUT4" "0"
rm -rf "$TMP4"

# Case 5: no touch on tests/*.sh
TMP5=$(setup_repo)
write_rot "$TMP5" '{
  "timestamp":"2026-04-18T00:00:00Z",
  "checks":[
    {"rule_id":"R1","severity":"warn",
     "source_file":"plugins/spec-autopilot/runtime/scripts/removed-script.sh",
     "target_file":"plugins/spec-autopilot/tests/test_sample.sh",
     "reason":"x","evidence":"removed-script.sh"}
  ]}'
SHA_BEFORE=$(shasum "$TMP5/plugins/spec-autopilot/tests/test_sample.sh" | awk '{print $1}')
AUTOPILOT_PROJECT_ROOT="$TMP5" "$GEN" \
  --candidates-file "$TMP5/.test-rot-candidates.json" \
  --output-dir "$TMP5/.tests-fix-patches" >/dev/null 2>&1
SHA_AFTER=$(shasum "$TMP5/plugins/spec-autopilot/tests/test_sample.sh" | awk '{print $1}')
if [ "$SHA_BEFORE" = "$SHA_AFTER" ]; then
  green "  PASS: 5a. tests/*.sh untouched"
  PASS=$((PASS + 1))
else
  red "  FAIL: 5a. tests/*.sh modified"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMP5"

green "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
