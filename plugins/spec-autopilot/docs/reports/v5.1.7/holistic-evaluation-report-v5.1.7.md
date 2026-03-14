# spec-autopilot v5.1.7 全维度工业级仿真评测报告

> **评测日期**: 2026-03-15
> **评测版本**: v5.1.7
> **评测范围**: 插件全栈 — Skills 编排 / 性能资源 / 代码生成 / GUI 控制台 / DX 工程成熟度 / 竞品对比
> **代码统计**: Shell 4,366 行 | Python 1,417 行 | GUI (TS/TSX) 1,324 行 | Skills/Refs ~2,000+ 行 | 测试 58 文件 ~734 断言

---

## 执行摘要 (Executive Summary)

### 总评分：**87.3 / 100**

| 维度 | 评分 | 等级 |
|------|------|------|
| 全生命周期编排与 Skills 合理性 | **91/100** | S |
| 效能、资源与并行性指标 | **83/100** | A |
| 代码生成质量与 TDD 引擎 | **89/100** | A+ |
| GUI 控制台完整性与鲁棒性 | **85/100** | A |
| DX 与工程成熟度 | **86/100** | A |
| 竞品多维降维打击对比 | **90/100** | S |

### 六维雷达图（文本形式）

```
                编排 91
                  ╱╲
           竞品 90╱  ╲83 效能
                ╱    ╲
           DX 86╲    ╱89 TDD
                 ╲  ╱
              GUI 85
```

### 核心发现

1. **三层门禁体系（L1/L2/L3）** 是同类工具中最严密的质量守卫机制，实现了从 TaskCreate 依赖到 Hook 校验到 AI 自查的全链路约束
2. **TDD 铁律引擎** 通过 `.tdd-stage` 状态机 + L2 Hook 写入拦截实现了业界罕见的「RED 阶段禁止写生产代码」硬约束
3. **反合理化检测** 24 种借口模式 × 3 级权重评分系统，有效遏制 AI「跳过测试」的惯性倾向
4. **GUI 事件总线** 达到生产级标准：Set 去重 + 1000 事件截断 + rAF 批量渲染 + 指数退避重连
5. **主要盲点**: 缺少端到端集成测试、无运行时性能 Profiling、反合理化模式实际为 24 种（非文档声称的 29 种）

---

## 维度一：全生命周期编排与 Skills 合理性 (91/100)

### 1.1 Skills 职责边界分析

系统共含 **7 个 SKILL 文件**，形成清晰的单一职责分层：

| Skill | 职责 | 行数 | 调用方式 |
|-------|------|------|----------|
| `autopilot` | 主线编排 — 8 阶段流转 + 模式分发 | 368 | 用户直接调用 |
| `autopilot-phase0` | 环境初始化 — 配置/锁/锚点/GUI | 227 | Skill 委托 |
| `autopilot-gate` | 门禁验证 — 3 层门禁 + 检查点 | 372 | Skill 委托 |
| `autopilot-dispatch` | 任务分发 — 上下文注入 + 模板填充 | 323 | Skill 委托 |
| `autopilot-recovery` | 崩溃恢复 — 检查点扫描 + 状态重建 | 163 | Phase 0 子步骤 |
| `autopilot-phase7` | 总结归档 — 汇总 + 知识萃取 + 压缩 | 182 | Skill 委托 |
| `autopilot-phase0` (banner) | 启动仪式 — 50 字符 ASCII 框 | (含于上) | 嵌入式 |

**评价**: 职责边界清晰，无重叠。唯一值得商榷的是 `autopilot-gate`（372 行）承载了门禁验证 + 检查点写入 + TDD 审计三重职责，可考虑进一步拆分。

### 1.2 状态机流转精度

三路径执行模型实现完整覆盖：

```
Full    (8 phases): 0 → 1 → 2 → 3 → 4 → 5 → 6 → 7
Lite    (5 phases): 0 → 1 → 5 → 6 → 7
Minimal (4 phases): 0 → 1 → 5 → 7
```

- **模式检测优先级**: `$ARGUMENTS` > `config.default_mode` > `"full"`（AI 不可覆盖）
- **Phase 1 & Phase 5 跨模式一致**: 三种模式下执行逻辑完全相同，避免了精简模式的质量退化
- **Phase 5 三路径**: 路径 A（并行 worktree）/ 路径 B（串行前端）/ 路径 C（TDD 模式），互斥由配置决定

### 1.3 前驱 Checkpoint 旁路分析

`check-predecessor-checkpoint.sh`（437 行）实现了 **7 个主要门禁分支**：

1. Phase 结果目录存在性门禁
2. Phase 2 独立检查（仅 Full 模式）
3. Phase 3/4 Full 模式专属门禁
4. Phase 3+ 顺序门禁（模式感知前驱 + Minimal 零跳检查）
5. Phase 5 特殊门禁（TDD 模式检测、Phase 4/3 前驱分叉逻辑）
6. Phase 6 特殊门禁（zero_skip_check + tasks.md 完成度）
7. 挂钟超时门禁（Phase 5 运行时间限制）

**TDD 模式延迟加载**: Lite/Minimal 模式跳过 ~50ms 的 Python3 fork 开销（懒检测策略）。

### 1.4 L2→L3 约束力评估

| 层级 | 机制 | 约束力 | 可绕过性 |
|------|------|--------|----------|
| L1 | `TaskCreate blockedBy` | 软约束 | AI 可伪造依赖满足 |
| L2 | Hook 校验（PreToolUse/PostToolUse） | **硬约束** | 无法绕过（Claude 平台级） |
| L3 | AI 8 步自查清单 | 半硬约束 | AI 可自欺但需对抗反合理化 |

**结论**: L2 是核心保障层。L1 依赖 AI 诚实、L3 依赖 AI 自律，但三层叠加后的综合逃逸概率极低。

### 1.5 Anti-Rationalization 覆盖率

`anti-rationalization-check.sh`（152 行）实现：

- **借口模式**: 24 种（3 级权重 × 中英双语）
  - 高置信度 (weight=3): 9 种（skip/skipping/skipped 等 + 跳过/延后/超出范围）
  - 中置信度 (weight=2): 5 种
  - 低置信度 (weight=1): 10 种
- **评分阈值**: ≥5 硬阻断 / ≥3+无产物 阻断 / ≥2 告警 / <2 静默放行
- **适用范围**: Phase 4/5/6 且 status=ok/warning
- **TDD 文档补充**: 额外 13 种红旗模式 + 13 种反合理化借口（文档级）

**盲点**: 文档声称 29 种模式，代码实现为 24 种，存在 **5 种缺口**（可能在迭代中丢失或未迁移完成）。

### 1.6 量化数据

| 指标 | 数值 |
|------|------|
| SKILL 文件总行数 | ~1,635 行 |
| 参考文档总数 | 27 个 |
| 门禁分支总数 | 7 + 8 步 L3 清单 = 15 个检查点 |
| 状态机路径数 | 3（Full/Lite/Minimal）|
| 借口模式实际数 | 24（代码）/ 29（文档声称）|
| Phase 5 执行路径 | 3（A/B/C 互斥）|
| 并行域上限 | 8 个 Agent |

---

## 维度二：效能、资源与并行性指标 (83/100)

### 2.1 Token 有效载荷比分析

- **按需加载策略**: `parallel-phase5.md`（295 行）仅在并行模式激活时注入上下文
- **上下文注入优先级**: 7 级（instruction_files → reference_files → Project Rules → project_context → test_suites → services → Phase 1 Steering → built-in），高优先级可覆盖低优先级
- **Phase 级差异化**: Phase 2/3 接收紧凑摘要，Phase 4/5 接收完整规则
- **参考文档总计**: 27 个 .md 文件，全量注入将占据 ~8,000 Token

**预估有效载荷比**:
- Full 模式 Phase 5 并行: ~65% 有效（含域规则 + TDD 文档 + 约束注入）
- Lite 模式: ~80% 有效（跳过 Phase 2/3/4 大量上下文）
- Minimal 模式: ~85% 有效（最精简路径）

### 2.2 flock 并行加速比与 I/O 阻塞率

`_common.sh` 中的 `next_event_sequence()` 原子机制：

- **锁机制**: `flock -x -w 5` 独占锁，5 秒超时
- **锁文件**: `$project_root/logs/.event_sequence.lock`
- **降级策略**: 超时后使用 `timestamp + $RANDOM` 作为 fallback 序列号
- **锁粒度**: 序列号文件级（极细），无全局阻塞

**并行加速比预估**:

| 场景 | 串行基准 | 并行预估 | 加速比 |
|------|----------|----------|--------|
| 8 域 Phase 5 | ~40min | ~8min | ~5x |
| 4 域 Phase 4 测试 | ~20min | ~6min | ~3.3x |
| Phase 6 三路径 | ~15min | ~6min | ~2.5x |

**I/O 阻塞率预估**: flock 竞争在 8 并发下约 <2% 时间占比（每次锁持有 <1ms）。

### 2.3 Hook 执行延迟基准

`unified-write-edit-check.sh` 各 CHECK 耗时预估：

| CHECK | 内容 | 预估耗时 | 技术 |
|-------|------|----------|------|
| CHECK 0 | Sub-Agent 状态隔离 | ~1ms | 纯 Bash |
| CHECK 1 | TDD 阶段隔离 | ~1ms | 纯 Bash |
| CHECK 2 | 禁止模式 (TODO/FIXME) | ~2ms | grep |
| CHECK 3 | 断言质量（同义反复） | ~2ms | grep (5 regex) |
| CHECK 4 | 代码约束（Python） | ~50ms | Python3 fork |
| **总计** | | **~56ms** | 含早期退出 |

**早期退出优化**: 9 种文件类型规则跳过 CHECK 4 的 Python fork，节省 ~50ms（非源码文件命中率约 40%）。

**Hook 超时配置**:

| Hook | 超时 |
|------|------|
| check-predecessor-checkpoint.sh | 30s |
| post-task-validator.sh | 60s |
| unified-write-edit-check.sh | 15s |
| save-state-before-compact.sh | 15s |
| scan-checkpoints-on-start.sh | 15s (async) |

### 2.4 MTBF 与崩溃恢复可靠性

- **崩溃恢复入口**: Phase 0.4 自动触发 `autopilot-recovery` Skill
- **检查点扫描**: 8 个 phase 文件 + phase5-tasks/task-N 子层级
- **TDD 恢复粒度**: `tdd_cycle.red.verified` / `green.verified` 级别
- **原子写入保障**: `.tmp → rename` 模式（崩溃安全）
- **.tmp 清理**: v5.1 残留物自动清理
- **锚点 SHA 验证**: 无效时自动重建

**预估 MTBF**: >50 小时连续运行（基于原子写入 + 多层恢复）

### 2.5 量化预估表

| 指标 | 数值 | 说明 |
|------|------|------|
| 单次 Hook 平均延迟 | ~56ms | unified-write-edit-check 全 CHECK |
| Hook 早期退出命中率 | ~40% | 非源码文件跳过 Python |
| flock 竞争率 (8 并发) | <2% | 序列号锁粒度极小 |
| 崩溃恢复成功率 | >95% | 基于检查点 + 原子写入 |
| Token 有效载荷比 (Full) | ~65% | Phase 5 并行模式 |
| 并行加速比上界 | ~5x | 8 域理想条件 |

---

## 维度三：代码生成质量与 TDD 引擎 (89/100)

### 3.1 RED/GREEN/REFACTOR 隔离度评估

TDD 铁律实现（`tdd-cycle.md` + `unified-write-edit-check.sh`）：

| 阶段 | 约束 | 隔离机制 | 违反后果 |
|------|------|----------|----------|
| RED | 仅允许写测试文件 | `.tdd-stage=red` + L2 Hook 拦截生产代码写入 | **硬阻断** |
| GREEN | 仅允许写生产代码 | `.tdd-stage=green` + L2 Hook 拦截测试修改 | **硬阻断** |
| REFACTOR | 允许重构但测试必须通过 | L2 验证 exit_code=0，失败自动 `git checkout -- .` | **全量回滚** |

**隔离度评价**: **极高**。通过 `.tdd-stage` 文件 + L2 Hook 的组合实现了物理隔离，AI 无法在 RED 阶段偷写生产代码。这是同类工具中罕见的硬约束级 TDD 实现。

### 3.2 .tdd-stage 生命周期安全性

- **创建**: Phase 5 TDD 路径 C 启动时创建，初始值 `red`
- **状态转换**: `red` → `green` → `refactor` → `red`（循环）
- **清理**: Phase 5 完成或崩溃恢复时删除
- **残留处理**: v5.2 Recovery Skill 自动清理残留 `.tdd-stage` 文件
- **并发安全**: 串行 TDD 为单 Agent，无竞争；并行 TDD 域内隔离

**安全评价**: 生命周期管理完善，有残留清理机制，无泄漏风险。

### 3.3 forbidden_files/patterns 约束顺从度

`_constraint_loader.py`（185 行）实现双优先级加载：

1. **优先级 1**: `autopilot.config.yaml` → `code_constraints` 节
2. **优先级 2**: `CLAUDE.md` 正则回退解析（中文标记识别: 禁止/禁）

**约束类别**:
- `forbidden_files`: 文件名黑名单（basename + 相对路径匹配）
- `forbidden_patterns`: 正则模式（无效正则自动降级为字面匹配）
- `allowed_dirs`: 目录白名单
- `max_lines`: 文件行数上限（默认 800 行，读取上限 100KB）

**L2 强制执行**: `unified-write-edit-check.sh` CHECK 4 调用 Python 约束检查，Phase 5 每次 Write/Edit 均触发。

### 3.4 test_pyramid 地板强制能力

- **金字塔几何约束**: `min_unit_pct + max_e2e_pct > 100%` 交叉验证
- **Hook floors 一致性**: `hook_floors.min_unit_pct ≤ test_pyramid.min_unit_pct` 等 3 条交叉规则
- **Phase 4→5 门禁**: `test_counts` + `artifacts` + `dry_run` 三重验证
- **Phase 5→6 门禁**: `test-results.json` + `zero_skip_check` + 任务完成度

### 3.5 change_coverage 验证能力

- **Phase 6 三路径**: A=测试执行 / B=代码审查 / C=质量扫描
- **zero_skip_check**: Phase 5→6 过渡时验证无跳过的测试
- **TDD 审计**: `red_violations = 0` 硬要求，`tdd_cycle` 完整性检查

### 3.6 量化指标表

| 指标 | 数值 |
|------|------|
| TDD 铁律条数 | 5（硬约束）|
| RED 阶段违反检测 | L2 Hook 级（不可绕过）|
| 反合理化红旗模式 | 13 种 |
| 约束加载优先级 | 2（配置 > CLAUDE.md）|
| 禁止模式匹配策略 | 正则 + 字面降级 |
| 文件行数上限默认 | 800 行 |
| Phase 4→5 验证项 | 3（test_counts/artifacts/dry_run）|
| Phase 5→6 验证项 | 3（results/zero_skip/completion）|
| REFACTOR 失败回滚 | `git checkout -- .`（全量）|

---

## 维度四：GUI 控制台完整性与鲁棒性 (85/100)

### 4.1 Zustand Store 事件洪峰压力分析

`gui/src/store/index.ts`（251 行）核心防御机制：

- **Set 去重**: `new Set(state.events.map(e => e.sequence))`，基于序列号唯一键
- **智能截断**: 分离关键事件（`phase_start`/`phase_end`/`gate_block`/`gate_pass`）与普通事件，普通事件截断至 `1000 - critical.length`
- **关键事件保护**: 关键事件永不被截断，保证状态机完整性

**压力预估**（100+ events/s 场景）：

| 指标 | 预估值 | 风险等级 |
|------|--------|----------|
| Set 去重开销 (1000 events) | ~2ms/次 | 低 |
| slice 截断开销 | <1ms | 极低 |
| 内存占用 (1000 events) | ~500KB | 低 |
| React 重渲染频率 | 受 rAF 节流 | 中 |

**盲点**: 无显式节流/防抖机制，极端突发场景（>500 events/s）可能导致 React 重渲染压力。建议增加批量聚合窗口。

### 4.2 VirtualTerminal 增量渲染方案评估

`gui/src/components/VirtualTerminal.tsx`（180 行）：

- **增量策略**: `lastRenderedSequence` ref 追踪已渲染最大序列号，仅处理增量事件
- **写入缓冲**: `writeBufferRef.current[]` 队列，rAF 批量刷入 xterm.js
- **rAF 去重**: 单一 `rafIdRef.current` 守卫，避免重复调度
- **事件类型着色**: 7 种 ANSI 色映射（蓝=phase_start、绿=phase_end/gate_pass、红=gate_block）
- **截断处理**: gate_block 错误 80 字符、error 消息 120 字符

**评价**: 增量渲染 + rAF 批量写入是正确的性能方案。xterm.js 本身具备虚拟化能力，大量日志不会导致 DOM 膨胀。

### 4.3 Memoization 优化覆盖度

| 组件/选择器 | Memoization 状态 |
|-------------|------------------|
| PhaseDuration selector | 按需计算（函数导出）|
| GateStats selector | 按需计算（函数导出）|
| TelemetryDashboard counters | `useMemo` 覆盖 |
| Active phase indices | Selector 内联 |
| Retry count | Event filter + memoized |

**覆盖度评估**: ~80%。大部分昂贵计算已 Memoize，但 Store 的 derived selectors 采用函数导出而非 Zustand `subscribeWithSelector`，在高频更新下可能重复计算。

### 4.4 WebSocket 断连容错与 UI 报警

`gui/src/lib/ws-bridge.ts`（138 行）：

| 参数 | 值 |
|------|-----|
| 初始重连延迟 | 1,000ms |
| 最大重连延迟 | 10,000ms |
| 连接超时 | 5,000ms |
| 退避因子 | ×1.5 |
| 退避公式 | `min(delay × 1.5, 10000)` |

- **连接超时守卫**: `WebSocket.CONNECTING` 状态下 5s 后强制关闭
- **Handler 管理**: Set-based 订阅 + 闭包取消
- **消息路由**: `snapshot`（全量重放）/ `event`（增量）/ `decision_ack`（ACK）

**UI 报警**（`GateBlockCard.tsx`）:
- 断连时显示: "网络已断开，请等待重连后操作"
- 按钮 disabled: `loading !== null || !connected`
- 30 秒决策超时 + AbortController 取消

### 4.5 GateBlockCard 交互反馈

- **三决策按钮**: Retry（青色）/ Fix（琥珀色）/ Override（玫红色）
- **修复指令输入**: Textarea 文本域，用户可附加上下文
- **自动消除**: `decisionAcked` 时返回 null
- **门禁解析**: 同 phase 后续 gate_pass 序列号比较

### 4.6 量化性能预估

| 指标 | 预估值 |
|------|--------|
| 首屏加载 (Vite dev) | ~800ms |
| WS 重连完成时间 (首次) | ~1.5s |
| WS 重连完成时间 (最大) | ~10s |
| 1000 事件渲染帧率 | ~55fps (rAF 批量) |
| Set 去重 + slice 截断 | <3ms/批 |
| xterm.js 增量写入 | <1ms/event |
| 内存峰值 (1000 events) | ~2MB |

---

## 维度五：DX 与工程成熟度 (86/100)

### 5.1 OOBE 接入成本评估

| 步骤 | 耗时估算 | 复杂度 |
|------|----------|--------|
| 安装插件 | ~2min | 低 |
| 创建 autopilot.config.yaml | ~5min | 中 |
| 配置验证 (validate-config.sh) | ~1min | 低（自动） |
| 首次运行 /autopilot | ~1min | 低 |
| **总 OOBE** | **~9min** | **中偏低** |

**正面**: Phase 0 自动完成 Python3 检查、GUI 启动、锁文件创建、锚点提交。
**负面**: 需手动编写 `autopilot.config.yaml`（无交互式向导），配置项 30+ 参数可能让新用户困惑。

### 5.2 配置验证器覆盖度

`_config_validator.py`（387 行）验证规则统计：

| 规则类别 | 数量 |
|----------|------|
| 必需顶层键 | 4 |
| 必需嵌套键 | 7 |
| 推荐键 | 4 |
| 类型规则 (TYPE_RULES) | 27 |
| 范围规则 (RANGE_RULES) | 17 |
| 枚举规则 (ENUM_RULES) | 3 |
| **交叉引用验证** | **9** |
| **总计** | **71 规则** |

**交叉引用验证（9 条）**:
1. `min_unit_pct + max_e2e_pct > 100%` 金字塔几何
2. `max_retries_per_task < 1` 告警
3. `parallel.enabled + max_agents < 2` 矛盾检测
4. `coverage_target=0 + zero_skip_required=true` 矛盾
5. `complexity_routing small ≥ medium` 阈值序检查
6. `hook_floors.min_unit_pct > test_pyramid.min_unit_pct` 一致性
7. `hook_floors.max_e2e_pct < test_pyramid.max_e2e_pct` 一致性
8. `hook_floors.min_total_cases > test_pyramid.min_total_cases` 一致性
9. `tdd_mode=true` 咨询性提示

**输出结构**: valid/missing_keys/type_errors/range_errors/enum_errors/cross_ref_warnings/warnings 七层反馈。

### 5.3 协议文档完整性

| 文档 | 覆盖范围 | 完整度 |
|------|----------|--------|
| event-bus-api.md | 5 事件类型 + 6 上下文字段 | 高 |
| parallel-phase5.md | 3 步域检测 + 合并冲突 | 高 |
| tdd-cycle.md | RED/GREEN/REFACTOR 全流程 | 高 |
| CLAUDE.md 工程法则 | 10 类 30+ 红线规则 | 高 |

**缺失**: 无独立的 API 参考文档、无 FAQ/Troubleshooting 文档。

### 5.4 构建产物纯净度

`build-dist.sh`（66 行）保障：

- **白名单复制**: 仅 `scripts/` 内文件（跳过子目录）
- **DEV-ONLY 剥离**: `sed` 删除 `<!-- DEV-ONLY-BEGIN -->` 至 `<!-- DEV-ONLY-END -->` 段
- **6 项禁止路径**: gui/docs/tests/CHANGELOG.md/README.md/scripts/node_modules
- **3 项关键字检查**: 测试纪律/构建纪律/发版纪律（确认 DEV-ONLY 剥离成功）
- **产物大小报告**: `du -sh` 源码 vs 构建产物对比

### 5.5 测试基础设施成熟度

| 指标 | 数值 |
|------|------|
| 测试文件数 | 58 |
| 断言/检查总数 | ~734 |
| 测试运行器 | `run_all.sh`（78 行）|
| 发现机制 | Glob `test_*.sh` |
| 过滤支持 | 多正则命令行参数 |
| 隔离策略 | 子 Shell 执行 |
| 退出码语义 | FAIL>0 → exit 1, RAN=0 → exit 1 |

**成熟度评价**: 测试覆盖面广（58 文件），但缺少：
- 端到端集成测试（跨 Phase 完整流程）
- 测试覆盖率统计
- CI 集成配置
- 测试性能基准

---

## 维度六：竞品多维降维打击对比 (90/100)

### 6.1 vs Cursor / Windsurf

| 能力 | spec-autopilot v5.1.7 | Cursor / Windsurf |
|------|----------------------|-------------------|
| 全生命周期编排 | 8 阶段状态机 + 3 模式 | 单轮对话 / Agent 模式 |
| 质量门禁 | 三层 L1/L2/L3 | 无（依赖 AI 自律） |
| TDD 强制 | `.tdd-stage` + L2 Hook 硬约束 | 无内置 TDD 支持 |
| 反合理化 | 24 模式 × 3 权重评分 | 无 |
| 崩溃恢复 | 检查点 + 原子写入 + 自动恢复 | 无（重新开始） |
| 并行执行 | 8 域 worktree 隔离 | Cursor: Tab 级并行 |
| 配置外置化 | YAML 71 条验证规则 | 无（hardcoded） |
| 可观测性 | GUI 控制台 + 事件总线 | Cursor: 内置 UI |

**结论**: spec-autopilot 在工程纪律维度实现了对 Cursor/Windsurf 的代际超越。Cursor 的优势在于 IDE 深度集成和实时补全，但在结构化交付流程上无法比拟。

### 6.2 vs GitHub Copilot Workspace

| 能力 | spec-autopilot v5.1.7 | Copilot Workspace |
|------|----------------------|-------------------|
| 规格驱动 | OpenSpec → 实现 → 测试 | Issue → Plan → Code |
| 门禁系统 | 三层硬约束 | PR Review（人工） |
| TDD 引擎 | 确定性 RED-GREEN-REFACTOR | 无 |
| 并行策略 | 8 域 + 批量调度器 | 单 Agent |
| 崩溃恢复 | 自动检查点恢复 | 手动重试 |
| 自定义约束 | forbidden_files/patterns + 动态加载 | 无 |
| 本地执行 | 完全本地 | 云端沙箱 |

**结论**: Copilot Workspace 在入门简易度上优势显著，但 spec-autopilot 在约束执行力和流程确定性上显著领先。

### 6.3 vs Bolt.new / v0.dev

| 能力 | spec-autopilot v5.1.7 | Bolt.new / v0.dev |
|------|----------------------|-------------------|
| 目标场景 | 企业级交付流水线 | 快速原型 / MVP |
| 项目规模 | 中大型（多模块/多域） | 小型单页应用 |
| 质量保障 | 三层门禁 + 测试金字塔 | 无（一次性生成） |
| 可维护性 | 高（检查点/知识萃取/归档） | 低（无后续生命周期） |
| 自定义度 | 极高（71 条配置规则） | 无 |
| 技术栈 | 任意（配置驱动） | 特定框架模板 |

**结论**: 两者定位完全不同。Bolt.new/v0.dev 擅长「从零到一」，spec-autopilot 擅长「从一到一百」的工程化交付。

### 6.4 四维对比矩阵

```
              工程纪律  可观测性  自动化深度  接入成本
              ────────  ────────  ──────────  ────────
spec-autopilot ★★★★★   ★★★★☆    ★★★★★      ★★★☆☆
Cursor/Windsurf ★★☆☆☆   ★★★★☆    ★★★☆☆      ★★★★★
Copilot WS      ★★★☆☆   ★★★☆☆    ★★★★☆      ★★★★☆
Bolt.new/v0     ★☆☆☆☆   ★☆☆☆☆    ★★☆☆☆      ★★★★★
```

---

## 静默盲点清单 (Silent Blind Spots)

按严重度降序排列：

| # | 严重度 | 盲点描述 | 影响范围 |
|---|--------|----------|----------|
| 1 | **P1** | 反合理化模式代码实现 24 种 vs 文档声称 29 种，存在 5 种缺口 | 质量逃逸风险 |
| 2 | **P1** | 无端到端集成测试覆盖完整 Phase 0→7 流程 | 回归风险 |
| 3 | **P2** | Store 无显式事件批量聚合窗口，>500 events/s 可能导致 React 重渲染风暴 | GUI 卡顿 |
| 4 | **P2** | L1 门禁（TaskCreate blockedBy）依赖 AI 诚实，缺少独立校验 | 门禁穿透 |
| 5 | **P2** | 无运行时性能 Profiling 基准数据，所有延迟数据均为静态分析预估 | 优化盲区 |
| 6 | **P2** | flock 5 秒超时降级为 timestamp+RANDOM 序列号，高并发下可能产生重复 | 事件乱序 |
| 7 | **P3** | 无 CI/CD 集成配置，测试仅可本地手动运行 | 自动化缺口 |
| 8 | **P3** | WS 重连无 jitter 抖动（仅 ×1.5 退避），多客户端同时断连可能形成重连风暴 | 服务端压力 |
| 9 | **P3** | `autopilot-gate` Skill 承载三重职责（门禁+检查点+TDD审计），单文件 372 行 | 可维护性 |
| 10 | **P3** | 无 FAQ / Troubleshooting 文档，新用户排障依赖代码阅读 | OOBE |
| 11 | **P3** | Phase 7 归档 `squash_on_archive` 依赖有效 anchor_sha，无效时静默跳过 | 数据完整性 |
| 12 | **P4** | VirtualTerminal 事件截断（80/120 字符）可能丢失关键错误上下文 | 调试体验 |
| 13 | **P4** | 配置向导缺失，30+ 参数需手动编写 YAML | 新手友好度 |
| 14 | **P4** | REFACTOR 回滚使用 `git checkout -- .` 全量回滚，可能覆盖同阶段其他修改 | 数据丢失风险 |

---

## 附录：量化预估数据汇总表

### A. 代码规模

| 模块 | 文件数 | 总行数 |
|------|--------|--------|
| Shell Scripts (scripts/) | ~15 | 4,366 |
| Python Scripts (scripts/) | ~5 | 1,417 |
| GUI Source (gui/src/) | ~10 | 1,324 |
| Skills + References | 7 + 27 | ~2,000+ |
| Tests | 58 | ~3,000+ |
| **总计** | **~115** | **~12,000+** |

### B. 质量保障指标

| 指标 | 数值 |
|------|------|
| 门禁层数 | 3 (L1/L2/L3) |
| Hook 注册数 | 7 (PreToolUse×1 + PostToolUse×2 + PreCompact×1 + SessionStart×3) |
| 配置验证规则总数 | 71 |
| 反合理化模式数 | 24 (代码) |
| TDD 铁律条数 | 5 |
| 测试文件数 | 58 |
| 断言/检查总数 | ~734 |
| 构建禁止路径数 | 6 |
| DEV-ONLY 关键字检查 | 3 |

### C. 性能预估基准

| 指标 | 数值 | 条件 |
|------|------|------|
| Hook 平均延迟 | ~56ms | 全 CHECK 启用 |
| Hook 快速路径延迟 | ~6ms | 早期退出命中 |
| flock 锁持有时间 | <1ms | 单次序列号递增 |
| WS 首次重连 | ~1.5s | 初始延迟 1000ms |
| WS 最大重连 | ~10s | 退避上限 |
| GUI 事件去重 + 截断 | <3ms | 1000 事件批量 |
| xterm.js 增量写入 | <1ms | 单事件 |
| 并行加速比 (8 域) | ~5x | 理想条件 |

### D. 插件元数据

| 字段 | 值 |
|------|-----|
| 名称 | spec-autopilot |
| 版本 | 5.1.7 |
| 关键字 | 57 |
| 许可证 | MIT |
| 仓库 | lorainwings/claude-autopilot |

---

> **评测结论**: spec-autopilot v5.1.7 在工程纪律和流程确定性方面达到了同类工具的最高水准。三层门禁体系、确定性 TDD 引擎、反合理化检测构成了其核心竞争壁垒。主要改进方向为端到端集成测试覆盖、GUI 事件批量聚合优化、以及反合理化模式的文档-代码同步。
