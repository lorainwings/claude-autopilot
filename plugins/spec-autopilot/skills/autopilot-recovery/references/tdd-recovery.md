# TDD 恢复逻辑

> 本文件由 `skills/autopilot-recovery/SKILL.md` 引用。定义 `config.phases.implementation.tdd_mode: true` 时 Phase 5 的 per-task TDD 恢复协议。

当 `config.phases.implementation.tdd_mode: true` 时，Phase 5 恢复需额外检查 per-task TDD 状态：

## TDD 恢复协议

1. 扫描 `phase5-tasks/task-N.json` 的 `tdd_cycle` 字段
2. 确定每个 task 的 TDD 阶段：

| tdd_cycle 状态 | 恢复点 |
|----------------|--------|
| 无 tdd_cycle | 从 RED 开始 |
| `red.verified = true`，无 `green` | 从 GREEN 恢复（测试文件已写好） |
| `green.verified = true`，无 `refactor` | 从 REFACTOR 恢复（当 `tdd_refactor: true`） |
| tdd_cycle 完整 | 下一个 task |

1. 恢复时：
   - 验证测试文件存在（GREEN/REFACTOR 恢复时）
   - 验证测试当前状态（运行测试命令确认）
   - 从正确的 TDD step 继续
