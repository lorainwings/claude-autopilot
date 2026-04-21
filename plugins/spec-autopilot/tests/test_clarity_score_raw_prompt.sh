#!/usr/bin/env bash
# TEST_LAYER: behavior
# test_clarity_score_raw_prompt.sh — 验证 Task 15 (C15) clarity_score 解耦自 BA 产出
# 目标：rule_score 改为评估"原始用户 prompt"的语言学特征（动词密度/量化词/角色词），
#       与 BA Agent 的结构化字段解耦，避免 BA drift 污染规则分。
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
DOC_FILE="$(cd "$TEST_DIR/.." && pwd)/skills/autopilot-phase1-requirements/references/phase1-clarity-scoring.md"
source "$TEST_DIR/_test_helpers.sh"

SCORER="$SCRIPT_DIR/score-raw-prompt.sh"

echo "--- clarity_score raw prompt decoupling ---"

# 0. 脚本存在且可执行
if [ -x "$SCORER" ]; then
  green "  PASS: 0. score-raw-prompt.sh exists & executable"
  PASS=$((PASS + 1))
else
  red "  FAIL: 0. score-raw-prompt.sh missing or not executable: $SCORER"
  FAIL=$((FAIL + 1))
fi

# 0a. 语法校验
if bash -n "$SCORER" 2>/dev/null; then
  green "  PASS: 0a. scorer syntax OK"
  PASS=$((PASS + 1))
else
  red "  FAIL: 0a. scorer syntax error"
  FAIL=$((FAIL + 1))
fi

VAGUE_PROMPT="做个登录"
SPECIFIC_PROMPT="为电商应用添加用户登录功能：邮箱+密码、支持记住我、JWT token 24h 过期，管理员可以在后台至少查看 100 条登录记录"

VAGUE_JSON=$("$SCORER" --prompt "$VAGUE_PROMPT" 2>/dev/null || echo "")
SPECIFIC_JSON=$("$SCORER" --prompt "$SPECIFIC_PROMPT" 2>/dev/null || echo "")

# 1. JSON 格式良好（jq 或 python 可解析）
if python3 -c "import json,sys; json.loads(sys.argv[1])" "$VAGUE_JSON" 2>/dev/null; then
  green "  PASS: 1. vague prompt JSON parseable"
  PASS=$((PASS + 1))
else
  red "  FAIL: 1. vague prompt JSON unparseable: $VAGUE_JSON"
  FAIL=$((FAIL + 1))
fi

if python3 -c "import json,sys; json.loads(sys.argv[1])" "$SPECIFIC_JSON" 2>/dev/null; then
  green "  PASS: 1a. specific prompt JSON parseable"
  PASS=$((PASS + 1))
else
  red "  FAIL: 1a. specific prompt JSON unparseable: $SPECIFIC_JSON"
  FAIL=$((FAIL + 1))
fi

# 2. 字段存在检查
for field in verb_density quantifier_count role_clarity total_score; do
  if python3 -c "import json,sys; d=json.loads(sys.argv[1]); sys.exit(0 if '$field' in d else 1)" "$SPECIFIC_JSON"; then
    green "  PASS: 2. specific JSON has field '$field'"
    PASS=$((PASS + 1))
  else
    red "  FAIL: 2. specific JSON missing field '$field'"
    FAIL=$((FAIL + 1))
  fi
done

extract_score() {
  python3 -c "import json,sys; print(json.loads(sys.argv[1])['total_score'])" "$1"
}

VAGUE_SCORE=$(extract_score "$VAGUE_JSON" 2>/dev/null || echo "1.0")
SPECIFIC_SCORE=$(extract_score "$SPECIFIC_JSON" 2>/dev/null || echo "0.0")

# 3. 模糊 prompt total_score < 0.30
if python3 -c "import sys; sys.exit(0 if float(sys.argv[1]) < 0.30 else 1)" "$VAGUE_SCORE"; then
  green "  PASS: 3. vague prompt total_score < 0.30 (got $VAGUE_SCORE)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3. vague prompt total_score >= 0.30 (got $VAGUE_SCORE)"
  FAIL=$((FAIL + 1))
fi

# 4. 明确 prompt total_score > 0.55
if python3 -c "import sys; sys.exit(0 if float(sys.argv[1]) > 0.55 else 1)" "$SPECIFIC_SCORE"; then
  green "  PASS: 4. specific prompt total_score > 0.55 (got $SPECIFIC_SCORE)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 4. specific prompt total_score <= 0.55 (got $SPECIFIC_SCORE)"
  FAIL=$((FAIL + 1))
fi

# 5. specific > vague
if python3 -c "import sys; sys.exit(0 if float(sys.argv[1]) > float(sys.argv[2]) + 0.20 else 1)" \
  "$SPECIFIC_SCORE" "$VAGUE_SCORE"; then
  green "  PASS: 5. specific score ($SPECIFIC_SCORE) >> vague score ($VAGUE_SCORE)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 5. specific score ($SPECIFIC_SCORE) not significantly > vague ($VAGUE_SCORE)"
  FAIL=$((FAIL + 1))
fi

# 6. 空 prompt exit 2
set +e
"$SCORER" --prompt "" > /dev/null 2>&1
EMPTY_EXIT=$?
set -e
assert_exit "6. empty prompt → exit 2" 2 "$EMPTY_EXIT"

# 7. --prompt-file 读取
TMP_FILE="$(mktemp)"
printf '%s' "$SPECIFIC_PROMPT" > "$TMP_FILE"
FILE_JSON=$("$SCORER" --prompt-file "$TMP_FILE" 2>/dev/null || echo "")
rm -f "$TMP_FILE"
if python3 -c "import json,sys; d=json.loads(sys.argv[1]); sys.exit(0 if float(d['total_score']) > 0.55 else 1)" "$FILE_JSON"; then
  green "  PASS: 7. --prompt-file 模式与 --prompt 产出一致 (score > 0.55)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 7. --prompt-file 读取异常: $FILE_JSON"
  FAIL=$((FAIL + 1))
fi

# 8. Doc 包含解耦说明
assert_file_contains "8. doc references score-raw-prompt.sh" "$DOC_FILE" "score-raw-prompt.sh"
assert_file_contains "8a. doc explains decoupling from rp.*" "$DOC_FILE" "不再"
assert_file_contains "8b. doc mentions raw prompt" "$DOC_FILE" "原始用户 prompt"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
