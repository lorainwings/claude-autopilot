/**
 * 事件总线测试
 *
 * 覆盖 EventBus 的发布/订阅、历史查询、订阅者管理等核心功能。
 */

import { describe, it, expect } from 'bun:test';
import { EventBus } from '../runtime/control-plane/event-bus';
import type { PlatformEvent } from '../runtime/control-plane/event-bus';

// ─────────────────────────────────────────────────────────────
// EventBus
// ─────────────────────────────────────────────────────────────

describe('EventBus', () => {
  it('emit 发射事件', () => {
    const bus = new EventBus();

    const event = bus.emit('task:created', 'planner', {
      task_id: 'task-1',
      title: '实现功能 A',
    });

    // 验证返回的事件结构
    expect(event.type).toBe('task:created');
    expect(event.source).toBe('planner');
    expect(event.payload.task_id).toBe('task-1');
    expect(event.payload.title).toBe('实现功能 A');
    expect(typeof event.id).toBe('string');
    expect(event.id.length).toBeGreaterThan(0);
    expect(typeof event.timestamp).toBe('string');
  });

  it('on 订阅接收事件', async () => {
    const bus = new EventBus();
    const received: PlatformEvent[] = [];

    bus.on('task:completed', (event) => {
      received.push(event);
    });

    bus.emit('task:completed', 'worker', { task_id: 'task-1' });
    bus.emit('task:completed', 'worker', { task_id: 'task-2' });

    // 等待异步处理器执行（EventBus 使用 Promise.resolve().then()）
    await new Promise(resolve => setTimeout(resolve, 10));

    expect(received.length).toBe(2);
    expect(received[0].payload.task_id).toBe('task-1');
    expect(received[1].payload.task_id).toBe('task-2');
  });

  it('once 只接收一次', async () => {
    const bus = new EventBus();
    const received: PlatformEvent[] = [];

    bus.once('task:failed', (event) => {
      received.push(event);
    });

    // 发射第一个事件并等待异步处理器执行完毕
    // （once 内部通过 Promise.resolve().then() 异步执行 off，
    //  必须等第一个 handler 执行后才能将 wrapper 从 Set 中移除）
    bus.emit('task:failed', 'worker', { task_id: 'task-1' });
    await new Promise(resolve => setTimeout(resolve, 10));

    // 再发射两个事件，此时 wrapper 已被移除，不应再被触发
    bus.emit('task:failed', 'worker', { task_id: 'task-2' });
    bus.emit('task:failed', 'worker', { task_id: 'task-3' });
    await new Promise(resolve => setTimeout(resolve, 10));

    // 只收到第一个事件
    expect(received.length).toBe(1);
    expect(received[0].payload.task_id).toBe('task-1');
  });

  it('off 取消订阅', async () => {
    const bus = new EventBus();
    const received: PlatformEvent[] = [];

    const handler = (event: PlatformEvent) => {
      received.push(event);
    };

    bus.on('worker:dispatched', handler);

    // 发射第一个事件
    bus.emit('worker:dispatched', 'scheduler', { worker_id: 'w-1' });
    await new Promise(resolve => setTimeout(resolve, 10));
    expect(received.length).toBe(1);

    // 取消订阅
    bus.off('worker:dispatched', handler);

    // 发射第二个事件，不应被接收
    bus.emit('worker:dispatched', 'scheduler', { worker_id: 'w-2' });
    await new Promise(resolve => setTimeout(resolve, 10));
    expect(received.length).toBe(1);
  });

  it('on 返回的取消函数可取消订阅', async () => {
    const bus = new EventBus();
    const received: PlatformEvent[] = [];

    const unsubscribe = bus.on('cost:recorded', (event) => {
      received.push(event);
    });

    bus.emit('cost:recorded', 'cost-controller', { cost: 0.05 });
    await new Promise(resolve => setTimeout(resolve, 10));
    expect(received.length).toBe(1);

    // 通过返回的函数取消订阅
    unsubscribe();

    bus.emit('cost:recorded', 'cost-controller', { cost: 0.10 });
    await new Promise(resolve => setTimeout(resolve, 10));
    expect(received.length).toBe(1);
  });

  it('getHistory 返回事件历史', () => {
    const bus = new EventBus();

    bus.emit('task:created', 'planner', { id: 1 });
    bus.emit('task:started', 'scheduler', { id: 2 });
    bus.emit('task:completed', 'worker', { id: 3 });

    const history = bus.getHistory();
    expect(history.length).toBe(3);
    // 按发射顺序排列
    expect(history[0].type).toBe('task:created');
    expect(history[1].type).toBe('task:started');
    expect(history[2].type).toBe('task:completed');
  });

  it('getHistory 支持类型过滤', () => {
    const bus = new EventBus();

    bus.emit('task:created', 'planner', { id: 1 });
    bus.emit('task:completed', 'worker', { id: 2 });
    bus.emit('task:created', 'planner', { id: 3 });
    bus.emit('task:failed', 'worker', { id: 4 });

    // 只获取 task:created 类型
    const created = bus.getHistory('task:created');
    expect(created.length).toBe(2);
    expect(created.every(e => e.type === 'task:created')).toBe(true);

    // 只获取 task:failed 类型
    const failed = bus.getHistory('task:failed');
    expect(failed.length).toBe(1);
    expect(failed[0].payload.id).toBe(4);
  });

  it('getHistory 支持数量限制', () => {
    const bus = new EventBus();

    // 发射 5 个事件
    for (let i = 1; i <= 5; i++) {
      bus.emit('task:created', 'planner', { index: i });
    }

    // 限制返回 2 条（最新的 2 条）
    const limited = bus.getHistory(undefined, 2);
    expect(limited.length).toBe(2);
    expect(limited[0].payload.index).toBe(4);
    expect(limited[1].payload.index).toBe(5);
  });

  it('getHistory 同时支持类型过滤和数量限制', () => {
    const bus = new EventBus();

    bus.emit('task:created', 'planner', { index: 1 });
    bus.emit('task:completed', 'worker', { index: 2 });
    bus.emit('task:created', 'planner', { index: 3 });
    bus.emit('task:created', 'planner', { index: 4 });
    bus.emit('task:completed', 'worker', { index: 5 });

    // 只获取 task:created，限制 1 条
    const result = bus.getHistory('task:created', 1);
    expect(result.length).toBe(1);
    expect(result[0].payload.index).toBe(4);
  });

  it('getSubscriberCount 正确', () => {
    const bus = new EventBus();

    expect(bus.getSubscriberCount()).toBe(0);
    expect(bus.getSubscriberCount('task:created')).toBe(0);

    // 添加订阅者
    bus.on('task:created', () => {});
    bus.on('task:created', () => {});
    bus.on('task:completed', () => {});

    // 按类型查询
    expect(bus.getSubscriberCount('task:created')).toBe(2);
    expect(bus.getSubscriberCount('task:completed')).toBe(1);
    expect(bus.getSubscriberCount('task:failed')).toBe(0);

    // 查询总数
    expect(bus.getSubscriberCount()).toBe(3);
  });

  it('clear 清除一切', () => {
    const bus = new EventBus();

    // 添加订阅者和事件
    bus.on('task:created', () => {});
    bus.on('task:completed', () => {});
    bus.emit('task:created', 'planner', { id: 1 });
    bus.emit('task:completed', 'worker', { id: 2 });

    // 验证有数据
    expect(bus.getHistory().length).toBe(2);
    expect(bus.getSubscriberCount()).toBe(2);

    // 清除
    bus.clear();

    // 验证已清空
    expect(bus.getHistory().length).toBe(0);
    expect(bus.getSubscriberCount()).toBe(0);
  });

  it('不同类型事件互不干扰', async () => {
    const bus = new EventBus();
    const createdEvents: PlatformEvent[] = [];
    const completedEvents: PlatformEvent[] = [];

    bus.on('task:created', (e) => { createdEvents.push(e); });
    bus.on('task:completed', (e) => { completedEvents.push(e); });

    bus.emit('task:created', 'planner', { id: 'a' });
    bus.emit('task:completed', 'worker', { id: 'b' });
    bus.emit('task:created', 'planner', { id: 'c' });

    await new Promise(resolve => setTimeout(resolve, 10));

    expect(createdEvents.length).toBe(2);
    expect(completedEvents.length).toBe(1);
  });

  it('事件 id 唯一', () => {
    const bus = new EventBus();

    const event1 = bus.emit('task:created', 'planner', { n: 1 });
    const event2 = bus.emit('task:created', 'planner', { n: 2 });

    expect(event1.id).not.toBe(event2.id);
  });
});
