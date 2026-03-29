#!/usr/bin/env bash
# install-dev-tools.sh
# 自动安装开发工具，跨平台 fallback 到预编译二进制

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
TOOLS_DIR="$REPO_ROOT/.tools/bin"
mkdir -p "$TOOLS_DIR"

OS="$(uname -s)"
ARCH="$(uname -m)"

# 版本锁定（与 Makefile 同步）
RUFF_VERSION="0.15.7"
MYPY_VERSION="1.15.0"
SHELLCHECK_VERSION="0.10.0"
SHFMT_VERSION="3.9.0"

echo "==> 检查 bun"
if ! command -v bun >/dev/null 2>&1; then
  echo "  未找到 bun，正在安装..."
  if [ "$OS" = "Darwin" ] || [ "$OS" = "Linux" ]; then
    curl -fsSL https://bun.sh/install | bash
    export PATH="$HOME/.bun/bin:$PATH"
    echo "  ✓ bun 已安装到 ~/.bun/bin/bun"
  else
    echo "  ⚠️  不支持的操作系统，请手动安装: https://bun.sh"
    exit 1
  fi
else
  echo "  ✓ bun 已安装: $(bun --version)"
fi

echo ""
echo "==> 检查 lint 工具"

# shellcheck
if ! command -v shellcheck >/dev/null 2>&1 && [ ! -f "$TOOLS_DIR/shellcheck" ]; then
  echo "  安装 shellcheck $SHELLCHECK_VERSION..."
  if [ "$OS" = "Darwin" ]; then
    URL="https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/shellcheck-v${SHELLCHECK_VERSION}.darwin.x86_64.tar.xz"
    curl -sL "$URL" | tar xJ -C /tmp
    cp "/tmp/shellcheck-v${SHELLCHECK_VERSION}/shellcheck" "$TOOLS_DIR/"
    rm -rf "/tmp/shellcheck-v${SHELLCHECK_VERSION}"
  elif [ "$OS" = "Linux" ]; then
    URL="https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/shellcheck-v${SHELLCHECK_VERSION}.linux.x86_64.tar.xz"
    curl -sL "$URL" | tar xJ -C /tmp
    cp "/tmp/shellcheck-v${SHELLCHECK_VERSION}/shellcheck" "$TOOLS_DIR/"
    rm -rf "/tmp/shellcheck-v${SHELLCHECK_VERSION}"
  fi
  echo "  ✓ shellcheck 已安装到 $TOOLS_DIR/shellcheck"
else
  echo "  ✓ shellcheck 已存在"
fi

# shfmt
if ! command -v shfmt >/dev/null 2>&1 && [ ! -f "$TOOLS_DIR/shfmt" ]; then
  echo "  安装 shfmt $SHFMT_VERSION..."
  if [ "$OS" = "Darwin" ]; then
    URL="https://github.com/mvdan/sh/releases/download/v${SHFMT_VERSION}/shfmt_v${SHFMT_VERSION}_darwin_amd64"
  elif [ "$OS" = "Linux" ]; then
    URL="https://github.com/mvdan/sh/releases/download/v${SHFMT_VERSION}/shfmt_v${SHFMT_VERSION}_linux_amd64"
  fi
  curl -sL "$URL" -o "$TOOLS_DIR/shfmt"
  chmod +x "$TOOLS_DIR/shfmt"
  echo "  ✓ shfmt 已安装到 $TOOLS_DIR/shfmt"
else
  echo "  ✓ shfmt 已存在"
fi

# ruff + mypy
if ! command -v ruff >/dev/null 2>&1 || ! command -v mypy >/dev/null 2>&1; then
  echo "  安装 ruff $RUFF_VERSION + mypy $MYPY_VERSION..."
  if pip3 install --user --break-system-packages "ruff==$RUFF_VERSION" "mypy==$MYPY_VERSION" 2>/dev/null; then
    echo "  ✓ ruff + mypy 已安装"
  elif pip3 install --user "ruff==$RUFF_VERSION" "mypy==$MYPY_VERSION" 2>/dev/null; then
    echo "  ✓ ruff + mypy 已安装"
  else
    echo "  ⚠️  pip 安装失败，请手动安装: pip3 install ruff mypy"
  fi
else
  echo "  ✓ ruff + mypy 已存在"
fi

echo ""
echo "==> 安装完成"
echo ""
echo "提示: 将以下路径加入 PATH（可选）："
echo "  export PATH=\"$TOOLS_DIR:\$HOME/.bun/bin:\$HOME/Library/Python/3.14/bin:\$PATH\""
