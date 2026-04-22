---
name: autopilot-phase6-report
description: "Use when the autopilot orchestrator reaches Phase 6 after Phase 5.5 Red Team has passed and must generate test reports with tri-path parallel execution covering testing, code review, and quality scans before archival."
user-invocable: false
---

# Autopilot Phase 6 — 测试报告与三路并行

> **前置条件自检**：本 Skill 仅在 autopilot 编排主线程中使用。如果当前上下文不是 autopilot 编排流程，请立即停止并忽略本 Skill。

Phase 6 执行测试报告生成，支持三路并行（测试 + 代码审查 + 质量扫描）和 Allure 集成。

**执行前读取**: `references/phase6-code-review.md` 与 `references/quality-scans.md`；并行 dispatch 协议详见 autopilot skill 的 parallel-phase6 章节。

## Phase 5→6 特殊门禁

> **仅 full 和 lite 模式执行**。minimal 模式跳过 Phase 6。

autopilot-gate 额外验证：

- `test-results.json` 存在
- `zero_skip_check.passed === true`
- 任务清单中所有任务标记为 `[x]`
- **Red Team 反例全绿**：若 `openspec/changes/{change_name}/context/redteam-report.json` 存在，其中所有 `reproducers[*].status` 必须为 `green`。任一 `blocking: true` 且非 green 的反例 → 硬阻断 Phase 6 进入（对应 rubric 校验条 `P6-FEAT-006`）。

## 测试执行

- 并行测试执行按 `config.test_suites` 分套件派发（详见 autopilot skill 的 parallel-phase6 章节）
- Agent: `config.phases.reporting.agent`（默认 general-purpose；推荐安装 qa-tester / qa-expert）
- 测试命令从 config.test_suites 动态读取（全量运行所有 suite）
- 报告命令从 config.phases.reporting.report_commands 读取
- 可选覆盖：config.phases.reporting.instruction_files（非空时注入）

## Allure 统一报告

`config.phases.reporting.format === "allure"` 时执行统一 Allure 流程（详见下文 Step A1–A6）；失败时降级为 `report_format: "custom"`。详见 autopilot skill 的 protocol 文档 Allure 报告章节。

## Phase 6 三路并行

> 详见 autopilot skill 的 mode-routing-table § 7。

Phase 5→6 Gate 通过后，主线程**在同一条消息中**同时派发路径 A / B / C，全部 `run_in_background: true`：

| 路径 | 内容 | 阻断性 |
|------|------|--------|
| **路径 A** | Phase 6 测试执行 | 主路径 |
| **路径 B** | Phase 6.5 代码审查（`config.phases.code_review.enabled = true` 时） | 不阻断路径 A |
| **路径 C** | 质量扫描（契约/性能/视觉/变异/安全测试） | 不阻断路径 A |

路径 B/C 不含 `autopilot-phase` 标记（不受 Hook 门禁校验）；路径 A 同样使用 `run_in_background: true`，主线程等待完成通知后写入 checkpoint。

**Phase 7 步骤 2 统一收集三路结果。**

## Allure Results 收集与报告生成（测试完成后）

当 `config.phases.reporting.format === "allure"` 时，测试完成后**必须执行**以下 Allure 流程：

### Step A1: 前置检查

```bash
bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/check-allure-install.sh "$(pwd)"
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

### Step A2.5: TDD Allure 处理（TDD 模式专用）

当 Phase 5 以 TDD 模式运行时（检测 `phase-4-tdd-override.json` 存在或 lock file 中 `tdd_mode: true`）：

1. **合并 TDD 阶段产物**：将 `allure-results/tdd/{red,green,refactor}/` 合并到统一 `$ALLURE_RESULTS_DIR`
2. **强制全量重跑**：设置 `FORCE_RERUN=true`，所有 `test_suites` 全量执行（忽略"近期通过"跳过逻辑），强制使用 `allure_args` 参数

```bash
TDD_ALLURE_DIR="openspec/changes/{change_name}/reports/allure-results/tdd"
if [ -d "$TDD_ALLURE_DIR" ]; then
  for stage_dir in "$TDD_ALLURE_DIR"/red "$TDD_ALLURE_DIR"/green "$TDD_ALLURE_DIR"/refactor; do
    if [ -d "$stage_dir" ]; then
      cp -r "$stage_dir"/* "$ALLURE_RESULTS_DIR/" 2>/dev/null || true
    fi
  done
fi
```

<details>
<summary>设计意图与根因</summary>

TDD 阶段已通过 Allure 增强命令产出 RED→GREEN→REFACTOR 结果（详见 autopilot-phase5-implement skill 的 tdd-cycle 章节），合并步骤将其纳入统一报告；强制重跑解决 TDD per-task 测试可能仅覆盖子集而非完整 suite 的问题。
</details>

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

当 `allure_report_generated === true` 时，**立即启动** Allure 本地预览服务，确保用户在 Phase 6 完成后即可通过浏览器查看测试报告。

```bash
# TODO: 抽取为 ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/read-allure-port.sh
BASE_PORT=$(python3 -c "import yaml; cfg=yaml.safe_load(open('.claude/autopilot.config.yaml')); print(cfg.get('phases',{}).get('reporting',{}).get('allure',{}).get('serve_port',4040))" 2>/dev/null || echo 4040)
bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/start-allure-serve.sh "openspec/changes/{change_name}" "$BASE_PORT"
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
bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-report-ready-event.sh \
  "openspec/changes" "{change_name}" "{mode}" "{session_id}"
```

> **设计意图**: 将 Allure 服务启动从 Phase 7 Step 2.5 前移至此，使用户在 Phase 6 完成后即可点击链接查看交互式测试报告。Phase 7 Step 2.5 仅负责验证服务存活和兜底重启。

### Step A6: Test Report 线框（Phase 6 即时展示）

Allure 服务启动完成后，立即渲染 **Test Report 线框**，确保用户在 Phase 6 结束时即可看到测试结果概览和报告访问地址。

```bash
# TODO: 抽取为 ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/compute-test-summary.sh
# 输入: $CHANGE_DIR  输出: JSON {total,passed,failed,skipped,pass_rate,allure_url}
bash -c '
  CHANGE_DIR="openspec/changes/{change_name}"
  P6="${CHANGE_DIR}/context/phase-results/phase-6-report.json"
  ALLURE_JSON="${CHANGE_DIR}/context/allure-preview.json"
  python3 - <<PY
import json, os
def agg(p, k):
    try:
        return sum(s.get(k,0) for s in json.load(open(p)).get("suite_results",[]))
    except Exception:
        return 0
total=agg("$P6","total"); passed=agg("$P6","passed")
failed=agg("$P6","failed"); skipped=agg("$P6","skipped")
rate=round(passed/total*100,1) if total else 0
url=""
if os.path.exists("$ALLURE_JSON"):
    try: url=json.load(open("$ALLURE_JSON")).get("url","")
    except Exception: pass
print(json.dumps({"total":total,"passed":passed,"failed":failed,
                  "skipped":skipped,"pass_rate":rate,"allure_url":url}))
PY
'
```

从 Bash 输出解析 JSON，渲染 Test Report 线框：

```
╭──────────────────────────────────────────────────╮
│                                                  │
│   Test Report                                    │
│                                                  │
│   Total   {total}  Passed  {passed}  Failed  {failed}       │
│   Skipped {skipped}  Pass Rate  {pass_rate}%                 │
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
