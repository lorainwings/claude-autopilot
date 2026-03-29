#!/usr/bin/env bash
# run-spec-autopilot-lint.sh
# spec-autopilot 统一 lint 入口。
# 被 Makefile `make lint`、pre-commit hook、GitHub Actions 共同调用。
# 单点维护检查范围、工具命令、失败语义，避免多处漂移。
#
# 用法:
#   bash scripts/run-spec-autopilot-lint.sh [--files-from-stdin]
#
#   无参数: 对 plugins/spec-autopilot/runtime/scripts/ 一级目录全量 lint
#   --files-from-stdin: 从 stdin 读取文件列表（每行一个），只 lint 这些文件
#                       （用于 pre-commit staged quick-check）
#
# 退出码: 0 = 全部通过, 1 = 有 lint 问题或缺工具

set -uo pipefail

SA_DIR="plugins/spec-autopilot"
SA_SCRIPTS="$SA_DIR/runtime/scripts"
SA_PYPROJECT="$SA_DIR/pyproject.toml"
FAILED=0

# ── 工具检查 helper ──
_require_tool() {
  local tool="$1"
  local install_hint="$2"
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "❌ $tool not found. Install: $install_hint"
    FAILED=1
    return 1
  fi
  return 0
}

# ── 解析参数 ──
FILES_MODE="full"
SH_FILES=""
PY_FILES=""

if [ "${1:-}" = "--files-from-stdin" ]; then
  FILES_MODE="stdin"
  ALL_FILES=$(cat)
  SH_FILES=$(echo "$ALL_FILES" | grep '\.sh$' || true)
  PY_FILES=$(echo "$ALL_FILES" | grep '\.py$' || true)
fi

# ── 全量模式: 收集文件 ──
if [ "$FILES_MODE" = "full" ]; then
  if [ ! -d "$SA_SCRIPTS" ]; then
    echo "ℹ️  $SA_SCRIPTS not found — skipping spec-autopilot lint"
    exit 0
  fi
  SH_FILES=$(find "$SA_SCRIPTS" -maxdepth 1 -name '*.sh' 2>/dev/null || true)
  PY_FILES=$(find "$SA_SCRIPTS" -maxdepth 1 -name '*.py' 2>/dev/null || true)
fi

# ── shellcheck ──
if [ -n "$SH_FILES" ]; then
  echo "── shellcheck ──"
  if _require_tool shellcheck "brew install shellcheck"; then
    echo "$SH_FILES" | tr '\n' '\0' | xargs -0 shellcheck --severity=warning || FAILED=1
  fi
fi

# ── shfmt ──
if [ -n "$SH_FILES" ]; then
  echo "── shfmt ──"
  if _require_tool shfmt "brew install shfmt"; then
    echo "$SH_FILES" | tr '\n' '\0' | xargs -0 shfmt -d -i 2 -ci || FAILED=1
  fi
fi

# ── ruff check ──
if [ -n "$PY_FILES" ]; then
  echo "── ruff check ──"
  if _require_tool ruff "pip install ruff"; then
    echo "$PY_FILES" | tr '\n' '\0' | xargs -0 ruff check --config "$SA_PYPROJECT" || FAILED=1
  fi
fi

# ── ruff format ──
if [ -n "$PY_FILES" ]; then
  echo "── ruff format ──"
  if _require_tool ruff "pip install ruff"; then
    echo "$PY_FILES" | tr '\n' '\0' | xargs -0 ruff format --check --config "$SA_PYPROJECT" || FAILED=1
  fi
fi

# ── mypy ──
if [ -n "$PY_FILES" ]; then
  echo "── mypy ──"
  if _require_tool mypy "pip install mypy"; then
    echo "$PY_FILES" | tr '\n' '\0' | xargs -0 mypy --config-file "$SA_PYPROJECT" || FAILED=1
  fi
fi

exit "$FAILED"
