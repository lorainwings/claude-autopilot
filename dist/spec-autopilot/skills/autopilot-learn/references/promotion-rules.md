# L3 晋升规则

## 晋升门槛

一个 L2 cluster 晋升为 L3 候选，必须同时满足：

1. **hit_count ≥ 3** — 至少 3 次独立 episode 命中
2. **无反例** — 同 phase、同 root_cause 的成功 fingerprint 抵消后仍 ≥ 3
3. **last_seen 在最近 90 天内** — 避免陈旧规则长期占用注入槽位

## 输出路径

- **候选**: `docs/learned/candidates/{pattern_id}.md` — 默认 `status: pending_review`
- **正式（人工审核通过后）**: `docs/learned/<skill-or-topic>.md` 或直接在根 `CLAUDE.md` "习得规则" 区块追加

当前仅做候选生成，不做自动写入正式区块。

## 候选 markdown 模板

```markdown
---
pattern_id: {pattern_id}
phase: {phase}
root_cause: {root_cause}
hit_count: {hit_count}
last_seen: {ISO-8601}
status: pending_review
---

# 习得规则候选：{root_cause}

## 失败证据

{evidence_episodes 列表}

## 代表性反思

{representative_reflection}

## 建议规则

> 由人工审核后改写为具体的工程法则，追加到 CLAUDE.md "习得规则" 区块。

## 审核检查清单

- [ ] 根因归因准确
- [ ] 建议规则可执行（非空泛描述）
- [ ] 无现有规则已覆盖
- [ ] 无反例未考虑
```

## 反例判定

以下情形视为反例，阻止晋升：

1. 同 phase / 同 root_cause 的 episode 中存在 `success_fingerprint.counters` 包含该 root_cause
2. 最近一次 episode 为成功且与失败 episode 时间差 < 1 小时（说明已在人工干预下解决）
3. 现有 CLAUDE.md 规则中已有同语义规则（字符串相似度 ≥ 0.8，由后续人工审核实现）
