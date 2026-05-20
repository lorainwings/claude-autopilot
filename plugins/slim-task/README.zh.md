[English](README.md)

# slim-task

> 结构化 7 阶段 AI 任务执行 SOP，支持多语言与 worktree 并行

**版本**: 0.3.0 <!-- x-release-please-version -->

## 概述

slim-task 是一个纯 Skill 型 Claude Code 插件，提供结构化的标准操作流程（SOP）来执行 AI 编码任务。它解决了 AI 执行任务时的 8 个常见问题：

1. 未进行需求澄清就开始执行
2. 方案设计阶段未调研业界最佳实践
3. 修复 BUG 时修改到无关代码
4. 代码改动未经用户审批就开始执行
5. 方案未固化到项目文档
6. 代码未经审批就直接提交推送
7. 任务执行太慢，未使用并行子 Agent
8. AI 自审作弊——写代码的 Agent 给自己打分

## 架构

- **主检子执**: 主 Agent 只做检查/决策/派发/验证，子 Agent 负责实际编码
- **DAG 并行**: 任务按依赖关系构建有向无环图，同层任务全部并行派发，无数量上限
- **影响范围锁定**: 强制输出文件级影响范围表，防止修改无关代码
- **Phase 5 盲审**: 质量检查派发独立 auditor 子 Agent 在隔离 context 内执行——写实现的 Agent 永远不评自己的代码
- **多语言支持**: AI 对话、决策卡、生成文档、子 Agent prompt 全部按配置语言输出（默认 `zh-CN`）；Conventional Commits 前缀保持英文
- **Worktree 隔离**: 可选 `--worktree` 模式将整个流水线运行在独立 git worktree 内，实现真正的多任务并行（无 staging 冲突）
- **7 个用户检查点**: 每个阶段转换都需要用户明确确认

## 7 阶段 SOP

| 阶段 | 名称 | 描述 |
|------|------|------|
| 0 | 会话初始化 | 解析 `--lang` / `--worktree` / `--base`；持久化语言偏好；可选进入独立 worktree |
| 1 | 需求澄清 | 解析输入、识别歧义、结构化问答 |
| 2 | 方案设计 | 最佳实践调研 + 代码扫描 + 影响范围 |
| 3 | 文档固化 + DAG 拆分 | 保存任务文档（带 `.{lang}.md` 后缀）+ 构建依赖 DAG |
| 4 | 最大化并行执行 | 按 DAG 拓扑序逐层派发子 Agent |
| 5 | 质量检查（盲审） | 三个独立审计子 Agent（scope / practice / engineering）在不知实现过程的情况下审 diff |
| 6 | 提交确认 | Worktree 模式黑名单文件检查、展示变更、确认 commit/push、可选 `ExitWorktree(keep)` |

## 安装

```bash
claude install lorainwings/claude-autopilot --plugin slim-task
```

## 使用

```
/slim-task [任务描述] [--lang zh-CN|en-US|...] [--worktree] [--base <分支>]
```

示例：

```
# 默认（中文，不启用 worktree，向后兼容）
/slim-task 修复 middleware 中 auth header 的 bug

# 英文输出 + 基于当前分支创建独立 worktree
/slim-task --lang en-US --worktree add health check endpoint

# 英文输出 + 基于 origin/main 创建 worktree
/slim-task --lang en-US --worktree --base origin/main refactor logger
```

也可使用自然语言触发："结构化任务"、"SOP 执行"、"拆分任务并行执行"。

### 配置

首次传入 `--lang` 后，该值会被持久化到 `.claude/slim-task.json` 作为默认偏好；后续调用无需重复传参。

### Worktree 注意事项

- Worktree 模式**默认关闭**，需显式 `--worktree` 开启。
- 整个 7 阶段流水线在 worktree 内执行。
- worktree 内的 commit **永不会被自动合并或 push 到 `main`**——slim-task 在 Phase 6 给出 `git merge` 命令，由用户人工合并。
- worktree 模式禁止 commit `release-please-config.json` / `.release-please-manifest.json` / `marketplace.json`（monorepo 共享状态）。

## 许可证

MIT
