---
name: autopilot-agents
description: "Discover, install and configure AI agents for autopilot phases from community sources (OMC, Anthropic official, VoltAgent, etc.). Supports install/list/swap/recommend/sources modes."
argument-hint: "[install | list | swap <phase> <agent> | recommend | sources]"
---

# Autopilot Agents — Agent 发现/安装/热交换

从社区来源（≥1000 stars）发现、安装和配置各阶段的专业 AI Agent。

## 操作模式

根据 `$ARGUMENTS` 选择模式：

| 模式 | 触发参数 | 用途 | 详细协议 |
|------|---------|------|----------|
| recommend（默认）| 空 / `recommend` | 输出 agent 推荐清单（含域级 Agent 推荐） | `references/recommend-mode.md` |
| sources | `sources` | 列出可选 agent 社区来源（≥1000 ★） | `references/sources-catalog.md` |
| install | `install` | 安装所选 Phase/域 agent + 工具权限适配 | `references/install-mode.md` |
| swap | `swap <phase\|domain/> <agent>` | 热交换单个 Phase 或域级 Agent | `references/swap-mode.md` |
| list | `list` | 列出当前 Phase-Agent 与域 Agent 映射 | `references/list-mode.md` |

执行任一模式前，**必须先读取对应的 references 文件**获取完整 Step 协议，不得依据本表简述直接操作。

## Agent 优先级链（运行时解析）

```
1. AUTOPILOT_PHASE{N}_AGENT 环境变量    ← 最高，单次实验用
2. config phases.{phase}.agent 字段     ← 持久配置
3. .claude/agents/{name}.md 定义        ← Agent 行为定义
4. 内置 general-purpose                 ← 兜底
```

## 适配说明

OMC `analyst` / `planner` 等来源 agent 与 autopilot Phase 的工具权限适配规则，详见 `references/omc-adaptation.md`。

## references 索引

- `references/recommend-mode.md` — Phase 级 + 域级推荐映射表、备选 Agent、来源评分
- `references/sources-catalog.md` — 8 个社区 Agent 市场列表与安装命令
- `references/install-mode.md` — Step 1–5 + 域级 Agent 安装完整协议（含工具权限适配）
- `references/swap-mode.md` — Phase swap + 域 swap 步骤、Phase → config key 映射
- `references/list-mode.md` — 当前 Phase/域 Agent 映射展示协议
- `references/omc-adaptation.md` — OMC `analyst` / `planner` 适配细则
