#!/usr/bin/env bash
# parallel-harness 构建脚本
# 用途：生成 dist 产物。测试和类型检查由 CI / Makefile 独立保证。
# 选项：--full  在构建前执行 typecheck + test（开发者本地验证用）
set -euo pipefail

PLUGIN_NAME="parallel-harness"
PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_DIR/../.." && pwd)"
DIST_DIR="$REPO_ROOT/dist/$PLUGIN_NAME"

cd "$PLUGIN_DIR"

# git hook 会注入仓库局部 GIT_* 环境；测试里会创建临时仓库，必须先清理这些变量。
while IFS= read -r git_var; do
  unset "$git_var"
done < <(git rev-parse --local-env-vars)

FULL_MODE=false
for arg in "$@"; do
  case "$arg" in
    --full) FULL_MODE=true ;;
  esac
done

echo "=== parallel-harness 构建流程 ==="
echo "插件目录: $PLUGIN_DIR"
echo "dist 目标: $DIST_DIR"
echo ""

# 1. 安装依赖
echo "--- 步骤 1/3: 安装依赖 ---"
bun install --frozen-lockfile 2>/dev/null || bun install
echo "依赖安装完成"

if [ "$FULL_MODE" = "true" ]; then
  echo ""
  echo "--- [full] TypeScript 类型检查 ---"
  bunx tsc --noEmit
  echo "类型检查通过"

  echo ""
  echo "--- [full] 运行测试 ---"
  bun test --timeout 15000
  echo "测试通过"
fi

# 2. 构建 dist（输出到仓库级 dist/parallel-harness/，与 dist/spec-autopilot/ 结构对齐）
echo ""
echo "--- 步骤 2/3: 构建 dist 产物 → $DIST_DIR ---"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# 复制插件元数据（市场安装所需最小集）
cp -r .claude-plugin "$DIST_DIR/"
cp -r runtime       "$DIST_DIR/"
cp -r skills        "$DIST_DIR/"
cp -r config        "$DIST_DIR/"

# CLAUDE.md — 裁剪 dev-only 段落（如有标记）
if grep -q "<!-- DEV-ONLY-BEGIN -->" CLAUDE.md 2>/dev/null; then
  sed '/<!-- DEV-ONLY-BEGIN -->/,/<!-- DEV-ONLY-END -->/d' CLAUDE.md > "$DIST_DIR/CLAUDE.md"
else
  cp CLAUDE.md "$DIST_DIR/"
fi

# 校验：dist 不包含 node_modules / tests / tools
for forbidden in node_modules tests tools bun.lock "*.tsbuildinfo"; do
  if compgen -G "$DIST_DIR/$forbidden" > /dev/null 2>&1; then
    echo "ERROR: dist 包含不应存在的路径: $forbidden"
    exit 1
  fi
done

DIST_SIZE=$(du -sh "$DIST_DIR" 2>/dev/null | cut -f1)
echo "dist built: $DIST_SIZE"

# 3. 更新 BUILD_MANIFEST（写到插件目录，被 .gitignore 忽略）
echo ""
echo "--- 步骤 3/3: 更新 BUILD_MANIFEST ---"
VERSION=$(grep '"version"' package.json | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
SCHEMA_VERSION=$(grep 'SCHEMA_VERSION' runtime/schemas/ga-schemas.ts | grep -oE '"[0-9]+\.[0-9]+\.[0-9]+"' | tr -d '"' 2>/dev/null | head -1 || echo "1.0.0")
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILT_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

MODULES=$(find runtime -mindepth 1 -maxdepth 1 -type d | sort | sed 's|^|    "|' | sed 's|$|"|' | paste -sd ',' -)

cat > BUILD_MANIFEST.json << EOFMANIFEST
{
  "name": "parallel-harness",
  "version": "${VERSION}",
  "schema_version": "${SCHEMA_VERSION}",
  "built_at": "${BUILT_AT}",
  "git_branch": "${GIT_BRANCH}",
  "git_commit": "${GIT_COMMIT}",
  "modules": [
${MODULES}
  ]
}
EOFMANIFEST

echo "BUILD_MANIFEST.json 已更新（本地，不跟踪）"
echo ""
echo "=== 构建完成 ==="
echo "  版本: ${VERSION}"
echo "  Git:  ${GIT_BRANCH}@${GIT_COMMIT}"
echo "  dist: $DIST_DIR"
