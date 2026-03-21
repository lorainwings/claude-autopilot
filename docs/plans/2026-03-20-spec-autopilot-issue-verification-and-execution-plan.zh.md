# spec-autopilot 问题核实与执行方案

> 日期: 2026-03-20
> 适用范围: `plugins/spec-autopilot`
> 用途: 这是一份可直接交给 Claude 执行的实施方案，不是泛泛建议。先核实，再改造，再回归验证。

## 0. 结论总览

本次针对你反馈的 6 个问题做了源码核查、现有测试核查、局部回归测试和官方资料补充调研，结论如下：

| 问题 | 核实结论 | 判断 |
|---|---|---|
| 1. 中间过程看不出模型是否切换 | 仓库已接入 `model_routing / model_effective / model_fallback` 事件、GUI 右侧有“模型路由”卡片，但不在中心主视区，不会形成强提示，也没有“切换成功/降级失败”的瞬时告警 | **部分实现，但未达到可感知 UX** |
| 2. 循环实施时本地 GUI 仪表盘服务会挂掉 | 串行重跑 `test_gui_server_health.sh` 与 `test_server_robustness.sh` 均通过，**本轮未复现服务直接挂死**；但代码中仍存在高频事件下前端排序/渲染压力、WS 解析异常静默吞掉、固定端口与跨会话误连等风险点 | **未直接复现，但存在真实脆弱点，需要先做复现基线再修** |
| 3. GUI 日志过于粗略，不够详细 | 已确认。默认事件流只显示摘要；`emit-tool-event.sh` 只写 `key_param`/`output_preview` 摘要；详细输入输出只在 ToolTrace 页签中部分可见；PreToolUse/决策链/调度链缺少完整结构化明细 | **确认存在缺口** |
| 4. 需求分析和决策流程速度慢 | 已确认。当前 Phase 1 仍偏重“调研驱动 + 多轮 AskUserQuestion + 大文档注入”，对“模糊但未达到强制澄清阈值”的需求仍有发散风险，且现有路由会让模型偏保守、偏慢 | **确认存在效能问题** |
| 5. 崩溃恢复未清理 fixup，扫描后仍弹 AskUserQuestion | 这是**当前设计使然**，不是偶发 bug。恢复阶段只扫描并提示 fixup，不自动 squash；auto-continue 仅在单候选、低 git 风险等条件满足时才跳过 AskUserQuestion | **主要是设计问题，需要策略改造** |
| 6. 循环实施中经常无法并行，效率低 | 日志现象与当前实现一致。`generate-parallel-plan.sh` 在“显式依赖 + 共享文件隐式依赖”下会回退串行；这不是实现失效，而是当前调度策略过于保守，且把“吞吐提升”过度押注在多 Agent 并行上 | **确认是架构/策略问题，不只是开关问题** |

---

## 1. 核实依据

### 1.1 本地源码核查点

- 模型路由与展示：
  - `plugins/spec-autopilot/runtime/scripts/emit-model-routing-event.sh`
  - `plugins/spec-autopilot/gui/src/store/index.ts`
  - `plugins/spec-autopilot/gui/src/components/TelemetryDashboard.tsx`
- GUI 服务与聚合链路：
  - `plugins/spec-autopilot/runtime/scripts/start-gui-server.sh`
  - `plugins/spec-autopilot/runtime/server/src/bootstrap.ts`
  - `plugins/spec-autopilot/runtime/server/src/api/routes.ts`
  - `plugins/spec-autopilot/runtime/server/src/session/file-cache.ts`
  - `plugins/spec-autopilot/gui/src/lib/ws-bridge.ts`
- 日志工作台：
  - `plugins/spec-autopilot/gui/src/components/LogWorkbench.tsx`
  - `plugins/spec-autopilot/gui/src/components/VirtualTerminal.tsx`
  - `plugins/spec-autopilot/gui/src/components/ToolTracePanel.tsx`
  - `plugins/spec-autopilot/runtime/scripts/emit-tool-event.sh`
  - `plugins/spec-autopilot/runtime/scripts/capture-hook-event.sh`
- Phase 1 需求理解：
  - `plugins/spec-autopilot/skills/autopilot/references/phase1-requirements.md`
  - `plugins/spec-autopilot/skills/autopilot/references/phase1-requirements-detail.md`
- 恢复与 fixup：
  - `plugins/spec-autopilot/runtime/scripts/recovery-decision.sh`
  - `plugins/spec-autopilot/runtime/scripts/clean-phase-artifacts.sh`
  - `plugins/spec-autopilot/skills/autopilot-recovery/SKILL.md`
  - `plugins/spec-autopilot/skills/autopilot-phase7/SKILL.md`
- Phase 5 并行/串行调度：
  - `plugins/spec-autopilot/runtime/scripts/generate-parallel-plan.sh`
  - `plugins/spec-autopilot/skills/autopilot/references/parallel-dispatch.md`
  - `plugins/spec-autopilot/skills/autopilot/references/phase5-implementation.md`

### 1.2 本地回归测试结果

已通过：

- `bash plugins/spec-autopilot/tests/test_model_routing_observability.sh`
- `bash plugins/spec-autopilot/tests/test_gui_server_health.sh`
- `bash plugins/spec-autopilot/tests/test_server_robustness.sh`
- `bash plugins/spec-autopilot/tests/test_recovery_auto_continue.sh`
- `bash plugins/spec-autopilot/tests/test_parallel_plan_generation.sh`
- `bash plugins/spec-autopilot/tests/test_phase1_clarification.sh`

注意：

- 一次并行跑多个固定端口测试时，`test_server_robustness.sh` 曾误失败；清空 `9527/8765` 端口后串行重跑通过。说明 GUI 链路测试必须串行执行，不能把“测试间端口冲突”误判成产品缺陷。

### 1.3 补充调研依据（Anthropic 官方）

以下结论只引用官方资料，用于指导“如何改”：

- Claude 提示工程最佳实践：
  - https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices
- Claude Code Subagents：
  - https://code.claude.com/docs/en/sub-agents
- Claude Code Hooks：
  - https://code.claude.com/docs/en/hooks
- Claude Code Status Line：
  - https://code.claude.com/docs/en/statusline
- Anthropic: Building effective agents：
  - https://www.anthropic.com/engineering/building-effective-agents
- Anthropic: Demystifying evals for AI agents：
  - https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents

---

## 2. 逐项核实

## 2.1 问题 1：模型切换不可感知

### 现状

仓库已经有模型路由可观测性链路：

- 路由事件发射：`emit-model-routing-event.sh`
- GUI store 聚合：`store/index.ts`
- 右侧卡片展示：`TelemetryDashboard.tsx`
- 测试覆盖：`test_model_routing_observability.sh`

但当前 UX 有三个明显问题：

1. 展示位置不对  
   模型信息只在右侧遥测卡片，用户在中部执行主视区很难第一时间看到。

2. 缺少“状态跃迁提示”  
   没有从“请求模型”到“实际模型”再到“fallback”的醒目提示，也没有 toast/banner。

3. 缺少执行阶段绑定  
   用户不知道“哪一个 Agent / 哪一个 Phase / 哪一次重试”发生了切换。

### 结论

这不是“完全没有实现”，而是“实现了数据链路，但没实现用户可感知的过程提示”。

### 必须改造

- 在主视区加入模型切换状态条，而不是只放在右侧卡片
- 新增瞬时事件提示：
  - `requested -> effective`
  - `effective mismatch`
  - `fallback applied`
- 每条提示必须带：
  - `phase`
  - `agent_id`
  - `requested_model`
  - `effective_model`
  - `fallback_reason`

---

## 2.2 问题 2：循环实施时 GUI 仪表盘服务会挂掉

### 现状

本轮没有直接复现“服务挂掉无法访问”：

- `test_gui_server_health.sh` 通过
- `test_server_robustness.sh` 串行重跑通过

说明“基础启动、会话切换、raw-tail、损坏 JSON 容错、journal 构建”这条主链路当前可用。

### 但仍存在真实风险点

1. 前端高频排序与重渲染压力  
   `store/index.ts` 的 `addEvents()` 每次都做全量拼接 + 排序 + 分池 + 截断。仓库自己的历史评估文档也指出高频事件下会掉帧。

2. WS 异常静默吞掉  
   `ws-bridge.ts` 中 `onmessage` 的 JSON 解析异常被 `catch {}` 直接吞掉，前端只会“没反应”，缺乏显式诊断。

3. 固定端口 + 跨项目误连风险  
   尽管 `start-gui-server.sh` 已用 `/api/info.projectRoot` 做归属检查，但所有项目仍共用 `9527/8765`。如果旧进程、外部调试、测试脚本混入，故障定位会非常差。

4. StatusLine 更新是 300ms debounce 且新更新会取消旧执行  
   这意味着采集脚本必须非常快，否则状态更新会被反复中断。

### 结论

“服务会挂掉”当前缺乏稳定复现证据；但“服务与 GUI 在高频事件/异常输入下不够可诊断、不够可压测”是确认存在的。

### 必须改造

- 先补复现 harness，再动代码
- 把“挂掉”拆成 4 类并分别量化：
  - HTTP 进程退出
  - HTTP 存活但 `/api/events` 空白
  - WS 断流
  - 前端渲染卡死/假死

---

## 2.3 问题 3：GUI 日志过于粗略

### 现状

当前 GUI 日志体系分为 4 个 tab：

- 事件流
- 正文
- 工具
- 原始

但是默认体验仍偏粗略，原因有三层：

1. 默认事件流是摘要流  
   `VirtualTerminal.tsx` 对很多事件只显示预览，且大量截断：
   - transcript 预览截断
   - routing_reason 截断
   - tool key_param/output_preview 截断

2. `emit-tool-event.sh` 本身只发轻量摘要  
   只落盘：
   - `tool_name`
   - `key_param`
   - `exit_code`
   - `output_preview`
   没有完整输入输出，没有 tool latency，没有 token/turn 级关联信息。

3. 缺少“过程链日志”  
   当前更像“事件点”，而不是“执行链”：
   - 为什么降级到串行
   - 哪些任务 ready / blocked
   - AskUserQuestion 是谁触发的
   - 恢复扫描到底依据了哪些 checkpoint / git 状态
   - fixup 检测结果与决策链
   这些都没有在 GUI 默认路径下完整展开。

### 结论

该问题已确认，不是用户错觉。

### 必须改造

- 把日志分成三层：
  - `summary`: 默认摘要
  - `trace`: 完整结构化事件
  - `raw`: 原始 hooks/statusline/transcript
- 每个关键阶段补“因果链”事件，不只写结果
- 新增一类“调度决策日志”：
  - 为什么串行
  - 为什么 fallback
  - 哪个依赖阻断
  - 哪个文件所有权冲突

---

## 2.4 问题 4：需求分析和决策流程慢

### 现状

代码和文档都显示当前 Phase 1 偏重：

- 规则检测
- 定向澄清/预循环
- Auto-Scan
- Research Agent
- Web Research
- BA 分析
- 多轮决策循环

这条链路在“需求清晰、项目上下文稳定”的场景下仍然偏重。

### 已确认的根因

1. 仍然有“灰区需求”  
   虽然已经加入 `flags >= 2` 的定向澄清预检，但对很多“模糊但常见”的需求，仍会很快进入调研链，而不是先把需求压缩成结构化输入。

2. 调研优先于澄清  
   当前设计仍偏向“先调研更多，再帮助用户做决定”，这会在模糊需求上浪费时间。

3. 过多把准确性押在大上下文注入上  
   不是先做“成功标准压缩”，而是先喂更多文档。

4. `min_qa_rounds` 和复杂度分路容易放大交互成本  
   对已足够清晰的需求也可能继续追问。

### 官方最佳实践对本问题的启示

Anthropic 官方给出的方向非常明确：

- 先把成功标准定义清楚，再做 prompt engineering
- 指令要清晰、直接、分步骤
- 用 3-5 个高质量示例稳定输出结构
- 用 XML 标签明确区分 `instructions/context/input/examples`
- 不要过度鼓励模型“过度彻底”，否则会放大延迟和 token
- 对 agent 系统要从简单工作流开始，只在证明有收益时增加复杂度

### 结论

这个问题不是模型不够强，而是当前 Phase 1 策略偏“重调研、重回合、重上下文”，需要改为“先压缩需求、再针对性调研、再最少轮澄清”。

---

## 2.5 问题 5：崩溃恢复不清理 fixup，扫描后还弹 AskUserQuestion

### 现状

恢复技能和脚本明确规定：

- `recovery-decision.sh` 会扫描 `has_fixup_commits`
- fixup 只作为状态提示，不在恢复阶段自动 squash
- 真正的 autosquash 在 Phase 7 归档时执行
- 若不满足 `auto_continue_eligible` 条件，就必须 AskUserQuestion

### 结论

这条流程**主要是当前设计如此**，不是偶发 bug。

但设计上有两个明显不合理点：

1. “恢复可继续”与“归档是否 squash”耦合太弱  
   用户感知上会觉得 fixup 是恢复残留垃圾，但系统却选择“现在不处理，以后再说”。

2. 扫描完成后是否弹 AskUserQuestion 的条件不透明  
   用户看到的是“明明扫描完了，怎么还来问我”，但系统没有把阻断原因显式展示出来。

### 必须改造

- 恢复阶段不要自动 squash，但必须显式展示：
  - 为什么不能 auto-continue
  - 当前 git 风险等级
  - fixup 数量
  - 需要用户确认的具体原因
- 把“扫描结果 -> 决策原因 -> 用户动作”结构化写入 GUI 和日志
- 增加可选策略：
  - `recovery.fixup_policy: keep | warn | soft-clean`
  - 默认 `warn`

---

## 2.6 问题 6：循环实施无法并行，效率低

### 现状

当前实现并不是“只要 `parallel.enabled=true` 就并行”，而是：

- 先生成依赖图
- 显式 `depends_on`
- 共享文件冲突产生隐式依赖
- 如果批次全是单任务，则 `fallback_to_serial=true`

这与你给出的日志一致：

> 29 个任务，按依赖关系分组，采用串行模式（config parallel.enabled: true 但任务间有强依赖）

### 关键判断

这不是简单的 bug，而是三层问题叠加：

1. 任务切分过于“共享文件导向”  
   任务描述如果反复引用同一批核心文件，会把依赖图自动拉成线性链。

2. 调度器只会“并行写代码”，不会“并行准备上下文”  
   一旦不能并行写文件，整个吞吐就掉回串行。

3. 过度依赖多 Agent 并行来提速  
   但 Anthropic 官方建议是：
   - 先用最简单、可组合的 workflow
   - 独立工具调用可并行
   - 依赖调用必须串行，不能猜参数
   - Subagent 的核心价值之一是上下文隔离，不是盲目堆并发数

### 结论

正确目标不是“最大并行”，而是“最大稳定吞吐”。

应该把效率优化拆成三类：

- `并行准备`
- `串行写入`
- `异步验证`

而不是把所有提速都押在“多个 Agent 同时改代码”。

---

## 3. 改造原则

这是后续 Claude 执行时必须遵守的原则：

1. 先做可复现基线，再改代码  
   没有复现 harness 的“稳定性修复”一律不允许直接动主链路。

2. 优先提高可诊断性，再提高复杂度  
   先让问题可见，再做优化。

3. 目标是吞吐与稳定性，不是表面并行度  
   对强依赖任务，先优化任务切分、上下文压缩、异步验证，而不是继续堆 Agent。

4. 恢复阶段以“透明决策”优先  
   fixup 与 AskUserQuestion 是否出现，必须让用户看懂原因。

5. 改造必须带回归测试与压测  
   尤其是 GUI/server/Phase1/recovery/parallel planner。

---

## 4. 交给 Claude 的执行方案

以下内容是给 Claude 的明确执行任务。

## 4.1 总目标

在不破坏现有 `/autopilot` 使用习惯的前提下，完成以下 6 个方向的系统改造：

1. 模型切换可感知
2. GUI 服务更稳定、更可诊断
3. GUI 日志从“摘要流”升级为“可追溯过程流”
4. Phase 1 更快、更准地澄清需求
5. 恢复流程对 fixup 与 AskUserQuestion 更透明、更合理
6. Phase 5 从“追求并行”改为“追求稳定高吞吐”

---

## 4.2 工作包拆分

### 工作包 A：建立复现与基线

目标：

- 把“主观卡顿/挂掉/日志粗略/恢复反复提问/并行失效”全部变成可重复的场景

必须完成：

1. 新增 GUI 稳定性压测脚本
   - 模拟 `50 / 100 / 200 events/sec`
   - 模拟长 session
   - 模拟 WS malformed message
   - 模拟 raw-tail 超大单行
   - 模拟 statusLine 高频取消

2. 新增恢复流程场景夹具
   - 单候选 + fixup
   - 多候选 + fixup
   - high git risk
   - gap phases
   - anchor_sha 失效

3. 新增并行计划场景夹具
   - 强依赖链
   - 共享文件冲突
   - 可并行准备 / 不可并行写入
   - 跨域但共享契约文件

交付物：

- `plugins/spec-autopilot/tests/` 下新增测试与夹具
- 一份基线报告，记录：
  - GUI 响应
  - 事件吞吐
  - raw-tail 正确性
  - 恢复分支命中率
  - planner 串行回退率

验收标准：

- 所有新增测试可本地无人工运行
- 能稳定复现至少 1 个“高频退化”场景
- 能稳定复现至少 3 类恢复分支

---

### 工作包 B：模型切换可感知改造

目标：

- 用户在中间过程能明确看到“请求模型 / 实际模型 / 是否降级 / 降级原因”

必须完成：

1. 在主视区加入 `ModelSwitchBanner`
   - 监听：
     - `model_routing`
     - `model_effective`
     - `model_fallback`
   - 展示：
     - 请求模型
     - 实际模型
     - phase
     - agent
     - 是否 mismatch
     - fallback reason

2. 右侧卡片保留，但改成历史面板

3. 增加显式颜色与状态文案：
   - 请求中
   - 已确认
   - 不支持覆盖
   - 已降级

4. 写测试
   - store 状态跃迁测试
   - GUI 渲染测试
   - fallback 场景测试

验收标准：

- 在一次路由事件后 1 秒内，主视区有明显提示
- mismatch 与 fallback 可被非开发者直接看懂
- 历史记录可追溯最近 10 次切换

---

### 工作包 C：GUI 日志与服务可观测性增强

目标：

- 把 GUI 从“摘要看板”升级为“可审计执行台”

必须完成：

1. 日志分层
   - `summary`
   - `trace`
   - `raw`

2. 新增结构化事件类型
   - `decision_trace`
   - `recovery_scan`
   - `recovery_reason`
   - `scheduler_trace`
   - `model_switch_trace`
   - `ask_user_trace`

3. 扩展 `tool_use` 事件
   - 增加 latency
   - 增加完整输入/输出是否可展开
   - 增加 tool correlation id
   - 保留摘要，但支持进入 trace 查看完整结构

4. `ws-bridge.ts` 不允许静默吞异常
   - 至少写 console error
   - 更好的是发一条本地诊断事件到 store

5. 新增 `/api/health/detail` 或等效信息
   - 当前 projectRoot
   - sessionId
   - event count
   - last refresh time
   - ws client count
   - last error

6. 对 `store/index.ts` 做性能优化
   - 减少全量排序次数
   - 避免每次全量 filter/sort/slice
   - 保证关键事件永久保留

验收标准：

- 默认日志页可看摘要
- trace 页能定位“为什么串行”“为什么 AskUserQuestion”“为什么 fallback”
- 高频事件下 GUI 不出现明显卡死
- 服务端和前端异常都能看到诊断信息

---

### 工作包 D：Phase 1 提速与准度改造

目标：

- 把 Phase 1 从“重调研工作流”改成“先压缩成功标准，再做最小必要调研”

必须完成：

1. 在 Phase 1 最前面新增 `Requirement Compression` 步骤
   输出统一 JSON：
   - goal
   - in_scope
   - out_of_scope
   - target_entity
   - acceptance_criteria
   - constraints
   - unknowns

2. 如果压缩后 `unknowns <= 2` 且验收标准明确：
   - 跳过重调研
   - 只做轻量 auto-scan + 精准 research

3. 重新定义 Phase 1 路由
   - `clarify_first`
   - `scan_first`
   - `research_first`
   而不是默认三路全开

4. 引入 prompt 结构升级
   - 明确步骤
   - XML tags
   - 3-5 个 few-shot 示例
   - 只对真正需要的场景启用更高 effort

5. 限制过度思考
   - 对清晰需求默认降 effort
   - 去掉泛化的“尽量全面调研”类提示

6. 建立 eval 套件
   - 清晰需求
   - 模糊需求
   - 非功能需求
   - 迁移/重构/bugfix/chore

验收标准：

- 清晰需求的 Phase 1 总时长显著下降
- 模糊需求的首轮提问更少但更准
- 最终 checkpoint 的结构化质量不下降

---

### 工作包 E：恢复流程与 fixup 生命周期改造

目标：

- 让恢复流程“可理解、可预测、可配置”

必须完成：

1. 明确区分三种 fixup 状态
   - `none`
   - `present_but_safe`
   - `present_and_risky`

2. `recovery-decision.sh` 输出新增字段
   - `auto_continue_blockers[]`
   - `user_interaction_reason`
   - `fixup_policy`
   - `fixup_scope`

3. GUI / 日志显示恢复决策原因
   - 为什么自动继续失败
   - 为什么要 AskUserQuestion
   - 当前 git 风险等级

4. 新增可选清理策略
   - `keep`
   - `warn`
   - `soft-clean`

5. `clean-phase-artifacts.sh` 与恢复文档保持一致
   - 不自动 squash，但在 `soft-clean` 下可做轻量 fixup 清理准备

验收标准：

- 用户能一眼看懂恢复为什么停下来
- “扫描完又弹 AskUserQuestion”不再是黑盒行为
- fixup 的处理语义在恢复和归档两个阶段一致

---

### 工作包 F：Phase 5 效率优化，不以“更多并行”为目标

目标：

- 把效率提升从“多 Agent 写代码”转成“稳定吞吐”

必须完成：

1. 调度器改为三段式
   - `parallel_prepare`
   - `serialized_write`
   - `async_validate`

2. `generate-parallel-plan.sh` 输出不只判断“能否并行”，还要输出：
   - 哪些任务可并行准备上下文
   - 哪些任务只能串行写入
   - 哪些验证可异步执行

3. 对共享文件冲突不再直接等同“完全串行”
   - 允许：
     - 并行读取
     - 并行生成 patch 草案
     - 主线程顺序应用
   - 只对最终写入序列化

4. 引入“高收益快路径”
   - 小改动单文件任务优先
   - 合同/接口文件先锁定
   - 跨域共享文件先收敛

5. 让 planner 显式输出串行原因
   - 文件所有权冲突
   - 显式依赖
   - 跨域共享契约
   - 风险降级

6. 把可异步的重任务移出主路径
   - 非阻断测试
   - 质量扫描
   - 部分 review
   - 非关键日志采集

验收标准：

- 强依赖任务下，总耗时仍能下降
- “串行”不再等于“所有事情都串行”
- GUI 能清晰显示：
  - ready
  - prepared
  - writing
  - validating
  - blocked

---

## 4.3 Claude 执行顺序

要求 Claude 严格按以下顺序推进，不允许一上来大改：

1. 先完成工作包 A，建立复现基线
2. 再做工作包 C，因为没有 trace 能力就很难做后续诊断
3. 再做工作包 B，让模型切换对用户可见
4. 再做工作包 E，让恢复流程透明
5. 再做工作包 D，优化 Phase 1
6. 最后做工作包 F，重构 Phase 5 效率路径

原因：

- A/C 是基础设施
- B/E 是用户最能直接感知的问题
- D/F 涉及主编排策略，风险更高，必须建立在前面基础之上

---

## 4.4 Claude 执行约束

要求 Claude：

1. 每完成一个工作包，必须先补测试，再继续下一个
2. 不允许把多个高风险工作包混在一个大 patch 里
3. 任何涉及协议字段变更的地方，必须同步：
   - runtime scripts
   - server ingest
   - GUI store
   - GUI component
   - tests
   - docs
4. 所有“新日志字段”必须结构化，不允许只靠自然语言字符串拼接
5. 所有“是否继续 AskUserQuestion”的判定都必须可追踪到结构化原因

---

## 4.5 最终验收清单

全部完成后，Claude 必须给出以下验证结果：

- 模型切换时，主视区有明显提示
- GUI 在高频事件下不挂、不假死、可诊断
- 日志能追到完整因果链，不只是结果摘要
- Phase 1 在清晰需求场景明显提速
- 恢复流程能解释 fixup 与 AskUserQuestion 的触发原因
- Phase 5 在强依赖任务下仍能提升整体吞吐
- 新增测试全部通过

---

## 5. 推荐给 Claude 的实现口径

如果你把这份文档直接交给 Claude，建议附加一句执行要求：

> 先按本文档的“工作包 A → C → B → E → D → F”顺序执行。每完成一个工作包，先提交代码、补测试、给出验证结果，再继续下一个工作包。不要跳步，不要一次性大改主编排。

