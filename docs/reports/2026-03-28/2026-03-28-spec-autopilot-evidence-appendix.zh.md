# spec-autopilot 评审附录：测试与证据矩阵

对应主报告:
- `docs/reports/2026-03-28-spec-autopilot-holistic-review.zh.md`

## 1. 测试执行记录

执行命令:

```bash
bash plugins/spec-autopilot/tests/run_all.sh
```

执行结果:
- `91 files / 1003 passed / 0 failed`

解释:
- 说明当前仓库在脚本层、Hook 层、部分集成层没有立即可见的回归。
- 不说明产品闭环已经满足你的目标，因为其中有一部分测试验证的是协议文本、SKILL 文档或脚本局部行为，不是完整的人机交互编排。

## 2. 模式仿真矩阵

| 模式 | 预期 phase 序列 | 代码实现 | 测试证据 | 评语 |
|------|------------------|----------|----------|------|
| full | 1→2→3→4→5→6→7 | 一致 | `tests/integration/test_e2e_checkpoint_recovery.sh` / `check-predecessor-checkpoint.sh` | 主干稳定，Phase 1 是主要风险区 |
| lite | 1→5→6→7 | 一致 | `tests/test_lite_mode.sh` | 自动化更快，但证据链更短 |
| minimal | 1→5→7 | 一致 | `tests/test_minimal_mode.sh` | 最轻量，但最弱可审计 |

## 3. 证据矩阵

### A. 自动化默认被中断

| 结论 | 证据 |
|------|------|
| `after_phase_1` 默认开启确认 | `plugins/spec-autopilot/README.zh.md:248-252` |
| Phase 1 结束后仍存在可配置确认点 | `plugins/spec-autopilot/skills/autopilot/SKILL.md:186` |
| Phase 7 归档仍然强依赖 AskUserQuestion | `plugins/spec-autopilot/skills/autopilot-phase7/SKILL.md:104-122` |

### B. Phase 1 存在上下文污染风险

| 结论 | 证据 |
|------|------|
| 主协议要求主线程不读全文 | `plugins/spec-autopilot/skills/autopilot/SKILL.md:146-171` |
| 并行协议却写明主线程合并 research 文件内容 | `plugins/spec-autopilot/skills/autopilot/references/parallel-phase1.md:81` |
| Phase 1 research / BA 任务不带 `autopilot-phase` marker | `plugins/spec-autopilot/skills/autopilot-dispatch/SKILL.md:258-287` |

### C. 上下文恢复是摘要回灌，不是完整恢复

| 结论 | 证据 |
|------|------|
| 每个 phase snapshot 只保留前 1000 字符 | `plugins/spec-autopilot/runtime/scripts/save-state-before-compact.sh:157-171` |
| reinject 时总 snapshot 字符数再限制为 4000 | `plugins/spec-autopilot/runtime/scripts/reinject-state-after-compact.sh:64-99` |
| 恢复指令是自然语言步骤，不是结构化 replay | `plugins/spec-autopilot/runtime/scripts/reinject-state-after-compact.sh:103-129` |
| SessionStart 还会额外注入 checkpoint summary | `plugins/spec-autopilot/runtime/scripts/scan-checkpoints-on-start.sh:77-197` |

### D. fixup 合并不是 fail-closed

| 结论 | 证据 |
|------|------|
| fixup 数量小于 checkpoint 数量仅 warning | `plugins/spec-autopilot/skills/autopilot-phase7/SKILL.md:135-144` |
| anchor 无效时允许跳过 autosquash 继续归档 | `plugins/spec-autopilot/skills/autopilot-phase7/SKILL.md:151-160` |

### E. 背景 agent 的 L2 闭环不完全

| 结论 | 证据 |
|------|------|
| 统一 validator 已要求 background task 完成后校验 | `plugins/spec-autopilot/runtime/scripts/post-task-validator.sh:22-35` |
| 旧脚本仍对 background agent bypass | `plugins/spec-autopilot/runtime/scripts/validate-json-envelope.sh:22-30` |
| 旧脚本仍对 background agent bypass | `plugins/spec-autopilot/runtime/scripts/anti-rationalization-check.sh:24-33` |
| 旧脚本仍对 background agent bypass | `plugins/spec-autopilot/runtime/scripts/code-constraint-check.sh:17-24` |
| 仓库测试把 bypass 当成预期 | `plugins/spec-autopilot/tests/test_background_agent_bypass.sh:20-55` |
| 但 `CLAUDE.md` 声称 background agent 必须接受 L2 验证 | `plugins/spec-autopilot/CLAUDE.md:57-59` |

### F. Phase 6.5 代码审查不是硬门禁

| 结论 | 证据 |
|------|------|
| Phase 6.5 没有 phase marker，校验器跳过 | `plugins/spec-autopilot/tests/test_phase65_bypass.sh:12-24` |
| Phase 6 不依赖 6.5 findings/metrics | `plugins/spec-autopilot/tests/test_phase6_independent.sh:12-17` |
| Phase 7 明确把 code review 作为 advisory | `plugins/spec-autopilot/skills/autopilot-phase7/SKILL.md:46-88` |

### G. 测试存在“文档即真相”的风险

| 结论 | 证据 |
|------|------|
| fixup 测试直接 grep `SKILL.md` | `plugins/spec-autopilot/tests/test_fixup_commit.sh:12-19` |
| search policy 测试前半段直接 grep 文档 | `plugins/spec-autopilot/tests/test_search_policy.sh:18-55` |

### H. `.claude` 多 agent 优先级当前无法保证

| 结论 | 证据 |
|------|------|
| rules-scanner 只扫 `.claude/rules/` 和 `CLAUDE.md` | `plugins/spec-autopilot/runtime/scripts/rules-scanner.sh:12-19` |
| rules-scanner 不感知 `.claude/agents` 之类 agent 注册 | `plugins/spec-autopilot/runtime/scripts/rules-scanner.sh:46-154` |
| runtime 只能审计 `subagent_type`，不能验证优先级策略 | `plugins/spec-autopilot/runtime/scripts/auto-emit-agent-dispatch.sh:126-155` |

## 4. GUI 现状与建议对照

### 当前主窗口展示

| 区域 | 当前内容 | 文件 |
|------|----------|------|
| Header | change / session / mode / connected | `plugins/spec-autopilot/gui/src/App.tsx:145-166` |
| 左侧 | phase 节点 + 总耗时 + 阶段数 + 门禁数 | `plugins/spec-autopilot/gui/src/components/PhaseTimeline.tsx:43-125` |
| 中间 | agent 卡片 / tool count / output files | `plugins/spec-autopilot/gui/src/components/ParallelKanban.tsx:128-240` |
| 右侧 | model / cwd / cost / worktree / transcript / gate stats / phase durations | `plugins/spec-autopilot/gui/src/components/TelemetryDashboard.tsx:73-206` |

### 我建议主窗口真正优先的内容

| 优先级 | 建议内容 | 当前是否具备 |
|--------|----------|--------------|
| P0 | 当前目标摘要 | 否 |
| P0 | 当前 phase / sub-step / next action | 部分 |
| P0 | gate frontier 与阻断证据 | 部分 |
| P0 | 活跃 agent 的 owned_files / domain | 否 |
| P1 | recovery source / checkpoint / anchor 状态 | 否 |
| P1 | context budget / compact 风险 | 否 |
| P2 | cwd / transcript_path / worktree | 具备，但应降级到调试面板 |

## 5. 建议的验收补测

如果下一轮要做整改，我建议至少补以下黑盒测试:

1. `Phase 1 不污染主窗口上下文`
- 判定标准: 调研 agent 结束后，主线程只消费 JSON facts，不补写产出文件，不读取 research 全文

2. `after_phase_1=false 时 full 模式全自动贯通`
- 判定标准: 从需求确认结束到 Phase 7 前无额外确认弹窗

3. `恢复前后 requirement packet hash 一致`
- 判定标准: 压缩前后的 canonical requirement packet 完全一致

4. `fixup completeness fail-closed`
- 判定标准: checkpoint 数量与 fixup 数量不匹配时，Phase 7 blocked

5. `phase6.5 review truly blocks archive`
- 判定标准: critical review finding 未清理时，归档不可达

6. `agent policy priority enforced`
- 判定标准: 配置多个 agent 优先级后，dispatch 若使用错误 agent，必须被阻断或告警

## 6. 附录结论

全量测试通过说明:
- 这不是一个“随便拼出来”的插件。

但证据矩阵同样说明:
- 当前主要问题已经不是脚本是否能跑，而是系统是否真的把产品要求落成了确定性控制。
