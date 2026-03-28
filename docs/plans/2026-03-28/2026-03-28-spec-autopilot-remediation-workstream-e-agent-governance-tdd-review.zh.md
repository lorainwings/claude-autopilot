# Workstream E: agent 治理、rules 解析、TDD 与 review 质量

日期: 2026-03-28
写入范围: rules/agent 选择、dispatch 记录、TDD 协议、review 结构化与门禁

## 1. 目标

修复以下治理缺口:

1. dispatch 需要可证明地遵守 rules、`CLAUDE.md`、agent 优先级。
2. 缺少 `.claude/agents` 时也要有确定性回退逻辑和证据记录。
3. TDD 不能停留在口头宣称，必须有 test intent 与前置 failing signal。
4. review findings 必须结构化并真实影响归档。

## 2. 必改文件

1. `plugins/spec-autopilot/runtime/scripts/rules-scanner.sh`
2. `plugins/spec-autopilot/runtime/scripts/auto-emit-agent-dispatch.sh`
3. `plugins/spec-autopilot/runtime/scripts/post-task-validator.sh`
4. `plugins/spec-autopilot/skills/autopilot/references/tdd-cycle.md`
5. `plugins/spec-autopilot/skills/autopilot/references/phase5-implementation.md`
6. `plugins/spec-autopilot/skills/autopilot/references/phase6-code-review.md`
7. 如有需要，可新增 dispatch/review schema 或 validator

## 3. 可建议但不直接修改的共享文件

1. `plugins/spec-autopilot/skills/autopilot/SKILL.md`
2. `plugins/spec-autopilot/CLAUDE.md`
3. `plugins/spec-autopilot/README.zh.md`

## 4. 必须落地的实现点

1. `rules-scanner.sh` 至少覆盖:
   - 仓库根 `CLAUDE.md`
   - `plugins/spec-autopilot/CLAUDE.md`
   - `.claude/rules`
   - `.claude/agents`
   - phase 局部规则
2. 缺少 `.claude/agents` 时，必须在 dispatch record 中明确写明缺失与回退依据
3. `agent-dispatch-record.json` 至少记录:
   - agent class
   - selection_reason
   - scanned_sources
   - resolved_priority
   - required validators
   - owned artifacts
   - fallback reason
4. TDD 结构至少包括:
   - `test-intent`
   - failing signal 或等价前置证据
   - implementation task pack
5. review findings 至少包括:
   - severity
   - evidence
   - blocking
   - owner
6. blocking review findings 未关闭时，archive 不得通过

## 5. 禁止走捷径

1. 禁止因为仓库里暂时没有 `.claude/agents` 就跳过优先级治理。
2. 禁止继续把 review 作为纯 advisory 展示项而不影响最终归档。
3. 禁止用“测试已通过”替代 TDD 的前置失败证据。
4. 禁止实现 agent 自己产出最终验收结论。

## 6. 必测项

至少新增或修订以下测试:

1. `plugins/spec-autopilot/tests/test_auto_emit_agent.sh`
2. `plugins/spec-autopilot/tests/test_tdd_isolation.sh`
3. `plugins/spec-autopilot/tests/test_phase65_bypass.sh`
4. `plugins/spec-autopilot/tests/test_phase6_independent.sh`
5. 新增 rules / agent priority enforcement 测试
6. 新增 review blocking -> archive blocked 黑盒

## 7. 完成定义

满足以下条件才算完成:

1. dispatch 可证明为什么选择该 agent。
2. rules / `CLAUDE.md` / agent priority 有真实扫描与回退逻辑。
3. TDD 与 review 形成可验证工件链。
4. review findings 的 blocking 项真实影响归档结果。

## 8. 交付给协调者的信息

请额外列出:

1. `agent-dispatch-record.json` 最终 schema
2. 需要同步到 Phase 7 / archive 的 review 状态字段
3. 需要写入 README / `CLAUDE.md` 的治理说明
