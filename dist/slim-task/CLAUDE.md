# slim-task Plugin CLAUDE.md

> 此文件为 slim-task 插件的工程法则。
> 所有 AI Agent 在执行期间必须遵守。
> 版本: 0.7.0 <!-- x-release-please-version -->

## 插件定位

纯 Skill 型插件，无 TypeScript runtime、无 hooks。
提供 7 阶段结构化 SOP（Phase 0-6），采用主检子执模式 + DAG 最大化并行 + Phase 5 独立审计盲审，解决 AI 任务执行的 8 个常见问题。

## 核心约束

1. **主检子执**: 主 Agent 只做检查/决策/派发/验证，子 Agent 做实际编码与质量审计
2. **影响范围即合约**: 禁止修改 Phase 2 审批的影响范围表之外的文件
3. **DAG 无上限并行**: 同层无依赖任务全部并行派发，不限数量
4. **阶段门控**: 每个阶段转换必须有用户检查点
5. **提交须授权**: commit/push 必须通过 AskUserQuestion 获得用户明确确认
6. **语言一致性**: AI 对话、决策卡、生成文档、子 Agent prompt 按 `${LANG}` 配置输出（默认 `zh-CN`），Conventional Commits 前缀保持英文
7. **Worktree 隔离可选**: 可通过 `--worktree` 开启独立 worktree 执行，禁止 auto-merge 回 main
8. **Phase 5 盲审反作弊**: 质量检查由独立 auditor 子 Agent 在隔离 context 内执行，禁止注入实现 Agent 的过程信息

## 触发方式

- Skill 触发词: `/slim-task [task] [--lang ...] [--worktree] [--base ...]`
- 自然语言: "结构化任务"、"SOP 执行"、"拆分任务并行执行"

## 完全独立

本插件不依赖 spec-autopilot、parallel-harness 或任何其他插件的基础设施。

