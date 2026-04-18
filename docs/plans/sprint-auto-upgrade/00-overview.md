# Sprint Auto-Upgrade 总览

> 版本：v0.1（设计单一真相来源）
> 范围：spec-autopilot 编排器的自愈 / 自省 / 自学习能力升级
> 产出目录：`docs/plans/sprint-auto-upgrade/`

## 1. 背景

当前 spec-autopilot 在持续运行中暴露三类系统性问题：

1. **Phase 1 Agent 名称解析 BUG**：日志中频繁出现 `subagent_type: Explore`（Claude 内置通用类型），而非 `.claude/autopilot.config.yaml` 中注册的 `general-purpose` / `requirements-analyst` 等 Agent。根因已定位在 `plugins/spec-autopilot/skills/autopilot/references/parallel-phase1.md:53/62/71`：Task 调用写成字面量 `subagent_type: config.phases.requirements.agent` 的模板占位符，主线程 LLM 未执行「配置解析」动作，而是基于 description 启发式地落到内置 Explore/general-purpose，导致预设 Agent 身份丢失、owned_files 校验失效。
2. **缺少主动风险扫描**：Phase 5/6 的门禁以「提交物是否符合 schema」为主，缺少对手视角（adversarial / red-team）的破坏性审视，漏报集中在跨 Phase 串通性缺陷（需求裂缝、威胁建模遗漏、回归面扩大）。
3. **缺少主动学习**：每次 run 的 reflection 停留在 `logs/events.jsonl` 与 `phase-results/` 中，没有闭环回灌到下次 Phase 0 上下文；失败模式重复踩坑，成功模式无法沉淀为可复用 skill。

## 2. 目标（按 Sprint 分层）

| Sprint | 主题 | 关键产出 |
|--------|------|---------|
| **Sprint 1** | BUG 修复 + 最小闭环 | 模板硬解析、注册表校验、PostToolUse 阻断、risk-scanner 骨架、phase-reflection 落盘 |
| **Sprint 2** | Rubric + 闭环回灌 + Pattern 聚类 | rubric-registry、phase5.5-redteam、autopilot-learn skill、claude-mem 集成、build_corpus 自动化 |
| **Sprint 3** | regression-vault + skill 晋升 | 回归用例金库、pattern → skill 自动晋升、CLAUDE.md「习得规则区」 |

## 3. 总体架构

```
                    spec-autopilot 升级总架构 (三主线)
  ┌───────────────────────────────────────────────────────────────────────┐
  │                                                                       │
  │  Part A: BUG 修复                Part B: 风险扫描            Part C: 主动学习
  │  ─────────────                   ──────────────              ────────────────
  │  A1 模板硬解析                    C1 risk-scanner (Phase 0.5) L1 Episode
  │  A2 注册表校验                    C2 phase5.5-redteam         (reflection JSON
  │  A3 dispatch 显式禁令             C3 rubric-registry           + claude-mem obs)
  │  A4 回归 testcase                 C4 feedback-loop            L2 Pattern
  │  A5 PostToolUse 阻断              C5 regression-vault         (autopilot-learn skill
  │       │                              │                         + build_corpus)
  │       ▼                              ▼                         L3 Skill/Rule 晋升
  │  autopilot-dispatch ────────→ autopilot-gate ────────→ Phase 7 archive
  │       │                              │                         │
  │       └───── events.jsonl ───────────┴────── phase-results ────┘
  │                                      │
  │                                      ▼
  │                            .claude-mem / CLAUDE.md 习得规则区
  └───────────────────────────────────────────────────────────────────────┘
```

## 4. 验收标准

- **A. Agent 身份正确性**（硬性）：任一次 autopilot 运行，`logs/events.jsonl` 中所有 `task_dispatch` 事件的 `subagent_type` 字段必须满足：
  - 值 ∈ `.claude/autopilot.config.yaml` 的 `phases.*.agent` 注册集合，或
  - 值 == `general-purpose`（明确 fallback）
  - **禁止** 出现 `Explore`、未注册字符串、或字面量 `config.phases.*`。
- **B. 风险扫描存在性**：每次 run 必须生成 `openspec/changes/{change}/reports/risk-scan.md`，且 Phase 5.5 输出 `redteam-findings.json`，blocking findings 走 fail-closed。
- **C. 学习闭环存在性**：每次 Phase 7 归档必须产出 `phase-reflection.json`，并写入 claude-mem（obs_type ∈ {phase_reflection, success_pattern, failure_pattern}）；下次 Phase 0 banner 中必须显示「上次教训 Top-3」。
- **D. 回归保护**：新增 Bash 测试（`tests/test_phase1_agent_resolution.sh`）覆盖 A1-A5，CI 全绿。

## 5. 风险与降级

- 若 Sprint 1 A1（模板硬解析）触碰现有 dispatch skill 过深，降级为 A3+A5 软拦截（禁令 prompt + PostToolUse 阻断），保证至少「不静默发生 Explore fallback」。
- 风险扫描若引入耗时 > 30s，Phase 0.5 走并行背景 Agent，不占 Phase 1 wall-clock。
- 学习闭环若 claude-mem 不可用，降级为纯 JSON 落盘 + 下次 Phase 0 Bash 读取 top-3。

## 6. 文件地图

- `00-overview.md`（本文）
- `01-bug-fix.md`：Part A 详设
- `02-risk-scanner.md`：Part B 详设
- `03-active-learning.md`：Part C 详设
