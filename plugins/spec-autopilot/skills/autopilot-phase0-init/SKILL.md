---
name: autopilot-phase0-init
description: "Use when the autopilot orchestrator main thread enters Phase 0 and must perform environment checks, load config, decide between fresh start and crash recovery, render the banner, seed the task tree, acquire the lockfile, and create the anchor commit before any downstream phase begins. Not for direct user invocation."
user-invocable: false
---

# Autopilot Phase 0 — 环境检查 + 崩溃恢复

> **前置条件自检**：本 Skill 仅在 autopilot 编排主线程中使用。如果当前上下文不是 autopilot 编排流程，请立即停止并忽略本 Skill。

## 输入参数

| 参数 | 来源 |
|------|------|
| $ARGUMENTS | autopilot 主编排器传入的原始参数 |
| plugin_dir | 插件根目录路径 |

## 执行步骤概览

| Step | 职责 |
|------|------|
| 1 | 读取插件版本 |
| 2 | 检查配置文件 |
| 3 | 解析执行模式 |
| 4 | 启动 GUI + Banner |
| 4.5 | 事件文件初始化 |
| 4.6 | 注入历史教训 |
| 5 | 检查必需插件 |
| 6 | 崩溃恢复 |
| 6.1 | 事件文件恢复清理 |
| 7 | 创建阶段任务 |
| 8 | gitignore |
| 9 | 创建锁文件 |
| 10 | 创建锚定 Commit |
| 10.5 | 发射 Phase 0 结束事件 |

**执行前必须读取 `references/execution-steps.md` 获取完整协议、脚本调用、字段定义。**

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

## 锁文件管理

`${session_cwd}/openspec/changes/.autopilot-active` 锁文件的完整生命周期（路径、JSON 格式、PID 冲突检测、创建/更新/删除操作、日志格式）详见 `references/lock-file-protocol.md`。日志遵循 `autopilot/references/log-format.md` 规范。
