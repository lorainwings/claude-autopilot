---
name: harness
description: 并行 AI 工程控制平面主入口。显式触发 parallel-harness runtime，对复杂工程任务执行任务图规划、并行调度、验证和报告汇总。仅在用户明确要求启动 harness 编排时使用。
argument-hint: "[工程任务描述]"
user-invocable: true
disable-model-invocation: true
context: fork
agent: general-purpose
---

# Harness

这个 skill 是 `parallel-harness` 的**可执行入口**，不是架构说明文档。

你的职责只有两件事：

1. 把用户的任务描述原样交给 `parallel-harness` runtime
2. 把 runtime 的真实执行结果简洁返回给用户

禁止手工在对话里“模拟” planning / dispatch / verify。运行时输出才是真相源。

## 执行步骤

### 1. 校验输入

- 如果 `$ARGUMENTS` 为空，要求用户补充明确的工程任务。
- 不要自己重写、压缩或猜测用户意图；原样传给 runtime。

### 2. 调用 runtime

把 `$ARGUMENTS` 写入临时文件，然后执行下面这条命令：

```bash
INTENT_FILE="$(mktemp)"
cat > "$INTENT_FILE" <<'EOF'
$ARGUMENTS
EOF

bun run "${CLAUDE_PLUGIN_ROOT}/runtime/scripts/execute-harness.ts" \
  --intent-file "$INTENT_FILE" \
  --project-root "$(pwd)" \
  --output json

STATUS=$?
rm -f "$INTENT_FILE"
exit "$STATUS"
```

要求：

- 必须使用 `runtime/scripts/execute-harness.ts`
- 必须传 `--intent-file`
- 必须传当前工作目录作为 `--project-root`
- 不要跳过 runtime 直接自行规划任务

### 3. 解释结果

脚本成功时会返回 JSON。向用户至少汇报：

- `run_id`
- `final_status`
- 已完成任务数
- 失败任务数
- 主要阻断/建议项（如果有）

如果 `final_status` 是：

- `succeeded`: 汇报成功完成，并给出关键建议项
- `blocked`: 明确指出被阻断，列出阻断原因或待处理建议
- `failed` / `partially_failed`: 明确指出失败范围，不要伪装成成功

### 4. 错误处理

- 如果脚本退出非 0，直接把错误告诉用户，并说明 harness runtime 没有成功执行。
- 不要在脚本失败后继续手工模拟一套结果。

## 运行时真相源

- 入口脚本：`runtime/scripts/execute-harness.ts`
- 主运行时：`runtime/engine/orchestrator-runtime.ts`
- Worker 阶段 skill 由 runtime 选择后，嵌套 Claude 会话显式调用对应的 `parallel-harness:*` skill
