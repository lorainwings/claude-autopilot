# v5.1.1 GUI 交互与双向反控审计报告

> 审计日期: 2026-03-14
> 审计员: Agent 6 — GUI 交互与双向反控体验审查员
> 审计范围: GUI 前端全组件 + WebSocket 通信层 + autopilot-server.ts + poll-gate-decision.sh 双向反控链路
> 基线对比: v5.0.4 GUI 审计报告 (综合 50/100)

---

## 1. 审计摘要

### 综合评分

| 维度 | 权重 | v5.0.4 得分 | v5.1.1 得分 | 加权分 | Delta |
|------|------|------------|------------|--------|-------|
| A. 双向反控闭环 | 30% | 42/100 | 82/100 | 24.60 | **+40** |
| B. 事件去重与内存管理 | 15% | 50/100 | 88/100 | 13.20 | **+38** |
| C. 终端渲染质量 | 15% | 40/100 | 72/100 | 10.80 | **+32** |
| D. 实时性与响应速度 | 10% | 55/100 | 60/100 | 6.00 | +5 |
| E. 错误状态展示与恢复 | 10% | 45/100 | 50/100 | 5.00 | +5 |
| F. 用户体验流畅度 | 5% | 60/100 | 65/100 | 3.25 | +5 |
| G. 代码质量 | 15% | 70/100 | 72/100 | 10.80 | +2 |
| **总计** | **100%** | **50** | — | **73.65** | **+24** |

**总分: 74/100** (从 v5.0.4 的 50 分跃升至 74 分，涨幅 +24 分)

### 核心结论

v5.1.1 完成了三项关键修复 — DC-PATH 路径统一、Zustand 去重+截断、VirtualTerminal 增量渲染 — 使 GUI 交互系统从"勉强及格"跨入"良好"区间。双向反控从"架构存在但实际断裂"提升至"端到端可运行"。距 80+ 优秀线仍有 6 分差距，瓶颈在于 ACK 反馈缺失、终端无 ANSI 着色、连接状态轮询等遗留项。

---

## 2. 双向反控闭环分析 (82/100, v5.0.4: 42)

### 2.1 DC-PATH 致命缺陷修复验证 — PASS

v5.0.4 的唯一致命缺陷：服务端写入 `{projectRoot}/.autopilot/decision.json`，引擎侧轮询 `{change_dir}/context/decision.json`，路径完全不同。

**v5.1.1 修复方案**: 服务端新增 `resolveDecisionFile()` 函数，通过读取 `.autopilot-active` 锁文件动态推导 change_dir。

**服务端写入路径** (`scripts/autopilot-server.ts` 第 124-141 行):

```typescript
async function resolveDecisionFile(): Promise<string | null> {
  try {
    const lockContent = await readFile(LOCK_FILE, "utf-8");
    let changeName: string;
    try {
      const lockData = JSON.parse(lockContent);
      changeName = lockData.change || "";
    } catch {
      changeName = lockContent.trim();  // 旧版纯文本回退
    }
    if (!changeName) return null;
    return join(CHANGES_DIR, changeName, "context", "decision.json");
  } catch {
    return null;
  }
}
```

**引擎侧轮询路径** (`scripts/poll-gate-decision.sh` 第 39-41 行):

```bash
CONTEXT_DIR="${CHANGE_DIR}context"
DECISION_FILE="${CONTEXT_DIR}/decision.json"
```

### 路径等价性证明

| 路径组件 | 服务端 (Node.js `join`) | 引擎侧 (Bash 拼接) |
|---------|------------------------|-------------------|
| 基础路径 | `{projectRoot}/openspec/changes/` | `{CHANGE_DIR}` (含尾部 `/`) |
| 变更名 | `{changeName}/` | 内嵌于 `CHANGE_DIR` |
| 上下文 | `context/` | `context/` |
| 文件名 | `decision.json` | `decision.json` |
| **最终** | `{root}/openspec/changes/{name}/context/decision.json` | `{root}/openspec/changes/{name}/context/decision.json` |

**100% 字符串等价。DC-PATH 已修复。**

### 2.2 完整链路拓扑 (v5.1.1)

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
autopilot-server.ts websocket.message handler       -- autopilot-server.ts:195-205
    |
    v
handleDecision() → resolveDecisionFile()            -- autopilot-server.ts:126-141
    |
    v
写入: {projectRoot}/openspec/changes/{name}/context/decision.json
    |
    v (路径已统一！)
    |
poll-gate-decision.sh 轮询同一路径                    -- poll-gate-decision.sh:41,84
    |
    v (1秒轮询间隔, 最多300秒)
    |
    v
读取 decision.json → 验证 action ∈ {override,retry,fix}
    |
    v
清理文件 + 发射 gate_decision_received 事件
    |
    v
返回决策 JSON → gate 脚本执行对应动作
```

**端到端链路已完全贯通。**

### 2.3 锁文件安全性分析

- `resolveDecisionFile()` 每次请求重新读取 `.autopilot-active` (非缓存)
- 支持 JSON 格式和纯文本回退 (第 130-134 行)
- `changeName` 为空时返回 `null` (第 136 行)，`handleDecision()` 会打印错误而不是写入错误路径
- `mkdir -p` 确保 context 目录存在 (第 151 行)

### 2.4 剩余缺陷

| 编号 | 严重度 | 描述 | 影响 |
|------|--------|------|------|
| DC-ACK | **高** | 服务端写入 decision 后不向前端发送 ACK 确认。GateBlockCard 2 秒后自动解除 loading (第 27 行)，用户不知决策是否被引擎接收 | 用户体验 |
| DC-CARD | **中** | gate_block 事件消费后卡片不消失。引擎恢复运行后旧 gate_block 仍在 events[] 中，卡片持续显示 | 视觉误导 |
| DC-FIX | **中** | `fix` 动作需要 `fix_instructions` (SKILL.md:117)，但 GateBlockCard 未提供文本输入框 | 功能缺失 |
| DC-OVERRIDE | **低** | `poll-gate-decision.sh` 未校验 Phase 4->5/5->6 禁止 override (SKILL.md:122) | 安全风险 |
| DC-ERR | **低** | `resolveDecisionFile()` 返回 null 时仅 console.error，不向前端推送失败原因 | 错误透明度 |

---

## 3. 事件去重与内存管理分析 (88/100, v5.0.4: 50)

### 3.1 Zustand Store 去重 + 截断 — PASS

**v5.0.4 缺陷**: events[] 无限增长 (SM-1)、断线重连后事件不去重 (WS-3)。

**v5.1.1 修复** (`gui/src/store/index.ts` 第 42-49 行):

```typescript
addEvents: (newEvents) =>
  set((state) => {
    // Deduplicate by sequence, then cap at 1000 events
    const seen = new Set(state.events.map((e) => e.sequence));
    const unique = newEvents.filter((e) => !seen.has(e.sequence));
    const merged = [...state.events, ...unique]
      .sort((a, b) => a.sequence - b.sequence)
      .slice(-1000);
```

### 验证矩阵

| 场景 | v5.0.4 行为 | v5.1.1 行为 | 判定 |
|------|-----------|-----------|------|
| 断线重连 snapshot 含重复事件 | 仅排序不去重，重复条目堆积 | `Set` 基于 `sequence` 去重，重复事件被过滤 | **PASS** |
| events[] 无限增长 | 无上限，长时间运行内存溢出 | `.slice(-1000)` 硬上限 1000 条 | **PASS** |
| 排序稳定性 | 仅排序 | 去重后排序再截断，保留最新 1000 条 | **PASS** |
| sequence 唯一性保证 | — | `next_event_sequence()` flock 原子计数器生成 | **PASS** |

### 性能分析

- 每次 `addEvents` 创建临时 `Set` 大小 <= 1000 (O(n))
- `filter` + `sort` + `slice` 总计 O(n log n)，n <= 1000，开销可接受
- 典型单次 autopilot 运行产生 50-200 事件，远低于 1000 上限

### 3.2 剩余问题

| 编号 | 严重度 | 描述 |
|------|--------|------|
| SM-SEL | **中** | 所有组件 `const { events, ... } = useStore()` 全量订阅，任何字段变更触发全量重渲染。应使用 `useStore(selector)` |
| SM-MAP | **中** | `taskProgress` 使用 `Map` 类型，Zustand 的 shallow 比较可能对 Map 失效，导致不必要的重渲染 |
| SM-CLEAN | **低** | `taskProgress` Map 无自动清理机制，任务完成后进度数据永久保留 |

---

## 4. 终端渲染质量分析 (72/100, v5.0.4: 40)

### 4.1 VirtualTerminal 增量渲染 — PASS

**v5.0.4 缺陷**: `useEffect([events])` 仅渲染 `events[events.length - 1]`，snapshot 推送的 N 条事件中 N-1 条丢失 (VT-2)。

**v5.1.1 修复** (`gui/src/components/VirtualTerminal.tsx` 第 16, 73-88 行):

```typescript
const lastRenderedSequence = useRef<number>(-1);  // 持久化追踪

useEffect(() => {
  const term = xtermRef.current;
  if (!term || events.length === 0) return;

  // 渲染所有 sequence > lastRenderedSequence 的事件（增量）
  const newEvents = events.filter(
    (e) => e.sequence > lastRenderedSequence.current
  );
  if (newEvents.length === 0) return;

  for (const event of newEvents) {
    const timestamp = new Date(event.timestamp).toLocaleTimeString();
    const line = `[${timestamp}] ${event.type.toUpperCase()} | Phase ${event.phase} (${event.phase_label})\r\n`;
    term.write(line);
  }

  lastRenderedSequence.current = newEvents[newEvents.length - 1].sequence;
}, [events]);
```

### 修复验证矩阵

| 场景 | v5.0.4 行为 | v5.1.1 行为 | 判定 |
|------|-----------|-----------|------|
| snapshot 推送 50 条历史事件 | 仅渲染第 50 条 | `lastRenderedSequence = -1`，全部 50 条被过滤为 `newEvents`，逐条写入 | **PASS** |
| 新事件逐条到达 | 仅渲染最后一条 | `filter(sequence > lastRendered)` 精确命中新事件 | **PASS** |
| 断线重连后 snapshot | 仅渲染最后一条 | `lastRenderedSequence` ref 保留断线前位置，仅渲染新增部分 | **PASS** |
| store 截断后 events 变短 | — | 已渲染事件被截断不影响 `lastRenderedSequence` ref | **PASS** |

### 4.2 渲染格式分析

**当前输出格式** (第 83 行):
```
[14:32:05] PHASE_START | Phase 3 (OpenSpec)
[14:32:10] GATE_BLOCK | Phase 3 (OpenSpec)
```

### 4.3 剩余问题

| 编号 | 严重度 | 描述 | 文件:行号 |
|------|--------|------|----------|
| VT-ANSI | **中** | 终端配置了完整 16 色 ANSI 调色板 (第 29-44 行) 但写入纯文本，颜色配置形同虚设 | VirtualTerminal.tsx:29-44,83 |
| VT-INFO | **中** | 仅显示 `type`/`phase`/`phase_label`，丢失 `gate_score`/`error_message`/`duration_ms` 等关键信息 | VirtualTerminal.tsx:83 |
| VT-STDIN | **低** | 未设置 `disableStdin: true`，用户可能误以为终端可交互 | VirtualTerminal.tsx:22 |
| VT-EOL | **低** | `convertEol: true` + 手动 `\r\n` 可能导致双倍换行 | VirtualTerminal.tsx:48,83 |

---

## 5. 实时性与响应速度分析 (60/100)

### 5.1 事件推送延迟链路

| 环节 | 延迟 | 机制 |
|------|------|------|
| events.jsonl 写入 → 服务端感知 | ~0-50ms | `fs.watch()` 内核通知 (fallback: 500ms 轮询) |
| 服务端解析 → WS 推送 | <1ms | JSON.parse + 遍历客户端 |
| WS 传输 → 前端接收 | <1ms | localhost WebSocket |
| Zustand 更新 → React 渲染 | ~16ms | React 批量更新 |
| **总端到端延迟** | **<70ms** | 正常路径 (非 fallback 轮询) |

### 5.2 决策反控延迟

| 环节 | 延迟 | 机制 |
|------|------|------|
| 用户点击 → WS 发送 | <1ms | 同步调用 |
| WS → 服务端处理 | <5ms | readFile + writeFile |
| 文件写入 → 引擎侧发现 | **0-1000ms** | `poll-gate-decision.sh` 1 秒轮询间隔 |
| **总反控延迟** | **<1100ms** | 最坏情况 |

反控延迟受限于引擎侧 1 秒轮询间隔，合理但非最优。可通过 inotifywait/fswatch 降至 <100ms，但当前 1 秒已满足可用性要求。

### 5.3 连接状态检测

**文件**: `App.tsx` 第 26-28 行

```typescript
const checkConnection = setInterval(() => {
  setConnected(wsBridge.connected);
}, 1000);
```

仍使用 1 秒轮询而非事件驱动。WSBridge 的 `onopen`/`onclose` 已有事件回调能力，但未在 App 层暴露 `onStatusChange` 接口。最坏延迟 1 秒 + 不必要的 CPU 开销。

---

## 6. 错误状态展示与恢复分析 (50/100)

### 6.1 GateBlockCard 错误展示

- 展示字段: Phase 名称、gate_score、error_message (第 42-51 行)
- 三个决策按钮: Retry / Fix / Override (第 54-76 行)
- Loading 状态: 按钮 disabled + "Sending..." 文案 (第 60-61 行)

### 6.2 缺陷

| 编号 | 严重度 | 描述 |
|------|--------|------|
| ERR-BOUNDARY | **高** | 全局无 React ErrorBoundary，组件异常导致白屏 |
| ERR-ACK | **高** | 决策发送后无 ACK 反馈，loading 状态 2 秒后自动清除而非等待确认 |
| ERR-CARD | **中** | gate_block 解除后卡片不消失 (基于 events 过滤，旧事件永远存在) |
| ERR-WS | **中** | WebSocket 断线仅在 header 显示状态，无 toast/banner 级别的明显提示 |
| ERR-EMPTY | **低** | 无事件时终端和时间轴为空白，无"等待连接/等待事件"引导提示 |

---

## 7. 用户体验流畅度分析 (65/100)

### 7.1 视觉设计

- CSS 设计系统完整: IBM Plex 字体家族、Mission Control 暗色主题、扫描线特效 (index.css)
- 状态颜色映射清晰: emerald=成功、amber=运行中、rose=阻断 (index.css:12-20)
- Phase 节点六边形裁切 + 发光动画 (index.css:390-450)
- 响应式布局: 1280px/768px 两级断点 (index.css:727-785)
- 入场动画: 依次 fadeIn (index.css:791-823)

### 7.2 交互品质

| 项目 | 评级 | 说明 |
|------|------|------|
| Phase Timeline 交互 | 良好 | hover 效果、active 高亮、running 脉搏动画 |
| GateBlockCard 交互 | 中等 | 按钮 hover/disabled 状态完整，但无确认弹窗和 ACK |
| VirtualTerminal | 中等 | xterm.js FitAddon + resize 处理，但无 ANSI 着色 |
| ParallelKanban | 良好 | 任务卡片排列、TDD 步骤图标、重试计数显示 |
| 连接状态 | 中等 | header 右上角小字，不够显眼 |

### 7.3 Tailwind CSS 未安装

`package.json` 中未包含 `tailwindcss` 依赖，但 `ParallelKanban.tsx` 和 `GateBlockCard.tsx` 中大量使用 Tailwind 类名 (如 `bg-gray-900`、`border-red-500/50`)。这些类名不会生效，组件实际样式依赖 `index.css` 中的同名 CSS 类覆盖。

**影响**: `index.css` 中 `.gate-block-card`、`.parallel-kanban`、`.task-card` 等选择器覆盖了 Tailwind 类名的视觉效果，实际渲染正确。但 `.grid-cols-1`、`.flex-1` 等布局类若无 CSS 覆盖则会失效。

---

## 8. 代码质量分析 (72/100)

### 8.1 TypeScript 类型安全

| 项目 | 评级 | 位置 |
|------|------|------|
| `AutopilotEvent.payload` | 不足 | `ws-bridge.ts:16` — `Record<string, unknown>` 过于宽泛 |
| `payload as any` | 不足 | `store/index.ts:56` — 丢失类型安全 |
| `endEvent.payload.status as typeof status` | 不足 | `PhaseTimeline.tsx:34` — 无运行时校验 |
| WSBridge 类设计 | 良好 | 完整的 connect/disconnect/reconnect 生命周期 |
| Zustand Store 接口 | 良好 | `AppState` 类型定义完整 |

### 8.2 React 最佳实践

| 项目 | 评级 |
|------|------|
| StrictMode | 良好 — main.tsx 启用 |
| 函数组件 + Hooks | 良好 — 全部使用 |
| useEffect 依赖 | 良好 — App.tsx:35 正确声明 |
| ErrorBoundary | **缺失** — 异常导致白屏 |
| Ref 清理 | 良好 — VirtualTerminal 正确 dispose |
| 选择器使用 | 不足 — 全量订阅 store |

### 8.3 服务端代码质量

| 项目 | 评级 |
|------|------|
| `resolveDecisionFile()` 错误处理 | 良好 — try/catch + null 返回 |
| WS 客户端管理 | 良好 — Set 管理 + send 失败时清理 |
| 事件文件监听 | 良好 — fs.watch + fallback 轮询 |
| 锁文件格式兼容 | 良好 — JSON + 纯文本双重解析 |
| CORS/MIME | 良好 — 完整配置 |
| ping/pong 心跳 | 部分 — 服务端支持但客户端未发送 |

---

## 9. v5.0.4 → v5.1.1 全量 Delta 分析

### 9.1 已修复项

| v5.0.4 缺陷 | 严重度 | v5.1.1 状态 | 分数影响 |
|-------------|--------|-----------|---------|
| DC-PATH: decision.json 路径不一致 | **致命** | **已修复** — `resolveDecisionFile()` 动态推导路径 | +40 (双向反控) |
| SM-1: events[] 无限增长 | **高** | **已修复** — `.slice(-1000)` 硬上限 | +20 (内存管理) |
| WS-3: 事件去重缺失 | **中** | **已修复** — `Set` 基于 sequence 去重 | +15 (内存管理) |
| VT-2: 终端批量事件丢失 | **高** | **已修复** — `lastRenderedSequence` ref 增量渲染 | +30 (终端渲染) |

### 9.2 未修复项 (从 v5.0.4 延续)

| 缺陷 | 严重度 | 状态 | 扣分影响 |
|------|--------|------|---------|
| DC-ACK: 决策无 ACK 反馈 | **高** | **未修复** | -10 (双向反控) |
| DC-CARD: gate_block 卡片不消失 | **中** | **未修复** | -3 (错误展示) |
| DC-FIX: fix 无输入机制 | **中** | **未修复** | -3 (双向反控) |
| WS-1: 连接状态轮询 | **中** | **未修复** | -3 (实时性) |
| VT-ANSI: 终端无着色 | **中** | **未修复** | -5 (终端渲染) |
| VT-INFO: 终端信息缺失 | **中** | **未修复** | -5 (终端渲染) |
| PT-1: gate_block 状态优先级错误 | **中** | **未修复** | -3 (数据渲染) |
| SM-SEL: Zustand 全量订阅 | **中** | **未修复** | -3 (性能) |
| PK-TW: Tailwind 未安装 | **中** | **未修复** | -2 (代码质量) |
| ERR-BOUNDARY: 无 ErrorBoundary | **高** | **未修复** | -5 (错误恢复) |
| DC-OVERRIDE: override 无 phase 校验 | **低** | **未修复** | -1 (安全) |
| VT-STDIN: 终端可接受输入 | **低** | **未修复** | -1 (体验) |

### 9.3 分数跃升分析

```
v5.0.4 总分: 50/100
v5.1.1 总分: 74/100
Delta:       +24

主要贡献:
  DC-PATH 修复 → 双向反控 42→82 (+40) × 30% 权重 = +12 加权分
  SM-1/WS-3 修复 → 内存管理 50→88 (+38) × 15% 权重 = +5.7 加权分
  VT-2 修复 → 终端渲染 40→72 (+32) × 15% 权重 = +4.8 加权分
  合计关键修复带来约 +22.5 加权分

剩余 +1.5 分来自代码质量和服务端改善 (resolveDecisionFile 设计)
```

---

## 10. 剩余缺陷清单与修复建议

### P1 — 高优先级 (冲击 80+ 优秀线)

| 优先级 | 缺陷 | 修复方案 | 工作量 | 预计提分 |
|--------|------|----------|--------|---------|
| P1-1 | DC-ACK: 决策无 ACK | 服务端 `handleDecision` 成功后广播 `{ type: "decision_ack", data }` 到所有 WS 客户端；前端监听后更新 GateBlockCard 状态 | 中 | +3 |
| P1-2 | ERR-BOUNDARY: 无错误边界 | 添加全局 React ErrorBoundary，捕获异常显示降级 UI | 小 | +2 |
| P1-3 | VT-ANSI: 终端无着色 | 为不同事件类型添加 ANSI 前缀: `gate_block` → `\x1b[31m`(红)、`phase_start` → `\x1b[32m`(绿)、`gate_pass` → `\x1b[36m`(青) | 小 | +2 |

### P2 — 中优先级

| 优先级 | 缺陷 | 修复方案 | 工作量 |
|--------|------|----------|--------|
| P2-1 | DC-CARD | 监听 `gate_decision_received` 或 `phase_start` 事件后隐藏卡片 | 小 |
| P2-2 | WS-1 | WSBridge 添加 `onStatusChange(cb)` 方法，替代 setInterval | 小 |
| P2-3 | SM-SEL | 使用 `useStore(state => state.events)` 精确订阅 | 小 |
| P2-4 | VT-INFO | 终端渲染增加 payload 关键字段 (`gate_score`, `duration_ms`, `error_message`) | 小 |
| P2-5 | PT-1 | 按 `sequence` 比较 `gate_block` 和 `phase_end`，取更新的状态 | 小 |
| P2-6 | DC-FIX | GateBlockCard 为 fix 动作增加 `fix_instructions` 文本输入框 | 中 |

### P3 — 低优先级

| 优先级 | 缺陷 | 修复方案 | 工作量 |
|--------|------|----------|--------|
| P3-1 | PK-TW | 安装 Tailwind CSS 或将类名替换为纯 CSS | 中 |
| P3-2 | DC-OVERRIDE | `poll-gate-decision.sh` 添加 Phase 号校验 | 小 |
| P3-3 | SM-MAP | `taskProgress` 改为 `Record<string, TaskProgress>` | 小 |
| P3-4 | VT-STDIN | 终端配置添加 `disableStdin: true` | 小 |

---

## 11. 80+ 优秀线路径

完成 P1 三项修复后预计可达:

| 维度 | v5.1.1 | 修复后预估 |
|------|--------|-----------|
| 双向反控闭环 | 82 | 88 (+ACK) |
| 事件去重与内存 | 88 | 88 (无变化) |
| 终端渲染质量 | 72 | 80 (+ANSI) |
| 实时性 | 60 | 60 (无变化) |
| 错误状态展示 | 50 | 62 (+ErrorBoundary +ACK) |
| 用户体验 | 65 | 68 (附带提升) |
| 代码质量 | 72 | 75 (+ErrorBoundary) |
| **加权总分** | **74** | **~81** |

**结论**: 完成 P1 三项修复 (ACK 反馈 + ErrorBoundary + ANSI 着色) 即可突破 80 分优秀线。三项修复总工作量约 2-3 小时。

---

## 12. 总体结论

v5.1.1 实现了 GUI 交互系统的关键性跃升:

1. **双向反控闭环真正贯通**: DC-PATH 修复使 `resolveDecisionFile()` 通过锁文件动态推导路径，与 `poll-gate-decision.sh` 100% 对齐。用户点击决策按钮后，引擎可在 1 秒内响应。
2. **内存安全有保障**: Zustand store 的 `Set` 去重 + `.slice(-1000)` 截断消除了内存溢出风险。
3. **终端渲染无损还原**: `lastRenderedSequence` ref 增量渲染机制确保 snapshot 和实时事件均完整显示。
4. **分数从 50 跃升至 74**: 涨幅 +24 分，主要来自三项关键修复的乘数效应。

距离 80+ 优秀线还需补全 ACK 反馈、ErrorBoundary 和 ANSI 着色三项。当前 74 分已处于"良好"区间，系统具备实际可用性。
