# Part B：风险扫描体系设计

## 1. 设计目标

在现有 autopilot-gate 8 步 checklist 之外，补入**对手视角（adversarial / red-team）**的主动风险扫描层，让编排器在每个关键 Phase 都经历一次「反向审阅」，专治如下盲区：

- 需求裂缝（未枚举的非功能需求、隐含安全假设）
- 威胁建模缺失（鉴权、注入、越权、速率限制）
- 回归面扩大（跨模块副作用、废弃 API 依赖）

## 2. 组件清单

### C1 · risk-scanner（Phase 0.5）

- **职责**：在 Phase 0 → Phase 1 之间插入一次轻量扫描，基于 `context/` 和 git diff 扫出历史同类风险，产出初步 risk-matrix。
- **注入点**：`skills/autopilot/references/phase0.5-risk-scan.md`（新文档），由 autopilot 主 skill 在 Phase 0 banner 后调度。
- **产出**：`openspec/changes/{change}/reports/risk-scan.md`
- **prompt 模式**：
  ```
  你是红队审阅员。给定需求摘要与最近 30 天 git log，列出：
  1. 历史上此模块的 3 类典型故障
  2. 本次变更可能复现的 2 种失败模式
  3. 建议 Phase 4 必须覆盖的反例（sad path）
  ```

### C2 · phase5.5-redteam

- **职责**：Phase 5 实现完成后、Phase 6 测试报告前，插入红队审计：围绕 AuthZ / InputValidation / ErrorHandling / Concurrency / Secret 五类做 adversarial review。
- **注入点**：`skills/autopilot-phase5-implement/SKILL.md` 末尾调用；gate 层新增 `phase5.5` checkpoint。
- **产出**：`reports/redteam-findings.json`（同 review findings 结构）
- **与 autopilot-gate 集成**：`blocking: true` 的 findings fail-closed，阻断 Phase 6；`blocking: false` 作为 Phase 6 测试必须覆盖的用例输入。

### C3 · rubric-registry

- **职责**：统一管理 check_id，避免每个 Phase 自创规则造成漂移。
- **产出文件**：`plugins/spec-autopilot/skills/autopilot/rubrics/*.yaml`
- **Rubric YAML schema**：
  ```yaml
  rubric_id: RUB-AUTHZ-001
  description: "每个新端点必须显式声明鉴权策略"
  severity: high          # low | medium | high | critical
  phase_scope: [phase5, phase5.5]
  evidence_required:
    - type: code_grep
      pattern: "@RequireAuth|@AllowAnonymous"
    - type: test_coverage
      min_sad_path: 2
  applicable_when:
    change_type: [feature, refactor]
  ```

### C4 · feedback-loop

- **职责**：将 C1/C2 的 findings 回灌到 Phase 0 的上下文（下次运行），与 Part C 的学习闭环共用落盘路径。
- **注入点**：Phase 7 archive 时追加 `phase-reflection.json.findings`。

### C5 · regression-vault

- **职责**：把 redteam-findings 中被修复的典型缺陷，转成最小复现测试存入金库，后续每次 Phase 4 必须 include。
- **产出目录**：`plugins/spec-autopilot/regression-vault/{change_type}/*.sh`
- **晋升条件**：同一缺陷模式在 3 个不同 change 中出现 → 自动晋升为默认回归集合。

## 3. 与现有 autopilot-gate 的集成

```
Phase 0 ──→ [C1 risk-scanner] ──→ Phase 1-4 ──→ Phase 5 ──→ [C2 phase5.5-redteam]
                │                                                    │
                ▼                                                    ▼
         risk-scan.md ←───────── rubric-registry (C3) ─────── redteam-findings.json
                                           │
                                           ▼
                           autopilot-gate 8-step + 新增 step 9:
                           "C2 blocking findings == 0"
```

- gate 8 步 checklist 新增 step 9：`redteam_blocking_findings == 0 || phase < 5.5`
- phase-results checkpoint 新增字段 `risk_scan_summary`、`redteam_findings_count`

## 4. Rubric 评审模式（prompt 风格）

Red-team prompt 采用「adversarial code review」风格：

```
你扮演一名有敌意的外部审计员，目标是：在 10 分钟内找出让这段代码出事故的方法。
不要夸奖、不要复述代码、不要建议非关键重构。
只列：
- VULN-<N>: <一句话破坏路径> / <触发条件> / <证据行号>
- 输出 JSON 数组，severity ∈ {low, medium, high, critical}
```

参考业界实现：

1. [Cognition / Devin — Review Loop (Devin 内置自审)](https://www.cognition.ai/blog/introducing-devin)
2. [Cursor — Vulnerability Hunter mode（Cursor 博客 2025）](https://www.cursor.com/blog)
3. [Anthropic — Adversarial Code Review Pattern (Anthropic Agent cookbook)](https://docs.anthropic.com/en/docs/agents-and-tools)

> 注：上述链接为设计参考方向，实际实现以内部 rubric 为准。

## 5. 产出文件一览

| 路径 | 写入者 | 消费者 |
|------|--------|-------|
| `openspec/changes/{change}/reports/risk-scan.md` | C1 | Phase 1 需求分析 Agent、Phase 4 TC 设计 |
| `openspec/changes/{change}/reports/redteam-findings.json` | C2 | autopilot-gate, Phase 6 测试 Agent |
| `plugins/spec-autopilot/skills/autopilot/rubrics/*.yaml` | 人工 + 学习闭环 | C1/C2/C3 |
| `plugins/spec-autopilot/regression-vault/**/*.sh` | C5 自动晋升 | Phase 4 testcase skill |

## 6. 落地节奏

- **Sprint 1**：C1 骨架（可执行但 rubric 只 1-2 条）、C3 schema 冻结
- **Sprint 2**：C2 全量上线，C3 扩展至 10+ rubric
- **Sprint 3**：C5 regression-vault 自动晋升闭环
