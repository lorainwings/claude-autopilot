# 审计 Diff 消毒（盲审隔离原始材料）

> 本文件是注入审计 Agent 的 diff **生成命令与禁止项清单**（原始材料）。盲审隔离的流程约束见 SKILL.md「隔离硬约束」，不在此重复。

## 消毒命令

```bash
git diff --unified=0 --no-ext-diff --ignore-all-space -- <影响范围内文件列表>
```

| 选项 | 作用 | 隔离意义 |
|------|------|---------|
| `--unified=0` | 不输出上下文行，仅改动行 | 防上下文暴露周边代码评审历史/实现思路 |
| `--no-ext-diff` | 禁用外部 diff 工具 | 防自定义 diff 驱动泄漏额外信息 |
| `--ignore-all-space` | 忽略空白差异 | 聚焦语义改动，降噪 |
| `-- <文件列表>` | 限定影响范围内文件 | 防范围外文件痕迹进入审计视野 |

## 禁止注入审计 Agent 的信息类型

构造 auditor prompt 时逐项核对，命中任一即视为破坏盲审隔离（对应 Red Flags）：

1. Phase 4 实现 Agent 的对话历史 / 思考记录 / 自评结论
2. 本地 debug / temp 文件、编译产物、`.log`
3. commit message、文件 rename 历史（`git log` / `--follow` 输出）
4. 未消毒的 diff（带 `--unified=N>0` 上下文）

## prompt 参数白名单/黑名单

| 类型 | 内容 |
|------|------|
| ✅ 白名单 | 任务描述（Phase 1 摘要）、影响范围表（Phase 2 审批版）、清洁 diff、项目规范引用路径 |
| ⛔ 黑名单 | 实现 Agent ID、实现 prompt 全文、实现对话片段、实现 Agent 的 modified_files 自评理由 |

三维 auditor 的 prompt 必须用同一模板填充白名单字段，禁止手工字符串拼接夹带黑名单项。
