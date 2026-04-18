# Risk Report JSON Schema

`risk-report-phase{N}.json` 的权威 schema 定义。所有 Critic Agent 输出与 `risk-scan-gate.sh` 解析端必须遵守。

## 顶层字段

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `phase` | integer | 是 | phase 序号 (1, 2, 3, 4, 5, 5.5, 6, 7) — 5.5 表示 redteam 阶段 |
| `rubric_version` | integer | 是 | 引用的 rubric YAML 中的 `rubric_version` 值 |
| `requirement_type` | string | 是 | `feat` \| `bugfix` \| `refactor` \| `chore` |
| `scored_rubrics` | array<RubricScore> | 是 | 每条 check 的评分结果 |
| `blocking_count` | integer | 是 | `severity=block AND passed=false` 的条目数 |
| `warning_count` | integer | 是 | `severity=warn AND passed=false` 的条目数 |
| `recommendation` | string | 是 | `block_phase_advance` \| `proceed_with_warnings` \| `proceed` |
| `generated_at` | string (ISO 8601) | 是 | 生成时间戳 |
| `critic_agent_id` | string | 否 | Critic Agent 的 task_id，便于追溯 |

## RubricScore 子对象

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `check_id` | string | 是 | 必须与 rubric YAML 中 `check_id` 严格一致 |
| `severity` | string | 是 | `block` \| `warn` \| `info` |
| `passed` | boolean | 是 | true 表示证据充分 |
| `evidence` | string | 是 | 精确证据引用，遵循 rubric 中 `evidence_format` 模板 |
| `reasoning` | string | 是 | ≤3 句话的判定理由 |

## 决策映射

| blocking_count | warning_count | recommendation | gate 行为 |
|----------------|---------------|----------------|----------|
| > 0 | * | `block_phase_advance` | gate 拒绝放行 (fail-closed) |
| 0 | > 0 | `proceed_with_warnings` | gate 放行，warnings 进入 task envelope `prior_risks[]` |
| 0 | 0 | `proceed` | gate 放行，无注入 |

## 完整示例

```json
{
  "phase": 5,
  "rubric_version": 1,
  "requirement_type": "feat",
  "generated_at": "2026-04-18T10:30:00Z",
  "critic_agent_id": "critic-phase5-001",
  "scored_rubrics": [
    {
      "check_id": "P5-FEAT-001",
      "severity": "block",
      "passed": true,
      "evidence": "tests/test_foo.sh:42",
      "reasoning": "新增 foo() 在 test_foo.sh:42 处有断言覆盖"
    },
    {
      "check_id": "P5-FEAT-002",
      "severity": "block",
      "passed": false,
      "evidence": "src/bar.py:88",
      "reasoning": "src/bar.py:88 出现 TODO: handle edge case"
    }
  ],
  "blocking_count": 1,
  "warning_count": 0,
  "recommendation": "block_phase_advance"
}
```
