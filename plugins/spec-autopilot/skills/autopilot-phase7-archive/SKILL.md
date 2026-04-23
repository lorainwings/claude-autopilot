---
name: autopilot-phase7-archive
description: "Use when the autopilot orchestrator reaches Phase 7 after Phase 6 tri-path reports are available and must finalize the delivery by collecting summaries, extracting knowledge, previewing Allure, and evaluating archive readiness."
user-invocable: false
---

# Autopilot Phase 7 — 汇总 + Archive Readiness 自动归档

> **前置条件自检**：本 Skill 仅在 autopilot 编排主线程中使用。如果当前上下文不是 autopilot 编排流程，请立即停止并忽略本 Skill。

> **派发铁律**：主线程**必须**通过 `Task(subagent_type=autopilot-phase7-archive)` 派发本协议；**严禁**主线程自行做汇总展示、知识提取、Allure 预览、Archive Readiness 业务判定或 git autosquash。主线程仅负责派发、解析信封、根据 readiness 决策归档/阻断、调用确定性脚本清理锁文件。

> **执行步骤编号约定**：本 SKILL 中 `Step -1 / 0 / 0.5 / 1.6 / 6.5` 等含负数为前置事件、小数为子步骤，对应 Phase 7 协议文档中各阶段编号；非顺序连续不视为缺失。

**执行前读取**: `references/log-format.md`（Summary Box 渲染规范）

## 执行步骤

### Step -1: 发射 Phase 7 开始事件（Event Bus 补全）

```bash
# TODO(P1): 抽为 ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-phase-start.sh，SKILL 仅传 mode
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

前台 Task 读取所有 checkpoint 并生成汇总：

```
# 主线程先解析配置（subagent_type 必须为字面量字符串）
RESOLVED_AGENT=$(yq '.phases.archive.agent' .claude/autopilot.config.yaml)

# 然后用字面量调用 Task
Task(subagent_type: <RESOLVED_AGENT 字面量>, prompt: "
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

> **subagent_type 约束**：必须为字面量字符串（CLAUDE.md §子 Agent 约束 第 10 条），不得直接传 `config.phases.archive.agent`。

从返回信封提取并展示：

- 阶段状态汇总表（`phase_summary`）
- 测试驱动统计（`test_driven_summary`，仅 full 模式非 TDD 时展示）
- 测试报告汇总表 + Allure 报告链接（`test_report`，仅 full/lite 模式）
- 阶段耗时表格和分布图（`metrics`）

> **Phase 6 checkpoint 不存在时**（minimal 模式）：子 Agent 跳过测试报告部分

### Step 1.6: 知识提取（后台子 Agent）

- 主线程先解析 `RESOLVED_AGENT=$(yq '.phases.archive.agent' .claude/autopilot.config.yaml)`
- 派发后台 Agent：`Task(subagent_type: <RESOLVED_AGENT 字面量>, run_in_background: true)`（subagent_type 必须为字面量字符串，不得直接传 `config.phases.archive.agent`）
- Agent 任务：读取 autopilot skill 的 knowledge-accumulation 章节 → 遍历 phase-results → 提取知识 → 写入 `openspec/.autopilot-knowledge.json`
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
- blocked → 写入 checkpoint（status: blocked，含 critical findings），展示 critical findings；后续是否可继续由 Step 3 archive-readiness fail-closed 统一处理（详见 `references/archive-readiness.md`）
- code_review 未启用 → 跳过
- JSON 解析失败 → 写入 checkpoint（status: warning，含原始文本），展示原始文本

b. **质量扫描**（路径 C）：展示质量汇总表（含得分和阈值对比）

- 硬超时：`config.async_quality_scans.timeout_minutes`（默认 10 分钟），超时标记 `"timeout"`
- JSON 解析失败 → 展示原始文本，标记 warning

c. **知识提取**（Step 1.6 后台 Agent）：等待完成，展示提取结果

### Step 2.5: Allure 预览

**执行前读取**: `references/allure-preview-and-report.md`（Allure 服务启动 + Test Report 渲染）

派发前台 Task 启动 Allure 预览服务（含 fallback generate）。

### Step 2.6: Test Report 线框

从 Phase 6 checkpoint 和 allure-preview.json 读取数据，渲染 Test Report 线框（详见 `references/allure-preview-and-report.md`）。

### Step 3-5: Archive Readiness + 归档

**执行前读取**: `references/archive-readiness.md`（检查项定义 + 判定逻辑 + 归档操作 + 阻断处理）

- Step 3：构建 `archive-readiness.json`，统一判定（fail-closed）
- Step 4：archive readiness 通过后自动执行归档（git autosquash + OpenSpec 归档）
- Step 5：阻断时的用户选择（修复重检 / 放弃归档）

### Step 6: 归档后处理

归档完成后自动进入后续清理步骤（Step 6.5、7、8），无需额外确认。Allure 服务保活策略详见 `references/allure-preview-and-report.md` § 服务生命周期管理。

### Step 6.5: 发射 Phase 7 结束事件（Event Bus 补全）

```bash
# TODO(P1): 抽为 ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-phase-end.sh，SKILL 仅传 duration/artifacts
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

### Step 9: Allure 服务提示（确定性输出，始终展示）

无论 Allure 服务是否存活，都必须输出一行 `[ALLURE]` 状态提示，避免用户在 Summary Box 之外看不到任何 Allure 状态线索。

```bash
# TODO(P1): 抽为 ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-allure-hint.sh；
# 脚本职责：读取 PID 文件 + allure-preview.json + phase-6 checkpoint，输出 [ALLURE] 提示行
# 当前保留内联实现直至脚本落地。
Bash('
  PID_FILE="openspec/changes/{change_name}/context/allure-serve.pid"
  PREVIEW_FILE="openspec/changes/{change_name}/context/allure-preview.json"
  if [ -f "$PID_FILE" ]; then
    ALLURE_PID=$(cat "$PID_FILE")
    if kill -0 "$ALLURE_PID" 2>/dev/null; then
      ALLURE_URL=""
      if [ -f "$PREVIEW_FILE" ]; then
        ALLURE_URL=$(python3 -c "import json; print(json.load(open(\"$PREVIEW_FILE\")).get(\"url\",\"\"))" 2>/dev/null || echo "")
      fi
      echo "[ALLURE] 预览服务运行中 (PID: $ALLURE_PID)"
      [ -n "$ALLURE_URL" ] && echo "  报告地址: $ALLURE_URL"
      echo "  查看完报告后运行以下命令停止: kill $ALLURE_PID"
    else
      rm -f "$PID_FILE"
      echo "[ALLURE] 预览服务进程已退出 (stale PID 已清理)"
      echo "  重启命令: bash \$CLAUDE_PLUGIN_ROOT/runtime/scripts/start-allure-serve.sh openspec/changes/{change_name}"
    fi
  else
    echo "[ALLURE] 预览服务未启动 (无 allure-results 产物或上游 Phase 4/5/6 未触发自愈)"
    echo "  手动启动: bash \$CLAUDE_PLUGIN_ROOT/runtime/scripts/start-allure-serve.sh openspec/changes/{change_name}"
  fi
')
```

> **设计意图**：原版本 PID 文件不存在时静默无输出，导致用户不知道 Allure 是否启动过。新版本三态全展示（运行中 / 已退出 / 未启动），并附手动启动命令兜底。

---

## Summary Box 渲染（强制 Step）

**执行前读取**: `references/summary-box.md`（确定性地址收集 + 模板 + 渲染规则）

Phase 7 汇总展示时，输出 Summary Box（遵循 `references/log-format.md`）。**必须**通过以下确定性 Bash 调用渲染，禁止仅依赖 references 中的代码块由 AI 自行决定是否执行：

```bash
CHANGE_DIR="openspec/changes/{change_name}"
BASE_PORT=$(python3 -c "import yaml; cfg=yaml.safe_load(open('.claude/autopilot.config.yaml')); print(cfg.get('phases',{}).get('reporting',{}).get('allure',{}).get('serve_port',4040))" 2>/dev/null || echo 4040)

# Step S1: 确定性地址收集（含 Allure 自愈）
URLS_JSON=$(bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/collect-summary-urls.sh "$CHANGE_DIR" "$BASE_PORT")

# Step S2: 渲染 Summary Box，从磁盘文件确定性读取 Allure URL、GUI URL、Services 地址
#         模板与字段填充规则详见 references/summary-box.md
echo "$URLS_JSON" | python3 -c "
import json, sys
data = json.loads(sys.stdin.read() or '{}')
allure = data.get('allure_url') or 'unavailable'
gui    = data.get('gui_url') or 'unavailable'
svcs   = data.get('services') or {}
# AI 在此基础上叠加 Phase 状态行 / Duration / Pass Rate / TDD 行
print('[SUMMARY-URLS] allure=' + allure + ' gui=' + gui + ' services=' + str(len(svcs)))
"
```

> **设计意图（根因修复）**：原方案把 `collect-summary-urls.sh` 调用埋在 references/summary-box.md 的代码块中，依赖 AI "执行前读取" 后是否真的执行。现把调用提升为 SKILL.md 顶层强制 Step，且把 `CHANGE_DIR` 提取为变量显式传入，避免 `{change_name}` 占位符未被替换时静默失败。

> Summary Box 完整模板渲染（含 Phase 状态行、Quick Links 子框）：见 `references/summary-box.md`。AI 仍需按照该模板组装最终 Summary Box，但 Allure URL / GUI URL / Services 字段**必须**来自上方 `URLS_JSON` 的解析结果，禁止再独立读取 `allure-preview.json`。
