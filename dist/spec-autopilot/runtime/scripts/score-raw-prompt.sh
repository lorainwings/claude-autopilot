#!/usr/bin/env bash
# score-raw-prompt.sh — Task 15 (C15) 原始用户 prompt 语言学特征评分
#
# 目标：Phase 1 混合清晰度评分的 rule_score 不再读取 BA Agent 结构化产出（rp.*），
#       改为对**原始用户 prompt**计算确定性语言学特征，避免 BA drift 污染规则分。
#
# 输入：
#   --prompt <text>        # 直接传入 prompt 文本
#   --prompt-file <path>   # 从文件读取 prompt
#
# 输出（stdout，严格 JSON）：
#   {
#     "verb_density":    <float>,  # 动词数 / 总词数（基于 token 数）
#     "quantifier_count":<int>,    # 数字、时间单位、阈值词匹配总数
#     "role_clarity":    <int>,    # 角色词出现次数
#     "total_score":     <float>   # 归一到 [0,1] 的加权总分
#   }
#
# 总分公式：
#   total = min(1.0, 0.4 * min(1.0, verb_count / 4)
#                  + 0.3 * min(1.0, quantifier_count / 5)
#                  + 0.3 * min(1.0, role_clarity / 2))
#
#   使用 verb_count 的软饱和（而非 verb_density × 系数）避免超短 prompt
#   因单一动词占比过高而虚假得分。verb_density 仍作为观测指标输出。
#
# 退出码：
#   0  成功
#   2  参数错误 / 空 prompt / 文件不存在

set -uo pipefail

PROMPT=""
PROMPT_FILE=""

usage() {
  cat >&2 <<EOF
用法: $(basename "$0") (--prompt <text> | --prompt-file <path>)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --prompt)
      PROMPT="${2:-}"
      shift 2
      ;;
    --prompt-file)
      PROMPT_FILE="${2:-}"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "未知参数: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [ -n "$PROMPT_FILE" ]; then
  if [ ! -f "$PROMPT_FILE" ]; then
    echo "文件不存在: $PROMPT_FILE" >&2
    exit 2
  fi
  PROMPT="$(cat "$PROMPT_FILE")"
fi

# 去除首尾空白后判空
TRIMMED="$(printf '%s' "$PROMPT" | tr -d '[:space:]')"
if [ -z "$TRIMMED" ]; then
  echo "prompt 为空" >&2
  exit 2
fi

python3 - "$PROMPT" <<'PY'
import json
import re
import sys

text = sys.argv[1]

# 动词白名单：覆盖 spec-autopilot 常见中英文命令式动词
VERBS = {
    "添加", "创建", "实现", "支持", "修改", "删除", "分析", "做", "生成",
    "构建", "配置", "集成", "优化", "重构", "替换", "升级", "迁移", "拆分",
    "合并", "修复", "返回", "显示", "响应", "跳转",
    "add", "create", "implement", "support", "modify", "delete", "build",
    "generate", "configure", "integrate", "fix", "optimize", "refactor",
    "replace", "upgrade", "migrate", "split", "merge", "return", "display",
}

# 角色词：明确指代需求主体
ROLE_WORDS = [
    "用户", "管理员", "访客", "游客", "用户组", "运营", "开发者",
    "admin", "user", "guest", "visitor", "operator", "developer",
]

# 量化词：数字 + 时间单位 + 阈值 + 百分比
QUANTIFIER_PATTERNS = [
    r"\d+",
    r"(?:秒|分钟|小时|天|周|月|年)",
    r"(?:至少|最多|不超过|不少于|阈值)",
    r"\b(?:ms|sec|min|hour|day|week|month|year|percent)\b",
    r"%",
]

# Token 化：英文按 \w+ 拆分，中文按字拆分
# 简化：先抽英文单词，再把剩余中文字符每个算一个 token
english_tokens = re.findall(r"[A-Za-z]+", text)
chinese_tokens = re.findall(r"[\u4e00-\u9fff]", text)
tokens = [t.lower() for t in english_tokens] + chinese_tokens
total_tokens = len(tokens)

if total_tokens == 0:
    print(json.dumps({
        "verb_density": 0.0,
        "quantifier_count": 0,
        "role_clarity": 0,
        "total_score": 0.0,
    }))
    sys.exit(0)

# 动词计数：英文 token 直接匹配；中文则检查文本中含白名单词
verb_count = 0
text_lower = text.lower()
for w in english_tokens:
    if w.lower() in VERBS:
        verb_count += 1
for v in VERBS:
    if re.fullmatch(r"[\u4e00-\u9fff]+", v):
        # 中文动词：统计在原文中出现次数
        verb_count += len(re.findall(re.escape(v), text))

verb_density = verb_count / total_tokens if total_tokens else 0.0

# 量化词计数：所有 pattern 的匹配总数
quantifier_count = 0
for p in QUANTIFIER_PATTERNS:
    quantifier_count += len(re.findall(p, text, flags=re.IGNORECASE))

# 角色词计数：文本中出现次数
role_clarity = 0
for r in ROLE_WORDS:
    role_clarity += len(re.findall(re.escape(r), text_lower))

# 归一加权：
#   verb_count 饱和点 4（避免超短 prompt 因单一动词占比而虚假得分）
#   quantifier_count 饱和点 5
#   role_clarity 饱和点 2
norm_verb = min(1.0, verb_count / 4)
norm_quant = min(1.0, quantifier_count / 5)
norm_role = min(1.0, role_clarity / 2)

total_score = 0.4 * norm_verb + 0.3 * norm_quant + 0.3 * norm_role
total_score = min(1.0, max(0.0, total_score))

print(json.dumps({
    "verb_density": round(verb_density, 4),
    "quantifier_count": int(quantifier_count),
    "role_clarity": int(role_clarity),
    "total_score": round(total_score, 4),
}))
PY
