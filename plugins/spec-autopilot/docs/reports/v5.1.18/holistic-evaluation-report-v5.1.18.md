# spec-autopilot v5.1.18 全维度工业级仿真评测报告

> 评测日期: 2026-03-17
> 评测版本: v5.1.18
> 评测范围: Skills 编排 / Hook 与恢复链路 / GUI 控制台 / 构建分发 / 测试体系 / 竞品位势
> 评测基线:
> - `bash plugins/spec-autopilot/tests/run_all.sh`
> - `cd plugins/spec-autopilot/gui && pnpm build`
> - `bash plugins/spec-autopilot/scripts/build-dist.sh`

---

## 执行摘要

### 总评分: **86 / 100**

| 维度 | 评分 | 结论 |
|------|------|------|
| 全生命周期编排与 Skills 合理性 | **90/100** | 架构边界清晰，恢复链和模式路由成熟 |
| 效能、资源与并行性指标 | **82/100** | 并行协议扎实，但 GUI chunk 与状态保留策略仍偏重 |
| 代码生成质量与 TDD 引擎 | **88/100** | L2 Hook 强约束很强，TDD 隔离度高 |
| GUI 控制台完整性与鲁棒性 | **83/100** | 交互主路径可用，长会话和安全边界仍有缺口 |
| DX 与工程成熟度 | **80/100** | 测试规模大，但存在假绿风险与分发缺件 |
| 竞品多维降维打击对比 | **93/100** | 流程可视化、TDD 强约束、恢复协议构成明显护城河 |

### 一句话结论

`spec-autopilot` 已经具备成熟工程插件的主骨架，尤其在三层门禁、模式路由、崩溃恢复、TDD 铁律和 GUI 事件总线方面形成了体系化优势；但当前版本仍存在 3 个高优先级静默盲点: `Phase 7` 分发态缺件、测试套件假绿、以及 Gate override 约束只写在文档里没有落实到脚本层。

### 本次量化结果

| 指标 | 结果 |
|------|------|
| 插件版本 | `5.1.18` |
| Skills 数量 | `7` |
| 核心 Skill 文档总行数 | `1259` |
| Shell 脚本总行数 | `6290` |
| 测试脚本总行数 | `5857` |
| 文档文件数 | `115` |
| 测试文件数 | `65` |
| 官方测试汇总 | `599 passed / 0 failed` |
| 真实发现 | 至少 `1` 个日志级 FAIL 被测试框架吞掉 |
| GUI 构建结果 | `1691 modules transformed`, 主 JS `530.92 kB` |
| `gui-dist/` 体积 | `700K` |
| 发布包体积 | `1.4M` |
| 源码目录体积 | `327M` |
| 其中 node_modules | `gui/node_modules 294M` + `scripts/node_modules 29M` |

---

## 关键发现

### P0: 发布包缺少 `collect-metrics.sh`，但 Phase 7 明确依赖它

- `autopilot-phase7/SKILL.md` 要求在 Step 1 执行 `bash ${CLAUDE_PLUGIN_ROOT}/scripts/collect-metrics.sh`
- `build-dist.sh` 却把 `collect-metrics.sh` 列入 `EXCLUDE_SCRIPTS`
- `dist/spec-autopilot/scripts/` 实际确实没有该文件

**影响**:
- 源码态可运行，分发态在 Phase 7 汇总阶段有高概率直接掉功能
- 这是典型“开发环境绿、终端用户运行时红”的分发完整性缺陷

**结论**: 这是当前版本最严重的工程缺口之一。

### P0: 测试总 runner 存在“假绿”窗口，失败日志可被汇总吞掉

- `tests/run_all.sh` 只在测试脚本退出非 `0` 时统计 `FAIL:` 数
- `tests/test_clean_phase_artifacts.sh` 第 14 组用例在子 shell 内修改 `FAIL`，外层计数拿不到
- 本次真实执行中出现 `FAIL: 14b. stash_restored (got 'False')`，但最终仍汇总为 `27 passed, 0 failed`

**影响**:
- CI/本地回归可能把真实失败当通过
- 文档中“工业级全量评测”的可信度被直接折损

**结论**: 测试规模虽大，但当前测试框架的信号完整性不足。

### P1: Gate override 禁令只存在于文档，脚本层未强制执行

- `autopilot-gate/SKILL.md` 明确写了 `override` 不能用于 `Phase 4→5` 和 `Phase 5→6`
- `poll-gate-decision.sh` 仅校验 action 是否属于 `override|retry|fix`，没有按 phase / blocked_step 拒绝 override
- `GateBlockCard` 也对所有 gate_block 一律展示 Override 按钮

**影响**:
- 测试质量底线理论上可被 GUI 人工绕过
- “L2/L3 强约束”在最关键的测试门禁上存在执行层空洞

**结论**: 这是规约落地不闭环，而不是 UI 小瑕疵。

### P1: 指标采集脚本按文件名字典序取 checkpoint，不按最新时间取

- `collect-metrics.sh` 使用 `sorted(glob.glob(...))` 后取 `files[-1]`
- 这依赖文件名排序，而非 `mtime`
- 当同 phase 存在多份 checkpoint、补写、回滚或命名差异时，指标可能读到旧文件

**影响**:
- Phase 7 总结耗时、重试数、阶段状态都可能失真
- 该问题平时不易暴露，属于典型静默数据污染

### P2: GUI 事件池对 critical 事件不设上限，长会话会突破“1000 条上限”承诺

- store 的 `addEvents()` 对 regular 事件做预算截断
- `phase_start/end`、`gate_*`、`agent_dispatch/complete` 被认定为 critical，永久保留
- 所以真实上限并不是 1000，而是 `critical + cappedRegular`

**影响**:
- 长会话、多 agent、大量 gate 往返时，事件数组会持续增长
- `filter/findLast/sort` 型 selector 的 CPU 开销会随会话时长上升

---

## 维度一: 全生命周期编排与 Skills 合理性

评分: **90/100**

### 优势

- `autopilot` / `autopilot-dispatch` / `autopilot-gate` / `autopilot-recovery` 的职责边界清晰，分工符合主线程编排 + 子 Agent 调度模型。
- Full / Lite / Minimal 三种模式路由明晰，恢复协议显式感知 mode，并优先使用 lockfile mode，减少跨会话模式漂移。
- `check-predecessor-checkpoint.sh` 的阶段前驱门禁实现了 mode-aware 路由和 TDD 分支，具备较高确定性。
- `recovery-decision.sh` 已经从“脚本拼接判断”提升到“纯只读 JSON 决策器”，工程成熟度明显高于普通 agent-style 流程文档。

### 风险

- 主编排 Skill 文档体量已经很大: `autopilot 345 行`、`dispatch 324 行`、`gate 370 行`、`recovery 220 行`。如果未来继续把边界规则堆进主 Skill，认知负担会继续升高。
- Gate 的文档规约和脚本实现出现了偏差，说明“文档即协议”还没有完全变成“代码即协议”。

### 量化预估

| 指标 | 估值 |
|------|------|
| 编排链路完整度 | `90%+` |
| 恢复决策确定性 | `高` |
| Skill 职责耦合风险 | `中低` |
| 规约与实现偏差风险 | `中` |

---

## 维度二: 效能、资源与并行性指标

评分: **82/100**

### 优势

- 测试和文档都清晰强调“同一条消息并发派发多个后台 Task”，并行模型不是口号。
- GUI 服务端使用 `lastByteOffset` 做增量读取，较老版本按行数重扫有明显提升。
- `build-dist.sh` 的白名单打包策略有效，最终发布包仅 `1.4M`，明显优于源码态 `327M`。

### 证据

- GUI 构建成功，耗时约 `3.5s~3.8s`
- `gui-dist` 主 JS chunk 为 `530.92 kB`，Vite 已出现 chunk 过大警告
- 发布包没有带入 `docs/`、`tests/`、`gui/` 源码目录

### 风险

- GUI 主 chunk 超过 `500 kB`，初次加载、低配机热更新和长时间 DevTools 分析体验会受影响。
- 源码目录中直接包含 `323M` 的 node_modules，虽不污染 dist，但严重拉低源码态审计效率、仓库搬运成本和 IDE 索引体验。
- GUI 事件 store 的 critical 事件永久保留，使长会话性能曲线更接近线性增长而非固定上界。

### 量化预估

| 指标 | 估值 |
|------|------|
| 并行加速收益 | `2.5x ~ 5x`，取决于 Phase 4/5/6 并发度 |
| 事件总线 I/O 设计 | `良好` |
| GUI 首屏包体风险 | `中高` |
| 长会话状态增长风险 | `中` |

---

## 维度三: 代码生成质量与 TDD 引擎

评分: **88/100**

### 优势

- `unified-write-edit-check.sh` 将状态隔离、TDD 阶段隔离、TODO/FIXME/HACK 拦截、恒真断言拦截、代码约束统一到一个入口，成本和约束性都做了平衡。
- `.tdd-stage` 与 `.tdd-refactor-files` 的物理隔离设计是本插件最有差异化价值的能力之一。
- `test_tdd_isolation.sh`、`test_tdd_rollback.sh`、`test_unified_write_edit.sh` 等回归覆盖到关键 TDD 纪律。
- `code_constraints`、`change_coverage`、`test_pyramid` 等底线都有脚本级验证，而不是靠模型“自觉”。

### 风险

- TDD 与代码约束的强度主要体现在源码态和 Hook 态，若用户通过文档不一致的 override 通道进入后续阶段，质量底线会被间接削弱。
- `collect-metrics.sh` 的 checkpoint 读取问题会污染 Phase 7 对 TDD/阶段效果的回顾数据。

### 量化预估

| 指标 | 估值 |
|------|------|
| RED/GREEN 物理隔离度 | `高` |
| Hook 级质量拦截确定性 | `高` |
| TDD 恢复细粒度 | `高` |
| 汇总指标可信度 | `中` |

---

## 维度四: GUI 控制台完整性与鲁棒性

评分: **83/100**

### 优势

- `autopilot-server.ts` 已具备 snapshot + 增量事件 + reset 信号 + decision_ack 广播，主链路可用。
- `GateBlockCard` 对断连、请求失败、超时给出了明确 UI 反馈，不是静默失败。
- store 已修复同 phase 多次 start/end 的时间计算问题，恢复场景鲁棒性优于早期版本。

### 风险

- Override 按钮未按 phase 风险等级做条件性禁用。
- 事件池关键事件无限保留，与“高峰 100+ 事件/s 仍稳定”的目标之间还有实现差距。
- `VirtualTerminal`、`GateBlockCard`、`TelemetryDashboard` 仍包含多处基于全量 `events.filter()` 的派生逻辑，长会话 CPU 负担会逐渐上升。

### 量化预估

| 指标 | 估值 |
|------|------|
| GUI 交互正确性 | `中高` |
| WebSocket 恢复能力 | `高` |
| 长会话渲染稳定性 | `中` |
| 安全边界一致性 | `中低` |

---

## 维度五: DX 与工程成熟度

评分: **80/100**

### 优势

- 测试数量和覆盖面已经达到“工程产品”级别，不是 demo 量级。
- `build-dist.sh` 的隔离验证、脚本存在性验证、CLAUDE dev-only 剥离都体现出正式分发意识。
- 恢复、门禁、配置校验、构建、GUI 都有明确文档挂钩。

### 风险

- 测试信号存在假绿窗口，直接影响研发效能系统的可信度。
- 分发包缺少 Phase 7 依赖脚本，说明 release checklist 还没有把“运行时路径完整性”做成自动守卫。
- 源码目录包含海量依赖目录，给二次开发者造成不必要噪声。

### 量化预估

| 指标 | 估值 |
|------|------|
| OOBE 完整度 | `中高` |
| 分发纯净度 | `高` |
| 分发正确性 | `中低` |
| 测试可信度 | `中` |

---

## 维度六: 竞品多维降维打击对比

评分: **93/100**

### 相对 Cursor / Windsurf / Copilot Workspace / Bolt.new / v0.dev 的优势

1. `8` 阶段门禁流水线 + `L1/L2/L3` 三层约束，在“可验证流程化”这一维明显更深。
2. `TDD` 的 RED/GREEN/REFACTOR 硬隔离，比大多数竞品的“自由流式修改”更适合对质量底线敏感的团队。
3. `crash recovery + checkpoint + progress + context snapshot` 的组合拳，在长时任务续跑上有明显产品差异。
4. GUI 不只是日志窗，而是阶段、门禁、Agent、工具调用四层事件可视化。

### 劣势

1. 分发正确性和测试信号完整性仍不如成熟商业产品的 release discipline。
2. GUI 性能工程还没完全跟上其宏大协议设计。
3. 对用户错误操作的防呆边界还不够“硬”，尤其是 override 相关。

---

## 静默盲点清单

1. `Phase 7` 分发态依赖缺件: `collect-metrics.sh` 被打包脚本排除。
2. 测试框架假绿: 日志里已出现 `FAIL:`，但总 runner 仍输出全绿。
3. Override 禁令未落地: 文档禁止，脚本与 UI 未执行该禁令。
4. 指标脚本最新文件选择错误: 按字典序而非时间。
5. GUI 关键事件无上限保留: 会话越长，状态池越大。
6. 源码仓库噪声过大: 插件目录内嵌 `323M` 依赖目录，审计与协作成本偏高。

---

## 优先级建议

### 最高优先级

1. 修复 `build-dist.sh` 与 `autopilot-phase7` 的依赖不一致，把 `collect-metrics.sh` 纳入 runtime 包，或移除 Phase 7 对它的强依赖。
2. 修复 `test_clean_phase_artifacts.sh` 的子 shell 计数泄漏，并让 `tests/run_all.sh` 无论退出码如何都统计 `FAIL:` 行，避免假绿。
3. 在 `poll-gate-decision.sh` 和 GUI 层同时落实 override 禁令，至少对 `Phase 4→5`、`Phase 5→6` 做硬拒绝。

### 次优先级

1. 将 `collect-metrics.sh` 切换为按 `mtime` 选择最新 checkpoint。
2. 给 GUI 事件 store 增加真正的全局 hard cap 或分层索引缓存。
3. 拆分或懒加载主 JS chunk，压低 `530.92 kB` 的首包压力。

---

## 最终结论

`spec-autopilot v5.1.18` 已经不是“会跑流程的 skill 集合”，而是一个具备流程操作系统雏形的工程化插件。它最强的地方不在单个脚本，而在“协议 + Hook + 恢复 + GUI + 归档”这套全链路闭环。

但如果目标是“工业级仿真评测”这一级别，当前版本还必须先补上 3 个信号完整性问题: 分发包完整性、测试结果可信度、以及测试门禁不可绕过性。只要这三点补齐，整体成熟度可以稳定跨到 `90+` 区间。
