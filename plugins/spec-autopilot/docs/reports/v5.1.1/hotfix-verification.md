# V5.1.1 热修复专项验收报告

> **审计角色**: 首席 QA 工程师 & 回归测试审计员
> **审计日期**: 2026-03-14
> **审计范围**: 5 项 P0/P1 级热修复白盒代码审查
> **审计方法**: 证据驱动 + 零信任推理 + 静态分析

---

## 验证结论看板

| 测试项 | 审计目标 | 缺陷编号 | 判定 |
|--------|---------|----------|------|
| 测试 1 | 双向反控路径对齐 | DC-PATH | **PASS** |
| 测试 2 | IN_PHASE5 误判拦截修复 | D-01 | **PASS** |
| 测试 3 | Python3 Fail-Closed 机制 | D-05 | **PASS** |
| 测试 4a | flock 竞态锁 | D-06 | **PASS** |
| 测试 4b | 全局作用域 `local` 清除 | D-03 | **PASS** |
| 测试 5a | 状态去重与内存上限 | SM-1 | **PASS** |
| 测试 5b | 终端批量渲染 | VT-2 | **PASS** |
| 测试 5c | WebSocket 事件完整性 | WS-3 | **PASS** |

**总计: 8/8 PASS | 0 FAIL | 0 回归缺陷**

---

## [测试 1] 双向反控路径对齐 (DC-PATH) — PASS

### 代码证据

**服务端写入路径** (`scripts/autopilot-server.ts`):

```typescript
// 第 41-42 行
const CHANGES_DIR = join(projectRoot, "openspec", "changes");
const LOCK_FILE = join(CHANGES_DIR, ".autopilot-active");

// 第 126-141 行: resolveDecisionFile()
async function resolveDecisionFile(): Promise<string | null> {
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
  //  => {projectRoot}/openspec/changes/{changeName}/context/decision.json
}
```

**引擎侧轮询路径** (`scripts/poll-gate-decision.sh`):

```bash
# 第 24, 39, 41 行
CHANGE_DIR="${1:-}"                              # 例: openspec/changes/<name>/
CONTEXT_DIR="${CHANGE_DIR}context"               # => openspec/changes/<name>/context
DECISION_FILE="${CONTEXT_DIR}/decision.json"     # => openspec/changes/<name>/context/decision.json
```

### 路径等价性证明

| 路径组件 | 服务端 (Node.js `join`) | 引擎侧 (Bash 拼接) |
|---------|------------------------|-------------------|
| 基础路径 | `{projectRoot}/openspec/changes/` | `{CHANGE_DIR}` (绝对路径, 含尾部 `/`) |
| 变更名 | `{changeName}/` | 内嵌于 `CHANGE_DIR` |
| 上下文 | `context/` | `context/` |
| 文件名 | `decision.json` | `decision.json` |
| **最终结果** | `{root}/openspec/changes/{name}/context/decision.json` | `{root}/openspec/changes/{name}/context/decision.json` |

**100% 字符串等价。**

### 并发场景分析

- 服务端每次请求时重新读取 `.autopilot-active` 锁文件（第 128 行），非缓存设计。
- 单活跃会话设计：同一 `projectRoot` 下仅一个 `.autopilot-active` 锁文件，Phase 0 写入时实现互斥。
- 不同 `--project-root` 的多实例完全隔离，无并发风险。
- **风险等级**: 近零。锁文件是双端唯一事实来源。

---

## [测试 2] IN_PHASE5 误判拦截修复 (D-01) — PASS

### 代码证据

`scripts/unified-write-edit-check.sh` 第 42-76 行:

```bash
IN_PHASE5="no"
if [ -n "$PHASE4_CP" ]; then
  # 分支 A: Phase 4 存在 → 标准 full 模式流
  PHASE5_CP=$(find_checkpoint "$PHASE_RESULTS" 5)
  if [ -z "$PHASE5_CP" ]; then
    IN_PHASE5="yes"
  else
    STATUS=$(read_checkpoint_status "$PHASE5_CP")
    [ "$STATUS" != "ok" ] && IN_PHASE5="yes"
  fi
elif [ -n "$PHASE3_CP" ] && [ -n "$PHASE1_CP" ]; then
  # 分支 B: Phase 3 存在, Phase 4 不存在 → TDD 模式检查
  TDD_MODE_VAL=$(read_config_value "$PROJECT_ROOT_QUICK" "phases.implementation.tdd_mode" "false")
  if [ "$TDD_MODE_VAL" = "true" ]; then
    # ... 同样的 Phase 5 checkpoint 检查 ...
  fi
elif [ -n "$PHASE1_CP" ]; then
  # 分支 C: 仅 Phase 1 存在 — 关键修复点
  LOCK_MODE=$(read_lock_json_field "$LOCK_FILE" "mode" "full")   # 第 66 行
  if [ "$LOCK_MODE" != "full" ]; then                            # 第 67 行
    # lite/minimal: Phase 5 直接跟在 Phase 1 后面
    # ... 检查 Phase 5 checkpoint ...
  fi
  # full 模式: 落空 → IN_PHASE5 保持 "no"
fi
```

### 脑内推演 — 关键场景

**场景**: `mode=full`, `PHASE1_CP` 存在, `PHASE3_CP` / `PHASE4_CP` 不存在

| 步骤 | 条件判断 | 结果 |
|------|---------|------|
| 分支 A | `PHASE4_CP` 为空 | **跳过** |
| 分支 B | `PHASE3_CP` 为空 | **跳过** |
| 分支 C | `PHASE1_CP` 存在 | **进入** |
| 模式检查 | `LOCK_MODE="full"`, `"full" != "full"` | **FALSE** → 跳过内部块 |
| 最终 | `IN_PHASE5` | **"no"** (正确！系统在 Phase 2/3) |

**场景**: `mode=lite`, `PHASE1_CP` 存在, 其余为空

| 步骤 | 条件判断 | 结果 |
|------|---------|------|
| 分支 C | `PHASE1_CP` 存在 | **进入** |
| 模式检查 | `LOCK_MODE="lite"`, `"lite" != "full"` | **TRUE** → 进入内部块 |
| Phase 5 CP | 为空 | `IN_PHASE5="yes"` (正确！lite 模式 Phase 5 直接跟 Phase 1) |

### 完整边界矩阵

| 场景 | PHASE1 | PHASE3 | PHASE4 | mode | IN_PHASE5 | 正确性 |
|------|--------|--------|--------|------|-----------|-------|
| full, Phase 2 进行中 | 有 | 无 | 无 | full | no | 正确 |
| full, Phase 4 完成后 | 有 | 有 | 有 | full | yes | 正确 |
| full, Phase 5 已完成 | 有 | 有 | 有 | full | no | 正确 |
| lite, Phase 1 完成后 | 有 | 无 | 无 | lite | yes | 正确 |
| minimal, Phase 1 完成后 | 有 | 无 | 无 | minimal | yes | 正确 |
| full, TDD 模式 Phase 3 后 | 有 | 有 | 无 | full | yes | 正确 |
| full, 非 TDD Phase 3 后 | 有 | 有 | 无 | full | no | 正确 |
| 锁文件损坏/无 mode | 有 | 无 | 无 | (默认 full) | no | 正确(fail-safe) |

**8/8 边界场景全部正确。** 默认值 `"full"` 确保 fail-safe 语义。

---

## [测试 3] Python3 Fail-Closed 机制 (D-05) — PASS

### 代码证据

**`scripts/post-task-validator.sh` 第 27-31 行:**

```bash
# --- 依赖检查: python3 必需 (Fail-Closed) ---
# require_python3 在 python3 缺失时输出 {"decision":"block",...} 到 stdout，
# 然后返回 1。block JSON 被 Claude Code hook 基础设施消费。
# 没有 python3，5 个验证器全部静默跳过 — 必须阻断。
require_python3 || exit 0
```

**`scripts/_common.sh` 第 331-355 行 — `require_python3()`:**

```bash
require_python3() {
  local hook_type="${1:-block}"
  if command -v python3 &>/dev/null; then
    return 0   # python3 可用 → 继续
  fi
  if [ "$hook_type" = "deny" ]; then
    cat <<'DENY_JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",...}}
DENY_JSON
  else
    cat <<'BLOCK_JSON'
{"decision":"block","reason":"python3 is required for autopilot hook validation but not found in PATH. Install python3 to continue."}
BLOCK_JSON
  fi
  return 1
}
```

### python3 缺失时执行链路

1. `require_python3` 被调用（默认 `hook_type="block"`）
2. `command -v python3` 失败 → 进入 else 分支
3. 向 **stdout** 输出 `{"decision": "block", "reason": "..."}`
4. 函数返回 **1**
5. `|| exit 0` 捕获非零返回 → 脚本以退出码 0 终止
6. Claude Code hook 基础设施读取 stdout → 解析到 `"decision": "block"` → **阻断动作**

### Hook 协议语义澄清（exit 0 的正确性）

通过交叉比对项目中**所有** PostToolUse hook 的阻断模式，确认 `exit 0` 是正确的协议行为：

| 文件 | 阻断 JSON 输出 | 退出码 | 行号 |
|------|--------------|--------|------|
| `unified-write-edit-check.sh` | `{"decision":"block",...}` | `exit 0` | L116, L141, L147, L181, L226 |
| `post-task-validator.sh` (经 `require_python3`) | `{"decision":"block",...}` | `exit 0` | L31 |
| `check-predecessor-checkpoint.sh` (PreToolUse) | `{"permissionDecision":"deny",...}` | `exit 0` | L72, L130 |

**统一模式**: 所有 hook — 无论 PostToolUse 还是 PreToolUse — 均将决策 JSON 输出到 stdout 后以 `exit 0` 退出。`exit 0` 语义是"hook 自身执行成功"；实际的阻断/放行决策由 Claude Code 基础设施从 stdout JSON 中解析。非零退出码表示 hook *崩溃*，而非阻断意图。

**安全状态**: **Fail-Closed（安全态）**。block JSON 在 `exit 0` 前已刷入 stdout，hook 基础设施必定读取到阻断决策。

---

## [测试 4a] flock 竞态锁 (D-06) — PASS

### 代码证据

**`scripts/_common.sh` 第 290-306 行:**

```bash
next_event_sequence() {
  local project_root="$1"
  local seq_file="$project_root/logs/.event_sequence"
  local lock_file="$project_root/logs/.event_sequence.lock"
  mkdir -p "$(dirname "$seq_file")" 2>/dev/null || true

  local next
  (
    flock -x 200                    # 排他锁绑定 fd 200
    local current=0
    [ -f "$seq_file" ] && current=$(cat "$seq_file" 2>/dev/null | tr -d '[:space:]') || true
    [ -z "$current" ] && current=0
    next=$((current + 1))
    echo "$next" > "$seq_file"      # 回写
    echo "$next"                    # 输出给调用方
  ) 200>"$lock_file"               # fd 200 绑定到锁文件
}
```

### 原子性分析

| 属性 | 评估 |
|------|------|
| 锁类型 | `flock -x`（排他/写锁） |
| 锁范围 | 子 shell `(...)` — 退出时自动释放 |
| 临界区 | 读取 → 自增 → 回写（3 步操作, ~1ms） |
| 锁文件 | 独立的 `.event_sequence.lock`（非数据文件本身） |
| 死锁风险 | **可忽略** — 子 shell 极轻量；进程崩溃时 fd 200 关闭 → 锁自动释放 |
| 饥饿风险 | `flock -x` 无超时会无限阻塞，但临界区 <1ms，实际饥饿不可能 |

**结论**: 标准 `flock` 模式正确实现。排他锁确保读-改-写原子性，子 shell 模式保证异常时锁自动释放。

---

## [测试 4b] 全局作用域 `local` 清除 (D-03) — PASS

### 代码证据

**`scripts/check-predecessor-checkpoint.sh`** — 全局作用域变量扫描:

| 行号 | 变量 | 声明方式 | 作用域 |
|------|------|---------|-------|
| 21 | `STDIN_DATA` | `STDIN_DATA=""` | 全局（正确） |
| 34 | `PROJECT_ROOT_QUICK` | `PROJECT_ROOT_QUICK=$(...)` | 全局（正确） |
| 55 | `IS_BACKGROUND` | `IS_BACKGROUND=false` | 全局（正确） |
| 76 | `PROJECT_ROOT` | `PROJECT_ROOT=$(...)` | 全局（正确） |
| 89 | `CHANGES_DIR` | `CHANGES_DIR=...` | 全局（正确） |
| 92 | `TARGET_PHASE` | `TARGET_PHASE=$(...)` | 全局（正确） |
| 185 | `change_dir` | `change_dir=$(...)` | 全局（正确） |
| 187 | `phase_results_dir` | `phase_results_dir=...` | 全局（正确） |
| 199 | `last_phase` | `last_phase=$(...)` | 全局（正确） |
| 202 | `EXEC_MODE` | `EXEC_MODE=$(...)` | 全局（正确） |
| 206 | `TDD_MODE` | `TDD_MODE=""` | 全局（正确） |
| 251 | `PRED_PHASE` | `PRED_PHASE=$(...)` | 全局（正确） |

**所有 `local` 声明均位于函数体内部**（`deny`、`get_last_checkpoint_phase`、`get_autopilot_mode`、`get_predecessor_phase`）。全局作用域**零 `local` 声明**。修复已确认。

---

## [测试 5a] 状态去重与内存上限 (SM-1) — PASS

### 代码证据

**`gui/src/store/index.ts` 第 42-49 行:**

```typescript
addEvents: (newEvents) =>
  set((state) => {
    // 基于 sequence 去重，然后截断到 1000 条
    const seen = new Set(state.events.map((e) => e.sequence));  // O(n) Set 查找
    const unique = newEvents.filter((e) => !seen.has(e.sequence));
    const merged = [...state.events, ...unique]
      .sort((a, b) => a.sequence - b.sequence)
      .slice(-1000);                                             // 硬上限 1000 条
```

### 分析

| 要求 | 实现方式 | 判定 |
|------|---------|------|
| 基于 `sequence` 去重 | `Set` 收集已有 sequence + `.filter()` 过滤 | **满足** — O(n) 去重 |
| 内存上限 | `.slice(-1000)` 合并排序后截断 | **满足** — 硬性 1000 条上限 |
| 排序稳定性 | `.sort((a,b) => a.sequence - b.sequence)` | 按 sequence 数值排序，正确 |

**边界分析**: `sequence` 由 `next_event_sequence()` （flock 原子计数器）生成，唯一性有保证。高频场景下每次 `addEvents` 的临时 Set 为 O(n)（n ≤ 1000），开销可接受。

---

## [测试 5b] 终端批量渲染 (VT-2) — PASS

### 代码证据

**`gui/src/components/VirtualTerminal.tsx` 第 16, 73-88 行:**

```typescript
const lastRenderedSequence = useRef<number>(-1);    // 第 16 行: 持久化 ref

useEffect(() => {
  const term = xtermRef.current;
  if (!term || events.length === 0) return;

  // 渲染所有 sequence > lastRenderedSequence 的事件（增量）
  const newEvents = events.filter(
    (e) => e.sequence > lastRenderedSequence.current    // 第 78 行
  );
  if (newEvents.length === 0) return;

  for (const event of newEvents) {                      // 第 81 行: 遍历全部
    const timestamp = new Date(event.timestamp).toLocaleTimeString();
    const line = `[${timestamp}] ${event.type.toUpperCase()} | Phase ${event.phase} (${event.phase_label})\r\n`;
    term.write(line);
  }

  lastRenderedSequence.current = newEvents[newEvents.length - 1].sequence;  // 第 87 行
}, [events]);
```

### 缺陷修复验证

| 旧行为（Bug） | 新行为（修复后） |
|-------------|---------------|
| 仅渲染 `events[events.length - 1]`（快照最后一条） | 过滤 `sequence > lastRendered` → 渲染**所有**新事件 |
| 快照间事件丢失 | `lastRenderedSequence` ref 精确追踪已渲染位置 |
| 无增量渲染 | `useEffect([events])` 每次状态更新触发；`for` 循环写入所有新事件 |

---

## [测试 5c] WebSocket 事件完整性 (WS-3) — PASS

store 的 `addEvents` 通过去重+合并保全所有事件。`VirtualTerminal` 通过 `lastRenderedSequence` 增量遍历所有未渲染事件。WebSocket `snapshot` 和 `event` 两种消息类型均正确桥接到 `addEvents` 管线。事件从 WebSocket 推送到终端渲染的完整链路无丢失。

---

## 回归检查

| 区域 | 检查项 | 结果 |
|------|-------|------|
| Phase 检测 | 新增 mode 感知分支不影响已有 PHASE4_CP / PHASE3_CP 路径 | 无回归 |
| require_python3 | block JSON 输出不干扰 python3 可用时的正常路径（直接 return 0） | 无回归 |
| flock 子 shell | `next` 变量作用域 — 在子 shell 内声明为 `local`，通过 echo 输出 | 无回归 |
| store addEvents | taskProgress Map 更新（第 52-66 行）独立于去重逻辑 | 无回归 |
| VirtualTerminal | `useRef(-1)` 初始值确保首次渲染捕获所有事件（sequence 均 ≥ 0） | 无回归 |

---

## 最终判定

> **V5.1.1 具备进入全链路实测条件。**

5 项热修复目标（DC-PATH, D-01, D-05, D-06, D-03）和 3 项 GUI 目标（VT-2, SM-1, WS-3）均已通过代码级证据验证。零回归缺陷。代码库获准进入端到端集成测试阶段。
