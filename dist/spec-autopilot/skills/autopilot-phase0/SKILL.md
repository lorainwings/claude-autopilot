---
name: autopilot-phase0
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

从 `plugin.json` 读取版本号：`Bash("cat <plugin_dir>/.claude-plugin/plugin.json")`

提取 `version` 字段，**立即输出初始化提示**（先于一切其他操作让用户看到版本号）：

```
⏳ Autopilot v{version} initializing...
```

### Step 2: 检查配置文件

检查 `.claude/autopilot.config.yaml` 是否存在：
- **不存在** → 调用 Skill(`spec-autopilot:autopilot-init`) 自动扫描项目并生成配置
- **存在** → 直接读取并解析所有配置节，然后调用 `bash scripts/validate-config.sh` 验证 schema 完整性（valid=false 时展示 missing_keys 并提示修复）
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

### Step 4: 启动 GUI 服务器 + 展示启动 Banner（v5.2 合并）

**先启动 GUI 服务器**，再将地址嵌入 Banner 统一输出，避免分两步展示。

调用 `Bash("bash <plugin_dir>/scripts/start-gui-server.sh <project_root>")`：

- **已存活** → 静默退出（exit 0），GUI 地址仍为 `http://localhost:9527`
- **未存活** → 后台启动 autopilot-server.ts，GUI 地址为 `http://localhost:9527`
- **启动失败** → GUI 行显示 `unavailable`，不阻断流程（GUI 为可选增强功能）

> **零侵入保障**: 服务器以守护进程运行，日志重定向到 `/dev/null`，不干扰主线程输出。

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
│   GUI       http://localhost:9527                │
│                                                  │
╰──────────────────────────────────────────────────╯
```

- session_id：**此时生成**毫秒级时间戳并暂存，后续步骤 9 写入锁文件时复用同一值
- change_name：此时尚未确定，显示 `pending`（Phase 1 完成后更新锁文件时回填）
- Started：使用 `date "+%Y-%m-%d %H:%M:%S"` 获取本地时间，禁止 ISO-8601 带时区偏移格式
- GUI：服务器启动成功时显示 `http://localhost:9527`，启动失败时显示 `unavailable`

### Step 4.5: 初始化事件文件 + 发射 Phase 0 开始事件（v5.2 Event Bus 补全）

确保事件文件存在并发射 Phase 0 开始事件：

```bash
Bash('mkdir -p <project_root>/logs && touch <project_root>/logs/events.jsonl')
Bash('bash ${PLUGIN_ROOT}/scripts/emit-phase-event.sh phase_start 0 {mode}')
```

> **必要性**: Phase 0/1 此前未接入 Event Bus，导致 GUI 在 Phase 2 之前无任何数据。此步骤确保 `events.jsonl` 在 GUI 服务器启动后立即创建，且 Phase 0 生命周期事件对 GUI 可见。

### Step 5: 检查已启用插件

读取 `.claude/settings.json` 的 `enabledPlugins` → 检查已启用插件列表

### Step 6: 崩溃恢复

调用 Skill(`spec-autopilot:autopilot-recovery`)：扫描 checkpoint + progress 文件，决定起始阶段和子步骤恢复点

> **v5.3**: Recovery 同时扫描 `phase-{N}-progress.json` 实现子步骤粒度恢复

### Step 7: 创建阶段任务

使用 TaskCreate 创建阶段任务 + blockedBy 依赖链：
- **full 模式**: 创建 Phase 1-7（7 个任务）
- **lite 模式**: 创建 Phase 1, 5, 6, 7（4 个任务），Phase 5 blockedBy Phase 1，Phase 6 blockedBy Phase 5
- **minimal 模式**: 创建 Phase 1, 5, 7（3 个任务），Phase 5 blockedBy Phase 1
- 崩溃恢复时：已完成阶段直接标记 completed

### Step 8: 确保锁文件被 gitignore

检查项目根目录 `.gitignore` 是否包含 `.autopilot-active`，若不包含则追加：

```bash
echo '.autopilot-active' >> .gitignore
```

> 此文件是会话级运行时锁，包含 PID/session_id 等本机信息，禁止提交到 git。

### Step 9: 创建锁文件

调用锁文件管理（本 Skill 内置操作 1，见下方「锁文件管理」章节）：

传入参数（由主线程构造 JSON 字符串）：
```json
{"change":"pending","pid":"<PID>","started":"<ISO-8601>","session_cwd":"<abs_path>","anchor_sha":"","session_id":"<ms_timestamp>","mode":"<mode>"}
```

等待后台 Agent 返回：
- `status: ok` → 继续 Step 10
- `status: conflict` → AskUserQuestion 由用户决定覆盖/中止（见 lockfile Skill 冲突处理）

> **原子性**：初次写入时 `anchor_sha` 设为空字符串，Step 10 创建 commit 后更新。

### Step 10: 创建锚定 Commit

为后续 fixup + autosquash 策略创建空锚定 commit：

```bash
git commit --allow-empty -m "autopilot: start <change_name>"
ANCHOR_SHA=$(git rev-parse HEAD)
```

调用锁文件管理（本 Skill 内置操作 2）：将 `ANCHOR_SHA` 写入锁文件的 `anchor_sha` 字段。

> **原子性保障**：如果 Step 10 之前崩溃，恢复时检测到 `anchor_sha` 为空 → 重新创建锚定 commit 并更新。Phase 7 autosquash 前**必须**验证 `anchor_sha` 非空且 `git rev-parse $ANCHOR_SHA` 有效，无效则跳过 autosquash 并警告用户。

---

### Step 10.5: 发射 Phase 0 结束事件（v5.2 Event Bus 补全）

```bash
Bash('bash ${PLUGIN_ROOT}/scripts/emit-phase-event.sh phase_end 0 {mode} \'{"status":"ok","duration_ms":{elapsed},"artifacts":["lockfile","anchor_commit"]}\'')
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

## 锁文件管理（原 autopilot-lockfile，v4.0 合入）

管理 `${session_cwd}/openspec/changes/.autopilot-active` 锁文件的完整生命周期。通过后台 Agent 封装 Read→Write→Verify 流程，从根本上解决 Write 工具的前置 Read 要求。

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

使用后台 Agent 创建锁文件：

```
Agent(subagent_type: "general-purpose", run_in_background: true, prompt: "
  <!-- lockfile-writer -->
  你是 autopilot 锁文件管理 Agent。执行以下步骤：

  1. 确保目录存在：Bash('mkdir -p ${session_cwd}/openspec/changes/')
  2. 检查锁文件是否已存在：Bash('test -f ... && echo exists || echo new')
     - exists → Read 锁文件，执行 PID 冲突检测
     - new → 跳过检测
  3. Write 锁文件 JSON 内容
  4. Read 验证写入成功

  返回: {\"status\": \"ok|conflict\", \"action\": \"created|overwritten\", \"message\": \"...\"}
")
```

#### PID 冲突检测逻辑

| 条件 | 判定 | 处理 |
|------|------|------|
| PID 存活 + session_id 匹配 | 同一进程 | 返回 `conflict`，主线程 AskUserQuestion |
| PID 存活 + session_id 不匹配 | PID 被系统回收 | 自动覆盖，返回 `overwritten` |
| PID 不存在 | 崩溃残留 | 自动覆盖，返回 `overwritten` |

PID 存活检测：`Bash('kill -0 ${pid} 2>/dev/null && echo alive || echo dead')`

### 操作 2: 更新 anchor_sha（Step 10）

使用后台 Agent 更新锁文件中的 `anchor_sha` 字段。Read → 更新 JSON → Write → Read 验证。

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
