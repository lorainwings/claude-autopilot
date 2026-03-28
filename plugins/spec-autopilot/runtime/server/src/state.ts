/**
 * state.ts — 共享可变状态
 */

import type { ServerWebSocket } from "bun";
import type { SessionSnapshot } from "./types";

export const wsClients = new Set<ServerWebSocket<unknown>>();

export let snapshotState: SessionSnapshot = {
  sessionId: null,
  sessionKey: null,
  changeName: "unknown",
  mode: "full",
  events: [],
  journalPath: null,
  telemetryAvailable: false,
  transcriptAvailable: false,
  stateSnapshot: null,
  archiveReadiness: null,
};

export function setSnapshotState(next: SessionSnapshot) {
  snapshotState = next;
}

export let refreshInFlight = false;
export let dirtyWhileInFlight = false;

export function setRefreshInFlight(v: boolean) {
  refreshInFlight = v;
}

export function setDirtyWhileInFlight(v: boolean) {
  dirtyWhileInFlight = v;
}

export let pluginVersionCache = "unknown";

export function setPluginVersionCache(v: string) {
  pluginVersionCache = v;
}
