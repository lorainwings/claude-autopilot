# AI Harness 编排方法论 · spec-autopilot 编排审计 · 修复计划

> 调研日期：2026-08-10｜审计对象：`plugins/spec-autopilot/`
> 调研来源：superpowers (270k★, commit `44c9b2d6`)、open-gsd/gsd-core (v1.10.0, commit `57437071`)、Claude Code 官方文档、LangGraph/AutoGen/CrewAI/OpenAI Agents SDK
> 全部 BUG 均为**本地实测复现**，非静态推测

## 目录

- [第一部分：方法论](#第一部分方法论)
- [第二部分：审计结果](#第二部分审计结果)
- [第三部分：修复计划](#第三部分修复计划)

---

## 第一部分：方法论

### 核心公理：确定性 vs 概率性

一切编排稳定性问题都可归约为一个判断：**这个约束由代码强制，还是由模型自愿遵守？**

| | 确定性执行 | 概率性执行 |
|---|---|---|
| 载体 | hook 脚本退出码、JSON 决策、文件存在性、git 状态 | SKILL 正文措辞、prompt 指令、ALL CAPS、MUST |
| 失效模式 | 逻辑写错（可测试发现） | 模型在上下文压力下跳过（不可预测） |
| 可验证性 | 可写断言 | 只能统计倾向 |

superpowers 的实证最能说明代价：该库 270k★、零 `PreToolUse`/`PostToolUse` 守卫，全部中途门禁靠 prompt。结果是 issue #528「Claude 会跳过 spec 和 code quality review，问它为什么，它总说想快一点，并承认违反了指令」—— 提出用 `TaskCompleted` hook 修复的 PR #613 **至今未合并**。

GSD 把这条提炼成一句可直接引用的判据（`hooks/gsd-agent-isolation-guard.js` 文件头）：

> "A prose backstop cannot fix a prose defect — it is the same class of artifact the model may equally skip."

### P1｜凡依赖模型把值写进工具调用的约束，必须由 hook 校验该值

GSD issue #3045 是这条的原始事故：隔离模式在 shell 侧正确解析，但**通过 prose 交付给模型**；模型漏写 `isolation="worktree"` 时，"executor 直接在用户主检出里运行并提交，无同意、无告警"。

**可机械校验的检查**：对 SKILL 里每一条 `MUST`，指出捕获其违反的那个 exit 2 / deny 决策；指不出的，就承认它是 advisory。

### P2｜守卫必须 fail-closed，且 fail-closed 的方向按消费者区分

同一个查询对调度器可以 fail-open（退化成串行总是安全的），对守卫必须 fail-closed。GSD 注释：「a guard that cannot verify must not answer "safe"」。

**反面**：`|| echo '{"status":"warn"}'` 这类兜底把「检查崩了」和「检查通过」合并成同一个结果。

### P3｜守卫里的兜底 `catch { exit 0 }` 是绕过，不是安全网

GSD #2547/#2595 记录了一整类事故：畸形 payload 让守卫抛异常、命中外层 catch，「把一个本该 BLOCK 的调用静默降级为 allow」。变体包括 `file_path: ""` 遮蔽真实 `path`、`edit: [null]`、`{"toString": null}`、`JSON.parse('null')`。

### P4｜阻断必须发生在动作之前

Claude Code 官方文档（[hooks](https://code.claude.com/docs/en/hooks)）逐字：

> `PostToolUse` | After a tool call succeeds ... Can block? **No** — "Shows stderr to Claude; the tool already ran"

推论：任何"禁止写入 X"的约束挂在 PostToolUse 上都只是事后告知，文件已落盘。需真拦截必须用 PreToolUse + `hookSpecificOutput.permissionDecision: "deny"`。

另两条官方硬约束：
- exit 1 **不阻断**：「treats exit code 1 as a non-blocking error and proceeds with the action」。要阻断用 exit 2。
- exit 2 与 JSON **互斥**：「If you exit 2, any JSON is ignored」。

### P5｜绝不接受自证；要求机械可证的 fail-first

GSD ADR-1606 把调用方自陈（`failFirst: true`）定性为「unfalsifiable fake-green hole」，改为 `passed = proof.provenFailFirst === true && run.passed === true`。并分别防御两种伪造：load-crash 造成的假 RED、空测试文件造成的假 GREEN。

### P6｜写声明的 agent 不得是认证它的 agent

GSD verifier：独立上下文 + 对抗性先验（"Assume the phase goal was not achieved until codebase evidence proves it"）+ 无 `Edit` 工具 + 无提交权。superpowers 同构：spec 合规与代码质量两个独立 verdict，缺一不接受。

### P7｜持久化"决策"而非"能力"

"这台机器能隔离" ≠ "这次派发应当隔离"。GSD 用 `.gsd/dispatch-isolation-sentinel.json` 记录每次派发的已解析决策，带 10 分钟新鲜度窗口 + phase/plan 标签，使过期记录**不适用**而非仅仅"旧"。

### P8｜状态声明必须与独立来源交叉校验

GSD `src/verify.cts:2243-2277`：STATE 说 milestone 完成、ROADMAP 还列着未开始的 phase → **报错**，不是警告。

### P9｜恢复靠产物扫描做到幂等，磁盘是真相、状态文件是缓存

GSD：重跑 `/gsd:execute-phase` 扫描已有 SUMMARY、跳过、从第一个未完成的 plan 续跑。superpowers 用 plan-scoped ledger + 身份行（`# SDD ledger — plan: <path>`）让"读错 plan 的 ledger"变成可检测而非靠猜。

superpowers 记录的代价：「controllers that lost their place have re-dispatched entire completed task sequences — the single most expensive failure observed」。

### P10｜绝不无限等待 harness 的完成信号

GSD：「Never block indefinitely waiting for a signal — always verify via filesystem and git state.」丢信号但提交与 SUMMARY 都在 → 视为成功。

### P11｜阻断消息不得包含自身的绕过配方

GSD `gsd-write-guard.js`：「a block message that prints the bypass recipe hands that same agent a mechanical self-authorization」。可以说存在 override，不要说怎么开。

### P12｜子 agent 返回值用封闭枚举 + 每个分支都有处理

superpowers 实现：`DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT`，≤15 行，controller 每个状态都有文档化分支。

### P13｜产物按路径传递，绝不粘贴正文

superpowers 逐字理由：粘贴的内容「stays resident in your context for the rest of the session and is re-read on every later turn」。实测代价：「a real session's dispatch hit 42k chars of which 99% was pasted history」。

### P14｜每个循环都要有数值上限与定义好的断路器

superpowers：每 task 5 轮上限，第 4-5 轮换新 implementer 并升一档模型，到顶则裁决为 {park-with-ruling, BLOCKED} 二者之一。「Adjudicating earlier to end a loop is pre-judging with a different name.」

### P15｜按基线失效类型选择措辞形态（有实测反例）

superpowers `writing-skills/SKILL.md:459-478` 的实测结论，与直觉相反：

| 基线失效 | 正确形态 | 错误形态 |
|---|---|---|
| 跳过纪律 | 禁令 + rationalization 表 + red flags | — |
| 形状错误 | 正向配方（按序列出各部分） | **禁令**（实测「trended worse than even the no-guidance control」） |
| 遗漏 | 模板里的 REQUIRED 占位槽 | — |
| 条件行为 | 基于可观测量的谓词 | — |

并且：**不要加 nuance / 豁免子句**。「appending a single nuance clause to a winning recipe degraded it from consistent to noisy」；「'This limit doesn't apply to code blocks' still suppresses code blocks」。

### P16｜description 只写触发条件，不写流程摘要

superpowers 记录的真实回归：「A description saying 'code review between tasks' caused an agent to do ONE review, even though the skill's flowchart clearly showed TWO reviews」—— 流程摘要会成为 agent 抄的近道。

### P17｜禁止 `@path` 强加载，跨 SKILL 按名引用

`@` 立即加载，「consuming 200k+ context」。

### P18｜给 hook 决策同时输出结构化字段，让测试不必 regex 消息文本

GSD 输出 `decision` / `code` / `oldLines` / `newLines` 等 typed 字段。

### P19｜重复的内联逻辑用 parity 测试绑定

GSD 有 5 份内联 normalizer（刻意内联，因为「a sibling require is a staging dependency that can fail silently」），靠一个 parity 测试保持一致。

### P20｜验证注入本身，而不只验证被注入物

superpowers `CLAUDE.md`：「If you are not sure whether your integration loads the bootstrap at session start, it does not.」验收测试是固定用户消息 → 期望自动触发的 skill → 必须贴 transcript。

### 审计清单（可直接执行）

1. 每个"禁止写入"守卫挂在 PreToolUse 还是 PostToolUse？
2. 每个守卫是否有 `|| exit 0` / `|| echo warn` 兜底把崩溃降级为放行？
3. 每个 hook 的 matcher 是否锚定（`^X$`）？MCP 是否带 `__.*`？
4. 门禁的生效前提是否包含模型自填的值？
5. 审计/对帐脚本在输入缺失时报 ok 还是报错？
6. 事件发射器是否幂等？
7. 每个循环是否有数值上限与断路器？
8. 已知失效模式是否各有一条对应断言？

---

## 第二部分：审计结果

### 总览

| # | 严重级别 | 问题 | 违反 |
|---|---|---|---|
| A | **P0** | TDD 守卫与占位符禁令挂 PostToolUse，拦不住已落盘写入 | P4 |
| B | **P0** | L2 测试验证只 warn 不 deny，且只查最后一个 task | P2, P5 |
| E | **P0** | 门禁依赖模型自填 prompt 标记，漏写即静默失效 | P1 |
| C | **P1** | 派发审计三脚本为死代码，且输入缺失时报 `reconcile_status: "ok"` | P2, P8 |
| D | **P1** | `emit-phase-event.sh` 无幂等，恢复时重复发 `phase_start 0` | P9 |
| F | P2 | `parallel-merge-guard.sh` 为重构遗留孤儿，测试仍在跑它 | P19 |

### BUG-A（P0）｜TDD 守卫与占位符禁令是事后反馈，无法拦截

**位置**：`runtime/scripts/unified-write-edit-check.sh`，注册于 `hooks/hooks.json` 的 `PostToolUse` / matcher `^(Write|Edit)$`

**证据**：官方文档明确 PostToolUse 在工具**成功之后**触发、Can block 列为 **No**。脚本输出 `{"decision":"block"}` + `exit 0` 语法合法（PostToolUse 确实属于顶层 `decision` 组），但语义只是把 reason 反馈给模型，**不回滚已发生的写入**。

**受影响的检查**：

| 行号 | 检查 | 实际效果 |
|---|---|---|
| `:219` | TDD RED 阶段拦实现文件 | 实现代码已落盘 |
| `:225` | GREEN 阶段拦测试文件修改 | 测试已被改写 |
| `:249` | 占位符禁令（TODO/FIXME） | 占位符已进代码 |
| `:139` | 保护路径（openspec/、checkpoint） | **子 agent 已污染编排器状态** |
| `:187` | 并行文件归属 | 越界写入已发生 |

`:139` 最严重：设计意图是靠"子 agent 禁止改 checkpoint"保证状态隔离，实际写入已完成。

### BUG-B（P0）｜L2 测试验证只 warn 不 deny，且只查最后一个 task

**位置**：`runtime/scripts/check-predecessor-checkpoint.sh:385-393`

三个缺陷叠加：

- `:387` 只取 `tail -1`（排序后最后一个 task checkpoint）→ 前面所有 task 的测试验证结果**从不检查**
- `:388-392` 拿到 `warn` 只 `echo >&2`，注释自认 "Warn only — does not deny"，而同文件 `:111` 有可用 `deny` 函数，`:401`/`:435`/`:441` 都在用
- `:386` 兜底 `|| echo '{"status":"warn",...}'` → 验证脚本自身崩溃也降级为 warn（违反 P2）

结果："测试根本没跑"与"测试跑了没通过"被合并为同一个静默放过。

### BUG-E（P0，根缺陷）｜门禁依赖模型自填标记

**位置**：`runtime/scripts/check-predecessor-checkpoint.sh:47-49`

门禁只对 prompt 字段以 `<!-- autopilot-phase:N -->` 开头的 Task 生效，其余一律 `exit 0`。而该标记由主编排 SKILL 指示模型写入 —— 属于 P1 所述"prose 交付的值"，无任何机制校验模型是否真的写了。

**A/B 对照实测**（同一个越权的 Phase 5 派发，缺前驱 checkpoint）：

```
A. 带 marker  → {"permissionDecision":"deny","permissionDecisionReason":
                 "Phase results directory not found. Phase 1 must complete before Phase 5 can start."}
B. 去掉 marker → （空输出，退出码 0）＝ 静默放行
```

这是三层防线的根缺陷：L2 的生效前提本身是概率性的。模型少写一行注释，确定性防线整体消失且无告警。

### BUG-C（P1）｜派发审计链路是死代码 + 报假绿灯

**位置**：`runtime/scripts/generate-dispatch-plan.sh:110`

`python3 -c` 模式下使用 `__file__`（在 `resolve_agent()` 函数体内构造 `search_paths`，无 try/except，`:130` 无条件调用）。

**端到端实测**：退出码 1、`NameError: name '__file__' is not defined`、`dispatch-plan.json` **零字节未生成**。

但全仓库 grep 确认 `generate-dispatch-plan.sh` / `generate-dispatch-actual.sh` / `reconcile-dispatch.sh` **三者互相引用、无任何外部调用方** → 设计了审计机制但从未接线（否则崩溃早被发现）。

**连带的 fail-open（违反 P2/P8）**：
- plan 缺失时 `generate-dispatch-actual.sh` 输出 `plan_available: false` + `diff_count: 0` + **`reconcile_status: "ok"`**
- `reconcile-dispatch.sh` 输入全缺时输出 `status: "ok"` + 退出码 0

上游 100% 崩溃、下游报告"对帐通过"。

### BUG-D（P1）｜事件发射器无幂等

**位置**：`runtime/scripts/emit-phase-event.sh`（脚本内零去重）+ `skills/autopilot-phase0-init/references/execution-steps.md:127`（Step 4.5 无条件发射）、`:170`（Step 6.1 重发）

**实测**：连续两次调用产出两条 `phase_start 0`（sequence 1 和 2）。

"从头开始"分支因 `:169` 先 `: > events.jsonl` 截断而安全；**"从断点继续"分支不截断**（`:176`）→ Step 4.5 那条叠加在历史事件上，每次崩溃恢复多一条。

连带：实测两次 `session_id` 不同（`1786367974238` vs `...307`），同一次 Phase 0 归入两个 session，GUI 按 session 聚合会错位；`change_name` 均为 `unknown`（Step 4.5 早于 change 目录创建）。

### BUG-F（P2）｜孤儿脚本造成虚假信心

`runtime/scripts/parallel-merge-guard.sh` 自称 `Hook: PostToolUse(Task)`，但 `hooks.json` 零引用。逻辑已被 `_post_task_validator.py:557-577`（VALIDATOR 4）吸收。`tests/test_parallel_merge.sh` 仍在测这个孤儿脚本 → 测试全绿但被测对象不在运行路径上。

### 测试覆盖缺口（BUG 长期存活的原因）

| BUG | 相关测试文件数 |
|---|---|
| B（warn 不 deny） | **0** |
| C（`__file__` / `reconcile_status`） | **0** |
| D（事件幂等） | **0** |
| E（marker 缺失绕过） | **0** |

1245+ 断言的测试套件从未针对这些失效模式写过断言。

### 做得对的部分（修复时勿误改）

- 三个 PreToolUse 守卫 schema 完全正确：`hookSpecificOutput` + `hookEventName` + `permissionDecision: "deny"` + `exit 0`
- 全仓库 hook 脚本零 `exit 2`，统一走 JSON 决策 —— 符合官方"二选一"互斥约束
- checkpoint 用 `os.replace()` 原子写入（`write-checkpoint.sh:108`）；损坏文件先备份到 `.corrupted-backups/` 再移除，非静默删除
- v5.1 对"背景 agent 完全绕过 L2"的修复真实有效；python3 缺失时 fail-closed 正确
- 所有 matcher 均已锚定（`^Bash$` / `^Task$` / `^(Write|Edit)$`）
- `PostToolUse: '.*'` 只挂遥测（`capture-hook-event.sh`、`emit-tool-event.sh`），非守卫，开销可接受

### 审计中被推翻的假设（勿再沿用）

| 旧结论 | 实际情况 |
|---|---|
| `reinject-state-after-compact.sh` 把 SessionStart(compact) 误标为 PostCompact | **不成立**，注释本就正确并引了官方原话 |
| Phase 0 无条件重复发 `phase_start` | 需修正为：仅"从断点继续"分支触发（"从头开始"有截断保护） |
| `file_path` 用 grep 提取可被诱饵遮蔽 | **不成立**，JSON 转义使诱饵不匹配，实测正确提取 |
| `parallel-merge-guard.sh` 未注册＝功能缺失 | 实为重构遗留孤儿，逻辑已被 Python 侧吸收 |
| Stop/SubagentStop 缺 `stop_hook_active` 有循环风险 | **不成立**，二者只挂遥测、不返回 block 决策 |

---

## 第三部分：修复计划

### 批次划分

按"单独可验证、单独可回滚"切分，每批独立提交。

### 批次 1（P0）｜把阻断迁到 PreToolUse

**目标**：BUG-A

`unified-write-edit-check.sh` 拆成两条注册：

- **PreToolUse / `^(Write|Edit)$`** — 承载所有需要真阻断的检查（`:139` 保护路径、`:187` 并行归属、`:219`/`:225` TDD 阶段、`:249` 占位符），输出 `hookSpecificOutput.permissionDecision: "deny"`
- **PostToolUse / `^(Write|Edit)$`** — 仅保留事后遥测与 advisory

PreToolUse 的 `tool_input` 已含 `file_path` 与 `content`，现有检查逻辑无需重写取值方式。

**测试**（每条至少 3 例：正常/边界/错误）：
- RED 阶段写实现文件 → 断言 deny 且文件**未创建**
- GREEN 阶段改测试文件 → 断言 deny
- 子 agent 写 `checkpoint-phase-*.json` → 断言 deny
- 正常路径写允许的文件 → 断言放行

### 批次 2（P0）｜L2 测试验证改 fail-closed 且全量检查

**目标**：BUG-B

`check-predecessor-checkpoint.sh:385-393`：

1. 去掉 `tail -1`，遍历**全部** task checkpoint
2. 任一为 `fail` → 调用现有 `deny`（`:111`）
3. 去掉 `|| echo '{"status":"warn"}'` 兜底；验证脚本崩溃 → `deny`，理由写明"无法验证"（P2）
4. 保留 `warn` 用于真正的非阻断情形，与"无法验证"区分开

**测试**：全部 task 通过 → 放行；中间某个 task fail（非最后一个）→ deny；验证脚本崩溃 → deny；缺 checkpoint → deny。

### 批次 3（P0）｜门禁不再依赖模型自填标记

**目标**：BUG-E（根缺陷）

标记不可靠是因为它由模型写。改为**双通道**，任一命中即进入完整审计：

1. **主通道（确定性）**：Phase 0 落一份 dispatch sentinel（P7 模式）—— `openspec/changes/.autopilot-dispatch-sentinel.json`，含 `{phase, mode, session_id, ts}`，由编排器在派发**前**无条件写入（作为它本来就要做的调用的副作用，而非一条独立的"记得也写一下"指令）。门禁读 sentinel 判定"这次派发应当受审"，带新鲜度窗口 + phase 标签，过期即视为不适用。
2. **兜底通道**：保留现有 marker 匹配。

并新增**缺标记告警**：活跃 autopilot 会话中出现无 marker 且无 sentinel 的 Task 派发 → 输出 `permissionDecision: "ask"`，让用户裁决而非静默放行。

> `ask` 而非 `deny`：非 autopilot 的正常 Task 派发不应被硬拦。官方 `permissionDecision` 支持 allow/deny/ask/defer 四值。

**测试**：有 sentinel 无 marker → 完整审计；有 marker 无 sentinel → 完整审计；两者皆无 + 活跃会话 → ask；两者皆无 + 无活跃会话 → 放行；sentinel 过期 → 不适用 + ask。

### 批次 4（P1）｜派发审计接线或删除

**目标**：BUG-C

先决策再动手，二选一：

- **方案 A（接线）**：修 `__file__`（由 Bash 侧传 `SCRIPT_DIR` 参数或环境变量），在 `autopilot-dispatch` 派发前后真正调用这三个脚本，并把 `reconcile_status` 接入门禁
- **方案 B（删除）**：三脚本与 `tests/test_parallel_merge.sh` 之外的相关测试一并移除，在 CHANGELOG 说明理由

无论哪个方案，**必须先修 fail-open**：输入缺失时 `reconcile_status` 不得为 `ok`，应为 `unavailable` 并让消费方视作未通过（P2/P8）。

> 倾向方案 A：plan-vs-actual 对帐正是 P8 要求的独立来源交叉校验，值得接线。但需确认它是否与 `_post_task_validator.py` 的 WS-E agent 边界校验重复 —— 若重复则选 B。

### 批次 5（P1）｜事件幂等

**目标**：BUG-D

1. `emit-phase-event.sh` 加幂等：同一 `(session_id, type, phase)` 已存在则跳过（`phase_start` 类事件）
2. `execution-steps.md` Step 4.5 改为条件发射：仅当"从头开始"或事件文件为空
3. 修 `change_name: unknown` —— Step 4.5 移到 change 目录创建之后，或发射时补写
4. 修 `session_id` 不一致 —— 同一 Phase 内复用同一 session id

**测试**：连续两次调用 → 仅一条事件；"从断点继续"恢复 → 不新增 `phase_start 0`；"从头开始" → 截断后恰好一条。

### 批次 6（P2）｜清理孤儿

**目标**：BUG-F

删除 `parallel-merge-guard.sh`，`tests/test_parallel_merge.sh` 改为直接测 `_post_task_validator.py` 的 VALIDATOR 4（保留断言、换被测对象，不弱化）。

### 交付纪律（对齐仓库既有规则）

- 所有构建/测试经 Makefile：`make test` / `make lint` / `make build`
- 禁止手改 `dist/`，由 pre-commit 自动重建
- 禁止散弹式改版本号，交给 release-please
- SKILL.md 改动遵循 `.claude/rules/skill-authoring.md`：≤500 行、不写版本号、description 只写触发条件（与 P16 一致）
- commit 用 Conventional Commits，scope 为 `spec-autopilot`
- push 前先 `git fetch origin main && git rebase origin/main`（pre-push 强制）

### 建议执行顺序

批次 1 → 2 → 3 独立且都是 P0，可并行开发但需分别提交。批次 4 需先做接线/删除的决策。批次 5、6 可随时插入。

三条 P0 修完后，L2 防线才真正具备设计意图中的强度。
