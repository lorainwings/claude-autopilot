---
name: autopilot-phase0-init
description: "Use when the autopilot orchestrator main thread enters Phase 0 to bootstrap a session (env checks, config load, recovery decision, lockfile, anchor commit). Not for direct user invocation."
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

| 阶段簇 | 职责 |
|--------|------|
| Step 1-3 | 版本/配置/模式解析 |
| Step 4-4.6 | GUI + Banner + 事件初始化 + 历史教训注入 |
| Step 5-6.1 | 必需插件检查 + 崩溃恢复 + 事件文件清理 |
| Step 7-8 | 阶段任务创建 + gitignore |
| Step 9-10.5 | 锁文件 + 锚定 Commit + Phase 0 结束事件 |

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

`${session_cwd}/openspec/changes/.autopilot-active` 锁文件的完整生命周期（路径、JSON 格式、PID 冲突检测、创建/更新/删除操作、日志格式）详见 `references/lock-file-protocol.md`。
