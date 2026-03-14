# 维度四：遥测、并发与底层基建审计报告

> 审计日期: 2026-03-14
> 审计范围: `plugins/spec-autopilot/`
> 审计官: 首席架构审计官 (AI)

---

## 1. 原子性操作 — `next_event_sequence()` flock 排他锁

### 源码证据

**文件**: `scripts/_common.sh:290-306`

```bash
next_event_sequence() {
  local project_root="$1"
  local seq_file="$project_root/logs/.event_sequence"
  local lock_file="$project_root/logs/.event_sequence.lock"
  mkdir -p "$(dirname "$seq_file")" 2>/dev/null || true

  local next
  (
    flock -x 200
    local current=0
    [ -f "$seq_file" ] && current=$(cat "$seq_file" 2>/dev/null | tr -d '[:space:]') || true
    [ -z "$current" ] && current=0
    next=$((current + 1))
    echo "$next" > "$seq_file"
    echo "$next"
  ) 200>"$lock_file"
}
```

### 审计发现

**[Info] flock 子 shell 模式正确**
- 使用 `flock -x 200` 在子 shell `(...)` 内获取排他锁，fd 200 重定向到 `.event_sequence.lock` 文件。
- 子 shell 退出时 fd 自动关闭、锁自动释放，无需手动 unlock。
- 读取-递增-写入三步操作完全在临界区内，保证了原子性。

**[Minor] M1 — flock 无超时参数**
- `flock -x 200` 是无限等待模式。如果某个持锁进程意外挂起（如 `cat` 阻塞在损坏的文件系统上），其他 8 个 Phase 5 Agent 将全部死锁等待。
- **建议**: 改为 `flock -x -w 5 200` 加 5 秒超时，失败时打日志并回退到时间戳 fallback。

**[Minor] M2 — 锁文件未做生命周期管理**
- `.event_sequence.lock` 文件在会话结束后残留在 `logs/` 目录中，不会自动清理。
- 功能上无害（flock 基于 fd 而非文件存在性），但作为工程卫生问题值得注意。

**[Info] Phase 5 高并发评估**
- Phase 5 最多 8 个并行 Agent，每个 Agent 在 task 进度变更时调用 `emit-task-progress.sh` -> `next_event_sequence()`。
- flock 排他锁保证了序列号不会重复。但临界区内有 `cat` + `echo >` 两次磁盘 I/O，在 8 Agent 并发下可能形成锁争用瓶颈。
- **实际影响**: 每次锁持有时间约 1-2ms（SSD），8 Agent 的理论最大等待约 14ms，可接受。

### 本节评分: 4.5 / 5

---

## 2. 服务端 I/O — `autopilot-server.ts`

### 2.1 `getEventLines()` 增量读取

**文件**: `scripts/autopilot-server.ts:70-77`

```typescript
async function getEventLines(): Promise<string[]> {
  try {
    const content = await readFile(EVENTS_FILE, "utf-8");
    return content.split("\n").filter(Boolean);
  } catch {
    return [];
  }
}
```

**文件**: `scripts/autopilot-server.ts:79-98`

```typescript
async function broadcastNewEvents() {
  if (wsClients.size === 0) return;

  const lines = await getEventLines();
  if (lines.length <= lastLineCount) return;

  const newLines = lines.slice(lastLineCount);
  lastLineCount = lines.length;

  for (const line of newLines) {
    const message = JSON.stringify({ type: "event", data: JSON.parse(line) });
    // ...
  }
}
```

**[Major] J1 — getEventLines() 每次全量读取文件**
- `getEventLines()` 每次被调用时读取 `events.jsonl` 的**完整内容**，然后通过 `lines.slice(lastLineCount)` 截取增量部分。
- 增量语义通过 `lastLineCount` 偏移量实现，但底层 I/O 是全量 `readFile()`。
- 在长时间运行的 autopilot 会话中（数百个事件），每次文件变化都会读取并解析全部内容。
- **建议**: 使用字节偏移量（`fs.read()` + `position`），或者使用 `fs.createReadStream({ start: lastByteOffset })` 实现真正的增量读取。

**[Major] J2 — broadcastNewEvents 中 JSON.parse 无 try-catch**
- 第 89 行 `JSON.parse(line)` 位于 `for...of` 循环内，**未被 try-catch 包裹**。
- 如果 `events.jsonl` 中某一行格式损坏（如并发写入导致的半行数据），整个 `broadcastNewEvents()` 将抛出异常，导致**后续所有新行都不会被广播**。
- 更严重的是，`lastLineCount` 在第 86 行已经被更新，因此损坏行之后的事件将被**永久跳过**。
- **这是一个 Critical 级别的问题。**

```typescript
// 问题代码 (第86-89行):
lastLineCount = lines.length;  // <- 已更新偏移量

for (const line of newLines) {
  const message = JSON.stringify({ type: "event", data: JSON.parse(line) }); // <- 无保护
```

**[Info] HTTP REST fallback 端点同样缺少保护**

**文件**: `scripts/autopilot-server.ts:268-283`

```typescript
if (url.pathname === "/api/events") {
  const lines = await getEventLines();
  const offset = parseInt(url.searchParams.get("offset") || "0");
  return new Response(
    JSON.stringify({
      events: lines.slice(offset).map((l) => JSON.parse(l)),  // <- 无 try-catch
```

第 273 行的 `JSON.parse(l)` 同样无保护，但此处是 HTTP 请求级别，影响范围仅限单次请求。

### 2.2 WebSocket 连接管理

**文件**: `scripts/autopilot-server.ts:199-228`

**[Info] 连接管理实现完善**
- 使用 `Set<any>` 管理 WebSocket 客户端，`open` 时 `add`，`close` 时 `delete`。
- `send()` 失败时在 catch 中从 Set 移除死连接。
- 新连接时发送完整 snapshot，保证前端数据完整性。

**[Minor] M3 — snapshot 发送中的 JSON.parse 同样无保护**

**文件**: `scripts/autopilot-server.ts:203-209`

```typescript
open(ws) {
  wsClients.add(ws);
  getEventLines().then((lines) => {
    ws.send(
      JSON.stringify({
        type: "snapshot",
        data: lines.map((l) => JSON.parse(l)),  // <- 无保护
      })
    );
  });
},
```

**[Minor] M4 — wsClients 类型为 Set\<any\>**
- 第 64 行 `const wsClients = new Set<any>()` 使用了 `any` 类型，丧失了 TypeScript 类型安全。
- 应使用 Bun 的 `ServerWebSocket` 类型。

### 2.3 客户端 WebSocket 桥接

**文件**: `gui/src/lib/ws-bridge.ts`

**[Info] 客户端实现良好**
- `onmessage` 中的 `JSON.parse(e.data)` 被 try-catch 保护（第 46-59 行），malformed 消息被静默忽略。
- 指数退避重连策略：初始 1s，乘数 1.5x，上限 10s。
- 连接成功时重置退避时间。
- 支持 `disconnect()` 主动断开并清除重连定时器。

### 本节评分: 3.0 / 5

---

## 3. 产物纯净度 — `build-dist.sh`

### 源码证据

**文件**: `scripts/build-dist.sh` (完整 65 行)

### 审计发现

**[Info] 白名单复制机制正确**
- 第 15-18 行仅复制 4 个运行时目录：`.claude-plugin`, `hooks`, `skills`, `gui-dist`。
- 源码目录 `gui/` (含 node_modules)、`docs/`、`tests/` 均不在白名单中。

**[Info] EXCLUDE_SCRIPTS 白名单有效**
- 第 22 行 `EXCLUDE_SCRIPTS="bump-version.sh|build-dist.sh"` 仅排除 2 个开发脚本。
- 第 23-29 行通过 `grep -qE` 逐文件过滤。

**[Info] CLAUDE.md DEV-ONLY 裁剪验证**
- 第 32-33 行使用 `sed` 删除 `DEV-ONLY-BEGIN` 到 `DEV-ONLY-END` 之间的内容。
- 第 46-51 行通过关键词 "测试纪律"、"构建纪律"、"发版纪律" 验证裁剪结果。
- **实测确认**: dist 中的 CLAUDE.md 确实不含 DEV-ONLY 段落（共 3 段被正确移除）。

**[Info] 隔离验证闭环**
- 第 54-58 行显式检查 `gui`, `docs`, `tests`, `CHANGELOG.md`, `README.md` 均不存在于 dist。
- 违反时 `exit 1` 阻断构建。

**[Minor] M5 — mock-event-emitter.js 泄入 dist**
- `scripts/mock-event-emitter.js` 是一个测试/调试工具（"模拟事件发射器，用于测试 GUI 组件"），但它未被列入 `EXCLUDE_SCRIPTS`。
- **实测确认**: dist 目录中确实存在 `mock-event-emitter.js`。
- 这不影响功能安全性，但违反了"测试文件永不进入 dist"的原则精神。
- **建议**: 将 `mock-event-emitter.js` 加入 EXCLUDE_SCRIPTS。

**[Minor] M6 — autopilot-server.ts 进入 dist 但无 bun 运行时保证**
- `autopilot-server.ts` 是 TypeScript 文件，需要 `bun` 运行时。`start-gui-server.sh` 中有 `bun` 存在性检查，但 dist 产物本身不含该检查说明。
- 对于不安装 bun 的用户，dist 中的 server 脚本无法运行，但 `start-gui-server.sh` 会优雅降级。

### 本节评分: 4.5 / 5

---

## 4. 事件系统 — 完整写入链路审计

### 4.1 事件写入链路

三个事件发射器共享相同的写入模式：

**emit-phase-event.sh** (第 106-110 行):
```bash
EVENTS_DIR="$PROJECT_ROOT/logs"
EVENTS_FILE="$EVENTS_DIR/events.jsonl"
mkdir -p "$EVENTS_DIR" 2>/dev/null || true
echo "$EVENT_JSON" >> "$EVENTS_FILE" 2>/dev/null || true
```

**emit-gate-event.sh** (第 106-110 行): 同上
**emit-task-progress.sh** (第 107-111 行): 同上

**[Major] J3 — 事件写入无原子性保证**
- `echo "$EVENT_JSON" >> "$EVENTS_FILE"` 使用 shell `>>` 追加，在 Linux/macOS 上当 `EVENT_JSON` 长度 < PIPE_BUF (4096 bytes) 时，单次 `write()` 系统调用通常是原子的。
- 但 **没有显式的文件锁保护**。当 Phase 5 的 8 个并行 Agent 同时发射事件时：
  - 每个 Agent 独立调用 `emit-*-event.sh`
  - 这些进程可能在极短时间窗内同时追加
  - 虽然序列号通过 flock 保证了唯一性，但 **文件写入本身不在锁的保护范围内**
- **实际风险**: 对于典型的事件 JSON（约 200-500 bytes），远小于 PIPE_BUF，在实践中极少出现损坏。但这依赖于操作系统行为而非显式保证。
- **建议**: 将 `echo >> events.jsonl` 纳入 `flock` 保护范围，或使用独立的写入锁。

**[Info] 写入错误被静默忽略**
- `2>/dev/null || true` 意味着写入失败不会阻断 hook 执行流。
- 这是设计决策（遥测不应阻断核心流程），但意味着磁盘满等场景下事件会丢失且无告警。

### 4.2 事件格式验证

**[Info] 事件格式完整且规范**

三个发射器均通过 python3 构造事件 JSON，包含全部必需字段：

| 字段 | 来源 | 验证 |
|------|------|------|
| `type` | CLI 参数，case 语句验证 | emit-phase-event.sh:34, emit-gate-event.sh:34 |
| `phase` | CLI 参数，`int()` 转换 | python3 构造器 |
| `mode` | CLI 参数 | 无校验（信任调用者） |
| `timestamp` | ISO-8601 via python3 | `datetime.now(timezone.utc).isoformat()` |
| `change_name` | 环境变量 > 锁文件 > "unknown" | 三级 fallback |
| `session_id` | 环境变量 > 锁文件 > 时间戳 | 三级 fallback |
| `phase_label` | `get_phase_label()` 静态映射 | case 语句 |
| `total_phases` | `get_total_phases()` 模式映射 | case 语句 |
| `sequence` | `next_event_sequence()` 原子递增 | flock 保证 |
| `payload` | CLI 参数，JSON.parse 解析 | try-except 保护 |

**[Info] ISO-8601 时间戳双路实现**
- 主路径: `python3 -c "from datetime import datetime,timezone; print(datetime.now(timezone.utc).isoformat())"`
- 降级路径: `date -u +"%Y-%m-%dT%H:%M:%SZ"`
- 主路径输出带毫秒精度（如 `2026-03-14T10:30:45.123456+00:00`），降级路径仅秒精度。精度不一致但功能上可接受。

### 4.3 序列号原子性

**[Info] 序列号链路完整**
1. `emit-*-event.sh` 调用 `next_event_sequence "$PROJECT_ROOT"`
2. `next_event_sequence()` 通过 flock 排他锁保证原子递增
3. 序列号写入 `logs/.event_sequence` 文件持久化
4. 序列号嵌入事件 JSON 的 `sequence` 字段
5. 客户端 `store/index.ts:181` 使用 `new Set(state.events.map(e => e.sequence))` 去重
6. 客户端 `store/index.ts:183` 使用 `.sort((a,b) => a.sequence - b.sequence)` 排序

**[Info] mock-event-emitter.js 的序列号管理独立于 flock**
- `mock-event-emitter.js:31-33` 直接读取 `.event_sequence` 文件并在内存中自增。
- 作为测试工具可接受，但如果与真实 Agent 同时运行会产生序列号冲突。
- 这是预期行为（mock 不应与生产并行使用）。

### 4.4 客户端事件去重与截断

**文件**: `gui/src/store/index.ts:177-184`

```typescript
addEvents: (newEvents) =>
  set((state) => {
    const seen = new Set(state.events.map((e) => e.sequence));
    const unique = newEvents.filter((e) => !seen.has(e.sequence));
    const merged = [...state.events, ...unique]
      .sort((a, b) => a.sequence - b.sequence)
      .slice(-1000);
```

**[Info] 去重 + 排序 + 截断三合一实现**
- `Set` 去重保证 WebSocket 重连时 snapshot 不会产生重复。
- `.sort()` 保证序列号有序性（即使网络乱序到达）。
- `.slice(-1000)` 截断保护前端内存，保留最近 1000 条事件。

### 本节评分: 3.5 / 5

---

## 问题汇总

### Critical (1)

| 编号 | 问题 | 文件:行号 | 影响 |
|------|------|-----------|------|
| **J2** | `broadcastNewEvents()` 中 `JSON.parse(line)` 无 try-catch，且 `lastLineCount` 已提前更新 | `autopilot-server.ts:86-89` | 单行损坏导致后续所有事件永久丢失 |

### Major (2)

| 编号 | 问题 | 文件:行号 | 影响 |
|------|------|-----------|------|
| **J1** | `getEventLines()` 每次全量读取文件 | `autopilot-server.ts:70-77` | 长会话下 I/O 性能退化 |
| **J3** | 事件写入 `echo >> events.jsonl` 无文件锁保护 | `emit-*-event.sh:110` | 8 Agent 并发写入理论上可能损坏行 |

### Minor (4)

| 编号 | 问题 | 文件:行号 | 影响 |
|------|------|-----------|------|
| **M1** | flock 无超时参数，可能死锁 | `_common.sh:298` | 极端场景下所有 Agent 挂起 |
| **M2** | 锁文件 `.event_sequence.lock` 无清理 | `_common.sh:293` | 工程卫生 |
| **M3** | snapshot 发送中 `JSON.parse` 无保护 | `autopilot-server.ts:207` | 新连接时可能因单条坏数据崩溃 |
| **M4** | `wsClients` 使用 `any` 类型 | `autopilot-server.ts:64` | 类型安全缺失 |
| **M5** | `mock-event-emitter.js` 泄入 dist | `build-dist.sh:22` | 调试工具进入生产包 |

### Info (合格项)

- flock 子 shell 模式正确，锁自动释放
- 事件格式含全部 10 个必需字段，ISO-8601 时间戳带 UTC 时区
- 序列号从发射到客户端消费的全链路一致
- 客户端去重 + 排序 + 截断三合一保护
- CLAUDE.md DEV-ONLY 裁剪验证闭环
- 产物隔离验证覆盖 5 类禁止项
- 客户端 WSBridge 的 JSON.parse 有 try-catch 保护
- 指数退避重连策略合理（1s -> 1.5x -> 10s cap）

---

## 评分

| 审计子维度 | 满分 | 得分 | 备注 |
|------------|------|------|------|
| 原子性操作 | 5 | 4.5 | flock 正确但缺超时 |
| 服务端 I/O | 5 | 3.0 | 1 Critical + 1 Major |
| 产物纯净度 | 5 | 4.5 | mock 工具泄入 dist |
| 事件系统 | 5 | 3.5 | 写入无锁保护 |

**总分: 15.5 / 20**

### 优先修复建议

1. **[P0]** 在 `broadcastNewEvents()` 的 `JSON.parse(line)` 外层包裹 try-catch，跳过损坏行继续广播。同时将 `lastLineCount` 更新移至成功广播后。
2. **[P1]** 在 `emit-*-event.sh` 中对 `events.jsonl` 写入加 flock 保护，或将序列号获取与事件写入合并到同一个临界区。
3. **[P2]** 将 `getEventLines()` 改为基于字节偏移量的增量读取。
4. **[P2]** 在 `EXCLUDE_SCRIPTS` 中加入 `mock-event-emitter.js`。
5. **[P3]** 为 `flock -x 200` 添加 `-w 5` 超时参数。
