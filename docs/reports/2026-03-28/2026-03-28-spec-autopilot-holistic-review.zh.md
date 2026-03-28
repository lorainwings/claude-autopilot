# spec-autopilot 整体架构深度评审

日期: 2026-03-28
范围: `plugins/spec-autopilot`
方法:
- 代码与协议审查: `CLAUDE.md`、`skills/`、`runtime/scripts/`、`runtime/server/`、`gui/`
- 测试基线核查: 执行 `bash plugins/spec-autopilot/tests/run_all.sh`
- 结果: `91 files / 1003 passed / 0 failed`

说明:
- 下面的“已证实”指我直接在仓库代码或测试中看到的实现与行为。
- 下面的“推断”指基于协议、提示词和脚本边界推出的产品级风险，没有把它伪装成已运行的真实线上会话事实。
- 我没有执行一个真实 Claude 交互式 full/lite/minimal 端到端会话，因为这依赖外部子 agent 和交互环境；本报告基于脚本级仿真、Hook 行为、技能协议和测试基线给出结论。

## 一、总评

结论先行:
- 这套系统的脚本层严谨度明显高于普通“提示词工程”插件，特别是在 phase graph、checkpoint、zero-skip、TDD 写入隔离、恢复清理、GUI 事件采集上，已经形成了较完整的工程骨架。
- 但产品层存在明显“控制闭环不一致”问题，核心矛盾集中在 Phase 1、上下文恢复、fixup 归档、Phase 6.5 代码审查、主窗口信息架构上。
- 当前版本更像“高仪式感、强约束的实验性编排器”，不是一个已经收敛到商业化最优形态的产品。
- 如果不先收敛控制边界，这套设计会继续出现“文档说不该这样，实际又这样”的偏差。

总体判断:
- 工程完整度: 高
- 产品闭环一致性: 中
- 上下文治理成熟度: 中偏低
- 崩溃恢复可靠性: 中上
- 测试真实性: 中
- 商业化准备度: 中偏低
- 过度设计程度: 中到高

## 二、关键结论摘要

### 1. 三种模式 full/lite/minimal 的主干状态机基本成立，但自动化目标与产品诉求不一致

已证实:
- 模式序列在代码和测试中是一致的:
  - full: `1 2 3 4 5 6 7`
  - lite: `1 5 6 7`
  - minimal: `1 5 7`
- 证据:
  - `plugins/spec-autopilot/runtime/scripts/check-predecessor-checkpoint.sh:242-392`
  - `plugins/spec-autopilot/tests/integration/test_e2e_checkpoint_recovery.sh:146-225`
  - `plugins/spec-autopilot/tests/test_lite_mode.sh:16-34`
  - `plugins/spec-autopilot/tests/test_minimal_mode.sh:14-24`

问题:
- 默认配置明确要求 `after_phase_1: true`，这与“需求评审后所有阶段自动完成，不应该中断”的产品需求直接冲突。
- 证据:
  - `plugins/spec-autopilot/README.zh.md:248-252`
  - `plugins/spec-autopilot/skills/autopilot/SKILL.md:186`

结论:
- 模式切换是稳定的。
- 自动化体验不是稳定的，因为人为确认点是默认设计，不是 bug。

### 2. Phase 1 是当前架构最不稳定的区域

这是全局最高优先级问题。

已证实:
- 主协议明确宣称:
  - 子 agent 自己写文件
  - 主线程不读取全文
  - business-analyst 也后台运行，不占主窗口上下文
- 证据:
  - `plugins/spec-autopilot/skills/autopilot/SKILL.md:146-171`

但同仓库另一份并行协议又明确写着:
- “等待全部完成 → 主线程合并 `research-findings.md` 和 `web-research-findings.md` 的内容 → 传递给 business-analyst 分析”
- 证据:
  - `plugins/spec-autopilot/skills/autopilot/references/parallel-phase1.md:81`

这意味着:
- Phase 1 存在协议级自相矛盾。
- 你的日志里出现“Explore 完成后由主线程写入产出文件”，并不让我意外；它与现有协议漂移是同方向的。

进一步问题:
- Phase 1 的 research/business-analyst 任务明确“不含 `autopilot-phase` 标记”，因此不走统一的 phase marker 门禁链。
- 证据:
  - `plugins/spec-autopilot/skills/autopilot-dispatch/SKILL.md:258-287`
  - `plugins/spec-autopilot/runtime/scripts/post-task-validator.sh:19-35`
  - `plugins/spec-autopilot/runtime/scripts/validate-decision-format.sh:11-14`

影响:
- Phase 1 既是最依赖高质量上下文的阶段，又是当前最弱确定性校验的阶段。
- 需求调研、需求分析、决策卡片之间没有一个真正 fail-closed 的“单一事实源”。
- 这会直接造成:
  - 主 agent 上下文污染
  - 需求来源漂移
  - 用户日志里看到主线程补写文件
  - 需求理解质量高度依赖提示词，而不是系统约束

结论:
- Phase 1 不是“受控编排”。
- 它是“部分后台化 + 部分主线程汇总 + 部分提示词约束”的混合态。

### 3. 上下文压缩恢复不是“完整恢复”，而是“摘要回灌”

已证实:
- 压缩前保存的是 markdown 摘要，不是结构化运行时快照:
  - phase 状态表
  - tasks summary
  - progress entries
  - phase5 task summary
  - 每个 snapshot 最多取前 1000 字符
- 证据:
  - `plugins/spec-autopilot/runtime/scripts/save-state-before-compact.sh:100-171`
  - `plugins/spec-autopilot/runtime/scripts/save-state-before-compact.sh:175-224`
  - `plugins/spec-autopilot/runtime/scripts/save-state-before-compact.sh:233-330`

已证实:
- 压缩后 reinject 只是把 `autopilot-state.md` 直接打印到 stdout，并把所有 phase snapshot 合并后再额外限制总量 4000 字符。
- 证据:
  - `plugins/spec-autopilot/runtime/scripts/reinject-state-after-compact.sh:58-99`
  - `plugins/spec-autopilot/runtime/scripts/reinject-state-after-compact.sh:103-129`

已证实:
- SessionStart 还会额外把 checkpoint summary 注入上下文。
- 证据:
  - `plugins/spec-autopilot/runtime/scripts/scan-checkpoints-on-start.sh:77-197`

因此当前“保存了什么上下文”:
- phase 级别状态
- 截断后的 phase summary
- 截断后的 phase context snapshot
- 部分 task 进度
- 下一阶段提示

当前“没有严格保存”的内容:
- 原始调研全文
- 完整需求讨论历史
- AskUserQuestion 的完整决策链
- 主线程真实思考上下文
- GUI 当前面板状态
- phase 之间所有引用关系的机器可读恢复图

结论:
- 当前恢复是“足够让一个聪明 agent 猜着接着跑”。
- 不是“完全受控的、可验证的、可回放的状态恢复”。

### 4. 崩溃恢复主流程总体可用，但 fixup/anchor/人工分支仍然是 fail-open

已证实的优点:
- `recovery-decision.sh` 对 checkpoint、gap、progress、worktree residual、git risk、fixup count 做了系统扫描。
- 证据:
  - `plugins/spec-autopilot/runtime/scripts/recovery-decision.sh:96-149`
  - `plugins/spec-autopilot/runtime/scripts/recovery-decision.sh:151-260`
- `clean-phase-artifacts.sh` 的测试覆盖较强，且保留用户 WIP 的回退行为是加分项。
- 证据:
  - `plugins/spec-autopilot/tests/run_all.sh` 输出中 `Clean Phase Artifacts tests`

关键问题:
- fixup 完整性检查在归档阶段只是 warning，不阻断。
- 证据:
  - `plugins/spec-autopilot/skills/autopilot-phase7/SKILL.md:135-144`
- anchor 无效时允许用户“跳过 autosquash，保留所有 fixup commits 完成归档”。
- 证据:
  - `plugins/spec-autopilot/skills/autopilot-phase7/SKILL.md:151-160`

影响:
- 你问“是否将本次迭代所有 fixup 全部合并到一起了，且无遗漏？”当前答案是: 系统没有做到确定性保证，只做了提示。
- 这不符合“无任何遗漏”的产品承诺。

结论:
- 恢复扫描做得比归档收口更强。
- 真正脆弱的地方不在“能不能恢复”，而在“恢复/结束后是否保持提交历史完整”。

### 5. 背景 agent 的 L2 校验闭环只在部分路径成立

已证实:
- 统一后置验证器 `post-task-validator.sh` 已修正为“背景 agent 完成后也校验”。
- 证据:
  - `plugins/spec-autopilot/runtime/scripts/post-task-validator.sh:22-35`

但同样已证实:
- 多个旧 Hook/兼容脚本仍对 background agent 直接 bypass。
- 测试甚至把这种 bypass 当成预期行为。
- 证据:
  - `plugins/spec-autopilot/runtime/scripts/validate-json-envelope.sh:22-30`
  - `plugins/spec-autopilot/runtime/scripts/anti-rationalization-check.sh:24-33`
  - `plugins/spec-autopilot/runtime/scripts/code-constraint-check.sh:17-24`
  - `plugins/spec-autopilot/tests/test_background_agent_bypass.sh:20-55`

更关键的是:
- `CLAUDE.md` 明确写了“背景 Agent 必须接受 L2 验证”。
- 证据:
  - `plugins/spec-autopilot/CLAUDE.md:57-59`

结论:
- Phase 2-6 主干路径现在大部分靠统一验证器补回来了。
- 但“背景 agent 全面受控”这个说法仍然过头，尤其对 Phase 1 和 6.5 不成立。

### 6. Phase 6.5 代码审查不是独立门禁，只是 advisory

已证实:
- 测试明确验证了“Phase 6.5 无 autopilot-phase marker，因此跳过前驱检查和 envelope 校验”。
- 证据:
  - `plugins/spec-autopilot/tests/test_phase65_bypass.sh:12-24`
- 测试明确验证了“Phase 6 可以不依赖 6.5 的 findings/metrics”。
- 证据:
  - `plugins/spec-autopilot/tests/test_phase6_independent.sh:12-17`
- Phase 7 协议也明确把 code review 设计成 optional/advisory，不是硬前置条件。
- 证据:
  - `plugins/spec-autopilot/skills/autopilot-phase7/SKILL.md:46-88`

结论:
- 这会降低吞吐阻力，但不能回答“如何保证 code review 质量”。
- 现状只能回答“可以做 review，可观测，可展示 findings”，不能回答“review 结果决定性地约束产出”。

### 7. 测试覆盖很广，但存在“文档即测试”的 Hack Reward 风险

已证实:
- 一部分测试直接 grep `SKILL.md` / 文档，而不是验证真实运行时行为。
- 例子:
  - `plugins/spec-autopilot/tests/test_fixup_commit.sh:12-19`
  - `plugins/spec-autopilot/tests/test_search_policy.sh:18-55`

这类测试的风险:
- 改文档就能绿
- 真正的运行时没有变
- 奖励的是“补协议文本”，不是“补系统闭环”

但也要客观:
- 另一大类测试是真正有价值的脚本行为测试，例如:
  - 模式流转
  - recovery decision
  - checkpoint gap
  - TDD 写入隔离
  - clean-phase-artifacts
  - statusline/server robustness

结论:
- 测试体系不是弱。
- 但“产品需求映射测试”和“协议文字一致性测试”混在一起，导致覆盖率高，不等于产品可靠性高。

### 8. 主窗口信息结构有可视化深度，但产品信息优先级不合理

已证实的当前展示:
- Header: change / session / mode / connected
  - `plugins/spec-autopilot/gui/src/App.tsx:145-166`
- 左侧时间轴: phase 节点 + 总耗时 + 阶段完成数 + 门禁数 + mode
  - `plugins/spec-autopilot/gui/src/components/PhaseTimeline.tsx:43-125`
- 右侧遥测: model / cwd / cost / worktree / transcript_path / totalElapsed / gateStats / parallelPlan
  - `plugins/spec-autopilot/gui/src/components/TelemetryDashboard.tsx:73-206`
- 中间 Kanban: agent 卡片、工具调用数、产出文件、tool_use
  - `plugins/spec-autopilot/gui/src/components/ParallelKanban.tsx:128-240`

我认为主窗口真正必要的信息应该是:
1. 当前目标是什么
2. 当前处于哪个 phase，下一步要什么
3. 当前阻断点是什么
4. 哪些 agent 在跑，负责什么 owned_files
5. 当前产出是否满足门禁
6. 如果恢复，会从哪一步继续
7. 当前上下文预算/恢复状态是否安全

当前主窗口的冗余信息:
- 总耗时在左侧和右侧重复
- 门禁统计在左侧和右侧重复
- mode 在 Header 和左侧重复
- `cwd` / `transcript_path` / `worktree` 更像调试信息，不该占高优先级

当前主窗口缺失的高价值信息:
- 需求摘要 / 本次 change 的目标
- 当前 gate frontier
- 当前恢复来源（fresh/recovery）
- 当前 checkpoint / anchor_sha / fixup 状态
- agent 的 owned_files 与 domain
- 当前 phase 的输入合同和产出合同是否满足

结论:
- 现在的 GUI 更像“技术监控台”。
- 不是“主窗口编排台”。

## 三、逐项回答你的 13 个问题

### 1. full / lite / minimal 全流程仿真和测试

已证实:
- 三种模式在脚本层可达且前驱约束基本一致。
- lite/minimal 跳过的 phase 被 gate 正常阻断。
- 全量测试通过。

设计不合理点:
- 自动化体验仍会在 Phase 1 后中断，默认配置与产品需求不一致。
- full 模式最重的风险不在状态机，而在 Phase 1 上下文污染和 Phase 6.5 review 非硬门禁。
- lite/minimal 省略 OpenSpec/测试报告后，虽然速度快，但也进一步弱化了需求约束和证据链，适合小任务，不适合商业化“可审计交付”。

建议:
- 把“阶段是否自动继续”从用户确认门禁，改成 run policy:
  - `interactive`
  - `semi_auto`
  - `full_auto`
- 默认对 autopilot 使用 `full_auto`，仅把 archive 保留为单一人工关口，或者在企业模式下也可自动。

### 2. 主窗口 agent 信息必要性、冗余与最佳编排

必要信息:
- 任务目标摘要
- 当前 phase / sub-step
- 当前 gate 状态
- 活跃 agent 列表
- 每个 agent 的 domain / owned_files / status / ETA
- 当前恢复来源和风险
- fixup / checkpoint / anchor 健康度

冗余信息:
- `cwd`
- `transcript_path`
- 重复展示的总耗时、门禁统计、mode

最佳实践:
- 主窗口只放“编排层真相”
- 调试数据移到二级面板
- 每个 agent 卡片必须显示:
  - 输入合同
  - owned_files
  - 当前重试轮次
  - 当前模型
  - 预期产出
- GateBlockCard 应显示:
  - 阻断证据
  - 推荐动作
  - 动作影响范围

### 3. 上下文压缩流程是否完全受控

结论: 否。

当前受控部分:
- phase 状态、next phase、部分 task 进度、部分 snapshot 被保存。

当前不受控部分:
- snapshot 截断
- 总量裁剪
- 恢复依赖自然语言再理解，不是结构化状态回放
- SessionStart 额外注入 checkpoint summary，反而会继续占主上下文

是否保留足够上下文:
- 对“继续跑起来”通常够。
- 对“保证恢复后召回内容完全符合预期”不够。

建议:
- 保存机器可读 state JSON，而不是只保存 markdown
- phase context snapshot 只做人类可读副本
- reinject 优先注入结构化 JSON 摘要，次要再提供 markdown
- 为恢复加入 checksum:
  - checkpoint set hash
  - decision ledger hash
  - task graph hash

### 4. 崩溃恢复是否符合设计预期

总体上:
- checkpoint 扫描、gap 检测、progress 子步骤恢复、worktree 残留清理，这些都符合“恢复编排器”的设计预期。

缺口:
- fixup/anchor 结束态不是 fail-closed
- 压缩恢复仍然是摘要型
- 多个人工分支存在“允许继续但状态不完全收敛”的路径

优化:
- 对 fixup completeness 改为硬阻断
- anchor 重建失败禁止归档完成
- 恢复成功后增加 “state reconciliation report”
- 恢复后第一步先做状态对账，不要直接继续 phase

### 5. 需求评审是否有更好方案，三路 agent 是否必要

我的判断:
- 三路 agent 不是默认必要。
- 对大多数任务，应该是:
  - 单路 Auto-Scan
  - 必要时再触发技术调研
  - 只有外部知识不稳定时再触发 web research

更好方案:
- 把 Phase 1 拆成两层:
  - Layer A: 事实采集层，纯文件产出，不允许主线程整理全文
  - Layer B: 决策合成层，只消费结构化 facts

如何让 AI 更懂需求:
- 建立 canonical requirement packet:
  - raw_requirement
  - resolved_decisions
  - unresolved_questions
  - assumptions
  - non_functional_requirements
  - acceptance_criteria
- 任何后续 phase 只读这个 packet，不再反复读散落文档

如何保证需求来源稳定:
- Phase 1 最终必须生成单一 `requirements-contract.json`
- 后续 phase 只认这个文件，不认自由文本汇总

从提示词工程化入手:
- 少做“大段综合 prompt”
- 多做“输入合同 + 输出合同 + 约束字段 + 反例”
- 把 `decision_points` 变成 schema，不要只靠 markdown 卡片

### 6. OpenSpec 与 openspec ff 流程是否有异常风险

当前优点:
- Phase 2/3 已有 envelope 约束:
  - Phase 2 必须有 `artifacts` 和 `alternatives`
  - Phase 3 必须有 `plan` 和 `test_strategy`
- 证据:
  - `plugins/spec-autopilot/runtime/scripts/_post_task_validator.py:179-193`
  - `plugins/spec-autopilot/tests/test_phase2_artifacts_required.sh:16-60`
  - `plugins/spec-autopilot/tests/test_phase3_plan_required.sh:16-69`

风险:
- 这些验证更像“产出了看起来像样的 envelope”，不等于 OpenSpec 制品与需求真正一致。
- Phase 2/3 虽然后台化了主窗口占用，但如果产物语义错误，当前系统主要还是靠后续 phase 或人工发现。

建议:
- 为 OpenSpec 制品增加 schema 级和引用级验证:
  - proposal/spec/design/tasks 文件存在性
  - tasks 是否覆盖 acceptance criteria
  - spec 章节是否映射已决策字段
  - FF 结果是否回写 change name / requirement type / test strategy

### 7. 测试用例是否贴合产品需求，如何避免 Hack Reward

现状:
- Hook/脚本行为测试很强。
- 产品闭环测试偏弱。
- 一部分测试验证“文档里有没有写”，不是“系统有没有做到”。

如何提升:
- 按产品需求建立测试层次:
  - L0: schema / parser / helper
  - L1: hook / gate
  - L2: phase contract
  - L3: scenario integration
  - L4: anti-gaming tests

如何保证独立性:
- code review agent 的结果必须由独立 gate 消费
- Phase 5 产物不能由同一 agent 自证合格
- recovery 测试要验证恢复前后 artifact hash 一致

如何避免 Hack Reward:
- 禁止新增只验证文档字符串的测试作为主回归依据
- 为每个协议测试配一个运行时黑盒测试
- 将“文档断言测试”单列为 doc-compliance，不计入主可靠性评分

### 8. 是否严格遵守 rules / 全局 CLAUDE.md，如何判断是否用了要求的子 agent

当前能做到的:
- runtime 事件会记录 `subagent_type`
- 证据:
  - `plugins/spec-autopilot/runtime/scripts/auto-emit-agent-dispatch.sh:126-155`
  - `plugins/spec-autopilot/runtime/scripts/auto-emit-agent-complete.sh:182-199`

当前做不到的:
- 系统没有校验“是否选择了项目要求的优先 agent”
- `rules-scanner.sh` 只扫描 `.claude/rules/` 和顶层 `CLAUDE.md`，不扫描 `.claude/agents` 之类的 agent 注册与优先级配置
- 证据:
  - `plugins/spec-autopilot/runtime/scripts/rules-scanner.sh:12-19`
  - `plugins/spec-autopilot/runtime/scripts/rules-scanner.sh:46-154`

因此:
- 现在可以观察“用了什么 agent”
- 但不能强约束“必须用哪个 agent，优先级是否正确”

建议:
- 新增 `agent_policy.json`
  - phase -> required_agent_family
  - domain -> preferred_agent
  - fallback order
  - forbidden_agent_types
- dispatch 前强校验，dispatch 后事件审计复核

### 9. Phase 5/6 TDD、独立性、review 质量

优点:
- TDD 写入隔离在 Hook 层是强的。
- 证据:
  - `plugins/spec-autopilot/tests/test_tdd_isolation.sh:1-89`
- Phase 5 `zero_skip_check`、`tdd_metrics` 等后置约束也比较完整。
- 证据:
  - `plugins/spec-autopilot/runtime/scripts/_post_task_validator.py:142-165`

缺点:
- Review 质量没有同级别的确定性保障。
- Phase 6.5 目前只是 advisory，不是独立硬门禁。

建议:
- TDD 保持现有 L2 强约束
- 代码 review 升级为真正 Gate:
  - findings schema
  - severity policy
  - mandatory second-pass verifier
  - 与归档硬绑定

### 10. fixup 合并是否符合预期，是否全部合并无遗漏

结论:
- 当前系统没有做到确定性保证。
- 它做的是“归档前检查并提示”，不是“确保全部 fixup 被完整收敛”。

根因:
- `FIXUP_COUNT < CHECKPOINT_COUNT` 只是 warning。
- rebase/anchor 异常允许继续。

建议:
- Phase 7 改为:
  - fixup completeness mismatch -> blocked
  - anchor rebuild fail -> blocked
  - autosquash fail -> blocked
  - 只有全部收敛后才允许 `phase-7-summary.json = ok`

### 11. 每个阶段门禁的意义是什么？上下文恢复的意义是什么？

门禁的真正意义:
- 不是“多一层检查”
- 而是“阻止错误状态继续放大”

各门禁的意义:
- Phase 1 -> 2: 冻结需求，避免带着模糊需求生成规范
- Phase 4 -> 5: 冻结测试设计，避免实现先行挤压测试
- Phase 5 -> 6: 冻结实现质量，确保 zero-skip 和任务完成
- Phase 6/6.5 -> 7: 冻结验证结论，确保归档不是掩盖问题

上下文恢复的意义:
- 不是省 token
- 是让编排器在长时任务中保持“状态连续性”和“责任连续性”

当前问题在于:
- 它已经实现了“继续跑”
- 但还没有实现“恢复后仍然是同一个确定性系统”

### 12. 整体产品流程和设计理念是否合理，是否符合 harness 理念，商业价值如何

我的判断:
- 这套流程部分符合社区对 harness 的核心理念:
  - 明确状态机
  - 强制 gate
  - 可恢复
  - 有审计和可观测性

但它也偏离了经典 harness 的几个关键原则:
- 把太多产品经理流程、规范生成、交互、GUI、归档、autosquash 全塞进一个大 orchestrator
- 让 Phase 1 成为半提示词、半编排、半人工决策的复杂混合区
- 把系统复杂度堆高到“需要大量文档才能解释自己”

对 AI 缺点的规避程度:
- 对“跳步骤、偷懒、伪完成”规避得不错
- 对“需求误解、上下文污染、恢复失真、review 走过场”规避得不够

对 AI 优点的利用:
- 利用了:
  - 快速生成
  - 大量并行调研
  - 自动报告
  - 结构化 checkpoint
- 但没有把“主模型上下文稀缺”这件事真正贯彻到底，尤其在 Phase 1

从资深产品经理角度:
- 产品差异化明显
- 技术观赏性很强
- 商业化价值存在，尤其在“高合规、长流程、可审计交付”方向
- 但当前版本对普通团队来说偏重、偏复杂、学习成本高

是否过度设计:
- 是，有一定过度设计
- 过度设计集中在:
  - Phase 1 仪式感过强
  - GUI 信息层次过多
  - fixup/archive 流程复杂但仍非闭环
  - 太多行为放在 SKILL 文本而不是确定性 runtime

## 四、对你补充的 2 个问题的直接回答

### A. “需求评审完成后，所有阶段应该自动完成，不应该中断”

结论:
- 当前实现不满足。
- 这不是偶发现象，而是默认产品策略如此。

证据:
- `plugins/spec-autopilot/README.zh.md:248-252`
- `plugins/spec-autopilot/skills/autopilot/SKILL.md:186`
- `plugins/spec-autopilot/skills/autopilot-phase7/SKILL.md:104-122`

建议:
- 立刻新增 `orchestration.auto_continue_after_phase1 = true`
- 对 autopilot 默认 profile 改成:
  - `after_phase_1: false`
  - `after_phase_3: false`
  - `after_phase_4: false`
- 将 archive 从“必须 AskUser”改为策略项，而不是硬编码产品哲学

### B. “子 agent 不要占用主 agent 上下文，但现在需求评审直接在主 agent 写入了”

结论:
- 你的观察与仓库内部协议冲突完全一致。
- 不是你误判，是系统在 Phase 1 上确实存在协议漂移。

证据链:
- 主协议说主线程不读全文、子 agent 自写文件:
  - `plugins/spec-autopilot/skills/autopilot/SKILL.md:146-171`
- 并行协议又说主线程合并 research 文件内容:
  - `plugins/spec-autopilot/skills/autopilot/references/parallel-phase1.md:81`
- Phase 1 research / BA 任务不带 phase marker，不走统一 gate:
  - `plugins/spec-autopilot/skills/autopilot-dispatch/SKILL.md:258-287`

建议:
- 把 Phase 1 改成真正的“双层协议”:
  - 子 agent 只写文件 + 返回事实 JSON
  - 主线程只消费 facts JSON
  - 主线程永远不补写调研产出
- 对所有 Phase 1 子任务补上统一 marker，例如:
  - `<!-- autopilot-phase:1-research -->`
  - `<!-- autopilot-phase:1-ba -->`
- 将 Phase 1 也纳入统一 post-task-validator，而不是靠“当前设计下主线程自身保证”

## 五、我建议的整改优先级

### P0: 必须先改

1. 取消默认 `after_phase_1: true`
2. 把 Phase 1 做成单一事实源，不允许主线程补写研究产物
3. 为 Phase 1 research / BA 增加统一 marker 和统一后置校验
4. fixup completeness 改为 fail-closed
5. anchor/autosquash 失败禁止归档完成

### P1: 下一阶段改

1. 用结构化 `state.json` 替代纯 markdown 恢复
2. 主窗口改成“编排真相优先”，把 debug 信息降级
3. 把 Phase 6.5 review 升级为真正可阻断 gate
4. 引入 `requirements-contract.json`
5. 引入 `agent_policy.json`，显式管理 subagent 优先级

### P2: 产品收敛

1. 减少 Phase 1 交互仪式感
2. 将文档断言测试下沉为 doc-compliance，不再代表主可靠性
3. 区分企业模式和轻量模式
4. 将 archive / autosquash / knowledge extraction 从主 happy path 解耦

## 六、最终判断

如果你问的是:

“这套系统有没有工程价值？”

有，而且不低。

“这套系统现在是不是完全符合你要的产品？”

不是，尤其不符合你要的这两条:
- 需求评审后应全自动继续
- 子 agent 不应污染主 agent 上下文

“它是否具备商业化价值？”

有潜力，但前提是先把以下三件事收敛成确定性闭环:
- Phase 1 单一事实源
- 上下文恢复结构化
- fixup/review/归档 fail-closed

在这三件事没收敛前，我对它的产品定位会是:
- 强工程实验平台
- 中等成熟度的内部工具
- 尚未收敛到可直接大规模商业化售卖的稳定产品
