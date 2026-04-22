#!/usr/bin/env bash
# test_gui_snapshot_meta_refresh.sh — 真实集成测试: 已连接 GUI 的 meta-only 增量刷新
# 验证:
#   1. WS 初始连接收到 snapshot（含 meta 字段）
#   2. 仅修改 state-snapshot.json / archive-readiness.json（不追加 event）
#   3. 同一 WS 连接收到第二条 snapshot
#   4. 新 meta 值正确进入 GUI 可消费字段
#   5. /api/info 与 WS snapshot meta 一致
#
# 启动真实 autopilot-server.ts，通过环境变量覆盖端口。
# 依赖: bun
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$TEST_DIR/.." && pwd)"
SERVER_ENTRY="$PLUGIN_DIR/runtime/server/autopilot-server.ts"
source "$TEST_DIR/_test_helpers.sh"

echo "--- GUI snapshot meta refresh integration test (real server) ---"

# === 前置检查 ===
if ! command -v bun &>/dev/null; then
  echo "  [SKIP] bun not available, skipping integration test"
  exit 0
fi

# 使用随机高端口避免冲突
HTTP_PORT=$((30000 + RANDOM % 10000))
WS_PORT=$((HTTP_PORT + 1))

# === 构建临时项目目录 ===
TMP_PROJECT=$(mktemp -d)
SERVER_PID=""
cleanup() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$TMP_PROJECT"
}
trap cleanup EXIT

mkdir -p "$TMP_PROJECT/logs/sessions"
mkdir -p "$TMP_PROJECT/openspec/changes/test-change/context"

# 写入 lock file
cat >"$TMP_PROJECT/openspec/changes/.autopilot-active" <<'JSON'
{"change":"test-change","pid":"99999","started":"2026-01-01T00:00:00Z","session_id":"sess-meta-test"}
JSON

# 写入初始 state-snapshot.json
cat >"$TMP_PROJECT/openspec/changes/test-change/context/state-snapshot.json" <<'JSON'
{"schema_version":"1.0","snapshot_hash":"hash-old","gate_frontier":5,"next_action":"phase5","requirement_packet_hash":"pkt-old","phase_results":{},"review_status":null,"fixup_status":null,"archive_status":null,"recovery_confidence":null}
JSON

# 写入初始 archive-readiness.json
cat >"$TMP_PROJECT/openspec/changes/test-change/context/archive-readiness.json" <<'JSON'
{"timestamp":"2026-01-01T00:00:00Z","mode":"full","checks":{"all_checkpoints_ok":false,"fixup_completeness":{"passed":false,"fixup_count":0,"checkpoint_count":3},"anchor_valid":true,"worktree_clean":true,"review_findings_clear":true,"zero_skip_passed":true},"overall":"blocked","block_reasons":["fixup_incomplete"]}
JSON

touch "$TMP_PROJECT/logs/events.jsonl"

# === 启动真实 autopilot-server.ts ===
AUTOPILOT_HTTP_PORT=$HTTP_PORT \
AUTOPILOT_WS_PORT=$WS_PORT \
AUTOPILOT_POLL_MS=300 \
bun run "$SERVER_ENTRY" --project-root "$TMP_PROJECT" --no-open \
  >"$TMP_PROJECT/_server.log" 2>&1 &
SERVER_PID=$!

# 等待 /api/health 可用（最多 8 秒）
WAITED=0
while [ "$WAITED" -lt 80 ]; do
  if curl -s --max-time 1 "http://localhost:${HTTP_PORT}/api/health" 2>/dev/null | grep -q '"status"'; then
    break
  fi
  sleep 0.1
  WAITED=$((WAITED + 1))
done

if ! curl -s --max-time 1 "http://localhost:${HTTP_PORT}/api/health" 2>/dev/null | grep -q '"status"'; then
  red "  FAIL: real server did not become healthy within 8s"
  cat "$TMP_PROJECT/_server.log" 2>/dev/null | tail -20
  echo "Results: 0 passed, 1 failed"
  exit 1
fi

green "  PASS: real autopilot-server started on HTTP:$HTTP_PORT WS:$WS_PORT"
PASS=$((PASS + 1))

# === 测试 1: WS 初始 snapshot 包含旧 meta ===
mkdir -p "$TMP_PROJECT/_ws_out"

bun -e "
const ws = new WebSocket('ws://localhost:${WS_PORT}');
ws.onmessage = (e: any) => {
  Bun.write('${TMP_PROJECT}/_ws_out/init.json', e.data);
  ws.close();
};
ws.onerror = () => process.exit(1);
setTimeout(() => { ws.close(); process.exit(1); }, 3000);
" 2>/dev/null
sleep 0.3

if [ -f "$TMP_PROJECT/_ws_out/init.json" ]; then
  MSG1=$(cat "$TMP_PROJECT/_ws_out/init.json")
  if grep -q '"type":"snapshot"' <<< "$MSG1"; then
    green "  PASS: 1a. WS 初始连接收到 snapshot 消息"
    PASS=$((PASS + 1))
  else
    red "  FAIL: 1a. WS 初始连接未收到 snapshot"
    FAIL=$((FAIL + 1))
  fi

  META_CHECK=$(echo "$MSG1" | python3 -c "
import json, sys
msg = json.load(sys.stdin)
m = msg.get('meta', {})
ok = True
if m.get('requirementPacketHash') != 'pkt-old': ok = False
if m.get('gateFrontier') != 5: ok = False
ar = m.get('archiveReadiness')
if not isinstance(ar, dict) or ar.get('overall') != 'blocked': ok = False
print('OK' if ok else 'FAIL')
" 2>/dev/null || echo "FAIL")

  if [ "$META_CHECK" = "OK" ]; then
    green "  PASS: 1b. 初始 snapshot meta 包含正确旧值 (pkt-old, gf=5, blocked)"
    PASS=$((PASS + 1))
  else
    red "  FAIL: 1b. 初始 snapshot meta 值不正确"
    FAIL=$((FAIL + 1))
  fi
else
  red "  FAIL: 1a. WS 初始连接超时"
  red "  FAIL: 1b. (依赖 1a)"
  FAIL=$((FAIL + 2))
fi

# === 测试 2: 仅修改 meta 文件 → WS 收到第二条 snapshot ===
bun -e "
let count = 0;
const ws = new WebSocket('ws://localhost:${WS_PORT}');
ws.onmessage = (e: any) => {
  count++;
  Bun.write('${TMP_PROJECT}/_ws_out/long_' + count + '.json', e.data);
  // 等待最终态消息：避免捕获写入中间态（state 已更新但 archive 未更新）
  try {
    const msg = JSON.parse(e.data);
    const m = msg && msg.meta;
    const ar = m && m.archiveReadiness;
    if (m && m.requirementPacketHash === 'pkt-new' && m.gateFrontier === 7 &&
        ar && ar.overall === 'ready') {
      ws.close(); process.exit(0);
    }
  } catch {}
};
ws.onerror = () => process.exit(1);

// 等初始 snapshot 到后修改文件
setTimeout(async () => {
  await Bun.write('${TMP_PROJECT}/openspec/changes/test-change/context/state-snapshot.json',
    JSON.stringify({schema_version:'1.0',snapshot_hash:'hash-new',gate_frontier:7,next_action:'phase7',requirement_packet_hash:'pkt-new',phase_results:{},review_status:null,fixup_status:null,archive_status:null,recovery_confidence:null}));
  await Bun.write('${TMP_PROJECT}/openspec/changes/test-change/context/archive-readiness.json',
    JSON.stringify({timestamp:'2026-01-01T01:00:00Z',mode:'full',checks:{all_checkpoints_ok:true,fixup_completeness:{passed:true,fixup_count:3,checkpoint_count:3},anchor_valid:true,worktree_clean:true,review_findings_clear:true,zero_skip_passed:true},overall:'ready',block_reasons:[]}));
}, 500);

setTimeout(() => { ws.close(); process.exit(0); }, 6000);
" 2>/dev/null

# 检查收到了多少条 WS 消息
MSG_COUNT=$(ls "$TMP_PROJECT/_ws_out/long_"*.json 2>/dev/null | wc -l | tr -d ' ')

if [ "$MSG_COUNT" -ge 2 ]; then
  green "  PASS: 2a. 修改 meta 文件后 WS 收到 ≥2 条消息 (共 $MSG_COUNT 条)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2a. 修改 meta 文件后 WS 仅收到 $MSG_COUNT 条消息，预期 ≥2"
  FAIL=$((FAIL + 1))
fi

# 检查最后一条 snapshot 的 meta 新值
LAST_MSG_FILE=$(ls "$TMP_PROJECT/_ws_out/long_"*.json 2>/dev/null | sort -V | tail -1)
if [ -n "$LAST_MSG_FILE" ] && [ -f "$LAST_MSG_FILE" ]; then
  LAST_META=$(cat "$LAST_MSG_FILE" | python3 -c "
import json, sys
msg = json.load(sys.stdin)
m = msg.get('meta', {})
ar = m.get('archiveReadiness', {})
print(f\"pkt={m.get('requirementPacketHash','')},gf={m.get('gateFrontier','')},ar={ar.get('overall','') if isinstance(ar, dict) else ''}\")
" 2>/dev/null || echo "ERROR")

  if grep -q "pkt=pkt-new" <<< "$LAST_META"; then
    green "  PASS: 2b. 最新 snapshot requirementPacketHash = pkt-new"
    PASS=$((PASS + 1))
  else
    red "  FAIL: 2b. 最新 snapshot requirementPacketHash 不正确 (got: $LAST_META)"
    FAIL=$((FAIL + 1))
  fi

  if grep -q "gf=7" <<< "$LAST_META"; then
    green "  PASS: 2c. 最新 snapshot gateFrontier = 7"
    PASS=$((PASS + 1))
  else
    red "  FAIL: 2c. 最新 snapshot gateFrontier 不正确 (got: $LAST_META)"
    FAIL=$((FAIL + 1))
  fi

  if grep -q "ar=ready" <<< "$LAST_META"; then
    green "  PASS: 2d. 最新 snapshot archiveReadiness.overall = ready"
    PASS=$((PASS + 1))
  else
    red "  FAIL: 2d. 最新 snapshot archiveReadiness.overall 不正确 (got: $LAST_META)"
    FAIL=$((FAIL + 1))
  fi
else
  red "  FAIL: 2b-2d. 无有效的 WS 消息文件"
  FAIL=$((FAIL + 3))
fi

# === 测试 3: /api/info 与 WS snapshot meta 一致 ===
sleep 0.5
API_INFO=$(curl -s --max-time 3 "http://localhost:${HTTP_PORT}/api/info" 2>/dev/null || echo "{}")

if grep -q "pkt-new" <<< "$API_INFO"; then
  green "  PASS: 3a. /api/info requirementPacketHash = pkt-new"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3a. /api/info requirementPacketHash 不正确 (got: $API_INFO)"
  FAIL=$((FAIL + 1))
fi

if echo "$API_INFO" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d.get('gateFrontier')==7 else 1)" 2>/dev/null; then
  green "  PASS: 3b. /api/info gateFrontier = 7"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3b. /api/info gateFrontier 不正确"
  FAIL=$((FAIL + 1))
fi

AR_OVERALL=$(echo "$API_INFO" | python3 -c "
import json, sys
d = json.load(sys.stdin)
ar = d.get('archiveReadiness', {})
print(ar.get('overall', '') if isinstance(ar, dict) else '')
" 2>/dev/null || echo "")
if [ "$AR_OVERALL" = "ready" ]; then
  green "  PASS: 3c. /api/info archiveReadiness.overall = ready (与 WS snapshot 一致)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3c. /api/info archiveReadiness.overall 不正确 (got: $AR_OVERALL)"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0
