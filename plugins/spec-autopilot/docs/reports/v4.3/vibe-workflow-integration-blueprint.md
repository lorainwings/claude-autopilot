# vibe-workflow Integration Blueprint

> spec-autopilot (Engine) x vibe-workflow (GUI) 集成架构白皮书
> 基于 V4.3 破坏性验证通过后的底层事件流，正式规划上层 GUI 工具架构。

## 1. 系统分层架构

```
┌─────────────────────────────────────────────────────────────┐
│                    vibe-workflow (GUI Layer)                 │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────────┐  │
│  │ Phase    │  │ Parallel │  │ Gate     │  │ Error      │  │
│  │ Timeline │  │ Task     │  │ Decision │  │ Recovery   │  │
│  │ Progress │  │ Kanban   │  │ Card     │  │ Panel      │  │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └─────┬──────┘  │
│       │              │             │               │         │
│  ─────┴──────────────┴─────────────┴───────────────┴───────  │
│                    Event Renderer Layer                       │
│                 (React/Vue State Manager)                     │
├─────────────────────────────────────────────────────────────┤
│                   Communication Bridge                       │
│  ┌─────────────────────┐    ┌────────────────────────────┐  │
│  │ v4.2: File Watcher  │    │ v5.0: WebSocket Server     │  │
│  │ (tail -f JSONL)     │    │ (bidirectional)            │  │
│  └─────────┬───────────┘    └─────────────┬──────────────┘  │
├────────────┼──────────────────────────────┼─────────────────┤
│            │    spec-autopilot (Engine)    │                  │
│  ┌─────────▼───────────────────────────────▼─────────────┐  │
│  │              Event Bus (logs/events.jsonl)             │  │
│  └───────────────────────┬───────────────────────────────┘  │
│  ┌───────────────────────▼───────────────────────────────┐  │
│  │         8-Phase Pipeline + 3-Layer Gate System         │  │
│  │  Phase 0 → 1 → [2 → 3 →] 4 → 5 → 6 → 7              │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## 2. 通信桥梁设计

### 2.1 Phase 1 (v4.2): File System Watcher

当前可直接使用的方案，零改造成本。

```typescript
// vibe-workflow/src/bridge/file-watcher.ts
import { watch } from 'chokidar';
import { createReadStream } from 'fs';
import { createInterface } from 'readline';

class EventBridge {
  private eventsPath: string;
  private offset = 0;
  private handlers = new Map<string, Function[]>();

  constructor(projectRoot: string) {
    this.eventsPath = `${projectRoot}/logs/events.jsonl`;
  }

  start() {
    // Watch for file changes (new events appended)
    const watcher = watch(this.eventsPath, { persistent: true });
    watcher.on('change', () => this.readNewEvents());
  }

  private async readNewEvents() {
    const content = await fs.readFile(this.eventsPath, 'utf-8');
    const lines = content.split('\n').filter(Boolean);
    const newEvents = lines.slice(this.offset).map(l => JSON.parse(l));
    this.offset = lines.length;

    for (const event of newEvents) {
      this.dispatch(event);
    }
  }

  private dispatch(event: AutopilotEvent) {
    const listeners = this.handlers.get(event.type) || [];
    listeners.forEach(fn => fn(event));
  }

  on(type: string, handler: Function) {
    if (!this.handlers.has(type)) this.handlers.set(type, []);
    this.handlers.get(type)!.push(handler);
  }
}
```

### 2.2 Phase 2 (v5.0): WebSocket 双向通信

引擎侧启动 WebSocket Server，GUI 连接后实时推送事件 + 接收决策指令。

```typescript
// spec-autopilot 侧: scripts/event-server.ts (新增)
import { WebSocketServer } from 'ws';

const wss = new WebSocketServer({ port: 8765 });

// 引擎 → GUI: 推送事件
function emitToGUI(event: AutopilotEvent) {
  wss.clients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(JSON.stringify(event));
    }
  });
}

// GUI → 引擎: 接收决策指令
wss.on('connection', (ws) => {
  ws.on('message', (data) => {
    const command = JSON.parse(data.toString());
    // command: { type: 'gate_decision', phase: 5, action: 'approve' | 'reject' | 'retry' }
    handleGUICommand(command);
  });
});
```

```typescript
// vibe-workflow 侧: 连接 WebSocket
class WSBridge extends EventBridge {
  private ws: WebSocket;

  connect(port = 8765) {
    this.ws = new WebSocket(`ws://localhost:${port}`);
    this.ws.onmessage = (msg) => {
      const event = JSON.parse(msg.data);
      this.dispatch(event);
    };
  }

  // GUI → 引擎: 发送决策
  sendDecision(phase: number, action: 'approve' | 'reject' | 'retry') {
    this.ws.send(JSON.stringify({
      type: 'gate_decision',
      phase,
      action,
      timestamp: new Date().toISOString()
    }));
  }
}
```

## 3. GateBlock 交互式决策卡片

当引擎触发 `gate_block` 事件时，GUI 弹出决策卡片：

```
┌─────────────────────────────────────────────┐
│  ⛔ Gate Block — Phase 6 Entry Denied       │
│─────────────────────────────────────────────│
│                                             │
│  Reason: zero_skip_check failed             │
│  Phase:  5 → 6                              │
│  Score:  6/8 (threshold: 8/8)               │
│                                             │
│  Details:                                   │
│  • 2 tests skipped in auth.test.ts          │
│  • Change coverage: 75% < 80%              │
│                                             │
│  ┌──────────┐ ┌──────────┐ ┌────────────┐  │
│  │ 🔄 Retry │ │ 🔧 Fix   │ │ ⏭ Override │  │
│  │ Phase 5  │ │ & Re-run │ │ (Confirm)  │  │
│  └──────────┘ └──────────┘ └────────────┘  │
│                                             │
│  ℹ️ Override requires explicit confirmation  │
└─────────────────────────────────────────────┘
```

### React 组件设计

```tsx
// vibe-workflow/src/components/GateBlockCard.tsx

interface GateBlockProps {
  event: GateBlockEvent;
  onDecision: (action: 'retry' | 'fix' | 'override') => void;
}

function GateBlockCard({ event, onDecision }: GateBlockProps) {
  const [showConfirm, setShowConfirm] = useState(false);

  return (
    <Card variant="destructive">
      <CardHeader>
        <StatusIcon type="blocked" />
        <Title>Gate Block — Phase {event.phase} Entry Denied</Title>
      </CardHeader>
      <CardBody>
        <Field label="Reason">{event.payload.error_message}</Field>
        <Field label="Score">{event.payload.gate_score}</Field>
      </CardBody>
      <CardFooter>
        <Button onClick={() => onDecision('retry')}>Retry Phase {event.phase - 1}</Button>
        <Button onClick={() => onDecision('fix')}>Fix & Re-run</Button>
        <Button
          variant="danger"
          onClick={() => setShowConfirm(true)}
        >
          Override
        </Button>
      </CardFooter>
      {showConfirm && (
        <ConfirmDialog
          message="Override will skip gate validation. Are you sure?"
          onConfirm={() => onDecision('override')}
          onCancel={() => setShowConfirm(false)}
        />
      )}
    </Card>
  );
}
```

## 4. Phase 进度条 + 并发任务看板

### 4.1 Phase Timeline Progress

```
┌─────────────────────────────────────────────────────────────┐
│  Pipeline: feat/user-authentication         Mode: full      │
│─────────────────────────────────────────────────────────────│
│                                                             │
│  ●──────●──────●──────●──────◉──────○──────○──────○        │
│  P0     P1     P2     P4     P5     P6     P7     Done     │
│  Init   Design Resrch Tests  Impl   Verify Archv           │
│  ✅     ✅     ✅     ✅     ⏳     ⬜     ⬜               │
│  0.5s   45s    30s    120s   ...    -      -                │
│                                                             │
│  Overall: 4/7 phases complete  |  ETA: ~5 min              │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 Parallel Task Kanban (Phase 5)

```
┌────────────────────────────────────────────────────────────┐
│  Phase 5: Implementation  |  Mode: parallel  |  3 domains │
│────────────────────────────────────────────────────────────│
│                                                            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐       │
│  │  backend/   │  │  frontend/  │  │  infra/     │       │
│  │─────────────│  │─────────────│  │─────────────│       │
│  │ ✅ auth.ts  │  │ ✅ login.vue│  │ ⏳ docker   │       │
│  │ ✅ user.ts  │  │ ⏳ dash.vue │  │ ⬜ nginx    │       │
│  │ ⏳ db.ts    │  │ ⬜ api.ts   │  │             │       │
│  │             │  │             │  │             │       │
│  │ 2/3 done   │  │ 1/3 done    │  │ 0/2 done   │       │
│  │ ~60s left   │  │ ~90s left   │  │ ~120s left  │       │
│  └─────────────┘  └─────────────┘  └─────────────┘       │
│                                                            │
│  Speedup: 2.4x vs serial  |  ETA: ~120s (max domain)     │
└────────────────────────────────────────────────────────────┘
```

### React 组件化建议

```tsx
// vibe-workflow/src/components/

// 顶层布局
<AutopilotDashboard>
  <PipelineHeader changeName={...} mode={...} />
  <PhaseTimeline phases={phases} currentPhase={5} />

  {currentPhase === 5 && parallel && (
    <ParallelKanban domains={domains} metrics={parallelMetrics} />
  )}

  <EventLog events={recentEvents} />

  {gateBlockEvent && (
    <GateBlockCard event={gateBlockEvent} onDecision={handleDecision} />
  )}
</AutopilotDashboard>

// State Management (Zustand/Pinia)
interface AutopilotStore {
  phases: PhaseState[];           // 8 phases, each with status/duration
  currentPhase: number;           // Active phase
  events: AutopilotEvent[];       // All captured events
  gateBlockEvent: GateBlockEvent | null;  // Active gate block
  parallelDomains: DomainState[]; // Phase 5 parallel tracking

  // Actions
  processEvent(event: AutopilotEvent): void;
  sendDecision(phase: number, action: string): void;
}
```

## 5. 事件流增强建议 (v5.0 Roadmap)

基于 Task 4 审查发现，建议为所有事件增加以下字段以提升 GUI 可用性：

| 字段 | 类型 | 用途 | 优先级 |
|------|------|------|--------|
| `change_name` | `string` | 标识流水线实例，用于标题展示 | P1 |
| `session_id` | `string (uuid)` | 跨 Phase 事件关联，区分不同运行 | P1 |
| `phase_label` | `string` | 人类可读名称 (Init/Design/Research/Tests/Impl/Verify/Archive) | P2 |
| `total_phases` | `number` | 进度条百分比计算 (根据 mode 动态: full=8, lite=5, minimal=4) | P2 |
| `retry_count` | `number` | 错误重试渲染 | P2 |

增强后的事件 Schema:

```typescript
interface AutopilotEventV5 {
  // 现有字段 (v4.2)
  type: EventType;
  phase: number;
  mode: 'full' | 'lite' | 'minimal';
  timestamp: string;
  payload: Record<string, unknown>;

  // 新增字段 (v5.0)
  change_name: string;      // e.g., "feat/user-auth"
  session_id: string;        // e.g., "a1b2c3d4-e5f6-..."
  phase_label: string;       // e.g., "Implementation"
  total_phases: number;      // e.g., 8 (full mode)
  sequence: number;          // Auto-increment event counter
}
```

## 6. 部署拓扑

```
开发者机器
├── Claude Code CLI
│   └── spec-autopilot plugin (Engine)
│       ├── writes → logs/events.jsonl
│       └── listens ← (v5.0) ws://localhost:8765
│
├── vibe-workflow (GUI)          # Electron / Web App
│   ├── reads ← logs/events.jsonl (v4.2 File Watcher)
│   ├── connects ← ws://localhost:8765 (v5.0 WebSocket)
│   └── sends → gate decisions back to engine
│
└── (Optional) VS Code Extension
    └── Sidebar panel embedding vibe-workflow components
```

## 7. 安全边界

- **只读默认**: GUI 默认只有事件读取权限，Gate Override 需显式确认
- **本地通信**: File Watcher 和 WebSocket 均限于 localhost，不暴露网络端口
- **决策审计**: 所有 GUI 发送的决策指令记入 `logs/gui-decisions.jsonl`
- **沙箱隔离**: GUI 进程不持有 Claude Code 的 API Token，通过事件桥间接交互

## 8. 验证结果摘要 (V4.3 Acid Test)

本白皮书基于以下验证结论：

| Task | 验证项 | 结论 |
|------|--------|------|
| Task 1 | L2 Hook 绝对阻断力 | 3/3 PASS — TODO/恒真断言/Sad Path 缺失全部拦截 |
| Task 2 | Phase 5 并发引擎防护 | 6/7 PASS — 发现并修复 `_constraint_loader.py` P1 漏洞 |
| Task 3 | 版本号确定性同步 | PASS — `bump-version.sh` 一键同步 4 文件 |
| Task 4 | 事件总线 Payload 完整性 | PASS (修复后) — 发现并修复 `${4:-{}}` P0 缺陷 |

**底层引擎经破坏性验证后已达到 GUI 集成就绪状态。**
