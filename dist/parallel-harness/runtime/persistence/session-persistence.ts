/**
 * parallel-harness: Session Persistence & Audit Trail
 *
 * 持久化体系。从内存态升级为可持久化、可回放、可审计。
 * 至少支持本地持久化适配器，抽象未来数据库适配层。
 *
 * v2: RunStore 合并为单文件存储（runs/{run_id}.json），
 *     AuditTrail 改为 JSONL append-only（audit.jsonl）。
 */

import type {
  AuditEvent,
  SessionState,
  RunRequest,
  RunResult,
  RunExecution,
  RunPlan,
  TaskAttempt,
  GateResult,
  CostLedger,
} from "../schemas/ga-schemas";
import { generateId } from "../schemas/ga-schemas";

// ============================================================
// Store Interface — 持久化抽象层
// ============================================================

export interface Store<T> {
  get(id: string): Promise<T | undefined>;
  set(id: string, value: T): Promise<void>;
  delete(id: string): Promise<void>;
  list(filter?: Record<string, unknown>): Promise<T[]>;
  count(): Promise<number>;
}

// ============================================================
// Local Store — 本地持久化适配器
// ============================================================

export class LocalMemoryStore<T> implements Store<T> {
  private data: Map<string, T> = new Map();

  async get(id: string): Promise<T | undefined> {
    return this.data.get(id);
  }

  async set(id: string, value: T): Promise<void> {
    this.data.set(id, value);
  }

  async delete(id: string): Promise<void> {
    this.data.delete(id);
  }

  async list(_filter?: Record<string, unknown>): Promise<T[]> {
    return [...this.data.values()];
  }

  async count(): Promise<number> {
    return this.data.size;
  }

  clear(): void {
    this.data.clear();
  }
}

// ============================================================
// File-based Store — 文件系统持久化
// ============================================================

export class FileStore<T> implements Store<T> {
  private basePath: string;
  private cache: Map<string, T> = new Map();
  private initialized = false;

  constructor(basePath: string) {
    this.basePath = basePath;
  }

  /** 初始化：扫描目录加载所有已有数据到缓存 */
  private async ensureInitialized(): Promise<void> {
    if (this.initialized) return;
    this.initialized = true;
    try {
      const glob = new Bun.Glob("*.json");
      for await (const file of glob.scan({ cwd: this.basePath, absolute: true })) {
        try {
          const content = await Bun.file(file).text();
          const value = JSON.parse(content) as T;
          const id = file.replace(this.basePath + "/", "").replace(".json", "");
          this.cache.set(id, value);
        } catch { /* 忽略损坏文件 */ }
      }
    } catch { /* 目录不存在，忽略 */ }
  }

  async get(id: string): Promise<T | undefined> {
    await this.ensureInitialized();
    if (this.cache.has(id)) return this.cache.get(id);

    try {
      const filePath = `${this.basePath}/${id}.json`;
      const file = Bun.file(filePath);
      if (!(await file.exists())) return undefined;
      const content = await file.text();
      const value = JSON.parse(content) as T;
      this.cache.set(id, value);
      return value;
    } catch {
      return undefined;
    }
  }

  async set(id: string, value: T): Promise<void> {
    await this.ensureInitialized();
    this.cache.set(id, value);
    const filePath = `${this.basePath}/${id}.json`;
    await Bun.write(filePath, JSON.stringify(value, null, 2));
  }

  async delete(id: string): Promise<void> {
    await this.ensureInitialized();
    this.cache.delete(id);
    try {
      const filePath = `${this.basePath}/${id}.json`;
      const { unlinkSync } = await import("node:fs");
      unlinkSync(filePath);
    } catch { /* 文件可能不存在 */ }
  }

  async list(_filter?: Record<string, unknown>): Promise<T[]> {
    await this.ensureInitialized();
    return [...this.cache.values()];
  }

  async count(): Promise<number> {
    await this.ensureInitialized();
    return this.cache.size;
  }
}

// ============================================================
// Session Store
// ============================================================

export class SessionStore {
  private store: Store<SessionState>;

  constructor(store?: Store<SessionState>) {
    this.store = store || new LocalMemoryStore<SessionState>();
  }

  async save(session: SessionState): Promise<void> {
    session.last_active_at = new Date().toISOString();
    await this.store.set(session.session_id, session);
  }

  async get(sessionId: string): Promise<SessionState | undefined> {
    return this.store.get(sessionId);
  }

  async getByRunId(runId: string): Promise<SessionState | undefined> {
    const all = await this.store.list();
    return all.find((s) => s.run_id === runId);
  }

  async updateCheckpoint(sessionId: string, checkpoint: Record<string, unknown>): Promise<void> {
    const session = await this.store.get(sessionId);
    if (session) {
      session.checkpoint = { ...session.checkpoint, ...checkpoint };
      session.last_active_at = new Date().toISOString();
      await this.store.set(sessionId, session);
    }
  }

  async complete(sessionId: string): Promise<void> {
    const session = await this.store.get(sessionId);
    if (session) {
      session.status = "completed";
      session.last_active_at = new Date().toISOString();
      await this.store.set(sessionId, session);
    }
  }

  async listActive(): Promise<SessionState[]> {
    const all = await this.store.list();
    return all.filter((s) => s.status === "active");
  }

  static createDurable(basePath: string): SessionStore {
    return new SessionStore(new FileStore<SessionState>(basePath));
  }
}

// ============================================================
// Run Store — 按 run_id 聚合的单文件存储
// ============================================================

/** 聚合的 Run 记录，一次 run 的所有产物合并为单个文件 */
export interface RunRecord {
  run_id: string;
  request?: RunRequest;
  plan?: RunPlan;
  execution?: RunExecution;
  result?: RunResult;
  updated_at: string;
}

export class RunStore {
  private store: Store<RunRecord>;
  /** request_id → run_id 索引（内存） */
  private requestIndex: Map<string, string> = new Map();
  /** plan_id → run_id 索引（内存） */
  private planIndex: Map<string, string> = new Map();
  private indexBuilt = false;

  constructor(options?: {
    store?: Store<RunRecord>;
    /** @deprecated 向后兼容：独立 store 模式 */
    requestStore?: Store<RunRequest>;
    planStore?: Store<RunPlan>;
    executionStore?: Store<RunExecution>;
    resultStore?: Store<RunResult>;
  }) {
    if (options?.store) {
      this.store = options.store;
    } else if (options?.requestStore || options?.planStore || options?.executionStore || options?.resultStore) {
      // 向后兼容：测试中使用独立 store 模式，委托到 LegacyRunStoreAdapter
      this.store = new LegacyRunStoreAdapter(
        options.requestStore || new LocalMemoryStore(),
        options.planStore || new LocalMemoryStore(),
        options.executionStore || new LocalMemoryStore(),
        options.resultStore || new LocalMemoryStore(),
      );
    } else {
      this.store = new LocalMemoryStore<RunRecord>();
    }
  }

  /** 构建 ID 索引 */
  private async ensureIndex(): Promise<void> {
    if (this.indexBuilt) return;
    this.indexBuilt = true;
    const all = await this.store.list();
    for (const record of all) {
      if (record.request) {
        this.requestIndex.set(record.request.request_id, record.run_id);
      }
      if (record.plan) {
        this.planIndex.set(record.plan.plan_id, record.run_id);
      }
    }
  }

  private async getOrCreateRecord(runId: string): Promise<RunRecord> {
    await this.ensureIndex();
    const existing = await this.store.get(runId);
    return existing || { run_id: runId, updated_at: new Date().toISOString() };
  }

  async saveRequest(request: RunRequest): Promise<void> {
    // request 保存时 run_id 尚未关联到 record，需要从上下文推导
    // 由于 executeRun 中 saveRequest 在 saveExecution 之前调用，
    // 我们通过 request_id 临时存储，后续 saveExecution 时关联
    await this.ensureIndex();

    // 查找是否已有 record 包含此 request（通过索引）
    const existingRunId = this.requestIndex.get(request.request_id);
    if (existingRunId) {
      const record = await this.getOrCreateRecord(existingRunId);
      record.request = request;
      record.updated_at = new Date().toISOString();
      await this.store.set(existingRunId, record);
    } else {
      // 暂存：用 request_id 作为临时 key，等 saveExecution 时合并
      const record: RunRecord = {
        run_id: `__pending_${request.request_id}`,
        request,
        updated_at: new Date().toISOString(),
      };
      await this.store.set(`__pending_${request.request_id}`, record);
      this.requestIndex.set(request.request_id, `__pending_${request.request_id}`);
    }
  }

  async getRequest(requestId: string): Promise<RunRequest | undefined> {
    await this.ensureIndex();
    const runId = this.requestIndex.get(requestId);
    if (!runId) return undefined;
    const record = await this.store.get(runId);
    return record?.request;
  }

  async savePlan(plan: RunPlan): Promise<void> {
    await this.ensureIndex();
    const record = await this.getOrCreateRecord(plan.run_id);
    record.plan = plan;
    record.updated_at = new Date().toISOString();

    // 如果有 pending request，合并到此 record
    const pendingKey = `__pending_${(record.request?.request_id || "")}`;
    if (!record.request) {
      // 尝试从 pending 中查找匹配的 request
      const allRecords = await this.store.list();
      const pendingRecord = allRecords.find(r => r.run_id.startsWith("__pending_"));
      if (pendingRecord?.request) {
        record.request = pendingRecord.request;
        this.requestIndex.set(pendingRecord.request.request_id, plan.run_id);
        await this.store.delete(pendingRecord.run_id);
      }
    }

    record.run_id = plan.run_id;
    await this.store.set(plan.run_id, record);
    this.planIndex.set(plan.plan_id, plan.run_id);
  }

  async saveExecution(execution: RunExecution): Promise<void> {
    await this.ensureIndex();
    const record = await this.getOrCreateRecord(execution.run_id);
    record.execution = execution;
    record.updated_at = new Date().toISOString();

    // 合并 pending request（如果存在）
    if (!record.request) {
      const allRecords = await this.store.list();
      const pendingRecord = allRecords.find(r => r.run_id.startsWith("__pending_") && r.request);
      if (pendingRecord?.request) {
        record.request = pendingRecord.request;
        this.requestIndex.set(pendingRecord.request.request_id, execution.run_id);
        await this.store.delete(pendingRecord.run_id);
      }
    }

    record.run_id = execution.run_id;
    await this.store.set(execution.run_id, record);
  }

  async saveResult(result: RunResult): Promise<void> {
    await this.ensureIndex();
    const record = await this.getOrCreateRecord(result.run_id);
    record.result = result;
    record.updated_at = new Date().toISOString();
    await this.store.set(result.run_id, record);
  }

  async getExecution(runId: string): Promise<RunExecution | undefined> {
    await this.ensureIndex();
    const record = await this.store.get(runId);
    return record?.execution;
  }

  async getResult(runId: string): Promise<RunResult | undefined> {
    await this.ensureIndex();
    const record = await this.store.get(runId);
    return record?.result;
  }

  async getPlan(planId: string): Promise<RunPlan | undefined> {
    await this.ensureIndex();
    const runId = this.planIndex.get(planId);
    if (!runId) {
      // fallback: 线性扫描
      const all = await this.store.list();
      const found = all.find(r => r.plan?.plan_id === planId);
      if (found?.plan) {
        this.planIndex.set(planId, found.run_id);
        return found.plan;
      }
      return undefined;
    }
    const record = await this.store.get(runId);
    return record?.plan;
  }

  async listResults(): Promise<RunResult[]> {
    const all = await this.store.list();
    return all.filter(r => r.result).map(r => r.result!);
  }

  async listExecutions(): Promise<RunExecution[]> {
    const all = await this.store.list();
    return all.filter(r => r.execution).map(r => r.execution!);
  }

  /** 列出所有 RunRecord（供 GC 使用） */
  async listRecords(): Promise<RunRecord[]> {
    return this.store.list();
  }

  /** 删除指定 run（供 GC 使用） */
  async deleteRun(runId: string): Promise<void> {
    const record = await this.store.get(runId);
    if (record) {
      if (record.request) this.requestIndex.delete(record.request.request_id);
      if (record.plan) this.planIndex.delete(record.plan.plan_id);
      await this.store.delete(runId);
    }
  }

  static createDurable(basePath: string): RunStore {
    return new RunStore({
      store: new FileStore<RunRecord>(`${basePath}/runs`),
    });
  }
}

/**
 * 向后兼容适配器：将四个独立 Store 包装为 Store<RunRecord> 接口。
 * 仅用于测试中传入独立 store 的场景。
 */
class LegacyRunStoreAdapter implements Store<RunRecord> {
  constructor(
    private requestStore: Store<RunRequest>,
    private planStore: Store<RunPlan>,
    private executionStore: Store<RunExecution>,
    private resultStore: Store<RunResult>,
  ) {}

  async get(id: string): Promise<RunRecord | undefined> {
    const execution = await this.executionStore.get(id);
    if (!execution) return undefined;
    const result = await this.resultStore.get(id);
    return {
      run_id: id,
      execution,
      result: result || undefined,
      updated_at: new Date().toISOString(),
    };
  }

  async set(id: string, value: RunRecord): Promise<void> {
    if (value.request) await this.requestStore.set(value.request.request_id, value.request);
    if (value.plan) await this.planStore.set(value.plan.plan_id, value.plan);
    if (value.execution) await this.executionStore.set(id, value.execution);
    if (value.result) await this.resultStore.set(id, value.result);
  }

  async delete(id: string): Promise<void> {
    await this.executionStore.delete(id);
    await this.resultStore.delete(id);
  }

  async list(): Promise<RunRecord[]> {
    const executions = await this.executionStore.list();
    const records: RunRecord[] = [];
    for (const exec of executions) {
      const result = await this.resultStore.get(exec.run_id);
      records.push({
        run_id: exec.run_id,
        execution: exec,
        result: result || undefined,
        updated_at: new Date().toISOString(),
      });
    }
    return records;
  }

  async count(): Promise<number> {
    return this.executionStore.count();
  }
}

// ============================================================
// JSONL Store — 追加写入日志存储
// ============================================================

export class JournalStore<T extends { event_id: string; timestamp: string }> implements Store<T> {
  private filePath: string;
  private cache: Map<string, T> = new Map();
  private initialized = false;

  constructor(filePath: string) {
    this.filePath = filePath;
  }

  private async ensureInitialized(): Promise<void> {
    if (this.initialized) return;
    this.initialized = true;
    try {
      const file = Bun.file(this.filePath);
      if (!(await file.exists())) return;
      const content = await file.text();
      for (const line of content.split("\n")) {
        if (!line.trim()) continue;
        try {
          const event = JSON.parse(line) as T;
          this.cache.set(event.event_id, event);
        } catch { /* 忽略损坏行 */ }
      }
    } catch { /* 文件不存在，忽略 */ }
  }

  async get(id: string): Promise<T | undefined> {
    await this.ensureInitialized();
    return this.cache.get(id);
  }

  async set(id: string, value: T): Promise<void> {
    await this.ensureInitialized();
    this.cache.set(id, value);
    // 追加写入 JSONL
    const { appendFileSync, mkdirSync } = await import("node:fs");
    const { dirname } = await import("node:path");
    mkdirSync(dirname(this.filePath), { recursive: true });
    appendFileSync(this.filePath, JSON.stringify(value) + "\n");
  }

  async delete(id: string): Promise<void> {
    await this.ensureInitialized();
    this.cache.delete(id);
    // JSONL 不支持原地删除，重写整个文件
    await this.rewrite();
  }

  async list(_filter?: Record<string, unknown>): Promise<T[]> {
    await this.ensureInitialized();
    return [...this.cache.values()];
  }

  async count(): Promise<number> {
    await this.ensureInitialized();
    return this.cache.size;
  }

  /** 按时间戳排序返回所有事件 */
  async listSorted(): Promise<T[]> {
    const all = await this.list();
    return all.sort((a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime());
  }

  /** 删除早于指定日期的事件 */
  async purgeOlderThan(cutoff: Date): Promise<number> {
    await this.ensureInitialized();
    const cutoffTime = cutoff.getTime();
    let purged = 0;
    for (const [id, event] of this.cache) {
      if (new Date(event.timestamp).getTime() < cutoffTime) {
        this.cache.delete(id);
        purged++;
      }
    }
    if (purged > 0) {
      await this.rewrite();
    }
    return purged;
  }

  /** 重写 JSONL 文件（用于 delete/purge 后） */
  private async rewrite(): Promise<void> {
    const { mkdirSync } = await import("node:fs");
    const { dirname } = await import("node:path");
    mkdirSync(dirname(this.filePath), { recursive: true });
    const lines = [...this.cache.values()].map(v => JSON.stringify(v)).join("\n");
    await Bun.write(this.filePath, lines ? lines + "\n" : "");
  }
}

// ============================================================
// Audit Trail — JSONL append-only
// ============================================================

export class AuditTrail {
  private store: Store<AuditEvent>;
  private buffer: AuditEvent[] = [];
  private flushThreshold: number;

  constructor(store?: Store<AuditEvent>, flushThreshold: number = 100) {
    this.store = store || new LocalMemoryStore<AuditEvent>();
    this.flushThreshold = flushThreshold;
  }

  async record(event: AuditEvent): Promise<void> {
    this.buffer.push(event);
    if (this.buffer.length >= this.flushThreshold) {
      await this.flush();
    }
  }

  async recordBatch(events: AuditEvent[]): Promise<void> {
    this.buffer.push(...events);
    if (this.buffer.length >= this.flushThreshold) {
      await this.flush();
    }
  }

  /**
   * 强制 flush：确保所有缓冲事件写入持久化存储
   * 应在 run_completed / run_failed / approval_blocked / cancelled 后调用
   */
  async forceFlush(): Promise<void> {
    await this.flush();
  }

  async flush(): Promise<void> {
    for (const event of this.buffer) {
      await this.store.set(event.event_id, event);
    }
    this.buffer = [];
  }

  async query(filter: AuditQueryFilter): Promise<AuditEvent[]> {
    await this.flush();
    const all = await this.store.list();

    return all.filter((event) => {
      if (filter.run_id && event.run_id !== filter.run_id) return false;
      if (filter.task_id && event.task_id !== filter.task_id) return false;
      if (filter.type && event.type !== filter.type) return false;
      if (filter.actor_id && event.actor.id !== filter.actor_id) return false;
      if (filter.from && new Date(event.timestamp) < new Date(filter.from)) return false;
      if (filter.to && new Date(event.timestamp) > new Date(filter.to)) return false;
      return true;
    });
  }

  async getTimeline(runId: string): Promise<AuditEvent[]> {
    const events = await this.query({ run_id: runId });
    return events.sort((a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime());
  }

  async export(format: "json" | "csv", filter?: AuditQueryFilter): Promise<string> {
    const events = filter ? await this.query(filter) : await this.store.list();

    if (format === "json") {
      return JSON.stringify(events, null, 2);
    }

    // CSV
    const headers = ["event_id", "type", "timestamp", "actor_id", "run_id", "task_id", "payload"];
    const rows = events.map((e) => [
      e.event_id,
      e.type,
      e.timestamp,
      e.actor.id,
      e.run_id || "",
      e.task_id || "",
      JSON.stringify(e.payload),
    ]);

    return [headers.join(","), ...rows.map((r) => r.join(","))].join("\n");
  }

  getBufferSize(): number {
    return this.buffer.length;
  }

  static createDurable(basePath: string): AuditTrail {
    return new AuditTrail(new JournalStore<AuditEvent>(`${basePath}/audit.jsonl`));
  }
}

export interface AuditQueryFilter {
  run_id?: string;
  task_id?: string;
  type?: string;
  actor_id?: string;
  from?: string;
  to?: string;
}

// ============================================================
// Event Bus Persistence Adapter
// ============================================================

export class PersistentEventBusAdapter {
  private auditTrail: AuditTrail;

  constructor(auditTrail: AuditTrail) {
    this.auditTrail = auditTrail;
  }

  /**
   * 连接到 EventBus，自动持久化所有事件
   */
  connectToEventBus(eventBus: import("../observability/event-bus").EventBus): void {
    eventBus.on("*", (event) => {
      const auditEvent: AuditEvent = {
        schema_version: "1.0.0",
        event_id: generateId("evt"),
        type: event.type as any,
        timestamp: event.timestamp,
        actor: { id: "system", type: "system", name: "EventBus", roles: [] },
        run_id: event.graph_id,
        task_id: event.task_id,
        payload: event.payload,
        scope: {},
      };
      this.auditTrail.record(auditEvent);
    });
  }
}

// ============================================================
// Replay / Resume Support
// ============================================================

export interface ReplayOptions {
  /** 从哪个事件开始回放 */
  from_event_id?: string;

  /** 回放速度倍率 */
  speed: number;

  /** 是否只读 (不触发副作用) */
  readonly: boolean;
}

export class ReplayEngine {
  private auditTrail: AuditTrail;

  constructor(auditTrail: AuditTrail) {
    this.auditTrail = auditTrail;
  }

  async getReplayTimeline(runId: string): Promise<AuditEvent[]> {
    return this.auditTrail.getTimeline(runId);
  }

  async getResumePoint(runId: string): Promise<ResumePoint | undefined> {
    const timeline = await this.getReplayTimeline(runId);
    if (timeline.length === 0) return undefined;

    // 找到最后一个成功的任务
    const lastSuccessful = [...timeline]
      .reverse()
      .find((e) => e.type === "task_completed" || e.type === "worker_completed");

    return {
      run_id: runId,
      last_completed_task_id: lastSuccessful?.task_id,
      last_event_id: timeline[timeline.length - 1].event_id,
      timestamp: timeline[timeline.length - 1].timestamp,
      completed_tasks: timeline
        .filter((e) => e.type === "task_completed")
        .map((e) => e.task_id!)
        .filter(Boolean),
    };
  }
}

export interface ResumePoint {
  run_id: string;
  last_completed_task_id?: string;
  last_event_id: string;
  timestamp: string;
  completed_tasks: string[];
}
