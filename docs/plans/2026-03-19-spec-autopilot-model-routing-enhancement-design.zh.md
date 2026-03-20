# spec-autopilot 模型路由增强方案

> 日期：2026-03-19
> 目的：补上 `docs/plans/2026-03-19-spec-autopilot-execution-prompt.zh.md` 中遗漏的“参考竞品自动切换模型”增强方案，并把它收敛到 `spec-autopilot` 当前产品边界内。

## 1. 先说明为什么之前会漏

之前那份执行提示词没有把“自动切换模型”列为本轮交付，核心原因有两个：

1. 当时的边界判断是正确的：
   - `spec-autopilot` 不应该被改造成“大而全的通用模型路由平台”。
2. 但当时的能力前提已经过时：
   - 仓库内现有文档把 `model_routing` 定义为“提示级行为引导”，并假设 Claude Code 不支持真正的 per-task / subagent 模型控制。

现在这个前提已经不够准确。官方 Claude Code 文档已经明确支持：

- 会话级模型切换：`/model`、`claude --model`
- 特殊别名：`opusplan`
- subagent 默认模型环境变量：`CLAUDE_CODE_SUBAGENT_MODEL`
- 自定义 subagent 的 `model` 字段：`sonnet` / `opus` / `haiku` / `inherit`

这意味着：`spec-autopilot` 现在可以做“有限、可控、工程化”的真实模型路由，而不必继续停留在 prompt hint。

## 2. 本轮增强的正确边界

本轮要做的是：

- 把现有 `model_routing` 从“提示级”升级为“可执行级”
- 让 phase / subagent / retry escalation 真正影响模型选择
- 为成本、稳定性、长会话质量提供可观测证据

本轮不要做的是：

- 不做跨 provider 的大一统模型市场
- 不做独立 task graph 平台级 router
- 不把 `spec-autopilot` 改造成 `parallel-harness`
- 不把外部 provider 切换逻辑深度耦合进核心门禁链路

一句话定义：

`spec-autopilot` 只做“面向 8 阶段流水线的确定性模型路由增强”，不做“通用 AI 平台级路由器”。

## 3. 现状与缺口

当前仓库里已经有模型路由雏形：

- [config-schema.md](/Users/lorain/Coding/Huihao/claude-autopilot/plugins/spec-autopilot/skills/autopilot/references/config-schema.md)
- [protocol.md](/Users/lorain/Coding/Huihao/claude-autopilot/plugins/spec-autopilot/skills/autopilot/references/protocol.md)
- [dispatch-prompt-template.md](/Users/lorain/Coding/Huihao/claude-autopilot/plugins/spec-autopilot/skills/autopilot/references/dispatch-prompt-template.md)

但当前问题是：

1. `model_routing` 只有 `heavy / light / auto` 提示，没有真实模型解析层。
2. 配置校验没有真正校验 `model_routing` 的结构和枚举。
3. dispatch 层没有统一的“模型解析 -> subagent 选择 -> 失败升级 -> fallback”闭环。
4. 运行时没有产出 `selected_model` / `routing_reason` / `escalated_from` 等证据。
5. 测试里没有覆盖“模型路由解析、兼容、升级、降级”。

## 4. 竞品能力应该怎么吸收

### 4.1 `claude-code-switch` 应该吸收什么

该项目值得吸收的是：

- 模型切换显式化
- provider / model 切换命令体验
- user-level / project-level override 思路

但对 `spec-autopilot` 的正确吸收方式不是“把外部 provider 切换器直接嵌入插件”，而是：

- 借鉴它的 override 层级
- 借鉴它的显式切换体验
- 插件内部仍优先基于 Claude Code 官方模型别名和 subagent 模型配置实现

### 4.2 `oh-my-claudecode` 应该吸收什么

该项目值得吸收的是：

- 按任务复杂度自动用不同模型
- 把成本优化做成默认能力

对 `spec-autopilot` 的正确落地是：

- Phase / 子任务按风险和复杂度自动升级模型
- 高价值阶段用深模型，机械阶段用轻模型
- 保留失败升级和可观测性，避免“省 token 但省掉质量”

### 4.3 `BMAD-METHOD` / `superpowers` 应该吸收什么

这两个项目更像方法论和角色工程：

- `BMAD-METHOD` 提供角色化与流程化结构
- `superpowers` 提供轻量、低摩擦的能力入口

对当前插件的启发是：

- 模型路由不能只是配置项，必须进入角色和 phase 的执行合同
- 配置必须向下传递成稳定、可测试的执行行为

### 4.4 `Harness AI Agents` 应该吸收什么

其核心启发不是“模型切换”，而是：

- 成本、质量、修复动作要形成闭环

所以 `spec-autopilot` 的模型路由增强不能只回答“用了哪个模型”，还要回答：

- 为什么选它
- 如果失败了怎么升级
- 是否带来了更好的质量证据

## 5. 具体方案

## 5.1 方案总览

建议把增强拆成四层：

1. 配置层
2. 解析层
3. 派发层
4. 证据层

目标结构建议新增：

```text
plugins/spec-autopilot/
  runtime/
    model-routing/
      resolve-model.ts
      escalation-policy.ts
      routing-types.ts
      routing-events.ts
```

如果本轮不想过早引入 TS 模块，也可以先走脚本化最小版本：

```text
plugins/spec-autopilot/
  runtime/
    scripts/
      resolve-model-routing.sh
      emit-model-routing-event.sh
```

推荐优先选第一种，因为更容易测试、扩展和被 server/GUI 消费。

## 5.2 配置层设计

### 兼容原则

必须兼容旧配置：

```yaml
model_routing:
  phase_1: heavy
  phase_2: light
```

并允许新配置对象化：

```yaml
model_routing:
  enabled: true
  default_session_model: opusplan
  default_subagent_model: sonnet
  fallback_model: sonnet
  phases:
    phase_1:
      tier: deep
      model: opus
      effort: high
    phase_2:
      tier: fast
      model: haiku
      effort: low
    phase_5:
      tier: standard
      model: sonnet
      effort: medium
      escalate_on_failure_to: opus
```

### 推荐 tier 语义

- `fast` -> `haiku`
- `standard` -> `sonnet`
- `deep` -> `opus`
- `auto` -> 继承父会话

向后兼容映射：

- `light` -> `standard`
- `heavy` -> `deep`
- `auto` -> `auto`

### 建议默认值

- `default_session_model: opusplan`
- `default_subagent_model: sonnet`
- `fallback_model: sonnet`

理由：

- 主会话适合 `opusplan`，让计划/执行天然分离
- 大多数 subagent 任务默认走 `sonnet`，避免无脑全局 `opus`
- 当某模型不可用时，`sonnet` 是最稳的回退位

## 5.3 phase 默认路由建议

建议第一版直接固化如下映射：

| Phase | 默认 tier | 默认模型 | 原因 |
|------|------|------|------|
| 1 requirements | `deep` | `opus` | 需求分析、决策澄清、边界判断最吃推理 |
| 2 openspec | `fast` | `haiku` | 结构化制品填充偏机械 |
| 3 ff | `fast` | `haiku` | 模板化生成、低风险 |
| 4 testing | `deep` | `opus` | 测试设计、边界与反例需要深推理 |
| 5 implementation | `standard` | `sonnet` | 代码实现性价比最高 |
| 5 critical retry | `deep` | `opus` | 连续失败或高风险任务自动升级 |
| 6 reporting | `fast` | `haiku` | 报告整理和摘要偏机械 |
| 7 summary | `fast` | `haiku` | 收尾汇总偏机械 |

## 5.4 风险/复杂度覆盖规则

phase 默认值之外，再叠加三个 override：

1. `complexity`
2. `requirement_type`
3. `retry_count`

建议规则：

- `complexity = large` 且 phase 为 1/4/5 时，最低不低于 `deep`
- `requirement_type` 包含 `bugfix` 且 phase 为 4/5 时，最低不低于 `standard`
- `requirement_type` 包含 `refactor` 且影响面大时，phase 5 可直接升到 `deep`
- 同一 task / 子任务连续失败 1 次：`fast -> standard`
- 连续失败 2 次：`standard -> deep`
- 已经是 `deep` 且仍失败：不再自动升级，转人工决策或串行降并发

## 5.5 subagent 路由设计

这是本轮最关键的落地点。

不要依赖“在 prompt 里提醒它像某种模型一样思考”，而是直接把模型挂到 subagent 定义里。

推荐新增三个 autopilot 子 agent：

- `autopilot-fast`
- `autopilot-standard`
- `autopilot-deep`

对应：

- `autopilot-fast` -> `model: haiku`
- `autopilot-standard` -> `model: sonnet`
- `autopilot-deep` -> `model: opus`

dispatch 时不再只注入“高效模式/深度分析模式”文字，而是：

1. 先解析 phase + complexity + requirement_type + retry
2. 得到 `selected_model`
3. 选择对应 subagent
4. 再把 `routing_reason` 注入 prompt 和事件

这样可以把“提示级”能力升级成“执行级”能力。

## 5.6 主会话路由设计

主会话不建议频繁依赖 `/model` 动态切换，因为这会增加会话控制复杂度。

更稳妥的策略是：

1. 推荐用户在启动 `spec-autopilot` 前使用 `claude --model opusplan`
2. 插件内部把绝大部分 phase 工作派发给显式定义模型的 subagent
3. 主线程保留 orchestration、决策确认、门禁推进职责

这能兼顾稳定性和成本。

## 5.7 长会话与大上下文策略

第二阶段可补充：

- 当 Phase 1 / Phase 5 的上下文摘要超过阈值时，允许切换到 `sonnet[1m]`
- 对长会话优先升级上下文窗口，而不是一味升级到更贵模型

但这项建议放在第二阶段，不要阻塞第一阶段落地。

## 5.8 证据层设计

每次路由决策都必须留下结构化证据。

建议新增事件字段：

- `phase`
- `task_id`
- `selected_tier`
- `selected_model`
- `selected_effort`
- `routing_reason`
- `escalated_from`
- `fallback_applied`

建议写入：

- event bus
- phase envelope
- 最终报告摘要

这样后续才能量化：

- 哪些阶段最烧 token
- 哪些阶段最常升级
- 模型升级是否真的减少重试

## 6. 本轮建议修改的文件

优先修改：

- [config-schema.md](/Users/lorain/Coding/Huihao/claude-autopilot/plugins/spec-autopilot/skills/autopilot/references/config-schema.md)
- [protocol.md](/Users/lorain/Coding/Huihao/claude-autopilot/plugins/spec-autopilot/skills/autopilot/references/protocol.md)
- [dispatch-prompt-template.md](/Users/lorain/Coding/Huihao/claude-autopilot/plugins/spec-autopilot/skills/autopilot/references/dispatch-prompt-template.md)
- [SKILL.md](/Users/lorain/Coding/Huihao/claude-autopilot/plugins/spec-autopilot/skills/autopilot-dispatch/SKILL.md)
- [validate-config.sh](/Users/lorain/Coding/Huihao/claude-autopilot/plugins/spec-autopilot/runtime/scripts/validate-config.sh)
- [_config_validator.py](/Users/lorain/Coding/Huihao/claude-autopilot/plugins/spec-autopilot/runtime/scripts/_config_validator.py)
- [configuration.zh.md](/Users/lorain/Coding/Huihao/claude-autopilot/plugins/spec-autopilot/docs/getting-started/configuration.zh.md)
- [configuration.md](/Users/lorain/Coding/Huihao/claude-autopilot/plugins/spec-autopilot/docs/getting-started/configuration.md)

新增建议：

- `plugins/spec-autopilot/runtime/model-routing/resolve-model.ts`
- `plugins/spec-autopilot/runtime/model-routing/escalation-policy.ts`
- `plugins/spec-autopilot/runtime/model-routing/routing-types.ts`
- `plugins/spec-autopilot/tests/test_model_routing_resolution.sh`
- `plugins/spec-autopilot/tests/test_model_routing_escalation.sh`

如果本轮只想做最小脚本版本，则新增：

- `plugins/spec-autopilot/runtime/scripts/resolve-model-routing.sh`
- `plugins/spec-autopilot/runtime/scripts/emit-model-routing-event.sh`

## 7. 验收标准

本轮结束至少应满足：

1. 旧版 `heavy/light/auto` 配置仍可用。
2. 新版对象化 `model_routing` 配置可通过校验。
3. dispatch 不再只注入模型提示，而是能解析出真实 `selected_model`。
4. 至少 phase 2 / 5 / 6 三类任务能走不同模型。
5. 至少实现一条失败升级链：`haiku -> sonnet -> opus` 或 `sonnet -> opus`。
6. 有测试覆盖：
   - 兼容映射
   - phase 路由
   - retry escalation
   - fallback 行为
7. 最终报告能显示模型路由证据。

## 8. 推荐实施顺序

### 第一阶段：把配置做实

- 扩展 `model_routing` schema
- 增加 config validator 校验
- 保持旧格式兼容

### 第二阶段：把 dispatch 做实

- 新增 resolver
- dispatch 根据 resolver 结果选子 agent / 模型
- 保留原 prompt hint 作为附加信息，不再作为唯一机制

### 第三阶段：把升级与回退做实

- 失败升级
- 模型不可用时 fallback
- 事件记录

### 第四阶段：把文档与测试补齐

- 配置文档
- 运行说明
- 单测 / shell 测试

## 9. 结论

这轮最重要的不是“支持更多模型名字”，而是完成三个转变：

1. 从提示级路由，升级到执行级路由。
2. 从静态 phase 建议，升级到 phase + 风险 + retry 的组合决策。
3. 从手工感知模型，升级到有证据、可回归、可观察的工程能力。

`spec-autopilot` 做到这里就够了。

再往上的跨 provider、多插件、多任务图 router，应该继续放在 `parallel-harness`。

## 10. 外部参考

- Claude Code 模型配置: https://docs.anthropic.com/zh-CN/docs/claude-code/model-config
- Claude Code subagents: https://docs.anthropic.com/zh-CN/docs/claude-code/sub-agents
- claude-code-switch: https://github.com/foreveryh/claude-code-switch
- oh-my-claudecode: https://ohmyclaudecode.com/
- BMAD-METHOD: https://github.com/bmad-code-org/BMAD-METHOD
- Harness AI Agents: https://developer.harness.io/docs/code-repository/pull-requests/ai-agents/
