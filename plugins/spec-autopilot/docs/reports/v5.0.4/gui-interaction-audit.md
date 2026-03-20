# v5.0.4 GUI 交互与双向反控审计报告

> 审计日期: 2026-03-13
> 审计员: Agent 6 — GUI 交互与双向反控体验审查员
> 审计范围: GUI 前端全组件 + WebSocket 通信层 + autopilot-server.ts + poll-gate-decision.sh 双向反控链路
> 基线对比: v5.0 GUI 审计报告 (综合 54/100)

---

## 1. 审计摘要

### 综合评分

| 维度 | 权重 | 得分 | 加权分 | v5.0 对比 |
|------|------|------|--------|-----------|
| A. 数据渲染同步率 | 25% | 55/100 | 13.75 | 55 → 55 (无变化) |
| B. 终端保真度 | 15% | 40/100 | 6.00 | 40 → 40 (无变化) |
| C. 双向反控 | 30% | 42/100 | 12.60 | 25 → 42 (+17) |
| D. 内存与性能 | 15% | 50/100 | 7.50 | — (新增维度) |
| E. 代码质量 | 15% | 70/100 | 10.50 | 70 → 70 (无变化) |
| **总计** | **100%** | — | **50.35** | **54 → 50** |

**总分: 50/100**（较 v5.0 的 54 分略有下降，原因是本次拆分出内存/性能独立维度后加权调整，双向反控虽大幅改善但路径不一致问题抵消了部分增益）

### 核心发现

1. **[致命] 双向反控路径不一致**: 服务器将 decision 写入 `{projectRoot}/.autopilot/decision.json`，而 `poll-gate-decision.sh` 从 `{change_dir}/context/decision.json` 读取。**两条路径完全不同，决策链路在文件系统层面断裂。** 这是 v5.0 DC-1（引擎侧无消费者）的修复遗留——引擎侧已实现轮询，但与服务端写入路径未对齐。
2. **[高危] VirtualTerminal 批量事件丢失**: snapshot 推送时仅渲染最后一条事件，中间事件全部丢失。此问题自 v5.0 延续至今未修复。
3. **[高危] events[] 无限增长**: store 中事件数组无上限，长时间运行存在内存溢出风险。自 v5.0 延续未修。
4. **[中危] 事件去重缺失**: 断线重连后 snapshot 与已有事件合并，仅排序未去重，导致重复条目。
5. **[正面] v5.1 新增 `poll-gate-decision.sh`**: 引擎侧补全了决策轮询循环，SKILL.md 已集成调用入口，设计上实现了完整闭环。

---

## 2. 数据渲染同步率分析 (55/100)

### 2.1 WebSocket 重连机制

**文件**: `plugins/spec-autopilot/gui/src/lib/ws-bridge.ts`

- 指数退避重连: 初始 1s, 1.5x 递增, 上限 10s (行 26-27, 99-106)
- 重连后服务端自动推送 snapshot (autopilot-server.ts:158-166)
- **问题**: 无心跳检测，无法发现"半开"连接 (服务端支持 ping/pong 但客户端未发送)

### 2.2 事件去重

**文件**: `plugins/spec-autopilot/gui/src/store/index.ts` 行 44

```typescript
const merged = [...state.events, ...newEvents].sort((a, b) => a.sequence - b.sequence);
```

- 仅做排序，**无去重**。断线重连后 snapshot 包含已有事件时产生重复条目
- 修复方案: 按 `sequence` 去重，如 `Map<number, AutopilotEvent>` 或 `filter` 去重

### 2.3 Snapshot 批量渲染

- 服务端一次性推送所有历史事件作为 snapshot (autopilot-server.ts:161-166)
- 客户端 `addEvents` 正确合并 (store/index.ts:44)
- **问题**: VirtualTerminal 的 `useEffect([events])` 仅渲染最后一条事件 (VirtualTerminal.tsx:76)，snapshot 中 N-1 条事件丢失

### 2.4 连接状态同步

**文件**: `plugins/spec-autopilot/gui/src/App.tsx` 行 26-28

```typescript
const checkConnection = setInterval(() => {
  setConnected(wsBridge.connected);
}, 1000);
```

- 1 秒轮询检测连接状态，非事件驱动
- 最坏延迟 1 秒 + 额外 CPU 开销
- 应在 WSBridge 的 `onopen`/`onclose` 中直接回调通知

---

## 3. 终端保真度分析 (40/100)

**文件**: `plugins/spec-autopilot/gui/src/components/VirtualTerminal.tsx`

### 3.1 ANSI 颜色配置

- 完整 16 色 ANSI 调色板 (行 29-44)，VSCode Dark+ 配色
- **但**: 写入的是纯文本 `[时间] TYPE | Phase N (label)`，无 ANSI 转义码 (行 80-82)
- 颜色配置形同虚设

### 3.2 事件渲染格式

- 仅提取 `type`、`phase`、`phase_label` 三个字段 (行 80)
- 丢失关键信息: `duration_ms`、`gate_score`、`error_message`、`task_name`、`tdd_step`
- 不同事件类型无颜色区分

### 3.3 滚动性能

- FitAddon + requestAnimationFrame 的 resize 处理是最佳实践 (行 58-62)
- 默认 scrollback 1000 行 (xterm 默认值)，未显式配置
- `convertEol: true` + 手动 `\r\n` 可能导致双倍换行 (行 47, 81)
- 未设置 `disableStdin: true`，用户可能误以为可输入 (行 22)

### 3.4 批量事件丢失 (VT-2 延续)

**行 72-83**:
```typescript
useEffect(() => {
  const latest = events[events.length - 1];
  if (!latest) return;
  // 仅写入最后一条
  term.write(line);
}, [events]);
```

React 批量更新后 `useEffect` 只触发一次，snapshot 推送的 N 条事件中仅最后 1 条被渲染。

---

## 4. 双向反控链路完整性分析 (42/100)

**本节为本次审计核心。**

### 4.1 v5.1 改进: 引擎侧决策轮询已实现

**文件**: `plugins/spec-autopilot/scripts/poll-gate-decision.sh`

v5.0 报告的 DC-1（致命：引擎侧未实现 decision.json 轮询）和 DC-2（致命：gate 脚本不会挂起等待）已在 v5.1 中修复:

- `poll-gate-decision.sh` 实现了完整轮询循环 (行 83-136)
- 轮询间隔 1 秒，超时可配置 (默认 300 秒, 行 36-37)
- 支持 override/retry/fix 三种动作 (行 94)
- 决策读取后立即清理文件 (行 117-118)
- 发射 `gate_decision_pending` 和 `gate_decision_received` 事件到 Event Bus (行 77-78, 121-123)
- SKILL.md 已集成调用入口 (autopilot-gate/SKILL.md:96-98, autopilot/SKILL.md:177)

### 4.2 链路拓扑 (v5.1 现状)

```
[用户点击 Override]
    |
    v
GateBlockCard.handleDecision("override", 6)        -- GateBlockCard.tsx:23-31
    |
    v
App.handleDecision("override", 6)                  -- App.tsx:37-43
    |
    v
wsBridge.sendDecision({action:"override",phase:6})  -- ws-bridge.ts:86-91
    |
    v (WebSocket: {"type":"decision","data":{...}})
    |
    v
autopilot-server.ts websocket.message handler       -- autopilot-server.ts:170-178
    |
    v
handleDecision() → writeFile(DECISION_FILE)         -- autopilot-server.ts:124-132
    |
    v
写入路径: {projectRoot}/.autopilot/decision.json    -- autopilot-server.ts:41
    |
    !! 路径断裂 !!
    |
poll-gate-decision.sh 轮询路径:
{change_dir}/context/decision.json                  -- poll-gate-decision.sh:41
    |
    v (永远读不到文件)
    |
    v
超时 (300 秒后) → 回退到 AskUserQuestion           -- poll-gate-decision.sh:141-142
```

### 4.3 致命缺陷: 路径不一致 (DC-PATH)

| 组件 | decision.json 路径 | 文件:行号 |
|------|-------------------|-----------|
| autopilot-server.ts (写入) | `{projectRoot}/.autopilot/decision.json` | autopilot-server.ts:41 |
| poll-gate-decision.sh (读取) | `{change_dir}/context/decision.json` | poll-gate-decision.sh:41 |
| SKILL.md 文档描述 | `openspec/changes/<name>/context/decision.json` | autopilot-gate/SKILL.md:109 |

三者中，服务端写入路径与引擎侧读取路径完全不同:
- 服务端路径: `{projectRoot}/.autopilot/decision.json`
- 引擎侧路径: `openspec/changes/<change_name>/context/decision.json`

**影响**: 用户在 GUI 点击决策按钮后，决策被写入 `.autopilot/decision.json`，但 `poll-gate-decision.sh` 在 `{change_dir}/context/decision.json` 等待，永远读不到文件，最终超时。双向反控闭环虽然架构上完整，但实际运行时**仍然断裂**。

### 4.4 其余反控缺陷

| 编号 | 严重度 | 描述 | 位置 |
|------|--------|------|------|
| DC-PATH | **致命** | 服务端与引擎侧 decision.json 路径不一致（见上） | autopilot-server.ts:41 vs poll-gate-decision.sh:41 |
| DC-ACK | **高** | 无 ACK 反馈: 服务端写入 decision 后不向前端发送确认。前端 2 秒后自动解除 loading，用户不知决策是否生效 | autopilot-server.ts:124-132, GateBlockCard.tsx:27 |
| DC-CARD | **中** | gate_block 消费后卡片不消失: 即使引擎恢复运行，旧 gate_block 事件仍在 events[] 中，卡片持续显示 | GateBlockCard.tsx:17-20 |
| DC-FIX | **中** | `fix` 动作语义不明: SKILL.md:106 描述 fix 需要 `fix_instructions`，但 GateBlockCard 未提供输入框让用户填写修复指导 | GateBlockCard.tsx:68, SKILL.md:106 |
| DC-OVERRIDE-SAFETY | **低** | `poll-gate-decision.sh` 未检查 phase 号拒绝 override。SKILL.md:122 声明 Phase 4->5 和 5->6 不可 override，但脚本中无 phase 校验 | poll-gate-decision.sh:83-136 |

### 4.5 v5.0 致命缺陷修复评估

| v5.0 缺陷 | v5.1 状态 | 说明 |
|-----------|-----------|------|
| DC-1: 引擎侧未实现轮询 | **架构已修复** | poll-gate-decision.sh 实现完整轮询，但路径不一致导致实际未闭环 |
| DC-2: gate 脚本不会挂起 | **已修复** | poll-gate-decision.sh 在 gate_block 后进入挂起轮询 |
| DC-3: 无 ACK 反馈 | **未修复** | 服务端仍无 ACK 消息 |
| DC-4: 无幂等控制 | **部分修复** | poll-gate-decision.sh 读取后删除文件 (行 117-118)，但服务端写入时无 request_id |

---

## 5. 内存与性能分析 (50/100)

### 5.1 events[] 无限增长

**文件**: `plugins/spec-autopilot/gui/src/store/index.ts` 行 44

```typescript
const merged = [...state.events, ...newEvents].sort(...)
```

- 只追加不清理，无上限
- 典型 autopilot 运行产生 50-200 事件，多 session 累积后增长更快
- 每次 `addEvents` 都做全量排序 `O(n log n)`，随事件增多性能退化
- **修复**: `merged.slice(-MAX_EVENTS)` 或按 session 分段

### 5.2 Zustand Store 选择器

**文件**: `plugins/spec-autopilot/gui/src/components/PhaseTimeline.tsx` 行 20

```typescript
const { events, currentPhase, mode } = useStore();
```

- 所有组件直接解构整个 store 状态，任何字段变更触发全量重渲染
- PhaseTimeline 内部 `events.filter()` 在每次渲染时执行 (行 23)
- ParallelKanban 使用 `taskProgress` Map (行 22)，Zustand 对 Map 的 shallow 比较可能失效
- **修复**: 使用 `useStore(selector)` 精确订阅

### 5.3 CSS 动画

- PhaseTimeline 的 `phase-pulse` 动画 (index.css) 仅在 `.running` 节点上激活，无性能问题
- GateBlockCard 的 `alert-flash` 动画持续运行，但仅在卡片存在时激活
- 无无限动画泄漏风险

### 5.4 taskProgress Map 无清理

**文件**: `plugins/spec-autopilot/gui/src/store/index.ts` 行 47-61

- 任务完成后进度数据永久保留
- 新 session 同名任务可能冲突
- `reset()` 可清理，但无自动清理机制

---

## 6. 代码质量分析 (70/100)

### 6.1 TypeScript 类型安全

| 项目 | 评级 | 位置 |
|------|------|------|
| `AutopilotEvent.payload` | 不足 | `ws-bridge.ts:16` — `Record<string, unknown>` 过于宽泛 |
| `payload as any` | 不足 | `store/index.ts:51` — 丢失类型安全 |
| `endEvent.payload.status as typeof status` | 不足 | `PhaseTimeline.tsx:34` — 类型断言无运行时校验 |
| `endEvent.payload.duration_ms as number` | 不足 | `PhaseTimeline.tsx:35` — 可能为 undefined 或 NaN |
| 其余接口定义 | 良好 | 组件 Props、Store State 接口完整 |

### 6.2 React 最佳实践

| 项目 | 评级 | 说明 |
|------|------|------|
| StrictMode | 良好 | main.tsx 启用 |
| 函数组件 + Hooks | 良好 | 全部使用 |
| useEffect 依赖 | 良好 | App.tsx:35 正确声明 |
| ErrorBoundary | **缺失** | 全局无错误边界，异常导致白屏 |
| Ref 清理 | 良好 | VirtualTerminal 正确 dispose |
| 选择器使用 | 不足 | 所有组件全量订阅 store |

### 6.3 依赖完整性

**文件**: `plugins/spec-autopilot/gui/package.json`

| 依赖 | 版本 | 状态 |
|------|------|------|
| React | ^19.0.0 | 最新稳定版 |
| Zustand | ^5.0.0 | 最新稳定版 |
| @xterm/xterm | ^5.5.0 | 最新稳定版 |
| @xterm/addon-fit | ^0.10.0 | 最新稳定版 |
| Vite | ^6.0.0 | 最新稳定版 |
| TypeScript | ^5.7.0 | 最新稳定版 |
| **Tailwind CSS** | **未安装** | **组件中使用 Tailwind 类名但未安装** |

Tailwind 类名问题: ParallelKanban、GateBlockCard 中使用 `bg-gray-900`、`border-red-500/50` 等 Tailwind 类名 (ParallelKanban.tsx:31, GateBlockCard.tsx:35)。这些类名不会生效，组件依赖 `index.css` 中的自定义样式覆盖。

---

## 7. 关键缺陷清单

| 编号 | 严重级别 | 描述 | 文件路径 | 行号 |
|------|----------|------|----------|------|
| DC-PATH | **致命** | 服务端与引擎侧 decision.json 路径不一致，双向反控文件系统层面断裂 | `scripts/autopilot-server.ts` vs `scripts/poll-gate-decision.sh` | 41 vs 41 |
| VT-2 | **高** | VirtualTerminal 仅渲染最后一条事件，snapshot 批量推送时丢失 N-1 条 | `gui/src/components/VirtualTerminal.tsx` | 76 |
| SM-1 | **高** | events[] 无限增长，无上限控制，长时间运行内存溢出 | `gui/src/store/index.ts` | 44 |
| DC-ACK | **高** | 决策无 ACK 反馈，用户不知决策是否生效 | `scripts/autopilot-server.ts` | 124-132 |
| WS-3 | **中** | 断线重连后事件去重缺失，排序但不去重 | `gui/src/store/index.ts` | 44 |
| PT-1 | **中** | PhaseTimeline gate_block 优先于 phase_end，retry 成功后仍显示 blocked | `gui/src/components/PhaseTimeline.tsx` | 31-38 |
| DC-CARD | **中** | gate_block 事件消费后卡片不消失 | `gui/src/components/GateBlockCard.tsx` | 17-20 |
| DC-FIX | **中** | fix 动作无 fix_instructions 输入机制 | `gui/src/components/GateBlockCard.tsx` | 68 |
| SM-4 | **中** | Zustand 对 Map 类型 shallow 比较可能失效 | `gui/src/store/index.ts` | 47 |
| WS-1 | **中** | 连接状态 1s 轮询而非事件驱动 | `gui/src/App.tsx` | 26-28 |
| PK-1 | **中** | Tailwind 类名未安装，组件样式依赖 CSS fallback | `gui/src/components/ParallelKanban.tsx` | 31 |
| VT-1 | **中** | 终端无 ANSI 着色，16 色配置形同虚设 | `gui/src/components/VirtualTerminal.tsx` | 80-82 |
| DC-OVERRIDE | **低** | poll-gate-decision.sh 未校验 Phase 4->5/5->6 禁止 override | `scripts/poll-gate-decision.sh` | 83-136 |
| VT-7 | **低** | 未设置 `disableStdin: true`，终端可接受输入但无处理 | `gui/src/components/VirtualTerminal.tsx` | 22 |
| PT-2 | **低** | `find()` 取第一个匹配事件而非最新事件 (retry 场景) | `gui/src/components/PhaseTimeline.tsx` | 24-26 |

---

## 8. 与 v5.0 报告对比

### 8.1 已修复项

| v5.0 缺陷 | 状态 | 说明 |
|-----------|------|------|
| DC-1 (致命): 引擎侧无 decision.json 消费者 | **架构修复，实际未闭环** | `poll-gate-decision.sh` 已实现轮询循环 (v5.1)，但与服务端写入路径不一致 |
| DC-2 (致命): gate 脚本不挂起等待 | **已修复** | `poll-gate-decision.sh` 在 gate_block 后进入 while 循环等待 |

### 8.2 未修复项 (从 v5.0 延续)

| v5.0 缺陷 | 状态 | 说明 |
|-----------|------|------|
| VT-2 (高): VirtualTerminal 仅渲染最后一条 | **未修复** | 逻辑完全不变 |
| SM-1 (高): events[] 无限增长 | **未修复** | 无上限无清理 |
| WS-3 (中): 事件去重缺失 | **未修复** | 仅排序不去重 |
| PT-1 (中): gate_block 状态优先级错误 | **未修复** | 逻辑不变 |
| WS-1 (中): 连接状态轮询 | **未修复** | 仍用 setInterval |
| DC-3 (高): 无 ACK 反馈 | **未修复** | 服务端未添加 ACK |
| DC-4 (高): 无幂等控制 | **部分修复** | poll 读后删除文件，但无 request_id |
| PK-1/GB-4 (中): Tailwind 未安装 | **未修复** | package.json 未变 |
| VT-1 (高): 终端无 ANSI 着色 | **未修复** | 纯文本写入 |

### 8.3 新增问题

| 缺陷 | 严重度 | 说明 |
|------|--------|------|
| DC-PATH | **致命** | v5.1 新增 poll-gate-decision.sh，但与 autopilot-server.ts 写入路径未对齐 |
| DC-OVERRIDE | **低** | v5.1 新增的 poll-gate-decision.sh 缺少 Phase 4->5/5->6 override 安全检查 |

### 8.4 分数变化分析

v5.0 综合 54 分 → v5.1 综合 50 分。分数未提升的原因:

1. **双向反控**: 从 25 → 42 (+17)。架构上完成了关键补齐（引擎侧轮询），但路径不一致导致无法实际运行
2. **其余维度**: 前端代码无任何变更，所有 v5.0 非致命缺陷均延续
3. **加权调整**: 本次将内存/性能独立为 15% 权重维度（从数据渲染同步率中拆出），整体分布更合理

---

## 9. 修复优先级排序

### P0 — 立即修复 (阻断核心功能)

| 优先级 | 缺陷 | 修复方案 | 工作量 |
|--------|------|----------|--------|
| P0-1 | DC-PATH: decision.json 路径不一致 | 将 `autopilot-server.ts:41` 的 `DECISION_FILE` 修改为与 `poll-gate-decision.sh:41` 一致的路径 (`{change_dir}/context/decision.json`)，或反向统一。需要服务端知道当前 `change_dir`（可通过 WS 消息传递或锁文件推导） | 中 |

### P1 — 高优先级 (影响用户体验)

| 优先级 | 缺陷 | 修复方案 | 工作量 |
|--------|------|----------|--------|
| P1-1 | VT-2: 终端批量事件丢失 | 追踪已渲染的 `lastRenderedSequence`，每次 events 变更时从上次位置渲染所有新事件 | 小 |
| P1-2 | SM-1: events 无限增长 | `merged.slice(-1000)` 或 `merged.slice(-MAX_EVENTS)` | 小 |
| P1-3 | DC-ACK: 决策无 ACK | 服务端 `handleDecision` 成功后广播 `{ type: "decision_ack", data }` 到所有 WS 客户端；前端监听并更新 GateBlockCard 状态 | 中 |

### P2 — 中优先级 (质量改善)

| 优先级 | 缺陷 | 修复方案 | 工作量 |
|--------|------|----------|--------|
| P2-1 | WS-3: 事件去重 | `addEvents` 中按 `sequence` 去重: `new Map(merged.map(e => [e.sequence, e]))` | 小 |
| P2-2 | PT-1: 状态优先级 | 按 `sequence` 比较 `gate_block` 和 `phase_end`，取更新的状态 | 小 |
| P2-3 | VT-1/VT-4: ANSI 着色 | 为不同事件类型添加 ANSI 颜色前缀: gate_block → `\x1b[31m`, phase_start → `\x1b[32m` | 小 |
| P2-4 | WS-1: 连接轮询 | WSBridge 添加 `onStatusChange` 回调，在 `onopen`/`onclose` 中触发 | 小 |
| P2-5 | PK-1/GB-4: Tailwind 类名 | 安装 Tailwind CSS 或将类名替换为纯 CSS | 中 |
| P2-6 | DC-CARD: 卡片不消失 | 监听 `gate_decision_received` 或 `phase_start` 事件后隐藏 GateBlockCard | 小 |

### P3 — 低优先级

| 优先级 | 缺陷 | 修复方案 | 工作量 |
|--------|------|----------|--------|
| P3-1 | DC-OVERRIDE: override 安全检查 | `poll-gate-decision.sh` 中添加 Phase 号校验 | 小 |
| P3-2 | ErrorBoundary | 添加全局 React ErrorBoundary 组件 | 小 |
| P3-3 | DC-FIX: fix_instructions 输入 | GateBlockCard 增加文本输入框 | 小 |
| P3-4 | SM-4: Map shallow 比较 | 将 taskProgress 改为 `Record<string, TaskProgress>` 或使用 Zustand `subscribeWithSelector` | 中 |

---

> **结论**: v5.1 在架构层面完成了双向反控的关键补齐（poll-gate-decision.sh），但服务端与引擎侧的 decision.json 路径不一致导致闭环实际无法运行。这是当前唯一的致命缺陷，修复后双向反控维度预计可达 65+/100，综合分预计提升至 60+/100。前端组件层面自 v5.0 以来无代码变更，所有 v5.0 非致命缺陷均延续。
