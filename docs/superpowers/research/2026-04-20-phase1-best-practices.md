# Phase 1 需求理解阶段重设计 — 调研与最佳实践引用

> 本文沉淀 `docs/superpowers/plans/2026-04-20-phase1-redesign.md` 计划制定过程中所参考的外部 OSS 项目与最佳实践，作为后续审计的追溯根基。

## 1. 核心参考项目

### 1.1 GitHub Spec Kit
- 仓库：<https://github.com/github/spec-kit>
- 采用模式：`[NEEDS CLARIFICATION: 具体问题]` 澄清标记协议。
- 本计划采用点：
  - Phase 1→2 硬门禁：requirements.md 中任一未清零标记即阻断 Phase 2 派发（`check-phase1-gate.sh` 的 Check 1）。
  - BA 模板（`requirements-template.md`）强制 5-section 结构 + 禁止假设性填充，Review Checklist 首项即 "No `[NEEDS CLARIFICATION]` markers remain"。
- 映射任务：A3、B9、B10。

### 1.2 Anthropic Multi-Agent Research Orchestrator-Workers 模式
- 参考来源：Anthropic 公开的 multi-agent research 系统架构描述（orchestrator + parallel workers + serial synthesizer）。
- 采用模式：双路并行 Worker（ScanAgent + ResearchAgent）→ 串行 Synthesizer 仲裁。
- 本计划采用点：
  - Phase 1 拓扑由 v5.x 的 3 路平行（含独立 web_search agent）重设计为 2 并行 + 1 串行。
  - SynthesizerAgent 的职责聚焦：跨路冲突检测、语义去重、`verdict.json` 产出。
- 映射任务：A4、A5、B12。

### 1.3 JSON Schema draft 2020-12 + conditional constraints
- 规范：<https://json-schema.org/draft/2020-12/schema>
- 采用模式：`if/then` 条件约束、`enum` 枚举、`required` 分层。
- 本计划采用点：
  - `synthesizer-verdict.schema.json` 的 `conflict.resolution` enum `["adopted","deferred_to_user","irreconcilable"]`。
  - `research-envelope.schema.json` 的 `web_search_summary` 条件字段（`depth=deep` 才必填 queries_executed）。
  - `requirement-packet.schema.json` 的 `sha256` hex 格式与 `acceptance_criteria.items.required = [text, testable]` 契约。
- 映射任务：A2、A4、A6、B11。

## 2. 四要素任务契约（Four-Field Task Contract）

采用模式来源：OMC（Orchestrator-Model-Context）类 agent 系统的 task_boundary/tool_boundary/output_format 三段结构。

本计划对每一路 Phase 1 Agent 均强制写入以下四个 YAML 字段：

| 字段 | 作用 |
|---|---|
| `task_boundary.your_scope` | 子 Agent 执行步骤（做什么） |
| `task_boundary.not_your_scope` | 边界外职责（不做什么，避免越权） |
| `tool_boundary.allowed` / `forbidden` | 工具白名单 / 禁用列表（ScanAgent 禁止 WebSearch；SynthesizerAgent 禁止 WebSearch/WebFetch/Edit） |
| `output_format.envelope_schema` / `files` | 产出契约（envelope 路径 + 必须写入的 context 文件） |

映射任务：A3（模板）、A4（ResearchAgent）、A5（SynthesizerAgent）、C14（ScanAgent）。

## 3. 配置驱动纪律（No Hardcoded Agent Names）

本计划坚持 agent 字段全部由 `.claude/autopilot.config.yaml` 的 `phases.requirements.*.agent` 动态解析：

- `phases.requirements.auto_scan.agent`（ScanAgent）
- `phases.requirements.research.agent`（ResearchAgent）
- `phases.requirements.synthesizer.agent`（SynthesizerAgent，A7 新增）

`_config_validator.py` 硬阻断 ScanAgent/ResearchAgent 配置值为 `Explore`（Explore 无 Write 权限，无法写 context 文件）。SynthesizerAgent 同约束（需写 `verdict.json`）。

映射任务：A1（config-schema 扩展）、A7（autopilot-agents SKILL 更新）。

## 4. 规则分解耦（Decouple rule_score from BA Output）

采用模式：语言学特征评分取代结构化字段评分。

- 旧版 `rule_score` 从 BA Agent 产出的 `rp.goal/scope/non_goals/acceptance_criteria/context` 字段计算。
- 新版 `rule_score` 从原始用户 prompt 的语言学特征计算：
  - `verb_density`（动词密度）
  - `quantifier_count`（数字/时间单位/阈值词）
  - `role_clarity`（角色词：用户/管理员/访客/admin/user/guest 等）
  - 加权归一到 `[0,1]`

原 `rp.*` 字段降级为 `ai_score[i]` 的 LLM-judge 输入，不再参与规则分。

映射任务：C15（`runtime/scripts/score-raw-prompt.sh`）。

## 5. 失败统一协议（Unified Failure Handling）

弃用旧版 "搜索失败/超时 → 回退到 AI 内置知识" 的降级策略。新版统一协议：

1. 第一次失败 → 窄化重派（Narrowed Retry）：prompt 注入 `previous_failure: { reason, partial_output(500c) }` + task_boundary 缩窄 scope。
2. 第二次失败 → `AskUserQuestion` 升级三选项：(a) 手动重派 / (b) 跳过该路（`verdict.confidence -= 0.2` + `[NEEDS CLARIFICATION]` 追加）/ (c) 回 Phase 0。
3. 禁止行为：fallback 到 AI 内置知识、静默重试 >2 次、首次失败直接 AskUserQuestion。

映射任务：C16。

## 6. 早停 interrupt 协议（Early Interrupt for Blocker Findings）

两路 envelope 新增可选 `interrupt: { severity: "blocker"|"warning", reason: string }` 字段：

- `severity=blocker`：主线程立即 abort 未完成并行 Task → 跳过 SynthesizerAgent → 直接 AskUserQuestion（使用 `interrupt.reason` 作为问题正文）。
- `severity=warning`：记录到 `verdict.rationale`，不中断流程。

映射任务：C17。

## 7. 成熟度 × 项目类型矩阵

调研方案由 2D 矩阵决定（替代 v5.x 的 1D 硬编码表）：

| maturity | project_type | scan | research | research_depth | websearch_subtask |
|---|---|---|---|---|---|
| clear | greenfield | ✅ | ❌ | none | ❌ |
| clear | brownfield | ✅ | ❌ | none | ❌（lite-regression 子任务附在 ScanAgent） |
| partial | greenfield/brownfield | ✅ | ✅ | standard | ❌ |
| ambiguous | greenfield/brownfield | ✅ | ✅ | deep | ✅ |

由 `runtime/scripts/select-research-plan.sh` 统一输出 JSON。禁止主线程硬编码映射。

映射任务：C18。

## 8. 三层 Gate 架构回顾

- **L1（TaskCreate blockedBy）**：主线程编排层，保证 Phase 派发顺序。
- **L2（Hook envelope schema）**：PostToolUse Task hook 按 `<!-- autopilot-phase:1-{scan|research|synthesizer} -->` 标记路由到对应 schema 做运行时校验（B11 实施：`validate-phase1-envelope.sh`）。
- **L3（runtime triple-check script）**：`check-phase1-gate.sh` 执行 Phase 1→2 硬门（B10）：
  1. requirements.md 无 `[NEEDS CLARIFICATION:` 未清零标记。
  2. `verdict.confidence >= threshold`（默认 0.7，可由 `phases.requirements.gate.confidence_threshold` 覆盖）。
  3. `verdict.conflicts` 无 `resolution=irreconcilable` 条目。

## 9. 契约一致性

本计划的全部契约承诺均由集成测试 `tests/integration/test_phase1_e2e_v2.sh`（A8 + B13 扩展）通过 fixture 回放 + schema 校验 + gate 脚本调用的组合方式端到端验证：

- 派发顺序：scan ‖ research → synthesizer
- verdict.json schema 契约
- requirement-packet.json sha256 hex + 必填字段契约
- 无独立 web_search Agent 派发（v5.x deprecated）
- Gate 四案例覆盖（A/B/C/D）

## 10. 作者与审计记录

- 计划作者：主线程（Opus 4）+ subagent-driven-development 三段审查。
- 审计依据：`docs/superpowers/plans/2026-04-20-phase1-redesign.md` 21 个任务全部完成并通过 spec compliance + code quality 两段审查。
- 测试基线：Phase 1 重设计前 ~1933 → 重设计后 **2248 passed, 0 failed**（147 test files）。
- 分支：`feature/spec-autopilot`。

## 11. 后续技术债登记

以下债务在本计划中被识别但不在当前 scope，留待后续任务消化：

1. **research-envelope.schema.json 与 phase1-research-envelope.schema.json 重复**（B11 保留）：后续可通过 JSON `$ref` 或文档链接合并。
2. **L2 Hook scan/research 标记在 dispatch 模板中尚未全面 emit**：C14 landing 后 ScanAgent envelope 含 decision_points/conflicts_detected；但 dispatch 注入 `<!-- autopilot-phase:1-scan -->` 标记的完整闭环需要 D 阶段后的独立任务验证。
3. **SynthesizerAgent Bash 工具白名单（jq/diff）**：当前通过 task_boundary 文档契约约束；Hook 层白名单在 B11 未落地，留作独立强化任务。
4. **check-phase1-gate.sh 集成到 autopilot-gate 主流程**：B10 定义规格并通过 e2e 间接调用；直接绑定到主流程 hook 链路可在后续任务补齐。
5. **`requirements-template.md` 运行时注入**：B9 定义模板；实际 dispatch-phase-prompts.md 中的注入逻辑可在后续增强。
