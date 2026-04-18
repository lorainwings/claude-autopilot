#!/usr/bin/env bash
# detect-doc-drift.sh — 文档漂移静态检测器（候选清单生成器）
#
# 设计原则：
#   - 静态检测（grep / regex），不依赖 LLM
#   - 仅生成候选清单 .drift-candidates.json，不自动修复
#   - 支持 .drift-ignore 抑制误报
#   - 退出码恒为 0（warn-only），由 engineering-sync-gate.sh 决定 block/warn
#
# 输入：
#   --changed-files "<space-separated-relative-paths>"
#
# 输出：
#   stdout: DRIFT_CANDIDATES=N
#   file: <project_root>/.drift-candidates.json
#
# 检测规则：
#   R1 (warn): SKILL.md 修改但 README.md/README.zh.md 未同步
#   R2 (warn): 新增 runtime 脚本未登记 .dist-include
#   R3 (info): CLAUDE.md 修改 → 提示版本标识
#   R4 (info): autopilot/SKILL.md Phase 总览变化 → 提示流程图刷新
#   R5 (warn): 新增 SKILL.md 但根 README 表格未更新

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "$SCRIPT_DIR/_common.sh"

CHANGED_FILES=""
while [ $# -gt 0 ]; do
  case "$1" in
    --changed-files)
      CHANGED_FILES="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

PROJECT_ROOT=$(resolve_project_root)
CACHE_DIR="${PROJECT_ROOT}/.cache/spec-autopilot"
mkdir -p "$CACHE_DIR"
OUTPUT_FILE="$CACHE_DIR/drift-candidates.json"
IGNORE_FILE="$PROJECT_ROOT/.drift-ignore"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# --- 加载忽略规则 ---
declare -a IGNORE_RULES=()
declare -a IGNORE_PATHS=()
if [ -f "$IGNORE_FILE" ]; then
  while IFS= read -r line; do
    # 跳过注释与空行
    case "$line" in
      \#* | "") continue ;;
    esac
    if [[ "$line" == rule_id:* ]]; then
      # rule_id:R1 [path:...]
      rule=$(echo "$line" | sed -n 's/.*rule_id:\([A-Za-z0-9_]*\).*/\1/p')
      pathv=$(echo "$line" | sed -n 's/.*path:\([^ ]*\).*/\1/p')
      IGNORE_RULES+=("${rule}|${pathv}")
    else
      IGNORE_PATHS+=("$line")
    fi
  done <"$IGNORE_FILE"
fi

is_ignored() {
  local rule_id="$1" path="$2"
  for entry in "${IGNORE_RULES[@]:-}"; do
    [ -z "$entry" ] && continue
    local r="${entry%%|*}" p="${entry##*|}"
    if [ "$r" = "$rule_id" ]; then
      if [ -z "$p" ] || [[ "$path" == *"$p"* ]]; then
        return 0
      fi
    fi
  done
  for p in "${IGNORE_PATHS[@]:-}"; do
    [ -z "$p" ] && continue
    if [[ "$path" == *"$p"* ]]; then
      return 0
    fi
  done
  return 1
}

# --- JSON 候选累积（写入临时文件，避免 shell 引号地狱）---
CANDIDATES_FILE=$(mktemp)
# shellcheck disable=SC2064
trap "rm -f '$CANDIDATES_FILE'" EXIT

add_candidate() {
  local rule_id="$1" severity="$2" source_file="$3" target_file="$4" reason="$5" evidence="$6"
  if is_ignored "$rule_id" "$source_file"; then
    return 0
  fi
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

# --- 拆分变更列表 ---
read -r -a FILES_ARR <<<"$CHANGED_FILES"

# --- 规则评估 ---
README_TOUCHED=false
ROOT_README_TOUCHED=false
DIST_INCLUDE_TOUCHED=false
for f in "${FILES_ARR[@]:-}"; do
  case "$f" in
    plugins/spec-autopilot/README.md | plugins/spec-autopilot/README.zh.md)
      README_TOUCHED=true
      ;;
    README.md | README.zh.md)
      ROOT_README_TOUCHED=true
      ;;
    plugins/spec-autopilot/runtime/scripts/.dist-include)
      DIST_INCLUDE_TOUCHED=true
      ;;
  esac
done

DIST_INCLUDE_FILE="$PROJECT_ROOT/plugins/spec-autopilot/runtime/scripts/.dist-include"

for f in "${FILES_ARR[@]:-}"; do
  [ -z "$f" ] && continue

  # R1: SKILL.md 修改但 README 未同步
  if [[ "$f" =~ ^plugins/spec-autopilot/skills/([^/]+)/SKILL\.md$ ]]; then
    skill_name="${BASH_REMATCH[1]}"
    skill_full_path="$PROJECT_ROOT/$f"
    if [ -f "$skill_full_path" ] && [ "$README_TOUCHED" = false ]; then
      add_candidate "R1" "warn" "$f" "plugins/spec-autopilot/README.md" \
        "SKILL.md modified but README not synced" \
        "skill=$skill_name"
    fi

    # R5: 若 README 中无该 skill 名（潜在新增）→ 提示根 README 表格
    if [ -f "$PROJECT_ROOT/README.md" ] && ! grep -q -- "$skill_name" "$PROJECT_ROOT/README.md" 2>/dev/null; then
      if [ "$ROOT_README_TOUCHED" = false ]; then
        add_candidate "R5" "warn" "$f" "README.md" \
          "New SKILL.md not registered in root README plugin table" \
          "skill=$skill_name"
      fi
    fi
  fi

  # R2: 新增 runtime 脚本未登记 .dist-include
  if [[ "$f" =~ ^plugins/spec-autopilot/runtime/scripts/([^/]+\.sh)$ ]]; then
    script_name="${BASH_REMATCH[1]}"
    if [ -f "$DIST_INCLUDE_FILE" ]; then
      if ! grep -q -E "^${script_name}\$" "$DIST_INCLUDE_FILE" 2>/dev/null; then
        if [ "$DIST_INCLUDE_TOUCHED" = false ]; then
          add_candidate "R2" "warn" "$f" "plugins/spec-autopilot/runtime/scripts/.dist-include" \
            "New runtime script not registered in .dist-include" \
            "script=$script_name"
        fi
      fi
    fi
  fi

  # R3: CLAUDE.md 修改 → 版本标识提示
  if [ "$f" = "plugins/spec-autopilot/CLAUDE.md" ]; then
    add_candidate "R3" "info" "$f" "plugins/spec-autopilot/README.md" \
      "CLAUDE.md changed; verify README version banner is still accurate" \
      "manual-check"
  fi

  # R4: autopilot/SKILL.md Phase 总览
  if [ "$f" = "plugins/spec-autopilot/skills/autopilot/SKILL.md" ]; then
    add_candidate "R4" "info" "$f" "docs/plans/" \
      "autopilot/SKILL.md changed; verify docs/plans/ flow diagrams" \
      "manual-check"
  fi
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

echo "DRIFT_CANDIDATES=$COUNT"

# 打印候选规则 ID 摘要（供 pre-commit 日志 / 测试断言使用）
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
