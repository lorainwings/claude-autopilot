# GUI 交互审查报告

> 审查日期: 2026-03-13
> 审查范围: spec-autopilot GUI 全部前端组件 + WebSocket 通信层 + 服务端
> 审查方法: 代码级静态分析，对比 event-bus-api.md 规范

---

## 1. 执行摘要

spec-autopilot GUI 大盘基于 React 19 + Zustand 5 + XTerm.js 5.5 + Vite 6 构建，通过 WebSocket 桥接 `autopilot-server.ts` 实现事件流消费和双向决策反控。整体架构清晰、技术选型现代，但存在以下核心问题:

- **双向反控链路断裂**: GUI 已实现前端到 `decision.json` 的写入链路，但引擎侧(SKILL.md / gate 脚本)缺少轮询 `decision.json` 的消费逻辑，决策指令无法闭环
- **VirtualTerminal 仅为事件日志格式化器**: 未接入真实 CLI 输出流，不显示 ANSI 着色内容
- **事件数组无限增长**: `events[]` 无上限，长时间运行存在内存泄漏风险
- **缺失事件类型消费**: `gate_pass` 和 `error` 事件在 GUI 中未被显式消费/渲染
- **连接状态采用 1s 轮询而非事件驱动**: 导致最多 1 秒延迟且浪费 CPU

**综合评分: 62/100** (架构骨架完整，但关键链路存在断裂，多个功能处于"脚手架"阶段)

---

## 2. 组件逐一审查

### 2.1 PhaseTimeline (阶段进度时间轴)

**文件**: `gui/src/components/PhaseTimeline.tsx`

#### 数据渲染机制

- **事件消费**: 从 Zustand store 读取 `events` 数组，按 `phase === idx` 过滤，查找 `phase_start`/`phase_end`/`gate_block` 三类事件 (第23-26行)
- **状态推导逻辑** (第28-38行):
  ```
  gate_block 存在 → "blocked"
  phase_end 存在 → 取 payload.status 或默认 "ok"
  phase_start 存在 → "running"
  否则 → "pending"
  ```

#### 发现的问题

| 编号 | 严重度 | 描述 | 位置 |
|------|--------|------|------|
| PT-1 | **中** | 状态判定优先级错误: `gate_block` 优先于 `phase_end`。如果一个 Phase 先被 `gate_block` 再通过 retry 完成(产生 `phase_end`)，该 Phase 仍显示为 "blocked" 而非 "ok"。应改为时间戳比较或 sequence 比较 | `PhaseTimeline.tsx:31-38` |
| PT-2 | **低** | 使用 `events.find()` 取第一个匹配事件，但同一 Phase 可能有多次 `phase_start`(retry 场景)，应使用 `findLast()` 或取最大 sequence | `PhaseTimeline.tsx:24-26` |
| PT-3 | **低** | `gate_pass` 事件未消费 -- Gate 通过时没有视觉反馈 | `PhaseTimeline.tsx:23-26` |
| PT-4 | **信息** | 硬编码 8 个 Phase 标签(`PHASE_LABELS`)，但 lite 模式仅 5 个 Phase、minimal 模式仅 4 个。非活跃 Phase 会显示为空 "pending" 节点 | `PhaseTimeline.tsx:8-17` |
| PT-5 | **低** | `duration` 类型断言 `as number` 缺少安全检查，若 payload 为非数字值会显示 NaN | `PhaseTimeline.tsx:35` |

#### 正面评价

- CSS 动画效果出色: `phase-pulse` 动画让 running 状态一目了然 (`index.css:441-450`)
- 六角形 `clip-path` 裁剪效果赋予节点独特视觉风格 (`index.css:390-395`)
- 响应式布局处理得当，`timeline-track` 支持横向滚动 (`index.css:353-360`)

---

### 2.2 ParallelKanban (并发任务看板)

**文件**: `gui/src/components/ParallelKanban.tsx`

#### 数据渲染机制

- **事件消费**: 从 Zustand store 读取 `taskProgress` Map，该 Map 由 `addEvents` 中针对 `task_progress` + `phase === 5` 的事件更新 (`store/index.ts:50-61`)
- **可见性**: 仅当 `currentPhase === 5` 或 `taskProgress.size > 0` 时渲染 (第24行)
- **排序**: 按 `task_index` 升序排列 (第28行)

#### 发现的问题

| 编号 | 严重度 | 描述 | 位置 |
|------|--------|------|------|
| PK-1 | **中** | Tailwind 类名与纯 CSS 混用: 组件内使用 `bg-gray-900`、`text-lg` 等 Tailwind 类名，但项目**未安装 Tailwind CSS** (`package.json` 无 tailwindcss 依赖)。这些类名不会生效，组件依赖 `index.css` 中的 `.parallel-kanban`/`.kanban-header` 覆盖样式 | `ParallelKanban.tsx:31-42` |
| PK-2 | **中** | `STATUS_COLORS` 映射使用 Tailwind 类名 (`bg-blue-500/20 border-blue-500` 等)，同样不会生效。任务卡片缺少状态颜色区分 | `ParallelKanban.tsx:14-19` |
| PK-3 | **低** | 仅处理 `phase === 5` 的 `task_progress` 事件，如果未来 Phase 4(test_design)或其他 Phase 也支持并行任务，需要修改硬编码 | `store/index.ts:50` |
| PK-4 | **低** | `task.status` 的 TypeScript 类型为联合字面量，但 `STATUS_COLORS` 索引访问缺少默认值回退 -- 如果服务端发来未知 status 会导致 className 为 `undefined` | `ParallelKanban.tsx:46` |
| PK-5 | **信息** | 看板显示 "X / Y" 完成计数，但缺少进度条或百分比可视化 | `ParallelKanban.tsx:35` |

#### 正面评价

- TDD step 图标映射直观 (`red`/`green`/`refactor` 对应红绿蓝) (第8-12行)
- 重试计数显示位置合理，用黄色警告色突出 (第65-69行)
- 与 `event-bus-api.md` 定义的 `TaskProgressEvent` 字段完全对齐

---

### 2.3 GateBlockCard (门禁决策卡片)

**文件**: `gui/src/components/GateBlockCard.tsx`

#### 数据渲染机制

- **事件消费**: 过滤 `events` 中 `type === "gate_block"` 的事件，取最后一个 (第17-20行)
- **渲染字段**: `phase_label`、`payload.gate_score`、`payload.error_message`

#### 决策按钮交互

- 三个按钮: Retry / Fix / Override (第55-75行)
- 点击后调用 `onDecision(action, phase)` -> `App.tsx:handleDecision` -> `wsBridge.sendDecision()` (App.tsx:38-43)
- Loading 状态管理: 按钮点击后 `setLoading(action)` 禁用所有按钮，2 秒后 `setTimeout` 自动解除 (第25-31行)

#### 发现的问题

| 编号 | 严重度 | 描述 | 位置 |
|------|--------|------|------|
| GB-1 | **高** | 只显示最新一个 `gate_block` 事件，不显示历史阻断。如果连续多个 Phase 被阻断(理论上不应发生，但 error 事件可能)，用户只能看到最后一个 | `GateBlockCard.tsx:20` |
| GB-2 | **高** | 缺少决策确认反馈: 按钮点击后无法得知服务端是否成功处理。`sendDecision` 是 fire-and-forget 模式，WebSocket 不返回 ACK。2 秒后 loading 自动解除，但用户不知道决策是否生效 | `GateBlockCard.tsx:26-27` |
| GB-3 | **中** | `gate_block` 被消费后(用户做出决策)，卡片不会消失。即使引擎已恢复运行，旧的 gate_block 事件仍存在于 `events[]` 中，卡片持续显示 | `GateBlockCard.tsx:17-18` |
| GB-4 | **中** | Tailwind 类名问题同 PK-1: `p-4 bg-red-900/20 rounded-lg border border-red-500/50 mb-4` 不会生效。但 `index.css:526-542` 定义了 `.gate-block-card` 样式进行覆盖 | `GateBlockCard.tsx:35` |
| GB-5 | **低** | `onDecision` prop 是可选的 (`onDecision?.()`，第26行)，如果未传入，按钮点击无效但无任何提示 | `GateBlockCard.tsx:26` |
| GB-6 | **低** | `fix` 动作在 `event-bus-api.md` 中未定义。服务端 `handleDecision` 只做文件写入，不区分 action 类型。引擎侧对 "fix" 的预期行为不明确 | `GateBlockCard.tsx:23` |

#### 正面评价

- 错误消息使用深红背景突出显示，可读性好 (第47-50行)
- CSS 动画 `alert-flash` 让阻断卡片持续闪烁，引人注意 (`index.css:535-542`)
- Loading 状态禁用所有按钮，防止重复提交 (第57, 63, 70行)

---

### 2.4 VirtualTerminal (XTerm 虚拟终端)

**文件**: `gui/src/components/VirtualTerminal.tsx`

#### XTerm.js 集成

- **初始化**: `useEffect([], ...)` 中创建 `Terminal` 实例 + `FitAddon` (第18-69行)
- **ANSI 颜色**: 完整配置了 16 色标准 ANSI 调色板 (第29-44行)
- **自动适配**: 窗口 resize 时通过 `requestAnimationFrame` + `fitAddon.fit()` 适配 (第58-62行)
- **数据写入**: 第二个 `useEffect` 监听 `events` 变化，取最新一条事件格式化为单行写入终端 (第72-83行)

#### 发现的问题

| 编号 | 严重度 | 描述 | 位置 |
|------|--------|------|------|
| VT-1 | **高** | **非真实终端**: 仅将事件流格式化为 `[时间] TYPE | Phase N (label)` 单行写入，不接入任何 CLI 子进程输出。ANSI 16 色调色板配置形同虚设 -- 写入的是纯文本，无颜色转义码 | `VirtualTerminal.tsx:80-82` |
| VT-2 | **高** | **仅渲染最新一条事件**: `events[events.length - 1]`。如果一次 `addEvents` 批量追加 N 条(如 WebSocket snapshot)，中间 N-1 条会被跳过。这是因为 React 批量更新后 `useEffect` 只触发一次，只能看到最终的 `events` 状态 | `VirtualTerminal.tsx:76` |
| VT-3 | **中** | 缺少事件 payload 详情展示。当前格式只有 type、phase、phase_label，丢失了 `duration_ms`、`gate_score`、`error_message`、`task_name` 等关键信息 | `VirtualTerminal.tsx:80` |
| VT-4 | **中** | 无 ANSI 着色: 不同事件类型(phase_start/phase_end/gate_block/error)没有使用 xterm 的 `\x1b[31m` 等转义码上色 | `VirtualTerminal.tsx:80-82` |
| VT-5 | **低** | 无缓冲区限制: 长时间运行后 xterm 内部行缓冲无限增长。未设置 `scrollback` 参数(默认 1000 行)，但也未明确管理 | `VirtualTerminal.tsx:21-48` |
| VT-6 | **低** | `convertEol: true` 但写入时使用 `\r\n` 双换行符，可能导致双倍换行 | `VirtualTerminal.tsx:47, 81` |
| VT-7 | **信息** | `cursorBlink: false` 且终端只读(无输入处理)，但未设置 `disableStdin: true`。用户可能会误以为可以输入 | `VirtualTerminal.tsx:22` |

#### 正面评价

- ANSI 16 色调色板配置专业，VSCode Dark+ 配色方案 (第29-44行)
- `FitAddon` + `requestAnimationFrame` 的 resize 处理是最佳实践 (第58-62行)
- 组件卸载时正确 `dispose()` 终端实例 + 移除事件监听 (第66-68行)

---

## 3. WebSocket 通信层审查

**文件**: `gui/src/lib/ws-bridge.ts`

### 3.1 连接管理

- **默认端口**: `ws://localhost:8765` (第29行)
- **重连策略**: 指数退避，初始 1s，1.5x 递增，上限 10s (第27, 103行)
- **连接状态**: `get connected()` 检查 `readyState === WebSocket.OPEN` (第82-84行)

### 3.2 消息协议

**接收方向** (第43-53行):
- `{ type: "snapshot", data: AutopilotEvent[] }` — 连接时的全量快照
- `{ type: "event", data: AutopilotEvent }` — 增量单条事件

**发送方向** (第86-91行):
- `{ type: "decision", data: { action, phase, reason? } }` — 门禁决策

### 3.3 发现的问题

| 编号 | 严重度 | 描述 | 位置 |
|------|--------|------|------|
| WS-1 | **高** | **连接状态轮询**: `App.tsx:26-28` 使用 `setInterval(checkConnection, 1000)` 每秒轮询 `wsBridge.connected`。正确做法是在 `onopen`/`onclose` 回调中直接通知 store 更新 | `App.tsx:26-28` |
| WS-2 | **中** | **无断线重连时的事件补偿**: 断线期间的事件会丢失。重连后不会重新请求 snapshot，因为 `onopen` 回调没有触发 snapshot 请求。服务端在 `websocket.open` 中自动发送 snapshot (server:158-166)，所以重连后理论上会收到全量快照，但此时 store 中已有旧事件，可能导致重复 | `ws-bridge.ts:39-41, store/index.ts:44` |
| WS-3 | **中** | **事件去重依赖 sort**: `addEvents` 中 `[...state.events, ...newEvents].sort((a, b) => a.sequence - b.sequence)` 做了排序，但未去重。如果断线重连后收到 snapshot 包含已有事件，会出现重复条目 | `store/index.ts:44` |
| WS-4 | **低** | `sendDecision` 抛出异常("WebSocket not connected")，但 `App.tsx:handleDecision` 的 catch 只打日志然后 re-throw。GateBlockCard 的 catch 也只打日志 -- 用户看不到任何错误提示 | `ws-bridge.ts:88-89, App.tsx:41-43` |
| WS-5 | **低** | `onmessage` 中 JSON 解析失败时静默忽略(`catch {}`)。恶意或格式错误的消息完全无日志 | `ws-bridge.ts:51-53` |
| WS-6 | **信息** | 未实现 WebSocket ping/pong 心跳。服务端支持 `ping` 消息类型 (server:173-174)，但客户端从未发送 | `ws-bridge.ts` (缺失) |

---

## 4. 双向反控完整链路分析

这是本次审查的核心重点。完整链路分析:

### 4.1 链路拓扑

```
[用户点击按钮]
    |
    v
GateBlockCard.handleDecision("override", 6)     -- GateBlockCard.tsx:23-31
    |
    v
App.handleDecision("override", 6)               -- App.tsx:37-43
    |
    v
wsBridge.sendDecision({action:"override",phase:6}) -- ws-bridge.ts:86-91
    |
    v (WebSocket JSON: {"type":"decision","data":{"action":"override","phase":6}})
    |
    v
autopilot-server.ts: websocket.message handler  -- autopilot-server.ts:170-178
    |
    v
handleDecision() → writeFile(DECISION_FILE)     -- autopilot-server.ts:124-132
    |
    v
{project_root}/.autopilot/decision.json 文件写入
    |
    v
??? 引擎侧无消费者 ???                           -- !! 链路断裂 !!
```

### 4.2 链路断裂点

| 编号 | 严重度 | 描述 |
|------|--------|------|
| DC-1 | **致命** | **引擎侧未实现 decision.json 轮询**: 全局搜索 `decision.json` 仅在 `autopilot-server.ts:41` (定义路径) 和 `autopilot-server.ts:124-132` (写入) 中出现。SKILL.md、gate 脚本、hook 脚本中**均无**读取 decision.json 的逻辑。这意味着用户在 GUI 上点击 Override/Retry/Fix 按钮后，决策指令被写入文件但永远不会被消费 |
| DC-2 | **致命** | **gate 脚本不会挂起等待**: `emit-gate-event.sh` 是纯粹的"事件发射器"(fire-and-forget)，写入 events.jsonl 后立即退出。没有任何地方的代码在 gate_block 后进入挂起状态等待用户决策 |
| DC-3 | **高** | **无 ACK 反馈机制**: 服务端 `handleDecision` 写入文件后不向 WebSocket 客户端发送任何确认消息。前端无法得知决策是否被接收、是否生效 |
| DC-4 | **高** | **decision.json 无版本/幂等控制**: 多次点击会覆盖文件内容，无 timestamp、无 request_id。如果引擎侧未来实现轮询，无法区分新旧决策 |

### 4.3 链路修复建议

根据 `v5.0.1-execution-plan.md` 的设计意图:

1. **引擎侧**: gate 脚本在发射 `gate_block` 事件后，进入 `while true; sleep 1; read decision.json` 轮询循环
2. **服务端**: `handleDecision` 成功写入后，向所有 WS 客户端广播 `{ type: "decision_ack", data: { action, phase, timestamp } }`
3. **前端**: 监听 `decision_ack` 消息，移除或折叠对应的 GateBlockCard
4. **幂等**: decision.json 增加 `request_id` + `timestamp` 字段

---

## 5. 状态管理审查

**文件**: `gui/src/store/index.ts`

### 5.1 Store 结构

```typescript
interface AppState {
  events: AutopilotEvent[];           // 全量事件数组
  connected: boolean;                  // WebSocket 连接状态
  currentPhase: number | null;         // 当前 Phase
  sessionId: string | null;            // 会话 ID
  changeName: string | null;           // 变更名称
  mode: "full" | "lite" | "minimal" | null;  // 执行模式
  taskProgress: Map<string, TaskProgress>;    // 任务进度 Map
}
```

### 5.2 发现的问题

| 编号 | 严重度 | 描述 | 位置 |
|------|--------|------|------|
| SM-1 | **高** | **内存泄漏: events 无限增长**: `addEvents` 只追加不清理 (`[...state.events, ...newEvents]`)。长时间运行(例如多个 session)会导致数组无限增长。应设置上限(如最近 1000 条)或按 session 分段 | `store/index.ts:44` |
| SM-2 | **中** | **无事件去重**: 如 WS-3 所述，断线重连后 snapshot 会与已有事件合并，仅做了排序未做去重。应按 `sequence` 去重 | `store/index.ts:44` |
| SM-3 | **中** | **currentPhase 取自最新事件**: `latest?.phase` 在任何类型的事件(包括 gate_block)都会更新 currentPhase。gate_block 的 phase 是"目标 Phase"(即将进入但被阻断)，此时显示的 currentPhase 不准确 | `store/index.ts:66` |
| SM-4 | **中** | **taskProgress 是 Map 类型**: Zustand 对 Map 的 immutability 检测可能失效。虽然使用 `new Map(state.taskProgress)` 创建了新引用，但 Zustand 的 shallow 比较可能不会检测到 Map 内容变化 | `store/index.ts:47` |
| SM-5 | **低** | **mode/sessionId/changeName 取自最新事件**: 如果不同 session 的事件混入(理论上不应发生)，这些字段会被覆盖 | `store/index.ts:67-69` |
| SM-6 | **低** | **taskProgress 无清理**: 任务完成后进度数据永远保留在 Map 中。新 session 的任务可能与旧任务同名导致冲突 | `store/index.ts:47-61` |
| SM-7 | **信息** | `payload` 使用 `as any` 类型断言 (第51行)。丢失了类型安全性 | `store/index.ts:51` |

### 5.3 正面评价

- Zustand 选型正确: 轻量、无 boilerplate、React 19 兼容
- `addEvents` 按 `sequence` 排序保证事件顺序
- `taskProgress` 使用 Map 按 `task_name` 索引，后到的事件自然覆盖前序状态(最新快照语义)
- `reset()` 方法提供了完整的状态重置能力

---

## 6. 代码质量评估

### 6.1 TypeScript 类型安全

| 项目 | 评级 | 说明 |
|------|------|------|
| tsconfig 严格度 | **优秀** | `strict: true` + `noUnusedLocals` + `noUnusedParameters` + `noUncheckedIndexedAccess` (tsconfig.json:14-17) |
| AutopilotEvent 接口 | **良好** | `ws-bridge.ts:6-17` 定义了完整字段，与 event-bus-api.md 一致 |
| TaskProgress 接口 | **良好** | `store/index.ts:9-17` 字段完整 |
| payload 类型 | **不足** | `Record<string, unknown>` 过于宽泛，导致消费时需要 `as any` 或 `as number` 等断言 (store/index.ts:51, PhaseTimeline.tsx:34-35) |
| GateBlockCard props | **良好** | 接口定义清晰 (`GateBlockCardProps`，GateBlockCard.tsx:9-11) |

### 6.2 React 19 最佳实践

| 项目 | 评级 | 说明 |
|------|------|------|
| StrictMode | **优秀** | `main.tsx:6-9` 启用了 StrictMode |
| 函数组件 | **优秀** | 全部使用函数组件 + Hooks |
| useEffect 依赖 | **良好** | App.tsx:35 `[addEvents, setConnected]` 正确声明依赖 |
| 错误边界 | **不足** | 全局无 ErrorBoundary。任何组件渲染异常会导致整个应用白屏 |
| Suspense | **缺失** | 未使用 React 19 的 Suspense/use 等新特性 |
| Ref 清理 | **良好** | VirtualTerminal 正确在 cleanup 中 dispose 终端 (VirtualTerminal.tsx:66-68) |

### 6.3 组件可复用性

| 组件 | 可复用性 | 说明 |
|------|----------|------|
| PhaseTimeline | **中** | 硬编码 PHASE_LABELS，耦合具体业务 |
| ParallelKanban | **中** | 硬编码 Phase 5，但 TDD 步骤图标映射可提取 |
| GateBlockCard | **高** | 通过 props 回调解耦，可独立使用 |
| VirtualTerminal | **低** | 紧耦合 store events，无法独立接入其他数据源 |

### 6.4 构建配置

| 项目 | 评级 | 说明 |
|------|------|------|
| Vite 配置 | **良好** | 输出到 `gui-dist/`，sourcemap 关闭(生产模式)，proxy 正确配置 (vite.config.ts) |
| 依赖版本 | **优秀** | React 19, Zustand 5, Vite 6, TypeScript 5.7 -- 全部为最新稳定版 (package.json) |
| 缺少依赖 | **问题** | 组件中使用 Tailwind 类名但未安装 Tailwind CSS |

---

## 7. 缺失功能清单

### 7.1 对比 event-bus-api.md 的事件类型覆盖

| 事件类型 | event-bus-api.md 定义 | GUI 消费情况 | 状态 |
|----------|----------------------|-------------|------|
| `phase_start` | 已定义 | PhaseTimeline 消费 | **已实现** |
| `phase_end` | 已定义 | PhaseTimeline 消费 | **已实现** |
| `error` | 已定义 | **未消费** | **缺失** |
| `gate_pass` | 已定义 | **未消费** | **缺失** |
| `gate_block` | 已定义 | GateBlockCard + PhaseTimeline 消费 | **已实现** |
| `task_progress` | 已定义 (v5.0 规划) | ParallelKanban 消费 | **已实现** |

### 7.2 缺失的功能特性

| 功能 | 优先级 | 说明 |
|------|--------|------|
| `error` 事件渲染 | **高** | 引擎错误无法在 GUI 中展示。应添加错误通知/Toast 组件 |
| `gate_pass` 事件渲染 | **中** | Gate 通过时 PhaseTimeline 无视觉反馈(如绿色闪烁) |
| 全局 ErrorBoundary | **高** | 任何渲染异常导致白屏 |
| WebSocket 心跳 | **中** | 无法检测"半开"连接(TCP 连接存在但无响应) |
| 事件去重 | **中** | 断线重连后事件重复 |
| 决策 ACK 反馈 | **高** | 用户无法确认决策是否生效 |
| 终端 ANSI 着色 | **中** | xterm.js 的颜色能力未被利用 |
| 终端事件历史补全 | **高** | snapshot 时仅显示最后一条事件 |
| Tailwind CSS 安装或类名清理 | **中** | 样式不一致 |
| Session 切换/历史 | **低** | 无法查看历史 session 数据 |
| 主题切换 (亮/暗) | **低** | 仅暗色主题 |
| 键盘快捷键 | **低** | 无快捷操作 |

---

## 8. 风险矩阵

| 风险编号 | 风险描述 | 影响 | 可能性 | 风险等级 |
|----------|---------|------|--------|---------|
| R-1 | 双向反控链路断裂 -- 用户决策无法到达引擎 | **致命**: 核心功能失效 | **确定**: 代码中已验证无消费端 | **极高** |
| R-2 | 长时间运行内存泄漏 (events 无限增长) | **高**: 浏览器标签页崩溃 | **高**: 典型 autopilot 运行 10+ 分钟 | **高** |
| R-3 | VirtualTerminal 漏事件 (仅渲染最新一条) | **高**: 事件日志不完整 | **确定**: snapshot 时必然触发 | **高** |
| R-4 | Tailwind 类名失效导致样式缺失 | **中**: 看板和卡片布局异常 | **确定**: 未安装 Tailwind | **中** |
| R-5 | PhaseTimeline 状态优先级错误 (blocked 永久) | **中**: 误导用户 | **中**: 仅在 retry 成功后触发 | **中** |
| R-6 | 断线重连后事件重复 | **低**: 终端日志重复、统计偏差 | **中**: 网络波动时触发 | **中** |
| R-7 | 无 ErrorBoundary 导致白屏 | **高**: 完全不可用 | **低**: 组件代码较简单 | **中** |
| R-8 | gate_block 后 currentPhase 指向目标 Phase | **低**: 显示偏差 | **中**: gate_block 必然触发 | **低** |

---

## 9. 综合 GUI 评分

| 维度 | 权重 | 得分 | 加权分 |
|------|------|------|--------|
| 架构设计 | 20% | 75/100 | 15.0 |
| 数据渲染同步率 | 20% | 55/100 | 11.0 |
| 双向反控完整性 | 25% | 25/100 | 6.25 |
| XTerm 终端保真度 | 10% | 40/100 | 4.0 |
| 状态管理质量 | 10% | 60/100 | 6.0 |
| 代码质量/类型安全 | 10% | 70/100 | 7.0 |
| 视觉/UX 设计 | 5% | 85/100 | 4.25 |

**总计: 53.5/100 -> 四舍五入 54/100**

> 修正说明: 执行摘要中的 62 分为初步估计。经过逐维度加权计算，因双向反控链路断裂(权重最高的维度仅 25 分)和终端漏事件问题，实际得分下调至 **54/100**。

### 评分解读

- **架构骨架 (75)**: React 19 + Zustand + WebSocket + Bun 服务端的技术栈选型优秀，组件分层清晰
- **数据渲染 (55)**: 核心事件类型已对接，但存在状态优先级错误、事件遗漏、样式失效等问题
- **双向反控 (25)**: 前端和中继层已实现，但引擎侧完全缺失，属于**功能未完成**
- **终端保真 (40)**: xterm.js 集成正确，但仅作为事件格式化器使用，未发挥真实终端能力
- **状态管理 (60)**: Zustand 使用正确，但缺少去重、上限控制、Map 检测等健壮性处理
- **代码质量 (70)**: TypeScript 严格配置、正确的 cleanup、良好的组件接口设计
- **视觉 UX (85)**: Cyberpunk 风格 CSS 精致，动画效果专业，响应式布局完善

### 优先修复建议 (Top 5)

1. **[R-1] 实现引擎侧 decision.json 轮询** -- 补全双向反控最后一公里
2. **[R-3] 修复 VirtualTerminal 事件渲染** -- 追踪已渲染的 sequence，避免遗漏
3. **[R-2] 为 events[] 设置上限** -- `merged.slice(-MAX_EVENTS)` 防止内存泄漏
4. **[R-4] 解决 Tailwind/CSS 冲突** -- 要么安装 Tailwind，要么移除组件中的 Tailwind 类名
5. **[R-5] 修复 PhaseTimeline 状态优先级** -- 按 sequence 比较 gate_block 和 phase_end

---

> **注**: 标注"需浏览器实测验证"的项目:
> - PK-2 的 Tailwind 类名是否有部分 fallback 生效
> - VT-6 的 `convertEol` + `\r\n` 是否导致视觉上的双倍空行
> - SM-4 的 Zustand Map 检测是否在实际渲染中失效
> - 整体布局在 1280px / 768px 断点处的实际表现
>
> 等用户提供浏览器截图和实际事件日志后补充验证。
