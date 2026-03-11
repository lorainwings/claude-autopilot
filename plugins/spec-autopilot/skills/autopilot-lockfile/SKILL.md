---
name: autopilot-lockfile
description: "[ONLY for autopilot orchestrator] Background Agent-based lockfile management for .autopilot-active. Handles create, update, and delete with proper Read→Write→Verify flow."
user-invocable: false
---

# Autopilot Lockfile — 锁文件管理协议

> **前置条件自检**：本 Skill 仅在 autopilot 编排主线程中使用。如果当前上下文不是 autopilot 编排流程，请立即停止并忽略本 Skill。

管理 `${session_cwd}/openspec/changes/.autopilot-active` 锁文件的完整生命周期。通过后台 Agent 封装 Read→Write→Verify 流程，从根本上解决 Write 工具的前置 Read 要求。

## 锁文件路径

```
${session_cwd}/openspec/changes/.autopilot-active
```

## 锁文件 JSON 格式

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

---

## 操作 1: 创建锁文件（Phase 0 Step 9）

由 `autopilot-phase0` 调用。使用后台 Agent 创建锁文件：

```
Agent(subagent_type: "general-purpose", run_in_background: true, prompt: "
  <!-- lockfile-writer -->
  你是 autopilot 锁文件管理 Agent。执行以下步骤：

  1. 确保目录存在：Bash('mkdir -p ${session_cwd}/openspec/changes/')
  2. 检查锁文件是否已存在：Bash('test -f ${session_cwd}/openspec/changes/.autopilot-active && echo exists || echo new')
     - exists → Read 锁文件，执行 PID 冲突检测（见下方）
     - new → 跳过检测
  3. Write(${session_cwd}/openspec/changes/.autopilot-active, JSON内容)
     注意：如果步骤 2 为 exists 已执行 Read，满足 Write 前置要求；
           如果为 new，文件不存在，Write 可直接创建新文件
  4. Read 验证写入成功：读回文件确认 JSON 有效

  返回: {\"status\": \"ok|conflict\", \"action\": \"created|overwritten\", \"message\": \"...\"}
")
```

### PID 冲突检测逻辑

当锁文件已存在时，读取 `pid` 和 `session_id` 字段：

| 条件 | 判定 | 处理 |
|------|------|------|
| PID 存活 + session_id 匹配 | 同一进程 | 返回 `conflict`，主线程 AskUserQuestion |
| PID 存活 + session_id 不匹配 | PID 被系统回收 | 自动覆盖，返回 `overwritten` |
| PID 不存在 | 崩溃残留 | 自动覆盖，返回 `overwritten` |

PID 存活检测：`Bash('kill -0 ${pid} 2>/dev/null && echo alive || echo dead')`

### 冲突处理（主线程）

当后台 Agent 返回 `conflict` 时：

```
AskUserQuestion:
  "检测到另一个 autopilot 正在运行（PID: {pid}，启动于 {started}），是否覆盖？"
  选项:
  - "覆盖并继续 (Recommended)"
  - "中止当前运行"
```

---

## 操作 2: 更新 anchor_sha（Phase 0 Step 10）

由 `autopilot-phase0` 调用。使用后台 Agent 更新锁文件中的 `anchor_sha` 字段：

```
Agent(subagent_type: "general-purpose", run_in_background: true, prompt: "
  <!-- lockfile-updater -->
  你是 autopilot 锁文件管理 Agent。执行以下步骤：

  1. Read(${session_cwd}/openspec/changes/.autopilot-active)
  2. 解析 JSON，将 anchor_sha 字段值替换为 ${ANCHOR_SHA}
  3. Write 完整 JSON 覆盖写入（Read 已满足 Write 前置要求）
  4. Read 验证更新成功：读回文件确认 anchor_sha 已更新

  返回: {\"status\": \"ok\", \"anchor_sha\": \"${ANCHOR_SHA}\"}
")
```

---

## 操作 3: 删除锁文件（Phase 7 Step 7）

由 `autopilot-phase7` 直接执行，无需 Agent 封装：

```bash
Bash('rm -f ${session_cwd}/openspec/changes/.autopilot-active')
```

> 删除操作幂等，文件不存在时不报错。

---

## 日志格式

遵循 `autopilot/references/log-format.md` 规范：

```
[LOCK] created: .autopilot-active
[LOCK] updated: anchor_sha → {short_sha}
[LOCK] deleted: .autopilot-active
[LOCK] conflict: PID {pid} (started {time})
```
