---
name: autopilot-phase7-archive
description: "Use when the autopilot orchestrator reaches Phase 7 after Phase 6 tri-path reports are available and must finalize the delivery by collecting summaries, extracting knowledge, previewing Allure, and evaluating archive readiness. [ONLY for autopilot orchestrator]"
user-invocable: false
---

# Autopilot Phase 7 — 汇总 + Archive Readiness 自动归档

> **前置条件自检**：本 Skill 仅在 autopilot 编排主线程中使用。如果当前上下文不是 autopilot 编排流程，请立即停止并忽略本 Skill。

**执行前读取**: `autopilot/references/log-format.md`（Summary Box 渲染规范）

## 执行步骤

### Step -1: 发射 Phase 7 开始事件（Event Bus 补全）

```bash
Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-phase-event.sh phase_start 7 {mode}')
```

### Step 0: 写入 Phase 7 Checkpoint（进行中）

调用 Skill(`spec-autopilot:autopilot-gate`) checkpoint 管理写入 `phase-7-summary.json`：

```json
{"status": "in_progress", "phase": 7, "description": "Archive and cleanup"}
```

**进度写入**: `Bash('AUTOPILOT_PROJECT_ROOT=$(pwd) bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/write-phase-progress.sh 7 summary_dispatched in_progress')`

### Step 0.5: 主动学习 — Episodes 写入与候选晋升扫描

归档前，对本次 autopilot 全部 phase 写入 episode 并触发 L2/L3 学习：

```bash
# 1) 为 Phase 1-6 每个 phase 写 episode（status/mode 由脚本从 checkpoint JSON 自动解析）
for N in 1 2 3 4 5 6; do
  CKPT=$(ls openspec/changes/{change_name}/context/phase-results/phase-${N}-*.json 2>/dev/null | head -1)
  [ -n "$CKPT" ] && bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/learn-episode-write.sh \
    --phase phase${N} --checkpoint "$CKPT" --version {version} || true
done

# 2) 触发 L2 聚合 + L3 候选晋升扫描
Skill(spec-autopilot:autopilot-learn)

# 3) 候选晋升扫描产物：docs/learned/candidates/*.md（待人工/下一轮 gate 审阅）
bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/learn-promote-candidate.sh \
  --episodes-root docs/reports \
  --out-dir docs/learned/candidates || true
```

不阻断归档流程（学习失败 stderr 提示但 exit 0）。详见 `skills/autopilot-learn/SKILL.md`。

### Step 1: 派发汇总子 Agent

前台 Task 读取所有 checkpoint 并生成汇总（上下文保护增强）：

```
Task(subagent_type: config.phases.archive.agent, prompt: "
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

- 派发后台 Agent：`Task(subagent_type: config.phases.archive.agent, run_in_background: true)`
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
- warning → 写入 checkpoint（status: warning，含 findings），展示 findings，不阻断归档
- blocked → 写入 checkpoint（status: blocked，含 critical findings），展示 critical findings，但**不得**在 Step 2 提供"忽略继续归档"选项；后续是否可继续由 Step 3 的 archive-readiness fail-closed 判定统一处理
- code_review 未启用 → 跳过
- JSON 解析失败 → 写入 checkpoint（status: warning，含原始文本），展示原始文本

b. **质量扫描**（路径 C）：展示质量汇总表（含得分和阈值对比）

- 硬超时：`config.async_quality_scans.timeout_minutes`（默认 10 分钟），超时标记 `"timeout"`
- JSON 解析失败 → 展示原始文本，标记 warning

c. **知识提取**（Step 1.6 后台 Agent）：等待完成，展示提取结果

### Step 2.5-2.6: Allure 预览 + Test Report 线框

**执行前读取**: `references/allure-preview-and-report.md`（Allure 服务启动 + Test Report 渲染）

- Step 2.5：派发前台 Task 启动 Allure 预览服务（含 fallback generate）
- Step 2.6：从 Phase 6 checkpoint 和 allure-preview.json 读取数据，渲染 Test Report 线框

### Step 3-5: Archive Readiness + 归档

**执行前读取**: `references/archive-readiness.md`（检查项定义 + 判定逻辑 + 归档操作 + 阻断处理）

- Step 3：构建 `archive-readiness.json`，统一判定（fail-closed）
- Step 4：archive readiness 通过后自动执行归档（git autosquash + OpenSpec 归档）
- Step 5：阻断时的用户选择（修复重检 / 放弃归档）

### Step 6: 归档后处理

归档完成后自动进入后续清理步骤（Step 6.5、7、8），无需额外确认。

> **Allure 服务保活**：Step 2.5 启动的 Allure 预览服务**不在归档时清理**。服务保持运行直到用户手动停止，确保 Summary Box 中展示的链接可用。

### Step 6.5: 发射 Phase 7 结束事件（Event Bus 补全）

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
  PREVIEW_FILE="openspec/changes/{change_name}/context/allure-preview.json"
  P6_CHECKPOINT="openspec/changes/{change_name}/context/phase-results/phase-6-report.json"
  if [ -f "$PID_FILE" ]; then
    ALLURE_PID=$(cat "$PID_FILE")
    if kill -0 "$ALLURE_PID" 2>/dev/null; then
      # 读取 Allure URL
      ALLURE_URL=""
      if [ -f "$PREVIEW_FILE" ]; then
        ALLURE_URL=$(python3 -c "import json; print(json.load(open(\"$PREVIEW_FILE\")).get(\"url\",\"\"))" 2>/dev/null || echo "")
      fi
      # 读取测试统计
      TOTAL=0; PASSED=0; FAILED=0
      if [ -f "$P6_CHECKPOINT" ]; then
        TOTAL=$(python3 -c "import json; d=json.load(open(\"$P6_CHECKPOINT\")); print(sum(s.get(\"total\",0) for s in d.get(\"suite_results\",[])))" 2>/dev/null || echo 0)
        PASSED=$(python3 -c "import json; d=json.load(open(\"$P6_CHECKPOINT\")); print(sum(s.get(\"passed\",0) for s in d.get(\"suite_results\",[])))" 2>/dev/null || echo 0)
        FAILED=$(python3 -c "import json; d=json.load(open(\"$P6_CHECKPOINT\")); print(sum(s.get(\"failed\",0) for s in d.get(\"suite_results\",[])))" 2>/dev/null || echo 0)
      fi
      echo "[ALLURE] 预览服务运行中 (PID: $ALLURE_PID)"
      [ -n "$ALLURE_URL" ] && echo "  报告地址: $ALLURE_URL"
      [ "$TOTAL" -gt 0 ] 2>/dev/null && echo "  测试统计: $TOTAL 总计 / $PASSED 通过 / $FAILED 失败"
      echo "  查看完报告后运行以下命令停止:"
      echo "    kill $ALLURE_PID"
    else
      rm -f "$PID_FILE"
    fi
  fi
')
```

> **设计意图**：不自动 kill Allure 服务，确保 Summary Box 中的链接在用户查看期间始终可用。用户查看完后自行停止。

---

## Summary Box 渲染

**执行前读取**: `references/summary-box.md`（确定性地址收集 + 模板 + 渲染规则）

Phase 7 汇总展示时，输出 Summary Box（遵循 `autopilot/references/log-format.md`）。从磁盘文件确定性读取 Allure URL、GUI URL、Services 地址，渲染固定宽度线框。
