---
name: autopilot-learn
description: "Use when the autopilot orchestrator has finished Phase 7 archive and needs to aggregate Episode records into the L1/L2/L3 learning tiers, cluster failure/success patterns, and emit L3 promotion candidates. ONLY for autopilot orchestrator; not for direct user invocation."
user-invocable: false
---

# Autopilot Learn — 主动学习体系

> **前置条件自检**：本 Skill 仅在 autopilot 编排主线程的 Phase 7 归档之后使用。非 autopilot 流程请立即停止并忽略。

## 架构概览（三层记忆）

| 层级 | 粒度 | 存储 | 生命周期 |
|------|------|------|----------|
| **L1 Episode** | 单次 Phase 执行轨迹 | `docs/reports/{version}/episodes/phase{N}.json` + claude-mem `create_observations` | 永久 |
| **L2 Pattern** | 跨 Episode 聚类得到的成功/失败模式 | claude-mem `build_corpus(name="autopilot-lessons")` | 按需重建 |
| **L3 Skill-Rule** | 命中次数 ≥ 3 且无反例的晋升规则 | `docs/learned/<pattern_id>.md` 或 CLAUDE.md "习得规则"区块 | 人工审核后长期持有 |

## 输入参数

| 参数 | 来源 |
|------|------|
| phase | Phase 7 传入（默认 "phase7"） |
| checkpoint | `openspec/changes/{slug}/phase-results/phase{N}.json` |
| version | 当前发布版本号（用于 `docs/reports/{version}/episodes/` 路径） |

## 执行步骤

### Step 1: 写入 L1 Episode

```bash
bash "${CLAUDE_PLUGIN_ROOT}/runtime/scripts/learn-episode-write.sh" \
  --phase "$phase" \
  --checkpoint "$checkpoint" \
  --version "$version"
```

脚本负责：
1. 读取 phase-results JSON，提取 goal / actions / gate_result / failure_trace
2. 若 `gate_result ∈ {blocked, failed}`，强制生成 Reflexion 风格的自然语言反思（失败归因 + 可复用教训）
3. 调用 `learn-episode-schema-validate.sh` 校验 schema
4. 写入 `docs/reports/{version}/episodes/phase{N}.json`
5. 占位调用 claude-mem MCP `create_observations(obs_type=phase_reflection|success_pattern|failure_pattern)`

### Step 2: 聚合 L2 Pattern（占位）

Phase 7 之后触发一次聚合：

```bash
# dry-run：MCP 不可用时输出规范化 JSON 产物
claude-mem build_corpus \
  --name "autopilot-lessons" \
  --types "phase_reflection,failure_pattern,success_pattern" \
  --limit 200
```

聚类规则参见 `references/pattern-clustering.md`：
- 按 `failure_trace.root_cause` + `phase` 做 hash clustering
- 命中次数 ≥ 3 的 cluster 生成 `pattern_id`

### Step 3: 扫描 L3 晋升候选

```bash
bash "${CLAUDE_PLUGIN_ROOT}/runtime/scripts/learn-promote-candidate.sh" \
  --episodes-root docs/reports \
  --out-dir docs/learned/candidates
```

脚本负责：
1. 扫描 `docs/reports/*/episodes/*.json`（若 MCP 可用，切换到 `autopilot-lessons` corpus）
2. 按 `pattern_id` 聚合，命中次数 ≥ 3 且无反例（无成功 fingerprint 抵消）→ 输出候选到 `docs/learned/candidates/{pattern_id}.md`
3. 候选默认 `status: pending_review`，需人工审核后升级到正式 `docs/learned/<skill>.md` 或 CLAUDE.md "习得规则"区块

### Step 4: Phase 0 注入（由主线调用）

```bash
bash "${CLAUDE_PLUGIN_ROOT}/runtime/scripts/learn-inject-top-lessons.sh" \
  --raw-requirement "$raw_requirement"
```

输出 JSON 数组（top-3 教训），主线在 Phase 0 banner 之后注入到 dispatch prompt。

## 返回 JSON 信封

```json
{
  "status": "ok|warning|blocked|failed",
  "summary": "episode 写入 + 候选扫描结果",
  "artifacts": [
    "docs/reports/{version}/episodes/phase{N}.json",
    "docs/learned/candidates/{pattern_id}.md"
  ]
}
```

## 参考文档

- `references/episode-schema.md` — L1 Episode 字段定义
- `references/pattern-clustering.md` — L2 聚类策略
- `references/promotion-rules.md` — L3 晋升门槛与反例判定
