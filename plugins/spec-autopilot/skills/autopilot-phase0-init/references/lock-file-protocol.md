# 锁文件管理（确定性脚本重构）

管理 `${session_cwd}/openspec/changes/.autopilot-active` 锁文件的完整生命周期。通过 python3 内联脚本 + 原子写入（tempfile + os.replace）确保确定性。

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

## 操作 1: 创建锁文件（Step 9）

直接 Bash 调用 python3 内联脚本，含 PID 冲突检测 + 原子写入。详见 Step 9。

### PID 冲突检测逻辑

| 条件 | 判定 | 处理 |
|------|------|------|
| PID 存活 + session_id 匹配 | 同一进程 | 返回 `conflict`，主线程 AskUserQuestion |
| PID 存活 + session_id 不匹配 | PID 被系统回收 | 自动覆盖，返回 `overwritten` |
| PID 不存在 | 崩溃残留 | 自动覆盖，返回 `overwritten` |

## 操作 2: 更新 anchor_sha（Step 10）

直接 Bash 调用 python3 内联脚本，原子更新 JSON + 验证。详见 Step 10。

## 操作 3: 删除锁文件（Phase 7 Step 7）

由 `autopilot-phase7` 直接执行：`Bash('rm -f ${session_cwd}/openspec/changes/.autopilot-active')`

## 日志格式

锁文件相关日志统一使用 `[LOCK]` 前缀，最小 4 行样例如下（与 autopilot 全局日志规范保持一致）：

```
[LOCK] created: .autopilot-active
[LOCK] updated: anchor_sha → {short_sha}
[LOCK] deleted: .autopilot-active
[LOCK] conflict: PID {pid} (started {time})
```
