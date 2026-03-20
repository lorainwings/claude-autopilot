/**
 * 事件总线 — 插件内部的事件发布/订阅系统
 *
 * 提供去中心化的模块间通信机制，所有模块通过事件总线
 * 进行松耦合的消息传递，避免直接依赖。
 * 内部使用 Map<EventType, Set<EventHandler>> 存储订阅关系，
 * 事件历史最多保留 1000 条记录。
 */

// ─── 事件类型枚举 ─────────────────────────────────────────

/** 平台支持的所有事件类型 */
export type EventType =
  | 'task:created' | 'task:started' | 'task:completed' | 'task:failed'
  | 'worker:dispatched' | 'worker:completed' | 'worker:failed' | 'worker:timeout'
  | 'verifier:started' | 'verifier:completed' | 'verifier:failed'
  | 'model:routed' | 'model:escalated' | 'model:downgraded'
  | 'cost:recorded' | 'cost:warning' | 'cost:exceeded'
  | 'graph:created' | 'graph:completed' | 'graph:failed'
  | 'session:started' | 'session:ended';

// ─── 事件结构 ─────────────────────────────────────────────

/** 平台事件：事件总线中传递的标准消息结构 */
export interface PlatformEvent {
  /** 事件唯一标识（UUID） */
  id: string;
  /** 事件类型 */
  type: EventType;
  /** 事件产生时间（ISO-8601 格式） */
  timestamp: string;
  /** 事件来源模块名称 */
  source: string;
  /** 事件负载数据 */
  payload: Record<string, unknown>;
  /** 可选的元数据（用于追踪、调试等） */
  metadata?: Record<string, unknown>;
}

/** 事件处理函数签名：可以是同步或异步函数 */
export type EventHandler = (event: PlatformEvent) => void | Promise<void>;

// ─── 常量 ─────────────────────────────────────────────────

/** 事件历史最大保留条数 */
const MAX_HISTORY_SIZE = 1000;

// ─── 工具函数 ─────────────────────────────────────────────

/**
 * 生成简易 UUID（v4 格式）
 * 用于为每个事件分配唯一标识
 */
function generateId(): string {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

// ─── EventBus 类 ──────────────────────────────────────────

/**
 * 事件总线
 *
 * 提供发布/订阅模式的事件通信机制。
 * - 支持多订阅者同时监听同一事件类型
 * - 支持一次性监听（once）
 * - 自动维护事件历史（最多 1000 条）
 * - emit 时异步通知所有订阅者，不阻塞发射方
 */
export class EventBus {
  /** 订阅者映射表：事件类型 → 处理函数集合 */
  private subscribers: Map<EventType, Set<EventHandler>>;
  /** 事件历史记录 */
  private history: PlatformEvent[];

  constructor() {
    this.subscribers = new Map();
    this.history = [];
  }

  /**
   * 发射事件并通知所有订阅者
   *
   * @param type - 事件类型
   * @param source - 事件来源模块
   * @param payload - 事件负载数据
   * @returns 创建的 PlatformEvent 对象
   */
  emit(type: EventType, source: string, payload: Record<string, unknown>): PlatformEvent {
    // 构造事件对象
    const event: PlatformEvent = {
      id: generateId(),
      type,
      timestamp: new Date().toISOString(),
      source,
      payload,
    };

    // 追加到历史记录，超出上限则截断最旧的
    this.history.push(event);
    if (this.history.length > MAX_HISTORY_SIZE) {
      this.history = this.history.slice(-MAX_HISTORY_SIZE);
    }

    // 异步通知所有订阅者，不阻塞当前执行流
    const handlers = this.subscribers.get(type);
    if (handlers && handlers.size > 0) {
      for (const handler of handlers) {
        // 使用 Promise.resolve().then() 确保异步执行
        // 捕获异常防止单个 handler 失败影响其他订阅者
        Promise.resolve().then(() => handler(event)).catch((err) => {
          console.error(`[EventBus] 事件处理器执行失败 (${type}):`, err);
        });
      }
    }

    return event;
  }

  /**
   * 订阅指定类型的事件
   *
   * @param type - 要订阅的事件类型
   * @param handler - 事件处理函数
   * @returns 取消订阅的函数（调用即取消）
   */
  on(type: EventType, handler: EventHandler): () => void {
    // 如果该类型还没有订阅者集合，先初始化
    if (!this.subscribers.has(type)) {
      this.subscribers.set(type, new Set());
    }
    this.subscribers.get(type)!.add(handler);

    // 返回取消订阅函数
    return () => {
      this.off(type, handler);
    };
  }

  /**
   * 订阅指定类型的事件（只触发一次）
   *
   * 内部封装为包装函数，触发后自动取消订阅。
   *
   * @param type - 要订阅的事件类型
   * @param handler - 事件处理函数
   * @returns 取消订阅的函数（在触发前可手动取消）
   */
  once(type: EventType, handler: EventHandler): () => void {
    // 包装原始 handler，执行后自动取消订阅
    const wrapper: EventHandler = (event) => {
      this.off(type, wrapper);
      return handler(event);
    };
    return this.on(type, wrapper);
  }

  /**
   * 取消订阅指定类型的事件处理函数
   *
   * @param type - 事件类型
   * @param handler - 要取消的处理函数
   */
  off(type: EventType, handler: EventHandler): void {
    const handlers = this.subscribers.get(type);
    if (handlers) {
      handlers.delete(handler);
      // 如果该类型已无订阅者，清理空集合
      if (handlers.size === 0) {
        this.subscribers.delete(type);
      }
    }
  }

  /**
   * 获取事件历史记录
   *
   * @param type - 可选，按事件类型过滤
   * @param limit - 可选，限制返回条数（从最新开始）
   * @returns 符合条件的事件数组
   */
  getHistory(type?: EventType, limit?: number): PlatformEvent[] {
    let result = this.history;

    // 按类型过滤
    if (type) {
      result = result.filter((e) => e.type === type);
    }

    // 限制返回条数（取最新的 N 条）
    if (limit !== undefined && limit > 0) {
      result = result.slice(-limit);
    }

    return result;
  }

  /**
   * 清除所有事件历史和订阅关系
   *
   * 用于重置事件总线状态（如测试场景或会话重置）。
   */
  clear(): void {
    this.subscribers.clear();
    this.history = [];
  }

  /**
   * 获取订阅者数量
   *
   * @param type - 可选，指定事件类型。不指定则返回所有类型的订阅者总数。
   * @returns 订阅者数量
   */
  getSubscriberCount(type?: EventType): number {
    if (type) {
      return this.subscribers.get(type)?.size ?? 0;
    }

    // 统计所有类型的订阅者总数
    let total = 0;
    for (const handlers of this.subscribers.values()) {
      total += handlers.size;
    }
    return total;
  }
}
