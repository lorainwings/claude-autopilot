# GUI V2 交互与状态机边界极限测试报告 (v5.3)

> 审计时间: 2026-03-14
> 审计员: Agent 6 — GUI V2 交互与状态机边界极限测试员
> 审计范围: commit `2ff233e` (G1-G13 修复) 全部 GUI 源码 + WebSocket 服务端

---

## 执行摘要

本报告针对 v5.3 的 13 项 GUI 缺口修复 (G1-G13) 进行逐项源码级验证。审计覆盖 10 个前端源文件 + 2 个服务端文件。**13 项修复全部 PASS**，代码实现与修复目标一致。发现 3 项遗留风险建议跟进。

**总评分: 93/100**

---

## 1. G1-G13 修复逐项验证

| 编号 | 修复项 | 验证结果 | 证据/代码引用 |
|------|--------|----------|---------------|
| G1 | GateBlock 幽灵复现 | **PASS** | `GateBlockCard.tsx:27-29` — 过滤同 phase 的 `gate_pass` 事件，若最新 pass 的 sequence > 最新 block 的 sequence 则 `return null`，正确清除卡片 |
| G2 | decision_ack 竞态 | **PASS** | `store/index.ts:205-213` — `addEvents` 中检测新 `gate_block` 的 sequence > `lastAckedBlockSequence` 时自动重置 `decisionAcked=false`；`App.tsx:32-39` 事件驱动记录 `lastAckedBlockSequence`，替代定时器方案 |
| G3 | loading 状态不复位 | **PASS** | `GateBlockCard.tsx:36-46` — `handleDecision` 在 `try` 成功后 `setLoading(null)`，`catch` 中亦 `setLoading(null)`，双路径均复位 |
| G4 | Phase Running 恢复 | **PASS** | `store/index.ts:112-121` — `selectPhaseDurations` 使用 `findLast` 获取最新 `gate_block` 和 `gate_pass`，仅当 `gateBlock.sequence > gatePass.sequence` 时才标记 `blocked`，否则回落到 `running` 状态 |
| G5 | 动态阶段数 | **PASS** | `store/index.ts:75-79` — `MODE_PHASES` 字典定义 full=[0-7]、lite=[0,1,5,6,7]、minimal=[0,1,5,7]；`selectActivePhaseIndices` 从事件中提取 mode 动态选择 |
| G6 | ParallelKanban 条件标签 | **PASS** | `ParallelKanban.tsx:33-35` — 从 `runningTasks.length > 1` 或 `task_total > 1` 推断并行模式；从 `tdd_step !== undefined` 推断 TDD 模式，条件渲染 "并行" / "TDD 已开启" 标签 |
| G7 | ANSI 转义码 + payload 详情 | **PASS** | `VirtualTerminal.tsx:14-23` — 定义 8 种事件类型的 ANSI 颜色映射 (红绿黄蓝青品)；`VirtualTerminal.tsx:103-123` — switch/case 按事件类型追加 gate_score、error_message、duration_ms、task_name、tdd_step 等 payload 详情 |
| G8 | 初始空状态占位符 | **PASS** | `App.tsx:117-126` — `!hasEvents` 时渲染 spinner 动画 + 条件文案 "等待事件流..." / "正在连接引擎..." |
| G9 | Running 计时器实时刷新 | **PASS** | `PhaseTimeline.tsx:26-32` 和 `TelemetryDashboard.tsx:33-40` — 双组件均实现 `hasRunning` 检测 + 1s `setInterval` 强制 re-render，`useEffect` 清理定时器 |
| G10 | TaskProgressPayload 类型守卫 | **PASS** | `store/index.ts:28-31` — `isTaskProgressPayload` 函数检查 `task_name`(string)、`status`(string)、`task_index`(number) 三字段；`store/index.ts:190` 中使用守卫替代 `as any` |
| G11 | ErrorBoundary 降级 UI | **PASS** | `ErrorBoundary.tsx:1-39` — 标准 React Class Component 实现 `getDerivedStateFromError`；降级 UI 包含错误标题、错误信息 `<pre>` 展示、"重试" 按钮(`setState({error:null})`)；`main.tsx:9` 包裹 `<App/>` |
| G12 | 版本号 vite define 注入 | **PASS** | `vite.config.ts:7-9` — 读取 `plugin.json` 获取版本号；`vite.config.ts:15` — `define: { __PLUGIN_VERSION__: JSON.stringify(...) }`；`App.tsx:16` 声明 + `App.tsx:75` 使用 |
| G13 | SVG 环形图 CSS 变量 | **PASS** | `TelemetryDashboard.tsx:69-77` — 环形图的 `stroke` 使用 `style={{ stroke: "var(--color-surface)" }}` 和 `style={{ stroke: "var(--color-cyan)" }}`，替代硬编码颜色值 |

---

## 2. 状态机分析

### 2.1 GateBlock 生命周期状态机

```
[无阻断] → gate_block事件 → [GateBlockCard显示]
  → 用户点击 retry/fix/override → sendDecision → 写入 decision.json
  → 服务端 decision_ack 广播 → decisionAcked=true → [卡片隐藏]
  → 新 gate_block 到达 (seq > lastAckedBlockSequence) → decisionAcked=false → [卡片重新显示]
  → gate_pass 到达 (seq > latest block seq) → [卡片隐藏]
```

**安全性评估**: 状态机设计合理，有两条独立的清除路径 (ACK 驱动 + gate_pass 驱动)，防止单点故障导致卡片无法消失。`lastAckedBlockSequence` 机制解决了 G2 竞态问题。

### 2.2 Phase 状态派生

```
pending → phase_start → running → phase_end → ok/warning
                          ↓
                     gate_block → blocked → gate_pass → running (恢复)
```

**安全性评估**: `selectPhaseDurations` 使用 `findLast` 确保取最新的 gate 事件做判定，避免历史事件干扰。`blocked` 状态仅在 `gateBlock.sequence > gatePass.sequence` 时生效，G4 修复有效。

### 2.3 潜在边界场景

| 场景 | 分析 |
|------|------|
| 快速连续两次 gate_block | 第二次 block 的 sequence 更大，`lastAckedBlockSequence` 仍指向第一次，`decisionAcked` 会被重置 — **安全** |
| gate_pass 在 decision_ack 之前到达 | G1 的 sequence 比较会直接隐藏卡片 — **安全** |
| WebSocket 断开重连后 snapshot 重播 | `addEvents` 使用 Set 去重，不会产生重复事件 — **安全** |
| 事件超过 1000 条 | `.slice(-1000)` 截断旧事件，可能导致 `gate_block` 被截断但 `gate_pass` 保留，理论上不影响 (pass 也会被截断) — **低风险** |

---

## 3. WebSocket 链路分析

### 3.1 消息协议

| 方向 | 消息类型 | 格式 | 处理位置 |
|------|----------|------|----------|
| Server → Client | `snapshot` | `{type:"snapshot", data: AutopilotEvent[]}` | `ws-bridge.ts:48-49` |
| Server → Client | `event` | `{type:"event", data: AutopilotEvent}` | `ws-bridge.ts:50-51` |
| Server → Client | `decision_ack` | `{type:"decision_ack", data:{action,phase,timestamp}}` | `ws-bridge.ts:52-56` |
| Client → Server | `decision` | `{type:"decision", data:{action,phase,reason?}}` | `ws-bridge.ts:98-103` |
| Client → Server | `ping` | `{type:"ping"}` | `autopilot-server.ts:215-216` |

### 3.2 重连机制

- 初始延迟: 1000ms，指数退避系数 1.5x，上限 10000ms
- `scheduleReconnect` 防重入 (`if (this.reconnectTimer) return`)
- 重连成功后重置延迟 (`onopen` 中 `reconnectDelay = 1000`)
- **评估**: 重连机制健全，但缺少重连次数上限（无限重试）

### 3.3 Decision ACK 防重验证

- **客户端**: `wsBridge.onDecisionAck` 直接调用 `setDecisionAcked(true)`，无幂等保护。但由于 `decisionAcked` 是布尔值，多次设为 `true` 无副作用 — **安全**
- **服务端**: `handleDecision` 写入文件后立即广播 `decision_ack` 给**所有客户端**，无去重。多客户端场景下每个客户端都会收到 ACK — **符合预期**
- **竞态窗口**: 从 `writeFile` 到广播之间无原子性保证，但 `decision.json` 在 `poll-gate-decision.sh` 侧有独立轮询验证 — **可接受**

### 3.4 Decision 投递可靠性

- `sendDecision` 在 `!this.connected` 时抛异常，`App.tsx:58` catch 并 `console.error` — 但**未向用户显示错误提示**
- `handleDecision` 服务端写文件失败仅 `console.error`，未返回错误给客户端

---

## 4. fix_instructions 投递链路

### 完整链路追踪

```
1. 用户输入 → GateBlockCard.tsx textarea (fixInstructions state)
2. 点击 "修复" → handleDecision("fix")
3. action === "fix" && fixInstructions.trim() → reason = fixInstructions.trim()
   (GateBlockCard.tsx:38-39)
4. onDecision(action="fix", phase, reason) → App.tsx handleDecision
5. wsBridge.sendDecision({action:"fix", phase, reason})
   (ws-bridge.ts:102 → JSON.stringify({type:"decision", data:{action,phase,reason}}))
6. autopilot-server.ts:217 → handleDecision(msg.data)
7. writeFile(decisionFile, JSON.stringify(decision)) → decision.json 写入磁盘
   (autopilot-server.ts:152)
8. poll-gate-decision.sh:86-111 轮询读取 decision.json
9. decision.setdefault('reason', '') → reason 字段传递到引擎
   (poll-gate-decision.sh:102)
```

**验证结论**:
- **PASS**: fix_instructions 从前端 textarea → WebSocket → 文件 → 引擎的完整链路畅通
- **注意**: 仅 `action === "fix"` 时传递 reason，retry/override 的 reason 始终为 undefined — **符合设计意图**
- **边界**: 空字符串 fixInstructions 不会传递 reason (`fixInstructions.trim()` 为空时 reason = undefined) — **正确**

---

## 5. Error Boundary 降级验证

### 5.1 实现完整性

| 检查项 | 结果 |
|--------|------|
| `getDerivedStateFromError` 捕获渲染错误 | **PASS** — `ErrorBoundary.tsx:14-16` |
| 降级 UI 显示错误信息 | **PASS** — `<pre>` 展示 `error.message`，含滚动和高度限制 |
| 恢复按钮 | **PASS** — "重试" 按钮 `setState({error: null})` 重置错误状态 |
| 包裹层级正确 | **PASS** — `main.tsx:9` 在 `<StrictMode>` 内包裹 `<App/>` |
| 样式降级友好 | **PASS** — 使用 Tailwind 类名，背景 `bg-void`，文本颜色对比度良好 |

### 5.2 局限性

- `ErrorBoundary` 仅捕获**渲染阶段**错误，不捕获事件处理器 / async 错误
- WebSocket 通信错误不会触发 ErrorBoundary（在 `ws-bridge.ts` 中 try-catch 处理）
- 无 `componentDidCatch` 实现，不记录错误日志到远程服务 — 可接受（当前为本地工具）

---

## 6. 评分

| 维度 | 得分 | 满分 | 说明 |
|------|------|------|------|
| G1-G13 修复验证 | 39 | 39 | 13 项全部 PASS (每项 3 分) |
| 状态机边界安全性 | 18 | 20 | 1000 事件截断边界存在理论风险；无 phase 回退保护 |
| WebSocket 可靠性 | 16 | 20 | 重连无上限；decision 发送失败无 UI 反馈；无心跳检测 (仅 1s 轮询 connected) |
| 错误降级能力 | 10 | 10 | ErrorBoundary 实现完整，降级 UI 信息充分 |
| fix_instructions 投递准确性 | 10 | 11 | 链路完整，但 reason 字段在 poll-gate-decision.sh 中仅 setdefault 空字符串，未做长度限制 |
| **总分** | **93** | **100** | |

---

## 7. 遗留风险与建议

### 高优先级

1. **Decision 发送失败无用户反馈**: `App.tsx:58` 的 `console.error` 对用户不可见。建议在 `GateBlockCard` 中增加 error toast 或内联错误提示，避免用户误以为决策已发送。

### 中优先级

2. **WebSocket 重连无上限**: `ws-bridge.ts` 的指数退避在网络长期断开时会无限重试（每 10s 一次）。建议增加最大重试次数（如 100 次），超限后显示 "连接已断开，请刷新页面" 提示。

3. **fix_instructions 无长度限制**: textarea 无 `maxLength` 属性，超长内容可能导致 decision.json 文件过大。建议在前端限制 2000 字符。

### 低优先级

4. **connected 状态轮询延迟**: `App.tsx:42-44` 使用 1s setInterval 检测连接状态，最坏情况下断开 1s 后 UI 才反映。建议改为 `onopen`/`onclose` 事件回调直接更新。

5. **事件截断后的 gate 状态一致性**: `.slice(-1000)` 截断可能导致旧的 `gate_block` 被移除但对应的 `gate_pass` 尚未到达的窗口期出现状态不一致。概率极低但存在理论风险。
