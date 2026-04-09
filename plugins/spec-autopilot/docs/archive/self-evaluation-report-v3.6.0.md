# spec-autopilot 插件多维度自评报告 v3.6.0

> 评审日期：2026-03-12
> 插件版本：v3.6.0
> 代码规模：~12,300 行（含 9 Skills、18 脚本、17 references/templates）
> 评审范围：全部 SKILL.md、references、scripts、hooks.json、配置文档

---

## 评分总览

| # | 维度 | 评分 | 关键词 |
|---|------|------|--------|
| 1 | 生成速度与效率 | 3.5/5 | 并行设计精巧，Hook 开销可控，但 reference 加载链偏长 |
| 2 | 经济性（Token/成本控制）| 3.0/5 | 信封机制有效，但 SKILL.md + references 总量偏大 |
| 3 | AI 产出稳定性 | 4.5/5 | 三层门禁 + 确定性 Hook 体系业界领先 |
| 4 | 幻觉控制 | 4.0/5 | 测试验证闭环 + 反合理化检测覆盖关键场景 |
| 5 | 整体设计与架构 | 4.0/5 | 分层清晰、职责分明，复杂度已近临界 |
| 6 | 实现方案质量 | 3.5/5 | Python 模块化好，Shell 有重复模式，模板系统待成熟 |
| 7 | 对外部 Rules/记忆的遵守 | 4.0/5 | rules-scanner 自动扫描注入，对 CLAUDE.md 尊重度高 |
| 8 | 可持久记忆 | 3.5/5 | knowledge.json 框架完整，跨会话复用深度有限 |
| 9 | 可扩展性与易用性 | 3.0/5 | 配置复杂度高，Wizard 缓解有限，错误提示待改善 |

**综合评分：3.67 / 5**

---

## 维度 1：生成速度与效率

**评分：3.5 / 5**

### 1.1 8 阶段流水线的串行/并行设计

插件设计了清晰的 8 阶段流水线（Phase 0-7），整体为严格串行：每个 Phase 必须等待前驱 checkpoint 才能启动。这种设计保证了产出的确定性，但也意味着总延迟是各阶段之和。

**各阶段估算 Token 消耗**：

| Phase | 主要操作 | 估算 Token（输入+输出） | 时间估算 |
|-------|---------|----------------------|---------|
| 0 | 环境检查 + 配置加载 | ~5K | 10-30s |
| 1 | 需求讨论（含 3 路并行调研） | ~30-60K | 3-10min |
| 2 | OpenSpec 创建 | ~10-20K | 1-3min |
| 3 | FF 生成制品 | ~15-25K | 2-4min |
| 4 | 测试用例设计 | ~20-40K | 3-8min |
| 5 | 循环实施 | ~50-200K（视任务数） | 10-60min |
| 6 | 测试报告 + 代码审查 | ~15-30K | 3-10min |
| 7 | 汇总 + 归档 | ~10-15K | 1-3min |

**总估算**：full 模式一次完整流水线约 155-390K tokens，耗时 25-130 分钟。

### 1.2 并行执行效果分析

**Phase 1 三路并行**（Auto-Scan + 技术调研 + 联网搜索）：

- 优势：三者独立，并行效果接近理想（耗时约等于最慢的一个，而非三者之和）
- 约束：v3.2.1 强制要求在同一条消息中发起所有 Task，通过 `run_in_background: true` 实现真并行
- 实际收益：约节省 40-60% 的 Phase 1 调研时间

**Phase 4/5/6 并行**：

- Phase 4 按测试类型（unit/api/e2e/ui）并行，收益取决于测试种类数
- Phase 5 按域（backend/frontend/node）并行，是最大的效率杠杆——域间零依赖时可节省 60%+ 时间
- Phase 6 三路并行（测试执行 + 代码审查 + 质量扫描）设计巧妙，但路径 B/C 失败不阻断路径 A 的设计增加了复杂度

### 1.3 Hook 脚本性能影响

**多层 bypass 机制表现优秀**：

```
Layer 0: has_active_autopilot() — 纯 Bash，~1ms（无 python3 fork）
Layer 1: has_phase_marker() — grep 匹配，~1ms
Layer 1.5: is_background_agent() — grep 匹配，~1ms
```

非 autopilot 场景下，所有 6 个 PostToolUse Hook 在 Layer 0 即退出，总开销 ~6ms。autopilot 场景下命中完整链路时，每个 Hook 启动一次 python3（~50ms），6 个 PostToolUse Hook 最坏情况约 300ms。

**问题**：

- 每个 Hook 独立启动 python3 进程，`_envelope_parser.py` 和 `_constraint_loader.py` 被重复加载
- 建议：考虑 Hook 合并或守护进程模式，将 6 次 python3 fork 降为 1 次

### 1.4 子 Agent 调度开销

后台 Agent 化（v3.4.3）显著减少了主窗口上下文消耗：Phase 2/3/4/6 均使用 `run_in_background: true`。但每个 Task 调用本身有固定开销（prompt 注入、Skill 文件加载），估算单次 Task 创建开销约 2-5K tokens。

### 优势

- 多层 bypass 机制确保非 autopilot 场景零影响
- Phase 6 三路并行设计充分利用等待时间
- 后台 Agent 化减少主线程上下文膨胀

### 问题

- 阶段间严格串行，无法跨阶段流水线化（如 Phase 5 某些 task 完成后提前启动 Phase 6 测试）
- Hook 链 6 次 python3 fork 有优化空间
- reference 文件按需加载（"执行前读取"指令多达 15+ 处），每次加载消耗 Read 工具调用

---

## 维度 2：经济性（Token/成本控制）

**评分：3.0 / 5**

### 2.1 Prompt 大小分析

| 文件类型 | 数量 | 总行数 | 说明 |
|---------|------|--------|------|
| Skills（SKILL.md） | 9 | ~1,751 | 主编排器 351 行，最大 |
| References | 17 | ~3,654 | phase1-requirements 最大（722 行） |
| Templates | 4 | ~358 | 相对精简 |
| Scripts | 18 | ~5,990 | test-hooks.sh 占 2,725 行 |
| Python 模块 | 2 | ~365 | 共享模块 |

**核心问题**：autopilot SKILL.md（351 行）在每次主线程消息中都会被完整注入 Claude 上下文。加上 references 的按需加载，单次 Phase 切换时主线程上下文中的 prompt 指令可达 500-1000 行（约 10-20K tokens）。

### 2.2 SKILL.md 大小对调用的影响

主 SKILL.md（351 行）包含：

- 3 种执行模式的完整定义
- 8 个阶段的概要流程
- 30+ 条护栏约束
- 统一调度模板（7 步）
- 上下文压缩恢复协议

这是"一次加载，全程可用"的设计——好处是主线程无需在阶段间重新加载编排逻辑；坏处是无论当前处于哪个阶段，其他阶段的指令都占据上下文空间。

**建议**：考虑将护栏约束（30+ 条）拆分为独立 reference，仅在需要时加载。

### 2.3 References 加载策略

当前采用"执行前读取"策略——每个阶段启动时通过指令（如"**执行前读取**: `references/phase5-implementation.md`"）触发 AI 主动 Read。优势是按需加载、不浪费；问题是：

1. AI 可能忘记读取（依赖 prompt 遵从性）
2. Read 工具调用本身消耗 token（返回完整文件内容）
3. 部分 reference 较大（phase1-requirements.md 722 行、parallel-dispatch.md 465 行），单次 Read 即消耗 5-10K tokens

### 2.4 Model Routing 的实际效果

```yaml
model_routing:
  phase_1: heavy    # Opus
  phase_4: heavy    # Opus
  phase_5: heavy    # Opus
  phase_2: light    # Sonnet
  phase_3: light    # Sonnet
  phase_6: light    # Sonnet
  phase_7: light    # Sonnet
```

**当前限制**：Claude Code Task API 不支持 per-task model 参数，model_routing 仅作为行为引导注入（"高效模式"/"深度分析模式"）。实际效果完全依赖 prompt 引导质量，无法真正切换到低成本模型。

**如果 Claude Code 未来支持 model 参数**：Phase 2/3/6/7 使用 Sonnet 可节省 60-70% 成本（这 4 个阶段占总 token 的 ~30%）。

### 2.5 JSON 信封对 Token 节省的贡献

JSON 信封机制（v3.3.0 上下文保护增强）的核心思路是：

> 子 Agent 自行 Write 产出文件 + 返回精简 JSON 信封。主线程不读取全文，仅从信封提取 decision_points、summary 等关键字段。

这是整个插件最重要的 token 节省机制。以 Phase 1 为例：

- 无信封设计：Auto-Scan 输出 project-context.md（~5K tokens）+ research-findings.md（~3K）需全部灌入主线程
- 信封设计：仅 ~200 tokens 的 JSON 信封进入主线程

**估算节省**：每个子 Agent 调用节省 2-8K tokens，全流水线约节省 30-60K tokens。

### 优势

- JSON 信封机制显著降低主线程上下文消耗
- 后台 Agent 化避免子 Agent 输出污染主窗口
- 按需读取 references 避免不必要加载

### 问题

- 主 SKILL.md 351 行全程驻留，包含大量对当前阶段无关的指令
- model_routing 因 API 限制暂时无法真正降低成本
- reference 文件总量 3,654 行，部分文件过大
- 每次 Phase 切换约需 2-3 次 Read 工具调用加载 references

---

## 维度 3：AI 产出稳定性

**评分：4.5 / 5**

### 3.1 三层门禁体系

这是整个插件最核心的设计亮点，也是同类产品中罕见的系统性方案：

| Layer | 机制 | 执行者 | 确定性 |
|-------|------|--------|--------|
| L1 | TaskCreate blockedBy 依赖链 | 任务系统 | 100% 确定性 |
| L2 | 磁盘 checkpoint + Hook 脚本 | Shell/Python | 100% 确定性 |
| L3 | 8 步切换清单 + 特殊门禁 | AI（autopilot-gate Skill） | ~95%（依赖 AI 遵从） |

**L1 保障**：Phase 0 创建阶段任务时设置 blockedBy 依赖链（如 Phase 5 blockedBy Phase 4），这是 Claude Code 任务系统的原生能力，完全确定性阻止跳过。

**L2 保障**：`check-predecessor-checkpoint.sh` 作为 PreToolUse(Task) Hook，在子 Agent 派发前确定性验证前驱 checkpoint 存在且状态为 ok/warning。这是"fail-closed"设计——python3 不可用时直接 deny。

**L3 保障**：autopilot-gate Skill 执行 8 步清单 + Phase 4/5 特殊门禁。作为 AI 执行的检查，有 ~5% 的遵从风险，但被 L1+L2 兜底。

**整体评价**：三层递进、确定性递减的设计思路非常成熟。L1+L2 覆盖了所有可确定性验证的场景，L3 补充 AI 能力范围内的语义验证。即使 L3 失效，L1+L2 仍能阻止关键的阶段跳过和数据缺失。

### 3.2 反合理化检测

`anti-rationalization-check.sh` 是一个创新性的 Hook，通过加权模式匹配检测子 Agent 输出中的"合理化跳过"行为：

```
权重 3（高置信）：skip(ped|ping), deferred to, 跳过, 延后
权重 2（中置信）：out of scope, will be done later, 超出范围
权重 1（低置信）：already covered, not needed, 太复杂
```

**阈值设计合理**：

- 总分 >= 5：硬阻断
- 总分 >= 3 且无 artifacts：硬阻断（有跳过信号 + 无实际产出 = 高度可疑）
- 总分 >= 2：仅 stderr 警告（有产出则容忍轻微合理化）

**误报风险分析**：

- 低权重模式（"already covered"、"not necessary"）在正常技术讨论中常见，单独不触发阻断
- 高权重模式（"skipped because"）高度特异，误报风险低
- 中文模式覆盖双语场景，但"已跳过"在正常进度报告中可能出现

**覆盖面**：仅对 Phase 4/5/6（实施核心阶段）触发，Phase 2/3（文档生成）不触发，设计合理。

### 3.3 代码约束检测可靠性

双层检测机制：

1. `code-constraint-check.sh`（PostToolUse/Task）：检查子 Agent 返回的 artifacts 列表
2. `write-edit-constraint-check.sh`（PostToolUse/Write|Edit）：直接拦截文件写入操作

**约束来源优先级**：config.yaml code_constraints > CLAUDE.md 禁止项 > 无约束放行

**可靠性评估**：

- 文件名匹配和目录范围检查是确定性的
- 文件行数检查依赖 `wc -l`，确定性
- 内容模式匹配使用 `re.search(re.escape(pat))`，对字面量模式确定性，但不支持 regex 模式

### 3.4 JSON 信封解析的鲁棒性

`_envelope_parser.py` 的 3 策略解析设计优秀：

```
Strategy A: raw_decode 扫描所有 '{' 位置
  - Pass 1: 优先匹配 status + summary 的完整信封
  - Pass 2: 降级到仅含 status 的信封
Strategy B: 代码块提取 (```json ... ```)
Strategy C: 整体解析
```

**鲁棒性优势**：

- 即使子 Agent 在 JSON 前后输出了额外文本，Strategy A 仍能提取
- 即使子 Agent 用 markdown 代码块包裹 JSON，Strategy B 仍能提取
- 两遍扫描（Pass 1/2）避免了多个 JSON 对象时选错的问题

**已知风险**：

- 如果子 Agent 输出多个含 status 字段的 JSON 对象，取第一个含 summary 的——极端场景下可能误选
- 大输出（>100KB）时 raw_decode 逐字符扫描有性能开销

### 3.5 Phase 流转确定性

**跳过风险**：极低。L1（blockedBy）+ L2（checkpoint 文件检查）双重确定性阻断，加上 L2 的模式感知（full/lite/minimal 不同阶段序列），误跳过概率趋近于零。

**乱序风险**：极低。`check-predecessor-checkpoint.sh` 硬编码了每种模式的前驱映射关系（full: N-1, lite: 1->5->6->7, minimal: 1->5->7），不依赖 AI 判断。

**状态回退风险**：中低。checkpoint 文件一旦写入状态为 ok，无逻辑删除或覆盖。但如果 checkpoint 文件因系统故障损坏（JSON 解析失败），`read_checkpoint_status` 返回 "error"，L2 会视为阻断而非放行——这是 fail-closed 设计。

### 优势

- 三层门禁体系是同类系统中最完善的设计
- 确定性从 L1 到 L3 递减、覆盖面递增，层层兜底
- 反合理化检测是创新性的 AI 治理手段
- JSON 信封 3 策略解析鲁棒性极高
- 所有 Hook 脚本遵循 fail-closed 原则

### 问题

- L3（AI 执行的门禁）依赖 prompt 遵从性，无法 100% 保证
- 反合理化检测的中文模式在正常报告中有小概率误报
- Phase 4 的 warning 不接受规则仅在 L2 Hook 中强制，如果 Hook 被绕过则 L3 需要补位

---

## 维度 4：幻觉控制

**评分：4.0 / 5**

### 4.1 各阶段幻觉防护

| Phase | 幻觉风险 | 防护机制 |
|-------|---------|---------|
| 1 | 需求理解偏差 | 多轮决策 LOOP + AskUserQuestion 强制人类确认 |
| 2-3 | 虚构 OpenSpec 内容 | 基于 Phase 1 确认的需求，减少自由发挥空间 |
| 4 | 虚构测试用例 | dry_run_results 全 0 验证 + test_traceability 追溯需求 |
| 5 | 实现不符合设计 | 每 task typecheck/unit 快速验证 + Phase 5→6 zero_skip 门禁 |
| 6 | 虚报测试结果 | 实际运行测试命令 + pass_rate 从真实输出提取 |

### 4.2 测试验证的纠偏能力

Phase 4 要求 `dry_run_results` 全部为 0（所有测试的 exit code 为 0），这意味着测试必须实际运行通过，而非 AI 声称通过。Phase 5 的 zero_skip_check 和全量测试进一步验证。

Phase 5 串行模式中，每个 task 完成后运行 typecheck + unit 测试，形成"写代码 -> 立即验证"的紧反馈循环。TDD 模式更进一步：主线程 Bash() 独立运行测试验证 RED 失败/GREEN 通过，完全不信任子 Agent 的自我报告。

### 4.3 需求追溯的约束力

`test_traceability` 字段要求每个测试用例追溯到 Phase 1 的需求点。虽然目前是 recommended 字段（非 blocking），但其存在迫使 AI 在设计测试时考虑需求覆盖面，而非凭空生成测试。

建议：将 test_traceability 覆盖率 >= 80% 升级为 L2 blocking 条件。

### 4.4 Brownfield 验证的漂移检测

`brownfield_validation` 在 Phase 4->5、Phase 5->6 切换点进行三向一致性检查（设计-测试-实现），是检测 AI"认为自己实现了需求但实际偏离"的有效手段。

**当前状态**：默认关闭（`enabled: false`），需手动开启。对于存量项目，这是必要的安全网，建议默认开启。

### 优势

- TDD 模式的 L2 确定性验证（主线程 Bash()）是最强的幻觉防护
- 测试实际运行 + exit code 验证杜绝了"声称通过"的幻觉
- 多轮决策 LOOP 让人类参与关键决策
- Phase 4 dry_run_results 全 0 是高确定性要求

### 问题

- test_traceability 仅为 recommended，未强制执行
- brownfield_validation 默认关闭
- Phase 2/3（OpenSpec）的幻觉防护较弱（无实际验证步骤，依赖 AI 忠实转化需求）
- 语义验证（semantic-validation.md）为 AI 软检查，非确定性

---

## 维度 5：整体设计与架构

**评分：4.0 / 5**

### 5.1 两层架构评估

插件使用 Plugin/Project 两层架构：

- **Plugin 层**：Skills + Hooks + Scripts，提供通用编排能力
- **Project 层**：`.claude/autopilot.config.yaml`，提供项目特定配置

这种设计的优势是一套插件适配多种项目，配置可版本化管理。劣势是两层之间的接口面（config schema）必须非常稳定，任何 schema 变更都需要向后兼容。

### 5.2 Skill 拆分评估

9 个 Skills 的粒度分析：

| Skill | 职责 | 合理性 |
|-------|------|--------|
| autopilot | 主编排器 | 核心，合理 |
| autopilot-phase0 | 环境初始化 | 合理，隔离启动逻辑 |
| autopilot-phase7 | 汇总归档 | 合理，隔离收尾逻辑 |
| autopilot-gate | 门禁验证 | 合理，职责清晰 |
| autopilot-dispatch | 子 Agent 调度 | 合理，但与主 SKILL.md 有功能重叠 |
| autopilot-recovery | 崩溃恢复 | 合理 |
| autopilot-checkpoint | 状态持久化 | 偏薄（126 行），可考虑合并到 gate |
| autopilot-lockfile | 锁文件管理 | 偏薄（124 行），为解决 Write 前置 Read 限制而存在 |
| autopilot-setup | 配置初始化 | 合理，独立使用场景 |

**总体评价**：拆分粒度基本合理，但 checkpoint（126 行）和 lockfile（124 行）两个 Skill 偏薄，它们的存在更多是为了工程约束（后台 Agent 封装 Write 流程）而非功能粒度。

### 5.3 Hook 系统设计

11 个 Hook 脚本的分类：

| 分类 | Hook | 数量 |
|------|------|------|
| PreToolUse(Task) | check-predecessor-checkpoint | 1 |
| PostToolUse(Task) | validate-json-envelope, anti-rationalization-check, code-constraint-check, parallel-merge-guard, validate-decision-format | 5 |
| PostToolUse(Write\|Edit) | write-edit-constraint-check | 1 |
| PreCompact | save-state-before-compact | 1 |
| SessionStart | scan-checkpoints-on-start, check-skill-size, reinject-state-after-compact | 3 |

**设计优势**：

- 每个 Hook 职责单一，可独立测试
- 多层 bypass 机制确保性能（3 层快速退出）
- 共享 `_common.sh` + `_envelope_parser.py` + `_constraint_loader.py` 减少重复

**设计问题**：

- 5 个 PostToolUse(Task) Hook 串行执行，每个启动独立 python3 进程
- hooks.json 中 PostToolUse 的 Task matcher 重复定义 5 次，缺乏分组能力
- parallel-merge-guard 的超时设为 150s（其他 30s），因为包含 typecheck 执行

### 5.4 配置驱动的灵活性 vs 复杂度

config-schema.md 定义了 ~240 行的 YAML 模板，包含 60+ 可配置字段。

**灵活性**：极高。从执行模式、门禁阈值、测试金字塔比例、并行策略、TDD 开关到模型路由，几乎所有行为都可配置。

**复杂度**：偏高。新用户面对 60+ 字段的配置文件时认知负担重。虽然 autopilot-setup 的 Interactive Wizard（3 个预设模板）缓解了首次配置的门槛，但后续调优仍需理解大量字段间的交互关系（如 `test_pyramid.hook_floors` vs `test_pyramid.min_unit_pct` 的双层阈值）。

### 5.5 崩溃恢复完整性

崩溃恢复设计覆盖了以下场景：

| 场景 | 恢复策略 |
|------|---------|
| 进程崩溃 | checkpoint 扫描 + 从最后 ok 阶段恢复 |
| 上下文压缩 | PreCompact 保存状态 + SessionStart(compact) 注入恢复 |
| Phase 5 task 级崩溃 | phase5-tasks/ 目录扫描 + 从最后完成 task 恢复 |
| TDD 步骤级崩溃 | tdd_cycle 字段确定 RED/GREEN/REFACTOR 恢复点 |
| 锁文件残留 | PID + session_id 双重检测，自动覆盖死锁 |

**不足**：

- 无法恢复到"阶段内部的某个步骤"（如 Phase 1 的第 6 轮讨论）
- 上下文压缩恢复依赖 `autopilot-state.md` 文件的完整性

### 优势

- 三层门禁架构是同类产品中最系统化的设计
- 崩溃恢复覆盖到 task 级甚至 TDD 步骤级
- 配置驱动设计支持极高的定制化
- Skill 拆分使得职责边界清晰

### 问题

- 系统复杂度已近临界——9 Skills + 18 Scripts + 17 References 的交互矩阵难以全面测试
- 配置字段过多（60+），交叉引用验证覆盖不完整
- 部分 Skill 过薄（checkpoint 126 行、lockfile 124 行）

---

## 维度 6：实现方案质量

**评分：3.5 / 5**

### 6.1 Shell 脚本代码质量

**重复模式**：所有 PostToolUse Hook 脚本的前 40 行几乎完全相同：

```bash
STDIN_DATA=$(cat)
[ -z "$STDIN_DATA" ] && exit 0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
PROJECT_ROOT_QUICK=$(echo "$STDIN_DATA" | grep -o '"cwd"...' | ...)
has_active_autopilot "$PROJECT_ROOT_QUICK" || exit 0
has_phase_marker || exit 0
is_background_agent && exit 0
```

这段 ~15 行的 boilerplate 在 6 个 Hook 脚本中重复，总计 ~90 行冗余。建议提取为 `_hook_preamble.sh` 函数。

**可维护性**：

- `_common.sh`（148 行）提供了良好的共享基础设施
- 但 `check-predecessor-checkpoint.sh`（372 行）过长，混合了模式感知、TDD 检测、wall-clock 超时等多重职责
- `validate-config.sh`（292 行）包含完整的 Python YAML 验证逻辑，嵌入在 bash heredoc 中——可维护性差

**跨平台**：`_common.sh` 中的 `stat` 命令已处理 Darwin/Linux 差异，但 `find` 命令的行为差异未全面处理。

### 6.2 Python 辅助脚本设计

`_envelope_parser.py`（190 行）和 `_constraint_loader.py`（175 行）的设计质量较高：

- 函数粒度合理，职责单一
- 有完整的 docstring
- 错误处理采用 try/except + 安全降级
- PyYAML 优先 + regex fallback 的双策略配置读取

**改进空间**：

- `read_config_value` 的 regex fallback 对嵌套 YAML 的支持有限（不支持列表、多行字符串）
- `_constraint_loader.py` 从 CLAUDE.md 提取禁止项的 regex 模式过于特殊化（仅匹配中文"禁"字相关模式）

### 6.3 Prompt Engineering 质量

**主 SKILL.md 的 prompt 设计**：

- 使用 markdown 表格和代码块使结构清晰
- 明确标注"执行前读取"指令引导 AI 按需加载 reference
- 护栏约束以表格形式列出，覆盖面广
- "HARD CONSTRAINT"、"禁止"等强语气标记有效传达优先级

**Dispatch Prompt 模板**：

- 模板变量替换设计合理（`{config.services}` 等占位符）
- 优先级表（7 层注入）确保信息不遗漏
- 子 Agent 前置校验指令（检查前驱 checkpoint）是双重保险

**不足**：

- 部分指令过于冗长（如 Phase 5 路径 A/B/C 的互斥描述占 ~100 行），增加 AI 理解负担
- "禁止"类指令多达 20+，部分可能被 AI 忽略（注意力稀释效应）

### 6.4 References 组织

17 个 reference 文件按功能分组较清晰：

- 核心协议：protocol.md, config-schema.md
- 阶段详情：phase1-requirements.md, phase5-implementation.md, phase6-code-review.md
- 并行编排：parallel-dispatch.md, parallel-phase-dispatch.md
- 补充协议：knowledge-accumulation.md, brownfield-validation.md, semantic-validation.md, tdd-cycle.md, testing-anti-patterns.md

**问题**：parallel-dispatch.md（465 行）和 parallel-phase-dispatch.md（457 行）有较多内容重叠，建议合并或明确分工。

### 6.5 模板系统

4 个模板文件（phase4-testing.md, phase5-serial-task.md, phase6-reporting.md, shared-test-standards.md）总计 358 行，相对精简。

模板系统的设计采用"config.phases[phase].instruction_files 非空则覆盖，为空则使用内置模板"，这是良好的扩展点设计。但模板变量替换在 AI 层面执行（无编译期检查），拼写错误只能在运行时发现。

### 优势

- Python 共享模块（_envelope_parser.py, _constraint_loader.py）设计质量高
- Prompt 结构清晰，使用表格和代码块增强可读性
- 模板的"内置 + 覆盖"设计支持灵活定制

### 问题

- Shell 脚本有 ~90 行 boilerplate 重复
- check-predecessor-checkpoint.sh 过长（372 行），职责不够单一
- validate-config.sh 中 Python 嵌入 bash heredoc 可维护性差
- parallel-dispatch.md 和 parallel-phase-dispatch.md 内容重叠
- 模板变量替换无编译期检查

---

## 维度 7：对外部 Rules 和记忆的遵守性

**评分：4.0 / 5**

### 7.1 与 CLAUDE.md 的交互

插件通过两个层面与项目 CLAUDE.md 交互：

1. **rules-scanner.sh**：自动扫描 `.claude/rules/` 和 `CLAUDE.md`，提取禁止项、必须项、命名约定，注入子 Agent prompt
2. **_constraint_loader.py**：从 CLAUDE.md 提取禁止文件/模式作为 code_constraints 的 fallback 来源

**优势**：这种自动扫描 + 注入的设计意味着项目规则无需手动同步到 autopilot 配置中，减少了维护负担。

**不足**：

- rules-scanner.sh 的规则提取基于关键词匹配（"禁止"、"必须"等），对英文 CLAUDE.md 的支持不如中文
- 扫描结果在 Phase 0 缓存后全程复用——如果用户在 autopilot 运行中修改了 CLAUDE.md，本次运行不会感知

### 7.2 .autopilot-knowledge.json 知识系统

位于 `openspec/.autopilot-knowledge.json`，设计为跨 change 共享的知识库：

- **4 种知识类型**：pattern, decision, pitfall, optimization
- **分级置信度**：high, medium, low
- **自动淘汰**：FIFO 200 条上限，low confidence 优先淘汰
- **关键词匹配注入**：Phase 1 从需求中提取关键词，匹配 top-5 历史知识注入

设计完整度较高，但实际效果取决于：

1. Phase 7 知识提取的准确性（AI 执行，非确定性）
2. 关键词匹配的召回率（简单关键词匹配可能遗漏语义相关的知识）

### 7.3 对 Claude Code 原生能力的利用

| 原生能力 | 利用程度 | 说明 |
|---------|---------|------|
| Task/Agent API | 深度利用 | 核心调度依赖 Task 工具 |
| Hooks（PreToolUse/PostToolUse/PreCompact/SessionStart） | 深度利用 | 11 个 Hook 脚本覆盖 4 种 Hook 类型 |
| AskUserQuestion | 深度利用 | 多轮决策、确认归档等 |
| Worktree 隔离 | 适度利用 | Phase 5 并行模式使用 |
| Plan Mode | 未利用 | 可考虑 Phase 2/3 使用 Plan agent |
| Memory (auto-memory) | 未利用 | 插件不读写 Claude auto-memory |
| MCP | 未利用 | 无 MCP 集成 |

### 7.4 对项目 .claude/ 配置的尊重

- 配置文件放置在 `.claude/autopilot.config.yaml`，遵守 Claude Code 的项目配置目录约定
- 锁文件放置在 `openspec/changes/.autopilot-active` 并 gitignore，不污染项目配置
- Phase 0 检查 `.claude/settings.json` 的 enabledPlugins

### 优势

- rules-scanner 自动扫描 + 注入是高效的规则尊重机制
- 配置文件遵守 .claude/ 目录约定
- 对 Claude Code Hook API 的利用深度业界领先

### 问题

- 运行中 CLAUDE.md 变更不被感知
- 未利用 Claude Code auto-memory 进行跨会话记忆
- Plan Mode 和 MCP 能力未利用

---

## 维度 8：可持久记忆

**评分：3.5 / 5**

### 8.1 Knowledge Accumulation 系统

知识框架设计完整：

```
写入（Phase 7）：
  - 从 checkpoint 提取 decisions → decision 类知识
  - 从 retry_count > 0 提取 → pitfall 类知识
  - 从 code review findings 提取 → pattern 类知识
  - 从 _metrics 提取 → optimization 类知识

读取（Phase 1）：
  - 关键词匹配 RAW_REQUIREMENT vs entries[].tags + summary
  - Top-5 注入 project-context.md 和 business-analyst prompt
```

### 8.2 跨会话经验存储和读取

**存储**：JSON 文件格式，支持 git 版本管理和团队共享。200 条上限 + FIFO 淘汰策略。

**读取**：基于关键词的 top-5 匹配。

**局限**：

1. 关键词匹配是浅层语义匹配，无法捕捉"不同表述但语义相同"的知识复用
2. 知识条目的 detail 限制 500 字符，对于复杂的技术决策可能信息量不足
3. 200 条上限对于大型项目（数十个 change）可能不够

### 8.3 Steering Documents 持久化

`openspec/.autopilot-context/` 存储跨 change 共享的项目上下文，7 天缓存策略避免重复全量扫描。这是对 knowledge.json 的补充——knowledge.json 存储离散知识点，Steering Documents 存储整体项目理解。

### 8.4 对比行业最佳实践

**与 Cursor Instincts 系统对比**：

| 维度 | Cursor Instincts | spec-autopilot Knowledge |
|------|-----------------|-------------------------|
| 触发时机 | 每次交互自动提取 | 仅 Phase 7 显式提取 |
| 知识粒度 | 细粒度偏好 | 粗粒度决策/模式/陷阱 |
| 匹配方式 | 语义相似度 | 关键词匹配 |
| 存储位置 | 平台侧 | 项目本地 JSON 文件 |
| 团队共享 | 不支持 | 支持（git 版本管理） |
| 淘汰策略 | 按使用频率 | FIFO + confidence 分级 |

**spec-autopilot 的优势**：团队共享（通过 git）、显式可编辑（用户可直接修改 JSON）。
**spec-autopilot 的劣势**：提取频率低（仅 Phase 7）、匹配精度低（关键词 vs 语义）。

### 优势

- 知识框架设计完整（4 类型、3 置信度、自动淘汰）
- Steering Documents 持久化避免重复扫描
- 团队共享能力（通过 git 管理 knowledge.json）

### 问题

- 知识提取仅在 Phase 7，频率过低
- 关键词匹配无法捕捉语义相似性
- 200 条上限对大型项目可能不足
- 未利用 Claude Code auto-memory 进行会话级记忆

---

## 维度 9：可扩展性与易用性

**评分：3.0 / 5**

### 9.1 新用户上手门槛

**首次使用路径**：

1. 安装插件
2. 运行 `/autopilot <需求>` → 自动触发 autopilot-setup
3. init Wizard 提供 3 个预设（Strict/Moderate/Relaxed）
4. 自动检测项目结构 + 用户确认 → 生成配置
5. 继续执行 autopilot 流水线

**门槛评估**：

- 首次使用：Wizard + 自动检测降低了门槛，约 3-5 分钟可开始（评分 4/5）
- 配置调优：需理解 60+ 字段及其交互关系，文档分散在 config-schema.md 和 configuration.md（评分 2/5）
- 故障排查：Hook 脚本的 stderr 输出提供了一定的可观察性，但需要 Ctrl+O verbose mode 才能看到（评分 2.5/5）

### 9.2 配置复杂度

60+ 配置字段分布在 7 个顶级 section 中。虽然大部分有合理默认值，但某些字段间的交互关系隐晦：

- `test_pyramid.min_unit_pct` vs `test_pyramid.hook_floors.min_unit_pct`：双层阈值概念不直观
- `phases.implementation.parallel.enabled` + `tdd_mode` + `worktree.enabled` 的组合矩阵有多种合法状态
- `model_routing` 当前无实际效果（API 限制），但占据配置空间

### 9.3 错误提示友好度

**Hook 脚本的错误信息**：

```json
{"decision": "block", "reason": "Phase 4 test_pyramid floor violation (Layer 2): unit_pct=20% < 30% floor"}
```

技术性强、准确，但对非技术用户不友好。缺少：

- 修复建议（"建议增加 X 个单元测试"）
- 上下文链接（指向文档的哪个章节）
- 中英文适配（当前主要为英文，但项目语境为中文）

**validate-config.sh 的输出**：

```json
{"valid": false, "missing_keys": ["phases.testing.agent"], "type_errors": [], "range_errors": [], "cross_ref_warnings": []}
```

结构化输出好，但缺少人类友好的修复指导。

### 9.4 文档完整度

| 文档 | 状态 |
|------|------|
| configuration.md | 完整的字段参考 |
| config-schema.md | 完整的 YAML 模板 + schema 验证规则 |
| SKILL.md（各 Skill） | 完整的协议定义 |
| references/ | 完整的阶段详情和并行编排协议 |
| 快速入门指南 | **缺失** |
| 架构总览图 | **缺失** |
| 常见问题排查 | **缺失** |
| 配置调优指南 | **缺失** |

### 优势

- Interactive Wizard 降低首次使用门槛
- 3 个预设模板（Strict/Moderate/Relaxed）覆盖常见场景
- LSP 插件自动推荐提升开发体验
- 配置字段有 validate-config.sh 自动校验

### 问题

- 缺少快速入门指南和架构总览图
- 60+ 配置字段的调优需要深入理解系统
- Hook 错误信息缺少修复建议和中文支持
- 缺少常见问题排查文档
- test-hooks.sh（2,725 行）是测试脚本，但没有对应的 CI 集成文档

---

## 改进建议优先级

### P0（高优先级）

1. **Hook 脚本 boilerplate 提取**：将 ~15 行重复前言提取为 `_hook_preamble.sh`，减少 ~90 行冗余
2. **快速入门指南**：编写 1 页的 getting-started.md，覆盖安装 -> 首次运行 -> 配置调优
3. **test_traceability 升级为 blocking**：Phase 4 的需求追溯覆盖率应从 recommended 升级为 L2 blocking

### P1（中优先级）

1. **Hook 合并/守护进程**：将 5 个 PostToolUse(Task) Hook 合并为 1 个，减少 5 次 python3 fork 为 1 次
2. **SKILL.md 瘦身**：将 30+ 护栏约束拆分为 `references/guardrails.md`，主 SKILL.md 仅保留流水线逻辑
3. **brownfield_validation 默认开启**：对存量项目的设计-实现漂移检测应默认开启
4. **parallel-dispatch.md 和 parallel-phase-dispatch.md 合并**：消除内容重叠
5. **错误信息增强**：添加修复建议和文档链接到 Hook 阻断消息

### P2（低优先级）

1. **知识匹配升级**：从关键词匹配升级为 embedding 语义匹配（需要外部服务）
2. **Claude Code auto-memory 集成**：在 Phase 7 将关键知识写入 auto-memory
3. **model_routing 实际化**：待 Claude Code Task API 支持 model 参数后实现真正的模型切换
4. **架构总览图**：生成 mermaid 格式的系统架构图

---

## 附录

### A. 文件规模统计

| 分类 | 文件数 | 总行数 |
|------|--------|--------|
| Skills (SKILL.md) | 9 | 1,751 |
| References | 13 | 3,082 |
| Templates | 4 | 358 |
| Shell Scripts | 18 | 5,990 |
| Python Modules | 2 | 365 |
| Hooks Config | 1 | 120 |
| Documentation | 1 | 296 |
| **总计** | **48** | **11,962** |

> 注：References 不含 tdd-cycle.md 和 testing-anti-patterns.md（标记为新增未合入文件）。

### B. Hook 执行时序

```
非 autopilot 场景：
  PostToolUse(Task) × 5 → Layer 0 bypass (has_active_autopilot=false) → exit 0
  总耗时：~6ms

autopilot 场景（Phase 5 Task）：
  PreToolUse(Task)   → check-predecessor-checkpoint   → ~100ms (python3 fork)
  PostToolUse(Task)  → validate-json-envelope          → ~80ms
  PostToolUse(Task)  → anti-rationalization-check      → ~80ms
  PostToolUse(Task)  → code-constraint-check           → ~80ms
  PostToolUse(Task)  → parallel-merge-guard            → ~80ms (或 150s 含 typecheck)
  PostToolUse(Task)  → validate-decision-format        → ~3ms (Phase 5, 非 Phase 1 → bypass)
  总耗时：~420ms（不含 typecheck）
```

### C. 竞品对比参考

| 维度 | spec-autopilot v3.6.0 | Claude Code Superpowers | Cursor Agent |
|------|----------------------|------------------------|--------------|
| 阶段数 | 8 | 5（隐式） | 无固定阶段 |
| 门禁层数 | 3（L1+L2+L3） | 1（AI 自检） | 0 |
| 并行能力 | Phase 1/4/5/6 | 无 | Task 级并行 |
| 崩溃恢复 | Checkpoint + task 级 | 无 | 无 |
| TDD 支持 | 内置 RED-GREEN-REFACTOR | 无 | 无 |
| 知识累积 | knowledge.json | 无 | Instincts |
| 配置复杂度 | 60+ 字段 | 无 | 低 |
| 上手门槛 | 中高 | 低 | 低 |
