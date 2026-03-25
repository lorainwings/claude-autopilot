# spec-autopilot 多维度深度评审报告

> 评审日期: 2026-03-25 | 基线版本: v4.2.0+ | 评审范围: 10 个维度

## 评审总结

对 spec-autopilot 插件进行了 10 个维度的全面审计，共发现 **30+ 设计缺陷和优化点**，按优先级分为 P0(2)、P1(3)、P2(3)、P3(2) 四级。本次已实施 P0-P3 共 **9 项修复**。

## 已实施修复

### P0-Critical

| # | 问题 | 修复 | 修改文件 |
|---|------|------|---------|
| F1 | save-phase-context.sh 占位符 — SKILL.md Step 6.7 使用占位符文本而非实际信封内容 | 重写 Step 6.7 指令，明确要求从子 Agent JSON 信封提取 summary/decisions/constraints/artifacts/next_phase_context | `skills/autopilot/SKILL.md` |
| 3.2.1 | 压缩恢复依赖 AI 解析 — 恢复注入仅最新快照 + 无确定性指令 | 1) 注入所有阶段快照（4000字符总预算）2) 增加 `DETERMINISTIC RECOVERY INSTRUCTION` 区块 3) 快照截断从500→1000字符 | `scripts/reinject-state-after-compact.sh`, `scripts/save-state-before-compact.sh`, `references/guardrails.md` |

### P1-High

| # | 问题 | 修复 | 修改文件 |
|---|------|------|---------|
| 1.3 | 门禁路径硬编码 — get_predecessor_phase() 使用 case 语句 | 新增 `_phase_graph.py::get_predecessor()` + CLI命令，check-predecessor-checkpoint.sh 改为调用此函数（保留 TDD 运行时覆盖） | `scripts/_phase_graph.py`, `scripts/check-predecessor-checkpoint.sh` |
| 10.2.3 | fixup 完整性未检查 + 范围未验证 | Phase 7 归档前增加: 1) checkpoint数 vs fixup commit数对比 2) 非autopilot fixup提交检测 | `skills/autopilot-phase7/SKILL.md` |
| 9.2 | block_on_critical 语义不清 | 1) Phase 7 Step 3 归档前检查 critical findings 2) 修改选项为"忽略/修复/暂不归档" 3) 更新 Advisory Gate 文档 | `skills/autopilot-phase7/SKILL.md`, `skills/autopilot-gate/SKILL.md` |

### P2-Medium

| # | 问题 | 修复 | 修改文件 |
|---|------|------|---------|
| 4.2.1 | Phase 5 worktree 恢复 — 崩溃后代码状态不一致 | 1) recovery-decision.sh 增加 uncommitted_changes 检测 2) 恢复路径 A 增加 git diff 检查 + worktree 残留清理 | `scripts/recovery-decision.sh`, `skills/autopilot-recovery/SKILL.md` |
| 7.3 | 无断言测试检测缺失 | unified-write-edit-check.sh 新增 CHECK 3.5: 检测 JS/TS/Python/Java 中无断言的测试块 | `scripts/unified-write-edit-check.sh` |
| 8.1.1 | Phase 5 内部 CLAUDE.md 检测 — 串行模式 task 间不检测 | SKILL.md 串行模式增加每个 task dispatch 前的 CLAUDE.md mtime 检测 + rules 重扫 | `skills/autopilot/SKILL.md` |

### P3-Low

| # | 问题 | 修复 | 修改文件 |
|---|------|------|---------|
| 2.3 | 上下文使用率无监控 | SKILL.md Step 6.6 增加每阶段完成后输出 `[CTX]` 提示行 | `skills/autopilot/SKILL.md` |

## 未实施的评审发现（需后续跟进）

### 维度 1: 模式全流程仿真

- **1.1 lite 模式 Phase 1→5 上下文断裂**: Phase 1 在 lite/minimal 模式下应额外输出 `phase5-task-breakdown.md`。当前已有此文件路径支持（save-state-before-compact.sh:177），需确认 Phase 1 lite 模式是否实际产出。
- **1.2 minimal 模式 zero_skip_check**: 当前仅输出 WARNING，设计合理。建议在 Summary Box 中展示质量风险提示（已在 Phase 7 Summary Box 模式标注中部分覆盖）。
- **1.4 TDD+lite 行为**: 建议增加文档说明 lite+tdd_mode=true 时静默忽略 tdd_mode。
- **1.5 Phase 4 "不可跳过" 语义矛盾**: 建议修改文档措辞为"Phase 4 在非 TDD 模式下强制执行"。

### 维度 2: 主窗口信息分析

- **2.2 Phase 1 文档加载优化**: `phase1-requirements.md` ~280 行全部加载到主线程。建议拆分为核心协议(<100行) + 按需加载。
- **2.3.2 Skill 展开消耗**: gate/dispatch/recovery Skill 在主线程展开占用大量 Token。考虑将核心逻辑下沉为确定性脚本。
- **2.4 Phase 1 主线程合理性**: 设计合理（需 AskUserQuestion），但参考文档量偏大。

### 维度 3: 上下文压缩（已部分实施）

- **3.1.1 阶段内压缩**: 如果压缩发生在 Phase N 执行中（非阶段边界），恢复从 Phase N 重新开始。建议保存当前 Step 编号。
- **3.2.3 2000→4000 字符**: 已增大预算但仍有截断风险。复杂项目的完整决策链可能超限。

### 维度 4: 崩溃恢复（已部分实施）

- **4.2.2 上下文重建占位符**: 与 F1 同源，已通过 F1 修复解决。
- **4.2.3 多 Change 选择歧义**: recovery-decision.sh 已优先从锁文件读取 change，设计合理。
- **4.2.4 fixup commits 回退**: clean-phase-artifacts.sh 执行 git 回退前应验证不丢失 fixup commits。

### 维度 5: 需求评审

- **5.1 三路调研增量检测**: Auto-Scan 与技术调研内容可能重叠。建议增加增量检测。
- **5.2 需求模板化**: 提供 PRD 模板引导用户提供完整信息。
- **5.3 scope creep 全复杂度检查**: 当前仅 Large 复杂度做 scope creep 检查，建议扩展到所有级别。

### 维度 6: OpenSpec FF

- **6.1 Phase 3 文件完整性**: 建议 Phase 3 子 Agent 执行前验证 prd.md 等文件非空。
- **6.2 Phase 3 模型升级**: Haiku 模型生成 tasks.md 粒度可能不足，考虑升级为 Sonnet。
- **6.3 change 命名冲突**: Phase 2 子 Agent 应检测并自动处理。

### 维度 7: 测试用例（已部分实施）

- **7.1 traceability L2 检查**: `traceability_floor ≥ 80%` 目前在 L3 AI 层验证，建议迁移到 L2 Hook。
- **7.2 测试顺序随机化**: 建议 Phase 6 增加 `--shuffle` 选项。
- **7.3.2 过度 mock 检测**: testing-anti-patterns.md 有描述但无自动检测。
- **7.3.3 测试名称一致性**: 难以自动检测，依赖 Phase 6.5 代码审查。

### 维度 8: 代码实现规则

- **8.2 Agent 优先级文档**: 建议文档说明 autopilot dispatch agent 名称与 `.claude/agents/` 的关系。
- **8.3 代码风格一致性**: 建议增加与项目现有代码风格的 linter 对比检查。

### 维度 9: TDD 代码生成

- **9.1 并行 TDD L2 拦截**: 并行 TDD 缺乏 worktree 内的 `.tdd-stage` Hook 级约束。建议域 Agent prompt 注入 `.tdd-stage` 写入。
- **9.3 GREEN hack 检测**: 实现可能用硬编码返回值通过测试。建议 REFACTOR 阶段增加代码质量检查。

### 维度 10: fixup 合并（已部分实施）

- **10.2.2 rebase 冲突辅助**: 提供辅助命令帮助用户逐个 squash。
- **10.2.4 anchor SHA 重建诊断**: rebuild 失败时提供更详细的诊断信息。

### 交叉发现

- **F2 后台 Agent 超时级联**: 超时标记 timeout 但不检查操作是否完成。影响 fixup 完整性和恢复完整性。
- **F3 确定性 vs AI 检查边界**: 部分 L2 应做的检查（如 traceability 覆盖率）仍在 L3。

## 测试验证

所有修改通过以下测试:
- `_phase_graph.py --test`: 25/25 passed（含 8 个新增 get_predecessor 测试）
- `test_phase_graph_consistency.sh`: 11/11 passed
- `test_predecessor_checkpoint.sh`: 7/7 passed
- `test_phase_context_snapshot.sh`: 8/8 passed
- `test_unified_write_edit.sh`: 31/31 passed

## 修改文件清单

| 文件 | 修改类型 |
|------|---------|
| `skills/autopilot/SKILL.md` | Step 6.7 占位符修复 + Phase 5 串行 CLAUDE.md 检测 + Step 6.6 上下文监控 |
| `scripts/reinject-state-after-compact.sh` | 全快照注入 + 确定性恢复指令 |
| `scripts/save-state-before-compact.sh` | 快照截断扩大 500→1000 |
| `scripts/check-predecessor-checkpoint.sh` | get_predecessor_phase() 改为调用 _phase_graph.py |
| `scripts/_phase_graph.py` | 新增 get_predecessor() + CLI命令 + 自测 |
| `scripts/recovery-decision.sh` | 增加 uncommitted_changes 检测 |
| `scripts/unified-write-edit-check.sh` | 新增 CHECK 3.5 无断言测试检测 |
| `skills/autopilot-phase7/SKILL.md` | fixup 完整性检查 + block_on_critical 语义 |
| `skills/autopilot-gate/SKILL.md` | Advisory Gate 语义澄清 |
| `skills/autopilot-recovery/SKILL.md` | worktree 恢复一致性检查 |
| `references/guardrails.md` | 压缩恢复协议更新 |
