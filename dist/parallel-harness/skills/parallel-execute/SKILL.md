---
name: parallel-execute
description: "并行任务执行器：根据任务图调度并行执行、验证和综合。仅供 parallel-plan 后续调用。"
user-invocable: false
---

# parallel-execute — 并行任务执行

## 概述

`parallel-execute` 是 parallel-harness 的内部执行引擎，在 `/parallel-plan` 生成任务图后被调用。

## 执行流程

1. **加载任务图**：从会话状态中加载已规划的任务图
2. **调度执行**：按分层执行计划调度任务
   - 每层的任务并行分发给 Worker
   - Worker 在隔离环境中执行（worktree 模式）
   - 实时监控执行进度
3. **验证 Swarm**：每个任务完成后触发验证
   - test-verifier: 检查测试覆盖
   - review-verifier: 检查代码质量
   - security-verifier: 检查安全问题
   - perf-verifier: 检查性能反模式
4. **结果综合**：合并所有验证结果
   - 加权评分（test:30%, review:25%, security:30%, perf:15%）
   - 生成综合报告
5. **失败处理**：
   - 重试策略（指数退避）
   - 模型升级（tier-1 → tier-2 → tier-3）
   - 任务降级（简化验证器集合）
6. **最终输出**：
   - 执行摘要
   - 变更文件列表
   - 验证报告
   - 成本报告

## 角色约束

- Worker 只能修改 allowed_paths 中的文件
- Verifier 只能读取，不能修改
- Synthesizer 只能读取验证结果
