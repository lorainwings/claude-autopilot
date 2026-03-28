# Autopilot Plugin — 工程法则 (CLAUDE.md)

> 此文件为 spec-autopilot 插件的**单点事实来源 (Single Source of Truth)**。
> 所有 AI Agent（主线程 + 子 Agent）在执行期间**必须**遵守以下法则。

## 状态机跳变红线 (State Machine Hard Constraints)

1. **Phase 顺序不可违反**: Phase N 必须在 Phase N-1 checkpoint status ∈ {ok, warning} 后才能开始
2. **三层门禁联防**: L1 (TaskCreate blockedBy) + L2 (Hook 确定性验证) + L3 (AI Gate 8-step)，任一层阻断即阻断
3. **模式路径互斥**: `parallel.enabled = true` 必须走并行路径，`false` 走串行路径，禁止 AI 自主切换
4. **降级条件严格**: 仅合并失败 > 3 文件、连续 2 组失败、或用户显式选择时才允许降级
5. **Phase 4 不接受 warning**: Hook 确定性阻断，warning 强制覆盖为 blocked
6. **Phase 5 zero_skip_check**: `passed === true` 必须满足，否则阻断
7. **归档 fail-closed**: archive-readiness 通过时自动执行，任一检查项失败则硬阻断（fixup 不完整、anchor 无效、review blocking findings 未解决等）

## TDD Iron Law (仅 tdd_mode: true 时生效)

1. **先测试后实现**: RED 阶段仅写测试，GREEN 阶段仅写实现，违反即删除
2. **RED 必须失败**: `exit_code ≠ 0`，L2 Bash 确定性验证
3. **GREEN 必须通过**: `exit_code = 0`，L2 Bash 确定性验证
4. **测试不可变**: GREEN 失败时修复实现代码，禁止修改测试
5. **REFACTOR 回归保护**: 重构破坏测试 → 自动 `git checkout` 回滚

## 代码质量硬约束

1. **禁止 TODO/FIXME/HACK 占位符**: L2 Hook `unified-write-edit-check.sh` 确定性拦截 (v5.1, 原 banned-patterns-check.sh)
2. **禁止恒真断言**: L2 Hook `unified-write-edit-check.sh` 拦截 `expect(true).toBe(true)` 等 (v5.1, 原 assertion-quality-check.sh)
3. **Anti-Rationalization**: 10+6 种 excuse 模式匹配 → status 强制降级为 blocked (v5.2: +时间/环境/第三方借口)
4. **代码约束**: `code_constraints` 配置的 forbidden_files/patterns → L2 硬阻断
5. **Test Pyramid 地板**: unit_pct ≥ 30%, e2e_pct ≤ 40%, total ≥ 10 (L2 可配置)
6. **Change Coverage**: coverage_pct ≥ 80% (bugfix/refactor 路由可提升至 100%)
7. **Sad Path 比例**: sad_path_counts 每类型 ≥ test_counts 同类型 20% (v4.2)

## 需求路由 (v4.2)

需求自动分类为 Feature/Bugfix/Refactor/Chore，不同类别动态调整门禁阈值：

- **Bugfix**: sad_path ≥ 40%, change_coverage = 100%, 必须含复现测试
- **Refactor**: change_coverage = 100%, 必须含行为保持测试
- **Chore**: 放宽至 change_coverage ≥ 60%, typecheck 即可

## GUI Event Bus API (v4.2 Vanguard)

事件发射到 `logs/events.jsonl`，格式见 `references/event-bus-api.md`：

- `phase_start` / `phase_end`: Phase 生命周期
- `gate_pass` / `gate_block`: 门禁判定
- `task_progress`: Phase 5 任务细粒度进度 (v5.2)
- `decision_ack`: GUI 决策确认 (v5.2, WebSocket-only)
- 所有事件含 ISO-8601 时间戳 + phase 编号 + mode + payload

## 子 Agent 约束

1. **禁止自行读取计划文件**: 上下文由主线程提取注入
2. **禁止修改 openspec/ checkpoint**: L2 Hook `unified-write-edit-check.sh` 确定性阻断 (v5.1)，checkpoint 写入仅限 Bash 工具
3. **必须返回 JSON 信封**: `{"status": "ok|warning|blocked|failed", "summary": "...", "artifacts": [...]}`
4. **背景 Agent 产出必须 Write 到文件**: 返回信封仅含摘要，禁止全文灌入主窗口
5. **文件所有权 ENFORCED**: 并行模式下仅可修改 owned_files 范围内的文件
6. **背景 Agent 必须接受 L2 验证**: JSON 信封 + 反合理化检查不可绕过 (v5.1)
7. **Phase 1 上下文隔离**: 主线程禁止 Read 调研/BA 正文工件（research-findings.md、web-research-findings.md、requirements-analysis.md），仅消费 JSON 信封中的结构化字段
8. **Dispatch 审计**: dispatch 记录必须包含 selection_reason、resolved_priority、owned_artifacts，由 post-task-validator 验证
9. **Review findings fail-closed**: Phase 6.5 code review 中 `blocking: true` 的 findings 硬阻断 Phase 7 归档



