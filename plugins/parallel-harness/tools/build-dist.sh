#!/usr/bin/env bash
# parallel-harness 构建脚本
# 将源码打包到 dist/parallel-harness/

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_DIR/../.." && pwd)"
DIST_DIR="$REPO_ROOT/dist/parallel-harness"

echo "=== parallel-harness 构建开始 ==="
echo "插件目录: $PLUGIN_DIR"
echo "输出目录: $DIST_DIR"

# 1. 清理旧产物
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# 2. TypeScript 类型检查
echo "--- TypeScript 类型检查 ---"
cd "$PLUGIN_DIR"
npx tsc --noEmit
echo "✓ 类型检查通过"

# 3. 运行测试
echo "--- 运行测试 ---"
bun test
echo "✓ 测试通过"

# 4. 复制核心文件
echo "--- 复制核心文件 ---"

# 插件元数据
cp -r "$PLUGIN_DIR/.claude-plugin" "$DIST_DIR/.claude-plugin"

# Hooks
cp -r "$PLUGIN_DIR/hooks" "$DIST_DIR/hooks"

# Skills
cp -r "$PLUGIN_DIR/skills" "$DIST_DIR/skills"

# Runtime TypeScript 模块
mkdir -p "$DIST_DIR/runtime"
for module in schemas orchestrator scheduler models session verifiers control-plane ci; do
  if [ -d "$PLUGIN_DIR/runtime/$module" ]; then
    cp -r "$PLUGIN_DIR/runtime/$module" "$DIST_DIR/runtime/$module"
  fi
done

# README（仅英文版）
cp "$PLUGIN_DIR/README.md" "$DIST_DIR/README.md"

# 5. 校验产物
echo "--- 校验构建产物 ---"

# 检查必要文件
for f in .claude-plugin/plugin.json hooks/hooks.json skills/parallel-plan/SKILL.md README.md; do
  if [ ! -f "$DIST_DIR/$f" ]; then
    echo "✗ 缺少: $f"
    exit 1
  fi
done

# 检查 runtime 模块
MODULE_COUNT=$(find "$DIST_DIR/runtime" -name "*.ts" | wc -l | tr -d ' ')
if [ "$MODULE_COUNT" -lt 20 ]; then
  echo "✗ runtime 模块数不足: $MODULE_COUNT (期望 >= 20)"
  exit 1
fi

# 禁止包含测试和文档
for forbidden in tests docs package.json tsconfig.json node_modules; do
  if [ -e "$DIST_DIR/$forbidden" ]; then
    echo "✗ 产物中不应包含: $forbidden"
    exit 1
  fi
done

echo "✓ 产物校验通过"
echo ""
echo "=== parallel-harness 构建完成 ==="
echo "模块数: $MODULE_COUNT"
echo "产物目录: $DIST_DIR"
