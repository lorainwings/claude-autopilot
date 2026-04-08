---
name: autopilot-phase7
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

### Step 2.5: Allure 本地预览

> 当 Allure 产物存在时执行（多路径搜索，与 `emit-report-ready-event.sh` 一致）。
> Step 2.5.0 确保 `allure-report/` 的确定性存在。

#### 2.5.0 Allure Report 确定性生成（兜底 + 多路径搜索）

> 搜索 `allure-results/` 的三条路径（与 `emit-report-ready-event.sh:51-63` 保持一致）：
> 1. Phase 6 checkpoint `allure_results_dir` 字段（最高优先级）
> 2. change 级 `reports/allure-results/`
> 3. 项目根（CWD）`allure-results/`
>
> 对 `allure-report/` 同样做多路径搜索。若存在 `allure-results/` 但无 `allure-report/`，
> 由主线程确定性执行 `allure generate`。

```
Bash('
  CHANGE_DIR="openspec/changes/{change_name}"
  REPORT_DIR="${CHANGE_DIR}/reports"
  ALLURE_RESULTS_DIR=""
  ALLURE_REPORT_DIR=""

  # 1. 从 Phase 6 checkpoint 读取 allure_results_dir（最高优先级）
  PHASE6_CP="${CHANGE_DIR}/context/phase-results/phase-6-report.json"
  if [ -f "$PHASE6_CP" ]; then
    CP_DIR=$(jq -r ".allure_results_dir // \"\"" "$PHASE6_CP" 2>/dev/null || echo "")
    if [ -n "$CP_DIR" ] && [ -d "$CP_DIR" ]; then
      ALLURE_RESULTS_DIR="$CP_DIR"
    fi
  fi

  # 2. change 级 reports/allure-results/
  if [ -z "$ALLURE_RESULTS_DIR" ] && [ -d "$REPORT_DIR/allure-results" ]; then
    ALLURE_RESULTS_DIR="$REPORT_DIR/allure-results"
  fi

  # 3. 项目根 allure-results/
  if [ -z "$ALLURE_RESULTS_DIR" ] && [ -d "allure-results" ]; then
    ALLURE_RESULTS_DIR="allure-results"
  fi

  # 无 allure 产物
  if [ -z "$ALLURE_RESULTS_DIR" ]; then
    echo "NO_RESULTS"
    exit 0
  fi

  # 搜索 allure-report/（同级或项目根）
  PARENT_DIR=$(dirname "$ALLURE_RESULTS_DIR")
  if [ -d "$PARENT_DIR/allure-report" ]; then
    ALLURE_REPORT_DIR="$PARENT_DIR/allure-report"
  elif [ -d "allure-report" ]; then
    ALLURE_REPORT_DIR="allure-report"
  fi

  # 有 results 无 report → 确定性生成
  if [ -z "$ALLURE_REPORT_DIR" ]; then
    ALLURE_REPORT_DIR="$PARENT_DIR/allure-report"
    echo "[ALLURE] $ALLURE_RESULTS_DIR 存在但 allure-report/ 缺失，执行确定性生成..."
    npx allure generate "$ALLURE_RESULTS_DIR" -o "$ALLURE_REPORT_DIR" --clean 2>&1
    if [ $? -eq 0 ]; then
      echo "GENERATED:$ALLURE_REPORT_DIR"
    else
      echo "FAILED"
    fi
  else
    echo "EXISTS:$ALLURE_REPORT_DIR"
  fi
')
```

从 Bash 输出解析：
- `GENERATED:{path}` 或 `EXISTS:{path}` → 从输出提取 `ALLURE_REPORT_DIR` 路径，继续 2.5.1 启动服务
- `FAILED` → 日志输出 `[WARN] Allure 报告生成失败，跳过本地预览`，跳过整个 Step 2.5，不阻断流程
- `NO_RESULTS` → 跳过整个 Step 2.5（无 allure 产物）

> **路径一致性**: 此搜索逻辑与 `emit-report-ready-event.sh:51-63` 保持一致，确保 Phase 7 启动预览服务和事件发射读取同一套产物路径。

#### 2.5.1 读取配置端口 + 端口检测

主线程从配置读取 Allure 服务端口（伪代码注释，实际通过 Bash 工具执行 shell）：

```
Bash('
  ALLURE_BASE_PORT=$(python3 -c "
import yaml, sys
try:
    cfg = yaml.safe_load(open(\".claude/autopilot.config.yaml\"))
    print(cfg.get(\"phases\",{}).get(\"reporting\",{}).get(\"allure\",{}).get(\"serve_port\", 4040))
except: print(4040)
  " 2>/dev/null || echo 4040)

  ALLURE_PORT=$ALLURE_BASE_PORT
  for i in $(seq 0 9); do
    PORT=$((ALLURE_BASE_PORT + i))
    if ! lsof -i :$PORT -sTCP:LISTEN >/dev/null 2>&1; then
      ALLURE_PORT=$PORT
      break
    fi
  done
  echo "$ALLURE_PORT"
')
```

从 Bash 输出解析得到 `ALLURE_PORT`（如 `4040`）。若 10 个端口均被占用，输出 `[WARN]` 日志并跳过预览，不阻断流程。

#### 2.5.2 后台启动 Allure 服务 + 获取 PID

使用**单次 Bash 调用**在 shell 内部完成后台启动和 PID 获取（使用 2.5.0 发现的 `ALLURE_REPORT_DIR` 路径）：

```
Bash('
  CHANGE_DIR="openspec/changes/{change_name}"
  PID_FILE="${CHANGE_DIR}/context/allure-serve.pid"
  LOG_FILE="${CHANGE_DIR}/context/allure-serve.log"

  npx allure open {ALLURE_REPORT_DIR} --port {ALLURE_PORT} > "$LOG_FILE" 2>&1 &
  ALLURE_PID=$!
  echo "$ALLURE_PID" > "$PID_FILE"
  echo "$ALLURE_PID"
', run_in_background: false)
```

> **PID 文件路径隔离**: 写入 `${change_dir}context/allure-serve.pid`（每个 change 独立目录），避免多项目/多会话文件冲突。

#### 2.5.3 等待服务就绪

```
Bash('
  READY=false
  for i in $(seq 1 10); do
    if curl -sf http://localhost:{ALLURE_PORT} >/dev/null 2>&1; then
      READY=true
      break
    fi
    sleep 1
  done
  if [ "$READY" = true ]; then
    echo "READY"
  else
    echo "TIMEOUT"
  fi
')
```

- 输出 `READY` → 服务启动成功，进入 2.5.4
- 输出 `TIMEOUT` → 输出 `[WARN] Allure 服务未在 10 秒内就绪，使用本地文件链接作为降级`，跳过 URL 更新

#### 2.5.4 写入 allure-preview.json + 更新运行时消费链

**关键步骤**：将 Allure 预览 URL 写入 `allure-preview.json`，使 `emit-report-ready-event.sh` 和 GUI 能消费到 `allure_preview_url` 字段。

```
Bash('
  CHANGE_DIR="openspec/changes/{change_name}"
  CONTEXT_DIR="${CHANGE_DIR}/context"
  ALLURE_URL="http://localhost:{ALLURE_PORT}"

  # 1. 写入 allure-preview.json（emit-report-ready-event.sh 从此文件读取 allure_preview_url）
  echo "{\"url\": \"${ALLURE_URL}\", \"pid\": {ALLURE_PID}, \"port\": {ALLURE_PORT}}" > "${CONTEXT_DIR}/allure-preview.json"

  # 2. 更新 state-snapshot.json 的 report_state.allure_preview_url（GUI WebSocket 直接消费）
  if [ -f "${CONTEXT_DIR}/state-snapshot.json" ]; then
    TMP=$(mktemp)
    jq --arg url "$ALLURE_URL" ".report_state.allure_preview_url = \$url" "${CONTEXT_DIR}/state-snapshot.json" > "$TMP" && mv "$TMP" "${CONTEXT_DIR}/state-snapshot.json"
  fi

  # 3. 发射 report_ready 事件更新（emit-report-ready-event.sh 会自动读取 allure-preview.json）
  if [ -f "${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-report-ready-event.sh" ]; then
    CHANGES_DIR="openspec/changes"
    SESSION_ID=$(jq -r ".session_id // \"\"" "${CHANGES_DIR}/.autopilot-active" 2>/dev/null || echo "")
    bash "${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-report-ready-event.sh" "$CHANGES_DIR" "{change_name}" "{mode}" "$SESSION_ID"
  fi

  echo "[ALLURE] 预览服务已启动: ${ALLURE_URL}"
')
```

> **运行时消费链闭环**: `allure-preview.json` → `emit-report-ready-event.sh` 读取 `allure_preview_url` → 同时写入项目根 `logs/events.jsonl`（服务端归一化读取源）和 change 级日志 + 更新 `state-snapshot.json` 的 `report_state` → GUI 通过 WebSocket 消费 `report_ready` 事件中的 `allure_preview_url` 展示可点击链接。

在 Summary Box 中展示：
```
Allure Report: http://localhost:{ALLURE_PORT}
```

#### 2.5.5 服务生命周期管理

- PID 文件位于 `${change_dir}context/allure-serve.pid`（change 级隔离）
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
  - **v5.8 fixup 完整性检查**: 归档前验证 fixup 提交完整性——对比 checkpoint 数量与 fixup commit 数量：
    ```bash
    # 统计已完成的 phase checkpoint 数量
    CHECKPOINT_COUNT=$(ls openspec/changes/<name>/context/phase-results/phase-*.json 2>/dev/null | grep -v '.tmp$' | grep -v 'interim' | grep -v 'progress' | wc -l)
    # 统计 fixup commit 数量
    FIXUP_COUNT=$(git log --oneline --format='%s' ${ANCHOR_SHA}..HEAD 2>/dev/null | grep -c "^fixup! " || echo 0)
    ```
    如果 `FIXUP_COUNT < CHECKPOINT_COUNT`，**硬阻断归档**（fail-closed）：
    `[BLOCKED] fixup 完整性检查失败: ${FIXUP_COUNT} fixup commits < ${CHECKPOINT_COUNT} checkpoints. 必须确保所有 checkpoint 都有对应的 fixup commit 后才能归档。`
    → 将 `archive-readiness.json` 中 `fixup_completeness.passed` 设为 `false`
    → 归档流程中止，不提供跳过选项
  - 提交工作区残留变更：`git add -A && git diff --cached --quiet || git commit --fixup=$ANCHOR_SHA -m "fixup! autopilot: start <change_name> — final"`
  - **v5.8 fixup 范围验证**: autosquash 前列出将被合并的 fixup 提交，确认全部是 autopilot 前缀的：
    ```bash
    # 列出所有 fixup 提交，检查是否存在非 autopilot 的 fixup
    NON_AUTOPILOT_FIXUPS=$(git log --oneline --format='%s' ${ANCHOR_SHA}..HEAD 2>/dev/null | grep "^fixup! " | grep -v "^fixup! autopilot:" || true)
    ```
    如果存在非 autopilot 的 fixup 提交，AskUserQuestion 告知用户并确认是否继续
  - 读取锁文件中的 `anchor_sha`
  - 验证 anchor_sha 有效：`git rev-parse $ANCHOR_SHA` → 无效则先尝试重建：
    1. 调用 `Bash('AUTOPILOT_PROJECT_ROOT=$(pwd) bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/rebuild-anchor.sh $(pwd) ${LOCK_FILE}')`
    2. 退出码 0 → 使用 stdout 输出的新 anchor SHA，继续 autosquash 流程
    3. 退出码非 0 → **硬阻断归档**（fail-closed）：
       - `[BLOCKED] anchor 重建失败，无法执行 autosquash。归档中止。`
       - 将 `archive-readiness.json` 中 `anchor_valid` 设为 `false`
       - 禁止 "跳过 autosquash" 选项
  - 执行 `GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash $ANCHOR_SHA~1`
  - 成功 → 修改 commit message 为 `feat(autopilot): <change_name> — <summary>`
  - 失败 → `git rebase --abort`，**硬阻断归档**（fail-closed）：
    `[BLOCKED] autosquash 失败，无法合并 fixup commits。归档中止。请手动解决 rebase 冲突后重试。`

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

Phase 7 汇总展示时，输出 Summary Box（遵循 `autopilot/references/log-format.md`）：

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
│   Allure     http://localhost:{port}             │
│                                                  │
╰──────────────────────────────────────────────────╯
```

> 仅展示实际执行的阶段（lite/minimal 跳过的阶段不显示）。框内宽度固定 50 字符（纯 ASCII）。
> Allure 行仅在 Allure 服务成功启动时展示（Step 2.5 成功）。
> TDD 行仅在 `test_driven_summary` 非 null 时展示（full 模式非 TDD 模式）。{M} 为 `red_green_verified`，{N} 为 `total_tasks`。

**Archive Readiness 自动归档**: 当 archive-readiness.json 所有检查通过时，自动执行归档操作，不中断用户。仅在 readiness 检查失败时才阻断流程并请求用户决策。
