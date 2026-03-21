/**
 * parallel-harness: Session Persistence & Audit Trail
 *
 * 持久化体系。从内存态升级为可持久化、可回放、可审计。
 * 至少支持本地持久化适配器，抽象未来数据库适配层。
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
// Run Store
// ============================================================

export class RunStore {
  private requestStore: Store<RunRequest>;
  private planStore: Store<RunPlan>;
  private executionStore: Store<RunExecution>;
  private resultStore: Store<RunResult>;

  constructor(options?: {
    requestStore?: Store<RunRequest>;
    planStore?: Store<RunPlan>;
    executionStore?: Store<RunExecution>;
    resultStore?: Store<RunResult>;
  }) {
    this.requestStore = options?.requestStore || new LocalMemoryStore();
    this.planStore = options?.planStore || new LocalMemoryStore();
    this.executionStore = options?.executionStore || new LocalMemoryStore();
    this.resultStore = options?.resultStore || new LocalMemoryStore();
  }

  async saveRequest(request: RunRequest): Promise<void> {
    await this.requestStore.set(request.request_id, request);
  }

  async getRequest(requestId: string): Promise<RunRequest | undefined> {
    return this.requestStore.get(requestId);
  }

  async savePlan(plan: RunPlan): Promise<void> {
    await this.planStore.set(plan.plan_id, plan);
  }

  async saveExecution(execution: RunExecution): Promise<void> {
    await this.executionStore.set(execution.run_id, execution);
  }

  async saveResult(result: RunResult): Promise<void> {
    await this.resultStore.set(result.run_id, result);
  }

  async getExecution(runId: string): Promise<RunExecution | undefined> {
    return this.executionStore.get(runId);
  }

  async getResult(runId: string): Promise<RunResult | undefined> {
    return this.resultStore.get(runId);
  }

  async getPlan(planId: string): Promise<RunPlan | undefined> {
    return this.planStore.get(planId);
  }

  async listResults(): Promise<RunResult[]> {
    return this.resultStore.list();
  }

  static createDurable(basePath: string): RunStore {
    return new RunStore({
      requestStore: new FileStore(`${basePath}/requests`),
      planStore: new FileStore(`${basePath}/plans`),
      executionStore: new FileStore(`${basePath}/executions`),
      resultStore: new FileStore(`${basePath}/results`),
    });
  }
}

// ============================================================
// Audit Trail
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
    return new AuditTrail(new FileStore<AuditEvent>(basePath));
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
