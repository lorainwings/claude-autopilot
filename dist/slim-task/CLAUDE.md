# slim-task Plugin CLAUDE.md

> 此文件为 slim-task 插件的工程法则。
> 所有 AI Agent 在执行期间必须遵守。
> 版本: 0.1.0 <!-- x-release-please-version -->

## 插件定位

纯 Skill 型插件，无 TypeScript runtime、无 hooks。
提供 6 阶段结构化 SOP，采用主检子执模式 + DAG 最大化并行，解决 AI 任务执行的 7 个常见问题。

## 核心约束

1. **主检子执**: 主 Agent 只做检查/决策/派发/验证，子 Agent 做实际编码
2. **影响范围即合约**: 禁止修改 Phase 2 审批的影响范围表之外的文件
3. **DAG 无上限并行**: 同层无依赖任务全部并行派发，不限数量
4. **阶段门控**: 每个阶段转换必须有用户检查点
5. **提交须授权**: commit/push 必须通过 AskUserQuestion 获得用户明确确认

## 触发方式

- Skill 触发词: `/slim-task`
- 自然语言: "结构化任务"、"SOP 执行"、"拆分任务并行执行"

## 完全独立

本插件不依赖 spec-autopilot、parallel-harness 或任何其他插件的基础设施。

