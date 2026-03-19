/**
 * decision-service.ts — 决策写入与 ack 广播
 */

import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { CHANGES_DIR, LOCK_FILE } from "../config";
import { wsClients } from "../state";
import { safeJsonParse } from "../utils";

export async function resolveDecisionFile(): Promise<string | null> {
  try {
    const content = await readFile(LOCK_FILE, "utf-8");
    const parsed = safeJsonParse<Record<string, unknown>>(content);
    const changeName = parsed && typeof parsed.change === "string" ? parsed.change : content.trim();
    if (!changeName) return null;
    return join(CHANGES_DIR, changeName, "context", "decision.json");
  } catch {
    return null;
  }
}

export async function handleDecision(decision: { action: string; phase: number; reason?: string }) {
  try {
    const decisionFile = await resolveDecisionFile();
    if (!decisionFile) return;
    await mkdir(dirname(decisionFile), { recursive: true });
    await writeFile(decisionFile, JSON.stringify(decision, null, 2), "utf-8");

    const ackMessage = JSON.stringify({
      type: "decision_ack",
      data: {
        action: decision.action,
        phase: decision.phase,
        timestamp: new Date().toISOString(),
      },
    });
    for (const ws of wsClients) {
      try {
        ws.send(ackMessage);
      } catch {
        wsClients.delete(ws);
      }
    }
  } catch (error) {
    console.error("  ❌ Failed to write decision:", error);
  }
}
