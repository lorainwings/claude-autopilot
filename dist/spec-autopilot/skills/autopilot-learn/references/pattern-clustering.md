# L2 Pattern Clustering 策略

## 数据源

优先级（高到低）：

1. claude-mem MCP `query_corpus(name="autopilot-lessons")`
2. 本地 `docs/reports/*/episodes/*.json` 全量扫描（dry-run / fallback）

## 聚类维度

按以下复合 key 做 hash clustering：

```
pattern_key = sha1(phase + "::" + failure_trace.root_cause + "::" + failure_trace.failed_gate)
```

- **phase**: 区分 Phase4 与 Phase5 即使 root_cause 相同，治理策略不同
- **root_cause**: 主语，如 `file_ownership_overlap` / `tdd_red_skipped` / `coverage_below_floor`
- **failed_gate**: 触发的具体 gate 脚本名

## Cluster 字段

每个 cluster 输出：

| 字段 | 含义 |
|------|------|
| `pattern_id` | 取 `pattern_key` 前 12 位 |
| `phase` | 来源 phase |
| `root_cause` | 失败根因 |
| `hit_count` | 命中 episode 数 |
| `evidence_episodes` | episode 文件路径数组 |
| `last_seen` | 最近一次命中的 timestamp_end |
| `representative_reflection` | 选择最近一次 reflection 作为代表 |

## 成功指纹抵消

如果某 `pattern_id` 对应的失败 cluster 出现后，又有同 phase 的成功 episode 携带 `success_fingerprint` 包含 `counters: ["root_cause_x"]`，则该失败计数 -1。计数归零或转负 → 不参与晋升。

## Dry-run 输出

无 MCP 时，直接输出到 stdout：

```json
{
  "corpus": "autopilot-lessons",
  "mode": "dry-run",
  "clusters": [{...}, {...}]
}
```
