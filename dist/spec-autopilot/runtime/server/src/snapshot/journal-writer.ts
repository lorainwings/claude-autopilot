/**
 * journal-writer.ts — Journal 文件写入
 *
 * 支持增量追加：跟踪已写入的事件数量，仅追加新事件行。
 * Session 切换时通过 resetJournalState() 重置。
 */

import { appendFile, mkdir, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { SESSIONS_DIR } from "../config";
import type { AutopilotEvent } from "../types";

/** 每个 session 的 journal 写入状态 */
interface JournalState {
  writtenCount: number;
}

const journalStates = new Map<string, JournalState>();

export async function writeJournal(sessionKey: string, events: AutopilotEvent[]): Promise<string> {
  const journalDir = join(SESSIONS_DIR, sessionKey, "journal");
  const journalPath = join(journalDir, "events.jsonl");
  await mkdir(journalDir, { recursive: true });

  const state = journalStates.get(sessionKey);
  const writtenCount = state?.writtenCount ?? 0;

  if (events.length <= writtenCount) {
    // 没有新事件，无需写入
    return journalPath;
  }

  if (writtenCount === 0) {
    // 首次写入：全量写
    const content = events.map((event) => JSON.stringify(event)).join("\n");
    const contentBody = content ? `${content}\n` : "";
    await writeFile(journalPath, contentBody, "utf-8");
  } else {
    // 增量追加：仅写入新事件
    const newEvents = events.slice(writtenCount);
    const appendContent = newEvents.map((event) => JSON.stringify(event)).join("\n") + "\n";
    await appendFile(journalPath, appendContent, "utf-8");
  }

  journalStates.set(sessionKey, { writtenCount: events.length });
  return journalPath;
}

/** 重置 journal 状态（session 切换时调用） */
export function resetJournalState(sessionKey?: string) {
  if (sessionKey) {
    journalStates.delete(sessionKey);
  } else {
    journalStates.clear();
  }
}
