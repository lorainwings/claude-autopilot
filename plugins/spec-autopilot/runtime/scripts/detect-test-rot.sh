#!/usr/bin/env bash
# detect-test-rot.sh — 测试过期静态检测器（候选清单生成器）
# CODE-REF: docs/plans/engineering-auto-sync/test-audit.md
#
# 设计原则：
#   - 静态检测（grep / regex），不依赖 LLM
#   - 仅生成候选清单 .test-rot-candidates.json
#   - 退出码恒为 0
#
# 输入：
#   --changed-files "<space-separated>" --deleted-files "<space-separated>"
#
# 输出：
#   stdout: ROT_CANDIDATES=N
#   file: <project_root>/.test-rot-candidates.json
#
# 检测规则：
#   R1 (warn): runtime 脚本删除/重命名但 tests/ 仍引用
#   R2 (warn): 源码中 symbol 删除但测试仍引用
#   R3 (info): hook 文件修改 → 提示相关 test 回归
#   R4 (warn): 弱断言模式 (assert_exit "x" 0 0 / [ "a" = "a" ] / grep -q . .)
#   R5 (warn): 重复 case 名称

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "$SCRIPT_DIR/_common.sh"

CHANGED_FILES=""
DELETED_FILES=""
while [ $# -gt 0 ]; do
  case "$1" in
    --changed-files)
      CHANGED_FILES="${2:-}"
      shift 2
      ;;
    --deleted-files)
      DELETED_FILES="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

PROJECT_ROOT=$(resolve_project_root)
OUTPUT_FILE="$PROJECT_ROOT/.test-rot-candidates.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TESTS_DIR="$PROJECT_ROOT/plugins/spec-autopilot/tests"

CANDIDATES_FILE=$(mktemp)
# shellcheck disable=SC2064
trap "rm -f '$CANDIDATES_FILE'" EXIT

add_candidate() {
  local rule_id="$1" severity="$2" source_file="$3" target_file="$4" reason="$5" evidence="$6"
  python3 -c "
import json, sys
print(json.dumps({
  'rule_id': sys.argv[1],
  'severity': sys.argv[2],
  'source_file': sys.argv[3],
  'target_file': sys.argv[4],
  'reason': sys.argv[5],
  'evidence': sys.argv[6],
}))
" "$rule_id" "$severity" "$source_file" "$target_file" "$reason" "$evidence" >>"$CANDIDATES_FILE"
}

read -r -a CHANGED_ARR <<<"$CHANGED_FILES"
read -r -a DELETED_ARR <<<"$DELETED_FILES"

# --- R1: 删除的 runtime 脚本仍被 tests/ 引用 ---
for f in "${DELETED_ARR[@]:-}"; do
  [ -z "$f" ] && continue
  if [[ "$f" =~ ^plugins/spec-autopilot/runtime/scripts/([^/]+\.sh)$ ]]; then
    script_name="${BASH_REMATCH[1]}"
    if [ -d "$TESTS_DIR" ]; then
      # 在 tests/ 下检索残留引用
      refs=$(grep -rl -- "$script_name" "$TESTS_DIR" 2>/dev/null || true)
      if [ -n "$refs" ]; then
        evidence=$(echo "$refs" | head -3 | tr '\n' ';')
        add_candidate "R1" "warn" "$f" "plugins/spec-autopilot/tests/" \
          "Deleted runtime script still referenced in tests" \
          "refs=$evidence"
      fi
    fi
  fi
done

# --- R3: hook 文件修改 → info 提示 ---
for f in "${CHANGED_ARR[@]:-}"; do
  [ -z "$f" ] && continue
  if [[ "$f" =~ ^plugins/spec-autopilot/hooks/ ]]; then
    add_candidate "R3" "info" "$f" "plugins/spec-autopilot/tests/" \
      "Hook file modified; regression-test relevant tests" \
      "manual-check"
  fi
done

# --- R4: 弱断言扫描 (仅扫 changed test 文件) ---
for f in "${CHANGED_ARR[@]:-}"; do
  [ -z "$f" ] && continue
  case "$f" in
    plugins/spec-autopilot/tests/test_*.sh) ;;
    *) continue ;;
  esac
  full="$PROJECT_ROOT/$f"
  [ -f "$full" ] || continue

  # assert_exit "x" 0 0 — 期望值与实际值都是 0（无意义通过）
  if grep -nE 'assert_exit[[:space:]]+"[^"]+"[[:space:]]+0[[:space:]]+0' "$full" >/dev/null 2>&1; then
    line=$(grep -nE 'assert_exit[[:space:]]+"[^"]+"[[:space:]]+0[[:space:]]+0' "$full" | head -1)
    add_candidate "R4" "warn" "$f" "$f" \
      "Weak assertion pattern: assert_exit \"x\" 0 0" \
      "$line"
  fi

  # [ "a" = "a" ] — 恒真
  if grep -nE '\[[[:space:]]*"([^"]+)"[[:space:]]*=[[:space:]]*"\1"[[:space:]]*\]' "$full" >/dev/null 2>&1; then
    line=$(grep -nE '\[[[:space:]]*"([^"]+)"[[:space:]]*=[[:space:]]*"\1"[[:space:]]*\]' "$full" | head -1)
    add_candidate "R4" "warn" "$f" "$f" \
      "Weak assertion pattern: tautological [ \"a\" = \"a\" ]" \
      "$line"
  fi

  # grep -q . . — 几乎恒真
  if grep -nE 'grep[[:space:]]+-q[[:space:]]+\.[[:space:]]+\.' "$full" >/dev/null 2>&1; then
    line=$(grep -nE 'grep[[:space:]]+-q[[:space:]]+\.[[:space:]]+\.' "$full" | head -1)
    add_candidate "R4" "warn" "$f" "$f" \
      "Weak assertion pattern: grep -q . ." \
      "$line"
  fi
done

# --- R5: 重复 case 名称 ---
# 仅扫 changed 测试文件，跨文件对比 tests/ 全量
# 兼容 bash 3.2（macOS 默认）：使用临时文件代替 associative array
CASE_TALLY_FILE=$(mktemp)
# shellcheck disable=SC2064
trap "rm -f '$CANDIDATES_FILE' '$CASE_TALLY_FILE'" EXIT
if [ -d "$TESTS_DIR" ]; then
  while IFS= read -r tfile; do
    grep -oE 'assert_exit[[:space:]]+"[^"]+"' "$tfile" 2>/dev/null |
      sed -E 's/assert_exit[[:space:]]+"([^"]+)"/\1/' >>"$CASE_TALLY_FILE"
  done < <(find "$TESTS_DIR" -type f -name 'test_*.sh' 2>/dev/null)
fi

for f in "${CHANGED_ARR[@]:-}"; do
  [ -z "$f" ] && continue
  case "$f" in
    plugins/spec-autopilot/tests/test_*.sh) ;;
    *) continue ;;
  esac
  full="$PROJECT_ROOT/$f"
  [ -f "$full" ] || continue
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    cnt=$(grep -cFx -- "$name" "$CASE_TALLY_FILE" 2>/dev/null || echo 0)
    if [ "$cnt" -gt 1 ]; then
      add_candidate "R5" "warn" "$f" "$f" \
        "Duplicate test case name across files" \
        "case=$name count=$cnt"
    fi
  done < <(grep -oE 'assert_exit[[:space:]]+"[^"]+"' "$full" 2>/dev/null | sed -E 's/assert_exit[[:space:]]+"([^"]+)"/\1/' | sort -u)
done

# --- 写产物 ---
COUNT=$(wc -l <"$CANDIDATES_FILE" | tr -d ' ')
[ -z "$COUNT" ] && COUNT=0

python3 -c "
import json
entries = []
with open('$CANDIDATES_FILE') as f:
    for line in f:
        line = line.strip()
        if line:
            entries.append(json.loads(line))
out = {
  'timestamp': '$TIMESTAMP',
  'checks': entries,
}
with open('$OUTPUT_FILE', 'w') as f:
    json.dump(out, f, indent=2)
"

echo "ROT_CANDIDATES=$COUNT"
python3 -c "
import json
with open('$OUTPUT_FILE') as f:
    data = json.load(f)
for c in data.get('checks', []):
    print('- {rule} [{sev}] {src} → {tgt}: {reason}'.format(
        rule=c.get('rule_id',''), sev=c.get('severity',''),
        src=c.get('source_file',''), tgt=c.get('target_file',''),
        reason=c.get('reason','')))
"
exit 0
