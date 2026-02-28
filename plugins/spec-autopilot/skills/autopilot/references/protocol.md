# Autopilot 共享协议参考

> 此文件被 autopilot-dispatch、autopilot-gate、autopilot-checkpoint 共同引用。修改时需同步评估影响。

## JSON 信封契约

每个子 Agent **必须**返回此格式：

```json
{
  "status": "ok | warning | blocked | failed",
  "summary": "单行决策级摘要",
  "artifacts": ["已创建/修改的文件路径"],
  "risks": ["可选风险列表"],
  "next_ready": true
}
```

写入 checkpoint 时自动追加 `timestamp`（ISO-8601）和 `phase`（阶段编号）字段。

## 各阶段额外返回字段

| Phase | 必须字段 | 可选字段 |
|-------|----------|----------|
| 1 | `requirements_summary`, `decisions: [{point, choice}]`, `change_name` | `open_questions` |
| 4 | `test_counts: { unit, api, e2e, ui }`, `dry_run_results: { unit, api, e2e, ui }`, `test_pyramid: { total, unit_pct, integration_pct, e2e_pct }` | — |
| 5 | `test_results_path`, `tasks_completed`, `zero_skip_check: { passed: bool }` | `iterations_used` |
| 6 | `pass_rate`, `report_path`, `report_format` | `report_url`, `allure_results_dir` |

## 状态解析规则

| status | 主线程行为 |
|--------|-----------|
| ok | 写入 checkpoint，继续下一阶段 |
| warning | 写入 checkpoint，展示警告后继续（**Phase 4 例外**） |
| blocked | 暂停，展示给用户，要求排除阻塞 |
| failed | 暂停，展示给用户，可能需要重新执行本阶段 |

**Phase 4 特殊规则**：不接受 warning。warning 且 test_counts < 门禁阈值 → 强制覆盖为 blocked。

## 结构化标记（Hook 识别依据）

子 Agent prompt **开头第一行**必须包含：

```
<!-- autopilot-phase:{phase_number} -->
```

无标记的 Task 调用被 Hook 直接放行（exit 0）。

## Checkpoint 文件命名

```
phase-results/
├── phase-1-requirements.json
├── phase-2-openspec.json
├── phase-3-ff.json
├── phase-4-testing.json
├── phase-5-implement.json
└── phase-6-report.json
```

## 特殊门禁

### Phase 4 → Phase 5

- `test_counts` 每个字段 ≥ `config.phases.testing.gate.min_test_count_per_type`
- `test_pyramid` 比例符合 `config.test_pyramid` 约束（unit_pct ≥ 50%）
- `artifacts` 非空
- `dry_run_results` 全部为 0

### Phase 5 → Phase 6

- `test-results.json` 存在
- `zero_skip_check.passed === true`
- `tasks.md` 中所有任务标记为 `[x]`
