# Phase 流程后台 Agent 派发审计报告（v5.10.1）

> 审计日期：2026-04-19
> 审计范围：spec-autopilot 各 Phase 的子 Agent 派发链路
> 审计结论：**主框架健康，3 处 critical 需修复（Phase 1 三路单 agent / Phase 6.5 字面量派发 / Phase 7 字面量派发）**

## 总览表

| Phase | 派发 | BG | 名称硬解析 | 信封校验 | 上下文隔离 | Checkpoint | 严重度 |
|-------|:----:|:--:|:---------:|:------:|:--------:|:---------:|:------:|
| 0     | 主线程 | N/A | N/A | N/A | N/A | anchor commit | OK |
| 1     | Task ×3 | ✓ | ✓ (validate-agent-registry) | ✓ envelope_parser | ✓ 红线 | interim+final | **major（三路共享 agent）** |
| 2/3   | Task | ✓ | ⚠ 需主线程替换 | ✓ | ✓ | ✓ fixup | minor |
| 4     | Task / 并行 4 路 | ✓ | ⚠ `{agent_for_type}` 占位符 | ✓ enum=ok\|blocked | ✓ | ✓ | minor |
| 5     | Task / 并行域 | ✓ | ✓ resolve_agent | ✓ + parallel-merge-guard | ✓ | ✓ + worktree | OK |
| 5.5   | 主线程派发文档 | N/A | — | ✓ redteam-report.json | ✓ | ✓ | OK |
| 6     | Task ×3（路径 A/B/C） | ✓ | ⚠ 字面量 `config.phases.reporting.agent` | ✓ | ✓ | ✓ | minor |
| 6.5   | Task | ✓ | ✗ 字面量 `config.phases.code_review.agent` 直传 | ✓ | ✓ | ✓ | **critical** |
| 7     | Task | ✓ | ✗ 字面量 `config.phases.archive.agent` 直传 | ✓ | ✓ | ✓ autosquash | **critical** |

> 图例：✓ 完备 / ⚠ 文档示意需运行时替换 / ✗ 未替换的字面量违反 dispatch SKILL 红线

---

## Phase 0 — 初始化

**评估**：OK

- `phase0-init/SKILL.md` 不派发子 Agent，仅做 config 读取/校验/anchor commit
- `valid === false` 硬阻断（fail-closed）符合预期
- python3 不可用直接 fatal 终止，无静默降级

**风险**：无。

---

## Phase 1 — 需求理解（含三路调研）

**评估**：major（用户报告的核心问题）

### 现状

`autopilot-phase1-requirements/SKILL.md:40-42`：

```
┌─ Auto-Scan (config.phases.requirements.agent)         → Steering Documents     ← 始终执行
├─ 技术调研 (config.phases.requirements.research.agent) → research-findings.md  ← 中/高复杂度
└─ 联网搜索 (config.phases.requirements.research.agent) → web-research-findings.md ← 高复杂度
```

`parallel-phase1.md:11-19` / `auto-emit-agent-dispatch.sh:57-63` 均按**二元映射**实现：技术调研与联网搜索**共享同一 agent**。

### 问题

1. **能力错配**：联网搜索需 WebSearch + 信息综合，技术调研需 reasoning + 文档分析；两者强行复用同一 agent 会稀释专长（参见 `agent-sources-survey.md` Part D）
2. **setup wizard 引导不全**：`setup-agent-model-guide.md:42-49` 只问 2 个 agent（`requirements.agent` + `requirements.research.agent`），用户无法为联网搜索单独选 `search-specialist`
3. **运行时校验只能保证"与 config 一致"，不能保证"用对 agent"**：当前用户即使用 OMC researcher 也合规，但联网搜索效果差

### 建议修复（与 Issue #2 合并实施）

新增 3 独立字段（auto_scan/research/web_search 各 agent），保留 `requirements.research.agent` 作为 web_search 的 fallback 实现兼容。

**位置**：`file:plugins/spec-autopilot/skills/autopilot/references/parallel-phase1.md:11-23`、`runtime/scripts/auto-emit-agent-dispatch.sh:57-63`、`skills/autopilot-setup/references/setup-agent-model-guide.md:18-52`、`runtime/scripts/_config_validator.py:154`

---

## Phase 2/3 — OpenSpec + FF 生成

**评估**：minor

- ✓ `run_in_background: true` 强制（SKILL.md:21,39）
- ✓ JSON 信封必需（dispatch.md:232-234）
- ⚠ SKILL.md:19,37 的 `Agent: config.phases.openspec.agent（默认 Plan）` 是文档表述，主线程实际派发时由 dispatch SKILL 强制替换为字面量。但模板文档仍可能误导新人复制粘贴 → 建议加注释或改为 `<{{config.phases.openspec.agent}}>` 显式占位

**主要风险**：默认 agent 为 `Plan`（内置只读 agent），与 Phase 2/3 需要 Write 矛盾。但 OMC `executor` 已被 setup wizard 推荐覆盖，新装用户不会受影响；**老用户升级需要 migration 提示**。

---

## Phase 4 — 测试设计（TDD）

**评估**：minor

- ✓ `run_in_background: true` 强制
- ✓ status 仅允许 `ok | blocked`，禁止 `warning`（dispatch.md:236）
- ⚠ `parallel-phase4.md:36` 模板用 `subagent_type: "{agent_for_type}"` 占位符，要求主线程在派发前替换。auto-emit hook 的 Phase ≥2 Explore 阻断生效，未硬解析会被拦截
- ✓ Hook 测试金字塔地板 / change_coverage / sad_path 比例完备

**主要风险**：`{agent_for_type}` 在并行 4 路（unit/api/e2e/ui）派发时，每路应能独立映射到不同 agent，但现有 `config.phases.testing.agent` 是单值。**建议未来扩展为 `phases.testing.agent_per_type` 映射**（本次不做，记入 backlog）。

---

## Phase 5 — 实施（含并行域 Agent）

**评估**：OK（基础设施最完备）

- ✓ 并行/串行路径互斥由 `config.phases.implementation.parallel.enabled` 决定（mode-routing-table.md），主线程严禁切换
- ✓ 并行域 agent 通过 `domain_agents[prefix].agent` 配置，`phase5-implementation.md:198,484` 用 `subagent_type: config.phases...domain_agents[domain].agent` 模板，**实际派发由 dispatch SKILL 替换为字面量**
- ✓ owned_files 由 parallel-merge-guard 校验
- ✓ worktree 隔离 + 失败降级（worktree fallback → 串行重执行）
- ✓ TDD RED-GREEN-REFACTOR L2 hook 完备

**主要风险**：domain_agents 默认全部为 `general-purpose`（config-schema.md:108-113），用户不主动配置时并行优势归零。已在 setup-domain-agent-guide.md 引导，但**需要 wizard 默认推荐 VoltAgent backend/frontend-developer**（Issue #1）。

---

## Phase 5.5 — Red Team

**评估**：OK

- 文档 phase 序号约定，运行时由主 SKILL 编排
- 输出契约清晰：`redteam-report.json` + `tests/generated/redteam-*.sh`
- `blocking_reproducers > 0` 阻断 Phase 6（与 phase6-gate 集成）

**主要风险**：未在 dispatch-phase-prompts.md 中注册独立的 phase5.5 派发模板。当前由主 SKILL 直接派发（推断为前台或后台不明）。**建议补充 dispatch 模板，明确 BG + 信封契约**（minor，记入 backlog）。

---

## Phase 6 — 测试 + 报告

**评估**：minor

- ✓ 路径 A（测试）/ B（代码审查）/ C（质量扫描）三路并行，**全部 `run_in_background: true`**（SKILL.md:49,63；parallel-phase6.md:24-52）
- ✓ Allure 报告流程完备
- ⚠ `parallel-phase6.md:47` 写 `Task(subagent_type: config.phases.reporting.agent, ...)` 字面量，与 dispatch SKILL 红线冲突；运行时由主线程替换，但模板示范不利于贡献者理解

**主要风险**：路径 C 质量扫描的 prompt **不含 `<!-- autopilot-phase:N -->` 标记**（quality-scans.md:91），意味着 Hook 校验链路绕过——这是设计意图（信息性扫描），但需要确认 anti-rationalization-check / json envelope 仍生效。建议在 quality-scans.md 加一节"绕过项明示"。

---

## Phase 6.5 — Code Review

**评估**：**critical**

### 现状

`phase6-code-review.md:34`：

```
Task(
  subagent_type: config.phases.code_review.agent,
  ...
  run_in_background: true,
  prompt: "<!-- autopilot-phase:6 -->..."
)
```

### 问题

1. **字面量违反 dispatch SKILL 红线**：`autopilot-dispatch/SKILL.md:46` 明文禁止"在任何 Task 调用中直接写 `subagent_type: config.phases.X.Y`"。这正是触发 LLM 启发式降级到 `Explore`/`general-purpose` 的根因。
2. **auto-emit-agent-dispatch.sh** 的占位符检测正则 `subagent_type[[:space:]]*:[[:space:]]*(config\.phases\.|\{\{)` 在 Phase ≥2 会阻断该派发，但 Phase 6.5 用 `<!-- autopilot-phase:6 -->` 标记（注意是 6 不是 6.5），仍会触发占位符 guard——**目前是被动救场**而非主动正确
3. 默认 `pr-review-toolkit:code-reviewer` 是市场插件名，非 `.claude/agents/*.md` agent，运行时是否被 validate-agent-registry.sh 接受需验证

### 建议修复

将 `phase6-code-review.md:34` 改为 dispatch SKILL 推荐写法：

```
1. AGENT_NAME=$(yq '.phases.code_review.agent' .claude/autopilot.config.yaml)
2. bash $CLAUDE_PLUGIN_ROOT/runtime/scripts/validate-agent-registry.sh "$AGENT_NAME" || return blocked
3. Task(subagent_type: "$AGENT_NAME", ...)
```

**位置**：`file:plugins/spec-autopilot/skills/autopilot/references/phase6-code-review.md:34`

---

## Phase 7 — 归档

**评估**：**critical**

### 现状

`autopilot-phase7-archive/SKILL.md:59,91`：

```
Task(subagent_type: config.phases.archive.agent, prompt: "...")
Task(subagent_type: config.phases.archive.agent, run_in_background: true)
```

`allure-preview-and-report.md:14` 同样问题。

### 问题

与 Phase 6.5 同源——字面量未替换。Phase 7 归档涉及 autosquash + git fixup + 知识抽取，若派发到 Explore 会导致归档失败（Explore 无 Write 权限）。auto-emit hook 的 Explore 阻断会救场但 UX 极差。

### 建议修复

同 Phase 6.5：先 yq 读 config → validate-agent-registry → 字面量传入 Task。

**位置**：`file:plugins/spec-autopilot/skills/autopilot-phase7-archive/SKILL.md:59`、`:91`、`references/allure-preview-and-report.md:14`

---

## Top 5 必须修复项

| 序 | 严重度 | 问题 | 定位 | 建议 patch |
|---|------|------|------|----------|
| 1 | **critical** | Phase 1 三路调研共享同 agent，联网搜索能力错配 | `parallel-phase1.md:11-23`、`auto-emit-agent-dispatch.sh:57-63`、`setup-agent-model-guide.md:42-49`、`_config_validator.py:154` | 拆为 `auto_scan.agent` / `research.agent` / `web_search.agent` 三独立字段；hook 三元映射；wizard 三独立提问；validator 新增三字段 |
| 2 | **critical** | Phase 6.5 code_review 字面量 dispatch | `phase6-code-review.md:34` | 改为 yq 读 config → validate → 字面量传入 |
| 3 | **critical** | Phase 7 archive 字面量 dispatch | `phase7-archive/SKILL.md:59,91`、`allure-preview-and-report.md:14` | 同上 |
| 4 | major | Phase 5 域 agent 默认 general-purpose，用户未配置时并行无收益 | `config-schema.md:108-113`、`setup-domain-agent-guide.md` | wizard 默认推荐 VoltAgent `backend-developer`/`frontend-developer`，并自动写入 |
| 5 | minor | Phase 5.5 redteam 未在 dispatch-phase-prompts 注册独立模板 | `dispatch-phase-prompts.md`（缺 phase5.5 节） | 补 phase5.5 派发模板，明确 BG + 信封契约 |

---

## 结论

### 基础设施就绪度

**spec-autopilot 已具备"7 Phase 全部用独立后台子 Agent"的基础设施**：
- ✓ Task `run_in_background: true` 在 Phase 2/3/4/5/6/6.5/7 全部强制
- ✓ JSON 信封 + `_envelope_parser.py` + `post-task-validator.sh` 通用校验链路
- ✓ Hook 三层防线（L1 TaskCreate / L2 Bash 确定性 / L3 AI Gate）
- ✓ 名称硬解析机制（`validate-agent-registry.sh` + `auto-emit-agent-dispatch.sh` 占位符 guard）
- ✓ 上下文隔离红线（主线程禁 Read 子 Agent 大产物）

### 主要缺口

1. **Phase 1 三路调研只有 2 个 agent 配置位**——本次必须修复（Issue #2 核心）
2. **Phase 6.5 / Phase 7 文档示范用了字面量 `subagent_type: config.phases.X.agent`**，是 LLM 启发式降级的诱因；当前由 hook 占位符 guard 救场，但治本需改文档
3. **Phase 5 域 agent 默认值** 是 `general-purpose`，并行执行优势归零；wizard 应默认推荐 VoltAgent 域专职 agent

### 修复策略

- **本次 PR 范围**：Issue #1（Agent 默认预设）+ Issue #2（Phase 1 三路拆分）
- **后续 PR 范围**：Phase 6.5 / Phase 7 字面量改造、Phase 5.5 dispatch 模板补全、Phase 4 测试 agent 按类型路由

修复优先级：1 > 2 > 3 > 4 > 5。
