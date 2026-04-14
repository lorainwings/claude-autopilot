# Gate 特殊门禁规则

> 本文件从 `autopilot-gate/SKILL.md` 提取，供特定 Phase 切换时按需读取。

## 特殊门禁：Phase 4 → Phase 5

除通用 8 步校验外，额外验证（从 `autopilot.config.yaml` 读取阈值）：

**非 TDD 模式**（`tdd_mode: false` 或未设置）：

```
- [ ] phase-4-testing.json 中 test_counts 的每个字段 ≥ config.phases.testing.gate.min_test_count_per_type
- [ ] artifacts 列表中包含 config.phases.testing.gate.required_test_types 对应的文件
- [ ] dry_run_results 的所有字段全部为 0（exit code）
```

**TDD 模式**（`tdd_mode: true` 且模式为 `full`）：

```
- [ ] phase-4-tdd-override.json 存在且 tdd_mode_override === true
- [ ] 跳过 test_counts / dry_run 验证（测试在 Phase 5 per-task 创建）
```

任何条件不满足 → 阻断 Phase 5，要求重新执行 Phase 4。

## 特殊门禁：Phase 5 → Phase 6

除通用 8 步校验外，额外验证：

```
- [ ] test-results.json 存在
- [ ] zero_skip_check.passed === true
- [ ] tasks.md 中所有任务标记为 [x]
```

**TDD 模式额外验证**（当 `tdd_mode: true`）：

```
- [ ] tdd_metrics 存在
- [ ] tdd_metrics.red_violations === 0（零 RED 违规）
- [ ] 每个 task 的 tdd_cycle 完整（red + green 都 verified）
```

任何条件不满足 → **full 模式**阻断 Phase 6；**lite/minimal 模式**降级为 warning（记录但不阻断）。

## TDD 完整性审计（L3 层保障）

当 `tdd_mode: true` 时，Phase 5→6 门禁执行额外的 TDD 审计：

1. 扫描所有 `phase5-tasks/task-N.json` 文件
2. 验证每个 task 包含 `tdd_cycle` 字段
3. 验证 `tdd_cycle.red.verified === true` 和 `tdd_cycle.green.verified === true`
4. 记录 `refactor_reverts` 总数（允许 > 0，仅审计记录）
5. 汇总为 `tdd_audit` 输出：

   ```json
   {
     "total_tasks": 10,
     "tdd_complete": 10,
     "red_violations": 0,
     "refactor_reverts": 1,
     "audit_passed": true
   }
   ```

6. `audit_passed === false` → 阻断 Phase 6（full 模式硬门禁）

> **模式降级说明**: lite/minimal 模式下，若 `audit_passed === false`，降级为 warning（不阻断 Phase 6），
> 因为这两种模式跳过了 Phase 2-4，TDD 覆盖不完整属于预期行为。full 模式下始终硬阻断。

## Phase 6.5 代码审查门禁（可选，三路并行）[Advisory Gate — 不阻断 Phase 7]

当 `config.phases.code_review.enabled = true` 时，Phase 7 步骤 2.a 收集代码审查结果后检查：

```
- [ ] phase-6.5-code-review.json 存在（由 Phase 7 步骤 2.a 写入——ok/warning/blocked 三种状态均写入 checkpoint）
- [ ] 当 block_on_critical = true 且 findings 中 critical 数量 > 0 时：标记需用户确认（Phase 7 Step 3 展示并要求用户显式选择忽略/修复/暂停，不自动阻断）
- [ ] status 为 "ok" 或 "warning"（blocked 状态下用户选择"忽略继续归档"时，Phase 7 Step 2.a 已将 status 降级为 warning 并标记 user_override: true）
```

当 `code_review.enabled = false` 时，**跳过此门禁**，不要求 checkpoint 存在。

Phase 6.5 是可选步骤，不影响 Layer 1（TaskCreate blockedBy）和 Layer 2（Hook predecessor check）。
Phase 6.5 与 Phase 6 **并行执行**（三路并行），其结果在 Phase 7 汇合点收集。

> **Advisory Gate 语义**: Phase 6.5 是建议性旁路门禁（Advisory Gate），其 blocked 状态
> 不阻止 Phase 7 的 predecessor 条件（L2 Hook 不检查 6.5 checkpoint）。Phase 7 收集 6.5 结果后展示 findings。
> **block_on_critical 行为**: 当 `config.phases.code_review.block_on_critical = true` 时，Phase 7 Step 3
> 会在归档前检查是否存在 critical findings——如有，archive readiness 判定为 blocked 并向用户展示，
> 要求显式确认是忽略还是修复（用户有最终决策权）。
