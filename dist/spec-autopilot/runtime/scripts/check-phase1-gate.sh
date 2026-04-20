#!/usr/bin/env bash
# check-phase1-gate.sh — Phase 1→2 三重硬校验
#
# Task B10: 在 L1 (TaskCreate blockedBy) + L2 (Hook envelope schema) 之上，
# 校验跨路硬约束，防止未澄清/低置信/不可调和冲突的需求进入 Phase 2。
#
# 三重校验:
#   1. requirements.md 不含 [NEEDS CLARIFICATION: 标记
#   2. verdict.confidence >= --threshold (默认 0.7)
#   3. verdict.conflicts 中无 resolution=="irreconcilable"
#   附加: packet.sha256 必须存在 (依赖 A 阶段产物完整性)
#
# 用法:
#   check-phase1-gate.sh \
#     --requirements <path/to/requirements-analysis.md> \
#     --verdict <path/to/synthesizer-verdict.json> \
#     --packet <path/to/requirement-packet.json> \
#     [--threshold 0.7] \
#     [--config <path/to/autopilot.config.yaml>]
#
# 阈值优先级:
#   --threshold (CLI) > config (phases.requirements.gate.confidence_threshold) > 默认 0.7
#   未传 --config 时自动探测 <git-root>/.claude/autopilot.config.yaml；不存在则回落默认。
#   非法阈值（非 ^[0-9]+(\.[0-9]+)?$）一律 stderr 报错并 exit 2，禁止 silent failure。
#
# 退出码:
#   0  全部通过
#   1  任一校验失败 (信息打到 stderr)
#   2  参数错误 / 文件缺失 / 非法阈值 (调用方使用错误)
#
# 注：与 v1 版 (`post-task-validator.sh` 的 phase1 路径) 互补；
# v1 校验单路 envelope，本脚本校验跨路合约。

set -uo pipefail

REQ_FILE=""
VERDICT_FILE=""
PACKET_FILE=""
THRESHOLD_CLI=""
CONFIG_FILE=""
DEFAULT_THRESHOLD="0.7"

usage() {
  cat >&2 <<EOF
用法: $(basename "$0") --requirements <md> --verdict <json> --packet <json> [--threshold 0.7] [--config <yaml>]
EOF
}

is_valid_threshold() {
  # 严格匹配非负浮点（含整数），禁止 ".5" / "1." / "abc" / "1e2" 等模糊格式
  printf '%s' "$1" | grep -Eq '^[0-9]+(\.[0-9]+)?$'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --requirements)
      REQ_FILE="${2:-}"
      shift 2
      ;;
    --verdict)
      VERDICT_FILE="${2:-}"
      shift 2
      ;;
    --packet)
      PACKET_FILE="${2:-}"
      shift 2
      ;;
    --threshold)
      THRESHOLD_CLI="${2:-}"
      shift 2
      ;;
    --config)
      CONFIG_FILE="${2:-}"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "[GATE-PHASE1] 未知参数: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [ -z "$REQ_FILE" ] || [ -z "$VERDICT_FILE" ] || [ -z "$PACKET_FILE" ]; then
  echo "[GATE-PHASE1] 缺少必填参数" >&2
  usage
  exit 1
fi

# ── 阈值解析: CLI > config > default ──
THRESHOLD_SOURCE="default"
THRESHOLD="$DEFAULT_THRESHOLD"

# 1) 自动探测 config 路径（若未显式传入）
if [ -z "$CONFIG_FILE" ]; then
  _git_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [ -n "$_git_root" ] && [ -f "$_git_root/.claude/autopilot.config.yaml" ]; then
    CONFIG_FILE="$_git_root/.claude/autopilot.config.yaml"
  elif [ -f ".claude/autopilot.config.yaml" ]; then
    CONFIG_FILE=".claude/autopilot.config.yaml"
  fi
fi

# 2) 从 config 读取（若可用）
if [ -n "$CONFIG_FILE" ]; then
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "[GATE-PHASE1] WARN: --config 指定的文件不存在，回落默认: $CONFIG_FILE" >&2
  elif command -v python3 >/dev/null 2>&1; then
    cfg_val=$(
      python3 - "$CONFIG_FILE" <<'PYEOF' 2>/dev/null || true
import sys
path = sys.argv[1]
try:
    import yaml
    with open(path) as f:
        data = yaml.safe_load(f) or {}
except ImportError:
    # 极简正则 fallback：匹配 "phases.requirements.gate.confidence_threshold" 嵌套
    import re
    with open(path) as f:
        text = f.read()
    # 简化：仅扫单行 "confidence_threshold:" 在 gate: 块下
    m = re.search(r'^\s{6,}confidence_threshold:\s*([0-9]+(?:\.[0-9]+)?)\s*$', text, re.M)
    if m:
        print(m.group(1))
    sys.exit(0)
except Exception:
    sys.exit(0)

cur = data
for key in ("phases", "requirements", "gate", "confidence_threshold"):
    if isinstance(cur, dict) and key in cur:
        cur = cur[key]
    else:
        cur = None
        break
if cur is not None:
    print(cur)
PYEOF
    )
    if [ -n "$cfg_val" ]; then
      if is_valid_threshold "$cfg_val"; then
        THRESHOLD="$cfg_val"
        THRESHOLD_SOURCE="config:$CONFIG_FILE"
      else
        echo "[GATE-PHASE1] invalid threshold in config (phases.requirements.gate.confidence_threshold='$cfg_val'); expected ^[0-9]+(\\.[0-9]+)?$" >&2
        exit 2
      fi
    fi
  else
    echo "[GATE-PHASE1] WARN: python3 不可用，跳过 config 阈值读取，回落默认 $DEFAULT_THRESHOLD" >&2
  fi
fi

# 3) CLI 覆写
if [ -n "$THRESHOLD_CLI" ]; then
  if ! is_valid_threshold "$THRESHOLD_CLI"; then
    echo "[GATE-PHASE1] invalid threshold '$THRESHOLD_CLI' (expected ^[0-9]+(\\.[0-9]+)?$)" >&2
    exit 2
  fi
  THRESHOLD="$THRESHOLD_CLI"
  THRESHOLD_SOURCE="cli"
fi

# 文件存在性
missing=0
for f in "$REQ_FILE" "$VERDICT_FILE" "$PACKET_FILE"; do
  if [ ! -f "$f" ]; then
    echo "[GATE-PHASE1] BLOCKED: 文件不存在: $f" >&2
    missing=1
  fi
done
[ "$missing" -eq 1 ] && exit 1

# 依赖
if ! command -v jq >/dev/null 2>&1; then
  echo "[GATE-PHASE1] BLOCKED: jq 未安装" >&2
  exit 1
fi
if ! command -v awk >/dev/null 2>&1; then
  echo "[GATE-PHASE1] BLOCKED: awk 未安装" >&2
  exit 1
fi

failures=0

# ── 校验 1: requirements.md 不含 [NEEDS CLARIFICATION ──
if grep -q -F '[NEEDS CLARIFICATION:' "$REQ_FILE"; then
  count=$(grep -c -F '[NEEDS CLARIFICATION:' "$REQ_FILE" || echo 0)
  echo "[GATE-PHASE1] BLOCKED: requirements.md 残留 $count 处 [NEEDS CLARIFICATION:] 标记" >&2
  failures=$((failures + 1))
fi

# ── 校验 2: verdict.confidence >= threshold ──
confidence=$(jq -r '.confidence // empty' "$VERDICT_FILE" 2>/dev/null || echo "")
if [ -z "$confidence" ] || [ "$confidence" = "null" ]; then
  echo "[GATE-PHASE1] BLOCKED: verdict.confidence 缺失或为 null" >&2
  failures=$((failures + 1))
else
  # 浮点比较：confidence < threshold 则失败
  ok=$(awk -v c="$confidence" -v t="$THRESHOLD" 'BEGIN { print (c+0 >= t+0) ? 1 : 0 }')
  if [ "$ok" != "1" ]; then
    echo "[GATE-PHASE1] BLOCKED: verdict.confidence=$confidence 低于阈值 $THRESHOLD" >&2
    failures=$((failures + 1))
  fi
fi

# ── 校验 3: verdict.conflicts 无 irreconcilable ──
irre_count=$(jq -r '[.conflicts[]? | select(.resolution == "irreconcilable")] | length' "$VERDICT_FILE" 2>/dev/null || echo "0")
if [ -z "$irre_count" ] || [ "$irre_count" = "null" ]; then
  irre_count=0
fi
if [ "$irre_count" -gt 0 ]; then
  topics=$(jq -r '[.conflicts[]? | select(.resolution == "irreconcilable") | .topic] | join(", ")' "$VERDICT_FILE" 2>/dev/null || echo "")
  echo "[GATE-PHASE1] BLOCKED: 存在 $irre_count 处不可调和的 conflict (resolution=irreconcilable): $topics" >&2
  failures=$((failures + 1))
fi

# ── 附加: packet.sha256 必须存在且为 64-char hex ──
sha=$(jq -r '.sha256 // empty' "$PACKET_FILE" 2>/dev/null || echo "")
if [ -z "$sha" ] || [ "$sha" = "null" ]; then
  echo "[GATE-PHASE1] BLOCKED: packet.sha256 缺失" >&2
  failures=$((failures + 1))
elif ! printf '%s' "$sha" | grep -Eq '^[0-9a-f]{64}$'; then
  echo "[GATE-PHASE1] BLOCKED: packet.sha256 格式无效（需 64-char hex）: $sha" >&2
  failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
  echo "[GATE-PHASE1] FAILED: $failures 项校验未通过" >&2
  exit 1
fi

echo "[GATE-PHASE1] PASSED: requirements clarified, confidence>=$THRESHOLD (source=$THRESHOLD_SOURCE), 无 irreconcilable conflicts, packet.sha256 ok"
exit 0
