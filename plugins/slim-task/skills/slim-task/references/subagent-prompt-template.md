# 子 Agent Prompt 模板

Phase 4 派发实现 Agent 时，每个子 Agent 的 prompt 必须包含以下结构化字段：

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

## Output
完成后汇报：修改了哪些文件、做了什么变更、是否有遗留问题。
```

## 使用说明

- `{子任务目标}`：从 DAG 节点的 Objective 字段填入
- `{文件列表}`：从 DAG 节点的 File boundary 字段填入，必须是影响范围表的子集
- `${LANG}`：从 Phase 0 初始化的语言配置填入
- 使用 `Agent` 工具，设置 `run_in_background: true` 并行派发
