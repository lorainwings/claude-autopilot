# 全阶段性能与消耗评估报告

**审计日期**: 2026-03-13
**插件版本**: v5.0.1
**审计方**: AI 性能工程 Agent (Claude Opus 4.6)
**审计类型**: 理论分析（缺少实际运行 events.jsonl 数据，标注需实测验证项）

---

## 1. 执行摘要

本报告通过静态分析 spec-autopilot 的指标收集架构、事件发射脚本、Hook 超时配置和并行调度协议，建立每阶段的理论 Token 消耗模型和延迟模型。

**核心发现**:
- **Phase 5（实施）是绝对性能杀手**，理论占比 50-60% 的总 Token 消耗和 40-55% 的总耗时
- **Hook 链路在 PostToolUse 上存在串行瓶颈**: 每次 Write/Edit 触发 3 个 Hook 顺序执行（最大 35 秒超时）
- **指标收集架构成熟但缺少 Token 级指标**: 仅收集耗时和重试次数，无 input/output token 统计
- **并行模式理论加速比 2.5-4x**，但受 git merge 操作限制

**综合性能架构评分: 71/100**

---

## 2. Token 消耗模型（每阶段理论估算）

### 2.1 估算方法论

基于以下因素估算每阶段 Token 消耗:
- 主线程 Read/Write/Bash 调用量（从 SKILL.md 统计）
- 子 Agent prompt 长度 + 预期产出量
- Hook 脚本 stdout/stderr 注入主窗口上下文的量

### 2.2 每阶段 Token 估算

| Phase | 主线程消耗 | 子 Agent 消耗 | Hook 开销 | 总估算 | 占比 |
|-------|-----------|-------------|----------|--------|------|
| **0 (环境检查)** | ~2K（Skill 调用 + 锁文件读写） | 无 | ~500（SessionStart 3 Hook） | **~2.5K** | 1% |
| **1 (需求理解)** | ~8K（AskUserQuestion 多轮 + 信封解析） | ~30K（Auto-Scan 10K + Research 12K + Web 5K + BA 8K） | ~1K（无阶段 Hook） | **~39K** | 15% |
| **2 (OpenSpec 创建)** | ~3K（Gate + Dispatch 构造） | ~15K（OpenSpec 结构化文档生成） | ~2K（PostToolUse 信封验证） | **~20K** | 8% |
| **3 (FF 生成)** | ~3K（Gate + Dispatch 构造） | ~20K（tasks.md + specs 生成） | ~2K | **~25K** | 10% |
| **4 (测试设计)** | ~3K（Gate + Phase 4 特殊处理） | ~25K（测试用例设计，含 dry_run） | ~3K（PostToolUse + 金字塔验证） | **~31K** | 12% |
| **5 (实施)** | ~10K（多 Task 循环 + TDD 验证） | ~100K（代码实现，最大消耗者） | ~8K（每次 Write/Edit 3 Hook） | **~118K** | 46% |
| **6 (测试报告)** | ~3K（Gate + 三路并行派发） | ~12K（测试执行 + 报告生成） | ~2K | **~17K** | 7% |
| **7 (汇总归档)** | ~5K（Skill 调用 + 知识提取） | ~2K（collect-metrics.sh） | ~500 | **~7.5K** | 3% |
| **合计** | **~37K** | **~204K** | **~19K** | **~260K** | 100% |

### 2.3 关键发现

1. **子 Agent 消耗占 78%**: 204K/260K。主线程上下文保护策略有效——通过 JSON 信封机制，主线程仅消耗 37K
2. **Phase 5 独占 46%**: 代码实现是 Token 最大消耗者，每个 task 约 15-25K Token
3. **Hook 开销占 7%**: 19K Token，主要来自 Phase 5 的频繁 Write/Edit 触发（每个文件写入触发 3 个 Hook）
4. **lite 模式节省约 18%**: 跳过 Phase 2/3/4 节省约 76K Token
5. **minimal 模式节省约 25%**: 进一步跳过 Phase 6 节省约 93K Token

### 2.4 Token 优化机会

| 机会 | 预估节省 | 复杂度 | 建议 |
|------|---------|--------|------|
| Phase 5 子 Agent prompt 精简 | 10-15% | 低 | 移除冗余的参考文档注入，按需读取 |
| Hook stdout 精简 | 3-5% | 低 | 减少 Hook 成功时的输出（当前可能输出验证详情） |
| 持久化上下文命中率提升 | 5-10% (Phase 1) | 中 | 缩短刷新周期从 7 天到按 git commit 触发 |
| Phase 2/3 合并 | 8% | 高 | 将 OpenSpec 创建和 FF 生成合并为单个子 Agent |

---

## 3. 延迟分析

### 3.1 Hook 超时配置

从 `hooks/hooks.json` 提取:

| Hook | 触发时机 | 超时 | 异步 | 频率 |
|------|---------|------|------|------|
| `check-predecessor-checkpoint.sh` | PreToolUse(Task) | 30s | 否 | 每次 Task 派发 |
| `post-task-validator.sh` | PostToolUse(Task) | 150s | 否 | 每次 Task 完成 |
| `write-edit-constraint-check.sh` | PostToolUse(Write\|Edit) | 15s | 否 | 每次文件写入 |
| `banned-patterns-check.sh` | PostToolUse(Write\|Edit) | 10s | 否 | 每次文件写入 |
| `assertion-quality-check.sh` | PostToolUse(Write\|Edit) | 10s | 否 | 每次文件写入 |
| `save-state-before-compact.sh` | PreCompact | 15s | 否 | 每次压缩 |
| `scan-checkpoints-on-start.sh` | SessionStart | 15s | **是** | 会话启动 |
| `check-skill-size.sh` | SessionStart | 15s | 否 | 会话启动 |
| `reinject-state-after-compact.sh` | SessionStart(compact) | 15s | 否 | 压缩后 |

### 3.2 Write/Edit 操作的 Hook 串行瓶颈

**关键路径**: Phase 5 中每次 Write 或 Edit 触发 3 个 Hook **顺序执行**:
```
Write/Edit → write-edit-constraint-check.sh (15s)
           → banned-patterns-check.sh (10s)
           → assertion-quality-check.sh (10s)
           = 最大 35 秒延迟
```

**实际影响估算**:
- Phase 5 典型场景: 一个 task 产出 3-5 个文件，每文件 1-3 次 Write/Edit
- 总 Write/Edit 操作: 5-15 次/task × 5-10 tasks = 25-150 次
- 若每次 Hook 实际耗时 2-5 秒: 25×3s = 75s 到 150×5s = 750s (1.25-12.5 分钟)

**优化建议**: 将 3 个 Write/Edit Hook 合并为单个脚本，内部顺序执行 3 项检查，减少 Hook 调用开销。

### 3.3 每阶段延迟模型

| Phase | 理论延迟 (串行) | 理论延迟 (并行) | 瓶颈 |
|-------|---------------|---------------|------|
| 0 | 15-30s | — | 锁文件 I/O + checkpoint 扫描 |
| 1 | 5-30min | 3-15min | **用户交互等待**（非系统瓶颈） |
| 2 | 2-5min | — | 子 Agent LLM 生成 |
| 3 | 5-10min | — | OpenSpec FF 文档生成 |
| 4 | 5-15min | 3-8min | 测试用例设计 + dry_run |
| 5 | 30-120min | 15-45min | **代码实现 + Hook 串行** |
| 6 | 5-15min | 3-8min | 测试执行 + 报告生成 |
| 7 | 1-3min | — | collect-metrics + 知识提取 |
| **Full 总计** | **53-198min** | **30-109min** | Phase 1(用户) + Phase 5(系统) |

**并行模式加速比**: 理论 1.8-2.5x（受 git merge 串行化限制）

### 3.4 Git 操作延迟分析

每个 Phase 结束时执行的 git 操作:
```
git add -A → git commit --fixup → git rev-parse HEAD
```

- 小型变更: ~2-5s
- Phase 5 大型变更（10+ 文件）: ~5-15s
- 并行模式 worktree 合并: ~10-30s/组（含冲突检测）

Phase 7 的 `git rebase --autosquash`: 如果有 7 个 fixup commit，可能耗时 10-30s。

---

## 4. 指标收集架构评审

### 4.1 collect-metrics.sh 能力

**已收集指标**:
- 每阶段: status, duration_seconds, retry_count, start_time, end_time
- Phase 6.5: 代码审查结果
- 汇总: total_duration, total_retries

**输出格式**: JSON + markdown_table + ascii_chart（Phase 7 展示用）

**评分**: 65/100

### 4.2 缺失的关键指标

| 缺失指标 | 价值 | 建议 |
|---------|------|------|
| **Token 消耗** (input/output) | 最高——直接关联成本 | 需要 Claude Code API 暴露 token 计数 |
| **子 Agent 个数** | 高——量化并行效率 | 从 checkpoint parallel_metrics 提取 |
| **Hook 执行耗时** | 高——定位延迟瓶颈 | 在 _hook_preamble.sh 中添加计时 |
| **文件 I/O 量** | 中——理解磁盘负载 | 统计 Write/Edit/Read 调用次数 |
| **Gate 检查耗时** | 中——量化门禁开销 | 在 gate event 的 payload 中添加 duration |
| **用户等待时间** | 中——区分系统耗时和人工耗时 | Phase 1 AskUserQuestion 前后计时 |

### 4.3 Event Bus 指标补充

`emit-phase-event.sh` 和 `emit-gate-event.sh` 已发射事件到 `logs/events.jsonl`，但:
- **缺少 TaskProgressEvent**: event-bus-api.md 定义了 `task_progress` 类型（Phase 5 任务粒度），但无对应发射脚本
- **缺少 Token 指标字段**: event 的 payload 中无 token_count
- **缺少 Hook 执行事件**: Hook 执行不发射事件，无法从 events.jsonl 分析 Hook 延迟

---

## 5. 性能瓶颈定位

### 5.1 瓶颈优先级排序

| 排名 | 瓶颈 | 类型 | 影响 | 可优化性 |
|------|------|------|------|---------|
| 1 | **Phase 5 代码实现** | Token + 延迟 | 46% Token, 40-55% 耗时 | 中（受 LLM 能力限制） |
| 2 | **Write/Edit Hook 串行链** | 延迟 | Phase 5 额外 1-12 分钟 | 高（可合并为单脚本） |
| 3 | **Phase 1 用户交互** | 延迟 | 5-30 分钟不等 | 低（受用户响应速度限制） |
| 4 | **PostToolUse(Task) 150s 超时** | 延迟 | 单次最大 2.5 分钟阻塞 | 中（可调低到 60s） |
| 5 | **Phase 2/3 串行执行** | 延迟 | 7-15 分钟（两个串行阶段） | 高（可合并） |
| 6 | **git commit per-phase** | 延迟 | 每阶段 2-15s | 低（已后台化） |
| 7 | **Checkpoint Agent 后台等待** | 延迟 | 每阶段等待通知 | 低（已最优化） |

### 5.2 模式对比性能分析

| 指标 | Full | Lite | Minimal | Lite 节省 | Minimal 节省 |
|------|------|------|---------|----------|-------------|
| 阶段数 | 8 | 5 | 4 | 37.5% | 50% |
| 预估 Token | ~260K | ~182K | ~167K | 30% | 36% |
| 预估耗时 (串行) | 53-198min | 41-168min | 36-153min | 15-23% | 23-32% |
| 子 Agent 数 | 10-15 | 6-10 | 4-6 | 33% | 60% |

---

## 6. 优化建议（优先级排序）

### P0: 高影响低成本

| # | 优化 | 预估收益 | 实现复杂度 |
|---|------|---------|-----------|
| 1 | **合并 3 个 Write/Edit Hook 为单脚本** | Phase 5 减少 30-60% Hook 延迟 | 低（脚本合并） |
| 2 | **降低 post-task-validator.sh 超时**从 150s 到 60s | 减少最坏情况阻塞 | 低（改 hooks.json） |
| 3 | **在 _hook_preamble.sh 添加 Hook 计时** | 获得延迟诊断数据 | 低（3 行代码） |

### P1: 高影响中成本

| # | 优化 | 预估收益 | 实现复杂度 |
|---|------|---------|-----------|
| 4 | **实现 TaskProgressEvent 发射** | GUI 可显示 Phase 5 实时进度 | 中（新脚本 + SKILL.md 集成） |
| 5 | **Phase 2/3 合并为单子 Agent** | 节省 8% Token + 减少 1 次 Gate 检查 | 中（重构调度逻辑） |
| 6 | **Phase 5 子 Agent prompt 精简** | 节省 10-15% Token | 中（需验证质量不降低） |

### P2: 中影响高成本

| # | 优化 | 预估收益 | 实现复杂度 |
|---|------|---------|-----------|
| 7 | **Token 消耗追踪** | 成本可视化（需 Claude Code API 支持） | 高（依赖外部 API） |
| 8 | **Phase 5 批次调度优化** | 减少并行到串行的降级频率 | 高（算法重构） |

---

## 7. 综合性能评分

| 维度 | 权重 | 评分 | 加权 |
|------|------|------|------|
| Token 效率（上下文保护） | 25% | 82 | 20.5 |
| 延迟优化 | 25% | 60 | 15.0 |
| 指标收集完整性 | 20% | 65 | 13.0 |
| 并行化程度 | 15% | 75 | 11.25 |
| 可观测性 | 15% | 55 | 8.25 |
| **综合** | **100%** | | **68/100** |

### 评分解读

- **Token 效率 (82)**: 上下文保护策略（JSON 信封、后台子 Agent、持久化复用）效果显著，主线程仅消耗总 Token 的 14%
- **延迟优化 (60)**: Write/Edit Hook 串行链是主要延迟源，post-task-validator 150s 超时过高，Phase 2/3 可合并
- **指标收集 (65)**: duration + retry 基础指标齐全，但缺少 Token、Hook 耗时、用户等待时间等关键维度
- **并行化 (75)**: Phase 1/4/5/6 均支持并行，但受 git merge 串行化和降级条件限制
- **可观测性 (55)**: Event Bus 事件流为 GUI 提供了基础，但 TaskProgressEvent 未实现、Hook 无事件发射

---

## 需实际数据验证项

以下结论需要用户提供真实运行数据（`logs/events.jsonl` + checkpoint JSONs）后验证:

1. Phase 5 实际 Token 消耗是否占 46%（可能因项目规模浮动 ±15%）
2. Write/Edit Hook 实际耗时分布（理论 2-5s vs 可能更短）
3. 并行模式实际加速比（理论 1.8-2.5x vs 实际）
4. Phase 1 用户交互实际等待时间占比
5. git 操作实际延迟（依赖仓库大小和文件数）

---

*报告结束。*
