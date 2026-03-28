# spec-autopilot 二次复核遗漏问题修复计划（Round 3）

日期: 2026-03-29
范围: `plugins/spec-autopilot`
基线:

- `docs/plans/2026-03-29/2026-03-29-spec-autopilot-remediation-gap-fix-plan.zh.md`
- follow-up 修复提交 `f2b6573`

## 1. 本轮复核结论

二次修复后，大部分显式缺口已收口，但仍有 3 个问题不能判定为“完全修复”：

1. Agent 治理关联仍缺少 `session_id` 维度，跨 session 可误命中过期 dispatch record。
2. GUI/Server 对 `state-snapshot.json` / `archive-readiness.json` 的闭环只覆盖“首次快照读取”，未覆盖“已连接客户端的增量刷新”。
3. 英文 README 仍残留 “User-confirmed Archive” 的旧语义，与 v6.0 自动归档协议冲突。

## 2. 问题 A: Agent dispatch record 仍会跨 session 串用

### 2.1 现状

当前 validator 通过 marker 解析当前 `agent_id`，再用 `agent_id + phase` 命中最新 dispatch record：

- [`_post_task_validator.py`#L766](/Users/lorain/Coding/Huihao/claude-autopilot/plugins/spec-autopilot/runtime/scripts/_post_task_validator.py#L766)
- [`_post_task_validator.py`#L828](/Users/lorain/Coding/Huihao/claude-autopilot/plugins/spec-autopilot/runtime/scripts/_post_task_validator.py#L828)
- [`_post_task_validator.py`#L869](/Users/lorain/Coding/Huihao/claude-autopilot/plugins/spec-autopilot/runtime/scripts/_post_task_validator.py#L869)

但 dispatch record 写入时并没有把 `session_id` 持久化到 record 中：

- [`auto-emit-agent-dispatch.sh`#L244](/Users/lorain/Coding/Huihao/claude-autopilot/plugins/spec-autopilot/runtime/scripts/auto-emit-agent-dispatch.sh#L244)
- [`auto-emit-agent-dispatch.sh`#L252](/Users/lorain/Coding/Huihao/claude-autopilot/plugins/spec-autopilot/runtime/scripts/auto-emit-agent-dispatch.sh#L252)

因此只要新 session 使用了相同的 `agent_id`（这是稳定 slug，完全可能复用），validator 就会错误复用旧 session 的 dispatch record。

### 2.2 已复现

复现实验：

1. 构造 lock file，当前 session 为 `sess-new`。
2. 构造 `logs/.active-agent-session-sess-new`，内容为 `phase5-backend-impl`。
3. 构造 `agent-dispatch-record.json`，仅保留旧 session 的 `phase5-backend-impl` record。
4. 运行 `_post_task_validator.py`。

实际结果：validator 放行，未触发 `governance correlation missing`。

这说明当前实现并未满足 gap-fix plan 中“`agent_id + phase + session` 精确命中”的完成定义。

### 2.3 必须修复

1. `auto-emit-agent-dispatch.sh` 写 record 时增加 `session_id`。
2. 如有 `session_key` 或 `change_name`，建议一并写入，便于审计与清理。
3. `_post_task_validator.py` 匹配规则升级为 `session_id + agent_id + phase`。
4. 若当前 marker 可解析到 `session_id`，但 record 中无同 session 命中，必须 fail-closed block。
5. `phase-only` 回退仅允许用于“无 session / 无 marker 的旧兼容路径”，不能覆盖已知 session 场景。

### 2.4 补测要求

新增或扩展测试：

1. `test_agent_boundary_parallel.sh`
   - 当前 session marker 指向 `sess-new`
   - record 中只有 `sess-old` 同 agent_id 同 phase
   - 预期必须 block，reason 包含 `governance correlation missing`
2. `test_agent_priority_enforcement.sh`
   - dispatch record 文件必须断言存在 `session_id`

## 3. 问题 B: GUI 已连接客户端拿不到 meta-only 更新

### 3.1 现状

`snapshot-builder.ts` 已能读取 `state-snapshot.json` / `archive-readiness.json`，`/api/info` 和 WS 初始快照也会暴露这些字段：

- [`snapshot-builder.ts`#L85](/Users/lorain/Coding/Huihao/claude-autopilot/plugins/spec-autopilot/runtime/server/src/snapshot/snapshot-builder.ts#L85)
- [`routes.ts`#L74](/Users/lorain/Coding/Huihao/claude-autopilot/plugins/spec-autopilot/runtime/server/src/api/routes.ts#L74)
- [`ws-server.ts`#L34](/Users/lorain/Coding/Huihao/claude-autopilot/plugins/spec-autopilot/runtime/server/src/ws/ws-server.ts#L34)
- [`broadcaster.ts`#L9](/Users/lorain/Coding/Huihao/claude-autopilot/plugins/spec-autopilot/runtime/server/src/ws/broadcaster.ts#L9)

但刷新循环只有两种广播路径：

1. `forceSnapshot` 时发送完整 snapshot
2. 有新增 event 时只发送 `event`

见：

- [`bootstrap.ts`#L74](/Users/lorain/Coding/Huihao/claude-autopilot/plugins/spec-autopilot/runtime/server/src/bootstrap.ts#L74)
- [`bootstrap.ts`#L79](/Users/lorain/Coding/Huihao/claude-autopilot/plugins/spec-autopilot/runtime/server/src/bootstrap.ts#L79)
- [`bootstrap.ts`#L84](/Users/lorain/Coding/Huihao/claude-autopilot/plugins/spec-autopilot/runtime/server/src/bootstrap.ts#L84)

如果只有 `state-snapshot.json` / `archive-readiness.json` 变化，没有新增 event：

1. `snapshotState` 会在轮询中更新
2. `/api/info` 会返回新值
3. 已连接 GUI 不会收到新的 WS `snapshot`

### 3.2 已复现

复现实验结果：

1. WS 初始消息只有 1 条 `snapshot`
2. 修改 `archive-readiness.json` 与 `state-snapshot.json`
3. 2.5 秒后 `/api/info` 已反映新值：
   - `archiveReadiness.overall = ready`
   - `requirementPacketHash = hash-new`
   - `gateFrontier = 7`
4. 同一连接未收到任何 follow-up `snapshot`

这意味着 H 当前只修到了“首次打开 GUI 能读到值”，没有修到“运行中的 GUI 观察到真实状态变更”。

### 3.3 根因

1. `refreshSnapshot()` 只用 `event_id` 比较新增事件，没有比较 meta 是否变化。
2. `watch(CHANGES_DIR, { recursive: false })` 也无法可靠覆盖 `openspec/changes/<change>/context/*.json` 的深层文件更新。

### 3.4 必须修复

优先采用以下主方案：

1. 在 `refreshSnapshot()` 中比较上一版与当前版的 snapshot meta：
   - `archiveReadiness`
   - `requirementPacketHash`
   - `gateFrontier`
2. 若 meta 变化，即使 `added.length === 0`，也必须 `broadcastSnapshot(next.events)`。
3. 将该逻辑视为 server 主链路，不依赖用户手动刷新或重连。

建议同时补强：

1. 将 `watch(CHANGES_DIR, { recursive: false })` 调整为能覆盖 change context 文件的刷新策略。
2. 或直接在 `LOGS_DIR` / `CHANGES_DIR` 轮询逻辑中加入 meta 变更检测，避免依赖平台差异化 fs watch 语义。

### 3.5 补测要求

新增真实集成测试，不接受 grep：

1. 启动 server
2. 建立 WS 连接
3. 初始 snapshot 读取旧值
4. 只修改 `state-snapshot.json` / `archive-readiness.json`，不追加 event
5. 断言同一 WS 连接收到第二条 `snapshot`
6. 断言新的 meta 值进入 GUI 可消费字段

建议文件名：

- `plugins/spec-autopilot/tests/test_gui_snapshot_meta_refresh.sh`

## 4. 问题 C: README 英文文档仍残留旧归档语义

英文 README 的架构图仍写着：

- [`README.md`#L40](/Users/lorain/Coding/Huihao/claude-autopilot/plugins/spec-autopilot/README.md#L40)

内容为 `User-confirmed Archive`，与当前 v6.0 “archive readiness 通过后自动归档，失败才阻断”的协议不一致。

### 必须修复

1. 将 README 英文架构图改为与中文 README 一致的自动归档语义。
2. 对 README / README.zh / Phase 7 文档做一次统一 grep，禁止再出现“必须人工归档确认”的旧表述。

## 5. 建议执行顺序

1. 先修问题 A
   - 这是治理 fail-closed 正确性的硬问题
2. 再修问题 B
   - 这是 orchestration-first 是否真实可观测的闭环问题
3. 最后修问题 C
   - 文档收口，不阻塞实现，但必须在宣称完成前清掉

## 6. 最终验收标准

只有以下全部满足，才可宣称二次 follow-up 全部收口：

1. dispatch correlation 按 `session_id + agent_id + phase` 精确匹配
2. 跨 session 复用相同 agent_id 时，旧 record 不会被误命中
3. 已连接 GUI 在无新增 event 的情况下，仍能收到 snapshot meta 更新
4. `/api/info` 与 WS snapshot 对 `archiveReadiness` / `requirementPacketHash` / `gateFrontier` 一致
5. README 中英文文档不再残留 “User-confirmed Archive” 旧语义

## 7. 拒收条件

出现以下任一项即拒收：

1. 仅给 dispatch record 加 `session_id` 字段，但 validator 仍不按 session 匹配
2. 仅增加 `/api/info` 或首次连接快照，不修复已连接 GUI 的增量刷新
3. 用“重连 GUI 后能看到”替代实时闭环
4. 只补 grep 测试，不补真实 server + WS 集成测试
5. README 英文文档继续保留旧归档语义
