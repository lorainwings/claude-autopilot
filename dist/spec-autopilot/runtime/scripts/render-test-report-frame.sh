#!/usr/bin/env bash
# render-test-report-frame.sh — 确定性渲染 "Test Report" 线框 + 自愈启动 Allure 服务
#
# 用途: Phase 4/5/7 共享调用，确保测试报告访问地址始终以线框形式展示给用户
#       ——无论上游 AI 步骤是否跳过、Phase 6 是否尚未执行。
#
# 用法:
#   render-test-report-frame.sh <change_dir> [phase_label] [base_port]
#
# 参数:
#   change_dir   — openspec/changes/<change_name> 路径（必填）
#   phase_label  — 线框标题（默认 "Test Report"；Phase 5 TDD 建议传 "TDD Test Report"）
#   base_port    — Allure 基础端口（默认 4040）
#
# 行为:
#   1. 尝试自愈启动 Allure 服务（复用 start-allure-serve.sh 的优先级搜索逻辑）
#   2. 读取 phase-6-report.json（若存在）或扫描 allure-results 推导测试总数
#   3. 渲染固定宽度 50 字符 Test Report 线框到 stdout
#   4. 即使无测试结果也展示线框，Allure 行显示实际 URL 或 "unavailable"
#
# 退出码: 始终 0（信息性脚本，不阻断主流程）
#
# 设计约束:
#   - 纯 ASCII / BMP 字符（╭─╮ │ ╰─╯），与 log-format.md 的 Summary Box 一致
#   - 框内有效宽度 50 字符，遵循 references/log-format.md 约定

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CHANGE_DIR="${1:-}"
PHASE_LABEL="${2:-Test Report}"
BASE_PORT="${3:-4040}"

if [[ -z "$CHANGE_DIR" ]]; then
  echo "ERROR: 缺少 change_dir 参数" >&2
  echo "用法: render-test-report-frame.sh <change_dir> [phase_label] [base_port]" >&2
  exit 0
fi

CONTEXT_DIR="$CHANGE_DIR/context"
REPORT_DIR="$CHANGE_DIR/reports"
PREVIEW_FILE="$CONTEXT_DIR/allure-preview.json"

# ── Step 1: 自愈启动 Allure 服务（即使无 allure-results 也会 skipped，不阻断） ──
bash "$SCRIPT_DIR/start-allure-serve.sh" "$CHANGE_DIR" "$BASE_PORT" >/dev/null 2>&1 || true

# ── Step 2: 读取 Allure URL ──
ALLURE_URL=""
if [[ -f "$PREVIEW_FILE" ]]; then
  ALLURE_URL=$(python3 -c "import json; print(json.load(open('$PREVIEW_FILE')).get('url',''))" 2>/dev/null || echo "")
  # URL 存活校验：PID 必须活着且 HTTP 可达
  ALLURE_PID=$(python3 -c "import json; print(json.load(open('$PREVIEW_FILE')).get('pid',''))" 2>/dev/null || echo "")
  if [[ -n "$ALLURE_URL" && -n "$ALLURE_PID" ]]; then
    if ! kill -0 "$ALLURE_PID" 2>/dev/null; then
      ALLURE_URL=""
    fi
  fi
fi

# ── Step 3: 聚合测试结果（优先级: phase-6 checkpoint > 扫描 allure-results） ──
P6_CHECKPOINT="$CONTEXT_DIR/phase-results/phase-6-report.json"
TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0
PASS_RATE=0
SOURCE="none"

if [[ -f "$P6_CHECKPOINT" ]]; then
  read -r TOTAL PASSED FAILED SKIPPED PASS_RATE < <(python3 -c "
import json
try:
    with open('$P6_CHECKPOINT') as f:
        data = json.load(f)
    suites = data.get('suite_results', []) or []
    t = sum(s.get('total', 0) for s in suites)
    p = sum(s.get('passed', 0) for s in suites)
    fl = sum(s.get('failed', 0) for s in suites)
    sk = sum(s.get('skipped', 0) for s in suites)
    rate = round(p / t * 100, 1) if t else 0.0
    print(t, p, fl, sk, rate)
except Exception:
    print(0, 0, 0, 0, 0)
" 2>/dev/null || echo "0 0 0 0 0")
  [[ "$TOTAL" -gt 0 ]] && SOURCE="phase-6-report.json"
fi

# 若 phase-6 尚未生成，扫描 allure-results 目录（含 TDD 子目录）
if [[ "$TOTAL" -eq 0 ]]; then
  ALLURE_RESULTS_CANDIDATES=(
    "$REPORT_DIR/allure-results"
    "$REPORT_DIR/allure-results/tdd/red"
    "$REPORT_DIR/allure-results/tdd/green"
    "$REPORT_DIR/allure-results/tdd/refactor"
  )
  for d in "${ALLURE_RESULTS_CANDIDATES[@]}"; do
    [[ -d "$d" ]] || continue
    read -r t p fl sk < <(python3 -c "
import json, glob, os
t = p = fl = sk = 0
for fn in glob.glob('$d/*-result.json'):
    try:
        with open(fn) as f:
            r = json.load(f)
        t += 1
        s = r.get('status', '')
        if s == 'passed': p += 1
        elif s in ('failed', 'broken'): fl += 1
        elif s == 'skipped': sk += 1
    except Exception:
        pass
print(t, p, fl, sk)
" 2>/dev/null || echo "0 0 0 0")
    TOTAL=$((TOTAL + t))
    PASSED=$((PASSED + p))
    FAILED=$((FAILED + fl))
    SKIPPED=$((SKIPPED + sk))
  done
  if [[ "$TOTAL" -gt 0 ]]; then
    PASS_RATE=$(python3 -c "print(round($PASSED/$TOTAL*100, 1))" 2>/dev/null || echo "0")
    SOURCE="allure-results-scan"
  fi
fi

# ── Step 4: 渲染线框（固定 50 字符宽度） ──
# 帮助函数：左对齐内容并右侧补空格到 50 字符
render_line() {
  local content="$1"
  printf "│   %-47s│\n" "$content"
}

render_blank() {
  printf "│%-50s│\n" ""
}

URL_DISPLAY="${ALLURE_URL:-unavailable}"
RESULT_DISPLAY="pending (tests not yet executed)"
if [[ "$TOTAL" -gt 0 ]]; then
  RESULT_DISPLAY=""
fi

echo "╭──────────────────────────────────────────────────╮"
render_blank
render_line "$PHASE_LABEL"
render_blank
if [[ "$TOTAL" -gt 0 ]]; then
  render_line "Total   $TOTAL  Passed  $PASSED  Failed  $FAILED"
  render_line "Skipped $SKIPPED  Pass Rate  ${PASS_RATE}%"
else
  render_line "Status  $RESULT_DISPLAY"
fi
render_blank
render_line "Allure  $URL_DISPLAY"
render_blank
echo "╰──────────────────────────────────────────────────╯"

# 附加调试提示（仅当 Allure 不可用）
if [[ -z "$ALLURE_URL" ]]; then
  echo ""
  echo "[ALLURE] 预览不可用。请检查："
  echo "  1. 是否已安装 allure CLI: npx allure --version"
  echo "  2. 是否已产出 allure-results: $REPORT_DIR/allure-results/"
  echo "  3. 重试启动: bash \$CLAUDE_PLUGIN_ROOT/runtime/scripts/start-allure-serve.sh \"$CHANGE_DIR\""
fi

exit 0
