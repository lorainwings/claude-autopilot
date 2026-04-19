#!/usr/bin/env bash
# post-task-validator.sh
# Hook: PostToolUse(Task) — Unified entry point (v4.0 + WS-E governance)
# Purpose: Single orchestrator that runs all 5+1 PostToolUse(Task) validations
#          in one python3 process, reducing fork overhead from ~420ms to ~100ms.
#
# Replaces 5 separate hooks:
#   1. validate-json-envelope.sh    → JSON structure validation
#   2. anti-rationalization-check.sh → Skip pattern detection
#   3. code-constraint-check.sh     → Code constraint verification
#   4. parallel-merge-guard.sh      → Worktree merge validation
#   5. validate-decision-format.sh  → Decision format validation
# Plus (WS-E governance):
#   6. Agent priority & artifact boundary validation
#
# Output: PostToolUse `decision: "block"` with `reason` on first validation failure.

# --- Common preamble: stdin read, SCRIPT_DIR, _common.sh, Layer 0 bypass ---
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_hook_preamble.sh"

# --- Fast bypass Layer 1: prompt phase marker detection ---
# 标准 phase marker 命中 → 直接走完整校验
# 未命中但属于 Phase 6 advisory 路径（code review / quality scan）→ 走轻量信封校验
if ! has_phase_marker; then
  # Phase 6 路径 B/C advisory 白名单：当 prompt 引用以下产物时强制轻量信封校验
  # 设计意图：advisory agent 不含 autopilot-phase marker（无法走完整 5+1 校验），
  # 但其结构化输出（findings[]）是 Phase 7 archive readiness 的输入，
  # 必须保证返回标准 status/summary 字段，否则 archive readiness 才发现就太晚了。
  if echo "$STDIN_DATA" | grep -qE '(code-review|quality-scan|phase6-review|review-findings)\.json'; then
    require_python3 || exit 0
    # 通过 env 变量传入 STDIN_DATA，避免 heredoc 与管道重定向冲突
    AUTOPILOT_ADVISORY_PAYLOAD="$STDIN_DATA" python3 <<'PY'
import json, os, sys
data = os.environ.get('AUTOPILOT_ADVISORY_PAYLOAD', '')
try:
    payload = json.loads(data)
except Exception:
    sys.exit(0)
tu = payload.get('tool_response') or {}
if isinstance(tu, dict):
    content = json.dumps(tu, ensure_ascii=False)
elif isinstance(tu, str):
    content = tu
else:
    content = ''

def first_json_object(s):
    for i, c in enumerate(s):
        if c != '{':
            continue
        depth = 0
        in_str = False
        esc = False
        for j in range(i, len(s)):
            ch = s[j]
            if esc:
                esc = False
                continue
            if ch == '\\':
                esc = True
                continue
            if ch == '"':
                in_str = not in_str
                continue
            if in_str:
                continue
            if ch == '{':
                depth += 1
            elif ch == '}':
                depth -= 1
                if depth == 0:
                    return s[i:j+1]
    return None

blob = first_json_object(content)
if not blob:
    print(json.dumps({
        'decision': 'block',
        'reason': 'Phase 6 advisory 路径 (code review / quality scan) 子 Agent 必须返回 JSON 信封（未找到 { ... } 结构）。'
    }))
    sys.exit(0)
try:
    env = json.loads(blob)
except Exception:
    print(json.dumps({
        'decision': 'block',
        'reason': 'Phase 6 advisory envelope 解析失败，请检查 JSON 格式。'
    }))
    sys.exit(0)
if 'status' not in env:
    print(json.dumps({
        'decision': 'block',
        'reason': 'Phase 6 advisory envelope 缺失 "status" 字段。'
    }))
    sys.exit(0)
if env.get('status') not in ('ok', 'warning', 'blocked', 'failed'):
    print(json.dumps({
        'decision': 'block',
        'reason': f'Phase 6 advisory envelope status 必须为 ok/warning/blocked/failed (got: {env.get("status")!r}).'
    }))
    sys.exit(0)
if not env.get('summary'):
    print(json.dumps({
        'decision': 'block',
        'reason': 'Phase 6 advisory envelope 缺失 "summary" 字段。'
    }))
    sys.exit(0)
if 'findings' not in env or not isinstance(env.get('findings'), list):
    print(json.dumps({
        'decision': 'block',
        'reason': 'Phase 6 advisory envelope 必须包含 "findings": [] 数组（可为空）。'
    }))
    sys.exit(0)
PY
    exit 0
  fi
  exit 0
fi

# --- v5.1 FIX: Background agents must undergo validation ---
# Previously: `is_background_agent && exit 0` — completely bypassed all validation.
# Now: Background tasks are validated (JSON envelope + anti-rationalization) when they
# complete, since PostToolUse fires after the agent produces output.

# --- Dependency check: python3 required (Fail-Closed) ---
# require_python3 outputs {"decision":"block",...} to stdout when python3 is missing,
# then returns 1. The block JSON is consumed by Claude Code hook infrastructure.
# Without python3, all 5 validators would be silently skipped — this MUST block.
require_python3 || exit 0

# --- Single python3 call for all validations ---
echo "$STDIN_DATA" | python3 "$SCRIPT_DIR/_post_task_validator.py"

exit 0
