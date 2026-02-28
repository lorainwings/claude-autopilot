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
