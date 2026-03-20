# Claude 执行提示词文档

> 日期：2026-03-19
> 状态：已废弃
> 说明：本文件原本尝试在一个文档中合并两份提示词，但不满足“每份提示词必须是独立完整上下文”的要求，因此废弃。

## 请改用以下独立文档

- [spec-autopilot 完整执行提示词](docs/plans/2026-03-19-spec-autopilot-execution-prompt.zh.md)
- [parallel-harness 完整执行提示词](docs/plans/2026-03-19-parallel-harness-execution-prompt.zh.md)
- [spec-autopilot 模型路由增强执行提示词](docs/plans/2026-03-19-spec-autopilot-model-routing-enhancement-prompt.zh.md)

## 为什么废弃

旧版存在两个问题：

1. 两份提示词被放在同一个文档里，不便于直接分发给不同的 Claude 实例。
2. 内容不够完整，不能满足“单份文档即可独立提供完整上下文、实施步骤和验收标准”的要求。
3. 后续针对 `spec-autopilot` 的模型路由增强，需要独立补充提示词，避免和稳定性/结构治理提示词混写。

现在已经拆分为多份独立文档，分别覆盖：

- `spec-autopilot` 的稳定性/结构治理执行
- `parallel-harness` 的新插件建设
- `spec-autopilot` 的模型路由增强迭代

这些文档都包含：

- 完整背景上下文
- 产品边界
- 已知问题与目标
- 实施步骤
- 验收标准
- 最终可复制提示词
