# SKILL 撰写规范（Anthropic 官方对齐）

## 长度约束

- SKILL.md 正文 **≤ 500 行**；高频加载的编排器类 SKILL（如 `autopilot`）目标 ≤ 250 行
- references/ 单文件超过 100 行需添加 `## Contents` 目录
- 每个 SKILL 目录自洽；跨 SKILL 复用通过 `skill-name` 名称引用，禁止 `@path` 强加载

## 版本/演进信息归属铁律

- **SKILL.md 正文与 frontmatter 不得出现版本号、迭代标签、changelog 注脚**
  - 禁止样式：`自 v5.9 迁移至...`、`（Sprint 升级新增）`、`（WS-E 治理强化）`、硬编码版本对比表 `Autopilot v3.4.0`
  - 禁止理由：Anthropic 官方 best-practices 指出 SKILL 应为"时态中性"描述，版本演进应在 plugin.json / CHANGELOG.md / `## Old patterns <details>` 折叠块中呈现
- 运行时 phase 编号（`Phase 5.5`、`Phase 6.5`、`Phase 0.4`）属于协议标识，不视为版本噪音
- 历史兼容信息若必须保留，放入 SKILL 末尾的 `## Old patterns` 折叠区

## Frontmatter 要求

- `name`：仅 `[a-z0-9-]`，≤ 64 字符，不含版本号后缀
- `description`：以 "Use when..." 起句，第三人称，≤ 1024 字符，仅触发条件不概述流程

### description "Use when..." 标准示例与反例

**正确示例**（触发条件、第三人称、时态中性）：

| 场景 | description 样例 |
|------|------------------|
| 编排器入口 | `Use when user invokes /autopilot or requests end-to-end spec-driven delivery; orchestrates Phase 0-7 pipeline.` |
| 子 phase | `Use when autopilot orchestrator enters Phase 5 for implementation; executes TDD cycles per task.` |
| user-invocable 工具 | `Use when user runs /autopilot-docs-fix to scan and repair documentation drift.` |

**反面示例**（禁止）：

| 反模式 | 错误样例 | 问题 |
|--------|---------|------|
| 功能式描述 | `Generates OpenSpec documents and runs validation.` | 缺触发条件，未说明何时该被调用 |
| 身份式描述 | `I am the requirements analyzer for Phase 1.` | 第一人称，非触发条件 |
| 流程概述式 | `Reads requirement, asks clarifying questions, writes requirement-packet.json, then dispatches Phase 2.` | 把正文内容塞进 description，应放 SKILL.md 正文 |

**对比维度速查**：

| 维度 | 正确 | 错误 |
|------|------|------|
| 起句 | `Use when ...` | `Generates .../ I am .../ Handles ...` |
| 主语 | 省略或第三人称 | 第一人称（I / this skill） |
| 内容 | 触发条件 + 适用场景 | 实现细节 / 流程步骤 |
| 时态 | 中性现在时 | 夹带版本号 / "新增" / "升级" |
| 长度 | ≤ 1024 字符，单句或 2 句 | 多段落 / 含 bullet 列表 |

## references 组织

- 单一 SKILL 消费的 reference 必须放在 `skills/<skill-name>/references/`
- ≥2 个 SKILL 共享的 reference 才允许放在 `skills/autopilot/references/`（SHARED 区）
- references 引用只允许下钻一层；禁止 a.md → b.md → c.md 链式跳转
