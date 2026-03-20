# spec-autopilot 模型路由增强执行提示词

> 日期：2026-03-19
> 目的：给 Claude 一份可直接执行的后续增强提示词，继续迭代 `spec-autopilot` 的自动切换模型能力。
> 使用方式：直接复制 `## 最终提示词` 下的全部内容，原样交给 Claude。

## 背景

你已经完成了以下文档对应的 `spec-autopilot` 修复与结构化迭代，并且相关内容已经提交：

- [spec-autopilot 完整执行提示词](/Users/lorain/Coding/Huihao/claude-autopilot/docs/plans/2026-03-19-spec-autopilot-execution-prompt.zh.md)

但现在发现一个明确缺口：

- 执行提示词没有把“参考开源竞品做自动切换模型/自动模型路由增强”纳入后续迭代范围

这次要补的不是泛泛的“支持多模型”口号，而是：

- 在 `spec-autopilot` 的既有边界内，把现有 `model_routing` 从提示级能力升级为真实可执行能力

## 你必须先理解的关键前提

仓库里已有模型路由雏形，但仍偏旧：

- [config-schema.md](/Users/lorain/Coding/Huihao/claude-autopilot/plugins/spec-autopilot/skills/autopilot/references/config-schema.md)
- [protocol.md](/Users/lorain/Coding/Huihao/claude-autopilot/plugins/spec-autopilot/skills/autopilot/references/protocol.md)
- [dispatch-prompt-template.md](/Users/lorain/Coding/Huihao/claude-autopilot/plugins/spec-autopilot/skills/autopilot/references/dispatch-prompt-template.md)

目前的主要问题是：

1. `model_routing` 仍是 `heavy / light / auto` 的提示性配置。
2. dispatch prompt 只是注入“高效模式 / 深度分析模式”，没有真实模型解析层。
3. config validator 没有完整校验 `model_routing`。
4. 没有模型升级、失败回退、路由证据输出。
5. 没有对应测试。

同时，你必须意识到一个前提已经改变：

- Claude Code 官方文档现在已经支持模型配置、`opusplan`、subagent `model` 字段，以及 `CLAUDE_CODE_SUBAGENT_MODEL`

因此这轮迭代不能继续沿用“只能做 prompt hint，不能做真实路由”的旧假设。

## 本次任务的正确边界

这次任务允许做：

- `spec-autopilot` 内的 phase / subagent 模型路由增强
- config schema 扩展与兼容迁移
- dispatch 集成
- retry escalation / fallback
- 事件与报告中的模型路由证据
- tests / docs 补齐

这次任务不允许做：

- 把 `spec-autopilot` 改造成通用 model routing platform
- 做跨 provider 的复杂模型市场
- 引入 task graph / scheduler / verifier swarm 平台化能力
- 把 `parallel-harness` 的目标塞进当前插件

## 你必须参考的文档

在开始改代码前，你必须阅读并遵循：

1. /Users/lorain/Coding/Huihao/claude-autopilot/docs/plans/2026-03-19-spec-autopilot-model-routing-enhancement-design.zh.md
2. /Users/lorain/Coding/Huihao/claude-autopilot/docs/plans/2026-03-19-competitive-capability-reuse-matrix.zh.md
3. /Users/lorain/Coding/Huihao/claude-autopilot/docs/plans/2026-03-19-spec-autopilot-execution-prompt.zh.md

## 本轮必须完成的事项

### A. 让 `model_routing` 变成真实可执行能力

你必须把现有 `model_routing` 从“提示级”升级为“执行级”：

1. 支持旧格式兼容：
   - `heavy`
   - `light`
   - `auto`
2. 支持新格式对象化：
   - `enabled`
   - `default_session_model`
   - `default_subagent_model`
   - `fallback_model`
   - `phases.phase_N.model`
   - `phases.phase_N.tier`
   - `phases.phase_N.effort`
   - `phases.phase_N.escalate_on_failure_to`
3. 给出清晰映射：
   - `fast -> haiku`
   - `standard -> sonnet`
   - `deep -> opus`
   - 兼容映射：`light -> standard`，`heavy -> deep`

### B. 建立模型解析层

你必须新增一个统一 resolver，而不是把逻辑散落在 prompt 模板里。

推荐新增：

- `plugins/spec-autopilot/runtime/model-routing/resolve-model.ts`
- `plugins/spec-autopilot/runtime/model-routing/escalation-policy.ts`
- `plugins/spec-autopilot/runtime/model-routing/routing-types.ts`

如果当前仓库更适合先走脚本化实现，也至少要有：

- `plugins/spec-autopilot/runtime/scripts/resolve-model-routing.sh`

resolver 输入至少包括：

- phase number
- complexity
- requirement_type
- retry_count
- 是否 critical task

resolver 输出至少包括：

- `selected_tier`
- `selected_model`
- `selected_effort`
- `routing_reason`
- `escalated_from`
- `fallback_applied`

### C. 把 dispatch 集成到真实模型选择

你必须修改 dispatch 逻辑，使其不再只注入“像某种模型一样工作”的 prompt，而是：

1. 先解析模型路由
2. 再选择 subagent / model
3. 再把路由原因注入 prompt

必须优先检查并修改：

- /Users/lorain/Coding/Huihao/claude-autopilot/plugins/spec-autopilot/skills/autopilot-dispatch/SKILL.md
- /Users/lorain/Coding/Huihao/claude-autopilot/plugins/spec-autopilot/skills/autopilot/references/dispatch-prompt-template.md

### D. 建立最小 subagent 模型分层

你必须建立最小三层：

- `autopilot-fast`
- `autopilot-standard`
- `autopilot-deep`

目标：

- `autopilot-fast` 对应 `haiku`
- `autopilot-standard` 对应 `sonnet`
- `autopilot-deep` 对应 `opus`

如果当前仓库的实现形态不适合显式 subagent 文件，也必须在 dispatch 层明确三层选择策略，并确保未来可平滑迁移到显式 subagent 定义。

### E. 建立 phase 默认路由

你必须至少落地以下默认策略：

1. Phase 1 -> `deep` / `opus`
2. Phase 2 -> `fast` / `haiku`
3. Phase 3 -> `fast` / `haiku`
4. Phase 4 -> `deep` / `opus`
5. Phase 5 -> `standard` / `sonnet`
6. Phase 5 critical retry -> `deep` / `opus`
7. Phase 6 -> `fast` / `haiku`
8. Phase 7 -> `fast` / `haiku`

### F. 建立升级与降级策略

你必须实现最小 escalation policy：

1. `fast` 连续失败一次 -> 升到 `standard`
2. `standard` 连续失败两次或 critical -> 升到 `deep`
3. `deep` 仍失败 -> 不继续自动升级，给出显式 block / manual review / serial fallback
4. 模型不可用时，至少回退到 `fallback_model`

### G. 补充配置校验和文档

你必须更新：

- /Users/lorain/Coding/Huihao/claude-autopilot/plugins/spec-autopilot/runtime/scripts/_config_validator.py
- /Users/lorain/Coding/Huihao/claude-autopilot/plugins/spec-autopilot/runtime/scripts/validate-config.sh
- /Users/lorain/Coding/Huihao/claude-autopilot/plugins/spec-autopilot/skills/autopilot/references/config-schema.md
- /Users/lorain/Coding/Huihao/claude-autopilot/plugins/spec-autopilot/docs/getting-started/configuration.zh.md
- /Users/lorain/Coding/Huihao/claude-autopilot/plugins/spec-autopilot/docs/getting-started/configuration.md

要求：

- 文档说明旧格式与新格式
- 文档说明默认 phase 路由
- 文档说明 fallback / escalation
- 文档说明本能力的边界

### H. 输出模型路由证据

你必须新增结构化证据输出，至少让 event / report 能看见：

- `selected_model`
- `selected_tier`
- `routing_reason`
- `escalated_from`
- `fallback_applied`

这项能力不能只存在于日志字符串里，必须尽量结构化。

### I. 增加或修复测试

你必须至少补这些测试：

1. `heavy/light/auto` 兼容解析
2. 新 schema 对象化配置校验
3. phase 默认路由解析
4. retry escalation
5. fallback 行为
6. dispatch 选择结果

建议新增测试：

- `plugins/spec-autopilot/tests/test_model_routing_resolution.sh`
- `plugins/spec-autopilot/tests/test_model_routing_escalation.sh`

并更新已有 config 测试以覆盖新字段。

## 实施原则

1. 直接改代码，不要只停留在方案分析。
2. 先阅读现有文档与实现，再做兼容式迁移。
3. 优先做最小可执行闭环，不要一开始追求跨 provider 大而全。
4. 不要破坏 `spec-autopilot` 既有门禁、目录和产品定位。
5. 每完成一块就跑对应测试。
6. 如果发现现有 `model_routing` 文档与官方能力假设冲突，必须修正文档，而不是继续保留过时描述。

## 建议实施顺序

1. 阅读设计文档和现有 `model_routing` 相关文件
2. 扩展 config schema 与 validator
3. 新增 resolver / escalation policy
4. 接入 dispatch
5. 增加事件/报告字段
6. 补测试
7. 更新文档
8. 运行验证并汇报

## 验收标准

至少满足以下条件：

1. `model_routing` 不再只是 prompt hint。
2. 旧配置可兼容，新配置可落地。
3. 至少 3 个 phase 使用了不同模型档位。
4. 至少一条失败升级链可运行。
5. 至少一条 fallback 路径可运行。
6. config 测试和模型路由测试通过。
7. 最终汇报能明确说明：
   - 新增了哪些文件
   - 修改了哪些文件
   - 路由规则是什么
   - 跑了哪些测试
   - 剩余限制是什么

## 最终提示词

```text
你现在是这个仓库的高级功能增强工程师。你的任务不是重构新平台，而是在 `spec-autopilot` 现有边界内，把“自动切换模型 / 模型路由”增强做成真实可执行能力。

仓库根目录：
/Users/lorain/Coding/Huihao/claude-autopilot

任务对象：
当前插件 `spec-autopilot`

你必须先阅读并遵循以下文档：
1. /Users/lorain/Coding/Huihao/claude-autopilot/docs/plans/2026-03-19-spec-autopilot-model-routing-enhancement-design.zh.md
2. /Users/lorain/Coding/Huihao/claude-autopilot/docs/plans/2026-03-19-competitive-capability-reuse-matrix.zh.md
3. /Users/lorain/Coding/Huihao/claude-autopilot/docs/plans/2026-03-19-spec-autopilot-execution-prompt.zh.md

你必须理解以下关键背景：

一、当前已有能力
1. 仓库里已经存在 `model_routing` 概念：
   - `plugins/spec-autopilot/skills/autopilot/references/config-schema.md`
   - `plugins/spec-autopilot/skills/autopilot/references/protocol.md`
   - `plugins/spec-autopilot/skills/autopilot/references/dispatch-prompt-template.md`
2. 但当前实现仍然只是 `heavy/light/auto` 的提示级路由，不是真实模型选择。
3. 当前 config validator 没有完整覆盖 `model_routing`。
4. 当前没有统一 resolver、没有升级链、没有 fallback、没有结构化模型路由证据。

二、本次任务的正确边界
1. 这是 `spec-autopilot` 的模型路由增强，不是新平台开发。
2. 允许做 phase / subagent 模型路由增强、dispatch 集成、config 扩展、tests 补齐、文档修订。
3. 不允许把当前插件改造成通用 model router 平台。
4. 不允许引入 task graph / scheduler / verifier swarm / CI 平台化能力。
5. 不允许把跨 provider 的复杂切换逻辑深耦合进确定性门禁核心。

三、本轮必须完成的事项

A. 扩展 `model_routing` 配置
1. 兼容旧格式：
   - `heavy`
   - `light`
   - `auto`
2. 支持新格式：
   - `enabled`
   - `default_session_model`
   - `default_subagent_model`
   - `fallback_model`
   - `phases.phase_N.model`
   - `phases.phase_N.tier`
   - `phases.phase_N.effort`
   - `phases.phase_N.escalate_on_failure_to`
3. 兼容映射：
   - `light -> standard`
   - `heavy -> deep`
4. tier 映射：
   - `fast -> haiku`
   - `standard -> sonnet`
   - `deep -> opus`

B. 实现统一 resolver
1. 新增模型解析层，而不是把逻辑散在 prompt 中。
2. resolver 输入至少包括：
   - phase
   - complexity
   - requirement_type
   - retry_count
   - critical 标记
3. resolver 输出至少包括：
   - `selected_tier`
   - `selected_model`
   - `selected_effort`
   - `routing_reason`
   - `escalated_from`
   - `fallback_applied`

C. 修改 dispatch，使其变成真实路由
1. dispatch 前先解析模型。
2. 按解析结果选择 subagent / model。
3. prompt 里保留路由说明，但不能再只靠提示文字假装路由。

D. 建立最小 subagent 模型分层
1. 至少建立三层概念：
   - `autopilot-fast`
   - `autopilot-standard`
   - `autopilot-deep`
2. 对应：
   - `haiku`
   - `sonnet`
   - `opus`
3. 如果当前仓库结构不适合显式 subagent 文件，也要在 dispatch 层清晰实现这三层选择。

E. 建立默认 phase 路由
1. Phase 1 -> `deep` / `opus`
2. Phase 2 -> `fast` / `haiku`
3. Phase 3 -> `fast` / `haiku`
4. Phase 4 -> `deep` / `opus`
5. Phase 5 -> `standard` / `sonnet`
6. Phase 5 critical retry -> `deep` / `opus`
7. Phase 6 -> `fast` / `haiku`
8. Phase 7 -> `fast` / `haiku`

F. 建立升级与回退
1. `fast` 失败后升级到 `standard`
2. `standard` 连续失败或 critical 升级到 `deep`
3. `deep` 仍失败时不继续自动升级，而是转人工/串行/阻断
4. 模型不可用时回退到 `fallback_model`

G. 更新 schema、validator、文档
必须检查并修改：
1. `plugins/spec-autopilot/skills/autopilot/references/config-schema.md`
2. `plugins/spec-autopilot/skills/autopilot/references/protocol.md`
3. `plugins/spec-autopilot/skills/autopilot/references/dispatch-prompt-template.md`
4. `plugins/spec-autopilot/skills/autopilot-dispatch/SKILL.md`
5. `plugins/spec-autopilot/runtime/scripts/_config_validator.py`
6. `plugins/spec-autopilot/runtime/scripts/validate-config.sh`
7. `plugins/spec-autopilot/docs/getting-started/configuration.zh.md`
8. `plugins/spec-autopilot/docs/getting-started/configuration.md`

H. 增加结构化证据
至少输出：
1. `selected_model`
2. `selected_tier`
3. `routing_reason`
4. `escalated_from`
5. `fallback_applied`

I. 增加测试
至少覆盖：
1. 旧配置兼容
2. 新配置校验
3. phase 路由
4. retry escalation
5. fallback
6. dispatch 路由结果

四、实施原则
1. 直接改代码，不要只写文档。
2. 兼容迁移优先，不要破坏现有使用者配置。
3. 先做最小闭环，再考虑更复杂的 provider 扩展。
4. 保持 `spec-autopilot` 产品定位稳定。
5. 每完成一个关键点就运行对应测试。

五、建议新增文件
1. `plugins/spec-autopilot/runtime/model-routing/resolve-model.ts`
2. `plugins/spec-autopilot/runtime/model-routing/escalation-policy.ts`
3. `plugins/spec-autopilot/runtime/model-routing/routing-types.ts`
4. `plugins/spec-autopilot/tests/test_model_routing_resolution.sh`
5. `plugins/spec-autopilot/tests/test_model_routing_escalation.sh`

如果当前仓库更适合脚本化最小版本，则至少新增：
1. `plugins/spec-autopilot/runtime/scripts/resolve-model-routing.sh`

六、最终输出必须包含
1. 修改了哪些文件
2. 新增了哪些文件
3. 具体路由策略是什么
4. 兼容策略是什么
5. 跑了哪些测试
6. 残留风险和下一步建议

现在开始，不要只给计划，直接实施。
```
