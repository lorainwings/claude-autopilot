# Summary Box 渲染

> 本文件由 `autopilot-phase7-archive/SKILL.md` 通过 `**执行前读取**` 引用。
> 包含确定性地址收集、Summary Box 模板和渲染规则。

## 确定性地址收集（v8.0 — 从磁盘读取，不依赖上下文变量）

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

## Quick Links 渲染规则（v8.0 确定性地址）

- GUI 行：`gui_url` 非空时展示，为空时显示 `unavailable`
- Allure 行：`allure_url` 非空时展示实际地址，为空时显示 `unavailable`（**始终展示此行**，确保用户了解报告可用状态）
- Services 行：`services` 字典中每个 key-value 展示一行，字典为空时**不展示此行**
- TDD 行仅在 `test_driven_summary` 非 null 时展示（full 模式非 TDD 模式）
- **所有地址从磁盘文件读取**（allure-preview.json、GUI PID 文件、autopilot.config.yaml），不依赖 AI 在上下文中持有变量值

**Archive Readiness 自动归档**: 当 archive-readiness.json 所有检查通过时，自动执行归档操作，不中断用户。仅在 readiness 检查失败时才阻断流程并请求用户决策。
