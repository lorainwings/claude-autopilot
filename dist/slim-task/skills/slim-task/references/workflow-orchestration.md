# Workflow 确定性编排协议（≥4 节点）

> 本文件是 Phase 4-5 在 DAG ≥4 节点时的 **Workflow 确定性编排**完整协议（输入契约 + 脚本骨架 + 输出契约）。模式分流阈值与指令式 fan-out 流程见 SKILL.md Phase 4，不在此重复。

## Contents

- [适用条件](#适用条件)
- [输入契约](#输入契约)
- [脚本骨架](#脚本骨架)
- [输出契约](#输出契约)
- [隔离保证](#隔离保证)

## 适用条件

DAG 节点数 ≥4 时启用。主 Agent 调用 `Workflow` 工具，将 Phase 4（DAG 并行执行）与 Phase 5（三维盲审 + 修复循环）合并为一段确定性脚本。控制流（逐层 barrier、修复轮次计数、三维审计并行）由 JS 引擎保证，单个 `agent()` 内部仍是模型驱动。

## 输入契约

主 Agent 构建 `args` 注入：

```
{
  taskSlug, lang, baseRef,
  dagLayers: [[{ id, objective, files: [...] }, ...], ...],  // 按 Layer 分组
  impactFiles: [...],          // Phase 2 审批影响范围表的文件白名单（闭集）
  auditCmds: { lint, build, typecheck },  // 从 CLAUDE.md/Makefile 发现
  auditDir: ".claude/slim-task/audits/{taskSlug}/"
}
```

## 脚本骨架

关键控制流，主 Agent 据此生成：

```javascript
export const meta = {
  name: 'slim-task-execute',
  description: 'Phase 4-5: DAG parallel impl + three-dim blind audit with fix loop',
  phases: [{ title: 'Implement' }, { title: 'Audit' }],
}
const AUDIT_SCHEMA = { type: 'object', required: ['pass', 'issues'],
  properties: { pass: { type: 'boolean' }, issues: { type: 'array', items: { type: 'string' } } } }
const IMPL_SCHEMA = { type: 'object', required: ['modified_files', 'summary'],
  properties: { modified_files: { type: 'array', items: { type: 'string' } },
    summary: { type: 'string' }, issues: { type: 'array', items: { type: 'string' } } } }
const whitelist = new Set(args.impactFiles)
// Phase 4: 逐层并行，层内 parallel() 自带 barrier
phase('Implement')
for (let i = 0; i < args.dagLayers.length; i++) {
  const layer = args.dagLayers[i]
  log(`Layer ${i}: 派发 ${layer.length} 个任务`)
  const r = await parallel(layer.map(t => () =>
    agent(buildImplPrompt(t, args.lang), { label: `impl-${t.id}`, phase: 'Implement', schema: IMPL_SCHEMA })))
  const ok = r.filter(Boolean)
  if (ok.length < layer.length) return { status: 'impl-failed', layer: i }   // 部分失败即停
  // 文件边界硬校验：实际改动必须 ⊆ 白名单
  const over = ok.flatMap(a => a.modified_files).filter(f => !whitelist.has(f))
  if (over.length) return { status: 'scope-violation', layer: i, files: [...new Set(over)] }
  log(`Layer ${i}: 完成 ${ok.length}/${layer.length}`)
}
// Phase 5: 三维盲审强制并行 + 修复循环硬计数 ≤3
phase('Audit')
let round = 0, passed = false
while (round < 3 && !passed) {
  log(`审计第 ${round + 1}/3 轮`)
  const v = await parallel([
    () => agent('scope-auditor: 判定改动是否越界 + 预期改动是否发生。返回 pass/issues。', { schema: AUDIT_SCHEMA, phase: 'Audit' }),
    () => agent('practice-auditor: 对照方案与规范评分，标记偏离违规。返回 pass/issues。', { schema: AUDIT_SCHEMA, phase: 'Audit' }),
    () => agent(`engineering-auditor: 执行 ${JSON.stringify(args.auditCmds)} 捕获失败。返回 pass/issues。`, { schema: AUDIT_SCHEMA, phase: 'Audit' }),
  ])
  if (v.filter(Boolean).length < 3) return { status: 'audit-incomplete', round }  // 三维缺一即停
  const issues = v.flatMap(x => x.issues)
  if (issues.length === 0) { passed = true; break }
  round++
  if (round < 3) await agent(`修复以下 issue（独立 context，仅改影响范围内文件）：${JSON.stringify(issues)}`, { label: `fixer-${round}`, phase: 'Audit' })
}
return { status: passed ? 'pass' : 'max-rounds', round }
```

> 脚本若抛异常（语法错/全部 agent 失败），Workflow 返回非正常结果；主 Agent 须捕获并按 `script-error` 处理。

## 输出契约

主 Agent 读 Workflow 返回值后的动作（异常 #N 的完整展示内容与可选动作见 `exception-pause.md`）：

| 返回 status | 主 Agent 动作 |
|------------|--------------|
| `pass` | 展示审计摘要，自动进入 Phase 6 |
| `max-rounds` | 异常暂停 #2：展示残留 issue，交人工介入 |
| `impl-failed` | 异常暂停 #3：展示失败层号，询问重试或终止 |
| `scope-violation` | 异常暂停 #1：展示越界文件，询问扩范围或回滚 |
| `audit-incomplete` | 异常暂停 #6：三维审计缺一，重派该 auditor |
| `script-error` / 无返回 | 异常暂停 #3 变体：展示错误堆栈，询问重试 Workflow 或回退指令式手动执行 |

## 隔离保证

Workflow 内每个 `agent()` 都是全新隔离 context，天然满足审计隔离硬约束（护栏 10）；脚本不复用任何 Agent ID。子 Agent 经 `IMPL_SCHEMA` 强制返回 `modified_files`，边界校验与 scope 审计据此进行。脚本的 `parallel([scope, practice, engineering])` 三路缺一即违反护栏 10，`while (round < 3)` 上限禁止改大于 3。
