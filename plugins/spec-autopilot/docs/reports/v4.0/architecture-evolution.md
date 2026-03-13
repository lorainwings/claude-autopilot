# 全局架构演进与 Vibe Workflow 融合指南

> **报告版本**: v1.0
> **生成日期**: 2026-03-13
> **插件版本**: spec-autopilot v4.0.3 (commit 08d346f)
> **输入源**: 6 份专项审计报告 + 插件核心文件全量分析
> **报告定位**: 终极架构演进路线图 — 汇聚所有审计发现，规划从 v4.1 到 v6.0 的完整演进路径

---

## 1. 执行摘要

### 1.1 六份报告核心数据汇总

| # | 报告 | 评分 | P0 | P1 | P2 | 核心结论 |
|---|------|:----:|:--:|:--:|:--:|---------|
| 1 | 稳定性审计 | **8.2/10** | 0 | 3 | 5 | 三层门禁完备，崩溃恢复 anchor_sha 有缺口 |
| 2 | Phase 1 需求质量 | **7.4/10** | 1 | 2 | 4 | 模糊度检测缺失，需求类型不分类 |
| 3 | Phase 5 代码生成 | **8.7/10** | 0 | 3 | 5 | 规约服从度链路精良，并行反偷懒有盲区 |
| 4 | TDD 流程审计 | **7.4/10** | 2 | 4 | 5 | 串行 TDD 标杆级，并行 TDD 验证降级严重 |
| 5 | 性能评估 | **7.0/10** | 1 | 2 | 2 | Token 总量 ~99K 可控，Phase 5 串行是主要瓶颈 |
| 6 | 竞品对比 | **3.75/5** | — | — | — | 质量保障全面领先，易用性/并行/Token 效率显著落后 |

**缺陷统计**: P0 共 **4** 个 | P1 共 **17** 个 | P2 共 **26** 个 | 总计 **47** 个

### 1.2 插件整体成熟度评级

**综合评分: 7.6 / 10** （六维度加权平均）

```
成熟度等级: PRODUCTION-READY WITH GAPS
               ████████████████████████░░░░░░  76%

强项: 门禁架构(9.0) | 崩溃恢复(8.5) | 规约服从(9.0) | 反偷懒(8.5)
弱项: 并行TDD(5.0) | 断言质量(4.5) | Token效率(7.0) | 易用性(5.0)
```

插件在"确定性质量保障"维度处于 Vibe Coding 生态领先地位，三层门禁 + 反合理化 + 崩溃恢复的组合独一无二。主要风险集中在：并行 TDD 模式的 Iron Law 形同虚设、测试反模式检测完全依赖 AI 自律、Token 经济性与竞品（Aider 126K vs 本插件 ~800K）差距悬殊。

---

## 2. 全维度评分总览

| 维度 | 评分 | 来源报告 | 核心发现 |
|------|:----:|---------|---------|
| 状态机正确性 | **9.0** | 稳定性 | 三种模式流转逻辑完全正确，分支覆盖全面 |
| Gate 系统有效性 | **8.5** | 稳定性 | 三层防御纵深完备，后台 Agent L2 绕过有文档记录 |
| 崩溃恢复 | **7.5** | 稳定性 | 整体完善，anchor_sha 恢复有缺口 |
| 需求理解深度 | **7.0** | Phase 1 | 10 步流程完整，模糊需求/迁移需求缺少特化处理 |
| 复杂度路由准确性 | **6.5** | Phase 1 | 过度依赖 total_files 单一维度 |
| 规约服从度 | **9.0** | Phase 5 | 扫描-注入-Hook 拦截闭环，CLAUDE.md 变更感知到位 |
| 反偷懒检测 | **8.5** | Phase 5 | 26 种模式中英双语，并行模式域 Agent 跳过 |
| 并行正确性 | **9.0** | Phase 5 | Union-Find + 文件所有权 + merge-guard + 降级策略 |
| TDD 串行纯洁度 | **9.5** | TDD | 主线程 Bash L2 验证，行业标杆 |
| TDD 并行纯洁度 | **5.0** | TDD | L2 降级为事后全量测试，Iron Law 形同虚设 |
| 断言质量保障 | **4.5** | TDD | 反模式文档优秀，无 Hook 确定性执行 |
| 测试金字塔 | **7.5** | TDD | 双层阈值架构合理，min_total_cases 偏低 |
| Token 经济性 | **7.0** | 性能 | 总预算 ~99K tokens，Reference 文件偏大 |
| 执行效率 | **6.0** | 性能 | Phase 5 串行是主要瓶颈，并行需手动启用 |
| Metrics 体系 | **6.0** | 性能 | 基本可用，缺少 Token 消耗和细粒度数据 |
| 竞品竞争力 | **3.75/5** | 竞品 | 质量保障领先，易用性/并行/Token 显著落后 |

---

## 3. 缺陷全景图

### 3.1 P0 级缺陷（阻断性 — 4 个）

| ID | 来源 | 缺陷描述 | 影响范围 | 根因分析 |
|----|------|---------|---------|---------|
| **P0-TDD-1** | TDD 审计 | 并行 TDD 无逐 task RED 阶段确定性验证。域 Agent 可先写实现再补测试，伪造 `red_verified: true`，L2 后置验证无法检出 | 并行 TDD 模式 | 后台 Agent 的 PostToolUse Hook 被 `is_background_agent && exit 0` 跳过，且主线程合并后仅做全量测试 |
| **P0-TDD-2** | TDD 审计 | `validate-json-envelope.sh` 不检查 `tdd_metrics` 字段。TDD 模式下 `tdd_metrics.red_violations === 0` 仅 L3 AI Gate 执行，无 L2 确定性兜底 | TDD 模式全局 | Hook 合并为 `post-task-validator.py` 时未包含 TDD 专属验证逻辑 |
| **P0-REQ-1** | Phase 1 | 缺少前置需求模糊度检测与强制澄清门槛。模糊需求（如"优化性能"）直接进入三路调研浪费大量 Token | 所有模式 | 流程设计假设需求总是"可调研的"，无信息量下限门槛 |
| **P0-PERF-1** | 性能 | Phase 5 串行模式每个 Task 同步阻塞，10 tasks = 10x 延迟。Phase 5 占全流程 ~51% 耗时 | full/lite/minimal 串行模式 | 串行模式未利用无依赖 task 的并行潜力 |

### 3.2 P1 级缺陷（重大 — 17 个）

| ID | 来源 | 缺陷描述 | 影响范围 |
|----|------|---------|---------|
| **P1-S1** | 稳定性 | lite/minimal 模式 Phase 5 任务拆分缺乏确定性保障，无 Hook 层前置验证 | lite, minimal |
| **P1-S2** | 稳定性 | minimal 模式无测试验证即进入归档，Phase 5->7 门禁不含 zero_skip_check | minimal |
| **P1-S3** | 稳定性 | 崩溃恢复时 anchor_sha 为空的处理逻辑在 recovery Skill 中缺失 | 全模式 |
| **P1-REQ-2** | Phase 1 | 缺少需求类型分类（新功能/改造/修复/优化）与差异化处理路径 | 全模式 |
| **P1-REQ-3** | Phase 1 | Auto-Scan 使用 Glob+Grep+Read 文本级扫描，无法理解代码逻辑和调用关系 | 存量改造场景 |
| **P1-CG-1** | Phase 5 | 并行模式域 Agent 跳过 anti-rationalization 检查（`is_background_agent && exit 0`） | 并行模式 |
| **P1-CG-2** | Phase 5 | python3 缺失时约束 Hook 静默放行（write-edit-constraint-check.sh, code-constraint-check.sh） | 无 python3 环境 |
| **P1-CG-3** | Phase 5 | brownfield-validation.md 默认状态描述与 gate SKILL.md 不一致 | 文档一致性 |
| **P1-TDD-3** | TDD | 测试反模式 Gate Function 无确定性执行，5 种反模式仅作为 AI 自查清单 | 全模式 |
| **P1-TDD-4** | TDD | 无断言内容质量静态分析，`expect(true).toBe(true)` 等恒真断言无法检测 | 全模式 |
| **P1-TDD-5** | TDD | Sad Path 覆盖无量化门禁，`test_counts` 不区分 Happy/Sad Path | 全模式 |
| **P1-TDD-6** | TDD | 突变测试不阻断归档，突变分数低仅在汇总表标红 | 全模式 |
| **P1-REQ-4** | Phase 1 | 跨模块需求缺少显式的接口契约推导步骤 | 跨模块需求 |
| **P1-REQ-5** | Phase 1 | 安全敏感需求没有专项威胁建模（STRIDE/OWASP） | 安全需求 |
| **P1-PERF-2** | 性能 | `phase1-requirements.md` 单文件 12,295 tokens，Phase 1 强制全量加载 | Token 效率 |
| **P1-PERF-3** | 性能 | 并行参考文档 `parallel-dispatch.md` + `parallel-phase-dispatch.md` 合计 ~12K tokens，内容重叠 | Token 效率 |
| **P1-COMP-1** | 竞品 | 易用性严重不足：237 行 YAML + 8 阶段概念，新用户上手 30min vs Superpowers 1min | 用户增长 |

### 3.3 P2 级缺陷（改进 — 26 个）

| ID | 来源 | 缺陷描述 |
|----|------|---------|
| P2-S1 | 稳定性 | 遗留脚本（validate-json-envelope.sh 等）与 post-task-validator.sh 功能重叠 |
| P2-S2 | 稳定性 | L2/L3 test_pyramid 阈值分层设计未在 protocol.md 中说明 |
| P2-S3 | 稳定性 | lite 模式 Summary Box 未展示跳过阶段说明 |
| P2-S4 | 稳定性 | minimal 模式 `get_predecessor_phase` fallback 分支语义不安全 |
| P2-S5 | 稳定性 | `scan-checkpoints-on-start.sh` 不感知执行模式 |
| P2-REQ-1 | Phase 1 | 复杂度路由过度依赖 total_files 单一维度 |
| P2-REQ-2 | Phase 1 | 多轮决策循环没有硬性轮数上限 |
| P2-REQ-3 | Phase 1 | business-analyst prompt 缺少迁移特化指令 |
| P2-REQ-4 | Phase 1 | `.autopilot-knowledge.json` 不覆盖存量代码结构知识 |
| P2-CG-1 | Phase 5 | parallel-merge-guard 使用正则解析 YAML 提取 typecheck 命令 |
| P2-CG-2 | Phase 5 | Brownfield 三向一致性检查缺少 Hook 级确定性保障 |
| P2-CG-3 | Phase 5 | rules-scanner.sh 无法提取自由文本约束 |
| P2-CG-4 | Phase 5 | 串行 TDD REFACTOR 回滚使用 `git checkout` 而非 `git stash` |
| P2-CG-5 | Phase 5 | `_constraint_loader.py` 的 CLAUDE.md 降级扫描模式较窄 |
| P2-TDD-1 | TDD | `min_test_count_per_type` 固定值不随变更规模调整 |
| P2-TDD-2 | TDD | Mock 策略无配置化控制，`test_suites` 无 `mock_policy` 字段 |
| P2-TDD-3 | TDD | `test-hooks.sh` 缺少 TDD 专属测试用例 |
| P2-TDD-4 | TDD | L2/L3 阈值差距过大（min_unit_pct: 30 vs 50） |
| P2-TDD-5 | TDD | `min_total_cases` 默认值偏低（L3: 20, L2: 10） |
| P2-PERF-1 | 性能 | v4.0 已合并的 Skill 文件未物理删除（~2.9K tokens 冗余） |
| P2-PERF-2 | 性能 | Dispatch 上下文膨胀，每次 ~10K tokens 注入 |
| P2-PERF-3 | 性能 | Metrics 缺少 Token 消耗追踪 |
| P2-PERF-4 | 性能 | Metrics 缺少 Hook 执行计时 |
| P2-PERF-5 | 性能 | Metrics 缺少 Context Compaction 次数计数 |
| P2-COMP-1 | 竞品 | Token 效率与 Aider（126K/任务）差距 6x |
| P2-COMP-2 | 竞品 | 仅支持 Claude Code 单平台，Cline/Cursor 多平台生态更广 |

---

## 4. 架构重构方案

### 4.1 Gate 系统加固

#### 4.1.1 TDD 并行验证盲区修复（P0-TDD-1, P0-TDD-2）

**现状问题**: 并行模式下域 Agent 以 `run_in_background: true` 运行，`is_background_agent && exit 0` 导致所有 L2 Hook 被跳过。TDD Iron Law 在并行模式下无确定性保障。

**重构方案 — 合并后 TDD 审计 Hook**:

```
并行域 Agent 完成
    ↓
主线程合并 worktree
    ↓
[新增] TDD 后置审计（主线程 Bash 执行）:
  1. 遍历每个 task 的 git commit 历史
  2. 验证第一个 commit 仅含测试文件（RED 证据）
  3. 验证第二个 commit 含实现文件（GREEN 证据）
  4. 验证 tdd_metrics.red_violations === 0
    ↓
全量测试验证
    ↓
写入 checkpoint
```

**实现要点**:
- 在 `post-task-validator.py` 中新增 Validator 6: TDD Metrics 检查
- 条件触发: `tdd_mode === true && phase === 5`
- 检查字段: `tdd_metrics` 存在 + `red_violations === 0`
- 同时在 `phase5-implementation.md` 并行模式章节增加合并后审计步骤

#### 4.1.2 Minimal 模式门禁补全（P1-S2）

**现状问题**: minimal 模式跳过 Phase 6，Phase 5->7 门禁不含 zero_skip_check。代码可能在没有任何测试验证的情况下归档。

**重构方案**: 双策略可配置

```yaml
# autopilot.config.yaml 新增
gates:
  minimal_mode:
    require_zero_skip: true  # 默认 true: minimal 也验证 zero_skip
    # false: 保持当前行为（纯极简模式）
```

- `require_zero_skip: true` 时，`check-predecessor-checkpoint.sh` 在 minimal 模式 Phase 5->7 门禁增加 zero_skip_check 验证
- 在 Phase 7 Summary Box 标注 `Testing: {passed|skipped} (minimal mode)`

#### 4.1.3 断言质量 Hook 新增（P1-TDD-3, P1-TDD-4）

**现状问题**: 5 种测试反模式的 Gate Function 仅作为 AI 自查清单，`expect(true).toBe(true)` 等欺骗性测试无确定性检出。

**重构方案**: 新增 `assertion-quality-check.sh` PostToolUse(Write|Edit) Hook

```
触发条件: 文件路径匹配 **/*.{test,spec}.{ts,js,py,java}
检测模式:
  - 恒真断言: expect(true), assert True, toBe(true)
  - 空断言: test/it 函数体无 expect/assert
  - Mock 自验证: mock.return_value 后仅断言相同值
  - 单断言测试: 整个测试文件仅 1 个 assert
阻断策略: 检出 >= 2 个模式时 block
```

### 4.2 Hook 体系强化

#### 4.2.1 反偷懒覆盖盲区修复（P1-CG-1）

**现状问题**: `anti-rationalization-check.sh` 对后台 Agent（`is_background_agent`）直接 exit 0。并行模式所有域 Agent 均为后台 Agent。

**重构方案**: 合并后批量反偷懒扫描

在主线程合并域 Agent 结果后、写入 Phase 5 checkpoint 前，增加步骤:

```
1. git diff ${ANCHOR_SHA}..HEAD -- 获取所有变更
2. 对 diff 内容执行简化 anti-rationalization 扫描
3. 检查 tasks_completed 数组完整性（是否覆盖该域所有 task）
4. 评分 >= 5 → 阻断，要求人工确认
```

#### 4.2.2 python3 硬前置条件（P1-CG-2）

**现状问题**: `write-edit-constraint-check.sh` 和 `code-constraint-check.sh` 在 python3 不可用时静默放行（exit 0），所有约束失效。

**重构方案**: Phase 0 环境检查增加 python3 验证

```bash
# autopilot-phase0 SKILL.md Step 2 新增
if ! command -v python3 &>/dev/null; then
    echo "[FATAL] python3 is required for Hook constraint checking"
    echo "Install: brew install python3 / apt install python3"
    exit 1
fi
```

工作量: ~10 行，Phase 0 SKILL.md + 对应检查脚本。

#### 4.2.3 崩溃恢复 anchor_sha 校验（P1-S3）

**现状问题**: Phase 0 Step 9 创建锁文件时 anchor_sha 为空，Step 10 创建后更新。如果在此间隙崩溃，recovery 不检查 anchor_sha 有效性。

**重构方案**: 在 `autopilot-recovery` SKILL.md 恢复流程末尾新增:

```
Step 6: Anchor SHA 验证
  1. 从锁文件读取 anchor_sha
  2. 空字符串 → 创建新锚定 commit 并更新锁文件
  3. 非空但 git rev-parse 失败 → 创建新锚定 commit 并更新锁文件
  4. 有效 → 继续使用
```

### 4.3 Token 经济性优化

#### 4.3.1 Reference 文件分层加载（P1-PERF-2, P1-PERF-3）

**现状问题**:
- `phase1-requirements.md` 单文件 12,295 tokens，Phase 1 强制全量加载
- `parallel-dispatch.md` + `parallel-phase-dispatch.md` 合计 ~12K tokens，内容重叠

**重构方案**:

| 文件 | 当前 Token | 重构策略 | 预期 Token |
|------|-----------|---------|-----------|
| `phase1-requirements.md` | 12,295 | 拆分为核心流程(~3K) + 详细补充(按需) | ~3,000 常驻 |
| `parallel-dispatch.md` + `parallel-phase-dispatch.md` | 12,081 | 合并为单一文档，按阶段索引 | ~8,000 |
| `autopilot-checkpoint/SKILL.md` + `autopilot-lockfile/SKILL.md` | 2,921 | 物理删除（已合入其他 Skill） | 0 |

**预期收益**: 主线程常驻 Token 减少 ~16K（从 ~88K 降至 ~72K），full 模式峰值占比从 44.2% 降至 ~36%。

#### 4.3.2 Dispatch 上下文紧凑化（P2-PERF-2）

**现状问题**: 每次 dispatch ~10K tokens，Phase 5 多 task 场景累积巨大。

**重构方案**: 路径引用替代内容注入

```
当前: dispatch prompt 中内联 project_context / test_suites / rules_scan 全文
优化: dispatch prompt 仅注入文件路径，子 Agent 按需 Read
      对 project_context: "Read ${change_dir}/context/project-context.md"
      对 test_suites: "Read .claude/autopilot.config.yaml 的 test_suites 节"
```

**预期收益**: 单次 dispatch 减少 ~2-3K tokens，Phase 5 串行 10 tasks 累计节省 ~20-30K tokens（跨子 Agent）。

#### 4.3.3 子 Agent 模型分级路由（P2-COMP-1）

**现状问题**: 全阶段同模型，~800K tokens/任务 vs Aider 126K。

**重构方案**: 引入 `subagent_type` 分级路由

```yaml
# dispatch 协议新增
subagent_routing:
  mechanical:    # Phase 2/3 OpenSpec, checkpoint 写入
    model: "general-purpose"    # 轻量模型
  analytical:    # Phase 1 调研, Phase 4 测试设计
    model: "default"            # 标准模型
  creative:      # Phase 5 实现, Phase 6 代码审查
    model: "default"            # 标准模型
```

**预期收益**: 机械性 Task（Phase 2/3/checkpoint）使用轻量模型，Token 消耗降低 20-30%。

### 4.4 Metrics 体系补全

#### 4.4.1 现有 Metrics 覆盖度

| 指标 | 状态 | 收集位置 |
|------|------|---------|
| 阶段状态 | 有 | `collect-metrics.sh` |
| 阶段耗时 | 有 | `_metrics.duration_seconds` |
| 重试统计 | 有 | `_metrics.retry_count` |
| Phase 6.5 代码审查 | 有 | 特殊处理 |
| **Token 消耗** | **缺失** | 无法统计 |
| **子 Agent 独立耗时** | **缺失** | 无记录 |
| **Hook 执行耗时** | **缺失** | 仅有 timeout |
| **Context Compaction 次数** | **缺失** | 未计数 |
| **Phase 5 task 级耗时** | **缺失** | 仅整体 |

#### 4.4.2 补全方案

**Wave 1（低成本）**:
- `_metrics` 中增加 `context_compactions` 计数器（`save-state-before-compact.sh` 每次触发 +1）
- Phase 5 task checkpoint 增加 `task_duration_seconds` 字段

**Wave 2（中成本）**:
- Hook 耗时采样: 每 N 次执行记录 `$(date +%s%N)` 差值到 `/tmp/.autopilot-hook-timing`
- `collect-metrics.sh` 末尾汇总 Hook 平均耗时

**Wave 3（高成本）**:
- Token 消耗追踪: 利用 Claude Code 回调日志估算（需 API 支持）
- 自适应上下文管理: 基于剩余窗口动态裁剪 Reference

### 4.5 需求分析增强

#### 4.5.1 前置模糊度检测（P0-REQ-1）

**在 Step 1.1 之后、Step 1.2 之前插入确定性检测步骤**:

```
Step 1.1.5: 需求信息量评估（主线程规则引擎）

维度检测:
  - 文本长度 < 20 字符 → flag: brevity
  - 不含技术名词 → flag: no_tech_entity
  - 不含量化指标 → flag: no_metric
  - 不含具体动词（创建/迁移/修复/集成）→ flag: vague_action

决策树:
  flags >= 3 → 强制"需求澄清预循环"（调研之前）
  flags >= 2 → 标记 requirement_clarity: "low"，调研 Agent 聚焦范围界定
  flags < 2  → 正常流程
```

**预期收益**: 避免在"优化性能"类模糊需求上浪费三路并行调研的 Token（估算节省 ~5K-10K tokens/次）。

#### 4.5.2 需求类型分类与差异化路径（P1-REQ-2）

**在模糊度检测之后插入分类步骤**:

```
Step 1.1.6: 需求类型分类（关键词规则引擎）

分类规则:
  含 "迁移/migrate/替换/升级" → type: migration
  含 "优化/性能/速度/latency"  → type: optimization
  含 "修复/fix/bug/defect"    → type: bugfix
  含 "新增/添加/创建/实现"     → type: new_feature
  含 "重构/refactor/清理"     → type: refactoring
  默认                        → type: new_feature

差异化注入:
  migration:     兼容性矩阵模板 + 回退计划模板 + 分阶段里程碑
  optimization:  性能基线采集指令 + 量化目标确认
  bugfix:        简化流程，跳过联网搜索，聚焦复现步骤
  refactoring:   简化流程，聚焦代码影响范围分析
  new_feature:   当前标准流程
```

#### 4.5.3 复杂度路由多维化（P2-REQ-1）

将单一 `total_files` 扩展为加权多维评分:

```
complexity_score = (
    total_files * 1.0
  + new_dependencies * 2.0
  + cross_module_boundaries * 3.0
  + schema_changes * 2.5
  + api_surface_changes * 2.0
  + security_sensitivity * 3.0
)

score <= 4  → small  (1 轮快速确认)
score <= 12 → medium (2-3 轮讨论)
score > 12  → large  (3+ 轮 + 苏格拉底模式)
```

---

## 5. Vibe Workflow 融合路径

### 5.1 当前底层能力盘点

spec-autopilot v4.0 已具备的编排能力构成 Vibe Workflow 的底层支撑:

| 能力层 | 已有实现 | 成熟度 |
|--------|---------|--------|
| **状态机引擎** | 8 阶段 Phase 0-7，三种模式（full/lite/minimal），确定性流转 | 生产级 |
| **门禁系统** | 3 层防御（TaskCreate + Hook + AI），特殊门禁，brownfield 验证 | 生产级 |
| **崩溃恢复** | Checkpoint + 锁文件 + PID 回收 + 上下文压缩恢复 + Phase 5 task 级恢复 | 生产级 |
| **并行调度** | Union-Find 依赖分析 + worktree 域分区 + merge-guard + 降级策略 | 生产级 |
| **子 Agent 编排** | Dispatch 协议 + JSON 信封契约 + 上下文隔离 + 规则注入 | 生产级 |
| **质量检测** | 反合理化 + 代码约束 + 测试金字塔 + 需求追溯 | 生产级 |
| **配置驱动** | YAML 配置 + 配置验证 + 配置自动生成 | 成熟 |
| **指标收集** | 阶段耗时 + 重试统计 + ASCII 可视化 | 基础 |

### 5.2 向上解耦设计

当前架构的最大瓶颈是**编排逻辑与 SKILL.md 文本强耦合**。要支撑 GUI 工具链，需要在编排层和展示层之间插入一个**事件总线 + 状态存储层**:

```
当前架构:
┌─────────────────────────────────────────┐
│  SKILL.md (编排逻辑 + 状态管理 + 展示)    │
│  → Phase 切换逻辑硬编码在 Markdown 中      │
│  → 进度通过 stdout 文本输出               │
│  → 状态通过 checkpoint JSON 文件持久化     │
└─────────────────────────────────────────┘

目标架构:
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│  展示层            │  │  展示层           │  │  展示层           │
│  Terminal UI      │  │  Web Dashboard   │  │  IDE Extension   │
│  (当前 stdout)    │  │  (v6.0 目标)      │  │  (v6.0+ 远景)    │
└────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘
         │                     │                      │
    ┌────┴─────────────────────┴──────────────────────┴────┐
    │                 事件总线 (Event Bus)                    │
    │  phase_started | phase_completed | gate_passed        │
    │  task_dispatched | task_completed | hook_triggered     │
    │  error_occurred | user_input_required                 │
    └────────────────────────┬─────────────────────────────┘
                             │
    ┌────────────────────────┴─────────────────────────────┐
    │              状态存储层 (State Store)                   │
    │  checkpoint JSON (已有) + 实时状态 JSON (新增)          │
    │  autopilot-live-state.json:                           │
    │    current_phase, current_task, progress_pct,         │
    │    gate_results[], hook_timings[], token_usage        │
    └────────────────────────┬─────────────────────────────┘
                             │
    ┌────────────────────────┴─────────────────────────────┐
    │              编排引擎 (Orchestration Engine)            │
    │  SKILL.md (Phase 逻辑) + Hook 脚本 + Gate Skill       │
    │  → 所有状态变更通过 Event Bus 发布                      │
    │  → 所有持久化通过 State Store 写入                      │
    └─────────────────────────────────────────────────────┘
```

**解耦要点**:

1. **事件标准化**: 定义 `autopilot-events.schema.json`，每个状态变更（Phase 开始/结束、Gate 通过/阻断、Task 派发/完成、Hook 触发/结果）都发布为结构化事件
2. **实时状态文件**: 新增 `autopilot-live-state.json`（补充现有 checkpoint 的静态快照），提供实时进度百分比、当前执行步骤、预计剩余时间
3. **展示层解耦**: 当前 stdout 格式化输出改为事件消费者模式，Terminal UI 作为默认消费者

### 5.3 GUI 工具链支撑架构

基于解耦后的事件总线，GUI 工具链的架构设计:

```
┌─────────────────────────────────────────────────────────────┐
│  Vibe Workflow Web Dashboard                                 │
│                                                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │ Pipeline  │  │ Gate     │  │ Metrics  │  │ History  │   │
│  │ Kanban    │  │ Monitor  │  │ Dashboard│  │ Timeline │   │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘   │
│       │              │              │              │          │
│  ┌────┴──────────────┴──────────────┴──────────────┴────┐   │
│  │              WebSocket Event Stream                   │   │
│  │  autopilot-live-state.json → SSE/WS push to browser  │   │
│  └──────────────────────┬───────────────────────────────┘   │
└─────────────────────────┼───────────────────────────────────┘
                          │
┌─────────────────────────┼───────────────────────────────────┐
│  Local Event Bridge     │                                    │
│                         │                                    │
│  fs.watch(autopilot-live-state.json)                        │
│  → parse event → broadcast via WS                           │
│  → aggregate metrics → write metrics-realtime.json          │
│                                                              │
│  技术选型: Node.js 轻量服务 (< 200 行)                       │
│  或 Claude Code MCP Server                                   │
└─────────────────────────────────────────────────────────────┘
```

**GUI 功能模块规划**:

| 模块 | 功能 | 数据源 | 优先级 |
|------|------|--------|--------|
| **Pipeline Kanban** | 8 阶段看板，实时状态卡片，Phase 5 task 进度条 | autopilot-live-state.json | 高 |
| **Gate Monitor** | 三层门禁实时状态，Pass/Block 可视化，历史记录 | gate 事件流 | 高 |
| **Metrics Dashboard** | 阶段耗时分布图、Token 消耗趋势、Hook 延迟热力图 | collect-metrics.sh 输出 + 实时采样 | 中 |
| **History Timeline** | 多次运行对比、回归分析、趋势线 | phase-results/ 历史数据 | 中 |
| **Config Editor** | YAML 可视化编辑器、校验反馈、一键重置 | autopilot.config.yaml | 低 |
| **Decision Replay** | Phase 1 决策过程回放、决策卡片存档 | phase-1-requirements.json | 低 |

### 5.4 可视化工作流设计

**Vibe Workflow 的核心理念**: 将 spec-autopilot 的编排能力从"开发者运行命令"转变为"拖拽式可视化工作流"。

#### 5.4.1 工作流编辑器

```
┌─────────────────────────────────────────────────────┐
│  Vibe Workflow Editor                                │
│                                                      │
│  [Phase 0] ──→ [Phase 1] ──→ [Phase 2] ──→ ...     │
│     │              │              │                   │
│     │         ┌────┴────┐   ┌────┴────┐             │
│     │         │ 3路并行  │   │ 后台    │              │
│     │         │ 调研    │   │ Agent   │              │
│     │         └─────────┘   └─────────┘              │
│                                                      │
│  [拖拽] 新增自定义阶段 | 修改门禁条件 | 配置并行度   │
│  [预览] 预估 Token 消耗 | 预估执行时间              │
└─────────────────────────────────────────────────────┘
```

**设计原则**:

1. **节点即阶段**: 每个 Phase 是一个可拖拽节点，节点属性面板展示配置项
2. **连线即门禁**: 节点间连线代表 Gate 检查，点击连线可编辑门禁条件
3. **模式即模板**: full/lite/minimal 是预置模板，用户可自定义阶段组合
4. **实时预估**: 修改工作流后实时显示 Token 预估和时间预估

#### 5.4.2 交互式决策面板

Phase 1 的多轮决策循环可视化:

```
┌─────────────────────────────────────────────────────┐
│  Decision Board — Phase 1 需求分析                    │
│                                                      │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │
│  │ 决策点 #1    │  │ 决策点 #2    │  │ 决策点 #3   │ │
│  │ JWT vs      │  │ OAuth 库    │  │ RBAC 粒度   │ │
│  │ Session     │  │ 选择        │  │             │ │
│  │ ✅ 已决策   │  │ 🔄 待决策   │  │ ⏳ 未讨论   │ │
│  └─────────────┘  └─────────────┘  └─────────────┘ │
│                                                      │
│  [复杂度评估: large] [当前轮次: 2/5] [苏格拉底模式]   │
│                                                      │
│  推荐方案: JWT + Passport.js + 角色级 RBAC           │
│  置信度: 85% | 数据支撑: 3 篇调研引用                 │
└─────────────────────────────────────────────────────┘
```

#### 5.4.3 渐进式采纳路径

```
Level 0 (当前): CLI + stdout 文本
    ↓ 零改造，仅增加事件发布
Level 1 (v5.0): CLI + 实时状态文件 + 简易 Web 监控页
    ↓ 轻量 Node.js bridge，< 200 行
Level 2 (v5.5): CLI + Web Dashboard (Pipeline + Gate + Metrics)
    ↓ React/Vue SPA，读取事件流
Level 3 (v6.0): 完整 Vibe Workflow Editor + Decision Board
    ↓ 可视化编排 + 拖拽配置
Level 4 (v6.0+): IDE Extension (VS Code / Cursor 侧边栏)
    ↓ MCP Server 集成
```

---

## 6. 实施路线图

### 6.1 v4.1 紧急修复（1-2 周）

**目标**: 修复所有 P0 缺陷 + 高优 P1 缺陷

| 优先级 | 任务 | 关联缺陷 | 工作量 | 预期收益 |
|--------|------|---------|--------|---------|
| 1 | `post-task-validator.py` 增加 TDD Metrics 检查 | P0-TDD-2 | 2h | TDD 模式 L2 确定性保障 |
| 2 | Phase 5 并行模式增加合并后 TDD 审计步骤 | P0-TDD-1 | 4h | 并行 TDD Iron Law 恢复效力 |
| 3 | Phase 0 增加 python3 硬前置检查 | P1-CG-2 | 1h | 约束 Hook 不再静默失效 |
| 4 | `autopilot-recovery` 增加 anchor_sha 校验 | P1-S3 | 2h | 崩溃恢复闭环 |
| 5 | brownfield-validation.md 默认值描述统一 | P1-CG-3 | 0.5h | 文档一致性 |
| 6 | minimal 模式 Phase 5->7 门禁增加 zero_skip_check | P1-S2 | 3h | minimal 质量保障 |
| 7 | `get_predecessor_phase` fallback 改为安全值 | P2-S4 | 0.5h | 防御性编程 |
| 8 | `scan-checkpoints-on-start.sh` 模式感知 | P2-S5 | 2h | 正确的 resume 建议 |
| 9 | 遗留脚本添加 DEPRECATED 注释 | P2-S1 | 0.5h | 维护清晰度 |
| 10 | 物理删除已合并 Skill 文件 | P2-PERF-1 | 0.5h | 清理 ~2.9K tokens |

**总工作量**: ~16 小时

### 6.2 v4.2 能力强化（3-4 周）

**目标**: 补全测试质量保障 + Token 优化 + 需求增强

| 优先级 | 任务 | 关联缺陷 | 工作量 | 预期收益 |
|--------|------|---------|--------|---------|
| 1 | 新增 `assertion-quality-check.sh` Hook | P1-TDD-3, P1-TDD-4 | 8h | 恒真断言确定性检出 |
| 2 | Phase 4 增加 Sad Path 计数字段 + Hook 检查 | P1-TDD-5 | 6h | 边界用例量化门禁 |
| 3 | `phase1-requirements.md` 分层拆分 | P1-PERF-2 | 4h | 减少 ~8K tokens 常驻占用 |
| 4 | 合并并行参考文档 | P1-PERF-3 | 4h | 减少 ~3-4K tokens |
| 5 | 需求模糊度检测 Step 1.1.5 | P0-REQ-1 | 6h | 避免模糊需求浪费 Token |
| 6 | 需求类型分类 Step 1.1.6 | P1-REQ-2 | 6h | 差异化处理路径 |
| 7 | 并行模式合并后反偷懒扫描 | P1-CG-1 | 6h | 并行模式反偷懒覆盖 |
| 8 | Dispatch 上下文紧凑化（路径引用替代内联） | P2-PERF-2 | 8h | 单次 dispatch 减少 ~2-3K tokens |
| 9 | Metrics 增加 context_compactions + task 级耗时 | P2-PERF-3, P2-PERF-5 | 4h | 可观测性 |
| 10 | 突变测试可选阻断配置 | P1-TDD-6 | 3h | 测试有效性最后防线 |
| 11 | L2/L3 阈值差距收窄 | P2-TDD-4 | 2h | 测试金字塔更严格 |
| 12 | `min_total_cases` 默认值提升 | P2-TDD-5 | 1h | 更合理的测试数量下限 |

**总工作量**: ~58 小时（约 1.5 人月）

### 6.3 v5.0 架构革新（6-8 周）

**目标**: 事件总线 + 状态存储 + 易用性突破 + 并行增强

| 模块 | 任务 | 工作量 | 预期收益 |
|------|------|--------|---------|
| **事件总线** | 定义 `autopilot-events.schema.json`，SKILL.md 中所有状态变更发布事件 | 2w | GUI 工具链基础 |
| **实时状态** | 新增 `autopilot-live-state.json`，提供实时进度/预估时间 | 1w | 实时监控基础 |
| **Web 监控** | Node.js Event Bridge + 简易 Web 监控页（Pipeline + Gate 状态） | 2w | Level 1 可视化 |
| **易用性** | minimal 极简化 3 步快速通道 + 智能默认配置（YAML <30 行） | 1w | 新用户 5min 上手 |
| **快速启动** | 新增 `autopilot-quickstart` Skill（交互式引导） | 1w | 零配置体验 |
| **并行增强** | Phase 5 无依赖 task 后台并行化（无需 worktree） | 1w | 串行模式耗时降 30-50% |
| **模型路由** | subagent_type 分级路由（mechanical/analytical/creative） | 1w | Token 消耗降 20-30% |
| **安全增强** | 安全敏感需求自动 STRIDE 威胁建模 | 0.5w | 安全需求专项分析 |

**总工作量**: ~9.5 人周

### 6.4 v6.0 Vibe Workflow（12+ 周）

**目标**: 完整可视化工作流平台

| 模块 | 任务 | 工作量 | 里程碑 |
|------|------|--------|--------|
| **Dashboard** | React/Vue SPA，Pipeline Kanban + Gate Monitor + Metrics Dashboard | 4w | M1: 可读 |
| **History** | 多次运行对比、趋势分析、回归检测 | 2w | M2: 可追溯 |
| **Workflow Editor** | 拖拽式阶段编排 + 门禁条件配置 + Token/时间预估 | 3w | M3: 可编排 |
| **Decision Board** | Phase 1 决策可视化 + 决策卡片存档 + 决策回放 | 2w | M4: 可审计 |
| **多平台** | 抽象 Task/Hook/SessionStart 适配层（CC -> Cursor -> Cline） | 3w | M5: 跨平台 |
| **企业级** | SSO/审计/权限控制/合规报告 | 4w | M6: 企业就绪 |
| **IDE 集成** | VS Code / Cursor 侧边栏 Extension（MCP Server） | 3w | M7: IDE 原生 |

**总工作量**: ~21 人周（约 5 人月）

### 路线图时间线总览

```
2026-Q1          2026-Q2              2026-Q3              2026-Q4
──────────────────────────────────────────────────────────────────→

v4.1 ████         v4.2 ████████████    v5.0 ██████████████████
紧急修复          能力强化              架构革新
(P0修复+         (测试质量+            (事件总线+
 高优P1)          Token优化+            Web监控+
                  需求增强)             易用性)

                                                    v6.0 ██████
                                                    Vibe Workflow
                                                    (Dashboard+
                                                     Editor+
                                                     多平台)
```

---

## 7. 风险与缓解策略

### 7.1 技术风险

| 风险 | 概率 | 影响 | 缓解策略 |
|------|:----:|:----:|---------|
| **Claude Code API 变更导致 Hook/Task 行为不兼容** | 高 | 高 | 维护 `test-hooks.sh` 回归测试套件，CI 中每次 Claude Code 更新自动验证 |
| **事件总线引入的性能开销** | 中 | 中 | 事件发布异步化，写入文件用批量刷新（每 500ms 或事件积累 10 个），非 autopilot 场景零开销 |
| **Web Dashboard 安全性（本地端口暴露）** | 中 | 中 | 仅监听 localhost，可选 auth token，生产环境通过反向代理 |
| **并行 TDD 审计的 git 历史分析准确性** | 中 | 低 | 允许 `--skip-tdd-audit` 配置降级，审计失败仅 warning 不 block（初期） |
| **Reference 文件拆分后子 Agent 按需加载的一致性** | 低 | 中 | 拆分后运行 `test-hooks.sh` 全量回归，Phase 1-7 端到端测试 |

### 7.2 产品风险

| 风险 | 概率 | 影响 | 缓解策略 |
|------|:----:|:----:|---------|
| **Superpowers 成为事实标准，侵蚀用户基础** | 高 | 高 | 互补策略: 集成 Superpowers TDD skills 作为 Phase 5 可选增强，而非正面竞争 |
| **Claude Code Auto Mode 侵蚀插件价值** | 高 | 高 | 强调"质量保障"而非"自动化"，Auto Mode 无门禁/无崩溃恢复/无反合理化 |
| **易用性改进不及时导致用户流失** | 高 | 中 | v5.0 优先实施快速启动和智能配置，目标新用户 5min 首次运行 |
| **Token 成本劣势导致商业化受限** | 中 | 高 | v4.2 优先实施 Dispatch 紧凑化和模型路由，目标 Token 降 30% |
| **多平台适配成本过高** | 中 | 中 | 先做抽象层设计（v5.0），按需实现: CC -> Cursor -> Cline |

### 7.3 组织风险

| 风险 | 概率 | 影响 | 缓解策略 |
|------|:----:|:----:|---------|
| **v4.1 修复延迟导致 P0 缺陷持续暴露** | 中 | 高 | v4.1 仅包含 P0 修复 + 关键 P1，控制范围在 16 小时内 |
| **v5.0/v6.0 需要前端能力但团队缺少** | 中 | 中 | v5.0 Web 监控用极简 HTML+WS（<200 行），不依赖前端框架；v6.0 考虑社区贡献 |
| **过度重构导致稳定性回归** | 低 | 高 | 每个 Wave 发布前运行 `test-hooks.sh` 全量回归 + 真实项目端到端验证 |

---

## 8. 结论

### 8.1 核心判断

spec-autopilot v4.0 已建立起 Vibe Coding 生态中**最完整的确定性质量保障体系**。三层门禁 + 反合理化 + 崩溃恢复 + 测试金字塔的组合壁垒，是任何竞品短期内无法复制的核心竞争力。

但 4 个 P0 缺陷（并行 TDD 验证空白、需求模糊度无门槛、Phase 5 串行瓶颈、TDD Metrics 无 L2 检查）和 17 个 P1 缺陷显示，系统在**执行层确定性覆盖**上仍有结构性盲区。尤其是：

1. **并行模式的质量保障降级过于激进** — `is_background_agent && exit 0` 一刀切跳过了所有 L2 Hook，反偷懒和 TDD 验证在并行模式下形同虚设
2. **测试质量保障停留在"数量"而非"质量"** — 有 test_counts 和 test_pyramid，但无断言质量、Sad Path 覆盖、反模式检测的确定性门禁
3. **Token 经济性和易用性是竞争力短板** — 与 Aider 6x 的 Token 差距和 Superpowers 30x 的上手时间差距，限制了用户增长

### 8.2 战略建议

1. **v4.1 聚焦 P0 修复**（1-2 周）: TDD Metrics L2 检查 + 并行 TDD 合并后审计 + python3 硬前置 + anchor_sha 恢复。这是最小化风险暴露的紧急措施。

2. **v4.2 补全质量闭环**（3-4 周）: 断言质量 Hook + Sad Path 门禁 + 需求模糊度检测 + Token 优化。这是从"数量保障"升级为"质量保障"的关键步骤。

3. **v5.0 架构解耦**（6-8 周）: 事件总线 + 实时状态 + 易用性突破。这是向 Vibe Workflow 演进的架构基础，也是吸引社区贡献的前提。

4. **v6.0 Vibe Workflow**（12+ 周）: 完整可视化平台 + 多平台支持。这是长期愿景，将 spec-autopilot 从"CLI 插件"升级为"质量驱动的 AI 交付平台"。

### 8.3 成功指标

| 里程碑 | 关键指标 | 目标值 |
|--------|---------|--------|
| v4.1 | P0 缺陷清零 | 0 个 P0 |
| v4.2 | 测试质量门禁覆盖率 | 断言质量 + Sad Path + 反模式全覆盖 |
| v4.2 | Token 消耗降幅 | -30%（从 ~99K 降至 ~70K） |
| v5.0 | 新用户首次运行时间 | < 5 分钟 |
| v5.0 | Phase 5 串行模式耗时降幅 | -40% |
| v6.0 | 支持平台数 | >= 3（CC + Cursor + VS Code） |
| v6.0 | 可视化工作流编辑器可用 | Pipeline + Gate + Metrics + Editor |

---

*本报告综合 6 份专项审计（稳定性/需求质量/代码生成/TDD 流程/性能评估/竞品对比）的全部发现，覆盖 47 个缺陷（4 P0 + 17 P1 + 26 P2），提出从 v4.1 到 v6.0 的四阶段演进路径。报告基于 v4.0.3 (commit 08d346f) 的静态分析，建议结合实际运行数据持续校准优先级。*
