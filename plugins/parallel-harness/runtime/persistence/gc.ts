/**
 * parallel-harness: Garbage Collector
 *
 * 清理过期的 run 记录和 audit 日志，防止 .parallel-harness/data/ 无限增长。
 */

import type { RunStore, AuditTrail } from "./session-persistence";
import type { JournalStore } from "./session-persistence";
import type { AuditEvent } from "../schemas/ga-schemas";

export interface GCOptions {
  /** 保留最近 N 次 run 记录（默认 50） */
  maxRuns: number;
  /** audit 日志保留天数（默认 30） */
  auditRetentionDays: number;
}

const DEFAULT_GC_OPTIONS: GCOptions = {
  maxRuns: 50,
  auditRetentionDays: 30,
};

export interface GCResult {
  runsDeleted: number;
  auditEventsPurged: number;
}

/**
 * 执行 GC 清理。
 * 在 OrchestratorRuntime 初始化时调用。
 */
export async function runGC(
  runStore: RunStore,
  auditTrail: AuditTrail,
  options?: Partial<GCOptions>,
): Promise<GCResult> {
  const opts = { ...DEFAULT_GC_OPTIONS, ...options };
  const result: GCResult = { runsDeleted: 0, auditEventsPurged: 0 };

  // 1. 清理超出 maxRuns 的旧 run 记录
  try {
    const records = await runStore.listRecords();
    if (records.length > opts.maxRuns) {
      // 按 updated_at 排序，保留最新的 maxRuns 条
      const sorted = records.sort((a, b) =>
        new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime()
      );
      const toDelete = sorted.slice(opts.maxRuns);
      for (const record of toDelete) {
        await runStore.deleteRun(record.run_id);
        result.runsDeleted++;
      }
    }
  } catch { /* GC 失败不阻断主流程 */ }

  // 2. 清理 audit 日志中超过保留期的事件
  try {
    // 获取 auditTrail 内部的 store，如果是 JournalStore 则使用 purgeOlderThan
    const store = (auditTrail as any).store;
    if (store && typeof store.purgeOlderThan === "function") {
      const cutoff = new Date();
      cutoff.setDate(cutoff.getDate() - opts.auditRetentionDays);
      result.auditEventsPurged = await (store as JournalStore<AuditEvent>).purgeOlderThan(cutoff);
    }
  } catch { /* GC 失败不阻断主流程 */ }

  return result;
}
