#!/usr/bin/env bash
# apply-fix-patch.sh — 在 git stash 保护下应用 fix patch
#
# 设计原则:
#   - 必须在 git 仓库内运行
#   - 始终先 git stash push -u 保护 working tree
#   - 每个 patch 先 git apply --check 预校验, 失败立即 stash pop 回滚
#   - 默认仅允许 type:auto; manual 需 --force-manual
#   - 严禁在 CI / pre-commit 中调用; 仅供开发者手动触发
#
# 输入:
#   --index <path>           INDEX.json 路径 (必填)
#   --patch-id <id>          单个 patch id
#   --all                    应用 INDEX 中所有 auto patch
#   --dry-run                只检查不实际 apply
#   --force-manual           允许应用 manual 类型 (实际只是标记 acknowledge)
#
# 退出码:
#   0 成功
#   1 通用错误 (索引缺失 / patch id 不存在 / apply 失败)
#   2 拒绝应用 manual patch 而未指定 --force-manual

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "$SCRIPT_DIR/_common.sh"

INDEX=""
PATCH_ID=""
APPLY_ALL=0
DRY_RUN=0
FORCE_MANUAL=0

while [ $# -gt 0 ]; do
  case "$1" in
    --index)
      INDEX="${2:-}"
      shift 2
      ;;
    --patch-id)
      PATCH_ID="${2:-}"
      shift 2
      ;;
    --all)
      APPLY_ALL=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --force-manual)
      FORCE_MANUAL=1
      shift
      ;;
    *)
      shift
      ;;
  esac
done

PROJECT_ROOT=$(resolve_project_root)

if [ -z "$INDEX" ]; then
  # 默认按存在性查找
  for cand in "$PROJECT_ROOT/.docs-fix-patches/INDEX.json" "$PROJECT_ROOT/.tests-fix-patches/INDEX.json"; do
    [ -f "$cand" ] && INDEX="$cand" && break
  done
fi

if [ ! -f "$INDEX" ]; then
  echo "ERROR: INDEX.json not found (use --index <path>)" >&2
  exit 1
fi

if [ -z "$PATCH_ID" ] && [ "$APPLY_ALL" -ne 1 ]; then
  echo "ERROR: must provide --patch-id <id> or --all" >&2
  exit 1
fi

PATCH_DIR=$(dirname "$INDEX")

# 解析 INDEX 找出待应用 patch 列表 (id|type|target|apply_cmd)
SELECTED=$(
  python3 - "$INDEX" "$PATCH_ID" "$APPLY_ALL" <<'PY'
import json, sys
idx, pid, all_flag = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
data = json.load(open(idx))
patches = data.get("patches", [])
out = []
if all_flag:
    out = [p for p in patches if p.get("type") == "auto"]
else:
    out = [p for p in patches if p.get("id") == pid]
for p in out:
    print("|".join([p.get("id",""), p.get("type",""), p.get("target",""), p.get("apply_cmd","")]))
PY
)

if [ -z "$SELECTED" ]; then
  if [ -n "$PATCH_ID" ]; then
    echo "ERROR: patch id not found in index: $PATCH_ID" >&2
    exit 1
  else
    echo "INFO: no auto patches to apply"
    exit 0
  fi
fi

# 类型校验: 单 patch 模式下若为 manual 且未 force, 拒绝
if [ -n "$PATCH_ID" ] && [ "$APPLY_ALL" -ne 1 ]; then
  PTYPE=$(printf "%s" "$SELECTED" | head -1 | awk -F'|' '{print $2}')
  if [ "$PTYPE" = "manual" ] && [ "$FORCE_MANUAL" -ne 1 ]; then
    echo "ERROR: patch '$PATCH_ID' is type=manual; pass --force-manual to acknowledge" >&2
    exit 2
  fi
fi

cd "$PROJECT_ROOT" || exit 1

# 必须是 git 仓库
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "ERROR: not in a git repository" >&2
  exit 1
fi

# 在 stash 之前, 把 patch 文件快照到临时目录, 避免 -u stash 把未追踪的 PATCH_DIR 一起藏起来
SNAPSHOT_DIR=$(mktemp -d)
# shellcheck disable=SC2064
trap "rm -rf '$SNAPSHOT_DIR'" EXIT
if [ -d "$PATCH_DIR" ]; then
  cp -R "$PATCH_DIR"/. "$SNAPSHOT_DIR"/ 2>/dev/null || true
fi

TS=$(date -u +"%Y%m%d%H%M%S")
STASH_MSG="pre-apply-fix-patch-$TS"
STASH_CREATED=0

# 仅当存在变更时才 stash
if [ -n "$(git status --porcelain)" ]; then
  if [ "$DRY_RUN" -eq 0 ]; then
    if git stash push -u -m "$STASH_MSG" >/dev/null 2>&1; then
      STASH_CREATED=1
    fi
  fi
fi

rollback() {
  if [ "$STASH_CREATED" -eq 1 ]; then
    # 找到对应 stash 并 pop
    local ref
    ref=$(git stash list 2>/dev/null | grep -F "$STASH_MSG" | head -1 | awk -F: '{print $1}')
    if [ -n "$ref" ]; then
      git stash pop "$ref" >/dev/null 2>&1 || true
    fi
  fi
}

APPLIED=0
FAILED=0

# bash 3.2 兼容: 用 while read 解析 SELECTED
while IFS='|' read -r ID TYPE TARGET CMD; do
  [ -z "$ID" ] && continue
  if [ "$TYPE" = "manual" ]; then
    if [ "$FORCE_MANUAL" -ne 1 ]; then
      echo "SKIP: $ID (manual; needs --force-manual)"
      continue
    fi
    echo "ACK: $ID (manual; review only, no fs change)"
    APPLIED=$((APPLIED + 1))
    continue
  fi

  PATCH_FILE="$SNAPSHOT_DIR/$ID.patch"
  if [ ! -f "$PATCH_FILE" ]; then
    # 部分场景 patch 可能带 rule suffix (e.g. <id>.R1.patch)
    PATCH_FILE=$(find "$SNAPSHOT_DIR" -maxdepth 1 -name "$ID.*.patch" -print 2>/dev/null | head -1 || true)
  fi
  if [ -z "$PATCH_FILE" ] || [ ! -f "$PATCH_FILE" ]; then
    echo "ERROR: patch file missing for $ID" >&2
    FAILED=1
    break
  fi

  if ! git apply --check "$PATCH_FILE" >/dev/null 2>&1; then
    echo "ERROR: git apply --check failed for $ID" >&2
    FAILED=1
    break
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "DRY-RUN OK: $ID would apply ($PATCH_FILE)"
    continue
  fi

  if ! git apply "$PATCH_FILE" >/dev/null 2>&1; then
    echo "ERROR: git apply failed for $ID" >&2
    FAILED=1
    break
  fi

  echo "APPLIED: $ID → $TARGET"
  APPLIED=$((APPLIED + 1))
done <<EOF
$SELECTED
EOF

if [ "$FAILED" -ne 0 ]; then
  rollback
  exit 1
fi

# 成功: pop stash 恢复 working tree (用户原本就有的改动)
if [ "$STASH_CREATED" -eq 1 ] && [ "$DRY_RUN" -eq 0 ]; then
  ref=$(git stash list 2>/dev/null | grep -F "$STASH_MSG" | head -1 | awk -F: '{print $1}')
  if [ -n "$ref" ]; then
    git stash pop "$ref" >/dev/null 2>&1 || true
  fi
fi

echo "DONE: applied=$APPLIED dry_run=$DRY_RUN"
exit 0
