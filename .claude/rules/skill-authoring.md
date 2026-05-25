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

## 编排稳定性规范（防 AI 跳步）

> 来源：三视角深度调研（Anthropic 官方 + obra/superpowers 200k star 实证 + 学术论文）
> 详见全局记忆 `skill-authoring-best-practices.md`

### 高置信度结论（三方一致）

| # | 规范点 | 适用场景 |
|---|--------|----------|
| 1 | SKILL.md ≤ 500 行（编排器 ≤ 250 行）；关键约束放首尾 | 所有 SKILL |
| 2 | Checklist + 编号步骤 + Exit condition 三件套 | 多阶段流程 |
| 3 | `<HARD-GATE>` XML 标签钉死关键转换 | Phase 边界 / 工具调用前 / 状态转换点 |
| 4 | Rationalizations 反模式表（合理化说辞 → 为何错误 → 正确做法） | 易跳步的强约束 SKILL |
| 5 | Red Flags STOP 清单 | 关键决策点 |
| 6 | 状态码枚举（0/1/2）替代自然语言 | Phase 状态、子 Agent 返回值 |
| 7 | 子 Agent prompt 外置为 `references/<phase>-agent-prompt.md` | 派发子 Agent 场景 |
| 8 | 慎用 ALL CAPS，优先 why 叙事 | 全局 |
| 9 | 末尾 3-5 行重申循环终止条件（非大段重复 SOP） | 多阶段编排 |
| 10 | 多 SKILL Pipeline 串联点必须有用户确认 + hard-gate | 跨 SKILL 编排 |

### 反模式（禁止）

- ❌ **自动串联**：SKILL 末尾写 `REQUIRED SUB-SKILL: next-skill`，AI 自动跳转跳过约束（实证：obra/superpowers issue #1576）
- ❌ **大段重复 SOP**：在末尾把整个 Phase 协议重复一遍，加重 Lost in Middle 稀释
- ❌ **流程指令拆到 references**：流程类指令必须就近放主 SKILL，仅"原始材料"（schema、模板、平台映射表）可外置
- ❌ **过度 ALL CAPS / MUST**：4.6+ 字面遵循易过触发（官方 skill-creator 标记为 yellow flag）

### `<HARD-GATE>` 标准模板

```markdown
<HARD-GATE id="phase-N-entry">
BEFORE entering Phase N, you MUST:
1. Verify checkpoint-phase-{N-1}.json exists
2. Call TaskUpdate to mark Phase {N-1} completed
3. Emit event via hooks/emit-event.sh

If ANY step fails: STOP, report the issue, do NOT proceed.
</HARD-GATE>
```

### Rationalizations 反模式表标准格式

```markdown
## Rationalizations (禁止)

| 合理化说辞 | 为何错误 | 正确做法 |
|-----------|---------|---------|
| "用户没明确要求 X，跳过" | 违反 SOP 完整性 | X 是强制步骤，无论用户是否提及 |
| "这个检查点太简单，口头确认即可" | 违反工具调用约束 | 必须调用 AskUserQuestion |
```

### Red Flags STOP 清单标准格式

```markdown
<RED-FLAGS checkpoint="phase-N-start">
STOP immediately if ANY of these are true:
- [ ] checkpoint-phase-{N-1}.json does NOT exist
- [ ] Task {N-1} status is NOT "completed"
- [ ] User has NOT confirmed Phase {N-1} output

If ANY flag is raised: STOP, report the issue, wait for user fix.
</RED-FLAGS>
```
