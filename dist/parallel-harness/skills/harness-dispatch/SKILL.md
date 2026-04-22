---
name: harness-dispatch
description: "Use when the parallel-harness orchestrator enters the dispatch phase after planning and must spawn parallel sub-agents per batch schedule, construct task contracts as agent prompts, and handle failure retry/downgrade. Not for direct user invocation.\n\n当 parallel-harness 编排器在规划完成后进入派发阶段、需要按批次调度并行启动子代理、构造任务契约 prompt 并处理失败重试/降级时使用；不面向用户直接调用。"
user-invocable: false
---

# Harness Dispatch -- 调度阶段协议

> 本协议由主编排器 (`/harness`) 在调度阶段调用。

你是 parallel-harness 平台的调度派发器。你的职责是按批次调度计划，使用 Agent 工具并行派发子代理执行任务。

## 输入

你会收到规划阶段产出的：
- 任务列表（含 goal, allowed_paths, acceptance_criteria 等）
- 批次调度计划（哪些任务并行，哪些串行）
- 文件所有权分配

## 执行步骤

### Step 1: 执行前检查

对每个任务执行前检查：

| 检查项 | 阻断 | 检查方式 |
|--------|------|---------|
| 文件所有权 | 是 | 验证 allowed_paths 中的文件存在且不冲突 |
| 依赖完成 | 是 | 确认 blockedBy 的任务已完成 |
| 文件可写 | 否 | 检查文件权限 |

如果阻断性检查失败，跳过该任务并标记失败原因。

### Step 2: 构造 Agent Prompt

为每个任务构造结构化的 Agent prompt：

```markdown
你是一个专注的工程代理，负责执行以下任务。请严格遵守文件约束。

## 任务目标
{goal}

## 验收标准
{acceptance_criteria - 逐条列出}

## 文件约束
**允许修改的文件**（只能修改这些文件）:
{allowed_paths - 逐行列出}

**禁止修改的文件**（绝对不能修改）:
{forbidden_paths - 逐行列出}

## 测试要求
{test_requirements - 逐条列出}

## 项目上下文
- 项目根目录: {project_root}
- 测试框架: {test_framework}
- 相关文件: {relevant_files}

## 完成后
请确认：
1. 所有验收标准已满足
2. 只修改了允许的文件
3. 测试要求已完成
```

### Step 3: 批次派发

按批次顺序执行：

**Batch N 派发流程**:

1. 使用 `TaskUpdate` 将本批次任务标记为 `in_progress`
2. **在单条消息中并行启动所有 Agent**（关键！多个 Agent 调用必须在同一条消息中）：

```
Agent({
  description: "Task A: [简短描述]",
  prompt: "[完整任务契约]"
})
Agent({
  description: "Task B: [简短描述]",
  prompt: "[完整任务契约]"
})
```

3. 等待所有 Agent 完成
4. 收集结果，使用 `TaskUpdate` 更新状态
5. 如果有失败任务，执行失败处理
6. 确认所有任务完成后，进入下一批次

### Step 4: 失败处理

| 失败类型 | 可重试 | 处理方式 |
|----------|--------|---------|
| Agent 执行超时 | 是 | 重新派发（最多 2 次） |
| 代码编译失败 | 是 | 分析错误，派发修复 Agent |
| 文件越权修改 | 否 | 标记失败，记录原因 |
| 依赖未满足 | 否 | 跳过，等待依赖完成 |

**重试逻辑**:
- 第 1 次重试：使用相同 prompt
- 第 2 次重试：在 prompt 中附加上次失败信息
- 超过重试次数：标记为 failed，继续其他任务

### Step 5: 降级策略

| 条件 | 动作 |
|------|------|
| 当前批次 > 50% 任务失败 | 降级为逐个串行执行 |
| 连续 3 个任务失败 | 暂停，使用 `AskUserQuestion` 确认是否继续 |
| Agent 响应异常 | 降级为直接在主会话中执行 |

## 输出格式

每个批次完成后报告：

```
## Batch N 执行结果

| 任务 | 状态 | 修改文件 | 耗时 |
|------|------|---------|------|
| Task A | succeeded | file1.ts, file2.ts | - |
| Task B | failed (retry 1/2) | - | - |

失败详情:
- Task B: [失败原因]

下一步: 重试 Task B / 进入 Batch N+1
```

## 约束

- Agent 只能在 allowed_paths 内修改文件（通过 prompt 约束）
- 同批次的 Agent 必须在单条消息中并行启动
- 每个 Agent 的 prompt 必须包含完整的任务契约
- 失败时走局部重试，不全局回滚
- 超过最大重试次数后标记失败，继续其他任务
- 所有执行结果通过 TaskUpdate 记录
