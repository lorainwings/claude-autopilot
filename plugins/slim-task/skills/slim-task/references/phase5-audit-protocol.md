# Phase 5 审计隔离协议

## Contents

- [核心反作弊原则](#核心反作弊原则)
- [Rationalizations 反例表](#rationalizations-反例表)
- [Red Flags - STOP 清单](#red-flags---stop-清单)
- [隔离硬约束](#隔离硬约束)
- [三维审计派发](#三维审计派发)
- [汇总与修复流程](#汇总与修复流程)

## 核心反作弊原则

写实现的 Agent ≠ 审实现的 Agent。主 Agent 只做派发与汇总，**不做实质审查**。

## Rationalizations 反例表

主 Agent 与审计 Agent 在执行 Phase 5 时常见的"偷懒理由"清单。**任何与下表语义相近的内部独白都视为绕过，必须立即停下并改走右列动作**。表外但同类的理由同样视为绕过。

| 偷懒理由（Rationalization） | 真实含义 | 强制动作 |
|---|---|---|
| "用户上次已授权 commit，本次延用" | 把历史授权当本次授权 | 必须重新调 `AskUserQuestion`，历史消息不构成本次授权 |
| "改动很小 / diff 不到 50 行，跳过 Phase 5" | 用规模豁免流程 | 任何代码改动都进 Phase 5，size 不是豁免条件 |
| "我大致看了 diff，应该没问题" | 用主观判断替代独立审计 | 必须由独立子 Agent 重读 + 输出 `audit.json` |
| "lint/test 在 Phase 4 已经跑过了" | 把过往验证当本次验证 | engineering-auditor 必须重新执行 lint/build/typecheck，禁止缓存或复用历史输出 |
| "审计 Agent 报了 issue 但看起来无关紧要" | 主观降级 issue 严重度 | issue 一律进入修复循环，严重度仅决定优先级，不决定是否处理 |
| "修复 3 轮还有 issue，剩下的留给用户" | 用上限规避根因分析 | 触达 3 轮上限必须 **停下** 让用户人工介入，禁止 silent skip |
| "审计 Agent 可以共用 Phase 4 的 context 节省 token" | 破坏盲审隔离 | 审计 Agent 必须 `general-purpose` 独立派发，不复用任何 Agent ID 或 prompt |
| "范围表里没列这个文件但顺手改了" | 用便利性绕过影响范围合约 | 视为越界，scope-audit 必须报 issue；如确需扩展须回到 Phase 2 重审范围表 |
| "我自己读一遍代码当 review，不派审计 Agent 了" | 主 Agent 自审 | 主 Agent 严禁实质审查；必须独立派发三维 auditor |
| "用户没问 audit 报告，跳过展示直接进 Phase 6" | 用沉默替代检查点 | 必须按 `${LANG}` 展示统一审计报告并执行标准检查点 |
| "Worktree 模式所以审计可以更宽松" | 用隔离强度换取流程豁免 | Worktree 不改变 Phase 5 任何强度要求 |
| "审计 Agent 自己也说 issues=[]，那应该没问题" | 用单一审计源代替三维交叉 | 三维 audit.json 必须独立产出，缺一不可 |

## Red Flags - STOP 清单

以下任一信号一旦出现，**立即停止当前动作**，回到 SKILL.md 全局护栏重新校验：

1. 主 Agent 正在直接 `Edit` / `Write` 业务代码文件（违反全局护栏第 1 条）
2. Phase 5 三维 audit.json 中有任一文件不存在或为空对象
3. audit.json `issues=[]` 但 `git diff` 行数 > 200 且未附执行日志
4. 任一审计 Agent 的 prompt 中出现 Phase 4 实现 Agent 的 ID、对话片段、自评摘要
5. 修复循环计数 ≥ 3 且仍存在未关闭 issue
6. 范围表外的文件出现在 `git diff` 中且 scope-audit 未报 issue
7. Phase 6 即将 commit 但未先展示 Phase 5 统一审计报告并通过检查点
8. 出现"基于历史指令"、"上次已确认"、"用户应该是想要"等推断式授权语言

## 隔离硬约束

- 审计 Agent 的 prompt **严禁**注入 Phase 4 实现 Agent 的对话历史、思考记录、自评内容
- 审计 Agent 与修复 Agent 均使用 `general-purpose` subagent_type 独立派发
- **不复用** Phase 4 任何 Agent ID
- 审计产物落盘路径：`.claude/slim-task/audits/{task-slug}/`

## 三维审计派发

### 5a 范围审查 — scope-auditor

prompt 注入内容：
- 任务描述（Phase 1 摘要）
- 影响范围表（Phase 2 审批版本）
- 完整 `git diff` 输出

职责：判定所有改动文件是否在影响范围表内 + 表中预期改动是否真的发生。
输出：`scope-audit.json`（含越界文件、遗漏文件列表）。

### 5b 最佳实践对标 — practice-auditor

prompt 注入内容：
- 任务描述 + Phase 2c 方案
- 完整 `git diff` 输出
- 项目编码规范引用（`CLAUDE.md` / `.claude/rules/code-quality.md` 等路径）

职责：对照方案与项目规范评分；标记偏离与违规。
输出：`practice-audit.json`。

### 5c 工程检查 — engineering-auditor

prompt 注入内容：
- 项目根路径 + 影响范围内文件路径
- 项目 lint / build / typecheck 命令清单（从 `CLAUDE.md` / `Makefile` 自动发现）

职责：执行 lint / build / typecheck，捕获所有失败。
输出：`engineering-audit.json`（含失败命令、错误日志）。

### 5d UI 检查（涉及 UI 改动时）

提示用户调用 `frontend-design` 或 `ui-ux-pro-max` Skill 进行视觉一致性审查。

## 汇总与修复流程

1. 主 Agent 读取 3 份 `audit.json`
2. 向用户展示统一审计报告（按 `${LANG}`）
3. 若存在 issue：派发修复 Agent（独立 context）修复
4. 修复后再次派发 5a/5b/5c 审计 Agent 复核（同样独立 context）
5. **修复循环上限 3 次**，超过则停下让用户人工介入
6. 全部通过后执行标准检查点协议进入 Phase 6
