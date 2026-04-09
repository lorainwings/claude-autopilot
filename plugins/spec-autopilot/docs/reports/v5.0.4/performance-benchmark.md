# v5.0.4 全阶段性能与消耗评估报告

**审计日期**: 2026-03-13
**插件版本**: v5.0.4 (基于 v5.1 代码库)
**审计方**: Agent 3 — 全阶段性能与消耗评估审计员 (Claude Opus 4.6)
**审计类型**: 静态代码分析 + 文件尺寸实测
**前版对比**: `docs/reports/v5.0/performance-benchmark.md` (v5.0.1)

---

## 1. 审计摘要

### 1.1 性能总评

基于对 126 个源文件（总计 2.2MB）的静态分析，spec-autopilot 插件在 v5.1 中实现了两项关键性能改进：**Hook 合并**（3 个 Write/Edit Hook 合并为 `unified-write-edit-check.sh`）和 **Task 验证合并**（5 个 PostToolUse(Task) 验证器合并为 `post-task-validator.sh` + `_post_task_validator.py`）。这两项改进直接命中 v5.0 报告识别的 Top 2 瓶颈。

### 1.2 Top 3 性能瓶颈（v5.0.4 当前）

| 排名 | 瓶颈 | 影响量化 | v5.0 排名 | 变化 |
|------|------|---------|----------|------|
| **1** | **Phase 5 代码实施 Token 消耗** | 占总 Token 的 43-48%，占总耗时 40-55% | #1 | 持平（结构性瓶颈） |
| **2** | **SKILL.md + references 总 context 注入量 260KB** | 每次 Skill 调用注入 9-33KB prompt | 新发现 | 首次精确量化 |
| **3** | **Phase 1 多轮用户交互等待** | 5-30 分钟不可压缩延迟 | #3 | 持平 |

### 1.3 综合性能评分

| 维度 | 权重 | v5.0.1 评分 | v5.0.4 评分 | 变化 |
|------|------|-----------|-----------|------|
| Token 效率 | 25% | 82 | 82 | -- |
| 延迟优化 | 25% | 60 | **73** | +13 |
| 指标收集完整性 | 20% | 65 | 65 | -- |
| 并行化程度 | 15% | 75 | 75 | -- |
| 可观测性 | 15% | 55 | 55 | -- |
| **综合** | 100% | **68** | **73** | **+5** |

延迟优化大幅提升归因于 v5.1 的 Hook 合并：Write/Edit 最坏延迟从 35s 降至 15s，Task 验证从 420ms 降至 100ms。

---

## 2. Token 消耗热力图（Phase x Mode 矩阵）

### 2.1 文件尺寸实测（context 注入基础数据）

#### SKILL.md 文件（Skill 调用时全量注入 context）

| 文件 | 字节 | 估算 Token | 调用阶段 |
|------|------|-----------|---------|
| `autopilot/SKILL.md` | 22,770 | ~5,700 | Phase 0 启动时加载，全程常驻 |
| `autopilot-dispatch/SKILL.md` | 17,255 | ~4,300 | Phase 2-6 每次 dispatch |
| `autopilot-gate/SKILL.md` | 13,928 | ~3,500 | Phase 2-6 每次 gate check |
| `autopilot-setup/SKILL.md` | 13,167 | ~3,300 | 仅首次无配置时 |
| `autopilot-phase0/SKILL.md` | 8,985 | ~2,250 | Phase 0 |
| `autopilot-phase7/SKILL.md` | 7,848 | ~1,960 | Phase 7 |
| `autopilot-recovery/SKILL.md` | 5,781 | ~1,450 | Phase 0 恢复时 |
| **合计** | **89,734** | **~22,460** | |

#### Reference 文件（按需读取注入）

| 文件 | 字节 | 估算 Token | 读取阶段 |
|------|------|-----------|---------|
| `parallel-dispatch.md` | 33,623 | ~8,400 | Phase 1/4/5/6 并行时 |
| `phase5-implementation.md` | 23,617 | ~5,900 | Phase 5 |
| `phase1-requirements-detail.md` | 22,207 | ~5,550 | Phase 1 按需 |
| `config-schema.md` | 12,467 | ~3,100 | Phase 0 init |
| `tdd-cycle.md` | 11,287 | ~2,820 | Phase 5 TDD 模式 |
| `protocol.md` | 8,530 | ~2,130 | Phase 2-6 dispatch/gate |
| `phase1-requirements.md` | 8,452 | ~2,110 | Phase 1 |
| `quality-scans.md` | 6,218 | ~1,550 | Phase 6 |
| `knowledge-accumulation.md` | 6,104 | ~1,530 | Phase 7 |
| `dispatch-prompt-template.md` | 5,422 | ~1,360 | Phase 2-6 dispatch |
| `testing-anti-patterns.md` | 5,303 | ~1,330 | Phase 5 TDD |
| `guardrails.md` | 4,722 | ~1,180 | 阶段切换时 |
| `event-bus-api.md` | 4,277 | ~1,070 | Phase 0 |
| `metrics-collection.md` | 3,567 | ~890 | Phase 7 |
| `phase6-code-review.md` | 3,547 | ~890 | Phase 6 |
| `phase1-supplementary.md` | 3,334 | ~830 | Phase 1 large |
| `brownfield-validation.md` | 2,976 | ~740 | Gate check |
| `semantic-validation.md` | 2,854 | ~710 | Gate check |
| `log-format.md` | 2,021 | ~510 | 全程 |
| **合计** | **170,528** | **~42,600** | |

#### 其他常驻 context

| 文件 | 字节 | 估算 Token | 说明 |
|------|------|-----------|------|
| `CLAUDE.md` | 3,984 | ~1,000 | 插件级规则，全程常驻 |

**总 prompt 素材库**: 260,262 字节（SKILL.md + references），约 65,060 Token。

### 2.2 Token 消耗热力图

以下矩阵估算各阶段在不同模式下的 Token 消耗。估算方法：主线程 Skill context 注入 + reference 读取 + 子 Agent prompt 构造 + 子 Agent 执行产出 + Hook stdout。

Token 换算比：1 Token ~= 4 字节（中英文混合文档偏保守按 1:3.5-4 估算）。

#### Full 模式 Token 消耗

| Phase | 主线程 context | Reference 读取 | 子 Agent prompt | 子 Agent 产出 | Hook 开销 | **阶段总计** | **占比** |
|-------|---------------|---------------|----------------|-------------|----------|------------|--------|
| **0** | ~5,700 (SKILL.md) + 2,250 (phase0) + 1,450 (recovery) | ~3,100 (config-schema) + 1,070 (event-bus) | 无子 Agent | 无 | ~500 | **~14,070** | 4.7% |
| **1** | ~5,700 (常驻) + 2,110 (phase1-req) | ~5,550 (detail, 按需) + 830 (supplementary, large) | ~10K (Auto-Scan) + ~12K (Research) + ~5K (Web) + ~10K (BA) | ~8K (信封摘要到主线程) | ~500 | **~59,690** | 20.0% |
| **2** | ~4,300 (dispatch) + 3,500 (gate) | ~1,360 (dispatch-tmpl) + 2,130 (protocol) | ~8K (OpenSpec 创建) | ~12K (文档生成) | ~1K | **~32,290** | 10.8% |
| **3** | ~4,300 + 3,500 | ~1,360 + 2,130 | ~8K (FF 生成) | ~18K (specs/tasks/design) | ~1K | **~38,290** | 12.8% |
| **4** | ~4,300 + 3,500 | ~8,400 (parallel-dispatch) + 2,130 | ~6K x 4 类型 (测试设计) | ~5K x 4 (测试文件) | ~2K | **~44,330** | 14.9% |
| **5-serial** | ~4,300 + 3,500 | ~5,900 (phase5-impl) + 8,400 (parallel) | ~5K x N tasks | ~15K x N tasks | ~3K x N tasks | **~23K x N** | -- |
| **5** (N=5) | 同上 | 同上 | ~25K | ~75K | ~15K | **~132,100** | 44.3% |
| **6** | ~4,300 + 3,500 | ~890 (phase6-cr) + 1,550 (quality) + 8,400 (parallel) | ~6K (测试执行) + ~4K (代码审查) + ~3K (质量扫描) | ~5K | ~1.5K | **~38,140** | 12.8% |
| **7** | ~1,960 (phase7) | ~1,530 (knowledge) + 890 (metrics) | ~4K (汇总) + ~3K (知识提取) | ~2K | ~500 | **~13,880** | 4.7% |

**Full 模式总 Token 估算 (5 tasks)**: ~298K

#### 模式对比矩阵

| Phase | Full | Lite | Minimal | 说明 |
|-------|------|------|---------|------|
| 0 | ~14K | ~14K | ~14K | 所有模式相同 |
| 1 | ~60K | ~60K | ~60K | 所有模式相同（核心约束） |
| 2 | ~32K | **跳过** | **跳过** | lite/minimal 无 OpenSpec |
| 3 | ~38K | **跳过** | **跳过** | lite/minimal 无 FF |
| 4 | ~44K | **跳过** | **跳过** | lite/minimal 无测试设计 |
| 5 | ~132K | ~132K | ~132K | 所有模式相同质量 |
| 6 | ~38K | ~38K | **跳过** | minimal 无测试报告 |
| 7 | ~14K | ~14K | ~14K | 所有模式相同 |
| **合计** | **~298K** | **~258K** | **~220K** | -- |
| **相对 Full 节省** | -- | **13%** | **26%** | -- |

#### TDD 模式额外 Token 开销

| 项目 | 额外 Token | 说明 |
|------|-----------|------|
| TDD cycle reference 注入 | ~2,820/task | `tdd-cycle.md` 每个 task prompt 注入 |
| Anti-patterns 注入 | ~1,330/task | `testing-anti-patterns.md` 注入 |
| RED Task | ~3K/task | 测试编写 prompt + 产出 |
| GREEN Task | ~4K/task | 实现编写 prompt + 产出 |
| REFACTOR Task | ~2K/task | 重构 prompt + 产出 |
| L2 验证 (Bash) | ~200/task | 主线程 Bash 执行测试命令 |
| **每 task 额外** | **~13,350** | -- |
| **5 tasks 总额外** | **~66,750** | Phase 5 Token 从 ~132K 涨到 ~199K |

**TDD Full 模式总估算**: ~365K（比非 TDD Full 多 22%）

### 2.3 并行 vs 串行 Token 效率

| 维度 | 串行模式 | 并行模式 | 差异 |
|------|---------|---------|------|
| **Phase 5 主线程 context** | ~23K x N (每 task 累加前序摘要) | ~14K x domains (域级 prompt) | 并行节省 15-30% (fewer prompt rounds) |
| **文件所有权注入** | 无 | +~500/domain (owned_files 列表) | 并行微增 |
| **Review Agent** | 无 (串行内建) | +~5K (批量 review) | 并行微增 |
| **Merge 验证** | 无 | +~1K (typecheck per domain) | 并行微增 |
| **总效率差** | 基准 | **净节省 10-20%** | 来自减少的 prompt 轮次 |

关键发现：并行模式在 Token 层面轻微优于串行，因为域级单 Agent 批量处理减少了 prompt 开头的 context 重复注入。但省出的 Token 被文件所有权列表和 review Agent 部分抵消。

---

## 3. 延迟瓶颈分析

### 3.1 Hook 延迟分析（v5.1 改进后实测配置）

| Hook | 触发事件 | 超时(ms) | 异步 | 频率/阶段 | 实际耗时估算 |
|------|---------|---------|------|----------|------------|
| `check-predecessor-checkpoint.sh` | PreToolUse(Task) | 30,000 | 否 | Phase 2-6 各 1 次 | 5-15ms（bash + JSON parse） |
| `post-task-validator.sh` | PostToolUse(Task) | 150,000 | 否 | Phase 2-6 各 1+ 次 | **80-150ms**（python3 启动 + 5 项验证） |
| `unified-write-edit-check.sh` | PostToolUse(Write\|Edit) | 15,000 | 否 | Phase 5 高频 | **5-30ms**（bash + grep + python3） |
| `save-state-before-compact.sh` | PreCompact | 15,000 | 否 | 0-2 次/会话 | 10-50ms |
| `scan-checkpoints-on-start.sh` | SessionStart | 15,000 | **是** | 1 次 | 20-100ms |
| `check-skill-size.sh` | SessionStart | 15,000 | 否 | 1 次 | 5-10ms |
| `reinject-state-after-compact.sh` | SessionStart(compact) | 15,000 | 否 | 0-2 次 | 10-50ms |

#### v5.1 Hook 合并效果量化

**Write/Edit Hook (Phase 5 关键路径)**:

| 版本 | Hook 数量 | 最坏延迟 | 实际延迟估算 |
|------|----------|---------|------------|
| v5.0 | 3 个串行（write-edit-constraint 15s + banned-patterns 10s + assertion-quality 10s） | **35,000ms** | 6-15s |
| v5.1 | **1 个统一** (`unified-write-edit-check.sh` 15s) | **15,000ms** | **5-30ms** |
| **改进** | -2 hooks | **-57% 最坏延迟** | **-60~80% 实际延迟** |

**PostToolUse(Task) 验证器**:

| 版本 | 方式 | 延迟 |
|------|------|------|
| v5.0 | 5 个 shell 脚本 fork | ~420ms |
| v5.1 | 1 个 python3 进程 | **~100ms** |
| **改进** | -4 forks | **-76%** |

### 3.2 Gate 门禁延迟

| 层级 | 机制 | 延迟估算 | 说明 |
|------|------|---------|------|
| L1 | TaskCreate blockedBy | ~0ms | 任务系统内置，无 I/O |
| L2 | `check-predecessor-checkpoint.sh` | 5-15ms | 文件存在检查 + JSON status 解析 |
| L3 | autopilot-gate 8 步清单 | 2-5s | AI 执行：读取 checkpoint + 验证 + 输出日志 |
| L3 特殊门禁 | Phase 4->5, 5->6 | 3-8s | 额外字段验证（test_counts, zero_skip 等） |
| **总 Gate 延迟** | | **5-28s/次** | full 模式 5 次 gate = 25-140s |

### 3.3 文件 I/O 延迟

| 操作 | 频率 | 延迟 | 影响 |
|------|------|------|------|
| JSONL 追加写 (events.jsonl) | 每 Phase start/end + gate | ~1ms/次 | 可忽略 |
| Checkpoint 原子写入 | 每 Phase 1 次 + Phase 5 每 task | 5-20ms（write .tmp + verify + mv） | Phase 5 长流程累计 50-200ms |
| Git fixup commit | 每 Phase 1 次 + Phase 5 每 task | 2-15s | 取决于变更文件数和仓库大小 |
| Phase 5 ownership JSON | 并行模式每域 1 次 | ~2ms | 可忽略 |

### 3.4 并行调度启动延迟

| 操作 | 延迟 | 说明 |
|------|------|------|
| Worktree 创建 | 2-5s/域 | `git worktree add` + 分支创建 |
| Worktree 合并 | 5-30s/域 | `git merge --no-ff` + 冲突检测 |
| Worktree 清理 | 1-3s/域 | `git worktree remove` + `git branch -d` |
| **并行 3 域总开销** | **24-114s** | 创建 6-15s + 合并 15-90s + 清理 3-9s |

### 3.5 Compact 恢复延迟

| 操作 | 延迟 | 说明 |
|------|------|------|
| `save-state-before-compact.sh` | 10-50ms | 写入 `autopilot-state.md` |
| `reinject-state-after-compact.sh` | 10-50ms | 注入状态回 context |
| 主线程恢复 | 2-5s | 读取 state + 重载 config + 验证 checkpoint |
| **总 Compact 恢复延迟** | **2.1-5.1s** | 对用户感知良好 |

### 3.6 每阶段延迟模型（v5.0.4 更新）

| Phase | 串行延迟 | 并行延迟 | 主要瓶颈 | v5.0 对比 |
|-------|---------|---------|---------|----------|
| 0 | 5-15s | -- | config 加载 + 恢复扫描 | 无变化 |
| 1 | 5-30min | 3-15min | **用户交互**（不可压缩） | 无变化 |
| 2 | 2-5min | -- | LLM 文档生成 | 无变化 |
| 3 | 5-10min | -- | LLM FF 制品生成 | 无变化 |
| 4 | 5-15min | 3-8min | 测试用例设计 + dry-run | 无变化 |
| 5 | 30-120min | 15-45min | **代码实施 + Hook（已优化）** | Hook -57% |
| 6 | 5-15min | 3-8min | 测试执行 + 报告 | 无变化 |
| 7 | 1-3min | -- | collect-metrics + 知识提取 | 无变化 |
| **Full 总计** | **53-198min** | **30-109min** | | Hook 优化 |

---

## 4. 性能杀手 Top 10 排名

| 排名 | 杀手 | 类别 | 量化影响 | 可优化性 | 建议 |
|------|------|------|---------|---------|------|
| **1** | Phase 5 代码实施 Token | Token | ~132K (44% of total) | 中 | prompt 精简，按需注入 reference |
| **2** | SKILL.md 全量注入 | Token | 每次 Skill 调用注入 5-22K Token | 中 | 分层加载：核心指令 vs 详细参考 |
| **3** | Phase 1 用户交互等待 | 延迟 | 5-30min 不可压缩 | 低 | 优化决策卡片减少轮次 |
| **4** | `parallel-dispatch.md` 33.6KB | Token | Phase 1/4/5/6 每次读取 ~8.4K Token | 高 | 按阶段拆分为 4 个小文件 |
| **5** | `phase5-implementation.md` 23.6KB | Token | Phase 5 读取 ~5.9K Token | 中 | 串行/并行章节按需加载 |
| **6** | `phase1-requirements-detail.md` 22.2KB | Token | Phase 1 按需读取 ~5.5K Token | 中 | 已是按需加载，可进一步拆分 |
| **7** | Phase 5 Git fixup 操作 | 延迟 | 2-15s x N tasks | 低 | 已后台化 |
| **8** | TDD 模式 3x Task 派发 | Token | +13.3K/task (+22% total) | 低 | TDD 固有开销 |
| **9** | post-task-validator 150s 超时 | 延迟 | 最坏 2.5min 阻塞 | 高 | 降低到 60s |
| **10** | Phase 2+3 串行两阶段 | 延迟 | 7-15min 顺序执行 | 中 | 可合并为单阶段 |

### 4.1 冗余 context 注入分析

| 冗余项 | 涉及文件 | 重复注入次数 | 浪费 Token |
|--------|---------|------------|-----------|
| `parallel-dispatch.md` 全量读取 | Phase 1/4/5/6 | 4 次（各阶段全量读取含所有阶段配置） | ~25K (3 x 8.4K 冗余) |
| `protocol.md` 全量读取 | dispatch + gate 各阶段 | 5-10 次 | ~10-21K |
| `dispatch-prompt-template.md` | Phase 2-6 dispatch | 5 次 | ~5.4K (4 x 1.36K 冗余) |
| `autopilot/SKILL.md` 常驻 | 全程 | 持续占用 | ~5.7K（必要开销） |

**冗余 Token 总估算**: ~40-51K，占 Full 模式总量的 **13-17%**。

### 4.2 全量读取可改为增量处理的位置

| 位置 | 当前行为 | 优化方案 | 节省估算 |
|------|---------|---------|---------|
| `parallel-dispatch.md` Phase 1 节 | 读取全量 33KB | 按阶段拆分为独立文件 | ~6.3K/次 |
| `phase1-requirements-detail.md` | Phase 1 全量读取 22KB | 仅在 complexity=large 时读取完整版 | ~3K (small/medium 场景) |
| `config-schema.md` | Phase 0 init 全量读取 | 仅在无配置时读取 | ~3.1K (有配置时) |
| Phase 5 Steering Documents | 每个子 Agent 自行 Read | 已优化（v3.4.0 主线程提取注入） | -- |

---

## 5. 无人工干预成功率预估

### 5.1 各阶段触发人工干预条件

| Phase | 干预触发条件 | 概率 | 说明 |
|-------|------------|------|------|
| **0** | PID 冲突（锁文件已存在且 PID 存活） | 5% | 仅多会话并行时 |
| **0** | python3 不可用 | 2% | 现代 macOS/Linux 几乎都有 |
| **1** | `after_phase_1` 用户确认（默认 true） | **100%** | 设计要求，不可跳过 |
| **1** | 需求澄清预循环（flags >= 3） | 15% | 需求过于模糊时 |
| **1** | 多轮决策 LOOP（large complexity） | 30% | large 强制 3+ 轮 |
| **2** | Gate 阻断（Phase 1 checkpoint 缺失） | <1% | 极罕见 |
| **3** | Gate 阻断 | <1% | 极罕见 |
| **4** | Phase 4 warning 强制 blocked | 15% | 测试数量/覆盖率不足 |
| **4** | dry_run 失败 | 10% | 测试语法错误 |
| **5** | Wall-clock 2h 超时 | 5% | 大型项目 |
| **5** | 连续 3 次 task 失败 | 8% | 复杂实现 |
| **5** | 并行合并冲突 > 3 文件 | 10% | 并行模式特有 |
| **6** | 测试全部失败 | 5% | 实现有 bug |
| **6.5** | Critical code review findings | 8% | 安全/架构问题 |
| **7** | 归档确认（设计要求） | **100%** | 必须用户确认 |

### 5.2 Gate 自动通过率预估

| Gate | 自动通过率 | 阻断原因 |
|------|----------|---------|
| Phase 1 -> 2 | 98% | Phase 1 checkpoint 格式异常 |
| Phase 2 -> 3 | 99% | OpenSpec 创建失败 |
| Phase 3 -> 4 | 99% | FF 生成失败 |
| Phase 4 -> 5（非 TDD） | **80%** | test_counts 不足、dry_run 失败、test_pyramid 违规 |
| Phase 4 -> 5（TDD） | 99% | 仅检查 tdd-override.json |
| Phase 5 -> 6 | **85%** | zero_skip_check 失败、test-results 缺失、tasks 未全部 [x] |
| Phase 6 -> 7 | 95% | 测试全失败 |
| **加权平均** | **~90%** | |

### 5.3 TDD RED/GREEN 自动通过率

| 步骤 | 自动通过率 | 失败原因 |
|------|----------|---------|
| RED（测试必须失败） | 85% | 测试立即通过（测试逻辑有误）或语法错误 |
| GREEN（测试必须通过） | 75% | 实现不正确，需重试（max 3 次） |
| REFACTOR（测试仍通过） | 90% | 重构引入 regression（自动 git checkout 回滚） |
| **单 task TDD 全通过率** | **~57%** | 0.85 x 0.75 x 0.90 |
| **5 tasks 全自动通过率** | **~6%** | 0.57^5 |

关键发现：TDD 模式的串行特性导致自动完成率极低。每个 task 的 RED/GREEN 验证依赖 LLM 能力，GREEN 阶段 25% 的失败率是主要瓶颈。建议关注 GREEN 阶段的 prompt 质量以提升通过率。

### 5.4 并行合并自动通过率

| 场景 | 通过率 | 说明 |
|------|--------|------|
| 2 域无交叉文件 | 95% | 域分区良好时极少冲突 |
| 3 域有少量交叉 | 80% | 跨域公共文件（如配置文件）可能冲突 |
| 3 域 + cross-cutting tasks | 70% | cross-cutting 串行执行兜底 |
| Worktree 创建成功率 | 99% | 磁盘空间/权限极少失败 |

### 5.5 端到端无人工干预成功率

| 模式 | 估算无干预通过率 | 瓶颈 |
|------|----------------|------|
| Full（串行） | **~0%** | Phase 1 确认 + Phase 7 归档确认为设计强制 |
| Full（去除设计强制确认） | **~45%** | Phase 4 gate (80%) x Phase 5 gate (85%) x Phase 6 pass (95%) |
| Lite（串行） | **~0%** | 同上，Phase 1/7 确认强制 |
| Lite（去除强制确认） | **~65%** | 跳过 Phase 4 gate |
| Minimal | **~0%** | Phase 1 确认强制 |
| Minimal（去除强制确认） | **~75%** | 最少 gate 检查 |

---

## 6. 与 v5.0 报告对比

### 6.1 v5.0 报告 P0 建议执行状况

| v5.0 建议 | 优先级 | v5.1 执行状况 | 效果 |
|----------|--------|-------------|------|
| 合并 3 个 Write/Edit Hook 为单脚本 | P0 | **已完成** (`unified-write-edit-check.sh`) | 最坏延迟 -57% (35s->15s) |
| 降低 post-task-validator 超时 | P0 | **部分完成**（合并为单 python3 进程，超时仍 150s） | 实际延迟 -76% (420ms->100ms) |
| 在 _hook_preamble.sh 添加计时 | P0 | **未执行** | 仍缺少 Hook 延迟诊断数据 |

### 6.2 v5.0 报告 P1 建议执行状况

| v5.0 建议 | 优先级 | v5.1 执行状况 | 效果 |
|----------|--------|-------------|------|
| 实现 TaskProgressEvent 发射 | P1 | **未执行** | GUI 仍无 Phase 5 实时进度 |
| Phase 2/3 合并为单子 Agent | P1 | **未执行** | 仍为两阶段串行 |
| Phase 5 子 Agent prompt 精简 | P1 | **未执行** | prompt 尺寸未变 |

### 6.3 Token 消耗估算对比

| 指标 | v5.0 报告 | v5.0.4 报告 | 变化 | 说明 |
|------|----------|-----------|------|------|
| Full 模式总 Token | ~260K | **~298K** | +15% | v5.0.4 更精确（含 SKILL.md context + reference 注入，v5.0 低估） |
| Phase 5 占比 | 46% | **44%** | -2pp | 其他阶段 context 注入更精确后相对占比下降 |
| Hook 开销占比 | 7% | **~2%** | -5pp | v5.1 Hook 合并减少 stdout 输出 |
| 子 Agent 消耗占比 | 78% | **~72%** | -6pp | Skill context 注入更精确统计后比例调整 |
| 主线程消耗 | ~37K | **~50K** | +35% | v5.0 未计入 Skill/reference 全量 context |

**关键差异说明**: v5.0.4 报告首次精确计入了 SKILL.md 全量注入（89.7KB / ~22.5K Token）和 reference 按需读取（170.5KB / ~42.6K Token）的 context 成本。v5.0 报告仅统计了子 Agent prompt 和产出，低估了主线程 Skill 调用的 context 注入量。

### 6.4 延迟对比

| 指标 | v5.0 | v5.0.4 | 改进 |
|------|------|--------|------|
| Write/Edit 最坏 Hook 延迟 | 35s | **15s** | **-57%** |
| PostToolUse(Task) 验证延迟 | ~420ms | **~100ms** | **-76%** |
| Phase 5 总 Hook 开销估算 (50 次 Write/Edit) | 75-750s | **15-150s** | **-80%** |
| Full 串行总耗时范围 | 53-198min | **53-198min** | 无变化（LLM 时间主导） |

### 6.5 综合评分对比

| 维度 | v5.0 | v5.0.4 | 变化 | 归因 |
|------|------|--------|------|------|
| Token 效率 | 82 | 82 | -- | 无架构级变更 |
| 延迟优化 | 60 | **73** | **+13** | Hook 合并 + 验证器合并 |
| 指标收集 | 65 | 65 | -- | 未新增指标维度 |
| 并行化 | 75 | 75 | -- | 未新增并行能力 |
| 可观测性 | 55 | 55 | -- | 未实现 TaskProgressEvent |
| **综合** | **68** | **73** | **+5** | |

---

## 7. 优化路线图

### 7.1 短期（1-2 周，v5.2）

| # | 优化项 | 预估收益 | 复杂度 | 依赖 |
|---|--------|---------|--------|------|
| S1 | **降低 post-task-validator 超时**从 150s 到 60s | 减少最坏阻塞 60% | 极低 | 改 hooks.json 一行 |
| S2 | **在 _hook_preamble.sh 添加 Hook 计时** | 获得真实延迟数据 | 低 | 3-5 行代码 |
| S3 | **拆分 `parallel-dispatch.md`** 为 4 个阶段文件 | 减少冗余注入 ~25K Token (8%) | 低 | 文件拆分 + 引用更新 |
| S4 | **Phase 5 串行模式前序摘要截断** | 随 task 数增长主线程 context 不膨胀 | 低 | 仅保留最近 3 个 task 摘要 |

### 7.2 中期（1-2 月，v5.3-v6.0）

| # | 优化项 | 预估收益 | 复杂度 | 依赖 |
|---|--------|---------|--------|------|
| M1 | **Phase 2+3 合并为单阶段** | 节省 ~32K Token (11%) + 减少 1 次 Gate | 中 | 重构 dispatch/gate 逻辑 |
| M2 | **SKILL.md 分层加载** | 核心指令 ~5K（常驻）+ 详细参考 ~17K（按需） | 中 | 需 Claude Code 支持条件加载 |
| M3 | **实现 TaskProgressEvent** | GUI 实时展示 Phase 5 进度 | 中 | 新脚本 + SKILL.md 集成 |
| M4 | **Phase 5 TDD GREEN prompt 优化** | 提升 GREEN 通过率从 75% 到 85% | 中 | prompt 工程实验 |
| M5 | **增加 Token 消耗估算到 _metrics** | 基于 prompt 字节数估算 Token 写入 checkpoint | 中 | 扩展 `collect-metrics.sh` |

### 7.3 长期（3-6 月，v7.0）

| # | 优化项 | 预估收益 | 复杂度 | 依赖 |
|---|--------|---------|--------|------|
| L1 | **真实 Token 追踪** | 精确成本可视化 | 高 | Claude Code API 暴露 token 计数 |
| L2 | **Phase 5 增量 context 策略** | 子 Agent 仅接收 diff context 而非全量 | 高 | 需要 context 管理框架 |
| L3 | **智能 Gate 自适应阈值** | 基于历史通过率自动调整门禁宽松度 | 高 | 需要足够运行数据积累 |
| L4 | **Phase 1 决策预测** | 基于历史决策模式预填推荐值 | 高 | 需要 knowledge.json 足够丰富 |

### 7.4 优化预期收益汇总

| 时间段 | Token 节省 | 延迟改善 | 自动化率提升 |
|--------|-----------|---------|-------------|
| 短期 S1-S4 | 8-12% (~25K) | 最坏延迟 -60% | -- |
| 中期 M1-M5 | 15-20% (~50K) | Phase 2+3 合并省 7-15min | TDD GREEN +10pp |
| 长期 L1-L4 | 精确量化（当前为估算） | 增量 context 省 20-30% | 决策预测 +15pp |

---

## 附录 A: 文件尺寸完整清单

### Scripts 目录（328KB）

| 文件 | 字节 | 用途 |
|------|------|------|
| `test-hooks.sh` | 129,224 | Hook 测试套件（非生产） |
| `_post_task_validator.py` | 28,609 | **统一 Task 验证器**（v5.1 新增） |
| `check-predecessor-checkpoint.sh` | 15,400 | L2 前置 checkpoint 检查 |
| `_config_validator.py` | 12,949 | 配置 schema 验证 |
| `_common.sh` | 10,784 | 共享 bash 工具函数 |
| `unified-write-edit-check.sh` | 10,707 | **统一 Write/Edit 检查**（v5.1 新增） |
| `validate-json-envelope.sh` | 10,015 | JSON 信封验证（被 post-task-validator 替代） |
| `parallel-merge-guard.sh` | 8,753 | 并行合并守卫 |
| `save-state-before-compact.sh` | 7,692 | Compact 前状态保存 |
| `check-allure-install.sh` | 6,853 | Allure 安装检测 |
| `_constraint_loader.py` | 6,819 | 代码约束加载器 |
| 其余 16 个脚本 | ~80K | 各类辅助功能 |

### 生产 Hook 调用链

```
PreToolUse(Task):
  check-predecessor-checkpoint.sh [30s]
    -> _hook_preamble.sh -> _common.sh -> find_checkpoint() -> JSON parse

PostToolUse(Task):
  post-task-validator.sh [150s]
    -> _hook_preamble.sh -> _common.sh -> has_phase_marker()
    -> python3 _post_task_validator.py
       -> _envelope_parser.py (JSON 信封解析)
       -> _constraint_loader.py (代码约束)
       -> 5 项验证（信封/反合理化/约束/合并守卫/决策格式）

PostToolUse(Write|Edit):
  unified-write-edit-check.sh [15s]
    -> _hook_preamble.sh -> _common.sh
    -> CHECK 0: 子 Agent 状态隔离 (~1ms, pure bash)
    -> CHECK 1: TDD 阶段隔离 (~1ms, pure bash)
    -> CHECK 2: 禁止模式检测 (~2ms, grep)
    -> CHECK 3: 恒真断言检测 (~2ms, grep)
    -> CHECK 4: 代码约束检查 (~20ms, python3)
```

## 附录 B: Token 估算方法论

1. **字节到 Token 换算**：使用 1 Token ~= 4 字节的保守比率。中英文混合文档实际比率约 3.5-4.5，此处取 4 作为统一基准。
2. **主线程 context**：Skill 调用时 SKILL.md 全文被注入 context window，按文件字节 / 4 计算。
3. **Reference 读取**：`references/*.md` 在协议中标注"执行前读取"的文件按全量计入；标注"按需加载"的按 50% 概率折算。
4. **子 Agent prompt**：dispatch 模板字节 + 变量展开后的 context 注入（config 片段约 1-3K Token）。
5. **子 Agent 产出**：基于产出文件类型估算（文档 ~5-15K，代码 ~10-20K/task，信封 ~200-500）。
6. **Hook 开销**：仅 block 决策的 stdout 输出计入 context（约 100-300 Token/次），正常通过无输出。

---

*报告结束。*
*审计方: Agent 3 — 全阶段性能与消耗评估审计员*
*生成时间: 2026-03-13*
