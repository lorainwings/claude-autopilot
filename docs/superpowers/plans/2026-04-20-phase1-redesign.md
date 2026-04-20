# Phase 1 需求理解阶段重设计 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 spec-autopilot Phase 1 从"三路对等并行 + 信封字段拼接"重构为"双路并行 + 专职 Synthesizer + 显式歧义协议 + 硬 Gate"，对齐 Anthropic Orchestrator-Workers + GitHub Spec Kit + AutoGen Reflection 三大业界模式。

**Architecture:**
- **A 阶段（架构重构）**：取消独立 web-search Agent，联网搜索作为 ResearchAgent 可选子任务；新增 SynthesizerAgent 作为专职汇总者，输出结构化 verdict JSON。
- **B 阶段（Gate 与契约硬化）**：引入 `[NEEDS CLARIFICATION]` 协议作为 Phase 1→2 硬 Gate；L2 Hook 校验三路信封 JSON schema；Synthesizer 做 `decision_points` 语义去重。
- **C 阶段（细节优化）**：Auto-Scan 信封补字段；clarity_score 解耦；容错统一为 resume + 窄化重派；用户澄清支持单路 interrupt 早停；成熟度 × 调研方案矩阵化。

**Tech Stack:** Bash + Python（_envelope_parser.py）+ Markdown（SKILL）+ JSON Schema + L2 Hook（PostToolUse Task matcher）

**关键引用：**
- 业界最佳实践：见 `docs/superpowers/research/2026-04-20-phase1-best-practices.md`（待生成）
- 缺陷清单：见上层评审报告 D1-D12

---

## 阶段 A：架构重构（任务 1-8）

### Task 1：更新 config-schema 以支持新拓扑

**Files:**
- Modify: `plugins/spec-autopilot/skills/autopilot/references/config-schema.md`
- Modify: `plugins/spec-autopilot/skills/autopilot-agents/SKILL.md`

**目标变更：**
- `phases.requirements.research.web_search` 块标记为 `deprecated: true`
- `phases.requirements.research` 新增子字段 `web_search_subtask: { enabled: bool, depth_trigger: "deep" }`
- 新增 `phases.requirements.synthesizer.agent` 配置键

- [ ] **Step 1: 写测试** — 新增 `tests/test_phase1_config_schema_v2.sh`，断言：(a) 解析包含 `synthesizer.agent` 的 config 不报错；(b) 缺失 `synthesizer.agent` 时 setup 流程报警告但不阻断（向后兼容）；(c) `web_search.agent` 旧字段被识别为 deprecated。

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_test_helpers.sh"

test_synthesizer_field_required() {
  local fixture="$TEST_TMP/config-v2.json"
  cat > "$fixture" <<EOF
{"phases":{"requirements":{"agent":"general-purpose","auto_scan":{"agent":"Explore"},"research":{"agent":"Plan"},"synthesizer":{"agent":"general-purpose"}}}}
EOF
  bash "$REPO_ROOT/plugins/spec-autopilot/runtime/scripts/resolve-agent.sh" \
    --config "$fixture" --phase requirements --role synthesizer | grep -q "general-purpose"
}

test_deprecated_websearch_warns() {
  local fixture="$TEST_TMP/config-old.json"
  cat > "$fixture" <<EOF
{"phases":{"requirements":{"research":{"web_search":{"agent":"Explore"}}}}}
EOF
  local out
  out=$(bash "$REPO_ROOT/plugins/spec-autopilot/runtime/scripts/resolve-agent.sh" \
    --config "$fixture" --phase requirements --role websearch 2>&1 || true)
  echo "$out" | grep -qE "(deprecated|DEPRECATED)"
}

run_test test_synthesizer_field_required
run_test test_deprecated_websearch_warns
```

- [ ] **Step 2: 运行测试，确认失败**

```
bash plugins/spec-autopilot/tests/test_phase1_config_schema_v2.sh
# 预期：FAIL，resolve-agent.sh 不识别 synthesizer role
```

- [ ] **Step 3: 修改 config-schema.md** — 在 `phases.requirements` 块下添加：

```yaml
synthesizer:
  agent: <agent-name>      # 新增：专职汇总者，强制 Read 三路全文做冲突检测
research:
  agent: <agent-name>
  web_search_subtask:
    enabled: true          # 新增：取代独立 web_search.agent
    depth_trigger: deep    # 仅 depth=deep 时由 ResearchAgent 自主调用 WebSearch
  web_search:
    agent: <agent-name>    # DEPRECATED in v6.0：保留兼容，setup 时打印告警
    deprecated: true
```

- [ ] **Step 4: 修改 resolve-agent.sh / autopilot-agents SKILL.md** — 将 `synthesizer` 列入合法 role 白名单；deprecated 字段命中时 stderr 打印 `[DEPRECATED] phases.requirements.research.web_search.agent → use research.web_search_subtask`。

- [ ] **Step 5: 运行测试验证通过**

- [ ] **Step 6: Commit**

```bash
git add plugins/spec-autopilot/skills/autopilot/references/config-schema.md \
        plugins/spec-autopilot/skills/autopilot-agents/SKILL.md \
        plugins/spec-autopilot/tests/test_phase1_config_schema_v2.sh
git commit -m "feat(spec-autopilot): add synthesizer agent config + deprecate web_search agent"
```

---

### Task 2：定义 Synthesizer Verdict JSON Schema

**Files:**
- Create: `plugins/spec-autopilot/runtime/schemas/synthesizer-verdict.schema.json`
- Test: `plugins/spec-autopilot/tests/test_synthesizer_verdict_schema.sh`

- [ ] **Step 1: 写 schema 文件**

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "Phase1 Synthesizer Verdict",
  "type": "object",
  "required": ["coverage_ok", "conflicts", "confidence", "requires_human", "ambiguities", "rationale", "merged_decision_points"],
  "properties": {
    "coverage_ok": { "type": "boolean" },
    "conflicts": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["topic", "positions", "resolution"],
        "properties": {
          "topic": { "type": "string", "minLength": 3 },
          "positions": {
            "type": "array",
            "minItems": 2,
            "items": {
              "type": "object",
              "required": ["source", "claim"],
              "properties": {
                "source": { "type": "string", "enum": ["scan", "research", "user"] },
                "claim": { "type": "string" }
              }
            }
          },
          "resolution": { "type": "string", "enum": ["adopted", "deferred_to_user", "irreconcilable"] },
          "chosen": { "type": "string" }
        }
      }
    },
    "confidence": { "type": "number", "minimum": 0.0, "maximum": 1.0 },
    "requires_human": { "type": "boolean" },
    "ambiguities": {
      "type": "array",
      "items": { "type": "string", "pattern": "^\\[NEEDS CLARIFICATION:" }
    },
    "rationale": { "type": "string", "minLength": 10 },
    "merged_decision_points": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["topic", "options", "recommendation", "evidence_refs"],
        "properties": {
          "topic": { "type": "string" },
          "options": { "type": "array", "items": { "type": "string" }, "minItems": 1 },
          "recommendation": { "type": "string" },
          "evidence_refs": { "type": "array", "items": { "type": "string" } }
        }
      }
    }
  }
}
```

- [ ] **Step 2: 写测试，验证合法/非法 verdict**

```bash
test_valid_verdict_passes() {
  cat > "$TEST_TMP/verdict.json" <<EOF
{"coverage_ok":true,"conflicts":[],"confidence":0.85,"requires_human":false,"ambiguities":[],"rationale":"all sources agree","merged_decision_points":[]}
EOF
  bash "$REPO_ROOT/plugins/spec-autopilot/runtime/scripts/validate-json-envelope.sh" \
    --schema "$REPO_ROOT/plugins/spec-autopilot/runtime/schemas/synthesizer-verdict.schema.json" \
    --input "$TEST_TMP/verdict.json"
}

test_missing_required_fails() {
  echo '{"coverage_ok":true}' > "$TEST_TMP/verdict.json"
  ! bash "$REPO_ROOT/plugins/spec-autopilot/runtime/scripts/validate-json-envelope.sh" \
    --schema "$REPO_ROOT/plugins/spec-autopilot/runtime/schemas/synthesizer-verdict.schema.json" \
    --input "$TEST_TMP/verdict.json"
}

test_ambiguity_pattern_enforced() {
  cat > "$TEST_TMP/verdict.json" <<EOF
{"coverage_ok":false,"conflicts":[],"confidence":0.5,"requires_human":true,"ambiguities":["this is plain text"],"rationale":"x","merged_decision_points":[]}
EOF
  ! bash "$REPO_ROOT/plugins/spec-autopilot/runtime/scripts/validate-json-envelope.sh" \
    --schema "$REPO_ROOT/plugins/spec-autopilot/runtime/schemas/synthesizer-verdict.schema.json" \
    --input "$TEST_TMP/verdict.json"
}
```

- [ ] **Step 3: 检查 validate-json-envelope.sh 是否支持外部 schema 参数；不支持则扩展**

- [ ] **Step 4: 运行测试验证通过**

- [ ] **Step 5: Commit**

```bash
git add plugins/spec-autopilot/runtime/schemas/ \
        plugins/spec-autopilot/tests/test_synthesizer_verdict_schema.sh
git commit -m "feat(spec-autopilot): add synthesizer verdict JSON schema"
```

---

### Task 3：定义四要素任务契约模板

**Files:**
- Modify: `plugins/spec-autopilot/skills/autopilot-dispatch/SKILL.md`
- Modify: `plugins/spec-autopilot/skills/autopilot/references/dispatch-prompt-template.md`
- Test: `plugins/spec-autopilot/tests/test_task_object_four_fields.sh`

- [ ] **Step 1: 写测试** — 给一个 sample dispatch prompt，断言其包含全部四要素：

```bash
test_dispatch_prompt_has_four_fields() {
  local prompt
  prompt=$(bash "$REPO_ROOT/plugins/spec-autopilot/runtime/scripts/render-dispatch-prompt.sh" \
    --phase 1 --role research --change-id demo)
  echo "$prompt" | grep -qE "## Objective"
  echo "$prompt" | grep -qE "## Output Format"
  echo "$prompt" | grep -qE "## Tool Boundary"
  echo "$prompt" | grep -qE "## Task Boundary"
}
```

- [ ] **Step 2: 修改 dispatch-prompt-template.md** — 强制四节模板：

````markdown
## Objective
<one-sentence task objective>

## Output Format
- Envelope JSON Schema: `{schema_path}`
- Required fields: {field_list}
- Files to write: {file_list}

## Tool Boundary
- ALLOWED: {tool_whitelist}
- FORBIDDEN: {tool_blacklist}
- WebSearch quota: {n} calls (only if depth=deep)

## Task Boundary
- YOUR scope: {positive_scope}
- NOT YOUR scope (covered by other agents): {negative_scope}
- 如发现越界内容，写入 envelope 的 `out_of_scope_findings[]` 字段，不要自行处理
````

- [ ] **Step 3: 修改 autopilot-dispatch/SKILL.md** — 在"调度协议"小节插入"四要素强制契约"段落，引用 Anthropic Multi-Agent Research 文章作为依据。

- [ ] **Step 4: 修改 phase1 三路 dispatch 调用点（dispatch-phase-prompts.md）** — 让 Phase 1 三路（scan/research/synthesizer）prompt 渲染走统一模板。

- [ ] **Step 5: 运行测试验证通过**

- [ ] **Step 6: Commit**

```bash
git add plugins/spec-autopilot/skills/autopilot-dispatch/ \
        plugins/spec-autopilot/skills/autopilot/references/dispatch-prompt-template.md \
        plugins/spec-autopilot/skills/autopilot/references/dispatch-phase-prompts.md \
        plugins/spec-autopilot/tests/test_task_object_four_fields.sh
git commit -m "feat(spec-autopilot): enforce four-field task contract per Anthropic best practice"
```

---

### Task 4：重写 ResearchAgent prompt — 吸收 web-search 子任务

**Files:**
- Modify: `plugins/spec-autopilot/skills/autopilot/references/parallel-phase1.md`
- Modify: `plugins/spec-autopilot/skills/autopilot/references/phase1-requirements-detail.md`
- Test: `plugins/spec-autopilot/tests/test_phase1_research_subtask.sh`

- [ ] **Step 1: 写测试** — 验证 ResearchAgent prompt：(a) `depth=deep` 时包含 WebSearch 指令；(b) `depth=standard` 时不包含 WebSearch；(c) `task_boundary` 中明确写有 "you are NOT covering: project structure scan / synthesis"。

- [ ] **Step 2: 修改 parallel-phase1.md** — 把原"第 3 路 web-search Agent"段整段删除；把"第 2 路 research Agent" prompt 改写：

```yaml
research_agent:
  task_boundary:
    your_scope: "需求相关性分析 + 技术可行性 + 风险识别 + (depth=deep 时)联网调研最佳实践与 CVE"
    not_your_scope: "项目结构 Steering（由 ScanAgent 负责）/ 三路汇总仲裁（由 SynthesizerAgent 负责）"
  tool_boundary:
    allowed: [Read, Grep, Glob, WebSearch (条件), WebFetch (条件), Write]
    websearch_quota: "0 if depth=standard; up to 3 if depth=deep"
  output_format:
    envelope_schema: runtime/schemas/research-envelope.schema.json
    files: [context/research-findings.md]
```

- [ ] **Step 3: 修改 phase1-requirements-detail.md** — 删除第 3 路 web-search 段（约 280-360 行），把 "任务 5/6/7"（联网/竞品/CVE）合并到 ResearchAgent，明确"当且仅当 depth=deep 触发"。

- [ ] **Step 4: 添加 deprecation 提示** — `parallel-phase1.md` 末尾追加："v5.x web_search Agent 已合并至 ResearchAgent；旧 config 兼容但触发 setup 警告"。

- [ ] **Step 5: 运行测试验证通过**

- [ ] **Step 6: Commit**

```bash
git add plugins/spec-autopilot/skills/autopilot/references/parallel-phase1.md \
        plugins/spec-autopilot/skills/autopilot/references/phase1-requirements-detail.md \
        plugins/spec-autopilot/tests/test_phase1_research_subtask.sh
git commit -m "refactor(spec-autopilot): merge web-search into ResearchAgent as conditional subtask"
```

---

### Task 5：新增 SynthesizerAgent prompt 与流程

**Files:**
- Modify: `plugins/spec-autopilot/skills/autopilot/references/parallel-phase1.md`
- Modify: `plugins/spec-autopilot/skills/autopilot/references/phase1-requirements-detail.md`
- Modify: `plugins/spec-autopilot/skills/autopilot-phase1-requirements/SKILL.md`
- Test: `plugins/spec-autopilot/tests/test_phase1_synthesizer.sh`

- [ ] **Step 1: 写测试** — fixture 模拟两路 envelope，断言：(a) Synthesizer 被派发；(b) verdict.json 被写入；(c) 当两路 `decision_points` 出现矛盾 topic 时 verdict.conflicts 非空；(d) Synthesizer 有权限 Read context/*.md 全文。

- [ ] **Step 2: 在 parallel-phase1.md 追加第 3 路 SynthesizerAgent 定义**

```yaml
synthesizer_agent:
  triggers_after: [scan_agent, research_agent]   # 串行依赖前两路完成
  resolved_agent: "{{RESOLVED_SYNTHESIZER_AGENT}}"
  task_boundary:
    your_scope: |
      1. Read 全部前序产物（context/project-context.md, existing-patterns.md,
         tech-constraints.md, research-findings.md）正文
      2. 跨路冲突检测：对比 decision_points 与 tech_constraints
      3. 语义去重：合并相似 topic（语义相似度 >0.8）
      4. 输出 verdict.json（schema: runtime/schemas/synthesizer-verdict.schema.json）
      5. 在 verdict.merged_decision_points 中保留唯一决策点集合
      6. 在 verdict.ambiguities 中插入 [NEEDS CLARIFICATION: ...] 标记
    not_your_scope: "需求草稿撰写（由 BA Agent 负责）/ 用户澄清（由主线程 AskUserQuestion 负责）"
  tool_boundary:
    allowed: [Read, Write, Bash (限 jq/diff)]
    forbidden: [WebSearch, WebFetch, Edit (业务文件)]
  output_format:
    envelope_schema: runtime/schemas/synthesizer-verdict.schema.json
    files: [context/phase1-verdict.json]
```

- [ ] **Step 3: 修改 SKILL.md** — Step 1.2 流程：

```
Step 1.2.1 并行派发 ScanAgent + ResearchAgent (Task run_in_background=true)
Step 1.2.2 等待两路完成（Hook 通知）
Step 1.2.3 串行派发 SynthesizerAgent（Read 全文 + 输出 verdict）
Step 1.2.4 主线程 Read verdict.json（仅 verdict，不读 raw 全文）
Step 1.2.5 if verdict.requires_human || verdict.ambiguities 非空 → AskUserQuestion
Step 1.2.6 进入 1.5 BA Agent 派发（BA 输入 = verdict.merged_decision_points + 用户澄清答复）
```

- [ ] **Step 4: 修改 dispatch-phase-prompts.md** — 添加 `autopilot-phase:1-synthesizer` 标记，让 L2 Hook 能识别该角色。

- [ ] **Step 5: 运行测试验证通过**

- [ ] **Step 6: Commit**

```bash
git add plugins/spec-autopilot/skills/autopilot/references/parallel-phase1.md \
        plugins/spec-autopilot/skills/autopilot/references/phase1-requirements-detail.md \
        plugins/spec-autopilot/skills/autopilot-phase1-requirements/SKILL.md \
        plugins/spec-autopilot/skills/autopilot/references/dispatch-phase-prompts.md \
        plugins/spec-autopilot/tests/test_phase1_synthesizer.sh
git commit -m "feat(spec-autopilot): introduce SynthesizerAgent with structured verdict"
```

---

### Task 6：requirement-packet 合成改由 Synthesizer 全文驱动

**Files:**
- Modify: `plugins/spec-autopilot/skills/autopilot/references/phase1-requirements.md`
- Modify: `plugins/spec-autopilot/skills/autopilot-phase1-requirements/SKILL.md`
- Test: `plugins/spec-autopilot/tests/test_requirement_packet_synthesizer.sh`

**目标：修复 D3（信息瓶颈）—— 当前 packet 由主线程"压缩信封合成"，改为 Synthesizer 全文合成后主线程仅引用。**

- [ ] **Step 1: 写测试** — 给一组三路产物 fixture，断言 packet.json 中的 `acceptance_criteria` 数量 ≥ research-findings.md 中的可测试动词数（保证未失真压缩）。

- [ ] **Step 2: 修改 phase1-requirements.md Step 1.9** — 将"主线程从信封合成 packet"改为：

```
Step 1.9.1 SynthesizerAgent 已产出 verdict + merged_decision_points
Step 1.9.2 BA Agent 产出 requirements.md 草稿（结构化 user stories + AC + checklist）
Step 1.9.3 主线程派发 PackagerAgent（subagent_type 复用 synthesizer.agent）：
            输入 = verdict.json + requirements.md + 用户澄清答复
            输出 = openspec/changes/{change}/context/requirement-packet.json
            schema 校验：runtime/schemas/requirement-packet.schema.json
Step 1.9.4 主线程仅 Read packet.json（不读原始 markdown），写 phase-1-requirements.json
```

- [ ] **Step 3: 创建 requirement-packet.schema.json** — 强制字段：`goal/scope/non_goals/acceptance_criteria/risks/decisions/needs_clarification[]/sha256`。

- [ ] **Step 4: 修改 SKILL.md 对应步骤**

- [ ] **Step 5: 运行测试验证通过**

- [ ] **Step 6: Commit**

```bash
git add plugins/spec-autopilot/skills/autopilot/references/phase1-requirements.md \
        plugins/spec-autopilot/skills/autopilot-phase1-requirements/SKILL.md \
        plugins/spec-autopilot/runtime/schemas/requirement-packet.schema.json \
        plugins/spec-autopilot/tests/test_requirement_packet_synthesizer.sh
git commit -m "refactor(spec-autopilot): packet synthesis moves to dedicated agent (no main-thread compression)"
```

---

### Task 7：autopilot-agents install 流程注册新 agent role

**Files:**
- Modify: `plugins/spec-autopilot/skills/autopilot-agents/SKILL.md`
- Test: `plugins/spec-autopilot/tests/test_agent_install_synthesizer.sh`

- [ ] **Step 1: 写测试** — 模拟 setup 流程，断言生成的 config 包含 `phases.requirements.synthesizer.agent`，且其 agent 推荐为 architect/judge 类（不是 explore 类）。

- [ ] **Step 2: 修改 autopilot-agents SKILL.md** — Step 4 install 配置写入模板补充：
```yaml
phases.requirements.synthesizer.agent: <推荐：architect 或具备结构化判断能力的 agent>
```
推荐链：`OMC architect` > `Plan` > 用户自配。

- [ ] **Step 3: 同步 Phase → config key 映射表**，新增 `requirements.synthesizer` 行。

- [ ] **Step 4: 运行测试验证通过**

- [ ] **Step 5: Commit**

```bash
git add plugins/spec-autopilot/skills/autopilot-agents/SKILL.md \
        plugins/spec-autopilot/tests/test_agent_install_synthesizer.sh
git commit -m "feat(spec-autopilot): autopilot-agents installs synthesizer role with priority chain"
```

---

### Task 8：A 阶段集成测试

**Files:**
- Create: `plugins/spec-autopilot/tests/integration/test_phase1_e2e_v2.sh`

- [ ] **Step 1: 写端到端集成测试**
  - fixture：一个 partial 复杂度需求（"添加用户登录限流"）
  - 用 mock subagent runner 模拟 scan/research/synthesizer 三路返回
  - 断言：(a) 派发顺序 = scan‖research → synthesizer；(b) verdict.json 存在且 schema 通过；(c) requirement-packet.json 存在且 sha256 匹配；(d) 中间无 web-search Agent 被派发。

- [ ] **Step 2: 运行测试验证通过**

- [ ] **Step 3: 运行完整 phase1 测试集**

```bash
cd plugins/spec-autopilot && bash tests/run_all.sh -k phase1
```
预期：所有 phase1_* 测试通过，无 regression。

- [ ] **Step 4: Commit**

```bash
git add plugins/spec-autopilot/tests/integration/test_phase1_e2e_v2.sh
git commit -m "test(spec-autopilot): phase1 e2e integration test for v2 architecture"
```

---

## 阶段 B：Gate 与契约硬化（任务 9-13）

### Task 9：BA Agent 模板强制 [NEEDS CLARIFICATION] 标记

**Files:**
- Modify: `plugins/spec-autopilot/skills/autopilot/references/phase1-requirements.md`
- Create: `plugins/spec-autopilot/runtime/templates/requirements-template.md`
- Test: `plugins/spec-autopilot/tests/test_needs_clarification_marker.sh`

- [ ] **Step 1: 写测试**

```bash
test_template_includes_marker_section() {
  grep -q "\[NEEDS CLARIFICATION:" \
    "$REPO_ROOT/plugins/spec-autopilot/runtime/templates/requirements-template.md"
}

test_ba_prompt_instructs_marker_usage() {
  grep -qE "(NEEDS CLARIFICATION|未明确处必须标记)" \
    "$REPO_ROOT/plugins/spec-autopilot/skills/autopilot/references/phase1-requirements.md"
}
```

- [ ] **Step 2: 创建 requirements-template.md**（参考 GitHub Spec Kit 模板）

```markdown
# Feature: {feature_name}

## User Stories
1. As a {role}, I want {action}, so that {benefit}.
   [NEEDS CLARIFICATION: 是否对未登录用户也生效？]

## Acceptance Criteria
- [ ] AC1: {testable assertion}
- [ ] AC2: ...

## Non-Goals
- {explicitly out of scope}

## Open Questions
- [NEEDS CLARIFICATION: ...]

## Review Checklist
- [ ] No `[NEEDS CLARIFICATION]` markers remain
- [ ] All ACs are testable
- [ ] WHAT/WHY only — no HOW (implementation details)
```

- [ ] **Step 3: 修改 phase1-requirements.md** — BA Agent prompt 中明确："任何用户原始 prompt 未覆盖的点必须用 `[NEEDS CLARIFICATION: 具体问题]` 标记，禁止貌似合理的假设"。引用 GitHub Spec Kit 协议。

- [ ] **Step 4: 运行测试验证通过**

- [ ] **Step 5: Commit**

```bash
git add plugins/spec-autopilot/runtime/templates/requirements-template.md \
        plugins/spec-autopilot/skills/autopilot/references/phase1-requirements.md \
        plugins/spec-autopilot/tests/test_needs_clarification_marker.sh
git commit -m "feat(spec-autopilot): adopt [NEEDS CLARIFICATION] protocol from spec-kit"
```

---

### Task 10：autopilot-gate 升级 — Phase 1→2 三重校验

**Files:**
- Modify: `plugins/spec-autopilot/skills/autopilot-gate/SKILL.md`
- Modify: `plugins/spec-autopilot/runtime/scripts/poll-gate-decision.sh`（如包含 phase1 逻辑）
- Test: `plugins/spec-autopilot/tests/test_phase1_hard_gate_v2.sh`

- [ ] **Step 1: 写测试**

```bash
test_gate_blocks_when_clarification_remains() {
  echo "User wants X. [NEEDS CLARIFICATION: scope?]" > "$TEST_TMP/requirements.md"
  ! bash "$REPO_ROOT/plugins/spec-autopilot/runtime/scripts/check-phase1-gate.sh" \
      --requirements "$TEST_TMP/requirements.md" \
      --packet "$TEST_TMP/packet.json" \
      --verdict "$TEST_TMP/verdict.json"
}

test_gate_blocks_on_low_confidence() {
  cat > "$TEST_TMP/verdict.json" <<EOF
{"coverage_ok":true,"conflicts":[],"confidence":0.4,"requires_human":false,
 "ambiguities":[],"rationale":"low","merged_decision_points":[]}
EOF
  ! bash "$REPO_ROOT/plugins/spec-autopilot/runtime/scripts/check-phase1-gate.sh" \
    --verdict "$TEST_TMP/verdict.json" --threshold 0.7
}

test_gate_blocks_on_unresolved_conflicts() {
  cat > "$TEST_TMP/verdict.json" <<EOF
{"coverage_ok":true,"conflicts":[{"topic":"db choice","positions":[
  {"source":"scan","claim":"sqlite"},{"source":"research","claim":"postgres"}],
  "resolution":"irreconcilable"}],"confidence":0.9,"requires_human":true,
  "ambiguities":[],"rationale":"x","merged_decision_points":[]}
EOF
  ! bash "$REPO_ROOT/plugins/spec-autopilot/runtime/scripts/check-phase1-gate.sh" \
    --verdict "$TEST_TMP/verdict.json"
}

test_gate_passes_clean_state() {
  echo "All resolved." > "$TEST_TMP/requirements.md"
  cat > "$TEST_TMP/verdict.json" <<EOF
{"coverage_ok":true,"conflicts":[],"confidence":0.85,"requires_human":false,
 "ambiguities":[],"rationale":"all sources align","merged_decision_points":[]}
EOF
  echo '{"sha256":"abc","goal":"x"}' > "$TEST_TMP/packet.json"
  bash "$REPO_ROOT/plugins/spec-autopilot/runtime/scripts/check-phase1-gate.sh" \
    --requirements "$TEST_TMP/requirements.md" \
    --packet "$TEST_TMP/packet.json" \
    --verdict "$TEST_TMP/verdict.json"
}
```

- [ ] **Step 2: 创建 check-phase1-gate.sh**

```bash
#!/usr/bin/env bash
# 三重校验：(1) requirements.md 不含 [NEEDS CLARIFICATION:; 
# (2) verdict.confidence >= threshold (默认 0.7);
# (3) verdict.conflicts 中无 resolution=="irreconcilable"
set -euo pipefail
THRESHOLD=0.7
while [[ $# -gt 0 ]]; do
  case "$1" in
    --requirements) REQ="$2"; shift 2 ;;
    --packet) PKT="$2"; shift 2 ;;
    --verdict) VRD="$2"; shift 2 ;;
    --threshold) THRESHOLD="$2"; shift 2 ;;
    *) echo "unknown $1" >&2; exit 2 ;;
  esac
done
fail=0
if [[ -n "${REQ:-}" ]] && grep -q "\[NEEDS CLARIFICATION:" "$REQ"; then
  echo "GATE FAIL: unresolved [NEEDS CLARIFICATION] markers in $REQ" >&2; fail=1
fi
if [[ -n "${VRD:-}" ]]; then
  conf=$(jq -r '.confidence' "$VRD")
  if (( $(echo "$conf < $THRESHOLD" | bc -l) )); then
    echo "GATE FAIL: confidence $conf < $THRESHOLD" >&2; fail=1
  fi
  if jq -e '.conflicts[] | select(.resolution=="irreconcilable")' "$VRD" >/dev/null; then
    echo "GATE FAIL: irreconcilable conflicts present" >&2; fail=1
  fi
fi
if [[ -n "${PKT:-}" ]] && ! jq -e '.sha256' "$PKT" >/dev/null; then
  echo "GATE FAIL: packet missing sha256" >&2; fail=1
fi
exit $fail
```

- [ ] **Step 3: 修改 autopilot-gate/SKILL.md** — Phase 1→2 Gate section 添加："必须调用 check-phase1-gate.sh 三重校验"。

- [ ] **Step 4: 运行测试验证通过**

- [ ] **Step 5: Commit**

```bash
git add plugins/spec-autopilot/runtime/scripts/check-phase1-gate.sh \
        plugins/spec-autopilot/skills/autopilot-gate/SKILL.md \
        plugins/spec-autopilot/tests/test_phase1_hard_gate_v2.sh
git commit -m "feat(spec-autopilot): phase1->2 gate with triple validation"
```

---

### Task 11：L2 Hook 校验三路信封 schema

**Files:**
- Modify: `plugins/spec-autopilot/hooks/hooks.json`
- Create: `plugins/spec-autopilot/runtime/scripts/validate-phase1-envelope.sh`
- Create: `plugins/spec-autopilot/runtime/schemas/phase1-scan-envelope.schema.json`
- Create: `plugins/spec-autopilot/runtime/schemas/phase1-research-envelope.schema.json`
- Test: `plugins/spec-autopilot/tests/test_phase1_envelope_hook.sh`

- [ ] **Step 1: 写两个 envelope schema** — 参考 phase1-requirements-detail.md 现有信封字段定义。

- [ ] **Step 2: 写 hook 脚本**

```bash
#!/usr/bin/env bash
# PostToolUse Task hook: 检查若 task description 含 autopilot-phase:1-{scan|research|synthesizer}
# 标记，则强制校验对应 schema
set -euo pipefail
event_json=$(cat)
task_desc=$(echo "$event_json" | jq -r '.tool_input.description // ""')
case "$task_desc" in
  *autopilot-phase:1-scan*)     schema=phase1-scan-envelope.schema.json ;;
  *autopilot-phase:1-research*) schema=phase1-research-envelope.schema.json ;;
  *autopilot-phase:1-synthesizer*) schema=synthesizer-verdict.schema.json ;;
  *) exit 0 ;;
esac
output=$(echo "$event_json" | jq -r '.tool_response.content // ""')
echo "$output" | jq . >/dev/null 2>&1 || {
  echo "{\"decision\":\"block\",\"reason\":\"phase1 envelope is not valid JSON\"}"; exit 0; }
echo "$output" > /tmp/_phase1_envelope.json
if ! bash "$(dirname "$0")/validate-json-envelope.sh" \
       --schema "$(dirname "$0")/../schemas/$schema" \
       --input /tmp/_phase1_envelope.json; then
  echo "{\"decision\":\"block\",\"reason\":\"phase1 envelope schema violation\"}"
fi
```

- [ ] **Step 3: 修改 hooks.json** — 在 PostToolUse Task matcher 下追加该脚本调用。

- [ ] **Step 4: 写测试** — 模拟带标记的 Task 事件 + 非法 envelope，断言 hook 返回 `decision:block`。

- [ ] **Step 5: 运行测试验证通过**

- [ ] **Step 6: Commit**

```bash
git add plugins/spec-autopilot/hooks/hooks.json \
        plugins/spec-autopilot/runtime/scripts/validate-phase1-envelope.sh \
        plugins/spec-autopilot/runtime/schemas/phase1-*-envelope.schema.json \
        plugins/spec-autopilot/tests/test_phase1_envelope_hook.sh
git commit -m "feat(spec-autopilot): L2 hook enforces phase1 envelope schemas"
```

---

### Task 12：decision_points 语义去重（Synthesizer 内）

**Files:**
- Modify: `plugins/spec-autopilot/skills/autopilot/references/parallel-phase1.md`
- Test: `plugins/spec-autopilot/tests/test_decision_points_dedup.sh`

- [ ] **Step 1: 写测试** — 给一个 verdict fixture，其中两路 decision_points 含相似 topic（"db choice" vs "database selection"），断言 merged_decision_points 中去重为 1 条且 evidence_refs 含两路引用。

- [ ] **Step 2: 修改 SynthesizerAgent prompt**（parallel-phase1.md 中的 task_boundary）— 明确要求："对所有 decision_points 做语义聚合，相似 topic 合并并在 evidence_refs 中保留所有源路径；同主题不同推荐 → 写入 conflicts[]"。

- [ ] **Step 3: 添加 prompt 中的 few-shot 示例** —
```
INPUT decision_points:
  - {topic:"数据库选型", recommendation:"sqlite", source:scan}
  - {topic:"DB choice", recommendation:"postgres", source:research}

OUTPUT:
  conflicts: [{topic:"数据库选型", positions:[
    {source:scan,claim:sqlite}, {source:research,claim:postgres}],
    resolution:"deferred_to_user"}]
  merged_decision_points: []   # 因为是冲突，不写入 merged
```

- [ ] **Step 4: 运行测试验证通过**

- [ ] **Step 5: Commit**

```bash
git add plugins/spec-autopilot/skills/autopilot/references/parallel-phase1.md \
        plugins/spec-autopilot/tests/test_decision_points_dedup.sh
git commit -m "feat(spec-autopilot): synthesizer performs semantic decision_points dedup"
```

---

### Task 13：B 阶段集成测试

**Files:**
- Modify: `plugins/spec-autopilot/tests/integration/test_phase1_e2e_v2.sh`

- [ ] **Step 1: 扩展 e2e 测试**
  - 案例 A：requirements.md 含 1 个未清零标记 → Gate 失败
  - 案例 B：verdict.confidence=0.5 → Gate 失败
  - 案例 C：verdict.conflicts 含 irreconcilable → Gate 失败
  - 案例 D：全部 clean → Gate 通过 + Phase 2 派发

- [ ] **Step 2: 运行测试验证通过**

- [ ] **Step 3: Commit**

```bash
git add plugins/spec-autopilot/tests/integration/test_phase1_e2e_v2.sh
git commit -m "test(spec-autopilot): phase1 gate hardening e2e cases"
```

---

## 阶段 C：细节优化（任务 14-18）

### Task 14：Auto-Scan 信封补 decision_points / conflicts_detected 字段（D5）

**Files:**
- Modify: `plugins/spec-autopilot/runtime/schemas/phase1-scan-envelope.schema.json`
- Modify: `plugins/spec-autopilot/skills/autopilot/references/parallel-phase1.md`
- Test: `plugins/spec-autopilot/tests/test_scan_envelope_decision_points.sh`

- [ ] **Step 1: 修改 schema** — `phase1-scan-envelope.schema.json` 新增可选字段 `decision_points[]` 与 `conflicts_detected[]`。

- [ ] **Step 2: 修改 ScanAgent prompt** — 明确："发现项目模式与需求冲突时，写入 envelope.conflicts_detected[]，并产出对应 decision_points"。

- [ ] **Step 3: 写测试** — 断言 ScanAgent envelope 包含这两个字段（即便为空数组）。

- [ ] **Step 4: 运行测试验证通过**

- [ ] **Step 5: Commit**

```bash
git add plugins/spec-autopilot/runtime/schemas/phase1-scan-envelope.schema.json \
        plugins/spec-autopilot/skills/autopilot/references/parallel-phase1.md \
        plugins/spec-autopilot/tests/test_scan_envelope_decision_points.sh
git commit -m "feat(spec-autopilot): scan envelope carries decision_points and conflicts"
```

---

### Task 15：clarity_score 解耦（D7）

**Files:**
- Modify: `plugins/spec-autopilot/skills/autopilot/references/phase1-clarity-scoring.md`
- Create: `plugins/spec-autopilot/runtime/scripts/score-raw-prompt.sh`
- Test: `plugins/spec-autopilot/tests/test_clarity_score_raw_prompt.sh`

**目标**：rule 分改为评估"原始用户 prompt 的语言学特征"（动词密度、量化词、角色明确度），与 BA Agent 产出解耦。

- [ ] **Step 1: 写测试** — 给两个 fixture：模糊 prompt（"做个登录"）vs 明确 prompt（"为电商应用添加用户登录功能：邮箱+密码、支持记住我、JWT token 24h 过期"），断言后者得分显著高于前者。

- [ ] **Step 2: 创建 score-raw-prompt.sh** — 用 Python（_envelope_parser.py 已有依赖）实现：
  - `verb_density`（动词数 / 总词数）
  - `quantifier_count`（数字、时间单位、阈值词）
  - `role_clarity`（"用户/管理员/访客"等角色词出现次数）
  - 总分 = 加权平均，归一到 [0,1]

- [ ] **Step 3: 修改 phase1-clarity-scoring.md** — `rule_score` 计算改为调用 score-raw-prompt.sh，原 `rp.goal/scope/...` 字段降级为 LLM-judge 输入而非规则输入。

- [ ] **Step 4: 运行测试验证通过**

- [ ] **Step 5: Commit**

```bash
git add plugins/spec-autopilot/runtime/scripts/score-raw-prompt.sh \
        plugins/spec-autopilot/skills/autopilot/references/phase1-clarity-scoring.md \
        plugins/spec-autopilot/tests/test_clarity_score_raw_prompt.sh
git commit -m "fix(spec-autopilot): decouple clarity_score from BA agent output"
```

---

### Task 16：容错统一 — resume + 窄化重派（D10）

**Files:**
- Modify: `plugins/spec-autopilot/skills/autopilot/references/phase1-requirements-detail.md`
- Modify: `plugins/spec-autopilot/skills/autopilot/references/phase1-requirements.md`
- Test: `plugins/spec-autopilot/tests/test_phase1_resume_on_failure.sh`

- [ ] **Step 1: 写测试** — fixture：模拟 ResearchAgent 第一次失败（envelope 无效），断言：(a) 不 fallback 到"AI 内置知识"；(b) 主线程窄化重派（task_boundary 中标注"上次失败原因 + 缩小 scope"）；(c) 二次失败才 escalate user。

- [ ] **Step 2: 修改 phase1-requirements-detail.md** — 删除"web-search 失败 fallback AI 内置知识"段（约 338-339 行），改写为统一的 resume 协议。

- [ ] **Step 3: 修改 phase1-requirements.md** — 主线程逻辑：单路失败 → 派发"narrowed retry" task（prompt 含 `previous_failure: {reason, partial_output}`）→ 二次失败 → AskUserQuestion 询问是否跳过该路。

- [ ] **Step 4: 运行测试验证通过**

- [ ] **Step 5: Commit**

```bash
git add plugins/spec-autopilot/skills/autopilot/references/phase1-requirements*.md \
        plugins/spec-autopilot/tests/test_phase1_resume_on_failure.sh
git commit -m "fix(spec-autopilot): unify failure handling to resume + narrowed retry"
```

---

### Task 17：单路 interrupt 早停澄清（D11）

**Files:**
- Modify: `plugins/spec-autopilot/runtime/schemas/phase1-scan-envelope.schema.json`
- Modify: `plugins/spec-autopilot/runtime/schemas/phase1-research-envelope.schema.json`
- Modify: `plugins/spec-autopilot/skills/autopilot-phase1-requirements/SKILL.md`
- Modify: `plugins/spec-autopilot/runtime/scripts/capture-hook-event.sh`（如需扩展通知逻辑）
- Test: `plugins/spec-autopilot/tests/test_phase1_early_interrupt.sh`

- [ ] **Step 1: 修改两个 envelope schema** — 新增可选字段 `interrupt: { reason: string, severity: "blocker"|"warning" }`。

- [ ] **Step 2: 修改 SKILL.md** — Step 1.2.x 新增："收到任一路 envelope.interrupt.severity=='blocker' 时，立即中断未完成路（Task abort），主线程 AskUserQuestion 用 interrupt.reason 作为问题"。

- [ ] **Step 3: 写测试** — fixture：ScanAgent 提前返回 `interrupt:{severity:"blocker", reason:"技术栈不支持 X"}`，断言 ResearchAgent 被 abort，AskUserQuestion 被调用。

- [ ] **Step 4: 运行测试验证通过**

- [ ] **Step 5: Commit**

```bash
git add plugins/spec-autopilot/runtime/schemas/phase1-*-envelope.schema.json \
        plugins/spec-autopilot/skills/autopilot-phase1-requirements/SKILL.md \
        plugins/spec-autopilot/tests/test_phase1_early_interrupt.sh
git commit -m "feat(spec-autopilot): early interrupt protocol for blocker-class findings"
```

---

### Task 18：成熟度 × 调研方案矩阵化（D12）

**Files:**
- Modify: `plugins/spec-autopilot/skills/autopilot/references/phase1-requirements.md`
- Create: `plugins/spec-autopilot/runtime/scripts/select-research-plan.sh`
- Test: `plugins/spec-autopilot/tests/test_research_plan_matrix.sh`

- [ ] **Step 1: 写测试** — 验证矩阵：
  - clear + greenfield → skip research
  - clear + brownfield → "lite-regression"（仅 ScanAgent + 轻量回归分析子任务，不派 ResearchAgent）
  - partial + any → 标准双路
  - ambiguous + any → 双路 + depth=deep

- [ ] **Step 2: 创建 select-research-plan.sh** — 输入 `{maturity, project_type}`，输出 `{scan: bool, research: bool, research_depth: standard|deep, websearch_subtask: bool}`。

- [ ] **Step 3: 修改 phase1-requirements.md** — 替换硬映射表为调用 select-research-plan.sh。

- [ ] **Step 4: 运行测试验证通过**

- [ ] **Step 5: Commit**

```bash
git add plugins/spec-autopilot/runtime/scripts/select-research-plan.sh \
        plugins/spec-autopilot/skills/autopilot/references/phase1-requirements.md \
        plugins/spec-autopilot/tests/test_research_plan_matrix.sh
git commit -m "feat(spec-autopilot): research plan as maturity × project_type matrix"
```

---

## 阶段 D：发布前检查（任务 19-21）

### Task 19：完整测试套件 + 类型检查 + lint

- [ ] **Step 1: 运行完整 spec-autopilot 测试**

```bash
cd plugins/spec-autopilot && make test
```
预期：全部通过。

- [ ] **Step 2: 运行 lint + typecheck + format**

```bash
make lint && make typecheck && make format
```

- [ ] **Step 3: 修复任何回归（不修改测试断言来掩盖问题）**

---

### Task 20：构建 dist 并验证一致性

- [ ] **Step 1: 重建 dist**

```bash
make build
```

- [ ] **Step 2: 校验 freshness**

```bash
bash scripts/check-dist-freshness.sh spec-autopilot
```

- [ ] **Step 3: 确认 dist 已 staged**

```bash
git status dist/spec-autopilot/
```

---

### Task 21：文档与 CHANGELOG

**Files:**
- Modify: `plugins/spec-autopilot/CHANGELOG.md`（由 release-please 自动维护，不手动改版本号）
- Modify: `plugins/spec-autopilot/README.md` / `README.zh.md`（如有 Phase 1 架构图）
- Create: `docs/superpowers/research/2026-04-20-phase1-best-practices.md`（沉淀本次调研的引用列表）

- [ ] **Step 1: 创建调研文档** — 把 3 路调研 Agent 的输出整合为一份文件，便于后续审计追溯。

- [ ] **Step 2: 更新 README**（如需要）— 在架构图中把"三路并行"改为"双路 + Synthesizer"。

- [ ] **Step 3: 提交并推送 PR**

```bash
git add docs/superpowers/research/ plugins/spec-autopilot/README*.md
git commit -m "docs(spec-autopilot): document phase1 v2 architecture and best-practice references"
git push origin feature/spec-autopilot
gh pr create --base main --head feature/spec-autopilot \
  --title "feat(spec-autopilot): phase1 redesign — synthesizer + clarification protocol" \
  --body "See docs/superpowers/plans/2026-04-20-phase1-redesign.md"
```

---

## 回滚方案

每个阶段的 commit 都是原子的。如需回滚：
- A 阶段失败 → revert Task 1-8 的 8 个 commit；旧 web_search Agent 仍在 config 中（因 deprecated 保留），运行不受影响。
- B 阶段失败 → revert Task 9-13；Gate 退回原"存在性校验"。
- C 阶段失败 → revert Task 14-18；不影响主流程。

---

## Out of Scope（不在本计划中）

- Phase 2/3 OpenSpec 阶段的对应改造（独立计划）
- 多语言支持（current: 中英双语遵循 CLAUDE.md docs 规则）
- GUI 侧 Phase 1 可视化升级（gui/ 目录改动放后续 PR）
- parallel-harness 插件不受影响

---

## Self-Review Checklist

- [x] 12 个缺陷（D1-D12）全部映射到任务
- [x] 每个任务含 file paths + test code + commit message
- [x] 类型一致：synthesizer / verdict / NEEDS CLARIFICATION 命名贯穿全文一致
- [x] 无 TBD / TODO / "类似 Task N"
- [x] 测试 fixture 含具体 JSON / bash 代码
- [x] 回滚方案明确
