# 日志格式规范（Phase 7 本地副本）

> Phase 7 Summary Box 渲染所需的最小日志格式样例。完整规范见 autopilot skill 的 log-format 章节。

## 最小格式样例

| 模式 | 格式 |
|------|------|
| 阶段过渡 | `── Phase {N}: {name} ──` |
| Checkpoint | `[CP] phase-{N}-{slug}.json \| commit: {sha}` |
| 锁文件 | `[LOCK] {action}: .autopilot-active` |
| Allure 提示 | `[ALLURE] 预览服务运行中 (PID: {pid})` |

## Summary Box 渲染约束

- 框内宽度固定 50 字符（纯 ASCII）
- 仅展示实际执行的阶段（lite/minimal 跳过的阶段不显示）
- 所有地址从磁盘文件确定性读取
