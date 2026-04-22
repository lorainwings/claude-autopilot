# Phase 4-6 通用调度循环模板

对于 Phase N（N ∈ {4, 5, 6}），在**主线程**中执行以下步骤。

## Contents

- 循环步骤
- Step 约束要点

## 循环步骤

```
Step -1: 恢复跳过前置检查
        → 当 recovery_phase 已设定时：N < recovery_phase 跳过；
          N == recovery_phase 从该阶段开始恢复；N > recovery_phase 正常执行
        → 跳过的 Phase 不发射 phase_start/phase_end 事件
Step -0.5: GUI 健康检查（自动恢复，端口透传）
        # gui_ws_port = gui_port + 1（由 Phase 0 注入）
        → Bash('AUTOPILOT_HTTP_PORT={gui_port} AUTOPILOT_WS_PORT=${gui_ws_port} bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/start-gui-server.sh --check-health')
Step 0: 发射 Phase 开始事件 → emit-phase-event.sh phase_start {N} {mode}
Step 1: 调用 Skill("spec-autopilot:autopilot-gate")
        → 执行 8 步阶段切换检查清单（验证 Phase N-1 checkpoint）
        → Gate 通过/阻断后发射对应事件 + 进度写入；阻断时启动决策轮询（双向反控）
Step 1.5: 可配置用户确认点（仅 after_phase_{N} === true 时生效，默认全部 false；else 分支直接跳过 Step 1.5 进入 Step 2）
Step 2: 调用 Skill("spec-autopilot:autopilot-dispatch")
        → 按协议构造 Task prompt（注入 instruction_files、reference_files）
Step 3: Task 工具派发子 Agent（prompt 开头需 <!-- autopilot-phase:N --> 标记）
        → Hook 脚本自动校验前置 checkpoint 与返回 JSON
        → auto-emit-agent-dispatch / auto-emit-agent-complete 自动发射生命周期事件
Step 4: 解析子 Agent JSON 信封
        → ok → 继续 | warning → 继续（Phase 4 例外）| blocked/failed → 暂停
Step 4.7: GUI 周期性健康检查（Phase 5 长任务保活）
Step 5+7: 后台 Checkpoint Agent（原子写入 + 状态隔离）
Step 6: TaskUpdate Phase N → completed
Step 6.5: 发射 Phase 结束事件
Step 6.6: 上下文使用率提示（压缩预警）
Step 6.7: 调用 save-phase-context.sh，参数从子 Agent JSON 信封提取（next_phase / status / summary）
Step 8: 等待 Step 5+7 后台 Agent 完成通知 → 立即继续下一 Phase
```

## Step 约束要点

- Checkpoint 写入**必须使用 Bash 工具**（非 Write 工具）
- **必须使用 `git add -A`**（自动尊重 .gitignore）
- **禁止显式 `git add` 锁文件 `.autopilot-active`**
- Step 4 的 warning 在 Phase 4 会被门禁覆盖为 blocked（详见 autopilot-gate 特殊门禁）
