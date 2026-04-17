# Allure 本地预览 + Test Report 线框

> 本文件由 `autopilot-phase7-archive/SKILL.md` 通过 `**执行前读取**` 引用。
> 包含 Step 2.5（Allure 预览服务启动）和 Step 2.6（Test Report 线框渲染）。

## Step 2.5: Allure 本地预览（验证+兜底模式）

> Phase 6 Step A5.5 已在测试完成后立即启动 Allure 预览服务。
> 本步骤优先验证已有服务，仅在需要时执行兜底启动。

派发**前台 Task**（非后台）处理 Allure 预览验证/兜底：

```
Task(subagent_type: config.phases.archive.agent, prompt: "
  你是 Allure 预览服务验证子 Agent。按以下步骤执行：

  ## Step 1: 检查已有服务
  检查 ${change_dir}context/allure-preview.json 是否存在：
  - 若存在：读取 pid 和 url 字段
    - 验证 PID 是否存活（kill -0 $PID）
    - 验证 URL 是否可访问（curl -s -o /dev/null -w '%{http_code}' $URL | grep '200\|301\|302'）
    - 两者均通过 → 返回 {\"status\": \"ok\", \"url\": \"...\", \"pid\": ..., \"reused\": true}
    - PID 不存活或 URL 不可访问 → 继续 Step 2（兜底重启）

  ## Step 2: 兜底启动（仅在 Step 1 验证失败时执行）
  调用统一启动脚本：
  bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/start-allure-serve.sh '${change_dir}' ${base_port}

  解析返回 JSON 并透传。

  ## Step 3: 后续更新（仅在 Step 2 执行了新启动时）
  - 更新 state-snapshot.json 的 report_state.allure_preview_url（脚本已自动处理）
  - 调用 emit-report-ready-event.sh 发射事件（脚本未自动处理时补充调用）

  返回 JSON 信封:
  {\"status\": \"ok\", \"summary\": \"Allure 预览服务运行中\", \"url\": \"http://localhost:{port}\", \"pid\": {pid}}
  或
  {\"status\": \"skipped\", \"summary\": \"无 allure 产物，跳过预览\"}
  或
  {\"status\": \"warning\", \"summary\": \"Allure 报告生成/启动失败\", \"error\": \"...\"}
")
```

> **设计决策**: Phase 6 已在测试完成后启动服务，Phase 7 仅验证存活性。
> 如果 Phase 6 的启动因任何原因失败（如端口冲突、allure 未安装等），
> Phase 7 此步骤作为最后兜底确保服务可用。

### 服务生命周期管理

- PID 文件位于 `${change_dir}context/allure-serve.pid`（change 级隔离，由 Phase 6 Step A5.5 或本步骤兜底写入）
- **服务保活策略**：Allure 服务在 Phase 7 归档后**不自动 kill**。服务保持运行确保用户可随时通过 Summary Box 链接查看报告。Step 9 输出停止命令提示，由用户自行决定停止时机。
- **启动时机**：Phase 6 完成后立即启动（Step A5.5），Phase 7 仅验证+兜底（本步骤）

## Step 2.6: Test Report 线框（测试报告即时可见）

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
