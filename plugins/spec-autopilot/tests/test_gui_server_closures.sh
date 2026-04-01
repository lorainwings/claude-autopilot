#!/usr/bin/env bash
# TEST_LAYER: behavior
# test_gui_server_closures.sh — GUI/Server 编排状态闭环测试 (Workstream H)
# 验证:
#   H-3: snapshot-builder 使用 config.ts 的 projectRoot（而非仅依赖 env var）
#   H-2: archive_readiness 从 archive-readiness.json 读取并暴露到 SessionSnapshot
#   H-1: requirement_packet_hash 在 SKILL.md Phase 1 phase_end payload 中出现
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
SERVER_SRC_DIR="$(cd "$TEST_DIR/../runtime/server/src" && pwd)"
source "$TEST_DIR/_test_helpers.sh"

echo "--- GUI/Server 编排状态闭环测试 (Workstream H) ---"

# ============================================================
# H-3: snapshot-builder.ts 使用 config.ts 的 projectRoot
# ============================================================
echo ""
echo "  [H-3] snapshot-builder 使用 config.ts projectRoot"

# H-3a: snapshot-builder.ts 导入了 config.ts 的 projectRoot
if grep -q "projectRoot as configProjectRoot" "$SERVER_SRC_DIR/snapshot/snapshot-builder.ts"; then
  green "  PASS: H-3a. snapshot-builder 导入 config.ts 的 projectRoot"
  PASS=$((PASS + 1))
else
  red "  FAIL: H-3a. snapshot-builder 未导入 config.ts 的 projectRoot"
  FAIL=$((FAIL + 1))
fi

# H-3b: snapshot-builder.ts 优先使用 configProjectRoot，env var 作 fallback
if grep -q "configProjectRoot || process.env.AUTOPILOT_PROJECT_ROOT" "$SERVER_SRC_DIR/snapshot/snapshot-builder.ts"; then
  green "  PASS: H-3b. configProjectRoot 优先，env var 作 fallback"
  PASS=$((PASS + 1))
else
  red "  FAIL: H-3b. 未正确实现 projectRoot fallback 链"
  FAIL=$((FAIL + 1))
fi

# H-3c: config.ts 导出 projectRoot
if grep -q "export const projectRoot" "$SERVER_SRC_DIR/config.ts"; then
  green "  PASS: H-3c. config.ts 导出 projectRoot"
  PASS=$((PASS + 1))
else
  red "  FAIL: H-3c. config.ts 未导出 projectRoot"
  FAIL=$((FAIL + 1))
fi

# H-3d: config.ts 解析 --project-root CLI 参数
if grep -q '\-\-project-root' "$SERVER_SRC_DIR/config.ts"; then
  green "  PASS: H-3d. config.ts 解析 --project-root CLI 参数"
  PASS=$((PASS + 1))
else
  red "  FAIL: H-3d. config.ts 未解析 --project-root"
  FAIL=$((FAIL + 1))
fi

# ============================================================
# H-2: archive_readiness 闭环
# ============================================================
echo ""
echo "  [H-2] archive_readiness 闭环"

# H-2a: ArchiveReadiness 类型定义存在
if grep -q "export interface ArchiveReadiness" "$SERVER_SRC_DIR/types.ts"; then
  green "  PASS: H-2a. ArchiveReadiness 类型已定义"
  PASS=$((PASS + 1))
else
  red "  FAIL: H-2a. ArchiveReadiness 类型未定义"
  FAIL=$((FAIL + 1))
fi

# H-2b: SessionSnapshot 包含 archiveReadiness 字段
if grep -q "archiveReadiness: ArchiveReadiness | null" "$SERVER_SRC_DIR/types.ts"; then
  green "  PASS: H-2b. SessionSnapshot 包含 archiveReadiness 字段"
  PASS=$((PASS + 1))
else
  red "  FAIL: H-2b. SessionSnapshot 缺少 archiveReadiness 字段"
  FAIL=$((FAIL + 1))
fi

# H-2c: snapshot-builder 读取 archive-readiness.json
if grep -q "archive-readiness.json" "$SERVER_SRC_DIR/snapshot/snapshot-builder.ts"; then
  green "  PASS: H-2c. snapshot-builder 读取 archive-readiness.json"
  PASS=$((PASS + 1))
else
  red "  FAIL: H-2c. snapshot-builder 未读取 archive-readiness.json"
  FAIL=$((FAIL + 1))
fi

# H-2d: state.ts 初始值包含 archiveReadiness: null
if grep -q "archiveReadiness: null" "$SERVER_SRC_DIR/state.ts"; then
  green "  PASS: H-2d. state.ts 初始值包含 archiveReadiness: null"
  PASS=$((PASS + 1))
else
  red "  FAIL: H-2d. state.ts 缺少 archiveReadiness 初始值"
  FAIL=$((FAIL + 1))
fi

# H-2e: /api/info 暴露 archiveReadiness
if grep -q "archiveReadiness:" "$SERVER_SRC_DIR/api/routes.ts"; then
  green "  PASS: H-2e. /api/info 暴露 archiveReadiness"
  PASS=$((PASS + 1))
else
  red "  FAIL: H-2e. /api/info 未暴露 archiveReadiness"
  FAIL=$((FAIL + 1))
fi

# H-2f: broadcaster.ts 在 snapshot meta 中包含 archiveReadiness
if grep -q "archiveReadiness" "$SERVER_SRC_DIR/ws/broadcaster.ts"; then
  green "  PASS: H-2f. WS snapshot meta 包含 archiveReadiness"
  PASS=$((PASS + 1))
else
  red "  FAIL: H-2f. WS snapshot meta 缺少 archiveReadiness"
  FAIL=$((FAIL + 1))
fi

# H-2g: ws-server.ts 初始连接 snapshot 也带 meta
if grep -q "meta" "$SERVER_SRC_DIR/ws/ws-server.ts"; then
  green "  PASS: H-2g. ws-server 初始连接 snapshot 带 meta"
  PASS=$((PASS + 1))
else
  red "  FAIL: H-2g. ws-server 初始连接 snapshot 缺少 meta"
  FAIL=$((FAIL + 1))
fi

# H-2h: GUI store 中有 initOrchestrationFromMeta
GUI_STORE="$TEST_DIR/../gui/src/store/index.ts"
if grep -q "initOrchestrationFromMeta" "$GUI_STORE"; then
  green "  PASS: H-2h. GUI store 实现 initOrchestrationFromMeta"
  PASS=$((PASS + 1))
else
  red "  FAIL: H-2h. GUI store 缺少 initOrchestrationFromMeta"
  FAIL=$((FAIL + 1))
fi

# H-2i: GUI ws-bridge 支持 onMeta handler
GUI_WS_BRIDGE="$TEST_DIR/../gui/src/lib/ws-bridge.ts"
if grep -q "onMeta" "$GUI_WS_BRIDGE"; then
  green "  PASS: H-2i. GUI ws-bridge 支持 onMeta"
  PASS=$((PASS + 1))
else
  red "  FAIL: H-2i. GUI ws-bridge 缺少 onMeta"
  FAIL=$((FAIL + 1))
fi

# ============================================================
# H-1: requirement_packet_hash 闭环
# ============================================================
echo ""
echo "  [H-1] requirement_packet_hash 闭环"

# H-1a: SKILL.md Phase 1 步骤 10 payload 包含 requirement_packet_hash
SKILL_MD="$TEST_DIR/../skills/autopilot/SKILL.md"
if grep -q 'requirement_packet_hash' "$SKILL_MD"; then
  green "  PASS: H-1a. SKILL.md Phase 1 emit payload 包含 requirement_packet_hash"
  PASS=$((PASS + 1))
else
  red "  FAIL: H-1a. SKILL.md Phase 1 emit payload 缺少 requirement_packet_hash"
  FAIL=$((FAIL + 1))
fi

# H-1b: SKILL.md Phase 1 步骤 10 是 phase_end 事件且包含 requirement_packet_hash
if grep -A2 "phase_end 1" "$SKILL_MD" | grep -q "requirement_packet_hash"; then
  green "  PASS: H-1b. Phase 1 phase_end payload 明确包含 requirement_packet_hash"
  PASS=$((PASS + 1))
else
  red "  FAIL: H-1b. Phase 1 phase_end payload 未包含 requirement_packet_hash"
  FAIL=$((FAIL + 1))
fi

# H-1c: /api/info 暴露 requirementPacketHash
if grep -q "requirementPacketHash" "$SERVER_SRC_DIR/api/routes.ts"; then
  green "  PASS: H-1c. /api/info 暴露 requirementPacketHash"
  PASS=$((PASS + 1))
else
  red "  FAIL: H-1c. /api/info 未暴露 requirementPacketHash"
  FAIL=$((FAIL + 1))
fi

# H-1d: WS snapshot meta 包含 requirementPacketHash
if grep -q "requirementPacketHash" "$SERVER_SRC_DIR/ws/broadcaster.ts"; then
  green "  PASS: H-1d. WS snapshot meta 包含 requirementPacketHash"
  PASS=$((PASS + 1))
else
  red "  FAIL: H-1d. WS snapshot meta 缺少 requirementPacketHash"
  FAIL=$((FAIL + 1))
fi

# H-1e: GUI store 仍保留从 phase_end 事件提取 requirementPacketHash 的逻辑
if grep -q 'event.type === "phase_end" && event.phase === 1' "$GUI_STORE"; then
  green "  PASS: H-1e. GUI store 保留 phase_end(phase=1) 事件提取逻辑"
  PASS=$((PASS + 1))
else
  red "  FAIL: H-1e. GUI store 缺少 phase_end(phase=1) 提取逻辑"
  FAIL=$((FAIL + 1))
fi

# H-1f: GUI store initOrchestrationFromMeta 处理 requirementPacketHash 的 fallback
if grep -q "meta.requirementPacketHash" "$GUI_STORE"; then
  green "  PASS: H-1f. GUI store initOrchestrationFromMeta 处理 requirementPacketHash fallback"
  PASS=$((PASS + 1))
else
  red "  FAIL: H-1f. GUI store 缺少 requirementPacketHash meta fallback"
  FAIL=$((FAIL + 1))
fi

# ============================================================
# TypeScript 类型检查
# ============================================================
echo ""
echo "  [TS] TypeScript 类型检查"

# 检查 server 端（先确保依赖已安装）
(cd "$TEST_DIR/../runtime/server" && bun install --frozen-lockfile 2>/dev/null || bun install 2>/dev/null) >/dev/null
TS_SERVER_OUTPUT=$(cd "$TEST_DIR/../runtime/server" && bunx tsc --noEmit 2>&1)
TS_SERVER_EXIT=$?
if [ "$TS_SERVER_EXIT" -eq 0 ]; then
  green "  PASS: TS-a. Server TypeScript 零错误"
  PASS=$((PASS + 1))
else
  red "  FAIL: TS-a. Server TypeScript 有错误: $TS_SERVER_OUTPUT"
  FAIL=$((FAIL + 1))
fi

# 检查 GUI 端（先确保依赖已安装）
(cd "$TEST_DIR/../gui" && bun install --frozen-lockfile 2>/dev/null || bun install 2>/dev/null) >/dev/null
TS_GUI_OUTPUT=$(cd "$TEST_DIR/../gui" && bunx tsc --noEmit 2>&1)
TS_GUI_EXIT=$?
if [ "$TS_GUI_EXIT" -eq 0 ]; then
  green "  PASS: TS-b. GUI TypeScript 零错误"
  PASS=$((PASS + 1))
else
  red "  FAIL: TS-b. GUI TypeScript 有错误: $TS_GUI_OUTPUT"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0
