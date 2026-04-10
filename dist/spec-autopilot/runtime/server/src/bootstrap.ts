/**
 * bootstrap.ts — 服务器启动编排：刷新循环 + 初始化 + 信号处理
 */

import { watch } from "node:fs";
import { mkdir } from "node:fs/promises";
import { spawn } from "node:child_process";

import { autoOpen, CHANGES_DIR, HTTP_PORT, LOGS_DIR, POLL_INTERVAL_MS, projectRoot, EVENTS_FILE, SESSIONS_DIR, WS_PORT } from "./config";
import { dirtyWhileInFlight, refreshInFlight, setDirtyWhileInFlight, setRefreshInFlight, setSnapshotState, snapshotState } from "./state";
import { buildSnapshot } from "./snapshot/snapshot-builder";
import { broadcastEvents, broadcastReset, broadcastSnapshot } from "./ws/broadcaster";
import { ensurePluginVersion } from "./session/session-context";
import { resetFileCursors } from "./session/file-cache";
import { resetJournalState } from "./snapshot/journal-writer";
import { createWsServer } from "./ws/ws-server";
import { createHttpServer } from "./api/routes";

export async function refreshSnapshot(forceSnapshot = false) {
  if (refreshInFlight) {
    setDirtyWhileInFlight(true);
    return;
  }
  setRefreshInFlight(true);
  try {
    const prev = snapshotState;
    let next;
    try {
      next = await buildSnapshot();
    } catch (err) {
      const errObj = err instanceof Error ? err : new Error(String(err));
      console.error(JSON.stringify({
        timestamp: new Date().toISOString(),
        level: "error",
        component: "snapshot-builder",
        event: "snapshot_build_error",
        message: errObj.message,
        stack: errObj.stack?.split("\n").slice(0, 5).join("\n"),
      }));
      return;
    }

    const sessionChanged = next.sessionId !== prev.sessionId;

    // Session 切换 → 重置所有文件游标和 journal 状态
    if (sessionChanged) {
      console.error(
        `[${new Date().toISOString()}] [session_switch] ${prev.sessionId ?? "none"} → ${next.sessionId ?? "none"} (reason: active session changed)`,
      );
      resetFileCursors();
      resetJournalState();
      // 重新构建以获取干净的新 session 数据
      let fresh;
      try {
        fresh = await buildSnapshot();
      } catch (err) {
        const errObj = err instanceof Error ? err : new Error(String(err));
        console.error(JSON.stringify({
          timestamp: new Date().toISOString(),
          level: "error",
          component: "snapshot-builder",
          event: "snapshot_rebuild_error",
          message: errObj.message,
          context: "post-session-switch rebuild",
        }));
        return;
      }
      setSnapshotState(fresh);
      broadcastReset();
      broadcastSnapshot(fresh.events);
      return;
    }

    const prevIds = new Set(prev.events.map((event) => event.event_id));
    const added = next.events.filter((event) => !prevIds.has(event.event_id));

    // 检测 meta 变化（archiveReadiness / stateSnapshot）
    const metaChanged =
      JSON.stringify(prev.archiveReadiness) !== JSON.stringify(next.archiveReadiness) ||
      JSON.stringify(prev.stateSnapshot) !== JSON.stringify(next.stateSnapshot);

    setSnapshotState(next);

    if (forceSnapshot) {
      broadcastSnapshot(next.events);
      return;
    }

    if (added.length > 0) {
      broadcastEvents(added);
    }

    // meta 变化时广播 snapshot（含 v7.1 清晰度指标等编排数据）
    // v7.1 修复: 即使有新增 event 也需要广播 meta，否则同时发生的 meta 变化会被丢弃
    if (metaChanged) {
      broadcastSnapshot(next.events);
    }
  } finally {
    setRefreshInFlight(false);
    if (dirtyWhileInFlight) {
      setDirtyWhileInFlight(false);
      refreshSnapshot().catch(() => undefined);
    }
  }
}

function startRefreshLoop() {
  setInterval(() => {
    refreshSnapshot().catch(() => undefined);
  }, POLL_INTERVAL_MS);

  try {
    watch(LOGS_DIR, { recursive: true }, () => {
      refreshSnapshot().catch(() => undefined);
    });
  } catch {
    // polling loop already covers this
  }

  try {
    watch(CHANGES_DIR, { recursive: true }, () => {
      refreshSnapshot(true).catch(() => undefined);
    });
  } catch {
    // polling loop already covers this
  }
}

export async function startServer() {
  await mkdir(SESSIONS_DIR, { recursive: true }).catch(() => undefined);
  await ensurePluginVersion();
  setSnapshotState(await buildSnapshot());
  startRefreshLoop();

  const wsServer = createWsServer();
  const httpServer = createHttpServer();

  if (autoOpen) {
    const url = `http://localhost:${HTTP_PORT}`;
    const platform = process.platform;
    const cmd = platform === "darwin" ? "open" : platform === "win32" ? "start" : "xdg-open";
    try {
      spawn(cmd, [url], { detached: true, stdio: "ignore" }).unref();
    } catch {
      // ignore
    }
  }

  console.log(`
  Autopilot 聚合服务器已启动
  ├─ HTTP  → http://localhost:${HTTP_PORT}
  ├─ WS    → ws://localhost:${WS_PORT}
  ├─ 健康  → http://localhost:${HTTP_PORT}/api/health
  ├─ PID   → ${process.pid}
  ├─ 项目  → ${projectRoot}
  ├─ 旧事件 → ${EVENTS_FILE}
  └─ 会话  → ${snapshotState.sessionId ?? "none"}
`);

  process.on("SIGINT", () => {
    console.log("\n  🛑 服务器已停止");
    wsServer.stop();
    httpServer.stop();
    process.exit(0);
  });

  process.on("SIGTERM", () => {
    wsServer.stop();
    httpServer.stop();
    process.exit(0);
  });
}
