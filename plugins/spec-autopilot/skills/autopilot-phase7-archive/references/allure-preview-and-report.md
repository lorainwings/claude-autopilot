# Allure 本地预览 + Test Report 线框

> 本文件由 `autopilot-phase7-archive/SKILL.md` 通过 `**执行前读取**` 引用。
> 包含 Step 2.5（Allure 预览服务启动）和 Step 2.6（Test Report 线框渲染）。

## Step 2.5: Allure 本地预览（v8.0 子 Agent 委托）

> 当 Allure 产物存在时执行。v8.0 将原主线程内联的 ~170 行 Bash 操作委托给后台子 Agent，减少主窗口上下文污染。

派发**前台 Task**（非后台）处理 Allure 预览全流程：

```
Task(subagent_type: "general-purpose", prompt: "
  你是 Allure 预览服务启动子 Agent。按以下步骤执行：

  1. 搜索 allure-results/ (三条路径优先级: Phase 6 checkpoint 的 allure_results_dir 字段 > change 级 reports/allure-results/ > 项目根 allure-results/)
  2. 搜索 allure-report/ (同级目录或项目根)
  3. 如存在 results 但无 report，执行 npx allure generate
  4. 如 Phase 6 checkpoint 的 allure_report_generated === false，尝试 fallback generate（使用 Phase 6 checkpoint 的 allure_results_dir 字段）
  5. 从 .claude/autopilot.config.yaml 读取 phases.reporting.allure.serve_port (默认 4040)
  6. 检测端口可用性 (尝试 base_port 到 base_port+9)
  7. 后台启动 npx allure open，写入 PID 文件到 ${change_dir}context/allure-serve.pid
  8. 等待服务就绪 (最多10秒 curl 轮询)
  9. 写入 ${change_dir}context/allure-preview.json（关键：Summary Box 从此文件读取 URL）
  10. 更新 state-snapshot.json 的 report_state.allure_preview_url
  11. 调用 emit-report-ready-event.sh 发射事件

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
>
> 1. `allure-preview.json` 在 Summary Box 渲染前已写入磁盘
> 2. `state-snapshot.json` 已更新
> 3. `report_ready` 事件已发射
>
> **上下文优化仍有效**: 子 Agent 内部的 ~170 行 Bash 操作不进入主线程上下文，主线程仅接收 JSON 信封。

### 服务生命周期管理

- PID 文件位于 `${change_dir}context/allure-serve.pid`（change 级隔离，由子 Agent 写入）
- **服务保活策略**：Allure 服务在 Phase 7 归档后**不自动 kill**。服务保持运行确保用户可随时通过 Summary Box 链接查看报告。Step 9 输出停止命令提示，由用户自行决定停止时机。

## Step 2.6: Test Report 线框（v9.0 测试报告即时可见）

> **仅 full 和 lite 模式**。minimal 模式跳过此步骤（无 Phase 6）。

在 Allure 服务启动（Step 2.5）完成后，立即渲染 **Test Report 线框**，确保用户在归档前即可查看测试结果和报告访问地址。

### 数据收集

从以下来源确定性读取数据（不依赖主线程上下文变量）：

1. **测试结果**: 从 Phase 6 checkpoint（`phase-6-report.json`）读取 `suite_results`（total/passed/failed/skipped）
2. **Allure 地址**: 从 Step 2.5 子 Agent 返回的 JSON 信封提取 `url` 字段，或从 `${change_dir}context/allure-preview.json` 读取

```bash
Bash('
  CHANGE_DIR="openspec/changes/{change_name}"
  CONTEXT_DIR="${CHANGE_DIR}/context"

  # 1. 从 Phase 6 checkpoint 读取测试结果
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

  # 2. 从 allure-preview.json 读取 Allure 地址
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

### 线框渲染

从 Bash 输出解析 JSON，渲染 Test Report 线框：

> **渲染规则**: 使用 markdown 代码块输出。框内宽度固定 **50 字符**（纯 ASCII），与 Banner 和 Summary Box 一致。

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
