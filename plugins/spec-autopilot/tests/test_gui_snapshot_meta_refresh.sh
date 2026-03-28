#!/usr/bin/env bash
# test_gui_snapshot_meta_refresh.sh — 真实集成测试: 已连接 GUI 的 meta-only 增量刷新
# 验证:
#   1. WS 初始连接收到 snapshot（含 meta 字段）
#   2. 仅修改 state-snapshot.json / archive-readiness.json（不追加 event）
#   3. 同一 WS 连接收到第二条 snapshot
#   4. 新 meta 值正确进入 GUI 可消费字段
#
# 依赖: bun（server 运行时）
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$TEST_DIR/.." && pwd)"
SERVER_DIR="$PLUGIN_DIR/runtime/server"
source "$TEST_DIR/_test_helpers.sh"

echo "--- GUI snapshot meta refresh integration test ---"

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
mkdir -p "$TMP_PROJECT/_ws_out"

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

# === 写入全合一测试脚本（server + client） ===
cat >"$TMP_PROJECT/_test_all.ts" <<TSEOF
import { join } from "node:path";
import { existsSync, readFileSync, writeFileSync } from "node:fs";

const ROOT = "${TMP_PROJECT}";
const HP = ${HTTP_PORT};
const WP = ${WS_PORT};

// --- 简化 server ---
type Snap = { stateSnapshot: any; archiveReadiness: any; events: any[] };
let snap: Snap = { stateSnapshot: null, archiveReadiness: null, events: [] };
const clients = new Set<any>();

function meta() {
  return {
    archiveReadiness: snap.archiveReadiness ?? null,
    requirementPacketHash: snap.stateSnapshot?.requirement_packet_hash ?? null,
    gateFrontier: snap.stateSnapshot?.gate_frontier ?? null,
  };
}

function broadcast() {
  const p = JSON.stringify({ type: "snapshot", data: snap.events, meta: meta() });
  for (const ws of clients) { try { ws.send(p); } catch { clients.delete(ws); } }
}

function readFiles(): Snap {
  const dir = join(ROOT, "openspec/changes/test-change/context");
  let ss = null, ar = null;
  try { ss = JSON.parse(readFileSync(join(dir, "state-snapshot.json"), "utf-8")); } catch {}
  try { ar = JSON.parse(readFileSync(join(dir, "archive-readiness.json"), "utf-8")); } catch {}
  return { stateSnapshot: ss, archiveReadiness: ar, events: [] };
}

let refreshing = false;
function refresh(force = false) {
  if (refreshing) return;
  refreshing = true;
  try {
    const prev = snap;
    const next = readFiles();
    const metaChanged =
      JSON.stringify(prev.archiveReadiness) !== JSON.stringify(next.archiveReadiness) ||
      JSON.stringify(prev.stateSnapshot) !== JSON.stringify(next.stateSnapshot);
    snap = next;
    if (force || metaChanged) broadcast();
  } finally { refreshing = false; }
}

// 初始读取
snap = readFiles();

const wsSrv = Bun.serve({
  port: WP,
  fetch(req, server) {
    if (server.upgrade(req)) return undefined;
    return new Response("WS only", { status: 426 });
  },
  websocket: {
    open(ws: any) {
      clients.add(ws);
      ws.send(JSON.stringify({ type: "snapshot", data: snap.events, meta: meta() }));
    },
    close(ws: any) { clients.delete(ws); },
    message() {},
  },
});

const httpSrv = Bun.serve({
  port: HP,
  fetch(req) {
    const u = new URL(req.url);
    if (u.pathname === "/api/info") return Response.json(meta());
    if (u.pathname === "/api/health") return Response.json({ status: "ok" });
    return new Response("Not found", { status: 404 });
  },
});

// 轮询
const poll = setInterval(() => refresh(), 300);

// 写入就绪信号
writeFileSync(join(ROOT, "_ready"), "1");

process.on("SIGTERM", () => { clearInterval(poll); wsSrv.stop(); httpSrv.stop(); process.exit(0); });
TSEOF

# === 启动 server ===
bun run "$TMP_PROJECT/_test_all.ts" >/dev/null 2>&1 &
SERVER_PID=$!

# 等待就绪
WAITED=0
while [ "$WAITED" -lt 50 ] && [ ! -f "$TMP_PROJECT/_ready" ]; do
  sleep 0.1
  WAITED=$((WAITED + 1))
done

if [ ! -f "$TMP_PROJECT/_ready" ]; then
  red "  FAIL: server did not start within 5s"
  echo "Results: 0 passed, 1 failed"
  exit 1
fi

green "  PASS: server started on HTTP:$HTTP_PORT WS:$WS_PORT"
PASS=$((PASS + 1))

# === 测试 1: WS 初始 snapshot 包含旧 meta ===
bun -e "
const ws = new WebSocket('ws://localhost:${WS_PORT}');
ws.onmessage = (e: any) => {
  Bun.write('${TMP_PROJECT}/_ws_out/msg1.json', e.data);
  ws.close();
};
ws.onerror = () => process.exit(1);
setTimeout(() => { ws.close(); process.exit(1); }, 3000);
" 2>/dev/null
sleep 0.3

if [ -f "$TMP_PROJECT/_ws_out/msg1.json" ]; then
  MSG1=$(cat "$TMP_PROJECT/_ws_out/msg1.json")
  if echo "$MSG1" | grep -q '"type":"snapshot"'; then
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
  FAIL=$((FAIL + 2))
fi

# === 测试 2: 仅修改 meta 文件 → WS 收到第二条 snapshot ===
# 建立长连接，写入消息到文件
bun -e "
import { appendFileSync } from 'node:fs';
let count = 0;
const ws = new WebSocket('ws://localhost:${WS_PORT}');
ws.onmessage = (e: any) => {
  count++;
  Bun.write('${TMP_PROJECT}/_ws_out/long_msg_' + count + '.json', e.data);
  if (count >= 2) { ws.close(); process.exit(0); }
};
ws.onerror = () => process.exit(1);

// 等初始 snapshot 到后修改文件
setTimeout(async () => {
  await Bun.write('${TMP_PROJECT}/openspec/changes/test-change/context/state-snapshot.json',
    JSON.stringify({schema_version:'1.0',snapshot_hash:'hash-new',gate_frontier:7,next_action:'phase7',requirement_packet_hash:'pkt-new',phase_results:{},review_status:null,fixup_status:null,archive_status:null,recovery_confidence:null}));
  await Bun.write('${TMP_PROJECT}/openspec/changes/test-change/context/archive-readiness.json',
    JSON.stringify({timestamp:'2026-01-01T01:00:00Z',mode:'full',checks:{all_checkpoints_ok:true,fixup_completeness:{passed:true,fixup_count:3,checkpoint_count:3},anchor_valid:true,worktree_clean:true,review_findings_clear:true,zero_skip_passed:true},overall:'ready',block_reasons:[]}));
}, 500);

setTimeout(() => { ws.close(); process.exit(0); }, 5000);
" 2>/dev/null

# 检查收到了多少条 WS 消息
MSG_COUNT=$(ls "$TMP_PROJECT/_ws_out/long_msg_"*.json 2>/dev/null | wc -l | tr -d ' ')

if [ "$MSG_COUNT" -ge 2 ]; then
  green "  PASS: 2a. 修改 meta 文件后 WS 收到 ≥2 条消息 (共 $MSG_COUNT 条)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2a. 修改 meta 文件后 WS 仅收到 $MSG_COUNT 条消息，预期 ≥2"
  FAIL=$((FAIL + 1))
fi

# 检查最后一条 snapshot 的 meta 新值
LAST_MSG_FILE=$(ls "$TMP_PROJECT/_ws_out/long_msg_"*.json 2>/dev/null | sort -V | tail -1)
if [ -n "$LAST_MSG_FILE" ] && [ -f "$LAST_MSG_FILE" ]; then
  LAST_META=$(cat "$LAST_MSG_FILE" | python3 -c "
import json, sys
msg = json.load(sys.stdin)
m = msg.get('meta', {})
ar = m.get('archiveReadiness', {})
print(f\"pkt={m.get('requirementPacketHash','')},gf={m.get('gateFrontier','')},ar={ar.get('overall','') if isinstance(ar, dict) else ''}\")
" 2>/dev/null || echo "ERROR")

  if echo "$LAST_META" | grep -q "pkt=pkt-new"; then
    green "  PASS: 2b. 最新 snapshot requirementPacketHash = pkt-new"
    PASS=$((PASS + 1))
  else
    red "  FAIL: 2b. 最新 snapshot requirementPacketHash 不正确 (got: $LAST_META)"
    FAIL=$((FAIL + 1))
  fi

  if echo "$LAST_META" | grep -q "gf=7"; then
    green "  PASS: 2c. 最新 snapshot gateFrontier = 7"
    PASS=$((PASS + 1))
  else
    red "  FAIL: 2c. 最新 snapshot gateFrontier 不正确 (got: $LAST_META)"
    FAIL=$((FAIL + 1))
  fi

  if echo "$LAST_META" | grep -q "ar=ready"; then
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

# === 测试 3: /api/info 也反映新值 ===
# 先等轮询周期（300ms 轮询 + 余量）
sleep 0.5
API_INFO=$(curl -s --max-time 3 "http://localhost:${HTTP_PORT}/api/info" 2>/dev/null || echo "{}")

if echo "$API_INFO" | grep -q "pkt-new"; then
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

# === 测试 4: bootstrap.ts 源码验证 meta 变化检测逻辑 ===
BOOTSTRAP="$PLUGIN_DIR/runtime/server/src/bootstrap.ts"

if grep -q "metaChanged" "$BOOTSTRAP"; then
  green "  PASS: 4a. bootstrap.ts 包含 metaChanged 检测逻辑"
  PASS=$((PASS + 1))
else
  red "  FAIL: 4a. bootstrap.ts 缺少 metaChanged 检测逻辑"
  FAIL=$((FAIL + 1))
fi

if grep -q 'metaChanged && added.length === 0' "$BOOTSTRAP"; then
  green "  PASS: 4b. bootstrap.ts 在 meta 变化且无新 event 时广播 snapshot"
  PASS=$((PASS + 1))
else
  red "  FAIL: 4b. bootstrap.ts 缺少 meta-only 广播逻辑"
  FAIL=$((FAIL + 1))
fi

if ! grep -q 'watch(CHANGES_DIR, { recursive: false }' "$BOOTSTRAP"; then
  green "  PASS: 4c. CHANGES_DIR watch 不再使用 recursive: false"
  PASS=$((PASS + 1))
else
  red "  FAIL: 4c. CHANGES_DIR watch 仍使用 recursive: false"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0
