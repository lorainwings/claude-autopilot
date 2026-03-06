# Autopilot 共享协议参考

> 此文件被 autopilot-dispatch、autopilot-gate、autopilot-checkpoint 共同引用。修改时需同步评估影响。

## JSON 信封契约

每个子 Agent **必须**返回此格式：

```json
{
  "status": "ok | warning | blocked | failed",
  "summary": "单行决策级摘要",
  "artifacts": ["已创建/修改的文件路径"],
  "risks": ["可选风险列表"],
  "next_ready": true
}
```

写入 checkpoint 时自动追加 `timestamp`（ISO-8601）和 `phase`（阶段编号）字段。

## 各阶段额外返回字段

| Phase | 必须字段 | 可选字段 |
|-------|----------|----------|
| 1 | `requirements_summary`, `decisions: [DecisionPoint]` (each with `priority: "P0\|P1\|P2\|P3"`), `change_name`, `complexity: "small\|medium\|large"`, `research: { status, impact_files, estimated_loc, feasibility_score, new_deps_count }` | `open_questions`, `steering_artifacts`, `web_research: { queries_executed, best_practices, similar_implementations, dependency_evaluation, recommended_approach, sources_count: N, confidence_scores: [{source, confidence}] }` |
| 4 | `test_counts: { unit, api, e2e, ui }`, `dry_run_results: { unit, api, e2e, ui }`, `test_pyramid: { total, unit_pct, integration_pct, e2e_pct }` | — |
| 5 | `test_results_path`, `tasks_completed`, `zero_skip_check: { passed: bool }` | `iterations_used`, `parallel_metrics: { mode: "parallel\|serial\|downgraded", groups_count: N, max_agents_used: N, fallback_reason: null\|string, file_conflicts_count: N }`, `code_quality: { constraint_violations: N, violations: [{rule, file, detail}] }` |
| 6 | `pass_rate`, `report_path`, `report_format` | `report_url`, `allure_results_dir` |
| 7 | `archive_path`, `change_name` | `cleanup_actions`, `knowledge_extracted: number` |

## 状态解析规则

| status | 主线程行为 |
|--------|-----------|
| ok | 写入 checkpoint，继续下一阶段 |
| warning | 写入 checkpoint，展示警告后继续（**Phase 4 例外**） |
| blocked | 暂停，展示给用户，要求排除阻塞 |
| failed | 暂停，展示给用户，可能需要重新执行本阶段 |

**Phase 4 特殊规则**：不接受 warning。warning 且 test_counts < 门禁阈值 → 强制覆盖为 blocked。

## 结构化标记（Hook 识别依据）

子 Agent prompt **开头第一行**必须包含：

```
<!-- autopilot-phase:{phase_number} -->
```

无标记的 Task 调用被 Hook 直接放行（exit 0）。

## 模型路由（v3.0 新增）

config.model_routing 定义每阶段的推荐模型等级：

| 等级 | 含义 | 适用阶段 |
|------|------|---------|
| heavy | 需要深度推理的 Opus 级任务 | Phase 1, 4, 5 |
| light | 机械性操作的 Sonnet 级任务 | Phase 2, 3, 6, 7 |
| auto | 继承父进程模型（默认） | 未配置时 |

> 向后兼容: model_routing 为可选配置。未配置时所有阶段等效 auto。

## Checkpoint 文件命名

```
phase-results/
├── phase-1-requirements.json
├── phase-2-openspec.json
├── phase-3-ff.json
├── phase-4-testing.json
├── phase-5-implement.json
├── phase-6-report.json
└── phase-7-summary.json
```

## DecisionPoint 格式（v2.4.0 增强）

Phase 1 JSON 信封中的 `decisions` 数组，每个元素为 DecisionPoint：

```json
{
  "point": "决策点描述",
  "options": [
    {"label": "A", "description": "...", "pros": ["..."], "cons": ["..."], "recommended": false},
    {"label": "B", "description": "...", "pros": ["..."], "cons": ["..."], "recommended": true}
  ],
  "choice": "B",
  "rationale": "用户选择理由或 AI 推荐理由",
  "affected_components": ["frontend-sync", "backend-api"]
}
```

> **向后兼容**: 旧格式 `{"point": "...", "choice": "..."}` 仍被 checkpoint 和 gate 接受。增强字段（`options`、`rationale`、`affected_components`）为可选，validation hook 不强制检查。

## Web Research 格式（v2.4.0 增强）

Phase 1 JSON 信封中的 `web_research` 可选字段：

```json
{
  "queries_executed": ["Vue 3 real-time collaboration best practices 2026", "Y.js vs Automerge comparison 2026"],
  "best_practices": [
    {"source": "https://...", "pattern": "使用 WebSocket + CRDT", "relevance": "high"}
  ],
  "similar_implementations": [
    {"repo": "github.com/...", "approach": "Y.js + WebSocket", "pros": ["成熟"], "cons": ["体积大"]}
  ],
  "dependency_evaluation": [
    {"package": "yjs", "security_status": "clean", "maintenance_status": "active", "bundle_size": "45KB", "alternatives": ["automerge", "sharedb"]}
  ],
  "recommended_approach": "基于调研结果，推荐使用 Y.js + WebSocket 方案，理由：社区成熟、bundle 体积可控、与 Vue 3 集成良好"
}
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `queries_executed` | `string[]` | 实际执行的搜索查询列表 |
| `best_practices` | `{source, pattern, relevance}[]` | 结构化最佳实践，source 为来源 URL，relevance 为 high/medium/low |
| `similar_implementations` | `{repo, approach, pros, cons}[]` | 同类实现对比，含仓库地址、方案描述、优缺点 |
| `dependency_evaluation` | `{package, security_status, maintenance_status, bundle_size, alternatives}[]` | 依赖评估，含安全状态、维护状态、体积、替代方案 |
| `recommended_approach` | `string` | 基于调研的最终推荐方案摘要 |

## 特殊门禁

### Phase 4 → Phase 5

- `test_counts` 每个字段 ≥ `config.phases.testing.gate.min_test_count_per_type`
- `test_pyramid` 比例符合 `config.test_pyramid` 约束（unit_pct ≥ 50%）
- `artifacts` 非空
- `dry_run_results` 全部为 0

### Phase 5 → Phase 6

- `test-results.json` 存在
- `zero_skip_check.passed === true`
- `tasks.md` 中所有任务标记为 `[x]`

## File-Locks Registry Format (v3.1)

Located at `openspec/changes/<name>/context/phase-results/phase5-ownership/file-locks.json`:

```json
{
  "backend/src/Controller.java": "agent-1",
  "frontend/src/App.vue": "agent-2",
  "node/src/service.ts": "agent-3"
}
```

**Lifecycle**:
1. Phase 5 orchestrator writes `file-locks.json` before dispatching parallel agents
2. `write-edit-constraint-check.sh` reads the registry on every Write/Edit
3. Agent completion → orchestrator removes corresponding entries
4. All entries cleared after Phase 5 completes

**Fallback**: If `file-locks.json` does not exist → skip file-level lock check, use directory-level ownership only.

## Decision Priority Format (v3.1)

Phase 1 decisions include priority classification:

```json
{
  "decisions": [
    {
      "point": "Which database engine to use?",
      "priority": "P0",
      "options": [
        {"name": "PostgreSQL", "pros": ["Mature"], "cons": ["Setup complexity"]},
        {"name": "SQLite", "pros": ["Simple"], "cons": ["Concurrency"]}
      ],
      "recommended": "PostgreSQL",
      "choice": "PostgreSQL",
      "rationale": "Team expertise and scalability requirements"
    }
  ]
}
```

| Priority | Criteria | User Action |
|----------|----------|-------------|
| P0 | Blocking — cannot proceed without decision | Must decide |
| P1 | Irreversible — hard to change later | Must decide |
| P2 | High-impact — affects architecture/UX | Discuss + decide |
| P3 | Low-impact — naming, style, minor trade-offs | Can auto-accept recommended |
