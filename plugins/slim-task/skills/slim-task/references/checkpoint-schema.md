# Checkpoint Schema（断点续跑数据结构）

> 本文件是 checkpoint 落盘的**数据结构定义**（原始材料）。落盘时机、恢复逻辑等流程指令见 SKILL.md「Checkpoint 落盘与恢复」小节，不在此重复。

## 落盘路径

```
.claude/slim-task/checkpoints/{task-slug}-{phase}.json
```

同一 task 同一 phase 覆盖写最新态；Phase 6 commit 成功后整个 `{task-slug}` 相关 checkpoint 删除。

## JSON 结构

```json
{
  "taskSlug": "fix-login-timeout",
  "phase": "5",
  "lang": "zh-CN",
  "baseRef": "feat/login-fix",
  "worktree": ".claude/worktrees/slim-fix-login-timeout-1718000000 或 null",
  "updatedAt": "ISO8601 时间戳（由主 Agent 写入时生成）",
  "dagProgress": {
    "totalLayers": 3,
    "completedLayers": 2,
    "currentLayer": 2,
    "layerNodes": [
      { "id": "t1", "status": "done", "modifiedFiles": ["src/a.ts"] },
      { "id": "t2", "status": "running", "modifiedFiles": [] }
    ]
  },
  "fixRound": 1,
  "filesModified": ["src/a.ts", "src/b.ts"],
  "pendingDecision": {
    "type": "exception-pause | approval-gate | none",
    "exceptionId": "1-7 或 null",
    "options": ["展示给用户的可选动作标签"]
  }
}
```

## 字段说明

| 字段 | 用途 | 恢复时如何使用 |
|------|------|---------------|
| `phase` | 中断发生的 Phase | 决定从哪个 Phase 重入 |
| `dagProgress.completedLayers` | 已完成的 DAG 层数 | 跳过已完成层，从 `currentLayer` 续派 |
| `fixRound` | 修复循环已用轮次 | 恢复时**不清零**，续用剩余轮次（≤3 硬上限） |
| `filesModified` | 累计改动文件 | 与影响范围表比对，检测漂移 |
| `pendingDecision` | 中断时待用户决策项 | 恢复后直接重发对应 `AskUserQuestion` |

## 恢复决策卡（恢复时主 Agent 发起）

```
检测到中断于 Phase {phase}（{updatedAt}）：
- 从断点恢复（跳过已完成 {completedLayers} 层，续用修复轮次 {fixRound}/3）
- 重新开始（清理 checkpoint，从 Phase 0 重跑）
- 终止
```
