# Claude 执行提示词文档

> 日期：2026-03-19
> 状态：已废弃
> 说明：本文件原本尝试在一个文档中合并两份提示词，但不满足“每份提示词必须是独立完整上下文”的要求，因此废弃。

## 请改用以下两份独立文档

- [spec-autopilot 完整执行提示词](/Users/lorain/Coding/Huihao/claude-autopilot/docs/plans/2026-03-19-spec-autopilot-execution-prompt.zh.md)
- [parallel-harness 完整执行提示词](/Users/lorain/Coding/Huihao/claude-autopilot/docs/plans/2026-03-19-parallel-harness-execution-prompt.zh.md)

## 为什么废弃

旧版存在两个问题：

1. 两份提示词被放在同一个文档里，不便于直接分发给不同的 Claude 实例。
2. 内容不够完整，不能满足“单份文档即可独立提供完整上下文、实施步骤和验收标准”的要求。

现在已经拆分为两份完整文档，每份都包含：

- 完整背景上下文
- 产品边界
- 已知问题与目标
- 实施步骤
- 验收标准
- 最终可复制提示词
