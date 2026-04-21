# spec-autopilot v5.1.51 整体架构并行深度评审报告

> 评审日期: 2026-03-23
> 评审版本: v5.1.51
> 评审范围: `plugins/spec-autopilot` 全链路架构, 三模式状态机, 主窗口 GUI, 上下文压缩, 崩溃恢复, 需求评审, OpenSpec 流程, 测试体系, rules/CLAUDE 约束, TDD/Code Review, fixup autosquash
> 评审方式: 静态代码审查 + 文档一致性审查 + 全量测试执行 + 定向证据抽样
> 测试基线:
>
> - `cd plugins/spec-autopilot && bash tests/run_all.sh`

---

## 执行摘要

### 一句话结论

`spec-autopilot` 当前版本的核心问题不是“缺规则”，而是“规则强、闭环弱”。阶段定义、Hook 约束、Skill 文档和测试数量都已经很强，但运行时状态一致性、模式闭环、恢复确定性、子 agent 可证明性和测试信号可信度仍然不足，因此它还不是一个完全受控、完全确定性的 autopilot 系统。

### 本次实测结果

| 指标 | 结果 |
|------|------|
| 插件版本 | `5.1.51` |
| 全量测试结果 | `87 files, 875 passed, 33 failed` |
| 失败测试文件 | `test_agent_correlation`, `test_anti_rationalization`, `test_change_coverage`, `test_json_envelope`, `test_phase4_missing_fields`, `test_phase6_allure`, `test_phase_context_snapshot`, `test_phase_progress`, `test_pyramid_threshold` |
| 结论类型 | 同时存在“真实生产链问题”与“测试债/废弃脚本导致的失败” |
| 未覆盖项 | 未执行真实 GUI 手工交互式 E2E; 未将 `dist/` 产物作为主事实来源 |

### 总体判断

| 维度 | 结论 |
|------|------|
| 三模式 phase routing | 基本正确 |
| 三模式全链路闭环 | 不完整 |
| GUI 主窗口编排能力 | 偏弱, 更像观测台 |
| Compact/Recovery | 主链成形, 但非完全受控 |
| TDD/Code Review 门禁 | 有协议, 缺确定性闭环 |
| Rules/CLAUDE/Subagent 治理 | 部分硬约束, 缺运行时证明 |
| 测试体系可信度 | 数量大, 但存在 drift/hack reward 风险 |
| fixup/autosquash | 正常路径成立, 缺归档后校验闭环 |

---

## 关键发现总表

### P0

| 编号 | 问题 | 影响 |
|------|------|------|
| P0-1 | `emit-tool-event.sh` 未像 `_hook_preamble.sh` 那样优先从 stdin `cwd` 解析项目根 | `tool_use ↔ agent_id` 关联丢失, 并行 agent 遥测失真 |
| P0-2 | `save-phase-context.sh` / `write-phase-progress.sh` 走 `resolve_active_change_dir()` 默认 git root | 嵌套 repo/插件 repo 场景写错目录, compact/recovery 失真 |
| P0-3 | `save-state-before-compact.sh` 的 `next_phase` 非 mode-aware | lite/minimal 在 compact 后可能错误恢复到 Phase 2 |
| P0-4 | GUI 将 `decision_ack` 视为 gate 已消失 | 用户界面会误报“阻断已解决”, 实际可能尚未通过门禁 |
| P0-5 | TDD 协议、validator、gate 文档不一致 | full/lite/minimal 的 TDD 行为不可预测, 误判风险高 |

### P1

| 编号 | 问题 | 影响 |
|------|------|------|
| P1-1 | Recovery 只读取 `anchor_sha`, 不负责失效时自动重建 | autosquash 安全性和恢复完整性不足 |
| P1-2 | Phase 1 文档同时要求“默认三路并行”和“flags>=2 先澄清” | 需求评审策略自相矛盾 |
| P1-3 | Phase 6.5 code review 不构成确定性 predecessor gate | Code review 失败仍可能进入归档 |
| P1-4 | Rules/CLAUDE/semantic rules 无法形成完整运行时硬约束 | 规约遵守性无法被稳定证明 |
| P1-5 | 运行时无“本次 task 确实用了指定 subagent_type”的证据链 | 多 agent 治理不可审计 |

### P2

| 编号 | 问题 | 影响 |
|------|------|------|
| P2-1 | GUI 中央主区过度偏向 Phase 5/task 视角 | 非实施阶段信息表达不足 |
| P2-2 | `git_risk_level` 风险分层过粗 | auto-continue 判断不够精细 |
| P2-3 | 测试仍保留大量废弃脚本/文档 grep 断言 | 测试维护成本高, 信号噪音大 |

---

## 1. 三种模式 `full/lite/minimal` 全流程仿真与测试

### 结论

三种模式的基础 phase 序列和 predecessor gate 整体成立, 相关模式测试大多通过, 说明主干 phase routing 没有明显设计错误。但 compact、recovery、GUI 展示层没有形成完整 mode-aware 闭环, 因此不能说三模式已经“全流程稳定”。

### 真实生产链问题

- `save-state-before-compact.sh` 固定扫描 `1..7` 全阶段, 没有按 mode 过滤 checkpoint:
  - `runtime/scripts/save-state-before-compact.sh:102`
- `next_phase = last_completed + 1` 没有使用 mode 路由表:
  - `runtime/scripts/save-state-before-compact.sh:123`
- 结果是 lite/minimal 在 Phase 1 之后 compact, 可能把“下一阶段”错误写成 Phase 2, 而不是 Phase 5。

### 已通过但不能掩盖的问题

- `check-predecessor-checkpoint.sh` 对 full/lite/minimal 的主干 predecessor 行为基本正常。
- `recovery-decision.sh` 对 lite/minimal 的扫描序列是 mode-aware 的:
  - `runtime/scripts/recovery-decision.sh:146-152`
- 但 compact 状态保存与 recovery 决策脚本之间并没有形成完全一致的 mode 语义。

### 结论等级

`阶段序列正确` 不等于 `模式闭环正确`。当前应评估为: 主干可用, 闭环不完整。

---

## 2. 主窗口信息必要性、冗余与最佳 AI 流程编排

### 结论

主窗口当前更像“观测台”, 而不是可靠“编排台”。它展示了很多事件, 但没有把“当前阶段状态机”收敛成稳定的一等对象, 因此容易把“事件到达”误显示为“流程已解决”。

### 主窗口真正必要的信息

建议主窗口只保留以下 6 类核心信息:

1. 当前 `change/session/mode`
2. 当前 `phase` 与 predecessor/gate 状态
3. 未解决 decision 与允许动作
4. 活跃 task/agent 及其 phase 归属
5. 每个 agent 的实际模型、路由来源、fallback 状态
6. compact/recovery/crash 状态与恢复建议

### 当前冗余与设计问题

- `decision_ack` 一到就隐藏 GateBlockCard, 这只代表“决策送达”, 不代表 gate 已通过:
  - `gui/src/App.tsx:95-104`
  - `gui/src/components/GateBlockCard.tsx:43-45`
- `modelRouting` 采用全局单例聚合, 不适合并行 agent/多 phase 并发:
  - `gui/src/store/index.ts:458-476`
- 中央主区没有 task/agent 时直接空白, 且 `ParallelKanban` 在没有 task/agent 时直接返回 `null`:
  - `gui/src/components/ParallelKanban.tsx:80-82`
- `/api/info` 只暴露 session/change/telemetry 粗粒度信息, 没有 phase-state/recovery-state 一等视图:
  - `runtime/server/src/api/routes.ts:57-70`

### 最佳实践建议

- 用单一 `phase orchestration state` 驱动 GUI, 而不是让 gate/model/task/agent 各自独立推断状态。
- `decision_ack` 只能表示 `decision_sent`, 只有收到新的 `gate_pass` 或新的 `phase_end` 才能解除阻断态。
- `modelRouting` 必须改成 `phase + agent_id` 维度聚合, 否则并行 agent 会互相覆盖。
- 补齐 `skipped`, `recovered`, `compacting`, `recovering`, `awaiting_user` 等一等状态。

---

## 3. 上下文压缩流程是否完全受控

### 结论

不是。当前 compact 流程做到了“保存一份状态摘要”, 但没有做到“确定保存正确状态 + mode-aware 恢复 + 上下文充足召回”的完整闭环。

### 真实生产链问题

- `save-phase-context.sh` 与 `write-phase-progress.sh` 依赖 `resolve_active_change_dir()`:
  - `runtime/scripts/save-phase-context.sh:30`
  - `runtime/scripts/write-phase-progress.sh:32`
- 而 `resolve_active_change_dir()` 的根解析默认取 git root:
  - `runtime/scripts/_common.sh:25-58`
- 在嵌套 repo 或插件 repo 下, snapshot/progress 可能写错项目根, 这与失败测试 `test_phase_context_snapshot`、`test_phase_progress` 相互印证。

### 设计缺口

- `save-state-before-compact.sh` 的 checkpoint 扫描模式过于宽泛:
  - `runtime/scripts/save-state-before-compact.sh:102-118`
- `next_phase` 不是 mode-aware:
  - `runtime/scripts/save-state-before-compact.sh:123`
- compact state 只保留摘要、任务计数和部分 snapshot 截断文本, 不足以证明“下一阶段所需上下文完整保留”。

### 召回质量判断

当前更像“摘要型召回”, 不是“受控型状态恢复”。它能帮助模型知道之前做到哪一步, 但不能保证:

- 保留了足够的决策上下文
- 正确保留了 mode 语义
- 正确保留了任务拆分来源
- 正确保留了 anchor/worktree/fixup 风险状态

---

## 4. 崩溃恢复整体流程是否符合设计预期

### 结论

崩溃恢复主链基本成形, 但还不符合“强恢复闭环”的设计预期。当前系统擅长“给出恢复建议”, 还不擅长“确保恢复一定安全、完整、可继续”。

### 真实生产链问题

- `recovery-decision.sh` 会读取并返回 `anchor_sha`, 但不负责失效时自动重建:
  - `runtime/scripts/recovery-decision.sh:115-137`
  - `runtime/scripts/recovery-decision.sh:426-427`
- `fixup_squash_safe` 只是布尔输出, 不是执行型闭环:
  - `runtime/scripts/recovery-decision.sh:426`
- `git_risk_level` 只有 `none/low/high`, 缺少中间层:
  - `runtime/scripts/recovery-decision.sh:388-395`
- `worktree_residuals` 被采集了, 但没有进入 auto-continue eligibility 判定:
  - `runtime/scripts/recovery-decision.sh:112`
  - `runtime/scripts/recovery-decision.sh:397-412`

### 设计后果

- anchor 丢失时, autosquash 只能退化而不是自修复。
- worktree 残留不会阻止自动继续, 有可能把用户带到“可继续但不安全”的状态。
- 风险建模太粗, 不能把“需要确认但可继续”和“绝对不能继续”稳定区分开。

### 优化方向

1. recovery 阶段把 `anchor_sha` 重建流程脚本化, 不要只写在 Skill 文档里。
2. 将 `worktree_residuals`, `invalid_anchor`, `fixup_pending`, `stale_progress` 纳入统一风险分层。
3. 把 auto-continue 条件改成“明确 continue-safe 才自动继续”, 其余全部要求交互确认。

---

## 5. 需求评审环节与三路 agent 是否必要

### 结论

当前设计在需求评审上存在明显自相矛盾, 不应默认三路并行调研。更合理的方案是“先澄清, 再根据需求类型和复杂度自适应调研深度”。

### 文档冲突

- `SKILL.md` 仍然把三路并行调研写成默认流程:
  - `skills/autopilot/SKILL.md:118-138`
- `phase1-requirements.md` 又明确要求 `flags >= 2` 时先做定向澄清, 避免直接三路调研:
  - `skills/autopilot-phase1-requirements/references/phase1-requirements.md:31-42`
- `parallel-phase1.md` 又定义了复杂度自适应, `small` 只做 Auto-Scan, `medium` 不做联网搜索:
  - `skills/autopilot-phase1-requirements/references/parallel-phase1.md:85-94`

### 审查结论

- 三路 agent 不是默认必要, 只在 `large`、高不确定、涉及竞品/外部实践/多方案权衡时必要。
- 模糊需求上直接三路调研只会放大噪音, 并不能提高理解质量。
- 真正决定 Phase 1 质量的不是“agent 数量”, 而是:
  - 需求来源稳定性
  - 定向澄清前置
  - 决策点结构化
  - requirement_type/complexity/search_policy 的一致执行

### 最佳实践建议

1. 先做 requirement lint 和澄清。
2. 再根据 `feature/bugfix/refactor/chore` 选择调研深度。
3. 把“三路并行”降为受策略引擎控制的可选路径, 而不是硬编码默认动作。

---

## 6. `openspec` 与 `openspec ff` 流程是否存在异常风险

### 结论

Phase 2/3 的基础 predecessor 约束没有明显塌陷, 但它们高度依赖上游 Phase 1 收敛质量和下游 compact/recovery 一致性, 因此存在“形式正确、语义漂移”的结构性风险。

### 风险点

- 如果需求没有澄清完就进入 OpenSpec, 生成的 spec/task 可能从源头偏航。
- 如果 compact 后 `next_phase` 错误, 可能出现 `spec/tasks/current phase` 三者不一致。
- lite/minimal 模式依赖 Phase 1 自动拆任务, 其 mode-aware 状态如果恢复错位, Phase 5 会拿到错误任务来源。

### 审查结论

`openspec` / `openspec ff` 当前更像“在理想前提下可靠”, 而不是“对上游异常有足够免疫力”。要降低异常性, 应把进入 Phase 2/3 的条件从“前驱 checkpoint 存在”升级成“需求已收敛 + source 已锁定 + mode-aware context 正常”。

---

## 7. 测试用例设计、合理性、覆盖性与 Hack Reward

### 结论

当前测试总量很大, 但可信度并不与数量成正比。`33` 个失败不全是生产 bug, 但正因为很多测试没有对准真实注册链, 所以测试可信度本身就是问题。

### 测试债与真实问题要分开看

#### 真实问题指向

- `test_agent_correlation`
- `test_phase_context_snapshot`
- `test_phase_progress`

这些失败背后对应的运行时代码路径是真实生产脚本。

#### 测试债/废弃脚本导致的失败

- `test_json_envelope`
- `test_anti_rationalization`
- `test_change_coverage`
- `test_phase4_missing_fields`
- `test_phase6_allure`
- `test_pyramid_threshold`

这些大多仍在测已废弃脚本, 而不是真正注册在 hooks 里的执行链。

### 关键证据

- 生产注册的是 `post-task-validator.sh`, 不再是旧脚本:
  - `hooks/hooks.json:51-57`
- `validate-json-envelope.sh` 已标记废弃:
  - `runtime/scripts/validate-json-envelope.sh:2`
- `anti-rationalization-check.sh` 已标记废弃:
  - `runtime/scripts/anti-rationalization-check.sh:3-6`
- `test_background_agent_bypass.sh` 本身存在假阳性风险, `assert_not_contains` 调用顺序写反:
  - `tests/test_background_agent_bypass.sh:24`
  - `tests/_test_helpers.sh:33-41`

### 结论与建议

- 现有测试存在明显 drift。
- 需要把测试重构成“以 `hooks.json` 注册链为准”的 contract/E2E 套件。
- 文档 grep 和废弃脚本兼容测试应下沉为次级层, 不应再作为主质量信号。
- 要避免 hack reward, 应保证:
  - 断言真实运行链
  - 每个测试只验证一个 contract
  - 测试独立创建 fixture
  - 明确区分 compatibility tests 与 production-path tests

---

## 8. rules / 全局 `CLAUDE.md` / 子 agent / 多 agent 优先级 / 稳定性确定性

### 结论

当前只能做到“部分硬约束”, 做不到“全过程可证明遵守”。系统能注入规则, 但还不能完整证明生成过程真的遵守了所有项目级架构约束。

### 关键证据

- `rules-scanner.sh` 只扫描 `.claude/rules/*.md` 和 `CLAUDE.md`:
  - `runtime/scripts/rules-scanner.sh:13-19`
- `_constraint_loader.py` 主要还是围绕 `code_constraints` 工作:
  - `runtime/scripts/_constraint_loader.py:51-63`
- `semantic_rules` 明确写着不能被 Hook 自动检测:
  - `skills/autopilot-dispatch/SKILL.md:170-176`
- `auto-emit-agent-dispatch.sh` 没有对 `subagent_type` 建立可审计证明, 只是在事件里生成 `agent_id/label`:
  - `runtime/scripts/auto-emit-agent-dispatch.sh:83-100`

### 审查判断

- 运行时没有公开事件证明“本次 task 真用了项目要求的 `subagent_type`”。
- 仓库里没有看到多 `.claude` agent 的优先级解析与冲突消解器。
- 因此:
  - rules 可以注入
  - code_constraints 可以局部强制
  - semantic rules 主要靠模型自觉
  - subagent 使用策略不可被稳定审计

### 建议

1. 对 dispatch/complete 事件补充 `subagent_type`, `requested_agent_type`, `resolved_agent_source`, `rules_hash`。
2. 引入显式优先级链: `task-local > project .claude > project CLAUDE.md > plugin default`。
3. 对关键 phase 的 agent prompt 注入内容生成哈希并回写 checkpoint, 形成“规则已注入”的证据链。

---

## 9. Phase 5/6 的 TDD 独立性、Code Review 质量与预期符合度

### 结论

这里是当前版本最明显的“协议与执行不一致”区域。TDD 和 code review 都有文档设计, 但没有形成稳定、统一、确定性的门禁闭环。

### TDD 主要冲突

- 协议文档中 Phase 5 的 TDD 可选字段名是 `total_cycles`:
  - `skills/autopilot/references/protocol.md:27`
- `_post_task_validator.py` 却读取 `cycles_completed`:
  - `runtime/scripts/_post_task_validator.py:146-160`
- validator 只要发现 `tdd_mode=true` 就把 `tdd_metrics` 变成硬要求:
  - `runtime/scripts/_post_task_validator.py:109-127`
- 但 Phase 5 任务来源文档表达的是 TDD 路径与 mode/配置共同决定:
  - `skills/autopilot/references/mode-routing-table.md:24-27`

### Code Review / 6.5 门禁问题

- `phase5-implementation.md` 说 `tdd_unverified` 只 warning, 不阻断:
  - `skills/autopilot/references/phase5-implementation.md:234-241`
- `autopilot-gate/SKILL.md` 又说 `audit_passed === false` 应阻断 Phase 6:
  - `skills/autopilot-gate/SKILL.md:171-180`
- 测试还证明 Phase 6.5 blocked 不会阻止 Phase 7 predecessor:
  - `tests/test_phase7_predecessor.sh:25-32`

### 审查结论

- TDD 独立性: 有 RED/GREEN/REFACTOR 隔离约束, 但 Phase 5 完成态和 TDD 审计态没有统一。
- Code review 质量: 6.5 更像“建议性旁路”, 不是确定性 gate。
- TDD 是否符合预期: 不能稳定保证。

### 建议

1. 统一协议字段名, 只保留一种 `tdd_metrics` schema。
2. 明确 full/lite/minimal 下哪些模式允许 TDD 硬门禁。
3. 让 Phase 6.5 成为真正 predecessor gate, 或明确降级为 advisory, 不能文档和运行时各说各话。

---

## 10. 多个 fixup 提交的合并是否符合预期

### 结论

正常路径设计基本成立, 相关 git 模拟测试也覆盖到了 `full/lite/minimal`。但运行时缺少归档后“fixup 全部清零”的确定性校验器, 因此不能断言“本次迭代所有 fixup 一定全部合并且无遗漏”。

### 关键证据

- Phase 7 设计里 `anchor_sha` 无效时会直接跳过 autosquash:
  - `skills/autopilot-phase7/SKILL.md:121-128`
- recovery 决策只负责输出 `fixup_commit_count`、`fixup_squash_safe`、`anchor_sha`, 不负责归档后校验:
  - `runtime/scripts/recovery-decision.sh:424-430`

### 审查判断

- 正常路径: 可认为设计成立。
- 异常路径: 不能证明“没有遗漏 fixup”。
- 因此当前最多只能说“autosquash 机制存在且常规测试通过”, 不能说“归档后 fixup 一定完全收敛”。

### 建议

1. 在 Phase 7 完成前增加 `post-autosquash validator`。
2. 明确校验 `anchor_sha..HEAD` 不再存在 `fixup!` 提交。
3. 若 anchor 无效, 不应仅 warning 后继续归档, 应提升到显式恢复/确认流程。

---

## 真实生产链问题 vs 测试债

### 真实生产链问题

1. `emit-tool-event.sh` 项目根解析不正确, 导致 agent correlation 失真
2. `save-phase-context.sh` / `write-phase-progress.sh` 在嵌套 repo 下可能写错目录
3. compact `next_phase` 非 mode-aware
4. recovery 不负责 anchor 失效后的自修复
5. GUI 把 `decision_ack` 当作“阻断已解决”
6. TDD / Phase 6.5 门禁规则互相冲突

### 测试债或兼容层问题

1. 多个失败测试仍针对废弃脚本
2. 部分测试是文档/grep 断言, 不是生产执行链
3. 存在假阳性测试, 会掩盖真实风险

---

## 建议的修复优先级

### P0

1. 统一项目根解析, 修复 `emit-tool-event.sh`、`save-phase-context.sh`、`write-phase-progress.sh`
2. 让 compact state save 使用 mode-aware phase 序列与 `next_phase`
3. 修复 GUI gate 状态机, 区分 `decision_sent` 和 `gate_resolved`
4. 统一 TDD 协议、validator、gate 规则

### P1

1. 补齐 recovery 的 anchor 自修复与风险分层
2. 把 Phase 6.5 明确成硬门禁或 advisory, 二选一
3. 为 subagent_type、rules 注入、prompt source 建立可审计事件链
4. 重写 Phase 1 策略, 先澄清再自适应调研

### P2

1. 清理废弃脚本测试, 重建 contract/E2E 测试层级
2. 优化主窗口中心区, 以 phase orchestration state 为核心重构
3. 增加归档后 fixup 清零校验器

---

## 供后续 Claude 修复时直接使用的工作说明

建议后续修复按以下顺序推进:

1. 先修运行时确定性问题:
   - 项目根解析
   - compact/recovery mode-aware 闭环
   - GUI gate 状态机
2. 再修规则一致性问题:
   - TDD schema
   - Phase 6.5 gate 语义
   - Phase 1 调研策略统一
3. 最后修测试体系:
   - 用真实 `hooks.json` 注册链重建主测试集
   - 将废弃脚本测试降级到兼容层
   - 清理假阳性断言

---

## 附录: 关键证据文件

- `runtime/scripts/emit-tool-event.sh`
- `runtime/scripts/save-phase-context.sh`
- `runtime/scripts/write-phase-progress.sh`
- `runtime/scripts/save-state-before-compact.sh`
- `runtime/scripts/recovery-decision.sh`
- `runtime/scripts/_post_task_validator.py`
- `gui/src/App.tsx`
- `gui/src/components/GateBlockCard.tsx`
- `gui/src/store/index.ts`
- `gui/src/components/ParallelKanban.tsx`
- `runtime/server/src/api/routes.ts`
- `skills/autopilot/SKILL.md`
- `skills/autopilot-phase1-requirements/references/phase1-requirements.md`
- `skills/autopilot-phase1-requirements/references/parallel-phase1.md`
- `skills/autopilot/references/protocol.md`
- `skills/autopilot/references/mode-routing-table.md`
- `skills/autopilot/references/phase5-implementation.md`
- `skills/autopilot-gate/SKILL.md`
- `skills/autopilot-phase7/SKILL.md`
- `tests/test_phase7_predecessor.sh`
- `tests/test_background_agent_bypass.sh`
- `tests/_test_helpers.sh`
- `hooks/hooks.json`
