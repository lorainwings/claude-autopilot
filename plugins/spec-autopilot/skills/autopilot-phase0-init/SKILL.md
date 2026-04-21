---
name: autopilot-phase0-init
description: "[ONLY for autopilot orchestrator] Phase 0: Environment check, config loading, crash recovery, banner rendering, task creation, lockfile management, and anchor commit."
user-invocable: false
---

# Autopilot Phase 0 — 环境检查 + 崩溃恢复

> **前置条件自检**：本 Skill 仅在 autopilot 编排主线程中使用。如果当前上下文不是 autopilot 编排流程，请立即停止并忽略本 Skill。

## 输入参数

| 参数 | 来源 |
|------|------|
| $ARGUMENTS | autopilot 主编排器传入的原始参数 |
| plugin_dir | 插件根目录路径 |

## 执行步骤

### Step 1: 读取插件版本（最优先）

从 `plugin.json` 读取版本号：`Bash("cat ${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json")`

提取 `version` 字段，**立即输出初始化提示**（先于一切其他操作让用户看到版本号）：

```
⏳ Autopilot v{version} initializing...
```

### Step 2: 检查配置文件

检查 `.claude/autopilot.config.yaml` 是否存在：
- **不存在** → 调用 Skill(`spec-autopilot:autopilot-setup`) 自动扫描项目并生成配置
- **存在** → 直接读取并解析所有配置节，然后调用 `bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/validate-config.sh` 验证 schema 完整性

**校验结果处理（fail-closed）**：

解析 JSON 输出，若 `valid === false`，**必须硬阻断流程**并展示所有非空错误类别：

| 字段 | 含义 | 处理 |
|------|------|------|
| `missing_keys` | 缺少必需配置项 | 列出每项并提示补全 |
| `type_errors` | 类型不匹配 | 列出每项并提示修正类型 |
| `enum_errors` | 值不在允许范围（含 deprecated/forbidden 值） | 列出每项并通过 **AskUserQuestion** 询问用户是否同意按错误信息中的建议值修改配置，**禁止**未经用户确认直接修改 |
| `range_errors` | 数值范围越界 | 列出每项并提示调整范围 |
| `model_routing_errors` | model_routing 配置错误 | 列出每项 |

> **硬阻断语义**：`valid === false` 时**禁止**进入 Step 3，**禁止**以任何形式继续后续 Phase。必须通过 AskUserQuestion 要求用户修复配置（或允许用户手动编辑 `.claude/autopilot.config.yaml` 后重跑 `/autopilot`）。

> **cross_ref_warnings 处理**：`cross_ref_warnings` 是信息性警告，不阻断流程。当列表非空时，展示给用户作为提醒，但允许继续。注意：部分历史提示（如 `research.agent="Explore"`）已提升为 `enum_errors` 硬错误，不再出现在 warnings 中。

- **python3 可用性检查**: 执行 `Bash("command -v python3")`
  - 如果退出码 != 0 → 输出 `[FATAL] python3 is required for autopilot Hook constraint checking. Install: brew install python3 / apt install python3`，设置 `status: "blocked"`，终止流程
  - 如果可用 → 继续

### Step 3: 解析执行模式

```
1. $ARGUMENTS 关键词匹配: "lite"/"minimal"/"full" → 直接使用
2. config.default_mode → 配置默认值
3. 未指定 → "full"

解析: $ARGUMENTS = "[mode_keyword] [actual_requirement]"
  - 首个 token 匹配 full|lite|minimal → 提取为 mode，剩余为需求
  - 不匹配 → mode 从 config 读取，整体为需求
```

### Step 4: 启动 GUI 服务器 + 展示启动 Banner（合并）

**先启动 GUI 服务器**，再将地址嵌入 Banner 统一输出，避免分两步展示。

先从已加载的 config 中读取 `gui.port`（默认 9527），计算 WS 端口（`gui.port + 1`），以环境变量形式传入脚本：

调用 `Bash("AUTOPILOT_HTTP_PORT={gui_port} AUTOPILOT_WS_PORT={gui_port+1} bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/start-gui-server.sh <project_root>")`：

其中 `{gui_port}` 从 `config.gui.port` 读取，未配置时默认 `9527`。`{gui_port+1}` 为 WS 端口（如 `9528`）。

解析脚本输出中 `GUI_SERVER_JSON:` 前缀行的 JSON，提取 `http_url` 字段作为实际 GUI 地址。

- **已存活** → 静默退出（exit 0），从 JSON 提取 `http_url`
- **未存活** → 后台启动 autopilot-server.ts，从 JSON 提取 `http_url`
- **启动失败** → GUI 行显示 `unavailable`，不阻断流程（GUI 为可选增强功能）

> **零侵入保障**: 服务器以守护进程运行，日志重定向到文件（`logs/gui-server.log`），不干扰主线程输出。

**然后渲染 Banner**（将 GUI 地址合并到 Banner 中）：

> **渲染规则**: 使用 markdown 代码块输出。框内宽度（左 `│` 与右 `│` 之间）固定 **50 字符**（纯 ASCII，禁止在框内使用 emoji 避免终端宽度歧义），每行内容不足时用空格右填充至 50 字符，确保右侧 `│` 严格垂直对齐。单字段值超长时截断并追加 `…`，保证不溢出框宽。时间使用本地时间格式 `YYYY-MM-DD HH:mm:ss`。

```
╭──────────────────────────────────────────────────╮
│                                                  │
│   Autopilot v{version}                           │
│                                                  │
│   Mode      {mode}                               │
│   Change    {change_name}                        │
│   Session   {session_id}                         │
│   Started   {YYYY-MM-DD HH:mm:ss}               │
│   GUI       {gui_url}                            │
│                                                  │
╰──────────────────────────────────────────────────╯
```

- session_id：**此时生成**毫秒级时间戳并暂存，后续步骤 9 写入锁文件时复用同一值
- change_name：此时尚未确定，显示 `pending`（Phase 1 完成后更新锁文件时回填）
- Started：使用 `date "+%Y-%m-%d %H:%M:%S"` 获取本地时间，禁止 ISO-8601 带时区偏移格式
- GUI：从 `start-gui-server.sh` 的 `GUI_SERVER_JSON:` 输出解析 `http_url` 字段，服务器启动成功时显示实际地址（如 `http://localhost:9527`），启动失败时显示 `unavailable`

### Step 4.5: 初始化事件文件 + 发射 Phase 0 开始事件（Event Bus 补全）

确保事件文件存在并发射 Phase 0 开始事件：

```bash
Bash('mkdir -p <project_root>/logs && touch <project_root>/logs/events.jsonl')
Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-phase-event.sh phase_start 0 {mode}')
```

> **必要性**: Phase 0/1 此前未接入 Event Bus，导致 GUI 在 Phase 2 之前无任何数据。此步骤确保 `events.jsonl` 在 GUI 服务器启动后立即创建，且 Phase 0 生命周期事件对 GUI 可见。

### Step 4.6: 注入历史教训（主动学习 Phase 0 入口）

Banner 渲染完成后、dispatch Phase 1 之前，读取 `autopilot-lessons` 语料，把 top-3 与当前需求相似的历史教训注入后续 dispatch prompt。

> **Recovery 跳过**：若本次为崩溃恢复（即将在后续步骤中被设定 `recovery_phase > 0`），且 `.autopilot-lessons.json` 已存在，则**跳过本步骤**避免重复 IO 与覆盖。判定方式：检测 lock 文件中是否含历史 anchor_sha + episode 文件存在 → skip。

```bash
LESSONS_FILE="$(pwd)/openspec/changes/.autopilot-lessons.json"
if [ ! -f "$LESSONS_FILE" ]; then
  LESSONS_JSON=$(bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/learn-inject-top-lessons.sh \
    --raw-requirement "$ARGUMENTS" \
    --episodes-root "$(pwd)/docs/reports" \
    --top 3 2>/dev/null || echo "[]")
  # 结果写入 openspec/changes/.autopilot-lessons.json，供 autopilot-dispatch 在构造子 Agent prompt 时读取并以 "历史教训" 区块注入
  echo "$LESSONS_JSON" > "$LESSONS_FILE"
fi
```

空语料（首次运行或无历史 episode）返回 `[]`，不阻断流程。详见 `skills/autopilot-learn/SKILL.md`。

### Step 5: 检查必需插件

读取 `.claude/settings.json` 的 `enabledPlugins` → 仅检查 `spec-autopilot` 是否已启用。不列出、不评判其他无关插件（忽略 enabledPlugins 中的其余条目）。

### Step 6: 崩溃恢复

调用 Skill(`spec-autopilot:autopilot-recovery`)：扫描 checkpoint + progress 文件，决定起始阶段和子步骤恢复点

> Recovery 同时扫描 `phase-{N}-progress.json` 实现子步骤粒度恢复

### Step 6.1: 事件文件恢复清理

根据崩溃恢复决策清理事件文件：

**从头开始** → 清空事件文件和序列计数器，让 GUI 从零状态重新开始：

```bash
Bash(': > <project_root>/logs/events.jsonl && rm -f <project_root>/logs/.event_sequence')
Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-phase-event.sh phase_start 0 {mode}')
```

> Step 4.5 已发射的 phase_start 0 事件在截断时被清除，此处重新发射。

**从断点继续** → 不清理事件文件（保留历史事件供 GUI 展示已完成 Phase）。

### Step 7: 创建阶段任务（恢复状态增强, 顺序强制）

使用 TaskCreate 创建阶段任务 + blockedBy 依赖链：
- **full 模式**: 创建 Phase 1-7（7 个任务）
- **lite 模式**: 创建 Phase 1, 5, 6, 7（4 个任务），Phase 5 blockedBy Phase 1，Phase 6 blockedBy Phase 5
- **minimal 模式**: 创建 Phase 1, 5, 7（3 个任务），Phase 5 blockedBy Phase 1

**创建顺序强制约束**: TaskCreate 调用**必须严格按 Phase 编号升序**逐个执行（Phase 1 → 2 → 3 → 4 → 5 → 6 → 7），**禁止**乱序创建或并行创建。Task 列表的展示顺序取决于创建顺序，乱序创建会导致 Phase 编号在任务列表中错位（如 1,2,5,4,3,7,6），严重影响用户体验。

**崩溃恢复时的任务状态标记**（基于 `recovery_phase`）：

对 `get_phase_sequence(mode)` 返回的每个阶段 P：
- **P < recovery_phase** → TaskCreate 后立即 TaskUpdate status = `completed`
- **P == recovery_phase** → TaskCreate 后立即 TaskUpdate status = `in_progress`
- **P > recovery_phase** → 保持默认 `pending` 状态

> 之前仅将 P < recovery 标记为 completed。现在额外将 P == recovery 标记为 in_progress，使 GUI 和任务列表准确反映当前工作阶段。

### Step 8: 确保锁文件被 gitignore

检查项目根目录 `.gitignore` 是否包含 `.autopilot-active`，若不包含则追加：

```bash
echo '.autopilot-active' >> .gitignore
```

> 此文件是会话级运行时锁，包含 PID/session_id 等本机信息，禁止提交到 git。

### Step 9: 创建锁文件（确定性脚本）

直接通过 Bash 调用独立脚本创建锁文件（替代原有后台 Agent）：

```bash
Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/create-lockfile.sh "${session_cwd}" '"'"'${lock_json}'"'"'')
```

解析返回的 JSON：
- `status: ok` → 继续 Step 10
- `status: conflict` → AskUserQuestion 由用户决定覆盖/中止

> **原子性**：初次写入时 `anchor_sha` 设为空字符串，Step 10 创建 commit 后更新。

### Step 10: 创建锚定 Commit（确定性更新）

为后续 fixup + autosquash 策略创建空锚定 commit：

```bash
git commit --allow-empty -m "autopilot: start <change_name>"
ANCHOR_SHA=$(git rev-parse HEAD)
```

直接通过 Bash 调用独立脚本更新锁文件中的 `anchor_sha` 字段（替代原有后台 Agent）：

```bash
Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/update-anchor-sha.sh "${session_cwd}/openspec/changes/.autopilot-active" "${ANCHOR_SHA}"')
```

> **原子性保障**：如果 Step 10 之前崩溃，恢复时检测到 `anchor_sha` 为空 → 重新创建锚定 commit 并更新。Phase 7 autosquash 前**必须**验证 `anchor_sha` 非空且 `git rev-parse ${ANCHOR_SHA}^{commit}` 有效；无效时必须先重建 anchor，重建失败则**硬阻断归档**。

---

### Step 10.5: 发射 Phase 0 结束事件（Event Bus 补全）

```bash
Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-phase-event.sh phase_end 0 {mode} \'{"status":"ok","duration_ms":{elapsed},"artifacts":["lockfile","anchor_commit"]}\'')
```

---

## 输出

Phase 0 完成后，主编排器获得：

| 数据 | 用途 |
|------|------|
| version | 插件版本号 |
| mode | 执行模式（full/lite/minimal） |
| session_id | 毫秒级时间戳 |
| ANCHOR_SHA | 锚定 commit SHA |
| config | 完整配置对象 |
| recovery_phase | 崩溃恢复起始阶段（正常为 1） |

> **Checkpoint 范围**: Phase 0 在主线程执行，不写 checkpoint。

---

## 锁文件管理（确定性脚本重构）

管理 `${session_cwd}/openspec/changes/.autopilot-active` 锁文件的完整生命周期。通过 python3 内联脚本 + 原子写入（tempfile + os.replace）确保确定性。

### 锁文件路径

```
${session_cwd}/openspec/changes/.autopilot-active
```

### 锁文件 JSON 格式

```json
{
  "change": "<change_name>",
  "pid": "<当前进程PID>",
  "started": "<ISO-8601时间戳>",
  "session_cwd": "<项目根目录>",
  "anchor_sha": "<SHA|空字符串>",
  "session_id": "<毫秒级时间戳>",
  "mode": "<full|lite|minimal>"
}
```

### 操作 1: 创建锁文件（Step 9）

直接 Bash 调用 python3 内联脚本，含 PID 冲突检测 + 原子写入。详见 Step 9。

#### PID 冲突检测逻辑

| 条件 | 判定 | 处理 |
|------|------|------|
| PID 存活 + session_id 匹配 | 同一进程 | 返回 `conflict`，主线程 AskUserQuestion |
| PID 存活 + session_id 不匹配 | PID 被系统回收 | 自动覆盖，返回 `overwritten` |
| PID 不存在 | 崩溃残留 | 自动覆盖，返回 `overwritten` |

### 操作 2: 更新 anchor_sha（Step 10）

直接 Bash 调用 python3 内联脚本，原子更新 JSON + 验证。详见 Step 10。

### 操作 3: 删除锁文件（Phase 7 Step 7）

由 `autopilot-phase7` 直接执行：`Bash('rm -f ${session_cwd}/openspec/changes/.autopilot-active')`

### 日志格式

遵循 `autopilot/references/log-format.md` 规范：

```
[LOCK] created: .autopilot-active
[LOCK] updated: anchor_sha → {short_sha}
[LOCK] deleted: .autopilot-active
[LOCK] conflict: PID {pid} (started {time})
```
