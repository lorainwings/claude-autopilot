# Part C：主动学习体系设计

## 1. 设计目标

让 autopilot 每一次执行都**沉淀可复用的知识**，并在下一次执行前**主动注入**，实现：

- 失败不重复踩坑
- 成功模式可复用为 skill
- CLAUDE.md 的「习得规则区」随项目演进自动生长

## 2. 三层记忆架构

| 层 | 名称 | 粒度 | 存储载体 | 产生时机 |
|----|------|------|---------|---------|
| L1 | Episode（情景记忆） | 单次 Phase 的反思 | `phase-reflection.json` + claude-mem observation | 每个 Phase 结束 / 失败时 |
| L2 | Pattern（模式记忆） | 多次 Episode 聚类 | `autopilot-learn` skill + `build_corpus` 知识库 | Phase 7 归档时触发聚类 |
| L3 | Skill/Rule（显性知识） | 被晋升为规则或新 skill | CLAUDE.md 习得规则区 / `skills/learned/` | 阈值触发自动晋升 |

### L1 · Episode 结构

```json
{
  "schema": "phase-reflection/v1",
  "change_id": "sprint-auto-upgrade",
  "phase": 5,
  "status": "blocked",
  "duration_sec": 412,
  "failure_signature": "L2 hook unified-write-edit-check reject: TODO placeholder",
  "root_cause_hypothesis": "子 Agent 在 TDD GREEN 阶段误留 TODO",
  "lessons": [
    "TDD GREEN 前必须 grep TODO|FIXME"
  ],
  "artifacts": ["reports/review-findings.json"],
  "obs_type": "failure_pattern",
  "tags": ["tdd", "phase5", "placeholder"]
}
```

### L2 · Pattern 聚类

- 复用 `claude-mem` 的 `build_corpus` 能力，name 建议 `autopilot-lessons-<project>`；
- 约定 `obs_type` 枚举：
  - `phase_reflection`：L1 原始情景
  - `success_pattern`：连续 3 次成功的模式（如「parallel.enabled=true + owned_files 隔离」）
  - `failure_pattern`：连续 2 次失败签名相同

### L3 · Skill / Rule 晋升

- **命中阈值**：同一 `failure_signature` 出现 ≥ 3 次且无反例
- **晋升产物**二选一：
  - 写入 `plugins/spec-autopilot/CLAUDE.md`「习得规则区」（特殊注释块 `<!-- AUTO-LEARNED-BEGIN --> ... <!-- AUTO-LEARNED-END -->`），规则格式：`- [AUTO-LEARNED 2026-04-18] <lesson> （触发签名：<hash>）`
  - 创建 `skills/learned/<name>/SKILL.md`，由主 skill 在对应 Phase 条件注入

## 3. 学习闭环时序图

```
┌────────────────────────────────────────────────────────────────────┐
│ Run N                                                              │
│                                                                    │
│   Phase 0 ──► 从 L2 corpus 抽取 Top-3 lessons 注入 banner         │
│      │                                                            │
│      ▼                                                            │
│   Phase 1..6 ──► 某 Phase 失败 ──► gate-hook 写 phase-reflection │
│      │                               │                             │
│      ▼                               ▼                             │
│   Phase 7 archive ◄── 聚合所有 L1 ◄── claude-mem store obs        │
│      │                                                             │
│      ▼                                                             │
│   autopilot-learn skill ──► 聚类 + 计数 ──► 命中阈值?             │
│                                         │                          │
│                                         ├── 是 ─► 写 CLAUDE.md     │
│                                         │        习得规则区        │
│                                         └── 否 ─► 更新 corpus       │
│                                                                    │
├────────────────────────────────────────────────────────────────────┤
│ Run N+1                                                            │
│   Phase 0 banner 显示："上次教训 Top-3：..."                       │
└────────────────────────────────────────────────────────────────────┘
```

## 4. 复用 claude-mem 的集成细节

- 所有 L1 落盘时同步调用 mem-search 的 MCP 接口（或 CLI），写入 observation：
  - `obs_type`：枚举值之一
  - `project`：`claude-autopilot`
  - `concepts`：`[phase, change_type, failure_signature?]`
- Phase 7 触发 `autopilot-learn` skill 执行：
  ```
  prime_corpus name=autopilot-lessons-claude-autopilot
  query_corpus question="过去 30 天最常见的 Phase 5 阻断根因 Top-3"
  ```
- 返回 Top-3 写入 `context/last-run-lessons.md`，供 Run N+1 Phase 0 注入。

## 5. 晋升规则详细

### 晋升判定

```
for signature, episodes in cluster(L1_store):
    if len(episodes) >= 3 and not has_counterexample(episodes):
        if is_rule_shaped(signature):   # 一句话可表达的约束
            append_to_CLAUDE_md_learned_block(signature)
        elif is_procedure_shaped(signature):  # 需要多步
            scaffold_skill("skills/learned/" + slug(signature))
```

### 反例机制

- 若晋升后 30 天内出现「同签名但 status=ok」的 Episode，规则自动进入「quarantine」状态；
- quarantine 累计 2 次 → 自动回滚晋升并记录到 `reports/learning-rollback.log`。

## 6. 文件与触点

| 文件 / 目录 | 动作 |
|------------|------|
| `plugins/spec-autopilot/skills/autopilot-learn/SKILL.md` | 新增 |
| `plugins/spec-autopilot/runtime/scripts/write-phase-reflection.sh` | 新增 |
| `plugins/spec-autopilot/skills/autopilot-phase7-archive/SKILL.md` | 改：调度 learn skill |
| `plugins/spec-autopilot/skills/autopilot-phase0-init/SKILL.md` | 改：注入 top-3 lessons |
| `plugins/spec-autopilot/CLAUDE.md` | 改：新增「习得规则区」注释块 |

## 7. 安全护栏

- 晋升写 CLAUDE.md 必须经过一次「最小破坏验证」：用上一次失败场景 mock 一次 gate-hook，确认新规则能正确阻断；
- 习得规则区独立于人工规则区，永不覆盖人工内容；
- 任何 L3 晋升都在 `logs/events.jsonl` 发出 `learning_promotion` 事件，便于审计。

## 8. 落地节奏

- **Sprint 1**：L1 落盘 + claude-mem obs 写入
- **Sprint 2**：autopilot-learn skill + build_corpus 自动化 + Top-3 回灌
- **Sprint 3**：L3 晋升闭环 + 反例回滚机制
