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
  执行 bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/collect-metrics.sh 收集执行指标。
  生成以下格式的 JSON 信封返回（禁止返回 checkpoint 原文）：
  {
    \"status\": \"ok\",
    \"phase_summary\": [{\"phase\": N, \"status\": \"ok|warning|blocked\", \"description\": \"...\"}],
    \"test_report\": {\"format\": \"allure|custom\", \"path\": \"...\", \"suites\": [...], \"anomaly_alerts\": \"...\"},
    \"metrics\": {\"markdown_table\": \"...\", \"ascii_chart\": \"...\"}
  }
")
```

从返回信封提取并展示：
- 阶段状态汇总表（`phase_summary`）
- 测试报告汇总表 + Allure 报告链接（`test_report`，仅 full/lite 模式）
- 阶段耗时表格和分布图（`metrics`）

> **Phase 6 checkpoint 不存在时**（minimal 模式）：子 Agent 跳过测试报告部分

### Step 1.6: 知识提取（后台子 Agent）

- 派发后台 Agent：`Task(subagent_type: "general-purpose", run_in_background: true)`
- Agent 任务：读取 `references/knowledge-accumulation.md` → 遍历 phase-results → 提取知识 → 写入 `openspec/.autopilot-knowledge.json`
- 主线程同时继续执行步骤 2，不阻塞
- 在步骤 3 AskUserQuestion 前等待完成，展示：「已提取 N 条知识（M 条 pitfall，K 条 decision）」

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
  - blocked → 写入 `phase-6.5-code-review.json` checkpoint（status: blocked，含 critical findings），展示 critical findings，向用户展示但**不阻断** Phase 7 整体流程（用户可选择修复后重试或忽略继续归档）。**用户选择"忽略继续归档"时**：将 checkpoint status 从 `blocked` 更新为 `warning`，并追加 `"user_override": true, "override_reason": "user chose to ignore critical findings"` 字段，确保 Step 3 和 Gate 检查能正常读取
  - code_review 未启用 → 跳过
  - JSON 解析失败 → 写入 `phase-6.5-code-review.json` checkpoint（status: warning，含原始文本），展示原始文本

b. **质量扫描**（路径 C）：展示质量汇总表（含得分和阈值对比）
  - 硬超时：`config.async_quality_scans.timeout_minutes`（默认 10 分钟），超时标记 `"timeout"`
  - JSON 解析失败 → 展示原始文本，标记 warning

c. **知识提取**（Step 1.6 后台 Agent）：等待完成，展示提取结果

### Step 2.5: Allure 本地预览

> 仅当 `config.phases.reporting.format === "allure"` 且 allure-report 目录存在时执行。

- 后台启动预览服务器：`Bash('npx allure open allure-report', run_in_background: true)`
- 展示访问地址：`Allure Report: http://localhost:<port>/`
- 服务器随归档完成后自动清理

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

### Step 4: 归档操作（用户选择"立即归档"）

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
│                                                  │
╰──────────────────────────────────────────────────╯
```

> 仅展示实际执行的阶段（lite/minimal 跳过的阶段不显示）。框内宽度固定 50 字符（纯 ASCII）。

**Archive Readiness 自动归档**: 当 archive-readiness.json 所有检查通过时，自动执行归档操作，不中断用户。仅在 readiness 检查失败时才阻断流程并请求用户决策。
