#!/usr/bin/env bash
# test_needs_clarification_marker.sh — Task B9
# 验证 BA Agent 必须使用 [NEEDS CLARIFICATION: ...] 协议（GitHub Spec Kit）
# 覆盖：requirements-template.md 必含 marker 区块
#       phase1-requirements.md BA prompt 必须指示使用 marker

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=_test_helpers.sh
source "$SCRIPT_DIR/_test_helpers.sh"

TEMPLATE_FILE="$PLUGIN_DIR/runtime/templates/requirements-template.md"
PHASE1_DOC="$PLUGIN_DIR/skills/autopilot-phase1-requirements/references/phase1-requirements.md"

echo "=== Task B9: [NEEDS CLARIFICATION] 协议测试 ==="

# ---------------- template.md 结构性断言 ----------------
echo ""
echo "--- Group 1: requirements-template.md 结构性断言 ---"

# 1. 文件存在
assert_file_exists "1. requirements-template.md 存在" "$TEMPLATE_FILE"

# 2. 必含 marker 字面量 "[NEEDS CLARIFICATION:"（核心协议，fixed-string）
if [ -f "$TEMPLATE_FILE" ] && grep -qF '[NEEDS CLARIFICATION:' "$TEMPLATE_FILE"; then
  green "  PASS: 2. template 含 [NEEDS CLARIFICATION: marker"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2. template 缺少 [NEEDS CLARIFICATION: marker"
  FAIL=$((FAIL + 1))
fi

# 3. 必含 User Stories 章节
assert_file_contains "3. template 含 User Stories 章节" \
  "$TEMPLATE_FILE" 'User Stories'

# 4. 必含 Acceptance Criteria 章节
assert_file_contains "4. template 含 Acceptance Criteria 章节" \
  "$TEMPLATE_FILE" 'Acceptance Criteria'

# 5. 必含 Non-Goals 章节
assert_file_contains "5. template 含 Non-Goals 章节" \
  "$TEMPLATE_FILE" 'Non-Goals'

# 6. 必含 Open Questions 章节
assert_file_contains "6. template 含 Open Questions 章节" \
  "$TEMPLATE_FILE" 'Open Questions'

# 7. Review Checklist 必须要求消除所有 NEEDS CLARIFICATION 标记（fixed-string, 含特殊字符）
if grep -qF 'No `[NEEDS CLARIFICATION]`' "$TEMPLATE_FILE"; then
  green "  PASS: 7. Review Checklist 含 No [NEEDS CLARIFICATION] 检查"
  PASS=$((PASS + 1))
else
  red "  FAIL: 7. Review Checklist 缺少 No [NEEDS CLARIFICATION] 检查"
  FAIL=$((FAIL + 1))
fi

# ---------------- phase1-requirements.md BA prompt 断言 ----------------
echo ""
echo "--- Group 2: BA prompt 指令断言 ---"

# 8. phase1-requirements.md 含 NEEDS CLARIFICATION 字样
assert_file_contains "8. phase1-requirements.md 含 NEEDS CLARIFICATION" \
  "$PHASE1_DOC" 'NEEDS CLARIFICATION'

# 9. 明确禁止"貌似合理的假设"
assert_file_contains "9. BA prompt 禁止貌似合理假设" \
  "$PHASE1_DOC" '貌似合理'

# 10. 引用 GitHub Spec Kit 来源
assert_file_contains "10. BA prompt 引用 spec-kit 来源" \
  "$PHASE1_DOC" 'spec-kit'

# ---------------- 边界/错误路径 ----------------
echo ""
echo "--- Group 3: 边界与错误路径 ---"

# 11. template 不得含 HOW/实现细节指引的反例（WHAT/WHY only 契约反向断言）
assert_file_contains "11. template 声明 WHAT/WHY only" \
  "$TEMPLATE_FILE" 'WHAT/WHY'

# 12. marker 结尾必须闭合 — 基本 sanity：至少一对 [NEEDS CLARIFICATION 与 ] 共存
marker_count=$(grep -cF '[NEEDS CLARIFICATION:' "$TEMPLATE_FILE" 2>/dev/null || echo 0)
if [ "$marker_count" -ge 1 ]; then
  green "  PASS: 12. template 至少 1 个 NEEDS CLARIFICATION 示例 ($marker_count)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 12. template 缺少 NEEDS CLARIFICATION 示例"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
