# 日志格式规范

> 统一 autopilot 运行时日志输出格式，确保可读性和一致性。

## 格式定义

| 模式 | 格式 | 使用位置 |
|------|------|---------|
| 阶段过渡 | `── Phase {N}: {name} ──` | autopilot-gate |
| 门禁结果 | `[GATE] Phase {N-1} → {N}: PASSED ({M}/8)` | autopilot-gate |
| Checkpoint | `[CP] phase-{N}-{slug}.json \| commit: {sha}` | autopilot-checkpoint |
| 警告 | `[WARN] {message}` | 各 skill |
| 错误 | `[ERROR] {message}` | 各 skill |
| 超时 | `[TIMEOUT] {agent}: exceeded {N}m` | autopilot 主编排器 |
| 锁文件 | `[LOCK] {action}: .autopilot-active` | autopilot-lockfile |

## 阶段名称映射

| Phase | name |
|-------|------|
| 0 | Environment Setup |
| 1 | Requirements |
| 2 | OpenSpec |
| 3 | Fast-Forward |
| 4 | Test Design |
| 5 | Implementation |
| 6 | Test Report |
| 7 | Archive |

## Summary Box（Phase 7 专用）

```
╭──────────────────────────────────────────────────╮
│                                                  │
│   Autopilot Summary                              │
│                                                  │
│   Phase 1  Requirements    ok                    │
│   Phase 5  Implementation  ok                    │
│   Phase 6  Test Report     warning               │
│   Phase 7  Archive         ok                    │
│                                                  │
│   Duration   {HH:mm:ss}                          │
│   Pass Rate  {N}%                                │
│                                                  │
╰──────────────────────────────────────────────────╯
```

> 渲染规则：框内宽度固定 50 字符（纯 ASCII），与启动 Banner 一致。仅展示实际执行的阶段（lite/minimal 跳过的阶段不显示）。
