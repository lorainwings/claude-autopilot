---
name: autopilot-phase6-report
description: "[ONLY for autopilot orchestrator] Phase 6: Test report generation with tri-path parallel execution (testing + code review + quality scans) and Allure integration."
user-invocable: false
---

# Autopilot Phase 6 — 测试报告与三路并行

> **前置条件自检**：本 Skill 仅在 autopilot 编排主线程中使用。如果当前上下文不是 autopilot 编排流程，请立即停止并忽略本 Skill。

Phase 6 执行测试报告生成，支持三路并行（测试 + 代码审查 + 质量扫描）和 Allure 集成。

**执行前读取**: `autopilot/references/parallel-phase6.md` + `autopilot/references/phase6-code-review.md` + `autopilot/references/quality-scans.md`

## Phase 5→6 特殊门禁

> **仅 full 和 lite 模式执行**。minimal 模式跳过 Phase 6。

autopilot-gate 额外验证：

- `test-results.json` 存在
- `zero_skip_check.passed === true`
- 任务清单中所有任务标记为 `[x]`

## 测试执行

- 并行测试执行按 `config.test_suites` 分套件派发（详见 `autopilot/references/parallel-phase6.md`）
- Agent: qa-expert
- 测试命令从 config.test_suites 动态读取（全量运行所有 suite���
- 报告命令从 config.phases.reporting.report_commands 读取
- 可选覆盖：config.phases.reporting.instruction_files（非空时注入）

## Allure 统一报告

当 `config.phases.reporting.format === "allure"` 时：

- 前置检查 Allure 安装
- 统一 `ALLURE_RESULTS_DIR` 输出
- 生成报告
- 降级兜底为 `report_format: "custom"`

详见 `autopilot/references/protocol.md` Allure 报告章节。

## Phase 6 三路并行（增强）

> 详见 `autopilot/references/mode-routing-table.md` § 7。

Phase 5→6 Gate 通过后，主线程**在同一条消息中**同时派发路径 A / B / C，全部 `run_in_background: true`：

| 路径 | 内容 | 阻断性 |
|------|------|--------|
| **路径 A** | Phase 6 测试执行 | 主路径 |
| **路径 B** | Phase 6.5 代码审查（`config.phases.code_review.enabled = true` 时） | 不阻断路径 A |
| **路径 C** | 质量扫描（契约/性能/视觉/变异/安全测试） | 不阻断路径 A |

路径 B/C 不含 `autopilot-phase` 标记（不受 Hook 门禁校验）。

**Phase 7 步骤 2 统一收集三路结果。**

## Phase 6 路径 A（测试）dispatch 说明

- 也必须使用 `run_in_background: true`：测试执行不需要交互，主线程等待完成通知后写入 checkpoint
- 与路径 B/C 在同一消息中全部后台派发

## Allure Results 收集与报告生成（测试完成后）

当 `config.phases.reporting.format === "allure"` 时，测试完成后**必须执行**以下 Allure 流程：

### Step A1: 前置检查

```bash
Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/check-allure-install.sh "$(pwd)"')
```

解析返回 JSON，若 `all_required_installed === false`：

- 展示 `missing` 列表和 `install_commands`
- AskUserQuestion: "Allure 工具链不完整，是否自动安装？"
  - "自动安装 (Recommended)" → 逐个执行 install_commands
  - "跳过 Allure，使用 custom 格式" → 降级为 custom

### Step A2: 统一 ALLURE_RESULTS_DIR

确保所有测试套件的 Allure 结果输出到统一目录：

```bash
ALLURE_RESULTS_DIR="openspec/changes/{change_name}/reports/allure-results"
mkdir -p "$ALLURE_RESULTS_DIR"
```

### Step A2.5: TDD Allure 结果合并（TDD 模式专用）

当 Phase 5 以 TDD 模式运行时（检测 `phase-4-tdd-override.json` 存在或 lock file 中 `tdd_mode: true`），TDD 各阶段已产出 Allure 结果到 `allure-results/tdd/` 子目录。此步骤将 TDD 结果合并到统一 Allure 目录：

```bash
TDD_ALLURE_DIR="openspec/changes/{change_name}/reports/allure-results/tdd"
if [ -d "$TDD_ALLURE_DIR" ]; then
  # 合并 TDD 各阶段的 Allure 结果到统一目录
  for stage_dir in "$TDD_ALLURE_DIR"/red "$TDD_ALLURE_DIR"/green "$TDD_ALLURE_DIR"/refactor; do
    if [ -d "$stage_dir" ]; then
      cp -r "$stage_dir"/* "$ALLURE_RESULTS_DIR/" 2>/dev/null || true
    fi
  done
  echo "[ALLURE] 已合并 TDD Allure 结果到统一目录"
fi
```

> **设计意图**: TDD 模式下 Phase 5 的 RED→GREEN→REFACTOR 已经通过 Allure 增强命令产出了测试结果（详见 `tdd-cycle.md` TDD 测试命令 Allure 增强），此步骤确保这些结果被纳入统一 Allure 报告。

### Step A2.6: TDD 模式强制全量 Allure 重跑

当 Phase 5 以 TDD 模式运行时，Phase 6 **必须强制执行一次完整的 Allure 增强测试重跑**，而非依赖"智能跳过"逻辑（TDD 测试可能被标记为"近期通过"而被跳过，导致 Allure 结果不完整）：

```
IF tdd_mode was active in Phase 5:
  → 设置 FORCE_RERUN=true
  → 所有 test_suites 全量执行（忽略最近通过时间）
  → 所有 test_suites 必须使用 allure_args 参数
  → 确保 Allure 结果目录包含所有 suite 的完整结果
```

> **根因**: TDD Phase 5 的测试执行以 pass/fail 二值判断为核心，即使注入了 Allure 参数，其覆盖的可能只是 per-task 子集而非完整 suite。Phase 6 强制重跑确保 Allure 报告反映完整的测试覆盖。

### Step A3: 执行 allure_post 命令

对每个 `config.test_suites` 中配置了 `allure_post` 的套件：

```bash
# 示例：JUnit XML → Allure Results 转换
ALLURE_RESULTS_DIR="$ALLURE_RESULTS_DIR" eval "{suite.allure_post}"
```

### Step A4: 生成 Allure 报告

```bash
ALLURE_REPORT_DIR="openspec/changes/{change_name}/reports/allure-report"
npx allure generate "$ALLURE_RESULTS_DIR" -o "$ALLURE_REPORT_DIR" --clean
```

验证 `$ALLURE_REPORT_DIR/index.html` 存在。

### Step A5: 写入 checkpoint 附加字段

在 Phase 6 checkpoint (`phase-6-report.json`) 中包含：

```json
{
  "allure_results_dir": "openspec/changes/{change_name}/reports/allure-results",
  "allure_report_dir": "openspec/changes/{change_name}/reports/allure-report",
  "allure_report_generated": true,
  "report_format": "allure"
}
```

`allure_report_generated: false` 时 Phase 7 Step 2.5 会尝试 fallback generate。

> **降级兜底**: Allure 生成失败时降级为 `report_format: "custom"`，不阻断 Phase 6。

### Step A5.5: 启动 Allure 预览服务

当 `allure_report_generated === true` 时，**立即启动** Allure 本地预览服务，确保用户在 Phase 6 完成后即可通过浏览器查看测试报告：

```bash
Bash('
  CHANGE_DIR="openspec/changes/{change_name}"

  # 从配置读取 Allure 服务端口
  BASE_PORT=$(python3 -c "
import yaml
try:
    cfg = yaml.safe_load(open(\".claude/autopilot.config.yaml\"))
    print(cfg.get(\"phases\",{}).get(\"reporting\",{}).get(\"allure\",{}).get(\"serve_port\", 4040))
except: print(4040)
  " 2>/dev/null || echo 4040)

  # 调用统一启动脚本
  bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/start-allure-serve.sh "$CHANGE_DIR" "$BASE_PORT"
')
```

解析返回 JSON：
- `status === "ok"` → 从 `url` 和 `pid` 字段提取地址和 PID，更新 Phase 6 checkpoint 追加字段：
  ```json
  {
    "allure_preview_url": "http://localhost:{port}",
    "allure_serve_pid": {pid}
  }
  ```
- `status === "skipped"` → 无 Allure 产物，跳过预览
- `status === "warning"` → 展示错误信息，不阻断 Phase 6

启动成功后，调用 `emit-report-ready-event.sh` 更新事件（补充 `allure_preview_url`）：

```bash
Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-report-ready-event.sh \
  "openspec/changes" "{change_name}" "{mode}" "{session_id}"')
```

> **设计意图**: 将 Allure 服务启动从 Phase 7 Step 2.5 前移至此，使用户在 Phase 6 完成后即可点击链接查看交互式测试报告。Phase 7 Step 2.5 仅负责验证服务存活和兜底重启。

### Step A6: Test Report 线框（Phase 6 即时展示）

Allure 服务启动完成后，立即渲染 **Test Report 线框**，确保用户在 Phase 6 结束时即可看到测试结果概览和报告访问地址：

```bash
Bash('
  CHANGE_DIR="openspec/changes/{change_name}"
  CONTEXT_DIR="${CHANGE_DIR}/context"

  # 从 Phase 6 checkpoint 读取测试结果
  P6_CHECKPOINT="${CONTEXT_DIR}/phase-results/phase-6-report.json"
  TOTAL=0; PASSED=0; FAILED=0; SKIPPED=0; PASS_RATE="0"
  if [ -f "$P6_CHECKPOINT" ]; then
    TOTAL=$(python3 -c "import json; d=json.load(open(\"$P6_CHECKPOINT\")); print(sum(s.get(\"total\",0) for s in d.get(\"suite_results\",[])))" 2>/dev/null || echo 0)
    PASSED=$(python3 -c "import json; d=json.load(open(\"$P6_CHECKPOINT\")); print(sum(s.get(\"passed\",0) for s in d.get(\"suite_results\",[])))" 2>/dev/null || echo 0)
    FAILED=$(python3 -c "import json; d=json.load(open(\"$P6_CHECKPOINT\")); print(sum(s.get(\"failed\",0) for s in d.get(\"suite_results\",[])))" 2>/dev/null || echo 0)
    SKIPPED=$(python3 -c "import json; d=json.load(open(\"$P6_CHECKPOINT\")); print(sum(s.get(\"skipped\",0) for s in d.get(\"suite_results\",[])))" 2>/dev/null || echo 0)
    if [ "$TOTAL" -gt 0 ] 2>/dev/null; then
      PASS_RATE=$(python3 -c "print(round($PASSED/$TOTAL*100, 1))" 2>/dev/null || echo 0)
    fi
  fi

  # 从 allure-preview.json 读取 Allure 地址
  ALLURE_URL=""
  if [ -f "${CONTEXT_DIR}/allure-preview.json" ]; then
    ALLURE_URL=$(python3 -c "import json; print(json.load(open(\"${CONTEXT_DIR}/allure-preview.json\")).get(\"url\",\"\"))" 2>/dev/null || echo "")
  fi

  python3 -c "
import json
print(json.dumps({
    \"total\": $TOTAL, \"passed\": $PASSED, \"failed\": $FAILED, \"skipped\": $SKIPPED,
    \"pass_rate\": \"$PASS_RATE\", \"allure_url\": \"$ALLURE_URL\"
}))
  "
')
```

从 Bash 输出解析 JSON，渲染 Test Report 线框：

```
╭──────────────────────────────────────────────────╮
│                                                  │
│   Test Report                                    │
│                                                  │
│   Total   {N}  Passed  {N}  Failed  {N}          │
│   Skipped {N}  Pass Rate  {N}%                   │
│                                                  │
│   Allure  {allure_url}                           │
│                                                  │
╰──────────────────────────────────────────────────╯
```

> **Allure 行渲染规则**：
>
> - `allure_url` 非空时展示实际地址（如 `http://localhost:4040`）
> - `allure_url` 为空时（无产物或启动失败）展示 `unavailable`
> - Allure 行**始终展示**，确保用户了解报告可用状态
