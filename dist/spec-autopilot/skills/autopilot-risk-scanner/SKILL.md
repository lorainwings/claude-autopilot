---
name: autopilot-risk-scanner
description: "Use when the autopilot orchestrator dispatches an adversarial Critic sub-agent just before a phase gate and needs that sub-agent to score the phase artifacts against structured rubrics and emit risk-report-phase{N}.json into the change context for downstream gate prechecks. ONLY for autopilot orchestrator; not for direct user invocation; skip when running outside the dispatched Critic context."
user-invocable: false
---

# Autopilot Risk Scanner — 主动风险扫描 Critic Agent

> **前置条件自检**：本 Skill 仅在 autopilot 编排主线程派发的独立 Critic Sub-Agent 中使用。
> 如果当前不是该上下文，请立即停止并忽略本 Skill。

借鉴 **Devin Autofix Loop**、**Cursor Vuln Hunter**、**ASDLC Adversarial Review** 的核心模式：
**独立 Critic Agent + 结构化 Rubric + 闭环回灌**。

## 设计原则

1. **独立性**：Critic Agent 与执行 Agent 必须由编排主线程独立派发，禁止复用同一上下文，避免确认偏误
2. **对抗性**：prompt 中显式指示 Critic 以"反方角色"审视产物，主动寻找证据缺失而非认同当前实现
3. **结构化**：所有评分必须遵循 rubric YAML 中声明的 `check_id` / `severity` / `evidence_format`，禁止自由发挥
4. **可机读**：输出 JSON 必须严格符合下述 schema，下游 gate 脚本依赖此结构做拦截决策
5. **闭环回灌**：高风险条目通过 `feedback-loop-inject.sh` 注入后续 sub-agent 的 task envelope，形成防御纵深

## 调用时机

每个 phase gate 的 **Step 0 (预检)** 由 `runtime/scripts/risk-scan-gate.sh` 触发：

```
Phase N 完成 → autopilot-gate Step 0
              ├── 派发本 Skill 作为 Critic Sub-Agent (独立上下文)
              ├── 写入 openspec/changes/<change_name>/context/risk-report-phase{N}.json
              ├── risk-scan-gate.sh 读取报告，统计 blocking_count
              └── 若 blocking_count > 0 → fail-closed，gate 拒绝放行
```

## Prompt 模式 (Adversarial Rubric Scoring)

派发本 Skill 时，编排主线程应在 task envelope 中提供：

```json
{
  "phase": 5,
  "requirement_type": "feat",
  "rubric_path": "skills/autopilot-risk-scanner/references/rubrics/phase5-feat.yaml",
  "artifacts_root": "openspec/changes/<change_name>/",
  "report_output": "openspec/changes/<change_name>/context/risk-report-phase5.json",
  "stance": "adversarial-critic"
}
```

Critic Agent 的工作流程：

1. 加载 rubric YAML，枚举所有 `check_id`
2. 对每条 check：
   - 读取 `evidence_required` 与 `evidence_format`
   - 主动在 artifacts 中搜寻证据
   - **以反方视角**判定：若证据缺失或不足以推翻 "未达标" 假设，则 `passed=false`
3. 记录 `evidence` 字段（精确到文件:行号）与 `reasoning`（最多 3 句话）
4. 生成 JSON 报告

## 输出 JSON Schema

参见 `references/rubric-schema.md`。必备字段：

```json
{
  "phase": 5,
  "rubric_version": 1,
  "requirement_type": "feat",
  "scored_rubrics": [
    {
      "check_id": "P5-FEAT-001",
      "severity": "block",
      "passed": false,
      "evidence": "tests/test_foo.sh:无对应测试",
      "reasoning": "新增公共函数 foo() 在源码中存在但未被任何测试文件 import"
    }
  ],
  "blocking_count": 1,
  "warning_count": 0,
  "recommendation": "block_phase_advance"
}
```

`recommendation` 取值：`block_phase_advance` | `proceed_with_warnings` | `proceed`

## 与其他 Skill 的关系

| Skill | 关系 |
|------|------|
| `autopilot-gate` | gate Step 0 调用本 Skill 作为预检；blocking_count>0 时拒绝放行 |
| `autopilot-dispatch` | task envelope 应携带 `prior_risks[]`，由 `feedback-loop-inject.sh` 从本 Skill 报告生成 |
| `autopilot-phase5.5-redteam` | Phase 5.5 是更激进的对抗模式；本 Skill 是常规 phase 级 Critic |

## 脚本依赖

| 脚本 | 用途 |
|------|------|
| `runtime/scripts/risk-scan-gate.sh` | gate Step 0 预检入口，读取报告并决策放行/拦截 |
| `runtime/scripts/feedback-loop-inject.sh` | 将 severity≥warn 条目注入下游 task envelope (C4) |

## 反例库 (C5)

所有由本 Skill 拦截、最终被人工或 Phase 5.5 复现的真实事故，必须以条目形式收录至
`docs/regression-vault/`，命名规范见 `docs/regression-vault/README.md`。
