# Phase 1: 需求理解与多轮决策 — 详细流程

> 本文件由 autopilot SKILL.md 引用，执行 Phase 1 时按需读取。

**核心原则**: 绝不假设，始终列出选项由用户决策。

## 1.1 获取需求来源

- `$ARGUMENTS` 为文件路径 → 读取文件内容
- `$ARGUMENTS` 为文本 → 直接作为需求描述
- `$ARGUMENTS` 为空 → AskUserQuestion 要求输入

## 1.2 需求分析

调用 Task(subagent_type = config.phases.requirements.agent) 分析需求，产出:
- 功能清单
- 疑问点列表（每个疑问必须转化为决策点）
- 技术可行性初判

> **返回值校验**: 主线程必须检查 business-analyst 子 Agent 返回非空，且包含功能清单和疑问点。如果返回为空或格式异常，应重新 dispatch 并在 prompt 中明确要求结构化输出。此 Task 不含 autopilot-phase 标记（设计预期），因此不受 Hook 门禁校验。

## 1.3 多轮决策循环（LOOP）

**循环条件**: 存在任何未澄清的决策点

每轮循环:
1. 梳理当前所有未决策点
2. 将每个决策点转化为 AskUserQuestion（2-4 个选项，推荐方案标 Recommended）
3. 收集用户决策结果
4. 检查是否产生新的决策点
5. 重复直到**所有点全部澄清**

## 1.4 生成结构化提示词

整理所有决策结果，包含: 背景与目标、功能清单、决策结论、技术约束、验收标准。

## 1.5 最终确认

展示完整提示词，AskUserQuestion:
"以上需求理解是否准确？如有遗漏请补充。"
选项: "确认，开始实施 (Recommended)" / "需要补充修改"
- 选"补充" → 回到 1.3 循环

## 1.6 写入 Phase 1 Checkpoint

需求确认后，调用 Skill(`spec-autopilot:autopilot-checkpoint`) 写入 `phase-1-requirements.json`：

```json
{
  "status": "ok",
  "summary": "需求分析完成，共 N 个功能点，M 个决策已确认",
  "artifacts": ["openspec/changes/<name>/context/prd.md", "openspec/changes/<name>/context/discussion.md"],
  "requirements_summary": "功能概要...",
  "decisions": [{"point": "决策点描述", "choice": "用户选择"}],
  "change_name": "<推导出的 kebab-case 名称>"
}
```

> 此 checkpoint 使崩溃恢复能跳过 Phase 1，直接从 Phase 2 继续。

## 1.7 可配置用户确认点

如果 `config.gates.user_confirmation.after_phase_1 === true`（默认 true）：
- AskUserQuestion：「需求分析已完成，是否确认进入 OpenSpec 创建阶段？」
- 选项: "继续 (Recommended)" / "暂停，我需要再想想"
- 选"暂停" → 结束当前流水线，用户可后续通过崩溃恢复继续

---

## 苏格拉底模式协议

> 当 `config.phases.requirements.mode` 设为 `"socratic"` 时激活（默认 `"structured"`）。

苏格拉底模式通过挑战性提问深化需求理解，适用于需求模糊或创新性项目。

### 6 步提问流程

| 步骤 | 目的 | 示例提问 |
|------|------|---------|
| 1. 挑战假设 | 质疑用户隐含的前提条件 | "你提到需要实时同步，是否考虑过最终一致性就能满足需求？" |
| 2. 探索替代方案 | 寻找用户未考虑的解决路径 | "除了新增 API 端点，是否可以通过扩展现有端点的参数来实现？" |
| 3. 识别隐含需求 | 挖掘用户未明确表达的需求 | "你提到了创建功能，但是否还需要批量导入？删除时是否需要软删除？" |
| 4. 强制排优 | 当功能过多时迫使用户取舍 | "这 5 个功能中，如果只能在第一个版本实现 3 个，你会选择哪些？" |
| 5. 魔鬼代言人 | 从反对角度审视需求 | "如果竞品已经有这个功能，我们的差异化价值在哪里？" |
| 6. 最小可行范围 | 收敛到最小可交付范围 | "基于以上讨论，最小可行版本是否可以只包含 X 和 Y？" |

### 集成方式

在 Phase 1.3 多轮决策循环中，每轮除了处理用户疑问外，额外执行苏格拉底提问：

```
IF config.phases.requirements.mode == "socratic":
    FOR EACH undecided_point:
        1. 标准处理：AskUserQuestion 展示选项
        2. 苏格拉底追问：从 6 步中选择最相关的 1-2 步提问
        3. 根据用户回答，可能产生新的决策点（回到循环开头）
```

### 退出条件

- 所有决策点已澄清 **且** 苏格拉底提问未产生新决策点
- 用户明确表示"需求已经足够清晰，不需要更多提问"
