#!/usr/bin/env bash
# start-allure-serve.sh — 启动 Allure 本地预览服务
#
# 用法: start-allure-serve.sh <change_dir> [base_port]
#
# 参数:
#   change_dir  — openspec/changes/<change_name> 的路径
#   base_port   — 基础端口号（默认 4040），自动扫描 base_port 到 base_port+9
#
# 输出: JSON 到 stdout
#   成功: {"status":"ok","url":"http://localhost:4041","pid":12345}
#   跳过: {"status":"skipped","reason":"..."}
#   失败: {"status":"warning","error":"..."}
#
# 副作用:
#   - 写入 ${change_dir}/context/allure-serve.pid
#   - 写入 ${change_dir}/context/allure-preview.json
#   - 更新 ${change_dir}/context/state-snapshot.json 的 report_state.allure_preview_url
#
# 退出码: 始终 0（信息性脚本）

set -uo pipefail

CHANGE_DIR="${1:?用法: start-allure-serve.sh <change_dir> [base_port]}"
BASE_PORT="${2:-4040}"

CONTEXT_DIR="$CHANGE_DIR/context"
REPORT_DIR="$CHANGE_DIR/reports"
PID_FILE="$CONTEXT_DIR/allure-serve.pid"
PREVIEW_FILE="$CONTEXT_DIR/allure-preview.json"

# ── 检查是否已有运行中的服务 ──
if [[ -f "$PID_FILE" ]]; then
  EXISTING_PID=$(cat "$PID_FILE" 2>/dev/null || echo "")
  if [[ -n "$EXISTING_PID" ]] && kill -0 "$EXISTING_PID" 2>/dev/null; then
    # 服务已运行，读取已有 URL
    EXISTING_URL=""
    if [[ -f "$PREVIEW_FILE" ]]; then
      EXISTING_URL=$(python3 -c "import json; print(json.load(open('$PREVIEW_FILE')).get('url',''))" 2>/dev/null || echo "")
    fi
    if [[ -n "$EXISTING_URL" ]]; then
      echo "{\"status\":\"ok\",\"url\":\"$EXISTING_URL\",\"pid\":$EXISTING_PID,\"reused\":true}"
      exit 0
    fi
  else
    rm -f "$PID_FILE"
  fi
fi

# ── 查找 Allure Report 目录 ──
ALLURE_REPORT_DIR=""

# 优先级 1: Phase 6 checkpoint 中的 allure_report_dir
P6_CHECKPOINT="$CONTEXT_DIR/phase-results/phase-6-report.json"
if [[ -f "$P6_CHECKPOINT" ]]; then
  CHECKPOINT_REPORT_DIR=$(python3 -c "import json; print(json.load(open('$P6_CHECKPOINT')).get('allure_report_dir',''))" 2>/dev/null || echo "")
  if [[ -n "$CHECKPOINT_REPORT_DIR" && -d "$CHECKPOINT_REPORT_DIR" && -f "$CHECKPOINT_REPORT_DIR/index.html" ]]; then
    ALLURE_REPORT_DIR="$CHECKPOINT_REPORT_DIR"
  fi
fi

# 优先级 2: change 级 reports/allure-report/
if [[ -z "$ALLURE_REPORT_DIR" && -d "$REPORT_DIR/allure-report" && -f "$REPORT_DIR/allure-report/index.html" ]]; then
  ALLURE_REPORT_DIR="$REPORT_DIR/allure-report"
fi

# 优先级 3: 项目根 allure-report/
PROJECT_ROOT=$(cd "$CHANGE_DIR/../.." 2>/dev/null && pwd || pwd)
if [[ -z "$ALLURE_REPORT_DIR" && -d "$PROJECT_ROOT/allure-report" && -f "$PROJECT_ROOT/allure-report/index.html" ]]; then
  ALLURE_REPORT_DIR="$PROJECT_ROOT/allure-report"
fi

# ── 尝试从 allure-results 生成报告 ──
if [[ -z "$ALLURE_REPORT_DIR" ]]; then
  ALLURE_RESULTS_DIR=""
  # 从 checkpoint 读取
  if [[ -f "$P6_CHECKPOINT" ]]; then
    CHECKPOINT_RESULTS_DIR=$(python3 -c "import json; print(json.load(open('$P6_CHECKPOINT')).get('allure_results_dir',''))" 2>/dev/null || echo "")
    if [[ -n "$CHECKPOINT_RESULTS_DIR" && -d "$CHECKPOINT_RESULTS_DIR" ]]; then
      ALLURE_RESULTS_DIR="$CHECKPOINT_RESULTS_DIR"
    fi
  fi
  # change 级
  if [[ -z "$ALLURE_RESULTS_DIR" && -d "$REPORT_DIR/allure-results" ]]; then
    ALLURE_RESULTS_DIR="$REPORT_DIR/allure-results"
  fi
  # 项目根
  if [[ -z "$ALLURE_RESULTS_DIR" && -d "$PROJECT_ROOT/allure-results" ]]; then
    ALLURE_RESULTS_DIR="$PROJECT_ROOT/allure-results"
  fi

  if [[ -n "$ALLURE_RESULTS_DIR" ]]; then
    # 生成报告
    GEN_OUTPUT_DIR="$REPORT_DIR/allure-report"
    if npx allure generate "$ALLURE_RESULTS_DIR" -o "$GEN_OUTPUT_DIR" --clean 2>/dev/null; then
      if [[ -f "$GEN_OUTPUT_DIR/index.html" ]]; then
        ALLURE_REPORT_DIR="$GEN_OUTPUT_DIR"
      fi
    fi
  fi
fi

if [[ -z "$ALLURE_REPORT_DIR" ]]; then
  echo '{"status":"skipped","reason":"无 Allure 报告产物可供预览"}'
  exit 0
fi

# ── 检测可用端口 ──
SERVE_PORT=""
for offset in $(seq 0 9); do
  PORT=$((BASE_PORT + offset))
  if ! lsof -i ":$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    SERVE_PORT="$PORT"
    break
  fi
done

if [[ -z "$SERVE_PORT" ]]; then
  echo "{\"status\":\"warning\",\"error\":\"端口 $BASE_PORT-$((BASE_PORT+9)) 全部被占用\"}"
  exit 0
fi

# ── 启动 Allure Open 服务 ──
mkdir -p "$CONTEXT_DIR"
nohup npx allure open "$ALLURE_REPORT_DIR" -p "$SERVE_PORT" >/dev/null 2>&1 &
ALLURE_PID=$!
echo "$ALLURE_PID" > "$PID_FILE"

# ── 等待服务就绪 ──
ALLURE_URL="http://localhost:$SERVE_PORT"
READY=false
for i in $(seq 1 10); do
  if curl -s -o /dev/null -w "%{http_code}" "$ALLURE_URL" 2>/dev/null | grep -q "200\|301\|302"; then
    READY=true
    break
  fi
  sleep 1
done

if [[ "$READY" != "true" ]]; then
  # 检查进程是否还在
  if ! kill -0 "$ALLURE_PID" 2>/dev/null; then
    rm -f "$PID_FILE"
    echo "{\"status\":\"warning\",\"error\":\"Allure 服务启动后立即退出\"}"
    exit 0
  fi
  # 进程还在但未响应，可能需要更多时间，仍标记为成功
fi

# ── 写入 allure-preview.json ──
python3 -c "
import json
data = {
    'url': '$ALLURE_URL',
    'pid': $ALLURE_PID,
    'port': $SERVE_PORT,
    'report_dir': '$ALLURE_REPORT_DIR',
    'started_at': __import__('datetime').datetime.now(__import__('datetime').timezone.utc).isoformat()
}
with open('$PREVIEW_FILE', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null

# ── 更新 state-snapshot.json ──
if [[ -f "$CONTEXT_DIR/state-snapshot.json" ]]; then
  TMP_SNAPSHOT=$(mktemp)
  python3 -c "
import json
with open('$CONTEXT_DIR/state-snapshot.json') as f:
    snap = json.load(f)
if 'report_state' not in snap:
    snap['report_state'] = {}
snap['report_state']['allure_preview_url'] = '$ALLURE_URL'
with open('$TMP_SNAPSHOT', 'w') as f:
    json.dump(snap, f, indent=2)
" 2>/dev/null && mv "$TMP_SNAPSHOT" "$CONTEXT_DIR/state-snapshot.json"
fi

echo "{\"status\":\"ok\",\"url\":\"$ALLURE_URL\",\"pid\":$ALLURE_PID}"
exit 0
