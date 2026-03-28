# spec-autopilot 全量稳定性改造与修复总方案

日期: 2026-03-28
范围: `plugins/spec-autopilot`
依据:
- `docs/reports/2026-03-28-spec-autopilot-holistic-review.zh.md`
- `docs/reports/2026-03-28-spec-autopilot-evidence-appendix.zh.md`
- `docs/reports/2026-03-28-spec-autopilot-secondary-review.zh.md`
- `docs/reports/2026-03-28-spec-autopilot-conflict-verification.zh.md`

## 1. 文档定位

本文档不是优先级列表，也不是局部补丁建议，而是针对 `spec-autopilot` 当前整体产品、架构、运行时、GUI、测试、恢复、归档、提示词与 agent 治理的全量修复蓝图。

配套执行文档已补齐，实施时必须一并使用:

- `docs/plans/2026-03-28-spec-autopilot-remediation-execution-prompt.zh.md`
- `docs/plans/2026-03-28-spec-autopilot-remediation-execution-backlog.zh.md`
- `docs/plans/2026-03-28-spec-autopilot-remediation-acceptance-matrix.zh.md`
- `docs/plans/2026-03-28-spec-autopilot-remediation-workstream-a-phase1-context-isolation.zh.md`
- `docs/plans/2026-03-28-spec-autopilot-remediation-workstream-b-auto-continue-and-archive.zh.md`
- `docs/plans/2026-03-28-spec-autopilot-remediation-workstream-c-state-snapshot-and-recovery.zh.md`
- `docs/plans/2026-03-28-spec-autopilot-remediation-workstream-d-gui-orchestration-first.zh.md`
- `docs/plans/2026-03-28-spec-autopilot-remediation-workstream-e-agent-governance-tdd-review.zh.md`
- `docs/plans/2026-03-28-spec-autopilot-remediation-workstream-f-blackbox-tests-and-doc-sync.zh.md`

在 2026-03-29 的代码复核中，又确认了少量 remediation 遗漏项。后续补修时必须同时参考:

- `docs/plans/2026-03-29/2026-03-29-spec-autopilot-remediation-gap-fix-plan.zh.md`

本方案覆盖你提出的全部问题：

1. full/lite/minimal 三模式全流程仿真与问题修复策略
2. 主窗口信息必要性、去冗余与最佳 AI 编排
3. 上下文压缩、保存、恢复、召回闭环
4. 崩溃恢复整体闭环
5. 需求评审、三路 agent、需求理解深化、来源稳定性、提示词工程化
6. OpenSpec 与 OpenSpec FF 异常控制
7. 测试用例合理性、覆盖性、独立性与反 Hack Reward
8. rules / 全局 `CLAUDE.md` / 子 agent / 多 agent 优先级 / 代码稳定性
9. Phase 5/6 TDD、独立性与 code review 质量
10. fixup 合并与归档完整性
11. 各阶段门禁与上下文恢复的意义
12. 整体产品理念、harness 对齐、商业化与是否过度设计
13. 所有方案文档化落盘到 `docs`

同时本文档把你的两条新增产品诉求作为全局硬约束：

1. 需求评审完成后，后续阶段默认自动完成，不中断、不再逐阶段确认。
2. 子 agent 工作不得占用或污染主 agent 关键上下文，主 agent 只保留编排所需最小信息。

## 2. 总体修复原则

后续所有实现必须同时满足以下原则，不能只满足其中一部分：

1. `Main Agent Minimal Context`
主 agent 只持有编排态、门禁态、摘要态，不读取子 agent 原始全文，不代写子 agent 正文工件。

2. `Single Source of Truth`
需求、计划、测试、审查、恢复、归档都要落到结构化工件，不能再依赖“主线程记忆 + 零散 markdown + 提示词约束”的混合状态。

3. `Auto Continue by Default`
用户只在真正需要业务裁决时参与一次性确认；系统性流程不再反复 AskUserQuestion。

4. `Fail Closed by Default`
review 未清理、fixup 不完整、恢复不一致、agent 选型不合规、fast-forward 越权时必须阻断，不能 warning 后继续。

5. `Observable and Replayable`
系统恢复依赖结构化状态恢复，不依赖摘要回灌后让 AI “猜着续跑”。

6. `Same Control Standard Across Modes`
full/lite/minimal 只在调研深度、测试深度、成本与耗时上分层，不在控制闭环、恢复可靠性和门禁强度上分层。

7. `Prompt Engineering Must Become Protocol Engineering`
不再把能力寄托在更长的提示词，而是通过 prompt pack、schema、validator、artifact、gate 形成硬约束。

## 3. 目标总架构

### 3.1 四层模型

1. `Control Plane`
- phase graph
- gate engine
- dispatch engine
- recovery engine
- archive engine

2. `Artifact Plane`
- `requirement-packet.json`
- `research-manifest.json`
- `decision-log.json`
- `implementation-plan.json`
- `test-manifest.json`
- `review-findings.json`
- `state-snapshot.json`
- `archive-readiness.json`
- `agent-dispatch-record.json`

3. `Execution Plane`
- skills
- runtime scripts
- server
- GUI
- child agents

4. `Observation Plane`
- 主窗口编排视图
- workbench 诊断视图
- event stream
- recovery diagnostics
- archive diagnostics

### 3.2 核心状态对象

1. `Requirement Packet`
- 用户目标
- 业务边界
- 非目标
- 澄清问答
- 决策点
- 风险点
- 来源稳定性
- canonical hash

2. `State Snapshot`
- 最近成功 phase
- 当前 gate frontier
- artifact graph
- 未完成任务
- review 状态
- fixup 状态
- autosquash anchor 状态
- requirement packet hash
- compact 前后恢复一致性字段

3. `Agent Dispatch Record`
- agent class
- selection_reason
- scanned_sources
- resolved_priority
- phase allowlist
- required prompt pack
- required validators
- owned artifacts
- fallback reason

## 4. 全生命周期全量修复策略

本节不按优先级排列，而按产品生命周期顺序给出每个问题域的完整修复策略。

### 4.1 模式一致性与全自动推进

#### 修复目标

让 full/lite/minimal 三种模式都满足同一控制标准：

1. 需求确认后自动推进
2. 不再逐阶段确认
3. gate 决定是否继续，而不是用户点击继续
4. 三模式均可恢复、可审计、可归档

#### 详细策略

1. 配置体系重构
- 废弃 `after_phase_1/3/4` 这类“逐阶段确认”语义，改为“需求包确认后默认连续执行直到 archive”。
- 预设（`strict/moderate/relaxed`）只负责质量阈值、调研深度、测试强度，不再承担“减少确认点”的职责。
- 明确禁止通过切到 `relaxed`、切到 `minimal`、关闭 code review 等方式换取“更自动”。
- 模式决定深度，不决定是否自动推进；自动推进是控制面默认行为。

2. 默认行为重构
- requirement packet 一经确认，Phase 2-7 默认自动连续执行。
- Phase 7 不再把“归档需用户确认”作为铁律；当且仅当 `archive-readiness` 无法证明安全归档时，才触发一次裁决。
- 用户确认只保留在四类节点：需求包确认、破坏性操作、恢复歧义、真实 blocked 的 archive 裁决。
- 同步修订 `CLAUDE.md` 与 `autopilot-phase7/SKILL.md`，删除“归档必须 AskUserQuestion”的硬编码规则。

3. 模式差异重构
- `full`: 完整设计、测试、实现、验证、归档
- `lite`: 压缩设计与测试深度，但保留相同 gate
- `minimal`: 压缩中间文档与部分测试深度，但 gate、恢复、归档、review 合规性不降低

4. 模式仿真补测
- full 自动贯通
- lite 自动贯通
- minimal 自动贯通
- 三模式在 crash recovery 后自动继续
- 三模式在 compact/restore 后保持同一 requirement packet hash
- 三模式在 archive-ready 时自动归档，不弹阶段确认

#### 产物与改动域

- `README.zh.md`
- `skills/autopilot/SKILL.md`
- `runtime/scripts/check-predecessor-checkpoint.sh`
- `runtime/scripts/poll-gate-decision.sh`
- `tests/test_lite_mode.sh`
- `tests/test_minimal_mode.sh`
- 新增自动推进黑盒测试

### 4.2 Phase 1 需求评审、三路调研与主上下文隔离

#### 修复目标

解决当前最核心的产品违背：

1. 子 agent 结果直接或间接污染主 agent 上下文
2. Phase 1 协议自相矛盾
3. 三路调研默认化导致速度慢、成本高、理解不一定更准
4. 需求来源与决策链不稳定

#### 详细策略

1. Phase 1 拆成四步
- `1A Clarify`
- `1B Research`
- `1C Synthesis`
- `1D Requirement Confirm`

2. `1A Clarify`
- 主 agent 仅做 1 到 3 个高价值澄清问题。
- 先判断需求成熟度：`clear / partial / ambiguous`。
- `clear` 时不进入多路调研，只做轻量核验。
- `partial` 时进入双路调研。
- `ambiguous` 时才启用三路调研。

3. `1B Research`
- 所有 research agent 必须自行写工件。
- 工件分为 `repo-research-facts.json`、`web-research-facts.json`、`ba-analysis-facts.json`。
- 主 agent 禁止读取 `research-findings.md`、`web-research-findings.md`、`requirements-analysis.md` 正文，不得再代写这些正文工件。
- 主 agent 仅允许做两类动作：验证 `output_file` 存在；消费结构化 facts envelope。
- Phase 1 子任务不再复用 `autopilot-phase` 主阶段 marker，而改为轻量 `autopilot-subtask:*` 标记和对应 schema，既可统一验证，又不误触发 phase gate。
- 为 research / BA / synthesis 增加独立 L2 验证链，不能再依赖“主线程自律”。

4. `1C Synthesis`
- 单独使用 synthesis agent 读取 research facts 工件。
- 生成唯一 `requirement-packet.json` 与 `decision-log.json`。
- 主 agent 只消费 requirement packet 摘要、hash、未决问题和决策点。

5. `1D Requirement Confirm`
- 用户只确认 requirement packet。
- requirement packet 一旦确认，后续全流程自动推进。
- 需求确认后，主 agent 不再回读调研正文。

6. 需求来源稳定化
- 为 packet 中每个关键结论增加 `source_type`:
  - `user_confirmed`
  - `repo_evidence`
  - `external_evidence`
  - `inference`
- 对 `inference` 项要求在后续设计和测试阶段显式追踪。

7. 决策链约束
- 所有 `open_questions` 必须映射到 `decision_points`。
- 所有 `decision_points` 必须映射到测试关注点。
- 所有未关闭的 `open_questions` 不允许进入 Phase 5。

8. prompt 工程化改造
- 由“长提示词”改为 `prompt pack + schema + validator + artifacts`。
- research/BA/synthesis 各有独立 prompt pack。
- prompt pack 中必须声明 owned artifacts、禁止读写边界、禁止主线程回填。
- 清理所有要求主线程“合并 research 正文”“读取 requirements-analysis 全文”的旧协议描述，避免 AI 在冲突协议之间自行取舍。

#### 产物与改动域

- `skills/autopilot/SKILL.md`
- `skills/autopilot-dispatch/SKILL.md`
- `skills/autopilot/references/parallel-phase1.md`
- `skills/autopilot/references/phase1-requirements.md`
- `skills/autopilot/references/phase1-requirements-detail.md`
- `runtime/scripts/post-task-validator.sh`
- `runtime/scripts/validate-decision-format.sh`
- 新增 `requirement-packet.json` schema 和黑盒测试

### 4.3 主窗口信息架构与主 agent 编排最佳实践

#### 修复目标

把 GUI 主窗口从“技术遥测面板”重构为“编排驾驶舱”，保证主窗口只展示必要信息，不堆调试噪音。

#### 主窗口必须保留的信息

1. 当前目标摘要
2. 当前 phase / sub-step / next action
3. 当前 gate frontier 与阻断证据
4. 当前活跃 agent
5. 每个 agent 的 role、owned artifacts、status、validator 状态
6. requirement packet hash 与当前版本
7. recovery source、checkpoint、restore 状态
8. compact 风险、context budget、reinject 状态
9. archive readiness、fixup completeness、review gate
10. 模型路由与 effective/fallback 状态

#### 冗余信息的处理

以下信息不应占据主窗口主视觉，而应下沉到 workbench：

1. cwd
2. transcript path
3. worktree 原始细节
4. raw hooks 日志全文
5. 工具调用细碎事件全文
6. statusline 原始文本流

#### 最佳编排实践

1. 主窗口只呈现“当前为什么卡住、下一步是什么、谁在做什么”。
2. 主窗口不展示大段正文产出，不承担审阅器角色。
3. 主 agent 工作流以 gate 和 artifacts 驱动，而不是靠主窗口文本堆积。
4. GUI 中要显式区分：
- requested model
- effective model
- fallback model
- runtime unknown

#### 产物与改动域

- `gui/src/App.tsx`
- `gui/src/components/PhaseTimeline.tsx`
- `gui/src/components/ParallelKanban.tsx`
- `gui/src/components/TelemetryDashboard.tsx`
- `gui/src/components/OrchestrationPanel.tsx`
- `gui/src/store/index.ts`

### 4.4 上下文压缩、保存、恢复与召回闭环

#### 修复目标

将当前“摘要回灌”升级为“结构化状态恢复 + 可验证召回”。

#### 详细策略

1. compact 前保存结构化状态
- requirement packet hash
- artifact manifest
- gate frontier
- 当前活跃任务
- review 状态
- fixup 状态
- next action
- context budget 使用量

2. 新增 `state-snapshot.json`
- 合并原先 `context-ledger` 与 `recovery-state` 的职责
- 记录主 agent 保留摘要、工件索引、截断信息、gate frontier、active tasks、review/fixup/archive 状态
- 用于恢复控制平面，而不是恢复一段自然语言摘要

3. reinject 流程调整
- 不直接把超长 markdown 打回 stdout
- 先恢复 `state-snapshot.json`
- 再生成最小必要摘要注入主 agent
- 主 agent 只收到 resume 所需的最小事实集

4. 上下文恢复召回标准
- requirement packet 恢复后 hash 一致
- decision points 恢复后数量一致
- 未决问题恢复后一致
- active gate frontier 恢复后一致
- next action 恢复后一致

5. 保存了哪些上下文
- 需求包摘要和 hash
- 决策点
- 风险点
- 当前 phase 与 gate
- 活跃任务
- review / fixup / archive 状态

6. 不再以“保存完整对话”为目标
- 原始对话不作为控制态恢复唯一依据
- 调研正文通过 artifact 索引按需访问

#### 产物与改动域

- `runtime/scripts/save-state-before-compact.sh`
- `runtime/scripts/reinject-state-after-compact.sh`
- `runtime/scripts/scan-checkpoints-on-start.sh`
- `runtime/scripts/save-phase-context.sh`
- 新增 compact/restore hash 一致性测试

### 4.5 崩溃恢复整体闭环

#### 修复目标

恢复流程不只是“找最近 checkpoint”，而是完整回答：

1. 可以从哪里恢复
2. 恢复后保留什么
3. 需要丢弃什么
4. 哪些阶段必须重跑
5. 是否允许自动继续

#### 详细策略

1. `recovery-decision.sh` 输出结构化决策
- `resume_from_phase`
- `discarded_artifacts`
- `replay_required_tasks`
- `recovery_reason`
- `recovery_confidence`

2. 恢复后强制校验
- predecessor graph
- artifact completeness
- requirement packet hash
- review gate
- fixup completeness
- archive anchor
- worktree cleanliness

3. 恢复后的自动推进
- 如果结构化校验全部通过，则自动继续
- 如果存在歧义，仅在恢复裁决点打断用户一次

4. GUI 增加恢复来源与恢复质量
- `fresh_run`
- `compact_restore`
- `crash_recovery`
- `manual_resume`
- `legacy_resume`

5. 恢复优化方向
- 明确不可复用的子 agent 结果
- 明确过期的 research 与 design artifact
- 通过 artifact graph 避免“带着坏状态继续”

#### 产物与改动域

- `skills/autopilot-recovery/SKILL.md`
- `runtime/scripts/recovery-decision.sh`
- `runtime/scripts/clean-phase-artifacts.sh`
- `runtime/scripts/scan-checkpoints-on-start.sh`
- 集成恢复黑盒测试

### 4.6 OpenSpec 与 OpenSpec FF 异常控制

#### 修复目标

保持 `openspec` / `openspec ff` 作为 Phase 2/3 的受控执行路径，不额外引入一套独立状态机，同时确保 Phase 2/3 产出契约足够硬。

#### 详细策略

1. 不重建一套“FF 专属控制面”
- `openspec ff` 继续作为 Phase 3 的加速执行路径
- 真实约束点放在 Phase 2/3 前驱检查、结构化 envelope、artifacts 完整性和后续 gate 上

2. 强化 Phase 2/3 结构化契约
- Phase 2 至少产出 artifacts + alternatives
- Phase 3 至少产出 plan + test_strategy
- 所有这些字段由统一 validator 和黑盒测试共同约束

3. FF 审计要求
- 必须记录生成了哪些工件、依据的是哪个 requirement packet hash、是否命中 fallback
- 记录到 `decision-log.json` 与 `agent-dispatch-record.json`

4. 异常处理
- 若 Phase 2/3 产出无法证明完整性，则直接 blocked，不进入后续阶段
- 不把 FF 视为 review/fixup/archive 的旁路，也不为 FF 增加额外的人工确认

#### 产物与改动域

- `skills/autopilot/SKILL.md`
- OpenSpec 相关命令与文档
- fast-forward 约束测试

### 4.7 测试设计、覆盖性、独立性与反 Hack Reward

#### 修复目标

测试必须真正映射产品目标，而不是大量验证文档存在或文本包含某句提示词。

#### 详细策略

1. 测试分层
- `schema/static`
- `script behavior`
- `orchestration blackbox`
- `product simulation`

2. 所有产品目标必须绑定黑盒测试
- 自动推进
- 主上下文不污染
- compact/restore 一致
- crash recovery 自动恢复
- review gate 阻断
- fixup fail-closed
- agent priority enforced
- openspec ff 不越权

3. 测试独立性
- 实现 agent 不能直接生成“测试已通过”的最终结论
- 测试 agent 不能复用实现 agent 的自由描述替代真实输入
- review agent 不能与实现 agent 共享未清洗的叙述上下文

4. 防止 Hack Reward
- 把 `grep SKILL.md` 类测试降级为协议测试
- 协议测试不得代表产品闭环通过
- 产品验收必须来自脚本行为或黑盒仿真

5. full/lite/minimal 仿真
- 三模式都要有标准输入包、预期状态迁移、恢复测试、归档测试
- 不能只验证 phase 序列，还要验证 artifact、gate、context、review、fixup 闭环

#### 产物与改动域

- `tests/run_all.sh`
- 现有协议测试分类调整
- 新增八类黑盒测试与三模式仿真夹具

### 4.8 rules / CLAUDE / 子 agent / 多 agent 优先级治理

#### 修复目标

保证代码生成与任务分发严格遵守项目规则，并且可证明使用了正确的 agent。

#### 详细策略

1. 不新增独立 `agent-policy.json`
- 当前先避免引入新的全局策略文件
- 以 `.claude/agents` + `.claude/rules` + `CLAUDE.md` 为输入源，生成轻量选择证据

2. dispatch 前校验
- 是否命中正确 agent class
- 是否命中最高优先级合规 agent
- 若 fallback，为什么 fallback
- fallback 是否被允许

3. rules 解析范围扩展
- 项目根 `CLAUDE.md`
- `plugins/spec-autopilot/CLAUDE.md`
- `.claude/rules`
- `.claude/agents`
- phase 局部 rules

4. 代码稳定性与确定性
- 每个 agent 输出必须有 schema
- 每次 dispatch 必须记录 `requested/effective/fallback`
- 每次实现任务必须记录 owned files
- 非 owned files 写入必须触发 gate

5. 子 agent 使用证明
- 增加 `agent-dispatch-record.json`
- 记录 phase、task、agent class、selection_reason、priority resolution、validator result、fallback reason

#### 产物与改动域

- `runtime/scripts/rules-scanner.sh`
- `runtime/scripts/auto-emit-agent-dispatch.sh`
- `runtime/scripts/post-task-validator.sh`
- dispatch 相关 skill 与测试

### 4.9 Phase 5/6 TDD、独立性与 review 质量

#### 修复目标

让 TDD 与 review 从“口头宣称”变成“工件链可验证”。

#### 详细策略

1. 新增三类核心工件
- `implementation-task-pack.json`
- `test-intent.json`
- `review-assertions.json`

2. TDD 基本链路
- 先有 `test-intent`
- 再有 failing signal 或等价可审计前置
- 再允许实现
- 实现后必须再次执行测试
- review 根据 diff + intent + test result 形成 findings

3. 独立性约束
- 实现 agent 不产出最终验收结论
- 测试 agent 使用独立输入包
- review agent 使用独立输入包
- review findings 中必须包含证据引用

4. 代码 review 质量
- findings 结构化记录 severity、evidence、blocking、owner
- `critical/high` findings 未关闭则 archive blocked
- review 不允许完全 advisory 化

5. 避免伪 TDD
- 没有前置 failing signal 或测试意图，不得标记为 TDD
- 没有 review findings 文件，不得标记 review 已完成

#### 产物与改动域

- `skills/autopilot/references/tdd-cycle.md`
- `skills/autopilot/references/phase5-implementation.md`
- `skills/autopilot/references/phase6-code-review.md`
- `tests/test_tdd_isolation.sh`
- `tests/test_phase65_bypass.sh`
- `tests/test_phase6_independent.sh`

### 4.10 fixup 合并、autosquash 与归档完整性

#### 修复目标

保证每次迭代的 fixup 都被完整收口，不遗漏，不带病归档。

#### 详细策略

1. 新增 `archive-readiness.json`
- checkpoint 数量
- 预期 fixup 数量
- 实际 fixup 数量
- anchor 是否有效
- review gate 状态
- worktree 状态

2. 归档前强校验
- fixup 数量必须匹配
- anchor 必须可解析
- 所有 blocking review findings 必须关闭
- dirty worktree 必须有白名单原因

3. 归档策略
- 只允许 `archive_ready` 或 `archive_blocked`
- 不允许 warning 后继续归档
- 不允许“跳过 autosquash 完成归档”

4. 缺陷修复方向
- 自动重建 anchor
- 自动补扫 fixup
- 自动检测遗漏 checkpoint
- 若仍失败，则 blocked

#### 产物与改动域

- `skills/autopilot-phase7/SKILL.md`
- `runtime/scripts/check-predecessor-checkpoint.sh`
- `runtime/scripts/rebuild-anchor.sh`
- `tests/test_fixup_commit.sh`
- `tests/test_phase7_archive.sh`

### 4.11 阶段门禁的重新定义

#### 修复目标

让每个阶段门禁都有清晰、不可替代的语义，不再只是“形式化暂停点”。

#### 各阶段门禁意义

1. `Phase 1 Gate`
需求是否形成唯一 requirement packet，且可执行、可测试、可恢复。

2. `Phase 2 Gate`
设计是否完整覆盖需求边界、风险点、决策点。

3. `Phase 3 Gate`
计划是否拆出 ownership、顺序、依赖、回滚路径、测试映射。

4. `Phase 4 Gate`
测试是否真正约束实现，而非实现后补写。

5. `Phase 5 Gate`
实现是否遵守 rules、owned files、task pack、validator。

6. `Phase 6 Gate`
测试结果是否足以证明实现满足预期。

7. `Phase 6.5 Gate`
review findings 是否允许进入归档。

8. `Phase 7 Gate`
fixup、autosquash、archive、manifest、恢复状态是否完整收口。

#### 上下文恢复的意义

上下文恢复不是为了让下一个 AI 看懂更多文字，而是为了恢复控制平面，使系统能确定性继续，而不是重新猜测。

### 4.12 整体产品理念、harness 对齐、商业化与过度设计

#### 目标判断

当前 `spec-autopilot` 的价值在于：

1. 有明确的 phase/gate 骨架
2. 有较强的脚本工程化基础
3. 有 GUI 可观测性基础
4. 具备继续商业化演进的条件

#### 当前偏差

1. 控制面和提示词面边界不清
2. 主从 agent 职责不硬
3. 恢复更像“重新理解”，不是“恢复状态”
4. review 和 archive 仍存在 fail-open
5. GUI 过度偏向技术遥测，弱化了产品决策面

#### 与 harness 理念的对齐方式

1. 主 agent 负责编排和裁决，不负责吞下所有正文
2. 子 agent 负责受限执行，必须有 owned artifacts 和 validator
3. 系统状态由 artifacts 和 gates 维护，而不是由对话记忆维护
4. 快速路径不能绕开门禁
5. 恢复必须恢复状态，不是恢复“聊天感觉”

#### 商业化判断

只有完成本方案中的全量改造，产品才具备更强商业化基础：

1. 自动化体验稳定
2. 恢复与归档可信
3. 子 agent 使用受控
4. 结果可审计
5. 用户不再被流程噪音频繁打断

#### 如何避免过度设计

1. 保留 phase/gate 骨架
2. 去掉双重协议和重复确认
3. 去掉主线程代写研究正文
4. 去掉“名义存在但不决定结果”的伪门禁
5. 用更少但更硬的状态对象替代更多说明文本

## 5. 实施层详细策略

本节给出代码层面的全量修复方向，确保不是只停留在产品语义。

### 5.1 Skills 与协议层

1. 统一 `autopilot/SKILL.md`、`autopilot-dispatch/SKILL.md`、Phase 1 参考文档
2. 移除所有要求主线程合并 research 正文的协议描述
3. 为每类子任务定义固定输出 schema
4. 为每个 phase 增加 artifact ownership 约束

### 5.2 Runtime Scripts 层

1. 统一 background agent 校验闭环
2. 清理 deprecated validator 脚本与兼容测试命名，避免把遗留 bypass 误解为生产路径
3. 新增 compact/restore 结构化保存与校验
4. 新增 archive-readiness 与 review gate 阻断逻辑
5. 新增 agent selection resolution 输出

### 5.3 Server 层

1. 事件模型扩展
- `model_routing`
- `model_effective`
- `model_fallback`
- `review_gate`
- `archive_readiness`
- `recovery_source`
- `context_budget`

2. 快照模型扩展
- requirement packet hash
- active gate frontier
- active agents ownership
- review/fixup/archive 状态

3. 服务端日志增强
- snapshot/build/read/parse 错误结构化记录
- 恢复与归档状态可追踪

### 5.4 GUI 层

1. 主窗口改为 orchestration first
2. workbench 专门承载调试与原始日志
3. 明确显示 server 健康、WS 健康、statusline 状态、transcript 可用性
4. 明确显示 requested/effective/fallback model

### 5.5 Tests 层

1. 保留协议测试，但从产品验收中降级
2. 新增三模式黑盒仿真
3. 新增 Phase 1 上下文隔离测试
4. 新增 compact/restore hash 一致性测试
5. 新增 review/archive/fixup fail-closed 测试
6. 新增 agent priority enforcement 测试

### 5.6 Docs 层

1. 更新 README 与架构文档，保证与实际实现一致
2. 补充新的 artifact schema 文档
3. 补充 gate 语义与恢复语义
4. 明确 legacy session 与新协议 session 的差异

## 6. 全量验收标准

只有同时满足以下全部条件，才能认定本次稳定性改造完成：

1. 需求评审确认后，full/lite/minimal 全流程默认自动推进。
2. Phase 1 主线程不再代写 research / BA 正文工件。
3. 主 agent 只保留 requirement packet 摘要、gate、next action、必要决策状态。
4. compact/restore 前后 requirement packet hash 一致。
5. 崩溃恢复后 artifact graph、gate frontier、next action 可机器校验一致。
6. review findings 的 blocking 项未关闭时，archive 必须 blocked。
7. fixup 或 autosquash 不完整时，archive 必须 blocked。
8. `openspec ff` 不能绕过 Phase 2/3 结构化契约与后续 review、recovery、archive 完整性。
9. agent dispatch 可以证明为何选择该 agent、是否 fallback、是否合规。
10. GUI 主窗口优先展示编排信息，调试信息下沉到 workbench。
11. 测试体系中每个产品目标至少有一个黑盒测试，而不是只依赖文档 grep。
12. README、SKILL、runtime、GUI、tests 的行为与文档一致。

## 7. 兼容与迁移策略

1. 对历史 session 保持只读兼容。
2. 新协议通过 schema version 区分。
3. GUI 中显式标注 `legacy session` 与 `controlled session`。
4. 恢复脚本对旧工件允许降级读取，但不把旧行为伪装成新闭环。

## 8. 最终结论

这次修复不能再按“补几个点”理解，而必须被视为一次完整的控制面收敛。

真正要修的不是单个 bug，而是以下四件事：

1. 让主 agent 从正文消费者变成状态编排者
2. 让所有关键阶段从提示词约束变成结构化约束
3. 让恢复、review、archive 从 advisory 变成可阻断、可验证
4. 让 GUI 从技术遥测台变成产品编排驾驶舱

只有把这四件事全部做完，`spec-autopilot` 才真正符合你的产品目标，也才更接近社区对 harness 的合理预期。
