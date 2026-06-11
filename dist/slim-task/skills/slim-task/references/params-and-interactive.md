# 参数校验值域 + --interactive 逐阶段详表

> 本文件是 Phase 0 参数合法值域、`--interactive` 模式逐阶段检查点的**查阅表**（原始材料）。参数解析与 interactive 触发的流程指令见 SKILL.md Phase 0 与「检查点标准协议」，不在此重复。

## Contents

- [参数校验值域](#参数校验值域)
- [--interactive 逐阶段详表](#--interactive-逐阶段详表)

## 参数校验值域

Phase 0 参数解析后逐项校验，非法值经 `AskUserQuestion` 让用户重选或回退默认：

| 参数 | 合法值域 | 默认 | 非法处理 |
|------|---------|------|---------|
| `--lang` | `zh-CN` / `en-US` / 其他 BCP-47 标签 | `zh-CN` | 提示支持列表，让用户重选 |
| `--worktree` | flag（无值） | 关闭 | 若带值（`--worktree=x`）→ 提示是 flag，忽略值 |
| `--base` | 匹配 `^[A-Za-z][\w./-]*$` 的分支名 | 当前 HEAD | 非法分支名 → 提示重输或用 HEAD |
| `--interactive` | flag（无值） | 关闭 | 若带值 → 提示是 flag，忽略值 |

## --interactive 逐阶段详表

默认模式下 Phase 0/3/4/5 为自动 transition；`--interactive` 开启后，这些点降级为审批 gate，每个 Phase 末尾追加标准检查点。各阶段检查点形态：

| Phase | 默认行为 | --interactive 追加的检查点 | 决策卡选项 |
|-------|---------|---------------------------|-----------|
| 0 | 自动 → Phase 1 | 配置确认卡 | 采纳配置 → Phase 1 / 修改配置 / 终止 |
| 1 | **审批 gate（始终）** | 不变（本就是 gate） | 采纳需求 → Phase 2 / 补充澄清 / 终止 |
| 2 | **审批 gate（始终）** | 不变（本就是 gate） | 批准方案+DAG → 执行段 / 修改 / 终止 |
| 3 | 自动 → Phase 4 | 文档确认卡 | 采纳文档 → Phase 4 / 修改文档 / 终止 |
| 4 | 自动 → Phase 5 | 执行结果确认卡 | 进入 Phase 5 审计 / 回退修复 / 终止 |
| 5 | 全 pass 自动 → Phase 6 | 审计结果确认卡 | 批准 → Phase 6 / 派修复 Agent / 终止 |
| 6 | **双决策卡（始终）** | 不变（本就是双卡） | commit 卡 + push/PR 卡 |

> Phase 1/2/6 是三处关键人工边界，无论 `--interactive` 与否都执行；`--interactive` 只影响 Phase 0/3/4/5 这四个自动 transition 点是否额外询问用户。质量约束（三维盲审、影响范围、修复上限）不受该开关影响。
