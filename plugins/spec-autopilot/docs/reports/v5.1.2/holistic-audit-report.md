# spec-autopilot v5.1.2 全链路 360° 穿透审计白皮书

> **审计日期**: 2026-03-14
> **审计方法**: 五维全栈源码确证（禁止臆断，逐文件逐行）
> **审计范围**: `plugins/spec-autopilot/` 全目录（scripts/ hooks/ skills/ gui/src/ tests/）
> **审计版本**: v5.1.2 候选版本

---

## 一、全局评分大盘

| 维度 | 满分 | 得分 | 核心发现 |
|------|------|------|---------|
| 维度一：编排与状态机流转 | 20 | **16.5** | 三层门禁架构优秀，但 `min_qa_rounds` 缺失 L2 硬阻断 |
| 维度二：L2 确定性铁壁 | 20 | **17.0** | 反合理化引擎 29 条模式完备，但 python3 缺失时 CHECK 4 fail-open |
| 维度三：TDD 引擎与代码生成 | 20 | **13.5** | RED/GREEN 隔离扎实，但 `tdd-refactor-rollback.sh` 未实现 |
| 维度四：遥测、并发与底层基建 | 20 | **15.5** | flock 原子锁正确，但 `broadcastNewEvents` JSON.parse 无 try-catch |
| 维度五：GUI 交互与人机协同 | 20 | **13.0** | 状态机竞态处理精妙，但决策失败无 UI 报警 |
| **加权总分** | **100** | **75.5** | |

### 评级：**B+ — 接近发布标准，需修复 4 个 Critical 问题后方可发布**

```
███████████████████████████████████████░░░░░░░░░░  75.5%
```

---

## 二、五维审计详情

---

### 维度一：编排与状态机流转 (16.5/20)

#### 1.1 Phase 1 Socratic 质询引擎

**Socratic 7 步流程完备性** — `phase1-supplementary.md:14-31`

7 步流程（挑战假设 → 探索替代方案 → 识别隐含需求 → 强制排优 → 魔鬼代言人 → 最小可行范围 → 非功能需求质询）全部就位。v5.2 新增的 Step 7 覆盖并发/分布式/高可用/性能四维关键词强制触发，弥补了原有 6 步流程的盲区。

**[Critical] C1-1: `min_qa_rounds` 缺失 L2 硬阻断**

| 层级 | 实现状态 | 证据 |
|------|---------|------|
| L3 AI 软约束 | 已实现 | `phase1-requirements.md:144-163` 循环逻辑 |
| L2 Hook 硬阻断 | **缺失** | `_post_task_validator.py` 全文搜索 `min_qa` — 零匹配 |
| 配置范围校验 | **缺失** | `_config_validator.py:RANGE_RULES` 无 `min_qa_rounds` 条目 |

AI 可跳过最低轮数约束而不触发任何确定性拦截。此问题已在 `docs/reports/v5.0.10/routing-socratic-benchmark-v5.3.md:216` 被识别但未修复。

#### 1.2 路由矩阵（Feature/Bugfix/Refactor/Chore）

**闭环验证通过** — 路由生成（L3 AI, `phase1-requirements.md:37-94`）→ 路由消费（L2 Hook, `_post_task_validator.py:176-213`）形成完整闭环。

```python
# _post_task_validator.py:207-213 — 路由覆盖消费
_routing_cov = _routing_overrides.get("change_coverage_min_pct")
if _routing_cov is not None:
    FLOOR_MIN_CHANGE_COV = max(FLOOR_MIN_CHANGE_COV, int(_routing_cov))
```

Bugfix 路由可将 `change_coverage` 从默认 80% 提升至 100%，`sad_path` 从 20% 提升至 40%。

#### 1.3 全模式兼容性

**三模式 L2 确定性实现** — `check-predecessor-checkpoint.sh:218-274`

```
full:    0→1→2→3→4→5→6→7
lite:    0→1→5→6→7 （Phase 2/3/4 被 deny）
minimal: 0→1→5→7   （Phase 2/3/4/6 被 deny）
```

**[Major] M1-1**: lite 模式 Phase 1→5 跳跃路径缺少专项测试。`test_lite_mode.sh` 仅测试了 Phase 5→6 和 6→7，未覆盖 Phase 1→5 的允许及 Phase 2/3/4 的拒绝。

#### 1.4 Phase 0-7 完整生命周期

| Phase | 核心机制 | 验证结论 |
|-------|---------|---------|
| Phase 0 | 环境检查 + 崩溃恢复 + 锁文件 | 10 步流程完整，python3/PID 检测到位 |
| Phase 1 | 需求理解（主线程） | 中间态 `phase-1-interim.json` 支持细粒度崩溃恢复 |
| Phase 2-3 | 设计/规格（后台 Agent） | 标准 8 步模板 + Event Bus 事件发射 |
| Phase 4 | 测试设计 | warning→确定性 block (`_post_task_validator.py:157-160`) |
| Phase 5 | 实施 | 三条互斥路径 A/B/C + Wall-clock 超时 L2 Hook |
| Phase 6 | 三路并行（测试/审查/扫描） | `run_in_background: true` |
| Phase 7 | 汇总 + 归档 | 归档必须用户确认，不可自动执行 |

**Checkpoint 原子写入**: Write → .tmp → validate → atomic mv → final verify (`autopilot-gate/SKILL.md:278-301`)

---

### 维度二：L2 确定性铁壁 (17.0/20)

#### 2.1 Write/Edit 拦截网

**统一入口**: `hooks.json` 中 `unified-write-edit-check.sh` 注册为 PostToolUse `^(Write|Edit)$` 唯一 Hook。旧脚本（`banned-patterns-check.sh` 等 4 个）已标记 DEPRECATED。

**5 级检查链**:

| CHECK | 功能 | 实现 | 验证 |
|-------|------|------|------|
| CHECK 0 | 子 Agent 状态隔离 | 阻断 checkpoint/锁文件写入 | 通过 |
| CHECK 1 | TDD 阶段隔离 | RED→仅测试, GREEN→仅实现 | 通过 |
| CHECK 2 | TODO/FIXME/HACK 拦截 | `-i` 不区分大小写 + 白名单 | 通过 |
| CHECK 3 | 恒真断言拦截 | 5 类语言模式（JS/Python/Java/Kotlin/通用） | 通过 |
| CHECK 4 | 代码约束检查 | python3 + `_constraint_loader.py` | **缺陷** |

**[Critical] C2-1: CHECK 4 python3 缺失时 fail-open**

```bash
# unified-write-edit-check.sh:235 — fail-open!
command -v python3 &>/dev/null || exit 0
```

对比 `post-task-validator.sh:31` 的 fail-closed 设计（`require_python3` 输出 block JSON 后退出），`unified-write-edit-check.sh` 在 python3 缺失时直接放行，`forbidden_files/patterns` 约束在 Write/Edit 层完全失效。

#### 2.2 反合理化引擎

**29 条加权模式完备** — `_post_task_validator.py:316-348`

| 分组 | 数量 | 覆盖 |
|------|------|------|
| 英文基础 (v4.0) | 11 条 | 能力不足、范围/技术限制、外部因素等 |
| 英文新增 (v5.2) | 4 条 | 时间/环境/第三方借口 |
| 中文基础 (v4.0) | 11 条 | 对应英文模式的中文翻译 |
| 中文新增 (v5.2) | 3 条 | 时间/环境/第三方借口 |

**三级计分阻断**: score≥5 硬阻断, score≥3 且无 artifacts 硬阻断, score≥2 警告。逻辑无漏洞。

#### 2.3 新增测试资产

| 测试文件 | 用例数 | 质量评价 |
|---------|--------|---------|
| `test_routing_overrides.sh` | 4 | 较高 — 覆盖边界值精确匹配、override 覆盖默认、无 override 回退 |
| `test_tdd_isolation.sh` | 8 | 全面 — RED/GREEN/REFACTOR 三阶段 + 无阶段文件场景 |
| `test_unified_write_edit.sh` | 8 | 高 — 三种 banned pattern + 白名单 + 两种语言恒真断言 + 合法断言无误报 |

**[Minor]**: 缺少 Java/Generic 恒真断言测试、routing_overrides 无效值边界测试、.tdd-stage 异常内容测试。

---

### 维度三：TDD 引擎与代码生成 (13.5/20)

#### 3.1 TDD 生命周期隔离

**创建/消费/销毁链路完整**:

```
主线程 Bash → echo "red" > .tdd-stage
    ↓
子 Agent Write/Edit → Hook: unified-write-edit-check.sh CHECK 1
    ↓ 读取 .tdd-stage
  RED → 阻断实现文件 | GREEN → 阻断测试文件 | REFACTOR → 放行
    ↓
任务完成 → rm -f .tdd-stage
```

L2 Hook 消费端 (`unified-write-edit-check.sh:124-151`) 实现正确：
- RED 阶段：非测试文件 → block
- GREEN 阶段：测试文件 → block
- REFACTOR 阶段：全部放行

8 个测试用例 (`test_tdd_isolation.sh`) 覆盖全部分支。

#### 3.2 自动回滚机制

**[Critical] C3-1: `scripts/tdd-refactor-rollback.sh` 未实现**

通过 Glob 搜索 `plugins/spec-autopilot/**/*rollback*` 返回空结果。该脚本在以下文档中被提议但从未创建：
- `docs/reports/v5.0.10/compliance-audit-v5.3.md:379` — P1 建议改进项
- `docs/roadmap/v5.1.0-execution-plan.md:33` — 执行计划项

当前状态：REFACTOR 失败时 `git checkout -- .` 的回滚**完全依赖 AI 意图执行**（L3 层），无确定性保障。CLAUDE.md 和 `tdd-cycle.md` 声称"自动回滚"，实际上只是 AI 协议指令。

**[Major] M3-1**: `git checkout -- .` 粒度过粗——会丢弃所有未提交修改（包括非 REFACTOR 阶段的改动）。

#### 3.3 Gate 层 TDD 审计

**[Major] M3-2**: Phase 5→6 门禁的 TDD 全局完整性审计（`autopilot-gate/SKILL.md:164-182`）为纯 L3 AI 执行，无确定性 Hook 兜底。

**[Major] M3-3**: 并行 TDD 模式下 RED/GREEN 隔离完全依赖域 Agent L1 自律，`.tdd-stage` 文件机制仅适用于串行模式。

#### 3.4 崩溃恢复

`autopilot-recovery` Skill 提供完整的 TDD 崩溃恢复：
- `.tmp` 残留清理 (SKILL.md:23-25)
- `.tdd-stage` 残留清理 (SKILL.md:28-30)
- per-task TDD 阶段精确恢复（基于 `tdd_cycle` 字段状态推断恢复点）

---

### 维度四：遥测、并发与底层基建 (15.5/20)

#### 4.1 原子性操作

**`next_event_sequence()` flock 锁机制** — `_common.sh`

```bash
(
  flock -x 200
  current=$(cat "$SEQ_FILE" 2>/dev/null || echo "0")
  next=$((current + 1))
  echo "$next" > "$SEQ_FILE"
  echo "$next"
) 200>"$SEQ_FILE.lock"
```

子 shell 模式正确：锁在子 shell 退出时自动释放，避免手动 unlock 遗漏。

**[Minor]**: `flock -x 200` 无超时参数（`-w`），极端场景下可能死锁全部 8 个 Agent。

#### 4.2 服务端 I/O

**[Critical] C4-1: `broadcastNewEvents()` JSON.parse 无 try-catch**

```typescript
// autopilot-server.ts:86-89
const newEvents = lines.slice(lastLineCount).map(l => JSON.parse(l));
lastLineCount = lines.length;
```

`lastLineCount` 在解析**前**已更新。单行 JSON 损坏 → 异常抛出 → 该行之后所有事件被永久跳过 → WebSocket 客户端再也收不到新事件。

**[Major] M4-1**: `getEventLines()` 每次全量读取 `events.jsonl`，增量语义仅靠行数偏移实现。长会话下 I/O 性能持续退化。

**[Major] M4-2**: 三个事件发射器的 `echo >> events.jsonl` 不在 flock 保护范围内。序列号原子性有保证，但文件追加依赖 OS PIPE_BUF 行为。

#### 4.3 产物纯净度

**`build-dist.sh` 验证通过**:
- `tests/` 目录不在构建白名单中
- CLAUDE.md DEV-ONLY 段落裁剪 + 关键词验证闭环
- 产物隔离验证覆盖 gui/docs/tests/CHANGELOG/README 五类禁止项

**[Minor] M4-3**: `mock-event-emitter.js` 测试工具未被 `EXCLUDE_SCRIPTS` 排除，可能泄入 dist 产物。

---

### 维度五：GUI 交互与人机协同 (13.0/20)

#### 5.1 状态机竞态

**decisionAcked 重置逻辑** — `store/index.ts:204-213`

通过 `lastAckedBlockSequence` 精确追踪已确认的 gate_block 序号。新 gate_block 到达且 sequence > lastAckedBlockSequence 时自动重置 `decisionAcked = false`。设计精妙，解决了 G2 竞态问题。

**Set 去重 + sort 排序 + slice(-1000) 截断三合一机制** — `store/index.ts:179-184`

```typescript
const seen = new Set(state.events.map((e) => e.sequence));
const unique = newEvents.filter((e) => !seen.has(e.sequence));
const merged = [...state.events, ...unique]
  .sort((a, b) => a.sequence - b.sequence)
  .slice(-1000);
```

去重、排序、截断三步严密，不会导致重复事件或乱序。

#### 5.2 容错与反馈

**[Critical] C5-1: 决策发送失败无 UI 报警**

```typescript
// GateBlockCard.tsx:43-46
} catch (error) {
  console.error("Decision failed:", error);
  setLoading(null);   // 按钮恢复可点击，但无任何错误提示
}
```

当 WebSocket 断开时，用户点击决策按钮后仅看到按钮恢复为可点击状态，无 toast/红色提示/错误消息。用户可能误以为操作已成功。

**[Major] M5-1**: `WebSocket.send()` 在 OPEN 状态但网络实际断开时不抛异常，消息被静默丢弃。

#### 5.3 渲染性能

**VirtualTerminal 增量渲染** — `VirtualTerminal.tsx:29-130`

通过 `lastRenderedSequence` ref 实现增量渲染，仅对新事件调用 `term.write()`。设计正确且高效。

**[Major] M5-2: 所有高频 Selector 无 Memoization**

`selectPhaseDurations`、`selectTotalElapsedMs`、`selectGateStats` 均为纯函数直接调用，每秒随 `setTick` 强制重渲染触发重新计算。1000 条事件 × 8 phase × 4 次 filter/find ≈ 每秒 64 次数组遍历（两个组件各算一次）。

#### 5.4 WebSocket 管理

**指数退避重连** — `ws-bridge.ts:111-118`

初始 1000ms, 1.5x 增长, 上限 10000ms。防重复定时器到位。

**Snapshot 状态同步** — 重连时服务端推送 snapshot + 客户端 Set 去重，策略正确。

**[Major] M5-3**: 无应用层心跳/Ping-Pong。网络静默断开时 `readyState` 可能长时间停留在 OPEN。

---

## 三、核心修复校验结论

### 3.1 系统稳定性

| 判定维度 | 结论 | 说明 |
|---------|------|------|
| 编排正确性 | **通过** | Phase 0-7 全生命周期闭环，三模式路径互斥 L2 确定性实现 |
| 异常处理 | **通过（附条件）** | Fail-Closed 策略主体正确，但 C2-1 和 C4-1 各有一处 fail-open 缺口 |
| 崩溃恢复 | **通过** | .tmp + .tdd-stage 残留清理 + per-task TDD 阶段恢复 |
| 并发安全 | **通过（附条件）** | flock 原子锁正确，但事件文件追加缺显式锁保护 |

### 3.2 L2 硬约束

| 判定维度 | 结论 | 说明 |
|---------|------|------|
| Write/Edit 拦截 | **未完全通过** | CHECK 0-3 无懈可击，CHECK 4 python3 缺失时 fail-open |
| 反合理化引擎 | **通过** | 29 条中英双语模式 + v5.2 时间/环境/第三方借口 + 三级计分 |
| TDD 隔离 | **部分通过** | 串行模式 L2 扎实，并行模式依赖 L1/L3 |
| TDD 回滚 | **未通过** | `tdd-refactor-rollback.sh` 未实现，回滚为纯 L3 AI 意图 |
| 门禁阈值传递 | **通过** | 配置→路由覆盖→L2 Hook 消费三级递进完整 |

### 3.3 GUI 鲁棒性

| 判定维度 | 结论 | 说明 |
|---------|------|------|
| 状态一致性 | **通过** | sequence 去重 + sort + slice(-1000) 三合一 |
| 用户反馈 | **未通过** | 决策失败无 UI 报警，用户无法感知操作结果 |
| 渲染性能 | **有隐患** | Selector 无缓存，当前规模勉强可用但无增长空间 |
| 连接可靠性 | **有隐患** | 无心跳机制，网络静默断开检测延迟 |

### 发布裁定

> **结论：尚未达到发布标准。** 需修复 4 个 Critical 问题后重新评估。

---

## 四、全链路木桶效应分析

### 4.1 木桶最短板：TDD REFACTOR 回滚

**最脆弱环节**: 缺失的 `scripts/tdd-refactor-rollback.sh`

**影响链**:
```
REFACTOR 测试失败
  → 需要 git checkout -- . 回滚
    → 当前：完全依赖 AI 意图执行（L3）
      → AI 可能不执行回滚、执行错误的回滚、或回滚粒度不当
        → 被污染的代码进入 Phase 6 审查
          → Phase 6 审查也是 L3（AI 执行）
            → 最终产物质量无确定性保障
```

这是整个流水线中唯一一处 **CLAUDE.md 声称为"自动"但实际完全无自动化保障** 的环节，且已在 v5.0.10 审计和 v5.1.0 执行计划中被识别但未修复。

### 4.2 第二短板：broadcastNewEvents JSON 损坏导致事件流永久中断

**最脆弱文件**: `autopilot-server.ts:86-89`

```typescript
// lastLineCount 在 JSON.parse 前更新！
const newEvents = lines.slice(lastLineCount).map(l => JSON.parse(l));
lastLineCount = lines.length;  // 即使 parse 失败也不会回滚此值
```

单行 JSON 损坏（如并发写入导致的 truncated line）→ 该行之后所有事件永久丢失 → GUI 变成"盲人"。

### 4.3 第三短板：决策发送失败的静默吞错

**最脆弱文件**: `GateBlockCard.tsx:43-46`

用户在门禁阻断时做出决策（Override/Retry/Fix），WebSocket 已断开 → 操作静默失败 → 用户以为操作成功 → Autopilot 永远等待用户回应 → 死锁。

---

## 五、全部问题清单（按优先级排序）

### P0 — Critical（发布阻断）

| 编号 | 维度 | 问题 | 文件 | 修复建议 |
|------|------|------|------|---------|
| C3-1 | 三 | `tdd-refactor-rollback.sh` 未实现 | 缺失文件 | 创建脚本，封装 `git stash` + 回滚 + `git stash pop`，由 tdd-cycle.md 改为调用脚本 |
| C4-1 | 四 | `broadcastNewEvents` JSON.parse 无 try-catch，lastLineCount 提前更新 | `autopilot-server.ts:86-89` | 逐行 try-catch，失败行跳过但不更新偏移量 |
| C5-1 | 五 | 决策发送失败无 UI 报警 | `GateBlockCard.tsx:43-46` | catch 中添加 `setError(message)` + UI 红色提示条 |
| C1-1 | 一 | `min_qa_rounds` 缺失 L2 硬阻断 | `_post_task_validator.py` | Validator 5 增加 Phase 1 decisions 数组长度校验 |

### P1 — Major

| 编号 | 维度 | 问题 | 修复建议 |
|------|------|------|---------|
| C2-1 | 二 | CHECK 4 python3 缺失 fail-open | 改用 `require_python3 \|\| exit 0` |
| M3-2 | 三 | Gate 层 TDD 审计为纯 L3 | 增加确定性 Hook 扫描 phase5-tasks/task-N.json |
| M3-3 | 三 | 并行 TDD 无 L2 隔离 | 合并后扫描 git log 验证 test-first commit 顺序 |
| M4-1 | 四 | getEventLines 全量读取无增量 | 使用文件字节偏移替代行数偏移 |
| M4-2 | 四 | 事件文件追加缺显式锁 | 将 echo >> 纳入 flock 保护范围 |
| M5-2 | 五 | Selector 无 Memoization | 使用 useMemo 或 Zustand derived state |
| M5-3 | 五 | 无 WebSocket 心跳 | 添加 30s ping/pong + 超时重连 |
| M5-1 | 五 | WebSocket.send 静默丢包 | 发送前检查 readyState + 添加消息确认机制 |
| M1-1 | 一 | lite 模式 Phase 1→5 缺少测试 | 补充 test_lite_mode.sh 用例 |

### P2 — Minor

| 编号 | 维度 | 问题 |
|------|------|------|
| M3-1 | 三 | `git checkout -- .` 回滚粒度过粗 |
| M4-3 | 四 | mock-event-emitter.js 可能泄入 dist |
| Minor x6 | 二 | ERE \1 可移植性、Rust/Go 断言未覆盖、旧脚本残留等 |
| Minor x7 | 五 | 非原子更新、截断边界、ErrorBoundary 异步、轮询状态等 |

---

## 六、架构亮点（值得保持的设计）

| 设计 | 评价 |
|------|------|
| **三层门禁联防** (L1 blockedBy + L2 Hook + L3 AI Gate) | 纵深防御典范，任一层阻断即阻断 |
| **路由矩阵生成→消费闭环** | Phase 1 生成 routing_overrides → L2 Hook 在 Phase 4 动态调整阈值 |
| **反合理化引擎** | 29 条加权模式 + 三级计分 + 仅在 Phase 4/5/6 ok/warning 时触发 |
| **Checkpoint 原子写入** | Write → .tmp → validate → atomic mv → final verify |
| **decisionAcked 竞态处理** | lastAckedBlockSequence 精确追踪 + 自动重置 |
| **VirtualTerminal 增量渲染** | lastRenderedSequence ref + 仅新事件 write |
| **flock 子 shell 锁模式** | 子 shell 退出自动释放，避免手动 unlock 遗漏 |
| **并行配置按需加载** | parallel-phase*.md 拆分，各 Phase 仅加载本阶段文件 |

---

## 七、修复路线图建议

```
v5.1.2-rc1 → 修复 4 个 P0 Critical → v5.1.2-rc2 → 修复 P1 Major → v5.1.2 GA
                                          ↓
                                    回归测试全量通过
                                          ↓
                                    P2 Minor → v5.1.3 维护版本
```

**预计修复工作量**:
- P0 (4 项): 新建 1 个脚本 + 修改 3 个文件中各 5-15 行
- P1 (9 项): 涉及 6 个文件的中等规模修改
- P2 (14 项): 低优先级，可在后续版本迭代

---

> **审计官签章**: 本报告基于对 `plugins/spec-autopilot/` 目录下全部 `.sh`、`.py`、`.ts`、`.tsx` 源码的逐文件逐行审查，所有结论均附源码证据（文件名:行号）。未发现审计盲区。
>
> **下次审计建议**: 修复 P0 后执行针对性回归审计，重点验证 `tdd-refactor-rollback.sh` 的 L2 确定性、`broadcastNewEvents` 的容错性、`GateBlockCard` 的用户反馈。
