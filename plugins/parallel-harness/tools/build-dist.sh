#!/usr/bin/env bash
# parallel-harness 构建脚本
# 用途：类型检查 → 运行测试 → 生成 dist 产物 → 更新 BUILD_MANIFEST
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PLUGIN_DIR"

echo "=== parallel-harness 构建流程 ==="
echo "插件目录: $PLUGIN_DIR"
echo ""

# 1. 安装依赖
echo "--- 步骤 1/5: 安装依赖 ---"
bun install --frozen-lockfile 2>/dev/null || bun install
echo "依赖安装完成"

# 2. 类型检查
echo ""
echo "--- 步骤 2/5: TypeScript 类型检查 ---"
bunx tsc --noEmit
echo "类型检查通过"

# 3. 运行测试
echo ""
echo "--- 步骤 3/5: 运行测试 ---"
TEST_OUTPUT=$(bun test 2>&1) || true
echo "$TEST_OUTPUT" | tail -5

# 提取测试计数
PASS_COUNT=$(echo "$TEST_OUTPUT" | grep -oE '[0-9]+ pass' | grep -oE '[0-9]+' || echo "0")
FAIL_COUNT=$(echo "$TEST_OUTPUT" | grep -oE '[0-9]+ fail' | grep -oE '[0-9]+' || echo "0")
EXPECT_COUNT=$(echo "$TEST_OUTPUT" | grep -oE '[0-9]+ expect' | grep -oE '[0-9]+' || echo "0")

if [ "$FAIL_COUNT" != "0" ]; then
  echo "警告: ${FAIL_COUNT} 个测试失败"
fi

# 4. 构建 dist
echo ""
echo "--- 步骤 4/5: 构建 dist 产物 ---"
rm -rf dist
mkdir -p dist

# 复制运行时源码
cp -r runtime dist/
# 复制配置
cp -r config dist/
# 复制插件元数据
cp -r .claude-plugin dist/
# 复制文档
cp -r docs dist/
cp -r skills dist/
# 复制元文件
cp package.json dist/
cp tsconfig.json dist/
cp README.md dist/
cp README.zh.md dist/
cp CLAUDE.md dist/

echo "dist 产物已生成: dist/"

# 5. 更新 BUILD_MANIFEST
echo ""
echo "--- 步骤 5/5: 更新 BUILD_MANIFEST ---"
VERSION=$(grep '"version"' package.json | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
SCHEMA_VERSION=$(grep 'SCHEMA_VERSION' runtime/schemas/ga-schemas.ts | grep -oE '"[0-9]+\.[0-9]+\.[0-9]+"' | tr -d '"' || echo "1.0.0")
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILT_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# 计算模块列表
MODULES=$(find runtime -mindepth 1 -maxdepth 1 -type d | sort | while read -r dir; do
  echo "    \"${dir}\""
done | paste -sd ',' -)

cat > BUILD_MANIFEST.json << EOFMANIFEST
{
  "name": "parallel-harness",
  "version": "${VERSION}",
  "schema_version": "${SCHEMA_VERSION}",
  "built_at": "${BUILT_AT}",
  "git_branch": "${GIT_BRANCH}",
  "git_commit": "${GIT_COMMIT}",
  "test_count": ${PASS_COUNT},
  "test_failures": ${FAIL_COUNT},
  "expect_count": ${EXPECT_COUNT},
  "modules": [
${MODULES}
  ]
}
EOFMANIFEST

echo "BUILD_MANIFEST.json 已更新"
echo ""
echo "=== 构建完成 ==="
echo "  版本: ${VERSION}"
echo "  测试: ${PASS_COUNT} pass / ${FAIL_COUNT} fail"
echo "  Git: ${GIT_BRANCH}@${GIT_COMMIT}"
