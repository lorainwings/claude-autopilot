# 常见问题排查

> Top 10 常见错误场景和修复步骤。

## 1. Hook 阻断：test_pyramid floor violation

**错误信息**:
```json
{"decision": "block", "reason": "Phase 4 test_pyramid floor violation (Layer 2): unit_pct=20% < 30% floor"}
```

**原因**: 单元测试占比低于 Hook 底线阈值。

**修复**:
1. 检查 Phase 4 返回的 `test_pyramid` 字段
2. 增加单元测试用例直到占比 ≥ 30%
3. 如需调整阈值，修改 `.claude/autopilot.config.yaml`:
   ```yaml
   test_pyramid:
     hook_floors:
       min_unit_pct: 20  # 降低底线
   ```

## 2. Hook 阻断：Anti-rationalization check

**错误信息**:
```json
{"decision": "block", "reason": "Anti-rationalization check: Phase 5 output scored 5 (threshold 5)"}
```

**原因**: 子 Agent 输出中检测到跳过/延后模式（如 "skipped because"、"deferred to later"）。

**修复**: 这通常意味着子 Agent 未完成应有的工作。系统会自动重新派发该阶段。如果多次触发，检查需求是否过于复杂需要拆分。

## 3. Hook 阻断：zero_skip_check failed

**错误信息**:
```json
{"decision": "block", "reason": "Phase 5 zero_skip_check gate failed. All tests must pass with zero skips."}
```

**原因**: Phase 5 实施后仍有测试被跳过或失败。

**修复**:
1. 检查 `phase-5-implement.json` 中的 `zero_skip_check` 字段
2. 找到失败/跳过的测试并修复
3. 确保所有测试都通过后重新提交

## 4. 崩溃恢复：中途断开后如何继续

**场景**: autopilot 运行中断（网络断开、进程崩溃、手动关闭）。

**修复**: 直接重新运行 `/autopilot`。系统会：
1. 扫描 `openspec/changes/<name>/context/phase-results/` 下的 checkpoint
2. 找到最后一个 `status: ok` 的阶段
3. 从下一个阶段继续执行

Phase 5 支持 task 级恢复：即使在 task 3/10 中断，也能从 task 3 继续。

## 5. 配置验证失败：missing_keys

**错误信息**:
```json
{"valid": false, "missing_keys": ["phases.testing.agent"]}
```

**修复**: 在 `.claude/autopilot.config.yaml` 中补全缺失的字段。参考 `references/config-schema.md` 获取完整模板。

或重新运行 `/autopilot-init` 重新生成配置。

## 6. Phase 4 阻断：change_coverage insufficient

**错误信息**:
```json
{"decision": "block", "reason": "Phase 4 change_coverage insufficient: 33% < 80% threshold"}
```

**修复**: Phase 4 设计的测试未覆盖足够的变更点。增加针对未覆盖变更点的测试用例。

## 7. 锁文件冲突：另一个 autopilot 正在运行

**场景**: 启动时检测到 `.autopilot-active` 锁文件属于另一个进程。

**修复**: 系统会提示选择：
- **覆盖并继续**（推荐）：如果之前的进程已经不在运行
- **中止当前运行**：如果确实有另一个 autopilot 在运行

## 8. 上下文压缩后状态丢失

**场景**: Claude Code 自动压缩上下文后，autopilot 似乎忘记了进度。

**说明**: 这由 PreCompact + SessionStart(compact) Hook 自动处理。如果看到 `=== AUTOPILOT STATE RESTORED ===` 标记，说明恢复成功。

如果恢复失败，手动检查 `context/autopilot-state.md` 文件是否存在。

## 9. Phase 5 超时

**错误信息**:
```json
{"permissionDecision": "deny", "permissionDecisionReason": "Phase 5 wall-clock timeout"}
```

**修复**: 增加超时配置：
```yaml
phases:
  implementation:
    wall_clock_timeout_hours: 4  # 从默认 2h 增加到 4h
```

## 10. test_traceability 阻断（v4.0 新增）

**错误信息**:
```json
{"decision": "block", "reason": "Phase 4 test_traceability coverage 50% < 80% floor"}
```

**原因**: 测试用例未充分追溯到 Phase 1 需求。

**修复**:
1. 检查 Phase 4 返回的 `test_traceability.coverage_pct`
2. 为每个测试用例添加 requirement 映射
3. 如需调整阈值：
   ```yaml
   test_pyramid:
     traceability_floor: 60  # 降低到 60%
   ```
