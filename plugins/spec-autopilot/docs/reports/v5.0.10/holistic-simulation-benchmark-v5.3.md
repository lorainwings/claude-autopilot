# 全链路整体性真实业务仿真测试报告 (v5.3)

> 审计日期: 2026-03-14
> 审计范围: Phase 0-7 全流转 + GUI 四大组件数据同步 + 并发安全 + 断连恢复 + 动画性能
> 审计方法: 架构代码静态分析 + 事件流追踪 + 数据流映射

---

## 执行摘要

本报告从架构和代码层面对 spec-autopilot 插件的 Phase 0 到 Phase 7 完整流转进行端到端仿真分析，重点评估四大 GUI 组件（PhaseTimeline、ParallelKanban、VirtualTerminal、TelemetryDashboard）在高并发场景下的数据同步设计质量。

**核心发现**：

1. **事件驱动架构设计合理**：通过 events.jsonl (append-only) + WebSocket 实时推送 + Zustand 集中状态管理的三级架构，实现了从编排层到 GUI 层的事件单向流动，架构清晰。
2. **并发安全基本保障到位**：`next_event_sequence()` 使用 `flock -x` 文件锁保证序号原子递增；Store 使用 `Set` 去重 + `sequence` 排序确保事件幂等有序；VirtualTerminal 使用 `lastRenderedSequence` ref 避免重复渲染。
3. **断连重连机制完整**：WSBridge 实现了指数退避重连策略（1s 起步，上限 10s），连接恢复后服务端自动发送全量 snapshot，GUI 通过 sequence 去重无缝恢复。
4. **发现 5 项需要关注的设计风险**：Store 的 `.slice(-1000)` 截断策略在超长会话中可能丢失历史；GateBlockCard 的 Override 按钮缺少前端侧安全约束；selector 函数在高频事件下的计算开销需监控。

---

## 1. Phase 0-7 全流转分析

### 1.1 全流转事件流 -> GUI 更新映射

```
Phase 0 (环境初始化)
  编排层: Skill(autopilot-phase0) → start-gui-server.sh → autopilot-server.ts 启动
  事件发射: emit-phase-event.sh phase_start 0 {mode}
           emit-phase-event.sh phase_end 0 {mode} '{"status":"ok","duration_ms":N}'
  GUI 响应:
    - PhaseTimeline: Phase 0 节点从 pending(灰色) → running(青色脉冲) → ok(绿色勾号)
    - VirtualTerminal: 输出 "[HH:MM:SS] PHASE_START | Phase 0 (Environment Setup)"
    - TelemetryDashboard: 环形图从 0% 进入 1/N 完成; P0 耗时条开始计时

Phase 1 (需求理解)
  编排层: 主线程执行 → 三路并行调研 (Auto-Scan + 技术调研 + 联网搜索)
  事件发射: phase_start 1 → [调研期间无细粒度事件] → phase_end 1
  GUI 响应:
    - PhaseTimeline: Phase 1 节点变为 running
    - ParallelKanban: 此阶段不产生 task_progress 事件，Kanban 不显示
    - 注意: Phase 1 多轮决策 LOOP 期间无中间事件推送到 GUI

Phase 2 (OpenSpec 创建) — 仅 full 模式
  编排层: Gate 8步检查 → emit-gate-event.sh gate_pass 2 → Task 子 Agent
  事件发射: gate_pass 2 → phase_start 2 → phase_end 2
  GUI 响应:
    - GateBlockCard: gate_pass 不触发弹窗; 若 gate_block 则弹出决策面板
    - PhaseTimeline: Phase 2 节点 pending → running → ok
    - TelemetryDashboard: 门禁统计 passed+1

Phase 3 (快速生成) — 仅 full 模式
  编排层: Gate → Task(run_in_background) → checkpoint
  事件流: gate_pass 3 → phase_start 3 → phase_end 3
  GUI 响应: 同 Phase 2 模式

Phase 4 (测试设计) — 仅 full 模式
  编排层: Gate → 可选并行 Task (unit/api/e2e/ui) → Phase 4 特殊门禁
  事件流: gate_pass 4 → phase_start 4 → phase_end 4
  特殊: Phase 4 warning 被 Hook 强制覆盖为 blocked → 触发 gate_block 事件
  GUI 响应:
    - 若 gate_block: GateBlockCard 弹出，显示门禁分数和错误信息
    - 用户可通过 Retry/Fix/Override 按钮决策
    - poll-gate-decision.sh 写入 decision-request.json 并轮询 decision.json

Phase 5 (代码实施) — 关键阶段，最高并发
  编排层: Gate + 特殊门禁 → 串行/并行/TDD 三路互斥
  事件发射:
    - phase_start 5
    - emit-task-progress.sh 对每个 task: running → passed/failed/retrying
    - 并行模式: 多个 task 同时处于 running 状态
    - TDD 模式: tdd_step 字段在 red/green/refactor 间切换
    - phase_end 5
  GUI 响应:
    - ParallelKanban: 核心展示阶段
      · 水平卡片流显示所有 task
      · running 卡片带脉冲动画和紫色发光效果
      · TDD 模式: red(红色左边框) → green(绿色) → refactor(紫色)
      · 并行模式: 多张卡片同时显示 running 状态，自动检测并标记"并行"徽章
      · 进度条实时反映 passed/total 比例
    - VirtualTerminal: 每个 task_progress 事件输出一行带 ANSI 着色的日志
    - TelemetryDashboard: 重试计数器递增; P5 耗时条实时增长

Phase 6 (测试报告) — 三路并行
  编排层: 路径 A(测试执行) + 路径 B(代码审查) + 路径 C(质量扫描) 同时派发
  事件流: gate_pass 6 → phase_start 6 → phase_end 6
  GUI 响应:
    - 仅 Phase 6 主事件显示，路径 B/C 结果在 Phase 7 汇合

Phase 7 (归档清理)
  编排层: Skill(autopilot-phase7) → 汇总 + 三路收集 + 知识提取 + 用户确认归档
  事件流: phase_start 7 → phase_end 7
  GUI 响应:
    - PhaseTimeline: 全部节点变为绿色(正常流转)
    - TelemetryDashboard: 环形图到达 100%; 门禁统计最终定格
    - 锁文件删除后不再有新事件
```

### 1.2 模式差异对 GUI 的影响

| 模式 | 可见 Phase | total_phases | PhaseTimeline 节点数 |
|------|-----------|-------------|---------------------|
| full | 0,1,2,3,4,5,6,7 | 8 | 8 |
| lite | 0,1,5,6,7 | 5 | 5 |
| minimal | 0,1,5,7 | 4 | 4 |

Store 中 `selectActivePhaseIndices()` 通过 `MODE_PHASES` 映射表实现模式感知，`selectPhaseDurations()` 仅返回活跃 Phase 的耗时数据。PhaseTimeline 和 TelemetryDashboard 据此自动裁剪显示内容，设计正确。

### 1.3 事件完整性覆盖分析

| 事件类型 | 发射时机 | 覆盖的 Phase | GUI 消费组件 |
|---------|---------|-------------|-------------|
| `phase_start` | 每个 Phase 开始 | 0-7 | PhaseTimeline, VirtualTerminal, TelemetryDashboard |
| `phase_end` | 每个 Phase 结束 | 0-7 | PhaseTimeline, VirtualTerminal, TelemetryDashboard |
| `gate_pass` | 门禁通过 | 2-7 | TelemetryDashboard(统计), VirtualTerminal(日志) |
| `gate_block` | 门禁阻断 | 2-7 | GateBlockCard(弹窗), VirtualTerminal(日志) |
| `task_progress` | Phase 5 每 task | 5 | ParallelKanban(卡片), VirtualTerminal(日志) |
| `gate_decision_pending` | 决策等待开始 | 2-7 | GateStats(pending 计数) |
| `gate_decision_received` | 决策已收到 | 2-7 | VirtualTerminal(日志) |
| `decision_ack` | WS-only 决策确认 | 2-7 | GateBlockCard(隐藏) |

**覆盖度评估**: Phase 1 的多轮决策 LOOP 和调研进度缺乏细粒度事件，GUI 在 Phase 1 期间仅能显示"运行中"而无法展示内部进度。Phase 2/3 作为后台 Agent 执行，同样缺乏中间事件。这是当前事件覆盖的主要盲区。

---

## 2. 四大组件数据同步分析

### 2.1 PhaseTimeline

**数据源**: `useStore()` 中的 `events`、`currentPhase`、`mode`

**派生计算**:
- `selectPhaseDurations(events)`: 遍历事件计算每个 Phase 的状态和耗时
- `selectTotalElapsedMs(events)`: 累计会话总耗时
- `selectGateStats(events)`: 统计门禁通过/阻断数

**实时更新机制**:
- 当存在 `running` 状态的 Phase 时，启动 1 秒间隔定时器强制重渲染 (G9 修复)
- 通过 `Date.now() - startEvent.timestamp` 实时计算运行中 Phase 的耗时

**状态映射**:
```
pending  → 灰色 hex 节点 + 数字
running  → 青色 hex 节点 + 脉冲动画 + animate-pulse-glow-cyan
ok       → 绿色 hex 节点 + 勾号
warning  → 绿色 hex 节点 + 勾号 (与 ok 相同视觉)
blocked  → 红色 hex 节点 + 叉号
failed   → 红色 hex 节点 + 叉号
```

**优势**:
- 使用 Tailwind CSS 类动态组合，状态切换零延迟
- 模式感知裁剪，lite/minimal 模式只展示相关 Phase
- 底部统计面板与时间轴节点数据一致

**风险点**:
- `selectPhaseDurations` 在每次渲染时全量遍历 events 数组，事件量大时有性能开销
- warning 和 ok 的视觉表现完全相同，用户无法区分

### 2.2 ParallelKanban

**数据源**: `useStore()` 中的 `taskProgress` (Map) 和 `currentPhase`

**显隐控制**: 仅当 `currentPhase === 5` 或 `taskProgress.size > 0` 时渲染，其余阶段返回 null

**实时更新机制**:
- 每个 `task_progress` 事件到达时，Store 的 `addEvents()` 更新 `taskProgress` Map
- 使用 `task_name` 作为 Map key，同一 task 的后续事件自动覆盖前值
- 卡片按 `task_index` 排序，保证顺序稳定

**并行模式检测** (G6):
```typescript
const isParallel = runningTasks.length > 1 || tasks.some((t) => t.task_total > 1);
```
通过运行时推断而非配置读取来判定并行模式，设计灵活。

**TDD 模式展示**:
```
red    → 红色左边框 + "失败测试" 标签 + 红色脉冲覆盖层
green  → 绿色左边框 + "通过" 标签
refactor → 紫色左边框 + "重构" 标签 + 紫色脉冲覆盖层
```

**优势**:
- 水平可滚动卡片流设计适合大量并行任务展示
- TDD 步骤状态 与 任务完成状态 双维度展示
- 使用 CSS 动画而非 JS 动画，渲染层分离

**风险点**:
- 进度条宽度计算使用硬编码百分比 (`w-[65%]` for TDD running)，不够精确
- 当并行任务数量超过视口宽度时，用户需要手动滚动，缺乏自动聚焦到最新活动任务的机制
- `taskProgress` 使用 `Map` 类型，Zustand 的浅比较可能在某些 React 严格模式下有边界问题（目前通过创建新 Map 实例规避）

### 2.3 VirtualTerminal

**数据源**: `useStore()` 中的 `events`

**增量渲染机制**:
```typescript
const lastRenderedSequence = useRef<number>(-1);
// 每次 events 变化时，仅渲染 sequence > lastRenderedSequence 的新事件
const newEvents = events.filter((e) => e.sequence > lastRenderedSequence.current);
```

这是整个 GUI 中最关键的性能优化设计：
1. 使用 `useRef` 存储最后渲染的序号，组件重渲染不会重置
2. 过滤逻辑确保同一事件绝不会被写入 xterm.js 两次
3. 写入完成后更新 `lastRenderedSequence`

**ANSI 着色策略**:
- 每种事件类型映射固定 ANSI 颜色代码
- `gate_block` 和 `error` 使用亮红色 `\x1b[1;31m`
- `task_progress` 使用青色 `\x1b[36m`
- 每行格式: `[时间] 事件类型 | Phase N (标签) 详情`

**payload 展示** (G7): 根据事件类型附加关键字段
- `gate_block`: score + error_message (截断 80 字符)
- `phase_end`: status + duration_ms
- `task_progress`: task_name + status + tdd_step

**resize 处理**: 使用 `requestAnimationFrame` 包裹 `fitAddon.fit()`，避免频繁 resize 导致的布局抖动

**优势**:
- xterm.js 提供真正的终端渲染能力，支持 ANSI 转义序列
- `lastRenderedSequence` 增量渲染设计确保高频事件下不会重复写入
- 自定义暗色主题与整体 UI 风格一致

**风险点**:
- xterm.js 的 `write()` 在高频调用下可能产生微小延迟（内部有 write buffer）
- 长时间运行后 xterm.js 的行缓冲区可能占用较多内存（默认 scrollback 1000 行）
- 没有事件过滤器的实际实现（UI 中显示 "[全部]" 但无交互）

### 2.4 TelemetryDashboard

**数据源**: `useStore()` 中的 `events`（通过 selector 派生）

**展示模块**:

**Card 1 — 会话指标** (SVG 环形图):
```typescript
const circumference = 2 * Math.PI * 58;
const completionRatio = completedPhases / totalPhaseCount;
const strokeDashoffset = circumference * (1 - completionRatio);
```
使用 SVG `stroke-dasharray` + `stroke-dashoffset` 绘制进度环，通过 `transition-all duration-1000` 实现平滑动画。中心叠加总耗时文本。

**Card 2 — 阶段耗时** (水平条形图):
```typescript
const barWidth = p.durationMs > 0 ? Math.max((p.durationMs / maxDuration) * 100, 2) : 0;
```
每个 Phase 一行，条形宽度按比例计算（最长的 Phase 为 100%），运行中的 Phase 带青色发光阴影效果。

**Card 3 — 门禁统计** (双色圆环):
- 通过 CSS `border-4 border-emerald border-l-rose` 实现简易双色效果
- 展示通过率百分比 + 通过/阻断/待定三个计数

**实时更新**: 同 PhaseTimeline 使用 1 秒定时器强制重渲染运行中阶段 (G9)

**优势**:
- 纯 CSS + SVG 实现所有图表，无第三方图表库依赖
- 数据与 PhaseTimeline 复用同一套 selector，保证一致性
- 紧凑的卡片式布局，信息密度高

**风险点**:
- `selectPhaseDurations` 等 selector 在 PhaseTimeline 和 TelemetryDashboard 中各调用一次，相同计算重复执行
- Card 3 的双色圆环使用 border hack 而非 SVG，仅能展示固定比例，不能精确反映通过率
- `totalRetries` 计算遍历全部事件，随事件增长线性增加

---

## 3. 并发安全性评估

### 3.1 事件序号原子性

**机制**: `_common.sh` 中的 `next_event_sequence()` 函数

```bash
(
  flock -x 200
  local current=$(cat "$seq_file" 2>/dev/null | tr -d '[:space:]')
  next=$((current + 1))
  echo "$next" > "$seq_file"
  echo "$next"
) 200>"$lock_file"
```

**分析**:
- 使用文件描述符 200 + `flock -x`（排他锁）保证同一时刻只有一个进程能自增序号
- 子 shell `(...)` 确保锁在退出时自动释放
- 序号文件和锁文件分离，避免写入竞争

**评级**: **安全**。在 Phase 5 并行模式下多个子 Agent 可能同时发射 task_progress 事件，flock 确保序号严格递增不冲突。

### 3.2 Store 去重与截断

```typescript
addEvents: (newEvents) => set((state) => {
  const seen = new Set(state.events.map((e) => e.sequence));
  const unique = newEvents.filter((e) => !seen.has(e.sequence));
  const merged = [...state.events, ...unique]
    .sort((a, b) => a.sequence - b.sequence)
    .slice(-1000);
  // ...
})
```

**分析**:
- `Set` 去重: 基于 `sequence` 字段，即使 WebSocket 重连后发送 snapshot 重叠也不会产生重复事件
- `.sort()` 排序: 保证乱序到达的事件最终有序
- `.slice(-1000)` 截断: 保留最近 1000 条事件，防止内存无限增长

**风险**:
- 截断后丢失的早期事件会导致 `selectPhaseDurations` 中找不到对应的 `phase_start`/`phase_end` 配对，可能出现已完成 Phase 被误判为 pending
- 截断发生在 `.sort()` 之后，是保留最新的 1000 条，设计合理
- 但对于超过 500 个 task 的超大型项目（每个 task 约 2-4 个事件），1000 的上限可能不足

### 3.3 taskProgress Map 并发更新

```typescript
const newTaskProgress = new Map(state.taskProgress);
for (const event of newEvents) {
  if (event.type === "task_progress" && event.phase === 5 && isTaskProgressPayload(event.payload)) {
    newTaskProgress.set(p.task_name, { ... });
  }
}
```

**分析**:
- 使用 `new Map(state.taskProgress)` 创建浅拷贝，符合 Zustand 的不可变更新要求
- `task_name` 作为唯一 key，同一 task 的多次状态更新自动覆盖
- 在 `addEvents` 的 `set()` 回调中同步执行，不存在竞态条件

**评级**: **安全**。Zustand 的 `set()` 在 React 批量更新机制下保证原子性。

### 3.4 GateBlockCard 决策发送

```typescript
// WSBridge.sendDecision → WebSocket 发送
// autopilot-server.ts → handleDecision → 写入 decision.json
// poll-gate-decision.sh → 读取 decision.json → 删除 → 返回决策
```

**分析**:
- decision.json 的写入 (autopilot-server) 和读取 (poll-gate-decision.sh) 存在理论上的竞态窗口
- 但由于 poll 间隔为 1 秒，且 Bun 的 `writeFile` 是原子操作（先写临时文件再重命名），实际竞态风险极低
- `poll-gate-decision.sh` 在读取后立即 `rm -f` 删除，防止重复消费
- 无效 JSON 被删除并继续轮询，对 GUI "mid-write" 场景有容错

**decisionAcked 状态管理** (G2 修复):
```typescript
if (state.decisionAcked) {
  const hasNewBlock = newEvents.some(
    (e) => e.type === "gate_block" && e.sequence > state.lastAckedBlockSequence
  );
  if (hasNewBlock) newDecisionAcked = false;
}
```
通过 `lastAckedBlockSequence` 跟踪已确认的阻断事件序号，新的 gate_block 自动重置确认状态，确保连续多次门禁阻断都能正确弹出 GateBlockCard。

**评级**: **基本安全**，但 Override 操作缺少前端侧对 Phase 4->5 和 Phase 5->6 特殊门禁的约束提示（服务端有约束但 GUI 未展示）。

### 3.5 events.jsonl 并发追加

三个 emit 脚本 (emit-phase-event.sh, emit-gate-event.sh, emit-task-progress.sh) 都使用 `echo "$EVENT_JSON" >> "$EVENTS_FILE"` 追加写入。

**分析**:
- 在 Linux/macOS 上，小于 PIPE_BUF (4096 bytes) 的单次 write 是原子的
- 单个 JSON 事件通常 200-500 bytes，远小于 PIPE_BUF
- 但严格来说，shell 的 `>>` 重定向不保证原子性（取决于内核实现）
- 实际风险极低：并行事件间有几十毫秒的时间差，几乎不可能同时写入

**评级**: **风险可接受**。理论上极端并发可能导致行交错，但实际几乎不会发生。如需绝对保证，可考虑使用 flock 锁保护追加操作。

---

## 4. 断连恢复能力

### 4.1 WebSocket 重连策略

```typescript
// WSBridge.scheduleReconnect()
private scheduleReconnect() {
  if (this.reconnectTimer) return;
  this.reconnectTimer = setTimeout(() => {
    this.reconnectTimer = null;
    this.reconnectDelay = Math.min(this.reconnectDelay * 1.5, this.maxReconnectDelay);
    this.connect();
  }, this.reconnectDelay);
}
```

| 属性 | 值 | 说明 |
|------|-----|------|
| 初始延迟 | 1000ms | 首次断连后等待 1 秒 |
| 递增因子 | 1.5x | 每次失败延迟增加 50% |
| 最大延迟 | 10000ms | 上限 10 秒 |
| 重置时机 | onopen 成功时 | 重连成功后延迟重置为 1 秒 |

**评估**: 策略合理。1.5x 的递增因子比常见的 2x 更温和，可在 5 次失败内到达最大延迟（1s → 1.5s → 2.25s → 3.4s → 5.1s → 7.6s → 10s），既避免了频繁连接又保证了较快恢复。

### 4.2 Snapshot 恢复机制

```typescript
// autopilot-server.ts WebSocket onopen
open(ws) {
  wsClients.add(ws);
  getEventLines().then((lines) => {
    ws.send(JSON.stringify({
      type: "snapshot",
      data: lines.map((l) => JSON.parse(l)),
    }));
  });
}
```

连接建立后，服务端立即读取 events.jsonl 全部内容并作为 snapshot 发送。客户端 WSBridge 收到 `type: "snapshot"` 后调用 `this.emit(msg.data)`，Store 的 `addEvents()` 通过 sequence 去重合并。

**关键路径**: 断连 -> 自动重连 -> snapshot 全量同步 -> sequence 去重 -> GUI 无缝恢复

**评估**: 设计健壮。唯一的潜在问题是当 events.jsonl 文件非常大时（数千条事件），snapshot 的 JSON 解析和网络传输可能有延迟。但 `.slice(-1000)` 截断在客户端侧提供了保护。

### 4.3 连接状态 UI 反馈

```typescript
// App.tsx 中每 1 秒检查连接状态
const checkConnection = setInterval(() => {
  setConnected(wsBridge.connected);
}, 1000);
```

Header 右上角展示连接状态指示器:
- 绿色脉冲点 + "运行中" — WebSocket 已连接
- 红色静止点 + "断开" — WebSocket 已断开

**评估**: 1 秒轮询连接状态略显粗糙，但对用户体验影响很小。更优的方式是在 WSBridge 内部通过事件回调通知状态变化，避免定时器轮询。

### 4.4 服务端容错

autopilot-server.ts 的事件文件监听:
```typescript
try {
  watch(logsDir, { recursive: false }, (eventType, filename) => {
    if (filename === "events.jsonl") broadcastNewEvents();
  });
} catch {
  // Fallback: poll every 500ms
  setInterval(broadcastNewEvents, 500);
}
```

双重策略: 优先使用 `fs.watch`（高效），不可用时降级为 500ms 轮询。`broadcastNewEvents()` 内部维护 `lastLineCount` 偏移量，仅读取新增行。

**REST 降级**: HTTP 端点 `/api/events?offset=N` 提供非 WebSocket 消费方式，offset 参数支持增量拉取。

---

## 5. 动画性能评估

### 5.1 动画类型清单

| 组件 | 动画 | 实现方式 | 触发频率 |
|------|------|---------|---------|
| PhaseTimeline | 运行中节点脉冲 | CSS `animate-pulse-glow-cyan` | 持续循环 |
| ParallelKanban | 运行中卡片脉冲 | CSS `animate-pulse-soft` | 持续循环 |
| ParallelKanban | 运行中状态文本闪烁 | CSS `animate-pulse` | 持续循环 |
| ParallelKanban | 进度条发光 | CSS `shadow-[0_0_8px...]` | 状态变化 |
| VirtualTerminal | 红色脉冲点 | CSS `animate-pulse` | 持续循环 |
| TelemetryDashboard | 环形图过渡 | CSS `transition-all duration-1000` | Phase 完成时 |
| TelemetryDashboard | 运行中耗时条发光 | CSS `shadow-[0_0_8px...]` | 状态变化 |
| TelemetryDashboard | 耗时条宽度过渡 | CSS `transition-all duration-500` | 1 秒间隔 |
| App Header | 连接状态脉冲 | CSS `animate-ping` | 持续循环 |
| App | 扫描线覆盖层 | CSS `animate-scanline` | 持续循环 |
| GateBlockCard | 阻断弹窗脉冲 | CSS `animate-pulse-soft` | 持续循环 |

### 5.2 性能分析

**正面因素**:

1. **全部使用 CSS 动画**: 没有使用 Framer Motion 或任何 JS 动画库。所有动画通过 CSS `animation` / `transition` 实现，由 GPU 加速的合成层处理，不阻塞主线程。

2. **无 Framer Motion 依赖**: 项目的 GUI 部分未引入 Framer Motion。这意味着不存在 Framer Motion 在高速并发下的性能问题（如频繁的 layout 重计算、AnimatePresence 的 DOM 操作开销等）。

3. **CSS 动画属性选择合理**: 使用的 `opacity`、`transform`、`box-shadow` 都是可以被浏览器优化为 GPU 合成的属性，不触发布局回流（reflow）。

4. **VirtualTerminal 增量渲染**: xterm.js 使用 canvas 渲染，新事件仅追加写入，不触发已有内容的重绘。

**潜在风险**:

1. **1 秒定时器的重渲染开销**: PhaseTimeline 和 TelemetryDashboard 在有运行中 Phase 时每秒强制重渲染。由于 `selectPhaseDurations` 在每次渲染时全量遍历事件数组并创建新对象，这可能在 events 达到数百条时造成可观察的开销。建议使用 `useMemo` 缓存 selector 结果。

2. **ParallelKanban 的持续脉冲动画**: 当 Phase 5 有多个并行 running 任务时（最多 8 个），每个卡片都有脉冲覆盖层 + 状态闪烁。虽然是 CSS 动画，但多个同时运行的 `animate-pulse-soft` 仍然占用 GPU 合成资源。在低端设备上可能导致帧率下降。

3. **扫描线覆盖层**: `scanline-overlay` 全屏覆盖，配合 `animate-scanline` 持续运动。这个效果虽然视觉上增色，但在全屏 CSS 动画层叠下可能增加合成开销。建议在性能敏感场景允许用户关闭。

4. **Store 去重 + 排序的计算成本**: `addEvents` 中每次都创建 `new Set()`、展开数组、排序、截断。在高频事件到达时（如 Phase 5 并行 8 任务快速完成），短时间内多次调用 `addEvents` 可能产生排队效应。

---

## 6. 评分

| 维度 | 得分 | 满分 | 说明 |
|------|------|------|------|
| Phase 全流转完备度 | 17 | 20 | Phase 0-7 事件链路完整，但 Phase 1/2/3 缺乏中间进度事件，GUI 可见性不足 |
| 四大组件数据同步设计 | 18 | 20 | Zustand 单向数据流 + selector 派生设计清晰；selector 缺少 memoization；warning/ok 视觉未区分 |
| 并发安全性 | 17 | 20 | flock 序号原子性 + Set 去重 + Map 覆盖更新设计合理；events.jsonl 追加写入理论上非原子；Override 按钮缺少前端约束 |
| 断连恢复能力 | 19 | 20 | 指数退避重连 + snapshot 全量恢复 + sequence 去重三层保障完善；连接状态检测依赖轮询而非事件回调 |
| 动画性能设计 | 18 | 20 | 全 CSS 动画 + GPU 合成友好；1秒定时器重渲染缺少 memoization；全屏扫描线开销需关注 |
| **总分** | **89** | **100** | |

---

## 7. 改进建议

### P0 - 高优先级

1. **Selector Memoization**: `selectPhaseDurations`、`selectTotalElapsedMs`、`selectGateStats` 应使用 `useMemo` 或 Zustand 的 `useStore(selector)` 模式配合 shallow equality 检查，避免每 1 秒定时器触发全量重计算。

2. **events.jsonl 追加写入原子化**: 为三个 emit 脚本的文件追加操作添加 flock 保护，确保 Phase 5 高并发场景下行不交错：
   ```bash
   (flock -x 201; echo "$EVENT_JSON" >> "$EVENTS_FILE") 201>"$EVENTS_FILE.lock"
   ```

3. **GateBlockCard Override 安全约束**: 在前端对 Phase 4->5 和 Phase 5->6 的特殊门禁禁用 Override 按钮，或至少展示警告提示，与后端 `poll-gate-decision.sh` 的安全约束保持一致。

### P1 - 中优先级

4. **Phase 1 细粒度事件**: 为 Phase 1 的调研进度（三路并行开始/完成）和决策 LOOP 轮次增加事件发射，让 GUI 能展示 Phase 1 的内部进度而非仅 "运行中"。

5. **事件截断策略优化**: 将 `.slice(-1000)` 改为保留所有 `phase_start`/`phase_end`/`gate_*` 事件 + 最近 N 条 `task_progress` 事件的混合策略，避免超长会话丢失 Phase 状态事件。

6. **warning 与 ok 视觉区分**: PhaseTimeline 中 warning 状态的 Phase 节点应使用黄色/琥珀色区分，而非与 ok 相同的绿色。

7. **ParallelKanban 自动聚焦**: 当有新的 running 任务出现时，自动滚动到该卡片位置，提升多任务场景的可用性。

### P2 - 低优先级

8. **连接状态事件化**: 将 App.tsx 中 1 秒轮询 `wsBridge.connected` 改为在 WSBridge 内部使用回调通知连接状态变化，减少不必要的 setInterval。

9. **VirtualTerminal 事件过滤器**: 实现 UI 中已预留的 "[全部]" 过滤器下拉菜单，允许用户按事件类型过滤终端输出（如仅看 gate_block 或 task_progress）。

10. **扫描线可关闭**: 提供 UI 开关允许用户关闭全屏扫描线动画效果，在低端设备上释放 GPU 资源。

11. **Store 批量更新优化**: 当 snapshot 到达时一次性注入大量事件，考虑对 `addEvents` 进行节流（throttle），将高频调用合并为低频批量更新，减少 React 渲染次数。

---

## 附录 A: 数据流全景图

```
                    编排层                              传输层                         GUI 层
 ┌─────────────────────────┐     ┌──────────────────────────┐     ┌───────────────────────────┐
 │ SKILL.md 统一调度模板      │     │ autopilot-server.ts       │     │ Zustand Store              │
 │                          │     │                           │     │                            │
 │ Step 0: emit-phase-event │────>│ fs.watch(events.jsonl)    │     │  addEvents(newEvents)      │
 │ Step 1: emit-gate-event  │────>│   -> broadcastNewEvents() │────>│    -> Set 去重              │
 │ Phase 5: emit-task-prog  │────>│   -> ws.send(event)       │     │    -> sort by sequence     │
 │                          │     │                           │     │    -> slice(-1000)         │
 │ poll-gate-decision.sh    │<────│ handleDecision()          │<────│    -> update taskProgress  │
 │   <- decision.json       │     │   <- ws "decision" msg    │     │                            │
 └─────────────────────────┘     └──────────────────────────┘     └────────────┬───────────────┘
                                                                                │
                                                              ┌─────────────────┼─────────────────┐
                                                              │                 │                  │
                                                    ┌─────────┴────┐  ┌────────┴──────┐  ┌───────┴──────────┐
                                                    │PhaseTimeline │  │ParallelKanban │  │VirtualTerminal   │
                                                    │ events       │  │ taskProgress  │  │ events           │
                                                    │ currentPhase │  │ currentPhase  │  │ lastRenderedSeq  │
                                                    │ mode         │  │               │  │ (incremental)    │
                                                    └──────────────┘  └───────────────┘  └──────────────────┘
                                                              │
                                                    ┌─────────┴──────────┐  ┌────────────────────┐
                                                    │TelemetryDashboard  │  │GateBlockCard       │
                                                    │ selectPhaseDurations│  │ gate_block events  │
                                                    │ selectGateStats    │  │ decisionAcked      │
                                                    │ selectTotalElapsed │  │ onDecision -> WS   │
                                                    └────────────────────┘  └────────────────────┘
```

## 附录 B: mock-event-emitter.js 测试覆盖评估

当前 mock 模拟器覆盖了以下场景:
- Phase 0 完整生命周期 (start + end)
- Phase 5 三个并发任务 (running + TDD red/green/refactor + passed + failed)
- Gate Block 事件触发

**未覆盖的场景**:
- Phase 1-4, 6-7 的完整生命周期
- gate_pass 事件
- lite/minimal 模式的不同 total_phases
- 超时和重试场景
- decision_ack 事件
- 大规模并发 (>8 tasks) 压力测试

建议扩展 mock 模拟器以覆盖完整 Phase 0-7 流转和边界场景。
