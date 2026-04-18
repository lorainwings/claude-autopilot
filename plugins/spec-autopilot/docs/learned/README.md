# docs/learned/ — L3 习得规则落地

本目录存放由 autopilot 主动学习体系自动产出的 **L3 Skill-Rule 晋升候选**。

## 目录结构

```
docs/learned/
├── README.md                # 本文件
├── .gitkeep                 # 保留空目录
└── candidates/              # 由 learn-promote-candidate.sh 产出
    └── <pattern_id>.md      # 晋升候选（status: pending_review）
```

## 生命周期

1. **产出**: `learn-promote-candidate.sh` 扫描 `docs/reports/*/episodes/*.json`，命中 ≥ 3 次且无反例的 failure pattern → 在 `candidates/` 下生成 Markdown 候选
2. **人工审核**: 维护者评审候选规则的准确性、可执行性、与现有 CLAUDE.md 规则的去重关系
3. **晋升（本 sprint 不自动化）**:
   - 候选通过审核 → 改写为具体工程法则 → 追加到根 `CLAUDE.md` 或 `plugins/spec-autopilot/CLAUDE.md` 的"习得规则"区块
   - 或落地为独立 skill: `plugins/spec-autopilot/skills/learned/<skill>.md`
4. **候选清理**: 已晋升的候选在 `candidates/<pattern_id>.md` 顶部打 `status: promoted` 或直接移除

## 候选文件 frontmatter

```yaml
---
pattern_id: <12-char hash>
phase: phase5
root_cause: file_ownership_overlap
failed_gate: parallel-merge-guard
hit_count: 3
last_seen: 2026-04-18T10:12:30Z
status: pending_review   # pending_review | approved | promoted | rejected
---
```

## 审核建议

- 根因归因是否准确（勿把症状当根因）
- 建议规则是否可执行（避免空泛描述）
- 是否与现有 CLAUDE.md 规则重复
- 反例（成功 fingerprint）是否已充分考虑
- 是否值得以硬规则形式约束（相对"事后修复"）

## 与 claude-mem 的关系

当 MCP 可用时，晋升扫描优先从 `claude-mem build_corpus(name="autopilot-lessons")` 读取；MCP 不可用时 fallback 到本地 episodes 聚合。两种模式产出同构的候选 markdown。
