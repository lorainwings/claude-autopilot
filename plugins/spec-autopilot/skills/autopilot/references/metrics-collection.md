# 指标收集协议

> 由 autopilot SKILL.md 和 autopilot-checkpoint SKILL.md 引用。

## `_metrics` 字段

每个 phase checkpoint JSON 中包含可选的 `_metrics` 字段，记录执行指标：

```json
{
  "status": "ok",
  "summary": "...",
  "_metrics": {
    "start_time": "2026-01-15T10:00:00Z",
    "end_time": "2026-01-15T10:30:00Z",
    "duration_seconds": 1800,
    "retry_count": 0
  }
}
```

### 字段说明

| 字段 | 类型 | 描述 |
|------|------|------|
| `start_time` | string (ISO-8601) | 阶段开始时间 |
| `end_time` | string (ISO-8601) | 阶段结束时间 |
| `duration_seconds` | number | 执行耗时（秒） |
| `retry_count` | number | 重试次数（dispatch 失败后重新派发的次数） |

### 收集时机

主线程在写入 checkpoint 时附加 `_metrics`：

```
Phase 开始 → 记录 start_time
Phase 结束 → 记录 end_time, 计算 duration_seconds
如有重试 → 累加 retry_count
写入 checkpoint 时 → 将 _metrics 合并到 JSON 信封中
```

## Phase 7 指标汇总

Phase 7 调用 `collect-metrics.sh` 脚本收集所有阶段的指标，生成汇总表：

```
| Phase | Status | Duration | Retries |
|-------|--------|----------|---------|
| 1     | ok     | 5m 30s   | 0       |
| 2     | ok     | 2m 15s   | 0       |
| 3     | ok     | 8m 45s   | 1       |
| 4     | ok     | 12m 00s  | 0       |
| 5     | ok     | 45m 20s  | 2       |
| 6     | ok     | 10m 10s  | 0       |
| 7     | ok     | 1m 00s   | 0       |
| **Total** |    | **85m 00s** | **3** |
```

汇总表展示在 Phase 7 的状态报告中，帮助团队了解流水线效率。

### 可视化输出

`collect-metrics.sh` 的 JSON 输出包含 `markdown_table` 和 `ascii_chart` 两个字段，Phase 7 应直接展示：

#### Markdown 表格示例

```
| Phase | Status | Duration | Retries |
|-------|--------|----------|---------|
| 1     | ok     | 5m 30s   | 0       |
| 2     | ok     | 2m 15s   | 0       |
| 3     | ok     | 8m 45s   | 1       |
| 4     | ok     | 12m 00s  | 0       |
| 5     | ok     | 45m 20s  | 2       |
| 6     | ok     | 10m 10s  | 0       |
| 6.5   | ok     | 3m 00s   | 0       |
| 7     | ok     | 1m 00s   | 0       |
| **Total** | | **88m 00s** | **3** |
```

#### 耗时分布图示例

```
Duration Distribution:

  Phase    1 |████░░░░░░░░░░░░░░░░░░░░░░░░░░| 5m 30s (6%)
  Phase    2 |██░░░░░░░░░░░░░░░░░░░░░░░░░░░░| 2m 15s (3%)
  Phase    3 |██████░░░░░░░░░░░░░░░░░░░░░░░░| 8m 45s (10%)
  Phase    4 |████████░░░░░░░░░░░░░░░░░░░░░░| 12m 00s (14%)
  Phase    5 |██████████████████████████████| 45m 20s (51%)
  Phase    6 |███████░░░░░░░░░░░░░░░░░░░░░░░| 10m 10s (12%)
  Phase  6.5 |██░░░░░░░░░░░░░░░░░░░░░░░░░░░░| 3m 00s (3%)
  Phase    7 |█░░░░░░░░░░░░░░░░░░░░░░░░░░░░░| 1m 00s (1%)
```

Phase 7 主线程应解析 `collect-metrics.sh` 的 JSON 输出，提取 `markdown_table` 和 `ascii_chart` 字段直接展示给用户。

### 配置

指标收集默认启用，无需额外配置。`_metrics` 字段为可选，缺失时 `collect-metrics.sh` 对该阶段报告 duration=0。
