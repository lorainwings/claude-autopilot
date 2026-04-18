# Summary Box 渲染

> 本文件由 `autopilot-phase7-archive/SKILL.md` 通过 `**执行前读取**` 引用。
> 包含确定性地址收集、Summary Box 模板和渲染规则。

## 确定性地址收集（自愈 + 单脚本）

Summary Box 渲染前，通过 `collect-summary-urls.sh` 一次性确定性获取所有地址。**核心防御**：脚本内含 Allure 自愈逻辑——若 `allure-preview.json` 缺失 / PID 死亡 / URL 不通，自动调用 `start-allure-serve.sh` 兜底，避免上游 AI 步骤被跳过时 Allure 行渲染为 `unavailable`。

```bash
Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/collect-summary-urls.sh "openspec/changes/{change_name}" 4040')
```

输出单行 JSON：

```json
{
  "allure_url": "http://localhost:4041",
  "allure_pid": "12345",
  "gui_url":    "http://localhost:9527",
  "services":   {"backend": "http://localhost:8080/health"}
}
```

字段语义：

- `allure_url` — 自愈后的 Allure 报告地址（自愈失败为空字符串）
- `allure_pid` — Allure 服务 PID（用于 Step 9 输出停止命令）
- `gui_url` — GUI 大盘地址（PID 文件 + 端口监听双重校验）
- `services` — `autopilot.config.yaml` 的 `services` 字典中所有 string 类型条目

> **设计意图**：消除原内联 bash 三处独立读取 `allure-preview.json` 的不一致行为，并把"自愈"从 AI Task（Step 2.5）下沉为脚本副作用，确保 Summary Box 始终拿到最新可用的 URL。

## Summary Box 模板

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

## Quick Links 渲染规则（确定性地址）

- GUI 行：`gui_url` 非空时展示，为空时显示 `unavailable`
- Allure 行：`allure_url` 非空时展示实际地址，为空时显示 `unavailable`（**始终展示此行**，确保用户了解报告可用状态）
- Services 行：`services` 字典中每个 key-value 展示一行，字典为空时**不展示此行**
- TDD 行仅在 `test_driven_summary` 非 null 时展示（full 模式非 TDD 模式）
- **所有地址从磁盘文件读取**（allure-preview.json、GUI PID 文件、autopilot.config.yaml），不依赖 AI 在上下文中持有变量值

**Archive Readiness 自动归档**: 当 archive-readiness.json 所有检查通过时，自动执行归档操作，不中断用户。仅在 readiness 检查失败时才阻断流程并请求用户决策。
