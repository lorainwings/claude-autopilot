# spec-autopilot 修复设计方案

> 日期：2026-03-19
> 范围：仅针对当前 `spec-autopilot` 插件进行问题修复、稳定性治理、目录规范化和发布治理。
> 原则：不将当前插件重构为新平台，不承载下一代并行 AI 平台的全部野心；当前插件以“稳定、可维护、可发布”为第一目标。

## 1. 文档目标

本文档用于回答三个问题：

1. 当前 `spec-autopilot` 的核心问题是什么。
2. 应该如何在不推倒重来的前提下完成修复。
3. 修复后的插件如何继续纳入当前插件市场统一发布。

本方案明确区分：

- `spec-autopilot`：现有规范驱动交付插件，继续维护。
- 新并行 AI 平台插件：另起一个新插件，不替换当前插件。
- `lorainwings-plugins`：统一插件市场，承载两者共存。

## 2. 当前问题总览

### 2.1 架构层问题

当前插件已经形成较完整的方法流与门禁体系，但在工程实现层暴露出以下结构性问题：

- 控制面过重：`server/autopilot-server.ts` 为单文件控制塔，承担 HTTP、WS、日志聚合、快照、决策写回、静态资源服务等职责。
- 目录边界混乱：源码、构建产物、运行日志、发布包、GUI 构建产物并存于同一仓库主路径。
- 分发结构与源码结构不一致：`server/autopilot-server.ts` 被回填到 `dist/scripts/`，说明运行时布局并非源码布局的自然投影。
- 脚本数量大但分类弱：`scripts/` 已成为运行时内核，但命名和目录组织仍停留在历史堆叠阶段。

### 2.2 稳定性问题

本地审阅与测试显示：

- `test_autopilot_server_aggregation.sh` 当前存在失败，说明 session 切换和 `raw-tail` 能力已经出现回归。
- 快照刷新依赖全量扫描与定时轮询，长会话下存在性能退化风险。
- 状态一致性、事件增量处理、跨 session 视图隔离仍然脆弱。
- API 脱敏和本地控制面安全仍是基础实现，尚未形成系统治理。

### 2.3 产品边界问题

当前插件的目标已经膨胀：

- 既想做规范驱动流水线
- 又想做多 Agent 并行
- 又想做 GUI 可观测性平台
- 又想做事件总线
- 又想做恢复系统

这会导致 `spec-autopilot` 的职责持续变宽，最终不可维护。

因此，本方案明确：

- `spec-autopilot` 继续做“规范驱动交付编排插件”
- 不承担“下一代并行 AI 平台”的全部职责

## 3. 目标与非目标

### 3.1 目标

- 修复已知 P0/P1 稳定性问题。
- 清理目录边界与运行时分层。
- 拆分 server 控制面，降低单点复杂度。
- 强化测试、schema、增量读取和发布治理。
- 保持用户已有使用方式基本兼容。
- 继续通过当前插件市场发布。

### 3.2 非目标

- 不在本次修复中把 `spec-autopilot` 改造成通用多 Agent 平台。
- 不在本次修复中引入大规模新能力矩阵，如模型智能路由、完整 DAG 调度器、CI 自愈 swarm。
- 不打破已有插件名、安装方式与市场路径。

## 4. 修复总体策略

修复策略分为四条主线并行推进：

1. 运行时稳定性止血
2. server 模块化拆分
3. 目录与打包规范化
4. 测试与发布治理强化

### 4.1 主线一：运行时稳定性止血

优先修复用户可见和测试已暴露的问题：

- 修复 session 切换后的快照刷新与广播逻辑
- 修复 `/api/raw-tail` 增量游标与尾部读取行为
- 修复事件增量广播在异常行、损坏行、空 chunk 下的鲁棒性
- 修复跨 session journal 与内存快照同步逻辑

### 4.2 主线二：server 模块化拆分

当前 `autopilot-server.ts` 应拆分为以下模块：

```text
plugins/spec-autopilot/server/
  src/
    bootstrap.ts
    config.ts
    types.ts
    ingest/
      legacy-events.ts
      hook-events.ts
      status-events.ts
      transcript-events.ts
    snapshot/
      snapshot-builder.ts
      phase-lookup.ts
      journal-writer.ts
    session/
      session-context.ts
      file-cache.ts
    api/
      info-route.ts
      events-route.ts
      raw-route.ts
      raw-tail-route.ts
    ws/
      broadcaster.ts
      ws-server.ts
    decision/
      decision-service.ts
    security/
      sanitize.ts
```

拆分原则：

- 路由与业务逻辑分离
- 文件读取与事件归一化分离
- session 状态与广播状态分离
- 决策写回单独隔离
- 脱敏逻辑单独封装

### 4.3 主线三：目录与打包规范化

当前插件目录需要调整，但不做大搬家式破坏。建议采用渐进式重组。

目标结构：

```text
plugins/spec-autopilot/
  .claude-plugin/
  docs/
  hooks/
  runtime/
    scripts/
    server/
  gui/
  skills/
  tests/
  tools/
```

其中：

- `runtime/scripts/`：保留 shell/python 运行脚本
- `runtime/server/`：承载 server 源码与运行时入口
- `gui/`：只保留 GUI 源码
- `gui-dist/`：逐步迁移为构建产物目录，不再作为源码层常驻核心目录

发布产物结构建议：

```text
dist/spec-autopilot/
  .claude-plugin/
  hooks/
  runtime/
    scripts/
    server/
  assets/
    gui/
  skills/
  CLAUDE.md
```

关键变化：

- 取消 `server/autopilot-server.ts -> dist/scripts/autopilot-server.ts` 的回填模式
- GUI 发布目录从 `gui-dist` 收敛到 `assets/gui`
- 明确 `runtime` 才是发布包中的执行层

### 4.4 主线四：测试与发布治理强化

测试必须从“脚本存在性和语法可用”升级到“状态一致性和负载场景可验证”。

新增测试方向：

- 多 session 切换一致性测试
- 长日志 raw-tail 游标测试
- 脏数据 / 损坏 JSON 行容错测试
- GUI reconnect 测试
- decision 写回幂等测试
- journal 与 snapshot 一致性测试
- server 启动时缺目录 / 缺文件降级测试

发布治理要求：

- 每次发版必须运行 server 聚合测试、dist 构建测试、关键 smoke 套件
- 发布包结构由 manifest 驱动，不允许手工回填例外继续增加
- 引入发布验收 checklist

## 5. 详细设计

### 5.1 Session 与 Snapshot 设计

当前问题：

- `snapshotState` 同时承担内存视图、广播基准、session 判定
- `refreshSnapshot()` 同时做构建、diff、session 切换广播

调整方案：

- 新增 `SessionStateStore`
- 新增 `SnapshotBuilder`
- 新增 `SnapshotDiffEngine`

职责划分：

- `SessionStateStore`
  - 保存当前 sessionId、sessionKey、changeName、mode
  - 保存最新快照元数据
  - 提供原子切换接口

- `SnapshotBuilder`
  - 从文件系统读取原始数据
  - 构建标准化事件序列
  - 生成不可变快照

- `SnapshotDiffEngine`
  - 比较前后快照
  - 识别 session 变化、事件新增、快照重置
  - 输出广播动作

这样可以避免当前 `refreshSnapshot()` 过度集中。

### 5.2 增量读取设计

当前问题：

- 周期性全量读文件
- 通过文件修改时间缓存 JSONL 内容，但切换 session 和 partial read 时粒度不够

目标方案：

- legacy/hook/statusline/transcript 都支持基于偏移量或行游标的增量读取
- 每类流维护独立 cursor
- session 切换时重置对应 cursor

引入：

- `FileCursorStore`
- `TailReader`

能力：

- 按字节偏移读取
- 保留不完整尾行直到下一次拼接
- 在损坏行时跳过并记录 error metric

### 5.3 API 设计调整

保留现有接口名，减少前端破坏：

- `GET /api/info`
- `GET /api/events`
- `GET /api/raw`
- `GET /api/raw-tail`

但增加内部 schema 约束：

- `RawTailResponse`
- `EventsResponse`
- `InfoResponse`
- `DecisionRequest`

同时增加：

- `GET /api/health`
- `GET /api/metrics`

其中 `metrics` 可先暴露：

- active_session_id
- total_events
- snapshot_rebuild_count
- raw_tail_errors
- malformed_line_count
- ws_client_count

### 5.4 安全与脱敏设计

当前脱敏仅覆盖少量场景，建议升级为三层：

1. 路径脱敏
2. 凭据字段脱敏
3. 文本体启发式脱敏

扩展规则：

- 支持 Windows 路径脱敏
- 扩展敏感字段字典
- 对疑似 token、Bearer、API key 进行模式掩码

同时要求：

- `decision` 消息必须经过 schema 校验
- 非法 action 一律拒绝
- phase 必须在允许范围内

### 5.5 脚本层治理设计

当前 `scripts/` 语义混杂，建议先做分类迁移，不急于一次性改路径。

目标分类：

```text
runtime/scripts/
  hooks/
  validators/
  emitters/
  recovery/
  ops/
  compat/
```

示例归类：

- `emit-phase-event.sh` -> `emitters/`
- `validate-json-envelope.sh` -> `validators/`
- `recovery-decision.sh` -> `recovery/`
- `start-gui-server.sh` -> `ops/`

迁移策略：

- 第一阶段仅内部分类，不改 hooks 对外路径
- 第二阶段通过 shim 保持兼容
- 第三阶段统一更新 manifest

## 6. 里程碑与实施计划

### Milestone 1：稳定性止血

周期：1 到 2 周

交付项：

- 修复当前 server 聚合测试失败
- 增量读取实现第一版
- server 拆分为最少 5 个模块
- 新增回归测试

验收标准：

- `test_autopilot_server_aggregation.sh` 全绿
- server 关键用例通过
- 不破坏现有 GUI 基本使用

### Milestone 2：结构治理

周期：2 到 3 周

交付项：

- 引入 `runtime/` 分层
- 调整 dist 打包布局
- 去掉 server 回填模式
- 完成脚本分类迁移第一阶段

验收标准：

- `build-dist.sh` 保持通过
- 发布包结构清晰
- 现有安装方式兼容

### Milestone 3：发布治理强化

周期：1 周

交付项：

- 发布验收 checklist
- server smoke test 套件
- metrics 与 health 接口
- 文档同步更新

验收标准：

- 发版流程可重复
- 关键回归能在 CI 被提前拦截

## 7. 对用户与市场的影响

### 7.1 对现有用户

不应带来安装方式变化：

```bash
claude plugin install spec-autopilot@lorainwings-plugins --scope project
```

对用户的可见变化应仅包括：

- GUI 更稳定
- session 切换更可靠
- 日志与原始流查看更可靠
- 发布质量更高

### 7.2 对插件市场

当前市场文件 [marketplace.json](.claude-plugin/marketplace.json) 继续保留 `spec-autopilot`。

本插件在市场中的定位保持不变：

- 名称：`spec-autopilot`
- 分类：`development`
- 定位：规范驱动交付流水线插件

## 8. 风险与规避

### 风险一：修复过程中引入大规模路径变更

规避：

- 先模块拆分，再目录迁移
- 对外路径兼容优先

### 风险二：server 拆分导致 GUI 接口变化

规避：

- 保持现有 API 路径稳定
- 增量替换内部实现

### 风险三：发布包结构调整影响安装

规避：

- 先引入新 dist 结构，再保留兼容映射一版
- 用 build-dist 测试与 smoke test 双重验证

## 9. 最终结论

`spec-autopilot` 不应该继续承担“下一代并行 AI 平台”的全部目标。它应该被修好、稳住、规范化，并继续作为插件市场中的成熟交付编排插件存在。

这个插件的修复方向不是推翻，而是收敛：

- 收敛职责
- 收敛目录
- 收敛控制面复杂度
- 收敛发布边界

修复完成后，它将成为市场中的稳定产品线之一，为新一代并行 AI 平台插件让出产品边界，而不是被替换。
