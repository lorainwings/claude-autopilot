# 全模式稳定性与链路闭环审计报告

> 审计日期: 2026-03-17
> 审计版本: spec-autopilot `v5.1.20`
> 工作目录: `plugins/spec-autopilot`

## 执行摘要

本次审计以 `full`、`lite`、`minimal` 三种模式的状态机、门禁链路、文件 IO 与收口路径为核心。结论是: 主状态机与并行合并守卫已经达到可依赖水平，但“阶段上下文持久化”与“构建分发闭环”存在真实断点，因此本次稳定性评级为 **81/100**。

- 强项:
  - 模式路由正确，`full/lite/minimal` 的 phase 序列与前驱门禁均通过实测。
  - `parallel-merge-guard.sh` 对 `anchor_sha` 与越界文件有稳定阻断能力。
  - `collect-metrics.sh` 当前按最新 `mtime` 取 checkpoint，历史静默污染点已被修复。
- 主要问题:
  - `save-phase-context.sh` 与 `write-phase-progress.sh` 在当前仓库布局下会“成功退出但不落盘”。
  - `build-dist.sh` 依赖 GUI 构建成功；当前 `bun + vite` 组合会直接失败，导致分发链路中断。
  - 遗留 `anti-rationalization-check.sh` 仍有失败测试，说明遗留脚本与现行合并验证器存在漂移。

## 实测基线

执行命令与结果:

```bash
bash tests/run_all.sh test_minimal_mode test_lite_mode test_mode_lock test_parallel_merge test_phase7_predecessor integration/test_e2e_checkpoint_recovery
```

结果: `35 passed / 0 failed`

```bash
bash tests/run_all.sh test_collect_metrics test_phase_progress test_build_dist test_common_unit test_clean_phase_artifacts test_phase_context_snapshot
```

结果: `81 passed / 9 failed`

## 模式状态机审计

### Full

- `integration/test_e2e_checkpoint_recovery.sh` 验证序列为 `1 2 3 4 5 6 7`。
- `test_mode_lock.sh` 验证 `Phase 2 <- 1`、`Phase 6 <- 5`、`Phase 7 <- 6` 均正确受控。
- 结论: `full` 主链路状态机正确。

### Lite

- `test_lite_mode.sh` 验证 `Phase 5 -> 6 -> 7` 可通。
- `integration/test_e2e_checkpoint_recovery.sh` 验证 lite 序列为 `1 5 6 7`。
- 结论: lite 跳过 `2/3/4` 的逻辑稳定。

### Minimal

- `test_minimal_mode.sh` 验证 `Phase 5 -> 7` 可通，`Phase 6` 会被 deny。
- `test_mode_lock.sh` 验证 minimal 下 `Phase 7 <- 5` 正常，`Phase 6` 禁止进入。
- 结论: minimal 收敛路径稳定。

## 文件 IO 与恢复链路

### 已验证正常

- `test_common_unit.sh`: checkpoint 扫描、前驱判定、模式感知均通过。
- `test_clean_phase_artifacts.sh`: phase 清理、事件过滤、stash 恢复均通过。
- `test_collect_metrics.sh`: 最新 checkpoint 选择逻辑正确。

### 真实断点

#### P1: Phase Context Snapshot 静默失效

`test_phase_context_snapshot.sh` 失败，进一步用 `bash -x scripts/save-phase-context.sh ...` 追踪后确认:

- 脚本通过 `git rev-parse --show-toplevel` 将 `PROJECT_ROOT` 解析为 `plugins/spec-autopilot`
- 测试与真实工作区约定的 `openspec/changes` 位于仓库根 `/Users/lorain/Coding/Huihao/claude-autopilot`
- 结果是脚本命中不存在的 `plugins/spec-autopilot/openspec/changes`，随后 `exit 0`

影响:

- Phase 上下文快照无法落盘
- 压缩恢复与人工审计缺少阶段摘要
- 问题是“静默成功”，比显式报错更危险

#### P1: Phase Progress Tracking 静默失效

`test_phase_progress.sh` 与上面同源: `write-phase-progress.sh` 使用相同根目录解析策略，导致进度文件不创建，但仍返回 `0`。

影响:

- GUI 与恢复逻辑缺少细粒度 phase 内进度
- “正在进行/已派发/已收敛”这类状态无法可靠回放

## Merge 与收口审计

- `test_parallel_merge.sh`: `anchor_sha` 正常、非法、缺失三种场景都能检测越界文件；scope 内文件可通过。
- `test_phase7_predecessor.sh`: `Phase 7` 不依赖 `6.5`，只依赖 `6`，符合当前协议。

结论: 并行收口正确性高于分发构建稳定性，当前主要风险不在 merge，而在“构建/发布前链路”。

## 构建与分发

`test_build_dist.sh` 失败的根因已展开验证:

```bash
bun run build --mode production
```

失败信息:

```text
TypeError: crypto$2.getRandomValues is not a function
```

这会导致:

- `build-dist.sh` 在 GUI 构建阶段提前退出
- dist 不生成最新运行时内容
- `collect-metrics.sh` 缺失是构建中断的后果，而非当前白名单逻辑错误

但同一测试也证明:

- 当 `gui/node_modules` 不可用、走“使用已提交 `gui-dist/`”回退路径时，构建可成功
- 回退路径下 `collect-metrics.sh` 能正确进入 dist

结论: 这是“首选构建路径不可用，回退路径可用”的稳定性问题。

## 兼容性与遗留漂移

`test_anti_rationalization.sh` 失败，但当前主钩子已经合并到 `post-task-validator.sh` / `_post_task_validator.py`。这说明:

- 主执行链路并未因此失效
- 但遗留脚本、测试预期、实际门禁策略已出现漂移

风险在于:

- 维护者容易误判真实生效的门禁位置
- 文档与脚本表面积继续扩大会放大认知成本

## 结论与优先级

### 评级

| 维度 | 结论 |
|---|---|
| 状态机控制 | 强 |
| 并行 merge | 强 |
| 恢复与阶段快照 | 弱 |
| 构建与分发 | 中低 |
| 遗留一致性 | 中 |

### 优先级建议

1. 统一 `PROJECT_ROOT` 解析策略，显式支持“插件子目录 + 仓库根 openspec”的布局。
2. 修复 GUI 构建链路或在 `build-dist.sh` 中加入受控自动回退，而不是直接失败。
3. 清理或彻底标注遗留脚本，避免 `anti-rationalization-check.sh` 这类“未上链但仍被测试”的漂移。

