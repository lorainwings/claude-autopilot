# spec-autopilot 冲突点核实报告

日期: 2026-03-28

核实对象:
- `docs/reports/2026-03-28-spec-autopilot-secondary-review.zh.md`
- `plugins/spec-autopilot`

核实原则:
- 以你的原始产品目标为唯一准绳，不缩减目标，不以“降低自动化/降低约束/降低质量”换取表面一致性
- 严格区分“生产主路径真实行为”“协议/文档冲突”“废弃代码/兼容测试遗留”
- 不把测试全绿等同于产品目标已达成

你的硬目标在本次核实中按如下理解执行:
1. 需求评审完成后，后续阶段默认自动完成，不再逐阶段确认
2. 子 agent 工作不得占用或污染主 agent 关键上下文
3. 插件应被增强，而不是通过切到更轻预设、关闭能力、降低控制标准来“修复”

## 一、执行摘要

二次评审文档有价值，但结论并不完整。

成立的部分:
- GUI/主窗口信息架构问题真实存在，而且比文档写得更直接: 编排面板已经实现但完全未接入主路径
- fixup 完整性与 `rebuild-anchor.sh` 的问题真实存在
- 上下文压缩/恢复确实是多层保存，但注入主线程时仍然是有损摘要恢复
- `rules-scanner.sh` 不扫描 `.claude/agents`
- `Phase 6.5` 代码审查当前确实不是决定性硬门禁

二次评审低估的部分:
- 它把“自动推进”问题过度收敛为“把默认 preset 改成 relaxed 即可”，这不符合你的原始目标
- 它把 Phase 1 冲突收敛为“`parallel-phase1.md:81` 一处遗留”，但源码与协议里实际存在多处主线程读取/合并正文的指令
- 它承认恢复是有损的，却仍把当前恢复评价为“实用上足够”；对“完全受控恢复”的目标而言，这个判断偏宽
- 它保留了 Phase 7 强制确认，这与“需求评审后后续阶段自动完成”的目标直接冲突

不成立或需降级的部分:
- “背景 agent bypass 是当前生产路径 P0 缺陷”不成立；生产 hooks 已切到统一 validator
- 但“仓库内仍保留 bypass 语义并由测试覆盖，因此治理边界不干净”成立

## 二、核实方法

执行与核对内容:
- 源码核对: `skills/`、`runtime/scripts/`、`gui/`、`runtime/server/`
- 关键测试执行:
  - `bash plugins/spec-autopilot/tests/run_all.sh`
  - `bash plugins/spec-autopilot/tests/integration/test_e2e_checkpoint_recovery.sh`
  - `bash plugins/spec-autopilot/tests/test_lite_mode.sh`
  - `bash plugins/spec-autopilot/tests/test_minimal_mode.sh`
  - `bash plugins/spec-autopilot/tests/test_recovery_auto_continue.sh`
  - `bash plugins/spec-autopilot/tests/test_fixup_commit.sh`
  - `bash plugins/spec-autopilot/tests/test_background_agent_bypass.sh`
  - `bash plugins/spec-autopilot/tests/test_phase65_bypass.sh`

测试结果:
- `run_all.sh` 实测通过: `91 files / 1003 passed / 0 failed`

解释:
- 这证明当前实现与当前测试定义高度一致
- 这不证明当前实现满足你的产品目标，因为部分测试验证的是文档、兼容遗留或局部脚本行为

## 三、逐项核实

### 1. “需求评审完成后应全自动，不应再确认”是否与现状冲突

结论: `是，而且二次评审低估了冲突程度。`

证据:
- `README.zh.md` 的示例默认配置仍是 `after_phase_1: true`，见 `plugins/spec-autopilot/README.zh.md:248-252`
- `autopilot-init/SKILL.md` 虽然定义了 `strict/moderate/relaxed` 三档，但 `relaxed` 同时把默认模式切到 `minimal`，并关闭 code review，见 `plugins/spec-autopilot/skills/autopilot-init/SKILL.md:78-90`
- Phase 7 不是“可选确认”，而是协议明确写死“必须 AskUserQuestion”，见 `plugins/spec-autopilot/skills/autopilot-phase7/SKILL.md:112-122`
- 插件全局 `CLAUDE.md` 明确规定“归档需用户确认”“禁止自动执行”，见 `plugins/spec-autopilot/CLAUDE.md:14`，以及 `plugins/spec-autopilot/skills/autopilot-phase7/SKILL.md:230`

裁定:
- 二次评审建议“把默认预设从 moderate 改为 relaxed”不能满足你的目标
- 原因不是只剩一个小尾巴，而是 `relaxed` 本身通过降级模式与关闭能力换取更少确认点，这属于产品简化
- 同时，Phase 7 自动归档当前被协议和全局法则双重禁止

对原始目标的含义:
- 如果目标是不打断且不简化能力，则必须改的是控制语义本身，而不是切到 `relaxed`

### 2. Phase 1 是否真的存在“主 agent 被污染”的系统性风险

结论: `是，而且二次评审把问题缩小了。`

成立证据:
- 主协议声明“主线程不读取全文”，见 `plugins/spec-autopilot/skills/autopilot/SKILL.md:146-171`
- 但并行协议同时写明“主线程合并 `research-findings.md` 和 `web-research-findings.md` 内容”，见 `plugins/spec-autopilot/skills/autopilot/references/parallel-phase1.md:81`
- 更关键的是，详细协议中明确出现主线程读取 BA 输出文件正文的流程:
  - `analysis_file = Read(ba_envelope.output_file)`，见 `plugins/spec-autopilot/skills/autopilot/references/phase1-requirements-detail.md:563-577`
- Phase 1 research / BA 任务被设计为“不含 autopilot-phase marker”，见 `plugins/spec-autopilot/skills/autopilot-dispatch/SKILL.md:256-287`
- 旧决策格式脚本也直接承认当前设计下 `research/business-analyst` 任务不进该 Hook，见 `plugins/spec-autopilot/runtime/scripts/validate-decision-format.sh:11-14`

裁定:
- 这不是只有一处 `parallel-phase1.md:81` 的文档残留
- 至少有两条协议路径仍允许主线程读取/消费子 agent 正文
- 你的日志中出现“Explore 完成后由主线程写入产出文件”，并不是偶发离谱行为，而是当前协议空间里可以发生的偏移

对原始目标的含义:
- 以“子 agent 不占主 agent 上下文”为目标衡量，Phase 1 现在仍不受控
- 当前 Phase 1 更接近“弱后台化 + 弱约束摘要汇总”，而不是“主线程只保留编排态”

### 3. 主窗口 / GUI 编排信息冲突是否真实存在

结论: `是，且二次评审判断基本准确。`

成立证据:
- `OrchestrationPanel.tsx` 已实现编排信息，但 `App.tsx` 未引用，属死代码:
  - 组件存在: `plugins/spec-autopilot/gui/src/components/OrchestrationPanel.tsx:44-158`
  - 主布局未接入: `plugins/spec-autopilot/gui/src/App.tsx:10-15` 与 `plugins/spec-autopilot/gui/src/App.tsx:177-223`
- `mode` 重复展示:
  - Header: `plugins/spec-autopilot/gui/src/App.tsx:160-164`
  - Timeline 底部: `plugins/spec-autopilot/gui/src/components/PhaseTimeline.tsx:120-123`
- 总耗时重复展示:
  - Timeline: `plugins/spec-autopilot/gui/src/components/PhaseTimeline.tsx:106-109`
  - Telemetry: `plugins/spec-autopilot/gui/src/components/TelemetryDashboard.tsx:122-139`
- 门禁统计重复展示:
  - Timeline: `plugins/spec-autopilot/gui/src/components/PhaseTimeline.tsx:115-118`
  - Session Metrics: `plugins/spec-autopilot/gui/src/components/TelemetryDashboard.tsx:145-148`
  - Gate Statistics: `plugins/spec-autopilot/gui/src/components/TelemetryDashboard.tsx:181-203`
- store 声明了 `decisionLifecycle` 和 `recoverySource`，但 `addEvents` 不写入:
  - 声明: `plugins/spec-autopilot/gui/src/store/index.ts:121-124`
  - 初始化: `plugins/spec-autopilot/gui/src/store/index.ts:350-352`
  - 事件写入缺失: `plugins/spec-autopilot/gui/src/store/index.ts:399-558`

缺失的关键编排信息:
- 当前目标/需求摘要
- gate frontier / next pending gate
- 真正的恢复来源
- 真正的决策状态机

当前被高优先展示但更适合调试视图的信息:
- `cwd`
- `transcript_path`
- `worktree`
- `cost`

对原始目标的含义:
- 当前主窗口不是 orchestration-first，而是 telemetry-first
- 这与“主 agent 最小上下文编排”和“主窗口应展示最必要 AI 流程状态”不一致

### 4. 上下文压缩 / 恢复是否“完全受控”

结论: `否。二次评审关于分层描述是对的，但对“是否足够”判断偏宽。`

生产路径真实情况:
- `save-phase-context.sh` 在 phase 边界保存完整 Markdown 快照，见 `plugins/spec-autopilot/runtime/scripts/save-phase-context.sh:29-121`
- `save-state-before-compact.sh` 压缩前保存:
  - checkpoint summary 截到 80 字，见 `plugins/spec-autopilot/runtime/scripts/save-state-before-compact.sh:292`
  - phase5 task summary 截到 60 字，见 `plugins/spec-autopilot/runtime/scripts/save-state-before-compact.sh:218-222`
  - phase context snapshot 每 phase 截到 1000 字，见 `plugins/spec-autopilot/runtime/scripts/save-state-before-compact.sh:157-172`
- `reinject-state-after-compact.sh` 恢复时:
  - 直接把 `autopilot-state.md` 打回 stdout，见 `plugins/spec-autopilot/runtime/scripts/reinject-state-after-compact.sh:58-63`
  - 所有 phase snapshot 总预算再限制到 4000 字，见 `plugins/spec-autopilot/runtime/scripts/reinject-state-after-compact.sh:64-100`
  - 再用 `sed` 提取 `next_phase` / `mode` / `change` / `in-progress sub-step` 形成自然语言恢复指令，见 `plugins/spec-autopilot/runtime/scripts/reinject-state-after-compact.sh:103-133`
- `scan-checkpoints-on-start.sh` 新会话启动时只注入 checkpoint 摘要，summary 截到 60 字，见 `plugins/spec-autopilot/runtime/scripts/scan-checkpoints-on-start.sh:57-68`
- `autopilot-recovery/SKILL.md` 的恢复协议仍要求“读取快照段落并拼接摘要注入主线程”，见 `plugins/spec-autopilot/skills/autopilot-recovery/SKILL.md:177-201`

裁定:
- 当前恢复不是结构化状态重放
- 它是“磁盘上有较完整原始文件 + 注入主线程时使用截断 Markdown + 少量结构化字段辅助”
- 这对于“让 agent 大概率接着跑”是实用的
- 但对于“完全受控、可验证、恢复前后上下文保真可证明”的目标，还不够

对原始目标的含义:
- 不能把当前恢复描述成“已经满足设计预期”
- 只能描述成“有较强持久化基础，但主线程恢复仍依赖摘要再理解”

### 5. 崩溃恢复整体是否符合设计预期

结论: `部分符合。扫描与恢复判定比较完整，但结束态完整性仍不闭环。`

成立证据:
- `recovery-decision.sh` 会扫描 checkpoint、gap、progress、git 风险、fixup 数量、anchor 状态，并给出 `auto_continue_eligible`，见 `plugins/spec-autopilot/runtime/scripts/recovery-decision.sh:96-149`、`plugins/spec-autopilot/runtime/scripts/recovery-decision.sh:297-477`
- `autopilot-recovery/SKILL.md` 已把恢复步骤绑定到 `recovery-decision.sh` JSON，不再鼓励主线程随意内联 bash 决策，见 `plugins/spec-autopilot/skills/autopilot-recovery/SKILL.md:36-59`
- `test_recovery_auto_continue.sh` 与 `test_e2e_checkpoint_recovery.sh` 已覆盖单候选自动继续、git 风险、高低模式序列、gap 恢复等路径

仍然不闭环的点:
- 恢复只保证“从哪继续”较强，不保证“结束后 fixup/归档一致性”较强
- `fixup_commit_count` 被恢复逻辑识别，但并不会在恢复阶段闭合成强约束，见 `plugins/spec-autopilot/runtime/scripts/recovery-decision.sh:127-149` 与 `plugins/spec-autopilot/skills/autopilot-recovery/SKILL.md:66-69`

裁定:
- 崩溃恢复前半程较强
- 产品级“完整恢复闭环”仍被 Phase 7 收口能力拖后腿

### 6. fixup / anchor / autosquash 是否完全符合预期

结论: `否。二次评审这部分判断成立。`

成立证据:
- Phase 7 对 `FIXUP_COUNT < CHECKPOINT_COUNT` 仅警告，不阻断，见 `plugins/spec-autopilot/skills/autopilot-phase7/SKILL.md:135-144`
- `rebuild-anchor.sh` 新建 commit message 为 `autopilot: anchor (recovery)`，见 `plugins/spec-autopilot/runtime/scripts/rebuild-anchor.sh:29-30`
- 原始 anchor message 体系是 `autopilot: start <name>`，见 `plugins/spec-autopilot/docs/architecture/phases.md:32`
- `git rebase --autosquash` 依赖 fixup message 与目标 commit message 匹配，因此 message 改型会造成 squash 目标失配风险
- `autopilot-phase0/SKILL.md` 仍写“anchor 无效则跳过 autosquash 并警告”，见 `plugins/spec-autopilot/skills/autopilot-phase0/SKILL.md:245`
- 但 `autopilot-phase7/SKILL.md` 实际已改成“先重建，再失败后询问”，见 `plugins/spec-autopilot/skills/autopilot-phase7/SKILL.md:151-160`

裁定:
- 二次评审关于 `rebuild-anchor.sh` 和 Phase 0/7 文档不一致的判断成立
- 对“本次迭代 fixup 是否全部合并且无遗漏”这一目标，当前系统仍不能给出确定性保证

### 7. “背景 agent bypass 是生产主链重大缺陷”是否成立

结论: `不作为生产主链 P0 缺陷成立；但作为仓库治理问题成立。`

生产主路径真实情况:
- `hooks.json` 的 `PostToolUse(Task)` 当前只注册统一入口 `post-task-validator.sh`，见 `plugins/spec-autopilot/hooks/hooks.json:52-63`
- `post-task-validator.sh` 明确记录了 v5.1 已取消后台 agent 整体跳过校验，见 `plugins/spec-autopilot/runtime/scripts/post-task-validator.sh:22-35`

遗留/兼容路径情况:
- `validate-json-envelope.sh`、`anti-rationalization-check.sh`、`code-constraint-check.sh` 都是 `DEPRECATED`，且各自仍有 background bypass，见:
  - `plugins/spec-autopilot/runtime/scripts/validate-json-envelope.sh:2,24-25`
  - `plugins/spec-autopilot/runtime/scripts/anti-rationalization-check.sh:3-7,26-27`
  - `plugins/spec-autopilot/runtime/scripts/code-constraint-check.sh:3-7,17-18`
- `test_background_agent_bypass.sh` 也明确注明“部分 case 测的是 deprecated scripts”，见 `plugins/spec-autopilot/tests/test_background_agent_bypass.sh:2-4`

裁定:
- 二次评审纠正“生产主路径仍然 background bypass”这点是对的
- 但从产品治理角度看，这些脚本与测试仍然会制造理解歧义，不应被视作无害

### 8. Phase 6.5 代码审查只是 advisory，是否还能满足“高质量自动化”

结论: `现状不能。二次评审把“设计合理”说得过轻。`

成立证据:
- `autopilot-gate/SKILL.md` 将 6.5 明确标为 advisory gate，见 `plugins/spec-autopilot/skills/autopilot-gate/SKILL.md:203-220`
- `autopilot-phase7/SKILL.md` 明确写“optional/advisory，不作为 Phase 7 硬前置条件”，见 `plugins/spec-autopilot/skills/autopilot-phase7/SKILL.md:76-83`
- `test_phase65_bypass.sh` 验证了 6.5 无 phase marker，校验链跳过，见 `plugins/spec-autopilot/tests/test_phase65_bypass.sh:12-24`
- `test_phase6_independent.sh` 验证了 Phase 6 不依赖 6.5 findings，见 `plugins/spec-autopilot/tests/test_phase6_independent.sh:12-17`

裁定:
- 如果目标只是“保留吞吐并让 review 可展示”，当前设计成立
- 如果目标是“自动流程中的 code review 质量有决定性约束”，当前设计不成立
- 二次评审坚持保留 advisory，本质上是在接受“review 不决定产出”的设计

### 9. OpenSpec / OpenSpec FF 是否会异常越权

结论: `当前没有发现“绕过门禁”的证据；二次评审在这点上基本正确。`

成立证据:
- Phase 3 在非 full 模式会被前驱检查直接拒绝，见 `plugins/spec-autopilot/runtime/scripts/check-predecessor-checkpoint.sh:260-275`
- `_post_task_validator.py` 现在已经对 Phase 2 和 3 做了额外硬校验:
  - Phase 2: `artifacts` 非空且必须有 `alternatives`，见 `plugins/spec-autopilot/runtime/scripts/_post_task_validator.py:179-185`
  - Phase 3: `plan` 非空且必须有 `test_strategy`，见 `plugins/spec-autopilot/runtime/scripts/_post_task_validator.py:187-193`
- 黑盒测试已覆盖这两条:
  - `plugins/spec-autopilot/tests/test_phase2_artifacts_required.sh:16-60`
  - `plugins/spec-autopilot/tests/test_phase3_plan_required.sh:16-69`

裁定:
- “FF 会直接绕过门禁”这一冲突点，本次核实不成立
- 当前真实问题不在 FF 越权，而仍在更前面的 Phase 1 需求事实源与主线程上下文边界

### 10. `.claude` 多 agent 优先级是否可控

结论: `当前不可控，二次评审成立。`

成立证据:
- `rules-scanner.sh` 只看 `.claude/rules` 与 `CLAUDE.md`，见 `plugins/spec-autopilot/runtime/scripts/rules-scanner.sh:12-19`
- 其扫描实现没有 `.claude/agents` 路径，见 `plugins/spec-autopilot/runtime/scripts/rules-scanner.sh:46-154`
- `auto-emit-agent-dispatch.sh` 只审计 `subagent_type` 与 background 标记，不处理优先级、选择理由、候选 agent 比较，见 `plugins/spec-autopilot/runtime/scripts/auto-emit-agent-dispatch.sh:120-155`

裁定:
- 如果项目未来在 `.claude/agents` 下配置多个 agent，当前插件无法保证谁优先、为什么被选中、是否命中了预期 agent

## 四、对二次评审的最终裁定

### 二次评审正确的部分

1. GUI/主窗口冲突点基本全对
2. `rebuild-anchor.sh` 与 fixup fail-open 的判断基本全对
3. `rules-scanner` 不扫描 `.claude/agents` 的判断是对的
4. “背景 agent bypass 不应按生产主链 P0 报告”这个纠偏是对的
5. OpenSpec/FF 并未表现出明显越权，这个纠偏也是对的

### 二次评审不够到位的部分

1. 把“自动推进”收敛成“改默认 preset 为 relaxed”
   - 这会降低默认模式和能力，属于简化，不符合你的目标
2. 把 Phase 1 冲突收敛成“一处遗留文档”
   - 实际至少还存在 `phase1-requirements-detail.md` 中主线程读取 BA 全文的流程
3. 把当前恢复评价为“实用上足够”
   - 对“完全受控恢复”目标而言，这个评价偏松
4. 保留 Phase 7 归档确认
   - 这与“需求评审完成后自动完成全部后续阶段”的目标直接冲突
5. 把 advisory code review 视为合理折中
   - 这与“如何保证 review 质量、如何保证 TDD 代码符合预期”的目标并不相容

## 五、面向原始目标的结论

如果以你的原始目标为准，而不是以“尽量少改现有系统”为准，那么当前插件的真实状态是:

1. `自动推进目标未达成`
- 不是配置默认值小问题，而是 Phase 7 自动归档被协议级禁止

2. `主 agent 最小上下文目标未达成`
- 尤其在 Phase 1，协议里仍允许主线程读取/合并子 agent 正文

3. `上下文恢复完全受控目标未达成`
- 当前恢复是多层保存 + 有损回灌，不是严格 replay

4. `代码审查决定性约束目标未达成`
- 6.5 仍是 advisory，不足以构成高质量自动流水线的最终约束

5. `主窗口编排优先目标未达成`
- 编排面板未接线，关键编排态缺失，反而把遥测信息放在主视区

## 六、建议的后续处理顺序

本报告不展开完整改造方案，只给出与原始目标直接对应的纠偏优先级:

### P0

1. 取消“通过 relaxed 规避确认点”的思路，直接重写自动推进语义
2. 取消 Phase 1 主线程读取/合并正文的所有协议分支，建立单一 requirement packet 事实源
3. 去掉 Phase 7 强制确认铁律，改成受策略控制的自动归档闭环
4. 将 fixup 完整性从 warning 提升为 fail-closed
5. 修复 `rebuild-anchor.sh` 的 anchor message 兼容性
6. 接通 `OrchestrationPanel` 和 `decisionLifecycle` / `recoverySource` 事件链

### P1

1. 将恢复从 Markdown 摘要回灌升级为结构化状态恢复
2. 给 `.claude/agents` 建立可验证的优先级和选择理由记录
3. 将 Phase 6.5 findings 升级为决定性归档输入，而不是 advisory 装饰
4. 为 Phase 1 主线程隔离建立黑盒测试，验证“主线程不读全文、不代写正文工件”

### P2

1. 清理 deprecated validator 脚本与命名误导性测试
2. 给测试体系加标签，区分 behavioral / compatibility / doc-compliance

## 七、最终结论

本次核实后的结论是:

- 二次评审不是错的，但它站在“尽量保留现有设计”的角度，给了几条对你目标并不够硬的裁定
- 如果坚持你的原始目标不变，那么插件当前最核心的问题仍然是:
  - 自动推进语义不对
  - Phase 1 主线程上下文边界不对
  - 恢复仍非完全受控
  - review 与归档闭环不够决定性
  - 主窗口没有真正承载编排控制面

- 因此，后续应当做的是“增强现有编排器并把控制边界做硬”，而不是“通过 relaxed/保留 advisory/保留归档确认来把问题解释为合理设计”。
