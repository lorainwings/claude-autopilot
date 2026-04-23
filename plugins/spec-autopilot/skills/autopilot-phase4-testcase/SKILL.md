---
name: autopilot-phase4-testcase
description: "Use when the autopilot orchestrator enters Phase 4 to design test cases. Applies after Phase 3 alignment with tasks.md ready; gates Phase 5 dispatch."
user-invocable: false
---

# Autopilot Phase 4 — 测试用例设计

> **前置条件自检**：本 Skill 仅在 autopilot 编排主线程中使用。如果当前上下文不是 autopilot 编排流程，请立即停止并忽略本 Skill。

> **派发铁律**：主线程**必须**通过 `Task(subagent_type=autopilot-phase4-testcase)` 派发本协议；**严禁**主线程自行设计测试用例、自行 Read 业务源码归纳测试矩阵。Skill 加载仅用于注入协议，真正的用例设计在子 Agent 中执行。

Phase 4 在 full 模式下执行测试用例设计，具有特殊的 TDD 跳过逻辑和严格门禁规则。

**执行前读取**: 参见 autopilot skill 的 parallel-phase4 章节（由编排主线程已加载，子 SKILL 无需重复读取）+ 详见 autopilot skill 的 protocol 文档（特殊门禁定义）

## TDD 模式跳过（确定性检测）

**必须执行确定性 Bash 检测**（禁止依赖 AI 记忆判断配置值）：

```bash
TDD_RESULT=$(bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/check-tdd-mode.sh)
```

> 脚本自动解析项目根目录（`$AUTOPILOT_PROJECT_ROOT` > `git rev-parse` > `$PWD`），无需手动传参。

根据 `TDD_RESULT` 值分路：

- **`TDD_SKIP`**（`tdd_mode: true` 且 `mode: full`）：
  - Phase 4 标记为 `skipped_tdd`
  - 写入 `phase-4-tdd-override.json` checkpoint：`{"status":"ok","tdd_mode_override":true}`
  - 直接跳转 Phase 5（不执行 dispatch）
- **`TDD_DISPATCH`**（非 TDD 模式）：
  - 正常 dispatch 测试用例设计 Agent（见下方"非 TDD 模式"章节）

## 非 TDD 模式

正常 dispatch，并行模式按测试类型分组。

**执行位置**: Task 子 Agent

- `Agent name`：由 `config.phases.testing.agent` 配置项解析（默认 general-purpose；推荐安装 qa-expert / test-engineer）
- Model Tier: deep / opus
- **必须使用 `run_in_background: true`**：测试用例生成不需要交互，主线程等待完成通知后验证 gate 即可
- 项目上下文从 config.project_context + config.test_suites + Phase 1 Steering Documents 自动注入
- 可选覆盖：config.phases.testing.instruction_files / reference_files（非空时注入）

## 门禁规则（严格）

**Phase 4 只接受 ok 或 blocked**（warning 由 Hook 确定性阻断）。详见 autopilot skill 的 protocol 文档。

### Phase 4 → Phase 5 特殊门禁

**非 TDD 模式**：

```text
- [ ] phase-4-testing.json 中 test_counts 的每个字段 ≥ config.phases.testing.gate.min_test_count_per_type
- [ ] artifacts 列表中包含 config.phases.testing.gate.required_test_types 对应的文件
- [ ] dry_run_results 的所有字段全部为 0（exit code）
- [ ] 必须创建实际测试文件，禁止以任何理由跳过
- [ ] `change_coverage.coverage_pct` ≥ 80%，否则 blocked
- [ ] 测试金字塔: unit ≥ `min_unit_pct`%，e2e ≤ `max_e2e_pct`%
- [ ] 每个测试用例必须追溯到 Phase 1 需求点（traceability matrix）
- [ ] status 只允许 "ok" 或 "blocked"（禁止 "warning"）
```

**TDD 模式**：

```text
- [ ] phase-4-tdd-override.json 存在且 tdd_mode_override === true
- [ ] 跳过 test_counts / dry_run 验证（测试在 Phase 5 per-task 创建）
```

完整指令详见 references/phase4-testing-template.md（测试标准 + dry-run + 金字塔）

## Phase 4 收尾：Test Report 线框（强制）

**执行位置**: 子 Agent 门禁校验通过、checkpoint 写入后，进入 Phase 5 前的最后一步。

Phase 4 即使未执行真实测试（仅设计用例 / dry-run 校验），也**必须**渲染 Test Report 线框，展示 Allure 预览服务地址（若可用）或 `unavailable` 占位。设计意图：让用户在测试用例设计完成的第一时间知晓报告访问入口的存活状态，而非等到 Phase 6 才出现。

```bash
CHANGE_DIR="openspec/changes/{change_name}"
BASE_PORT=$(python3 -c "import yaml; cfg=yaml.safe_load(open('.claude/autopilot.config.yaml')); print(cfg.get('phases',{}).get('reporting',{}).get('allure',{}).get('serve_port',4040))" 2>/dev/null || echo 4040)
bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/render-test-report-frame.sh "$CHANGE_DIR" "Phase 4 Test Report" "$BASE_PORT"
```

> 脚本职责：自愈启动 Allure 服务（若存在 allure-results）→ 读取 URL / PID / 测试总数 → 渲染固定宽度 50 字符线框。即使无结果也展示线框，Allure 行渲染为 `unavailable`。
> TDD 模式（`skipped_tdd`）下本步骤仍执行：此时扫描无 allure-results，线框展示 `pending (tests not yet executed)` + `Allure unavailable`，给用户一个"Phase 4 已确认但测试将在 Phase 5 TDD 中产生"的可观察信号。
