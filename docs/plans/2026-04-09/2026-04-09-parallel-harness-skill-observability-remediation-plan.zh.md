# parallel-harness SKILL 可观测性与调用闭环修复方案

日期: 2026-04-09
适用范围:
- `plugins/parallel-harness`
- `plugins/spec-autopilot`

## 1. 问题定义

当前用户在实际使用 `parallel-harness` 时，看不到明确、稳定、可证明的 “SKILL 已被调用” 信号。

截图里出现的:
- `Loaded .claude/rules/frontend.md`
- `Explore agents finished`
- `Searching for ...`
- `Deliberating...`

更像 Claude Code 原生终端/转录内容中的自然语言片段，而不是插件自身定义的结构化事件。

这导致两个直接问题:

1. 无法判断某个 `SKILL.md` 只是“可用/被加载”，还是“已被当前流程真正采用”。
2. 即使实际流程使用了某个 skill，当前仓库也没有统一的运行时证据链把它可靠显示出来。

本方案的目标不是继续在 `SKILL.md` 里堆更多提示词，而是把 “skill 命中/选择/注入/执行完成” 做成可审计、可展示、可测试的一等运行时对象。

## 2. 代码级结论

### 2.1 `parallel-harness` 里存在 Skill 定义，但没有 Skill 运行时主链

证据:

- `plugins/parallel-harness/skills/harness/SKILL.md:17-23`
  - 主 skill 文本要求依次调用 `/harness-plan`、`/harness-dispatch`、`/harness-verify`
- `plugins/parallel-harness/skills/harness-plan/SKILL.md:1-6`
- `plugins/parallel-harness/skills/harness-dispatch/SKILL.md:1-6`
- `plugins/parallel-harness/skills/harness-verify/SKILL.md:1-6`
  - 子 skill 以文档形式存在

但运行时代码里:

- `plugins/parallel-harness/runtime/capabilities/capability-registry.ts:161-187`
  - `SkillRegistry` 只有 `register/get/findByPhase/findByLanguage/listAll`
  - 没有 “resolve selected skill for task/run” 之类的执行态接口
- `plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts:2598-2613`
  - `OrchestratorOptions` 只有 `hookRegistry` 和 `instructionRegistry`
  - 没有 `skillRegistry`
- `plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts:1239-1269`
  - 执行前会把 `InstructionRegistry` 注入到 contract
  - 没有任何 `SkillRegistry` 注入逻辑
- `plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts:1772-1782`
  - pre-check 的 `capability` 检查使用的是 `WorkerExecutionController` 的 capability registry
  - 不是 `SkillRegistry`
- `plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts:2401-2427`
  - `LocalWorkerAdapter` 直接 `claude -p <prompt> --output-format json`
  - 没有显式调用 `/harness-plan` 或读取 `skills/*/SKILL.md`

补充证据:

- 仓库内搜索 `plugins/parallel-harness/runtime/**`，没有任何地方消费 `SkillRegistry`
- `plugins/parallel-harness/tests/unit/context-pr-capability.test.ts:231-252`
  - 只验证 `SkillRegistry` CRUD/过滤
  - 没有验证 skill 命中进入 runtime、审计、contract、执行元数据

结论:

`parallel-harness` 当前的 skill 更接近 “静态 prompt 资产”，不是运行时原语。

### 2.2 当前不存在 “skill 已调用” 的结构化审计或事件类型

证据:

- `plugins/parallel-harness/runtime/observability/event-bus.ts:16-66`
  - `EventType` 不包含 `skill_selected`、`skill_invoked`、`skill_completed`、`skill_failed`
- `plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts:317-360`
  - audit 到 EventBus 的映射中没有 skill 类事件
- `plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts:2363-2369`
  - hook effect 只记录 `effects_count/effect_types`
  - 不记录 skill 命中

结论:

即使某个 skill 被“概念上使用”，当前平台也没有统一事件模型来证明它。

### 2.3 `spec-autopilot` 的 ingest/UI 也没有专门的 skill 事件链路

证据:

- `plugins/spec-autopilot/runtime/server/src/snapshot/snapshot-builder.ts:70-82`
  - 当前只合并四类来源:
  - `logs/events.jsonl`
  - `raw/hooks.jsonl`
  - `raw/statusline.jsonl`
  - transcript 文件
- `plugins/spec-autopilot/runtime/server/src/ingest/hook-events.ts:31-60`
  - `PostToolUse` 只归一化为 `tool_use`
- `plugins/spec-autopilot/runtime/server/src/ingest/hook-events.ts:68-95`
  - 其它 hook 只会变成 `session_start/subagent_start/tool_prepare/hook_event` 等
- `plugins/spec-autopilot/runtime/server/src/ingest/transcript-events.ts:65-88`
  - transcript 全部落成 `transcript_message`
  - 没有 skill 识别/提炼逻辑
- `plugins/spec-autopilot/runtime/server/src/types.ts:7-21`
  - `AutopilotEvent` 的 `source` 仅有 `legacy | hook | statusline | transcript`
  - 没有 skill source
- `plugins/spec-autopilot/gui/src/store/index.ts:798-800`
  - 只预聚合 `transcriptEvents` 和 `toolEvents`
- `plugins/spec-autopilot/gui/src/components/ToolTracePanel.tsx:15-99`
  - 只展示 `tool_use`
- `plugins/spec-autopilot/gui/src/components/TranscriptPanel.tsx:13-73`
  - 只展示 `transcript_message`
- `plugins/spec-autopilot/gui/src/components/VirtualTerminal.tsx:15-48`
  - 没有任何 `skill_*` 颜色映射
- `plugins/spec-autopilot/gui/src/components/VirtualTerminal.tsx:103-210`
  - 事件格式化分支里没有 `skill_*`

结论:

即使未来 runtime 发出了 skill 生命周期信号，当前 GUI 也看不见。

### 2.4 截图里的文本不是仓库代码模板生成的

证据:

- 全仓搜索:
  - `Loaded .*rules`
  - `Loaded .*SKILL`
  - `Explore agents finished`
  - `Deliberating`
- 均未命中插件源码模板

结论:

截图里的这些词来自 Claude Code 原生输出或 transcript 原文，不是本仓库自己生成的结构化显示。

因此，不能把 “截图没出现 skill 字样” 简化理解为前端漏渲染一条本来就存在的事件。

## 3. 根本原因

### 根因 A: 架构层把 SKILL 设计成文档，不是运行时实体

`parallel-harness` 当前把 skill 当作:
- slash command 入口文档
- prompt 规范
- 产品说明

但没有把它建模成:
- 选择结果
- 输入 contract 的一部分
- 审计对象
- 生命周期事件

### 根因 B: 依赖 Claude 内部隐式行为，缺少外显证据

主 skill 文本写了 “调用 `/harness-plan` / `/harness-dispatch` / `/harness-verify`”，
但仓库本身并没有确定性机制证明:
- 是否真的进入了这些子 skill
- 进入的是哪个版本
- 在哪个 task/phase 上生效
- 何时结束

### 根因 C: 可观测性模型只有 tool/agent/transcript，没有 skill 维度

当前观测栈的基本单位是:
- hook
- tool
- subagent
- transcript

没有 `skill` 这个第一等维度，所以 UI 根本无从准确展示。

### 根因 D: 产品语义与用户预期不一致

用户期望看到的是:
- “这次运行明确使用了哪个 skill”
- “何时切换到哪个子 skill”
- “这个 skill 是否真正生效”

而当前系统最多只能间接看到:
- 某些 transcript 文本
- 某次工具调用
- 某个 agent 启停

两者不是一回事。

## 4. 修复原则

1. 不再把 “skill 被调用” 仅仅当作自然语言叙事。
2. 不依赖 Claude transcript 的脆弱文案格式作为唯一证据。
3. skill 事件必须能进入:
   - runtime 决策
   - 审计日志
   - 执行元数据
   - GUI 展示
   - 自动化测试
4. 必须区分以下四种语义，避免误报:
   - `available`: 仓库里存在该 skill
   - `selected`: runtime 判断本次应使用该 skill
   - `injected`: skill 协议/约束已注入 contract/prompt
   - `observed`: transcript 中观察到疑似加载痕迹
5. 只有 `selected/injected/completed` 才能作为 “真实生效” 证据。
6. `observed` 只能作为辅助证据，不能替代真实闭环。

## 5. 推荐修复方向

推荐采用 “双层闭环”:

### 第一层: 运行时确定性 skill 生命周期

由 `parallel-harness` runtime 明确决定并记录:
- 候选 skill
- 被选中 skill
- skill 注入到 contract/prompt
- skill 运行完成/失败

这一层不依赖 Claude 内部是否打印 “Loaded xxx”。

### 第二层: transcript 补充观测

由 `spec-autopilot` server 从 transcript 中额外识别:
- `Loaded .../SKILL.md`
- `Loaded .../rules/*.md`
- 其它可稳定识别的 skill/规则加载痕迹

这一层只做 “observed evidence”，用于增强可读性和排障，不作为唯一真实依据。

## 6. 详细技术方案

### Workstream 1: 把 skill 建模成 runtime 一等对象

目标:
- 让 `parallel-harness` 不再只有 `SkillRegistry`，而有 `SkillResolution` / `SkillInvocation`

建议新增结构:

1. `SkillMatch`
   - `skill_id`
   - `match_reason`
   - `phase_match`
   - `language_match`
   - `path_match`
   - `confidence`

2. `SelectedSkill`
   - `skill_id`
   - `selection_reason`
   - `source` (`explicit` | `phase_default` | `language_default` | `fallback`)
   - `version`

3. `SkillInvocationRecord`
   - `run_id`
   - `task_id`
   - `attempt_id`
   - `phase`
   - `selected_skill_id`
   - `injected_at`
   - `completed_at`
   - `status`
   - `evidence`

建议修改文件:
- `plugins/parallel-harness/runtime/capabilities/capability-registry.ts`
- `plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts`
- `plugins/parallel-harness/runtime/session/context-pack.ts`
- `plugins/parallel-harness/runtime/schemas/ga-schemas.ts`

关键动作:

1. 在 `OrchestratorOptions` 中新增 `skillRegistry?: SkillRegistry`
2. 在 task 执行前增加 `resolveSkillsForTask(task, ctx)`:
   - phase 维度
   - 语言维度
   - 路径维度
   - 可选 repo/org 维度
3. 将 `selected_skill_ids` 和 `selection_reason` 写入 `TaskContract`
4. 将 `selected_skill_ids` 写入 `TaskAttempt` / `RunExecution` 元数据
5. 在 worker prompt/contract 中显式注入 skill 协议摘要，而不是只靠外部 slash 命令隐式切换

注意:

这里的“注入”应优先注入经过裁剪的协议摘要，而不是直接拼完整 `SKILL.md`，避免 prompt 膨胀。

### Workstream 2: 新增 skill 生命周期事件与审计

目标:
- skill 生效链必须进入 EventBus 与 AuditTrail

建议新增 EventBus 事件:
- `skill_candidates_resolved`
- `skill_selected`
- `skill_injected`
- `skill_completed`
- `skill_failed`
- `skill_observed` 仅供 transcript 识别结果使用

建议修改文件:
- `plugins/parallel-harness/runtime/observability/event-bus.ts`
- `plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts`
- `plugins/parallel-harness/runtime/persistence/session-persistence.ts`

建议审计 payload 字段:
- `task_id`
- `attempt_id`
- `phase`
- `candidate_skill_ids`
- `selected_skill_id`
- `selection_reason`
- `protocol_digest`
- `evidence_source`

要求:

1. `skill_selected` 必须发生在 worker 执行前
2. `skill_injected` 必须在 contract/prompt 完成后发射
3. `skill_completed` / `skill_failed` 必须跟 task attempt 绑定
4. UI 上任何 “已调用 skill” 文案都只能基于这些事件，不允许从散落文本硬猜

### Workstream 3: 不再把子 skill 调用停留在纯文档宣称

这是最关键的“彻底修复”点。

当前问题不是 skill 文件格式不规范，而是:
- `harness/SKILL.md` 说要调 `/harness-plan`
- 但 runtime 没有显式执行链证明

建议采用以下策略之一:

#### 方案 A: 推荐方案，runtime 驱动，skill 文件变成协议源

做法:

1. 保留 `/harness` 作为用户入口，不改变入口体验
2. `harness-plan` / `harness-dispatch` / `harness-verify` 不再依赖“模型自己切 slash command”
3. runtime 直接根据阶段选择对应 skill 协议摘要，注入当前 task 的 contract/prompt
4. skill 文件成为协议模板和人类可维护文档，不再承担唯一执行控制职责

优点:
- 可测试
- 可审计
- 不依赖 Claude 内部 slash 行为
- 能稳定显示 skill 生效链

缺点:
- 需要重构当前 “子 skill 由主 skill 文本调用” 的叙事

#### 方案 B: 兼容方案，保留 slash 叙事，但增加显式确认协议

做法:

1. 继续让主 skill 文本要求进入子 skill
2. 但进入子 skill 后，第一条结构化输出必须包含:
   - `active_skill`
   - `phase`
   - `task_scope`
   - `protocol_version`
3. runtime/ingest 只在看见该结构化确认后，才记为 `skill_completed`

优点:
- 对现有文档改动较小

缺点:
- 仍然依赖模型遵守协议
- 不够确定性

建议:

优先做方案 A，方案 B 仅作过渡。

### Workstream 4: `spec-autopilot` ingest 增加 skill 识别层

目标:
- 把 runtime skill 事件和 transcript 观察证据都接进来

建议修改文件:
- `plugins/spec-autopilot/runtime/server/src/types.ts`
- `plugins/spec-autopilot/runtime/server/src/ingest/legacy-events.ts`
- `plugins/spec-autopilot/runtime/server/src/ingest/transcript-events.ts`
- `plugins/spec-autopilot/runtime/server/src/snapshot/snapshot-builder.ts`

实现建议:

1. 扩展允许的 event type，支持 `skill_*`
2. 在 `legacy-events.ts` 支持读取 `parallel-harness` 写出的 `skill_*` 事件
3. 在 `transcript-events.ts` 新增轻量识别器:
   - 若文本匹配 `Loaded .../SKILL.md` → 生成 `skill_observed`
   - 若文本匹配 `Loaded .../rules/*.md` → 生成 `instruction_observed` 或 `skill_observed` 的子类 payload
4. `skill_observed` payload 需标注:
   - `observed_path`
   - `observed_kind`
   - `confidence`
   - `derived_from: transcript`

注意:

`skill_observed` 不得自动升级为 `skill_selected`。

### Workstream 5: GUI 增加 skill 维度展示

目标:
- 让用户在 UI 中一眼看出:
  - 哪些 skill 被选中了
  - 哪些只是 transcript 里观察到的痕迹
  - skill 与 agent/tool/task 的关系

建议修改文件:
- `plugins/spec-autopilot/gui/src/store/index.ts`
- `plugins/spec-autopilot/gui/src/components/VirtualTerminal.tsx`
- `plugins/spec-autopilot/gui/src/components/ParallelKanban.tsx`
- `plugins/spec-autopilot/gui/src/components/TranscriptPanel.tsx`
- `plugins/spec-autopilot/gui/src/components/ToolTracePanel.tsx`
- 可新增 `SkillTracePanel.tsx`

UI 设计建议:

1. VirtualTerminal:
   - 新增 `skill_selected`
   - 新增 `skill_injected`
   - 新增 `skill_completed`
   - 新增 `skill_failed`
   - 新增 `skill_observed`

2. ParallelKanban:
   - Agent 卡片显示当前 `active_skill`
   - 展开卡片时显示:
     - 选择理由
     - protocol digest
     - 相关工具调用

3. TranscriptPanel:
   - 对包含 `Loaded .../SKILL.md` 的 transcript_message 加高亮 badge
   - 但 badge 文案写成 `Observed`
   - 不写成 `Invoked`

4. 新增 Skill 面板:
   - 按时间线列出 skill 生命周期
   - 支持按 task/agent/phase 过滤

### Workstream 6: 测试体系补齐

这是本次修复不能省的一层。

当前仓库最大风险不是“做不出来”，而是再次落回 “文档写了，但运行时没闭环”。

必须新增以下测试:

#### `parallel-harness` 单测

1. `SkillRegistry` 命中规则测试
   - phase/language/path 三维匹配
2. `Orchestrator` 选择 skill 后写入 contract
3. `TaskAttempt` / `RunExecution` 元数据包含 selected skill
4. EventBus 发出 `skill_selected/skill_injected/skill_completed`
5. AuditTrail 可查询 skill 生命周期

建议文件:
- `plugins/parallel-harness/tests/unit/context-pr-capability.test.ts`
- `plugins/parallel-harness/tests/unit/orchestrator.test.ts`
- `plugins/parallel-harness/tests/unit/mainline-integration.test.ts`

#### `spec-autopilot` server 单测

1. transcript 中 `Loaded .../SKILL.md` 能归一化为 `skill_observed`
2. runtime 产生的 `skill_*` 事件能被 snapshot builder 合并
3. `skill_observed` 不会错误更新为 `skill_selected`

建议文件:
- 新增 `plugins/spec-autopilot/tests/test_skill_observability.sh`
- 或 server 侧 TS 单测

#### GUI 单测或快照测试

1. store 能聚合 `skill_*`
2. VirtualTerminal 能格式化 skill 事件
3. Agent 卡片能显示 active skill

#### 黑盒回归测试

构造一条完整 fixture:
- 主会话触发 `/harness`
- 任务进入 planning
- runtime 选择 `harness-plan`
- 写出 `skill_selected`
- transcript 中同时出现 `Loaded .../skills/harness-plan/SKILL.md`

验证:
- UI 同时显示:
  - `skill_selected` 结构化事件
  - `skill_observed` transcript 辅助痕迹
- 两者语义不混淆

## 7. 交付顺序

建议 Claude 按以下顺序实施，而不是先动 UI:

1. `parallel-harness` schema/event/audit 建模
2. `parallel-harness` runtime skill 选择与 contract 注入
3. `parallel-harness` 单测补齐
4. `spec-autopilot` server ingest 接 skill 事件
5. `spec-autopilot` transcript 辅助识别
6. GUI store 聚合与终端显示
7. 黑盒回归测试
8. README / docs / dist 同步

原因:

如果先改 UI，只会把 “看不见” 变成 “看起来像看得见”，但底层仍不可证明。

## 8. 验收标准

Claude 修复完成后，至少满足以下验收条件:

1. 对任意一次 task attempt，都能回答:
   - 候选 skill 有哪些
   - 选中了哪个
   - 为什么选它
   - 是否已注入执行上下文
   - 最终是否完成

2. UI 中明确区分:
   - `selected/injected/completed`
   - `observed`

3. 不依赖 Claude 原生终端是否打印 `Loaded ...`
   - 即使 transcript 没这行，也能通过 runtime 事件看到真实 skill 生效链

4. transcript 中若出现 `Loaded .../SKILL.md`
   - 能被当作辅助证据展示
   - 但不会被误当作唯一真实依据

5. 自动化测试覆盖:
   - runtime
   - ingest
   - UI/store
   - 黑盒 fixture

## 9. 明确不推荐的错误修法

以下做法都不够彻底:

1. 只在 `SKILL.md` 里加一句 “请先告诉用户我调用了某个 skill”
2. 只在 transcript 面板里对 `Loaded ...SKILL.md` 做字符串高亮
3. 只给 GUI 新增一个 `Skill` 标签页，但不补 runtime 事件
4. 继续把 `SkillRegistry` 留在 registry 层，不进入 orchestrator 主链
5. 用自然语言 “应该已经调用了” 替代结构化证据

## 10. 对 Claude 的执行提示

如果把这份方案交给 Claude，建议明确要求它:

1. 不要只修前端显示
2. 必须先补 runtime skill lifecycle schema
3. 必须补测试，尤其是黑盒回归测试
4. 必须在最终说明中给出:
   - 新增的 skill 事件类型
   - skill 生命周期在哪些文件落盘/展示
   - 如何证明不是只改了文档

## 11. 最终判断

本次问题的根本原因不是:
- `SKILL.md` frontmatter 不规范
- GUI 少画了一条日志
- Claude 偶尔没打印某句话

真正根因是:

`parallel-harness` 当前没有把 skill 设计为可执行、可审计、可展示的运行时实体，`spec-autopilot` 也没有对应的 ingest/UI 维度，因此“skill 是否真正被调用”在架构上就无法被稳定证明。

如果要彻底修复，必须把 skill 从 “文档层提示词” 升级成 “运行时一等对象 + 审计事件 + UI 维度”。
