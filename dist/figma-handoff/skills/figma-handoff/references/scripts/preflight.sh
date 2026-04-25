#!/usr/bin/env bash
# figma-handoff preflight 探测脚本
# 用途: 输出 ready / degraded / blocking 三段式 JSON 契约
# 用法: bash preflight.sh [project-root] [target-stack]
#       target-stack 形如 vue3+element-plus / react+antd / react+tailwind
# 输出: stdout 写 JSON; 同时落盘 .cache/figma-handoff/preflight.json
set -euo pipefail

PROJECT_ROOT="${1:-$(pwd)}"
TARGET_STACK="${2:-}"
CACHE_DIR="$PROJECT_ROOT/.cache/figma-handoff"
mkdir -p "$CACHE_DIR"

# ---------- helpers ----------
ready=()
degraded=()
blocking=()

json_quote() {
  printf '%s' "$1" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"%s"' "$1"
}

add_ready() { ready+=("$(json_quote "$1")"); }
add_degraded() {
  local cap="$1" reason="$2" fb="$3"
  degraded+=("{\"capability\":$(json_quote "$cap"),\"reason\":$(json_quote "$reason"),\"fallback\":$(json_quote "$fb")}")
}
add_blocking() {
  local cap="$1" fix="$2"
  blocking+=("{\"capability\":$(json_quote "$cap"),\"fix\":$(json_quote "$fix")}")
}

has_dep() {
  # 在 package.json 的 dependencies / devDependencies / peerDependencies 里查找指定包
  local pkg="$1" pjson="$PROJECT_ROOT/package.json"
  [ -f "$pjson" ] || return 1
  python3 - "$pjson" "$pkg" <<'PY' 2>/dev/null
import json, sys
p, pkg = sys.argv[1], sys.argv[2]
try:
    d = json.load(open(p))
    for k in ("dependencies","devDependencies","peerDependencies"):
        if pkg in (d.get(k) or {}): sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
PY
}

can_resolve_dep() {
  # 依赖 ready 必须能从目标项目实际解析;仅 package.json 声明但未安装不算 ready。
  local pkg="$1" pjson="$PROJECT_ROOT/package.json"
  [ -f "$pjson" ] || return 1
  command -v node >/dev/null 2>&1 || return 1
  node - "$pjson" "$pkg" <<'NODE' >/dev/null 2>&1
const { createRequire } = require("node:module");
const fs = require("node:fs");
const path = require("node:path");
const [, , packageJsonPath, packageName] = process.argv;
try {
  const projectRoot = fs.realpathSync(path.dirname(packageJsonPath));
  const resolved = createRequire(packageJsonPath).resolve(packageName);
  const resolvedReal = fs.realpathSync(resolved);
  const expectedPrefix = fs.realpathSync(path.join(projectRoot, "node_modules")) + path.sep;
  if (!resolvedReal.startsWith(expectedPrefix)) process.exit(1);
  process.exit(0);
} catch {
  process.exit(1);
}
NODE
}

# ---------- 1. package manager ----------
pm="npm"
if   [ -f "$PROJECT_ROOT/bun.lock" ] || [ -f "$PROJECT_ROOT/bun.lockb" ]; then pm="bun"
elif [ -f "$PROJECT_ROOT/pnpm-lock.yaml" ];                                then pm="pnpm"
elif [ -f "$PROJECT_ROOT/yarn.lock" ];                                     then pm="yarn"
elif [ -f "$PROJECT_ROOT/package-lock.json" ];                             then pm="npm"
fi
if command -v corepack >/dev/null 2>&1 && [ -f "$PROJECT_ROOT/package.json" ]; then
  pkg_pm="$(python3 - "$PROJECT_ROOT/package.json" <<'PY' 2>/dev/null || true
import json, sys
try:
    value = json.load(open(sys.argv[1])).get("packageManager", "")
    print(value.split("@", 1)[0])
except Exception:
    pass
PY
)"
  case "$pkg_pm" in
    bun|pnpm|yarn|npm) pm="$pkg_pm" ;;
  esac
fi

# ---------- 2. framework ----------
framework="unknown"
if [ -n "$TARGET_STACK" ]; then
  case "$TARGET_STACK" in
    *vue*)     framework="vue" ;;
    *react*)   framework="react" ;;
    *svelte*)  framework="svelte" ;;
    *angular*) framework="angular" ;;
  esac
fi
if [ "$framework" = "unknown" ]; then
  if   has_dep "vue";          then framework="vue"
  elif has_dep "react";        then framework="react"
  elif has_dep "@angular/core"; then framework="angular"
  elif has_dep "svelte";       then framework="svelte"
  fi
fi
if [ "$framework" = "unknown" ]; then
  vue_count=$(find "$PROJECT_ROOT" \( -path "$PROJECT_ROOT/node_modules" -o -path "$PROJECT_ROOT/.git" -o -path "$PROJECT_ROOT/dist" \) -prune -o -name '*.vue' -print 2>/dev/null | wc -l | tr -d ' ')
  react_count=$(find "$PROJECT_ROOT" \( -path "$PROJECT_ROOT/node_modules" -o -path "$PROJECT_ROOT/.git" -o -path "$PROJECT_ROOT/dist" \) -prune -o \( -name '*.tsx' -o -name '*.jsx' \) -print 2>/dev/null | wc -l | tr -d ' ')
  if [ "${vue_count:-0}" -gt "${react_count:-0}" ] && [ "${vue_count:-0}" -gt 0 ]; then
    framework="vue"
  elif [ "${react_count:-0}" -gt 0 ]; then
    framework="react"
  fi
fi

# ---------- 3. component library ----------
lib="unknown"
if   has_dep "element-plus";       then lib="element-plus"
elif has_dep "vant";               then lib="vant"
elif has_dep "naive-ui";           then lib="naive"
elif has_dep "@arco-design/web-vue"; then lib="arco"
elif has_dep "tdesign-vue-next";   then lib="tdesign"
elif has_dep "primevue";           then lib="primevue"
elif has_dep "antd";               then lib="antd"
elif has_dep "@mui/material";      then lib="mui"
elif has_dep "@chakra-ui/react";   then lib="chakra"
elif has_dep "@mantine/core";      then lib="mantine"
elif [ -f "$PROJECT_ROOT/components.json" ]; then lib="shadcn"
fi
if [ "$lib" = "unknown" ] && [ -n "$TARGET_STACK" ]; then
  case "$TARGET_STACK" in
    *element-plus*) lib="element-plus" ;;
    *vant*)         lib="vant" ;;
    *naive*)        lib="naive" ;;
    *arco*)         lib="arco" ;;
    *tdesign*)      lib="tdesign" ;;
    *primevue*)     lib="primevue" ;;
    *antd*|*ant-design*) lib="antd" ;;
    *mui*)          lib="mui" ;;
    *chakra*)       lib="chakra" ;;
    *mantine*)      lib="mantine" ;;
    *shadcn*)       lib="shadcn" ;;
    *tailwind*)     lib="tailwind" ;;
  esac
fi
if [ "$lib" = "unknown" ]; then
  lib="tailwind"
fi

# ---------- 4. capability checks ----------
# figma MCP — shell preflight 无法 introspect Agent 工具层。
# 官方 Remote/Desktop MCP 是否可用必须由 Agent 工具列表最终确认; 这里仅探测本地能力和显式环境变量。
figma_mcp_mode="${FIGMA_MCP_MODE:-unknown}"
case "$figma_mcp_mode" in
  remote|desktop|local|unknown) ;;
  "")
    figma_mcp_mode="unknown"
    ;;
  *)
    add_degraded "figma-mcp-mode" "FIGMA_MCP_MODE=$figma_mcp_mode 非预期" "unknown"
    figma_mcp_mode="unknown"
    ;;
esac

case "${FIGMA_MCP_READY:-}" in
  1|true|TRUE|yes|YES)
    add_ready "figma-mcp"
    ;;
  *)
    if command -v figma-developer-mcp >/dev/null 2>&1; then
      if [ "$figma_mcp_mode" = "unknown" ]; then
        figma_mcp_mode="local"
      fi
      add_ready "figma-mcp"
    else
      case "$figma_mcp_mode" in
        remote|desktop)
          add_degraded "figma-mcp" "shell 无法 introspect Agent 工具层; 官方 ${figma_mcp_mode} MCP 需由 Agent 工具列表最终确认" "manual-tool-check"
          ;;
        local)
          add_degraded "figma-mcp" "FIGMA_MCP_MODE=local 但未检测到 figma-developer-mcp; 也可能由 Agent 已注册工具提供" "manual-tool-check"
          ;;
        unknown)
          add_degraded "figma-mcp" "shell 无法 introspect Agent 工具层; 请在 Agent 工具层确认 mcp__figma__* 可用" "manual-tool-check"
          ;;
      esac
    fi
    ;;
esac

# chrome-devtools MCP
if command -v chrome-devtools-mcp >/dev/null 2>&1 || [ -n "${CHROME_DEVTOOLS_MCP_READY:-}" ]; then
  add_ready "chrome-devtools-mcp"
else
  add_degraded "chrome-devtools-mcp" "未在本机检测到 MCP server" "playwright-cli"
fi

# playwright
if can_resolve_dep "@playwright/test" || can_resolve_dep "playwright" || command -v playwright >/dev/null 2>&1; then
  add_ready "playwright"
  pw_ready=1
else
  pw_ready=0
fi

# pixelmatch + pngjs
if can_resolve_dep "pixelmatch" && can_resolve_dep "pngjs"; then
  add_ready "pixelmatch"
  pm_ready=1
else
  pm_ready=0
fi

# 视觉 diff 兜底判定: 至少要有一个可用引擎
if [ "$pw_ready" -eq 0 ] && [ "$pm_ready" -eq 0 ]; then
  add_blocking "visual-diff-engine" \
    "$pm add -D @playwright/test && npx playwright install chromium  # 或: $pm add -D pixelmatch pngjs sharp"
fi

# sharp (软依赖)
if can_resolve_dep "sharp"; then
  add_ready "sharp"
else
  add_degraded "sharp" "未安装" "skip-preprocess"
fi

# odiff (可选, 仅高敏模式)
if command -v odiff >/dev/null 2>&1 || can_resolve_dep "odiff-bin"; then
  add_ready "odiff"
fi

# ---------- 5. emit JSON ----------
join() { local IFS=,; echo "$*"; }
out_json=$(cat <<EOF
{
  "ready": [$(join "${ready[@]:-}")],
  "degraded": [$(join "${degraded[@]:-}")],
  "blocking": [$(join "${blocking[@]:-}")],
  "framework": "$framework",
  "componentLibrary": "$lib",
  "packageManager": "$pm",
  "figmaMcpMode": "$figma_mcp_mode"
}
EOF
)

echo "$out_json" | tee "$CACHE_DIR/preflight.json"

# ---------- 6. exit code ----------
# 有 blocking 项 → 退出 2 (caller 应中止主流程)
# 仅 degraded → 退出 0 (主流程继续, 但需打印 fallback 提示)
if [ "${#blocking[@]}" -gt 0 ]; then
  exit 2
fi
exit 0
