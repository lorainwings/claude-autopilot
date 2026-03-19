# 竞品能力复用与反向改进矩阵

> 日期：2026-03-19
> 目标：把开源竞品中可借鉴的能力拆成可直接落地的模块、实施顺序和反向改进点。
> 适用范围：`spec-autopilot` 的有限修复参考，以及新插件 `parallel-harness` 的核心能力建设。

## 1. 文档目的

这份文档不做“泛泛的竞品分析”，而是回答四个具体问题：

1. 哪些竞品能力可以直接复用到你的插件体系里。
2. 这些能力应该落到当前插件，还是新插件。
3. 竞品本身有哪些明显缺点，不能直接照搬。
4. 如何把这些能力改造成你自己的产品优势。

## 2. 竞品复用总原则

### 2.1 不照搬整套产品，按能力模块复用

每个竞品都有其上下文：

- 有的偏 workflow pack
- 有的偏命令集合
- 有的偏工程方法论
- 有的偏 agent orchestration
- 有的偏 CI/PR 集成

因此必须拆成能力单元，而不是整库模仿。

### 2.2 复用对象优先级

优先复用以下几类对象：

- 配置结构
- 能力分层
- 调度模式
- 验证模式
- 开发者交互模式

谨慎复用以下内容：

- 具体 prompt
- 强绑定文件组织
- 未被验证的默认策略

### 2.3 落地分层

竞品能力落地时分三层：

1. `spec-autopilot` 可吸收的修复型能力
2. `parallel-harness` 应承接的平台型能力
3. 插件市场层需要统一的发布与产品矩阵能力

## 3. 竞品拆解矩阵

## 3.1 `obra/superpowers`

来源：

- https://github.com/obra/superpowers

可复用能力：

- methodology-as-code 思路
- 工作流能力的显式模块化
- 轻量交互命令体验
- 把复杂方法论封装成低摩擦入口

适合落地位置：

- `spec-autopilot`
  - 吸收轻量命令体验
  - 吸收方法封装方式
- `parallel-harness`
  - 吸收能力编排方式

不要直接照搬的点：

- 过度依赖说明型能力而不是强约束运行时
- 容易形成“能力很多，但工程治理不够硬”的问题

反向增强建议：

- 在你的插件里，所有 `superpower-like` 能力都必须绑定可验证契约
- 每个便捷命令都要明确输入输出 schema
- 所有流程增强都要能被 metrics 与日志追踪

可执行落地：

- 在 `parallel-harness` 中建立 `capabilities/` 清单
- 每个 capability 包含：
  - `name`
  - `intent`
  - `required_context`
  - `worker_policy`
  - `verifier_policy`

## 3.2 `claude-code-switch`

来源：

- https://github.com/foreveryh/claude-code-switch

可复用能力：

- 模型切换显式化
- 不同任务使用不同模型成本档位
- 开发者主动控制模型选择

适合落地位置：

- `parallel-harness`
  - 作为平台一级能力

不要直接照搬的点：

- 仅有人工切换还不够
- 若缺少任务复杂度与质量反馈，模型切换只会变成手工操作负担

反向增强建议：

- 在新插件里做自动模型路由，而不是只做手工切换
- 模型路由要接入：
  - 任务复杂度
  - token 预算
  - 失败次数
  - 质量风险等级

可执行落地：

- 新增 `runtime/models/model-router.ts`
- 定义：
  - `tier-1`
  - `tier-2`
  - `tier-3`
- 路由规则表：
  - search/refactor/format -> `tier-1`
  - implementation/general review -> `tier-2`
  - planning/design/critical review -> `tier-3`

## 3.3 `oh-my-claudecode`

来源：

- https://ohmyclaudecode.com/

可复用能力：

- 多 Agent 协作导向
- 工具链整合体验
- 强调多人协作式 AI 工作方式

适合落地位置：

- `parallel-harness`

不要直接照搬的点：

- 仅靠“多 agent”标签不够
- 若没有任务图和 ownership，agent 数量增加只会增加冲突和噪音

反向增强建议：

- 你的新插件必须先建图，再调度，再验证
- agent 不是自由生长，而是任务图节点执行器

可执行落地：

- 新增 `task-graph-builder`
- 新增 `ownership-planner`
- 所有 agent 必须消费结构化任务合同

## 3.4 `everything-claude-code`

来源：

- https://opencodedocs.com/zh/affaan-m/everything-claude-code/start/quickstart/
- https://lzw.me/docs/opencodedocs/affaan-m/everything-claude-code/

可复用能力：

- agents / skills / hooks / rules / MCP 的集合化
- 开箱即用的生态集成思路
- 配置和能力资产的系统收纳

适合落地位置：

- `parallel-harness`
  - 作为能力资产层
- 插件市场
  - 作为多插件矩阵设计参考

不要直接照搬的点：

- “大而全” 容易演变为认知负担
- 如果缺少清晰产品分层，资产越多越难维护

反向增强建议：

- 你的市场不追求最大而全，而是追求：
  - 清晰插件边界
  - 能力清单透明
  - 最少必要安装

可执行落地：

- 在新插件中建立：

```text
plugins/parallel-harness/skills/
plugins/parallel-harness/runtime/
plugins/parallel-harness/hooks/
plugins/parallel-harness/docs/capabilities/
```

- 每个能力单元都要求：
  - 用途说明
  - 输入输出
  - 何时启用
  - 风险与降级策略

## 3.5 `BMAD-METHOD`

来源：

- https://github.com/bmadcode/BMAD-METHOD

可复用能力：

- 方法工程化
- agent framework 化
- 工作流模板化
- 明确角色职责

适合落地位置：

- `parallel-harness`
  - 作为平台方法层

不要直接照搬的点：

- 方法论如果不接入运行时约束，会变成“文档很强，系统很弱”

反向增强建议：

- 所有方法都必须转换为可执行 contract
- 角色不只是描述，而要映射成：
  - planner
  - worker
  - verifier
  - synthesizer

可执行落地：

- 新插件定义四类一等角色：
  - `planner`
  - `worker`
  - `verifier`
  - `synthesizer`

- 为每类角色定义标准接口：
  - 输入格式
  - 输出格式
  - 失败语义
  - 可访问资源边界

## 3.6 `claude-task-master`

来源：

- https://github.com/eyaltoledano/claude-task-master

可复用能力：

- PRD 到任务分解
- 任务复杂度管理
- 任务状态生命周期
- 任务依赖意识

适合落地位置：

- `parallel-harness`

不要直接照搬的点：

- 任务系统如果只管拆，不管 ownership 和 verifier，会导致执行层失控

反向增强建议：

- 任务系统与所有权、模型路由、验证系统必须联动

可执行落地：

- 任务节点字段标准化：
  - `id`
  - `title`
  - `goal`
  - `dependencies`
  - `risk_level`
  - `allowed_paths`
  - `required_tests`
  - `model_tier`
  - `verifier_set`

## 3.7 `get-shit-done`

来源：

- https://github.com/glittercowboy/get-shit-done

可复用能力：

- context engineering 导向
- 更贴近实际交付的任务推进感
- 强调减少多余上下文和行动摩擦

适合落地位置：

- `parallel-harness`
  - 上下文包系统
- `spec-autopilot`
  - 轻量改进交互和最小上下文策略

不要直接照搬的点：

- 如果过于追求“快”，容易牺牲质量和治理

反向增强建议：

- 用它的“低摩擦”思路，但加上 verifier 和 metrics

可执行落地：

- 新插件实现 `context-packager`
- 规则：
  - 默认不喂全仓
  - 默认不喂无关历史
  - 上下文大小超预算自动摘要

## 3.8 Harness AI Agents

来源：

- https://developer.harness.io/docs/code-repository/pull-requests/ai-agents/

可复用能力：

- 把 AI 能力嵌入 PR/CI 流程
- review / autofix / coverage 等能力闭环
- AI 不只是写代码，而是参与软件交付治理

适合落地位置：

- `parallel-harness`
  - 平台集成层

不要直接照搬的点：

- 不能只做 PR review 表层集成
- 如果没有任务图和执行历史，CI 自愈会失真

反向增强建议：

- 你的 CI/PR 集成必须能读取：
  - 任务图
  - worker 输出
  - verifier 报告
  - 风险摘要

可执行落地：

- 新增：
  - `pr-review-agent`
  - `ci-failure-analyzer`
  - `autofix-dispatch`
  - `coverage-gap-agent`

## 4. 竞品能力复用到你体系的映射表

| 能力 | 主要来源 | 落地插件 | 具体模块 |
|---|---|---|---|
| 方法工程化 | superpowers, BMAD | 两者 | capabilities, role contracts |
| 自动模型路由 | claude-code-switch | `parallel-harness` | `runtime/models/` |
| 多 Agent 协作 | oh-my-claudecode | `parallel-harness` | scheduler, dispatch |
| 资产化能力集 | everything-claude-code | `parallel-harness` | skills, hooks, capability docs |
| 任务分解与依赖 | claude-task-master | `parallel-harness` | task graph |
| 最小上下文包 | get-shit-done | 两者 | context packager |
| PR/CI 闭环 | Harness | `parallel-harness` | ci/pr integration |
| 轻量命令体验 | superpowers | `spec-autopilot` | command UX |

## 5. `spec-autopilot` 应直接吸收的能力

当前插件不应该吸收平台化大能力，但可以直接吸收以下能力：

### 5.1 轻量命令与能力清单

来自：

- `superpowers`

落地：

- 在 `docs/` 中新增能力清单
- 把高频操作抽成清晰命令入口

### 5.2 最小上下文包

来自：

- `get-shit-done`

落地：

- 优化现有阶段输入摘要
- 限制非必要 transcript 注入
- 缩减阶段切换时的上下文噪音

### 5.3 更严格的验证指标

来自：

- Harness

落地：

- 增强 phase 报告结构
- 引入更清晰的 QA / coverage / review 证据

## 6. `parallel-harness` 必须吸收的能力

### 6.1 必做能力

- 任务图
- ownership enforcement
- model router
- verifier swarm
- context packager
- CI/PR integration

### 6.2 可延后能力

- 高级 GUI
- 自动推荐插件组合
- 复杂 MCP 生态整合

## 7. 竞品缺点与反向设计

你不能只“学习优点”，还必须“系统性避开他们的短板”。

### 缺点一：只会堆能力，不做约束

常见于：

- 大型能力合集

你的反向设计：

- 每个能力都必须有 contract
- 每个能力都要有降级策略

### 缺点二：只会多 Agent，不会防冲突

常见于：

- 多 agent orchestration 类项目

你的反向设计：

- ownership 先于 dispatch
- merge guard 先于结果合并

### 缺点三：只会切模型，不会做路由闭环

常见于：

- 模型切换工具

你的反向设计：

- 任务复杂度 + 成本预算 + 失败升级联动

### 缺点四：只会做方法，不会做工程

常见于：

- 方法论型项目

你的反向设计：

- 方法必须映射到 runtime 接口和测试用例

### 缺点五：只会做 PR review，不会接执行历史

常见于：

- 部分 CI/PR agent 集成

你的反向设计：

- PR/CI agent 必须接入 task graph 与 verifier 报告

## 8. 可执行实施顺序

建议按以下顺序复用，而不是同时开太多线。

### Sprint 1

- 任务图模型
- ownership 规则
- 最小上下文包

### Sprint 2

- scheduler
- worker dispatch
- merge guard

### Sprint 3

- verifier swarm
- model router
- retry / downgrade

### Sprint 4

- PR/CI integration
- quality reports
- 市场文档完善

## 9. 最终结论

你的优势不应该是“把最多竞品塞进一个仓库”，而应该是：

- 把竞品里真正有效的能力拆出来
- 放到正确的插件边界里
- 用更强的工程约束把它们变成可长期维护的产品

因此最终策略应是：

- `spec-autopilot` 吸收少量低风险、提升体验的能力
- `parallel-harness` 承接并行调度、模型路由、验证 swarm、CI/PR 闭环
- 插件市场负责统一发布，而不是让单个插件无限膨胀
