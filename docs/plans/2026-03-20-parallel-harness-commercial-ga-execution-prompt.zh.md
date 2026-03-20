# parallel-harness 商业化 GA 执行提示词

> 日期：2026-03-20
> 目的：这是一份面向 `plugins/parallel-harness` 的商业化 GA 执行提示词，用于在现有实现基础上继续迭代到可直接接入、可治理、可审计、可发布、可运营的完整插件。
> 使用方式：直接复制 `## 最终提示词` 下的全部内容，原样交给 Claude。
> 执行原则：不是补 MVP，不是再做一层骨架，不是只补文档和 schema，而是按商业化上线标准把平台能力补齐。

## 为什么需要新的提示词

`parallel-harness` 已经完成一轮基于 `mvp-scope.zh.md` 的实现，但当前交付仍然停留在“模块化 Beta”：

- 有编排模块，但缺少统一运行时入口，很多能力仍是并列模块，不是闭环平台。
- 有 scheduler、ownership、router、verifier，但它们之间仍有明显的“弱绑定”与“模拟执行”。
- 有测试和文档，但还不是面向商业接入的治理、运维、发布、审计、支持体系。
- 有部分竞品能力映射，但还没有做到 Harness、GitHub Copilot coding agent、CodeRabbit 这一档产品的闭环深度。

因此，后续工作不能再按 MVP 范式推进，而必须转成商业化 GA 范式推进。

## 现状判断

基于前一轮的实现总结，当前版本已经具备：

- 任务图引擎
- 文件级 ownership 规划
- 三层模型路由
- verifier swarm 基础模块
- 基础 scheduler
- context packager
- planner/worker/verifier/synthesizer 角色合同

但距离“可直接商业化接入和使用”的目标，仍存在关键缺口：

1. `worker-dispatch` 仍偏模拟，缺少真实 worker runtime、隔离执行与恢复机制。
2. 缺少真正统一的 orchestrator 入口，当前更像模块集合，不是受控平台。
3. ownership 没有真正贯通 scheduler、dispatch、merge guard、policy engine。
4. model router 仍容易被静态 `model_tier` 兜底短路，缺少失败升级、预算压降、SLO 驱动的闭环。
5. verifier 仍更像结果汇总器，尚未升级为可阻断的 gate system。
6. PR/CI 侧若只是 comment/formatter/reporter 层，不足以对标 Harness 与 CodeRabbit。
7. session、event、observability 若仍是内存态，就不具备商业级审计与追溯能力。
8. 缺少 policy-as-code、RBAC、审批流、人工介入、租户边界、密钥治理。
9. 缺少 GUI / control-plane / 运维面板，难以被团队真正使用。
10. 缺少商业化发布链路：版本迁移、打包、兼容性矩阵、支持文档、SLA/SLO、升级策略。

## 必须先阅读的本地文档

在开始任何编码前，必须完整阅读并遵循以下本地文档：

- [全局调研报告](docs/plans/2026-03-19-holistic-architecture-research-report.zh.md)
- [并行 AI 平台插件设计](docs/plans/2026-03-19-parallel-ai-platform-plugin-design.zh.md)
- [竞品能力复用矩阵](docs/plans/2026-03-19-competitive-capability-reuse-matrix.zh.md)
- [parallel-harness 实施 Backlog](docs/plans/2026-03-19-parallel-harness-execution-backlog.zh.md)
- [parallel-harness 完整执行提示词](docs/plans/2026-03-19-parallel-harness-execution-prompt.zh.md)

如果后续在仓库内发现其他 `parallel-harness` 的设计、评审、README、架构文档，也必须纳入上下文；不得忽略已有实现现状，直接重建一套平行系统。

## 必须参考的外部竞品资料

以下资料不是“可选参考”，而是本轮商业化能力对标基线：

### Harness

- https://developer.harness.io/docs/platform/harness-aida/harness-agents

必须吸收的能力：

- pipeline-native runtime
- agent 作为平台一等执行单元
- OPA policy enforcement
- RBAC / connectors / secrets / approvals
- full audit trail
- API 调用与模板化复用
- 可接 PR / CI / coverage / autofix 的闭环

### GitHub Copilot coding agent

- https://docs.github.com/en/copilot/using-github-copilot/using-copilot-coding-agent-to-work-on-tasks
- https://docs.github.com/en/copilot/concepts/agents/coding-agent/about-coding-agent

必须吸收的能力：

- 后台异步 delegated execution
- ephemeral execution environment
- PR-first workflow
- sessions / logs / steerable iteration
- custom agents / hooks / MCP / environment customization
- firewall / network governance
- 组织级策略与审计

### CodeRabbit

- https://docs.coderabbit.ai/overview/pull-request-review
- https://docs.coderabbit.ai/reference/review-commands
- https://docs.coderabbit.ai/pr-reviews/summaries
- https://docs.coderabbit.ai/guides/review-instructions

必须吸收的能力：

- incremental review / full review
- PR summary / walkthrough / structured review output
- path-based review instructions
- auto review controls
- autofix / unit test generation / stacked PR
- review config as code
- 评审结果直接进入 PR 工作流，而不是停在控制台输出

## 商业化 GA 目标定义

本轮不是要交付“可演示的并行 harness”，而是要交付一个：

- 可安装
- 可配置
- 可治理
- 可观测
- 可审计
- 可接 SCM / CI / PR
- 可多团队复用
- 可版本升级
- 可文档化交付
- 可作为 marketplace 插件商业化接入

的完整插件。

目标产物必须满足：

- 不是单点算法集合，而是平台化运行时。
- 不是单次命令体验，而是会话化、批次化、可恢复系统。
- 不是“跑完即失忆”，而是有历史、审计、决策痕迹与治理约束。
- 不是只对开发者友好，也要对平台管理员、审核者、运维人员友好。

## 多维度竞品对标后的缺失清单

### 1. 运行时维度

相对 Harness / Copilot coding agent，缺少：

- 统一 orchestrator runtime
- batch / run / task / verifier 的状态机
- 后台任务执行与恢复
- 真实 worker dispatch
- 沙箱策略、网络策略、工具策略
- cancel / retry / replay / resume

### 2. 工程治理维度

相对 Harness，缺少：

- policy-as-code
- approvals
- RBAC / project / org scope
- connector / secret / environment boundary
- execution entitlement
- change guard / merge guard 实际拦截

### 3. PR / CI 闭环维度

相对 Copilot coding agent / CodeRabbit，缺少：

- provider-native PR 流程
- review mode 切换
- PR summary / walkthrough / delta review
- autofix branch / stacked PR
- issue / PR / CI run 之间的统一关联标识
- 会话日志与 PR 评论的双向映射

### 4. 可观测与审计维度

相对 Harness，缺少：

- durable event log
- run timeline
- task lineage
- verifier evidence store
- cost ledger
- model decision trace
- 可导出的审计报告

### 5. 运营与商业化维度

相对成熟平台产品，缺少：

- 安装向导与配置模板
- 兼容性矩阵
- 迁移脚本与版本升级说明
- license / plan / quota / budget 策略钩子
- 支持手册、排障手册、FAQ、runbook
- 发布链路、回滚链路、Beta/GA 分级策略

## 必须补齐的实施范围

以下所有部分都要尽量在这一轮中落地到代码、配置、测试、文档和可运行链路，而不是只写设计文档。

### A. 统一 Orchestrator / Runtime 主入口

必须新增或重构出真正的一等主入口，负责：

- intent ingest
- task graph build
- ownership plan
- scheduling
- worker dispatch
- verifier dispatch
- synthesis
- persistence
- event publication
- policy evaluation
- approval checkpoints

实施要求：

- 定义统一 `RunRequest`、`RunPlan`、`RunExecution`、`RunResult` 数据结构。
- 统一 `run_id / batch_id / task_id / attempt_id / verifier_id / review_id` 标识体系。
- 形成单入口服务，而不是由调用方自行拼模块。
- 所有模块都必须通过 runtime context 共享同一份 execution metadata。

目标结果：

- 输入一个任务请求后，系统能创建完整 run，贯通从规划到验证到汇总的生命周期。

### B. 真实 Worker Runtime 与隔离执行

必须把 `worker-dispatch` 从模拟升级为真实运行时：

- worker contract
- worker launch strategy
- worker capability registry
- tool allowlist / denylist
- path sandbox
- environment injection
- timeout / heartbeat / cancellation
- retry with idempotency
- partial failure recovery

实施要求：

- Worker 必须接收结构化 task contract，而不是自由 prompt。
- 必须有执行前校验：ownership、policy、budget、capability、approval。
- 必须支持本地 worker 与未来远端 worker 的抽象接口。
- 必须记录每次 worker attempt 的输入、输出摘要、成本、状态迁移、失败分类。

目标结果：

- 无冲突任务能被真实分发执行。
- 冲突任务会被阻断、串行化或等待审批，而不是默默继续。

### C. Ownership Enforcement / Merge Guard / Policy Engine

必须把 ownership 从“规划建议”升级为“强约束执行器”：

- scheduler 必须消费 ownership plan
- dispatch 必须拒绝越权路径
- merge guard 必须在任务汇总、PR 输出、autofix 前再次检查
- policy engine 必须支持规则化约束

实施要求：

- 支持 path claim、path reservation、conflict resolution、handoff。
- 定义 `policy violations`、`ownership violations`、`unsafe override` 语义。
- 提供最小 policy DSL 或 JSON/YAML policy schema。
- 支持规则类别：路径边界、模型等级上限、网络访问、敏感目录、需要审批的动作、最大并行度、预算上限。

目标结果：

- 任何越界改动、敏感目录写入、超预算、未授权模型升级，都可以被系统级阻断。

### D. Schema 升级为 GA 级契约

现有 schema 必须升级到能够支撑持久化、审计和外部集成：

必须覆盖：

- task graph schema
- run schema
- task execution schema
- worker attempt schema
- verifier result schema
- review artifact schema
- policy decision schema
- approval decision schema
- audit event schema
- cost ledger schema
- connector / environment / session schema

实施要求：

- 增加版本字段与 migration 策略。
- 所有 schema 必须能序列化并长期存储。
- 为未来 API / GUI / CLI / webhook 复用保留稳定字段。

目标结果：

- schema 不再只是内部类型，而是产品级 contract。

### E. 任务状态机与失败分类

必须实现清晰的状态机，而不是散落的布尔值：

Run 状态至少包括：

- pending
- planned
- awaiting_approval
- scheduled
- running
- verifying
- blocked
- failed
- partially_failed
- succeeded
- cancelled
- archived

Task / Worker Attempt / Verifier 也必须各自拥有状态机。

必须定义失败分类：

- transient_tool_failure
- permanent_policy_failure
- ownership_conflict
- budget_exhausted
- approval_denied
- verification_failed
- network_restricted
- unsupported_capability
- human_intervention_required

目标结果：

- 失败能被正确归因，后续重试、升级、降级、人工接管都有依据。

### F. 模型路由、预算控制、升级与降级闭环

当前 router 必须升级为闭环控制器，而不是一次性选择器。

必须新增：

- budget policy
- quota policy
- escalation policy
- downgrade policy
- fallback chain
- retry model selection
- route explanation
- model decision audit trace

实施要求：

- 路由输入必须包含：复杂度、风险、任务类型、历史失败、token 预算、组织策略、敏感度、SLO 等级。
- 不允许默认 `model_tier` 直接绕过动态策略。
- 支持不同阶段使用不同模型：planner、worker、review、security、summary。
- 支持超预算时自动压降非关键 verifier 或改用低 tier summary 模型。

目标结果：

- 形成“质量、成本、风险”三者之间的动态控制闭环。

### G. Verifier Swarm 升级为 Gate System

当前 verifier 体系必须从“结果综合”升级成“可阻断门禁系统”。

必须至少具备以下 verifier / gate 类型：

- test gate
- lint / type gate
- review gate
- security gate
- perf gate
- coverage gate
- policy gate
- documentation gate
- release readiness gate

实施要求：

- 每类 gate 要有输入合同、阈值、结论、证据、阻断级别。
- 支持 task-level、run-level、PR-level 三层 gate。
- 支持 incremental review 与 full review。
- review 输出必须结构化：summary、findings、risk、required actions、suggested patches。
- coverage 不能只做 reporter，必须能成为 merge blocker。

目标结果：

- verifier 结论能真正决定是否继续、是否合并、是否发布。

### H. PR / CI Provider-Native Integration

必须把 PR / CI 打通到商业可用级别，而不是只输出本地报告。

必须实现或预留稳定接口：

- GitHub PR review adapter
- GitHub Checks / statuses adapter
- issue-to-run / PR-to-run mapping
- CI failure ingest
- autofix branch strategy
- stacked PR strategy
- incremental push re-review
- PR summary renderer
- walkthrough / evidence comment renderer

实施要求：

- 参考 Copilot coding agent 的 PR-first 执行形态。
- 参考 CodeRabbit 的 incremental/full review、summary placeholder、path-based review instructions。
- review 指令、summary 指令、autofix 指令必须通过 provider-native surface 暴露，而不是自造一个不可接入的命令体系。

目标结果：

- 用户能在 PR 中直接触发、查看、控制并行 harness 的行为。

### I. Session Persistence / Event Bus / Audit Trail

必须把 session、event、history 从内存态升级为持久化体系。

必须新增：

- session store
- run store
- task attempt store
- verifier evidence store
- event bus abstraction
- event sink
- audit trail exporter
- resumable execution loader

实施要求：

- 至少支持本地持久化适配器，并抽象未来数据库适配层。
- 所有关键动作都要形成审计事件：谁触发、什么输入、使用了什么模型、调用了什么工具、修改了什么范围、何时被 gate 阻断、何时被人工批准。
- 需要支持 session timeline、run replay、failure forensics。

目标结果：

- 平台具备问题定位、合规追踪、历史复盘能力。

### J. Governance / RBAC / Approval / Human-in-the-loop

必须增加商业化必须的治理平面：

- actor identity
- org / project / repo / environment scope
- role-based access control
- approval workflow
- emergency override
- human takeover / human comment feedback loop
- sensitive action confirmation

实施要求：

- 定义谁可以创建 run、谁可以批准模型升级、谁可以允许写敏感目录、谁可以执行 autofix push、谁可以忽略 gate。
- approval 要能绑定具体动作，而不是笼统批准。
- 人工反馈要能回流到 session / run history。

目标结果：

- 不是“AI 自由执行”，而是“AI 在企业治理框架内执行”。

### K. GUI / Control Plane

如果当前插件已有 GUI / dashboard 基础，必须继续补齐；如果没有，必须新增最小控制面。

至少要有以下面板：

- run list
- run detail timeline
- task graph view
- worker execution panel
- verifier / gate panel
- cost / budget panel
- policy / approval panel
- artifacts / reports panel
- configuration diagnostics panel

实施要求：

- 支持查看状态、失败点、路径 ownership、使用模型、花费估算、证据链接。
- 支持手动 retry、resume、cancel、approve、reject、reroute。
- 界面必须服务真实操作，不是静态演示图。

目标结果：

- 团队成员和管理员不需要翻源码或日志文件才能使用插件。

### L. Skills / Hooks / Capability Assets / Extensibility

必须建立可扩展资产层，对标 Copilot 自定义 agent / hook 与开源生态的 capability-as-code：

- capability registry
- skill manifests
- hook lifecycle
- policy-aware tool adapters
- instruction packs
- path / repo / language scoped rules

实施要求：

- 每个 capability 必须声明用途、输入、输出、权限、依赖工具、推荐模型 tier、适用阶段。
- 支持 repo-level 和 org-level 指令继承。
- 支持 path-based review / coding instructions。

目标结果：

- 平台可以按团队、仓库、语言逐步扩展，而不是每次改核心代码。

### M. 商业化准备：打包、发布、迁移、兼容性、支持

必须补齐商业化交付链路：

- build / dist 输出
- plugin package validation
- marketplace readiness checklist
- semver versioning
- migration scripts / data migrations
- backward compatibility notes
- release notes template
- support matrix
- operational runbook
- incident / rollback playbook

实施要求：

- 至少完成一个可验证的 dist 产物链路。
- 插件元数据、依赖、入口、配置说明必须完整。
- 对外文档要写清楚兼容条件、限制、实验性功能、升级步骤。

目标结果：

- 插件能从源码工程走到可发布、可升级、可支持的产品状态。

### N. 商业级测试体系

现有单元测试不够，必须建立分层测试矩阵：

- schema validation tests
- orchestrator integration tests
- scheduler / ownership conflict tests
- worker runtime tests
- retry / escalation / downgrade tests
- verifier gate tests
- persistence / replay tests
- PR adapter tests
- policy / approval tests
- GUI smoke tests
- packaging / build tests

实施要求：

- 测试不只是 happy path，必须覆盖冲突、超预算、审批拒绝、session 恢复、增量 review、autofix 回退。
- 如无法完整接入真实外部 provider，至少提供契约测试和稳定 mock。
- 必须输出覆盖范围说明，不得只报通过数。

目标结果：

- 平台关键路径可被持续回归验证。

### O. 文档、运维资料与交付材料

必须补齐面向不同角色的文档，而不是只有开发 README：

- README / README.zh
- architecture
- operator guide
- admin guide
- policy guide
- integration guide
- troubleshooting
- FAQ
- release checklist
- security / compliance notes
- examples / demo flows

实施要求：

- 文档必须覆盖安装、配置、运行、接 PR/CI、治理、审计、故障排查。
- 要明确与 `spec-autopilot` 的边界和组合方式。
- 要有典型流程示例：需求拆图、并行执行、PR review、CI failure autofix、coverage gate、人工审批。

目标结果：

- 商业接入方无需翻实现代码就能部署、配置、使用和排障。

## 额外必须补齐的商业化环节

除了技术实现，还必须补齐以下成熟产品常见环节：

### 1. 多租户与作用域模型

- account / org / project / repo / environment 作用域
- 配置继承与覆盖
- 不同作用域下的 policy / connector / instruction 继承

### 2. 密钥与连接器治理

- LLM connector
- SCM connector
- CI connector
- ticketing / chat / MCP connector
- secret reference 而不是明文配置

### 3. 配额、预算与计费钩子

- 每 run / 每 repo / 每组织预算
- token / cost ledger
- plan / quota hook
- 将来对接 license / billing 的数据面

### 4. 数据治理与安全

- 数据保留策略
- 敏感内容脱敏
- 审计导出
- 访问日志
- 配置项中的安全默认值

### 5. SLO / SLA / 支持体系

- run 成功率
- 平均完成时延
- verifier 阻断率
- autofix 成功率
- escalation 触发率
- 支持手册与故障升级路径

## 交付物清单

本轮必须尽可能交付以下产物，不接受只完成其中少数：

- 商业化 GA 级 runtime 代码
- 对应 schema / config / policy 契约
- 完整测试矩阵
- GUI / control-plane 或最小可操作界面
- PR / CI adapter 或稳定接口层
- 持久化与审计基础设施
- 构建与打包链路
- 完整文档与运维资料
- 商业化 readiness 评估报告

## 完成标准

只有满足以下条件，才能视为本轮任务完成：

1. 不再存在仅文档化、未接线的关键核心模块。
2. `worker-dispatch`、`retry-manager`、`downgrade-manager`、`cost-controller`、`escalation-policy`、`event-bus`、`observability-server`、`session-state` 等关键缺口已被真正实现或以可运行 stub + 明确接口 + 测试接入，而不是空文件占位。
3. runtime 能统一拉起 run 并产出可追溯的生命周期状态。
4. verifier 体系可以形成真实 gate，而不是仅打印报告。
5. PR/CI 至少完成一条 provider-native 主路径。
6. ownership / policy / approval 能真实阻断危险动作。
7. 数据持久化、日志、审计、回放至少完成本地可运行版本。
8. 文档能支撑真实接入、运维和排障。
9. 插件具备清晰可验证的 dist / packaging / release readiness。
10. 测试覆盖关键主路径和关键失败路径。

## 实施要求

### 原则

- 直接在现有 `plugins/parallel-harness` 基础上继续演进，不允许另起一套平行实现。
- 优先补齐真正决定商业化可用性的链路，不要沉迷次要抽象。
- 能落到代码就不要只写设计文档。
- 能落到测试就不要只写 TODO。
- 能落到 provider-native 接口就不要只做纯内部模拟。

### 顺序建议

1. 先做现状审计，列出已实现、半实现、未实现。
2. 先贯通统一 runtime 主路径。
3. 再打通真实 worker、ownership enforcement、policy、session persistence。
4. 再升级 verifier gate、PR/CI integration。
5. 再补 GUI、商业化发布链路、文档与支持资料。

### 每完成一批模块时必须同步完成

- 类型定义
- 测试
- 文档
- 示例配置
- 运行验证

## 最终提示词

以下内容可直接复制给 Claude：

```md
你现在要继续迭代 `plugins/parallel-harness`，但目标不再是 MVP，而是商业化 GA 级可用插件。你必须先阅读以下本地文档，并基于当前仓库已有实现做真实增量迭代，而不是重建一套平行系统：

- `docs/plans/2026-03-19-holistic-architecture-research-report.zh.md`
- `docs/plans/2026-03-19-parallel-ai-platform-plugin-design.zh.md`
- `docs/plans/2026-03-19-competitive-capability-reuse-matrix.zh.md`
- `docs/plans/2026-03-19-parallel-harness-execution-backlog.zh.md`
- `docs/plans/2026-03-19-parallel-harness-execution-prompt.zh.md`

同时你必须对标这些外部成熟产品能力，并把它们转成可落地模块，而不是停留在分析层：

- Harness Agents: `https://developer.harness.io/docs/platform/harness-aida/harness-agents`
- GitHub Copilot coding agent:
  - `https://docs.github.com/en/copilot/using-github-copilot/using-copilot-coding-agent-to-work-on-tasks`
  - `https://docs.github.com/en/copilot/concepts/agents/coding-agent/about-coding-agent`
- CodeRabbit:
  - `https://docs.coderabbit.ai/overview/pull-request-review`
  - `https://docs.coderabbit.ai/reference/review-commands`
  - `https://docs.coderabbit.ai/pr-reviews/summaries`
  - `https://docs.coderabbit.ai/guides/review-instructions`

你必须先对 `plugins/parallel-harness` 做一次现状审计，输出：

1. 已完成模块
2. 半完成模块
3. 未完成模块
4. 关键假实现/弱绑定/空壳模块
5. 与商业化 GA 的差距列表

然后直接开始实现，目标是把它提升到“可直接商业化接入和使用”的插件。不要只补 schema，不要只补文档，不要只做骨架，不要停在 MVP。

必须完成的实施范围如下：

### 1. 统一 runtime / orchestrator

实现一个真正的一等主入口，统一串起：

- intent ingest
- task graph build
- ownership planning
- scheduling
- worker dispatch
- verifier dispatch
- synthesis
- persistence
- event publication
- policy evaluation
- approvals

要求：

- 定义统一 `RunRequest`、`RunPlan`、`RunExecution`、`RunResult`
- 统一 `run_id / batch_id / task_id / attempt_id / verifier_id / review_id`
- 所有模块共享统一 execution context
- 提供清晰入口 API / service

### 2. 真实 worker runtime

把 `worker-dispatch` 从模拟升级成真实运行时：

- worker contract
- worker launcher
- capability registry
- tool allowlist / denylist
- path sandbox
- timeout / heartbeat / cancel / retry
- local adapter 与 future remote adapter abstraction

要求：

- task 必须以结构化 contract 下发
- 执行前必须经过 ownership、policy、budget、approval 校验
- 每次 attempt 都要记录输入摘要、输出摘要、状态、错误、成本

### 3. ownership enforcement + merge guard + policy engine

把 ownership 从建议升级为强约束：

- scheduler 消费 ownership
- dispatch 拒绝越权写入
- merge guard 在汇总、autofix、PR 输出前复检
- 支持 policy-as-code

要求：

- 实现 path claim / reservation / conflict resolution / handoff
- 定义 ownership violation / policy violation / unsafe override
- 提供最小 policy schema 或 DSL
- 支持路径边界、敏感目录、模型等级、预算、网络、并行度、审批条件约束

### 4. schema 升级

把 schema 升级成产品级 contract：

- run schema
- task graph schema
- task execution schema
- worker attempt schema
- verifier result schema
- review artifact schema
- policy decision schema
- approval decision schema
- audit event schema
- cost ledger schema
- connector / environment / session schema

要求：

- 增加版本字段
- 支持 migration
- 支持持久化与 API/GUI/CLI 复用

### 5. 状态机与失败分类

实现 Run / Task / Attempt / Verifier 的状态机，并定义失败分类：

- `transient_tool_failure`
- `permanent_policy_failure`
- `ownership_conflict`
- `budget_exhausted`
- `approval_denied`
- `verification_failed`
- `network_restricted`
- `unsupported_capability`
- `human_intervention_required`

要求：

- 状态迁移可追踪
- 失败分类能驱动 retry / escalate / downgrade / human takeover

### 6. 模型路由、预算、升级与降级闭环

升级 model router，新增：

- budget policy
- quota policy
- escalation policy
- downgrade policy
- fallback chain
- route explanation
- audit trace

要求：

- 路由必须综合复杂度、风险、任务类型、失败历史、token 预算、组织策略、敏感度、SLO
- 不允许静态 `model_tier` 绕过动态策略
- 支持 planner / worker / review / summary 分阶段选模

### 7. verifier swarm 升级为 gate system

至少实现以下 gate：

- test gate
- lint / type gate
- review gate
- security gate
- perf gate
- coverage gate
- policy gate
- documentation gate
- release readiness gate

要求：

- gate 结论可阻断流程
- 支持 task-level / run-level / PR-level
- 支持 incremental review 与 full review
- review 输出必须结构化：summary、findings、risk、required actions、suggested patches

### 8. PR / CI provider-native integration

至少完成一条 provider-native 主路径，优先 GitHub：

- PR review adapter
- checks/status adapter
- issue-to-run / PR-to-run mapping
- CI failure ingest
- autofix branch strategy
- stacked PR strategy
- incremental push re-review
- PR summary renderer
- walkthrough / evidence renderer

要求：

- 参考 GitHub Copilot coding agent 的 PR-first workflow
- 参考 CodeRabbit 的 incremental/full review、summary placeholder、path-based instructions、review controls
- 能在 PR 界面直接触发、查看、控制

### 9. session persistence + event bus + audit trail

实现持久化与审计：

- session store
- run store
- task attempt store
- verifier evidence store
- event bus abstraction
- audit exporter
- replay / resume loader

要求：

- 至少有本地持久化适配器
- 所有关键动作都要落审计事件
- 支持 timeline、history、failure forensics

### 10. governance / RBAC / approvals / HITL

实现治理平面：

- actor identity
- org / project / repo / environment scope
- RBAC
- approval workflow
- emergency override
- human takeover
- sensitive action confirmation

要求：

- 明确谁可以创建 run、批准升级、允许敏感写入、触发 autofix push、忽略 gate
- approval 必须绑定具体动作
- 人工反馈必须写回 session / run history

### 11. GUI / control-plane

新增或补齐最小可操作控制面：

- run list
- run detail timeline
- task graph
- worker panel
- gate panel
- cost panel
- policy / approval panel
- artifacts panel
- config diagnostics

要求：

- 支持 retry、resume、cancel、approve、reject、reroute 等操作
- 不做静态演示，要能服务真实调试与运维

### 12. capabilities / skills / hooks / scoped instructions

建立可扩展资产层：

- capability registry
- skill manifests
- hook lifecycle
- policy-aware tool adapters
- instruction packs
- path / repo / language scoped rules

要求：

- 每个 capability 必须声明输入、输出、权限、依赖、推荐模型 tier、适用阶段
- 支持 repo-level 和 org-level 继承
- 支持 path-based review / coding instructions

### 13. 商业化准备

补齐：

- build / dist
- package validation
- semver
- migration scripts
- compatibility matrix
- release notes template
- marketplace readiness checklist
- operator runbook
- incident / rollback playbook
- support docs

要求：

- 至少完成一个可验证 dist 产物链路
- 插件元数据、入口、依赖、安装说明、升级说明完整

### 14. 商业级测试体系

必须实现：

- schema tests
- orchestrator integration tests
- worker runtime tests
- scheduler / ownership conflict tests
- retry / escalation / downgrade tests
- gate tests
- persistence / replay tests
- PR adapter tests
- policy / approval tests
- GUI smoke tests
- packaging tests

要求：

- 覆盖 happy path 与关键 failure path
- 输出覆盖说明与剩余风险

### 15. 文档与交付资料

必须补齐：

- README / README.zh
- architecture
- operator guide
- admin guide
- policy guide
- integration guide
- troubleshooting
- FAQ
- security / compliance notes
- examples / demo flows
- release checklist

要求：

- 说明与 `spec-autopilot` 的边界
- 提供典型流程示例：需求拆图、并行执行、PR review、CI autofix、coverage gate、人工审批

执行约束：

1. 不要只分析，直接落代码。
2. 不要另建平行实现，必须基于当前 `plugins/parallel-harness` 演进。
3. 每完成一批模块，同步补测试、文档、配置示例。
4. 不要把关键能力留成 TODO 或空壳。
5. 如果某一外部集成无法完全接通，必须提供稳定接口、契约测试和明确阻塞说明。
6. 以商业化可用为标准，而不是以“已有 50 个测试通过”为标准。

最终输出必须包含：

1. 现状审计结果
2. 已实现的代码
3. 新增和修改的文件列表
4. 测试执行结果
5. 尚未完成项和阻塞项
6. 商业化 readiness 评估
```
