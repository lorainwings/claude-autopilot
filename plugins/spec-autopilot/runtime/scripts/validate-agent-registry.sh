#!/usr/bin/env bash
# validate-agent-registry.sh
# CODE-REF: plugins/spec-autopilot/skills/autopilot-dispatch/SKILL.md
# Purpose: 校验 Sub-Agent 名称是否合法（已注册自定义 agent ∪ 内置 agent）
#          并检测输入中是否残留未解析的模板占位符（{{...}}, config.*, config.phases.*）
#
# Usage:
#   bash validate-agent-registry.sh <agent_name>
#
# Exit codes:
#   0 — agent name is valid (registered custom or builtin)
#   1 — agent name unknown OR contains unresolved template placeholders OR empty
#
# Output:
#   stderr: human-readable error messages
#   stdout: success JSON `{"status":"ok","agent":"<name>","source":"builtin|custom"}` on success
#
# 依赖：
#   - 自定义 agent 扫描自 $AUTOPILOT_PROJECT_ROOT/.claude/agents 与 $HOME/.claude/agents
#   - 内置 agent 白名单：general-purpose, Explore, Plan
#
# 设计意图：在 dispatch 前作为 fail-fast 校验，防止模板变量未替换即派发，
#          导致 LLM 从 description 启发式选择 agent，丢失预设身份。

set -uo pipefail

AGENT_NAME="${1:-}"

# ---- 1. 空输入 fail-fast ----
if [ -z "$AGENT_NAME" ]; then
  echo "ERROR: agent name is empty (validate-agent-registry expects 1 argument)" >&2
  exit 1
fi

# ---- 2. 模板未替换检测 ----
# 命中以下任一即 block：
#   - 含 {{ 或 }} （未渲染的 mustache/handlebars 占位符）
#   - 以 config. 开头或含 config.phases. （YAML 配置路径泄漏）
if echo "$AGENT_NAME" | grep -qE '\{\{|\}\}'; then
  echo "ERROR: unresolved template placeholder detected in agent name: '$AGENT_NAME' (contains '{{' or '}}')" >&2
  echo "       dispatch must replace placeholder with the actual registered agent name before invoking Task." >&2
  exit 1
fi

if echo "$AGENT_NAME" | grep -qE '^config\.|config\.phases\.'; then
  echo "ERROR: unresolved config path detected in agent name: '$AGENT_NAME'" >&2
  echo "       dispatch must resolve 'config.phases.<phase>.agent' to the actual agent name from autopilot.config.yaml." >&2
  exit 1
fi

# ---- 3. 内置 agent 白名单 ----
case "$AGENT_NAME" in
  general-purpose | Explore | Plan)
    printf '{"status":"ok","agent":"%s","source":"builtin"}\n' "$AGENT_NAME"
    exit 0
    ;;
esac

# ---- 4. 扫描自定义 agent 注册表 ----
# 项目根：优先 AUTOPILOT_PROJECT_ROOT，再退回 git 顶层，再退回 PWD
PROJECT_ROOT="${AUTOPILOT_PROJECT_ROOT:-}"
if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

REGISTERED=()

# 项目级 agents 目录
if [ -d "$PROJECT_ROOT/.claude/agents" ]; then
  while IFS= read -r f; do
    base=$(basename "$f" .md)
    REGISTERED+=("$base")
  done < <(find "$PROJECT_ROOT/.claude/agents" -maxdepth 2 -type f -name '*.md' 2>/dev/null)
fi

# 用户级 agents 目录
if [ -n "${HOME:-}" ] && [ -d "$HOME/.claude/agents" ]; then
  while IFS= read -r f; do
    base=$(basename "$f" .md)
    REGISTERED+=("$base")
  done < <(find "$HOME/.claude/agents" -maxdepth 2 -type f -name '*.md' 2>/dev/null)
fi

# ---- 5. 命中即通过 ----
for name in "${REGISTERED[@]:-}"; do
  if [ "$name" = "$AGENT_NAME" ]; then
    printf '{"status":"ok","agent":"%s","source":"custom"}\n' "$AGENT_NAME"
    exit 0
  fi
done

# ---- 6. 未命中 → fail-fast ----
echo "ERROR: agent '$AGENT_NAME' is not registered." >&2
echo "       Searched: $PROJECT_ROOT/.claude/agents, \$HOME/.claude/agents" >&2
echo "       Builtin allowed: general-purpose, Explore, Plan" >&2
if [ ${#REGISTERED[@]} -gt 0 ]; then
  echo "       Registered custom agents: ${REGISTERED[*]}" >&2
else
  echo "       (no custom agents registered)" >&2
fi
exit 1
