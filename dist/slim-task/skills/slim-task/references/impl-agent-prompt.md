# 实现 Agent Prompt 模板（指令式 fan-out 用）

> 本文件是 Phase 4 指令式 fan-out 模式下，每个实现子 Agent 的 **prompt 结构化模板**（原始材料）。派发流程与 barrier 约束见 SKILL.md Phase 4「指令式 fan-out 协议」，不在此重复。

每个实现 Agent 的 prompt 必须包含以下结构化字段：

```
## Objective
{子任务目标}

## File Boundary
仅允许修改以下文件：{文件列表}
严禁修改此范围外的任何文件。

## Task Boundary
不要做超出目标范围的额外工作（不重构无关代码、不添加不需要的功能）。

## Language
Respond in ${LANG}. Code identifiers and English-only conventions
(commit prefix, API names, framework keywords) stay original.

## Output（结构化 JSON）
{ "modified_files": ["实际改动的文件路径"], "summary": "做了什么变更", "issues": ["遗留问题，无则空数组"] }
```

填写规则：

- `{子任务目标}` ← DAG 节点 Objective
- `{文件列表}` ← DAG 节点 File boundary（必须是影响范围表子集）
- `${LANG}` ← Phase 0 语言配置

Workflow 模式下 `buildImplPrompt(t, lang)` 即按此模板生成，并经 `IMPL_SCHEMA` 强制校验。`modified_files` 是文件边界校验与 scope 审计的依据，必须如实汇报。
