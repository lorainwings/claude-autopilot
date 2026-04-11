---
name: autopilot-phase7-archive
description: "[ONLY for autopilot orchestrator] Phase 7: Summary display, tri-path result collection, knowledge extraction, Allure preview, archive readiness auto, git autosquash, and lockfile cleanup."
user-invocable: false
---

# Autopilot Phase 7 — 汇总 + Archive Readiness 自动归档

> **前置条件自检**：本 Skill 仅在 autopilot 编排主线程中使用。如果当前上下文不是 autopilot 编排流程，请立即停止并忽略本 Skill。

**执行前读取**: `autopilot/references/log-format.md`（Summary Box 渲染规范）

## 执行步骤

### Step -1: 发射 Phase 7 开始事件（v5.2 Event Bus 补全）

```bash
Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-phase-event.sh phase_start 7 {mode}')
```

### Step 0: 写入 Phase 7 Checkpoint（进行中）

调用 Skill(`spec-autopilot:autopilot-gate`) checkpoint 管理写入 `phase-7-summary.json`：

```json
{"status": "in_progress", "phase": 7, "description": "Archive and cleanup"}
```

**v5.3 进度写入**: `Bash('AUTOPILOT_PROJECT_ROOT=$(pwd) bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/write-phase-progress.sh 7 summary_dispatched in_progress')`

### Step 1: 派发汇总子 Agent

前台 Task 读取所有 checkpoint 并生成汇总（v3.3.0 上下文保护增强）：

```
Task(subagent_type: "general-purpose", prompt: "
  读取 openspec/changes/<name>/context/phase-results/ 下所有 JSON checkpoint 文件。
  读取 Phase 6 checkpoint（phase-6-report.json）提取 report_format、report_path、suite_results。
  读取 Phase 5 task checkpoints（phase5-tasks/task-*.json）提取 test_driven_evidence 字段（如存在）。
  执行 bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/collect-metrics.sh 收集执行指标。
  生成以下格式的 JSON 信封返回（禁止返回 checkpoint 原文）：
  {
    \"status\": \"ok\",
    \"phase_summary\": [{\"phase\": N, \"status\": \"ok|warning|blocked\", \"description\": \"...\"}],
    \"test_report\": {\"format\": \"allure|custom\", \"path\": \"...\", \"suites\": [...], \"anomaly_alerts\": \"...\"},
    \"test_driven_summary\": {\"total_tasks\": N, \"red_green_verified\": M, \"red_skipped\": K},
    \"metrics\": {\"markdown_table\": \"...\", \"ascii_chart\": \"...\"}
  }
  其中 test_driven_summary 统计：
  - total_tasks: Phase 5 中含 test_driven_evidence 的 task 总数
  - red_green_verified: red_verified=true 且 green_verified=true 的 task 数（有效 RED→GREEN 转变）
  - red_skipped: red_verified=false 的 task 数（测试已通过，证据不完整）
  若无任何 test_driven_evidence 字段，则 test_driven_summary 为 null。
")
```

从返回信封提取并展示：
- 阶段状态汇总表（`phase_summary`）
- 测试驱动统计（`test_driven_summary`，仅 full 模式非 TDD 时展示）
- 测试报告汇总表 + Allure 报告链接（`test_report`，仅 full/lite 模式）
- 阶段耗时表格和分布图（`metrics`）

> **Phase 6 checkpoint 不存在时**（minimal 模式）：子 Agent 跳过测试报告部分

### Step 1.6: 知识提取（后台子 Agent）

- 派发后台 Agent：`Task(subagent_type: "general-purpose", run_in_background: true)`
- Agent 任务：读取 `references/knowledge-accumulation.md` → 遍历 phase-results → 提取知识 → 写入 `openspec/.autopilot-knowledge.json`
- 主线程同时继续执行步骤 2，不阻塞
- 在步骤 3 archive-readiness 检查前等待完成，展示：「已提取 N 条知识（M 条 pitfall，K 条 decision）」

### Step 2: 收集三路并行结果

> **仅 full/lite 模式**。minimal 模式跳过此步骤（无 Phase 6），直接进入步骤 3。

**等待机制**：阻塞等待路径 A/B/C 的后台 Agent 完成或超时（`config.background_agent_timeout_minutes`，默认 30 分钟）。超时自动标记 `"timeout"`，不阻断 Phase 7 流程。

a0. **Phase 6 测试执行**（路径 A，后台 Task）：
  - 等待后台 Agent 完成通知
  - 解析 JSON 信封，按统一调度模板 Step 4/5+7/6/8 处理
  - ok/warning → 继续收集路径 B/C
  - blocked/failed → 展示给用户，但不阻断路径 B/C 的收集

a. **Phase 6.5 代码审查**（路径 B，仅当 `config.phases.code_review.enabled = true`，**optional/advisory — 不作为 Phase 7 硬性前置条件**）：
  - 检查后台 Agent 完成通知
  - ok → 写入 `phase-6.5-code-review.json` checkpoint（status: ok）
  - warning → 写入 `phase-6.5-code-review.json` checkpoint（status: warning，含 findings），展示 findings，不阻断归档
  - blocked → 写入 `phase-6.5-code-review.json` checkpoint（status: blocked，含 critical findings），展示 critical findings，但**不得**在 Step 2 提供“忽略继续归档”选项；后续是否可继续由 Step 3 的 archive-readiness fail-closed 判定统一处理
  - code_review 未启用 → 跳过
  - JSON 解析失败 → 写入 `phase-6.5-code-review.json` checkpoint（status: warning，含原始文本），展示原始文本

b. **质量扫描**（路径 C）：展示质量汇总表（含得分和阈值对比）
  - 硬超时：`config.async_quality_scans.timeout_minutes`（默认 10 分钟），超时标记 `"timeout"`
  - JSON 解析失败 → 展示原始文本，标记 warning

c. **知识提取**（Step 1.6 后台 Agent）：等待完成，展示提取结果

### Step 2.5: Allure 本地预览（v8.0 子 Agent 委托）

> 当 Allure 产物存在时执行。v8.0 将原主线程内联的 ~170 行 Bash 操作委托给后台子 Agent，减少主窗口上下文污染。

派发**前台 Task**（非后台）处理 Allure 预览全流程：

```
Task(subagent_type: "general-purpose", prompt: "
  你是 Allure 预览服务启动子 Agent。按以下步骤执行：

  1. 搜索 allure-results/ (三条路径优先级: Phase 6 checkpoint 的 allure_results_dir 字段 > change 级 reports/allure-results/ > 项目根 allure-results/)
  2. 搜索 allure-report/ (同级目录或项目根)
  3. 如存在 results 但无 report，执行 npx allure generate
  4. 从 .claude/autopilot.config.yaml 读取 phases.reporting.allure.serve_port (默认 4040)
  5. 检测端口可用性 (尝试 base_port 到 base_port+9)
  6. 后台启动 npx allure open，写入 PID 文件到 ${change_dir}context/allure-serve.pid
  7. 等待服务就绪 (最多10秒 curl 轮询)
  8. 写入 ${change_dir}context/allure-preview.json（关键：Summary Box 从此文件读取 URL）
  9. 更新 state-snapshot.json 的 report_state.allure_preview_url
  10. 调用 emit-report-ready-event.sh 发射事件

  路径一致性: 搜索逻辑与 emit-report-ready-event.sh:51-63 保持一致。

  返回 JSON 信封:
  {\"status\": \"ok\", \"summary\": \"Allure 预览启动成功\", \"url\": \"http://localhost:{port}\", \"pid\": {pid}}
  或
  {\"status\": \"skipped\", \"summary\": \"无 allure 产物，跳过预览\"}
  或
  {\"status\": \"warning\", \"summary\": \"Allure 报告生成/启动失败\", \"error\": \"...\"}
")
```

> **v8.0 设计决策**: 使用**前台 Task**（非 `run_in_background`），确保 Allure 子 Agent 完成后主线程再进入 Step 3。这保证了：
> 1. `allure-preview.json` 在 Summary Box 渲染前已写入磁盘
> 2. `state-snapshot.json` 已更新
> 3. `report_ready` 事件已发射
>
> **上下文优化仍有效**: 子 Agent 内部的 ~170 行 Bash 操作不进入主线程上下文，主线程仅接收 JSON 信封。

#### 服务生命周期管理

- PID 文件位于 `${change_dir}context/allure-serve.pid`（change 级隔离，由子 Agent 写入）
- **服务保活策略**：Allure 服务在 Phase 7 归档后**不自动 kill**。服务保持运行确保用户可随时通过 Summary Box 链接查看报告。Step 9 输出停止命令提示，由用户自行决定停止时机。

### Step 3: Archive Readiness 检查与归档决策

**v6.0 Archive Readiness 自动化**: 归档前执行统一的 archive-readiness 判定。所有判定条件通过时自动归档，无需人工确认；任一条件失败时硬阻断并展示原因。

#### Step 3.1: 构建 archive-readiness.json

收集以下字段，写入 `${change_dir}context/archive-readiness.json`：

```json
{
  "timestamp": "ISO-8601",
  "mode": "full|lite|minimal",
  "checks": {
    "all_checkpoints_ok": true,
    "fixup_completeness": { "passed": true, "fixup_count": 5, "checkpoint_count": 5 },
    "anchor_valid": true,
    "worktree_clean": true,
    "review_findings_clear": true,
    "zero_skip_passed": true
  },
  "overall": "ready|blocked",
  "block_reasons": []
}
```

各检查项定义：
- `all_checkpoints_ok`: 所有已执行 phase 的 checkpoint status 为 ok 或 warning
- `fixup_completeness`: `FIXUP_COUNT >= CHECKPOINT_COUNT`（**硬阻断**，不再是 warning）
- `anchor_valid`: `git rev-parse $ANCHOR_SHA` 成功
- `worktree_clean`: `git status --porcelain` 为空（工作区残留变更已提交）
- `review_findings_clear`: 当 `block_on_critical = true` 时，无未解决 critical findings；否则总是 true
- `zero_skip_passed`: Phase 5 checkpoint 中 `zero_skip_check.passed === true`（minimal 模式豁免）

#### Step 3.2: 判定逻辑

```
IF archive-readiness.overall === "ready":
  → 日志输出 [ARCHIVE] Readiness check: PASSED — auto-archiving
  → 直接进入 Step 4 归档操作（无需 AskUserQuestion）
ELSE:
  → 日志输出 [ARCHIVE] Readiness check: BLOCKED — {block_reasons}
  → AskUserQuestion 展示阻断原因，选项:
    - "修复后重新检查"
    - "放弃归档"
  → 禁止 "忽略继续归档" 选项（fail-closed 原则）
```

**v5.8 block_on_critical 语义保留**: 当 `config.phases.code_review.block_on_critical = true` 时：
1. 检查 `phase-6.5-code-review.json` 中是否存在 `critical` 级别 findings
2. 如有 critical findings 未修复 → `review_findings_clear = false`，归入 `block_reasons`
3. 如无 critical findings 或 `block_on_critical = false` → `review_findings_clear = true`

**v5.3 进度写入**: `Bash('AUTOPILOT_PROJECT_ROOT=$(pwd) bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/write-phase-progress.sh 7 summary_complete complete')`

### Step 4: 归档操作（archive readiness 通过后自动执行）

a. **归档前清理**：
  - 更新 Phase 7 Checkpoint（完成）：调用 Skill(`spec-autopilot:autopilot-gate`) checkpoint 管理更新 `phase-7-summary.json`：
    ```json
    {"status": "ok", "phase": 7, "description": "Archive complete", "archived_change": "<change_name>", "mode": "<mode>"}
    ```
  - 删除临时文件：`openspec/changes/<name>/context/phase-results/phase5-start-time.txt`（如存在）

b. **Git 自动压缩**（当 `config.context_management.squash_on_archive` 为 true，默认 true）：
  - **v5.3 进度写入**: `Bash('AUTOPILOT_PROJECT_ROOT=$(pwd) bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/write-phase-progress.sh 7 autosquash_started in_progress')`
  - **v8.0 独立脚本**: 所有 fixup 完整性检查、非 autopilot fixup 检查、anchor 验证/重建、rebase 操作已封装到 `autosquash-archive.sh`：
    ```bash
    Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/autosquash-archive.sh "$(pwd)" "${ANCHOR_SHA}" "${change_name}"')
    ```
    解析返回的 JSON（`{"status":"ok|blocked|needs_confirmation","anchor_sha":"...","squash_count":N,"non_autopilot_fixups":[...],"error":"..."}`）：
    - `status: "ok"` → 修改 commit message 为 `feat(autopilot): <change_name> — <summary>`，继续归档
    - `status: "needs_confirmation"` → 展示 `non_autopilot_fixups` 列表，AskUserQuestion 确认是否继续
      - 用户选择“继续” → **必须**使用确认标志重新调用：
        ```bash
        Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/autosquash-archive.sh "$(pwd)" "${anchor_sha_from_json}" "${change_name}" true')
        ```
      - 用户选择“取消” → 中止归档，不执行 rebase
    - `status: "blocked"` → 硬阻断归档（fail-closed），展示 `error` 信息
      - fixup 不完整时：`[BLOCKED] fixup 完整性检查失败: ${FIXUP_COUNT} fixup commits < ${CHECKPOINT_COUNT} checkpoints.`
      - anchor 重建失败时：`[BLOCKED] anchor 重建失败，无法执行 autosquash。归档中止。`
      - autosquash 失败时：`[BLOCKED] autosquash 失败，无法合并 fixup commits。归档中止。`
  > **v8.0 上下文优化**: 主线程不再内联执行 ~50 行 git 操作，仅调用一次 Bash 并解析 JSON 结果。

c. **归档**（模式感知）：
  - **full 模式**: 执行 Skill(`openspec-archive-change`)（完整 OpenSpec 归档）
  - **lite/minimal 模式**: 跳过 OpenSpec 归档，仅完成 git squash

### Step 5: Archive Readiness 阻断时的用户选择

当 Step 3.2 判定 `overall === "blocked"` 时，用户选择"修复后重新检查"：
→ 提示用户根据 `block_reasons` 修复问题，修复后重新执行 Step 3.1 构建 archive-readiness.json

当用户选择"放弃归档"：展示手动归档命令，结束流程。

### Step 6: 归档后处理

归档完成后自动进入后续清理步骤（Step 6.5、7、8），无需额外确认。

> **Allure 服务保活**：Step 2.5 启动的 Allure 预览服务**不在归档时清理**。服务保持运行直到用户手动停止，确保 Summary Box 中展示的链接可用。

### Step 6.5: 发射 Phase 7 结束事件（v5.2 Event Bus 补全）

```bash
Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-phase-event.sh phase_end 7 {mode} \'{"status":"ok","duration_ms":{elapsed},"artifacts":["phase-7-summary.json"]}\'')
```

### Step 7: 清理锁定文件

删除 `${session_cwd}/openspec/changes/.autopilot-active`（无论用户选择何种归档方式）：

```bash
rm -f ${session_cwd}/openspec/changes/.autopilot-active
```

输出：`[LOCK] deleted: .autopilot-active`

### Step 8: 清理 git tag

删除 `autopilot-phase5-start` tag（如果存在）：

```bash
git tag -d autopilot-phase5-start 2>/dev/null
```

### Step 9: Allure 服务提示（若 Step 2.5 启动了服务）

若 `${change_dir}context/allure-serve.pid` 存在，输出提示：

```
Bash('
  PID_FILE="openspec/changes/{change_name}/context/allure-serve.pid"
  if [ -f "$PID_FILE" ]; then
    ALLURE_PID=$(cat "$PID_FILE")
    if kill -0 "$ALLURE_PID" 2>/dev/null; then
      echo "[ALLURE] 预览服务仍在运行 (PID: $ALLURE_PID)。查看完报告后运行以下命令停止:"
      echo "  kill $ALLURE_PID"
    else
      rm -f "$PID_FILE"
    fi
  fi
')
```

> **设计意图**：不自动 kill Allure 服务，确保 Summary Box 中的链接在用户查看期间始终可用。用户查看完后自行停止。

---

## Summary Box 渲染

Phase 7 汇总展示时，输出 Summary Box（遵循 `autopilot/references/log-format.md`）。

### 确定性地址收集（v8.0 — 从磁盘读取，不依赖上下文变量）

Summary Box 渲染前，通过**单次 Bash 脚本**从磁盘文件确定性读取所有关键地址：

```bash
Bash('
  CHANGE_DIR="openspec/changes/{change_name}"
  CONTEXT_DIR="${CHANGE_DIR}/context"

  # 1. Allure 预览地址（从 allure-preview.json 读取，Step 2.5 子 Agent 已写入）
  ALLURE_URL=""
  ALLURE_PID=""
  if [ -f "${CONTEXT_DIR}/allure-preview.json" ]; then
    ALLURE_URL=$(python3 -c "import json; print(json.load(open(\"${CONTEXT_DIR}/allure-preview.json\")).get(\"url\",\"\"))" 2>/dev/null || echo "")
    ALLURE_PID=$(python3 -c "import json; print(json.load(open(\"${CONTEXT_DIR}/allure-preview.json\")).get(\"pid\",\"\"))" 2>/dev/null || echo "")
  fi

  # 2. GUI 大盘地址（从 GUI 服务器 PID + 配置端口推导）
  GUI_URL=""
  GUI_PORT=$(python3 -c "
import yaml
try:
    cfg = yaml.safe_load(open(\".claude/autopilot.config.yaml\"))
    print(cfg.get(\"gui\",{}).get(\"port\", 9527))
except: print(9527)
  " 2>/dev/null || echo 9527)
  if [ -f "logs/.gui-server.pid" ]; then
    GUI_PID_VAL=$(cat "logs/.gui-server.pid" 2>/dev/null || echo "")
    if [ -n "$GUI_PID_VAL" ] && kill -0 "$GUI_PID_VAL" 2>/dev/null; then
      GUI_URL="http://localhost:${GUI_PORT}"
    fi
  fi

  # 3. 服务健康检查地址（从配置读取）
  SERVICES=$(python3 -c "
import yaml, json
try:
    cfg = yaml.safe_load(open(\".claude/autopilot.config.yaml\"))
    svcs = cfg.get(\"services\", {})
    for name, url in svcs.items():
        if isinstance(url, str): print(f\"{name}: {url}\")
except: pass
  " 2>/dev/null || true)

  # 输出 JSON 供主线程解析
  python3 -c "
import json, sys
result = {
    \"allure_url\": \"${ALLURE_URL}\",
    \"allure_pid\": \"${ALLURE_PID}\",
    \"gui_url\": \"${GUI_URL}\",
    \"services\": {}
}
for line in \"\"\"${SERVICES}\"\"\".strip().splitlines():
    if \": \" in line:
        k, v = line.split(\": \", 1)
        result[\"services\"][k.strip()] = v.strip()
print(json.dumps(result))
  " 2>/dev/null || echo "{}"
')
```

从 Bash 输出解析 JSON，获取 `allure_url`、`gui_url`、`services` 字典。这些值**全部来自磁盘文件**，不依赖主线程上下文中是否持有变量。

### Summary Box 模板

如果 execution_mode !== "full":
  在 Summary Box 的第一行添加:
  `Mode: ${execution_mode} | Skipped: Phase ${skipped_list}`
  其中:
  - lite: skipped_list = "2, 3, 4"
  - minimal: skipped_list = "2, 3, 4, 6"

```
╭──────────────────────────────────────────────────╮
│                                                  │
│   Autopilot Summary                              │
│   Mode: lite | Skipped: Phase 2, 3, 4           │
│                                                  │
│   Phase 1  Requirements    ok                    │
│   Phase 5  Implementation  ok                    │
│   Phase 6  Test Report     warning               │
│   Phase 7  Archive         ok                    │
│                                                  │
│   Duration   {HH:mm:ss}                          │
│   Pass Rate  {N}%                                │
│   TDD        {M}/{N} tasks RED→GREEN verified    │
│                                                  │
│   ── Quick Links ──                              │
│   GUI        {gui_url}                           │
│   Allure     {allure_url}                        │
│   Services   {service_name}: {service_url}       │
│                                                  │
╰──────────────────────────────────────────────────╯
```

> 仅展示实际执行的阶段（lite/minimal 跳过的阶段不显示）。框内宽度固定 50 字符（纯 ASCII）。
> **Quick Links 区域渲染规则**（v8.0 确定性地址）：
> - GUI 行：`gui_url` 非空时展示，为空时显示 `unavailable`
> - Allure 行：`allure_url` 非空时展示，Allure 服务未启动（无产物或启动失败）时**不展示此行**
> - Services 行：`services` 字典中每个 key-value 展示一行，字典为空时**不展示此行**
> - TDD 行仅在 `test_driven_summary` 非 null 时展示（full 模式非 TDD 模式）
> - **所有地址从磁盘文件读取**（allure-preview.json、GUI PID 文件、autopilot.config.yaml），不依赖 AI 在上下文中持有变量值

**Archive Readiness 自动归档**: 当 archive-readiness.json 所有检查通过时，自动执行归档操作，不中断用户。仅在 readiness 检查失败时才阻断流程并请求用户决策。
