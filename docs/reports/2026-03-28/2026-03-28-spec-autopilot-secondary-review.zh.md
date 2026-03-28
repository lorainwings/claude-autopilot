# spec-autopilot 二次评审：对 Codex 报告的全量核实与再评估

日期: 2026-03-28
评审对象:
- `docs/reports/2026-03-28-spec-autopilot-holistic-review.zh.md`（Codex 主报告）
- `docs/reports/2026-03-28-spec-autopilot-evidence-appendix.zh.md`（Codex 证据附录）
- `docs/plans/2026-03-28-spec-autopilot-stability-remediation-master-plan.zh.md`（Codex 修复总方案）

方法:
- 对 Codex 报告中每一条"已证实"声称进行源码级交叉验证
- 对每一条引用的行号和文件进行精确复核
- 对修复方案的可行性和必要性进行独立评估
- 基于插件**原始产品目标**（增强而非简化）给出补充建议

## 一、总评

### 对 Codex 报告的整体评价

Codex 报告展现了较高的调查深度，对测试基线执行、脚本行为分析、GUI 组件审查均有实质性工作。但存在以下系统性偏差：

1. **过度渲染问题严重性**：将已废弃脚本（DEPRECATED, 未注册到 hooks.json）中的代码当作生产行为声称"背景 agent bypass 存在"
2. **遗漏关键缓解机制**：未提及 `relaxed` 预设可完全消除阶段间确认、未提及 `rebuild-anchor.sh` 的存在
3. **将设计决策误判为矛盾**：把 Phase 1 子任务有意不带 `autopilot-phase` 标记的分层设计误读为"协议自相矛盾"
4. **修复方案过度工程化**：提出的四层模型、十类工件对象远超当前问题的实际修复需求
5. **忽视已有但未集成的代码**：`OrchestrationPanel.tsx` 已实现了报告建议的大部分编排功能，但作为死代码存在

### 我的独立评价

| 维度 | Codex 评分 | 我的评分 | 差异原因 |
|------|-----------|---------|---------|
| 工程完整度 | 高 | **高** | 一致 |
| 产品闭环一致性 | 中 | **中上** | Codex 将废弃代码的遗留问题算入了生产闭环评分 |
| 上下文治理成熟度 | 中偏低 | **中** | 三层保存架构（无截断持久化→有损压缩前保存→有损注入）被 Codex 扁平化描述了 |
| 崩溃恢复可靠性 | 中上 | **中上** | 一致 |
| 测试真实性 | 中 | **中上** | Codex 夸大了"文档即测试"比例（实际纯文档测试仅占 3-5%） |
| 商业化准备度 | 中偏低 | **中** | 核心闭环问题数量比 Codex 声称的少 |
| 过度设计程度 | 中到高 | **中** | 复杂度大部分有对应的产品场景支撑 |

## 二、逐项核实：Codex 声称的问题是否真实存在

### 2.1 Phase 1 协议"自相矛盾" ⚠️ 部分属实

**Codex 声称**：Phase 1 存在协议级自相矛盾，主协议说"主线程不读全文"，并行协议说"主线程合并 research 文件内容"。

**核实结果**：

| 矛盾点 | 是否存在 | 严重程度 |
|--------|---------|---------|
| `parallel-phase1.md` 第 81 行 vs 第 43 行 | **是** — 同文件内前后不一致 | **低** |
| SKILL.md 主文件 vs parallel-phase1.md | **否** — 主文件一致性完好 | — |
| Phase 1 子任务无标记导致 Hook 失效 | **否** — 有意设���，多处文档标注"设计预期" | — |

**精确证据**：
- `parallel-phase1.md:43` 明确说"主线程仅消费信封，不 Read 产出文件"
- `parallel-phase1.md:81` 却说"主线程合并 research-findings.md 和 web-research-findings.md 的内容"
- 但 `SKILL.md:146` 说"主线程不读取全文"，`phase1-requirements-detail.md:585` 的 BA prompt 模板让 BA 子 Agent 自行 Read
- `autopilot-dispatch/SKILL.md:262` 明确标注"此 Task 不含 autopilot-phase 标记 → 不受 Hook 门禁校验（设计预期）"
- `validate-decision-format.sh:11-14` 注释完整解释了为什么 Phase 1 不走 Hook 门禁

**独立判定**：第 81 行是 v3.3.0 之前的遗留描述，未被清理。从多文件交叉验证看，整体协议设计**自洽**。Codex 将一个文档清理遗漏升级为"当前架构最不稳定的区域"是过度渲染。

**但真正的问题是**：虽然协议设计意图是一致的，但 AI Agent 在执行时是否真的遵循了主文件优先级？这取决于提示词的实际注入顺序和权重，是一个运行时风险而非协议层矛盾。

**建议**：
1. 清理 `parallel-phase1.md:81` 的遗留描述 → **必须做**
2. 为 Phase 1 子任务增加轻量化标记（如 `<!-- autopilot-subtask:research -->`），使其可被统一验证器识别但不触发 phase 门禁 → **建议做**
3. 不需要 Codex 方案中的完整"双层协议"重构 → **过度**

### 2.2 自动推进与用户确认 ✅ 属实但缓解机制未被提及

**Codex 声称**：`after_phase_1: true` 默认配置与"需求评审后自动完成"的产品需求直接冲突。

**核实结果**：

| 声称 | 是否属实 | 补充 |
|------|---------|------|
| `after_phase_1` 默认为 true | **是** | `README.zh.md:248-252` |
| 阶段间确认与自动化目标冲突 | **是** | 但 Codex 遗漏了 `relaxed` 预设 |
| Phase 7 归档强制 AskUserQuestion | **是** | CLAUDE.md 铁律，设计意图 |

**Codex 遗漏的关键信息**：

`autopilot-init/SKILL.md:55-90` 已定义三个预设级别：
- **strict**: `after_phase_1: true, after_phase_3: true`（最多确认点）
- **moderate**: `after_phase_1: true, after_phase_3: false`（默认）
- **relaxed**: `after_phase_1: false, after_phase_3: false`（零确认点，全自动）

使用 `relaxed` 预设后，理想路径上仅 Phase 1 决策循环和 Phase 7 归档确认会中断用户。Phase 1 的 AskUserQuestion 是需求澄清的核心交互，不可消除。

**独立判定**：问题存在但比 Codex 描述的严重程度低。不需要新增 `confirmation_policy` 或 `orchestration.auto_continue_after_phase1` — 只需将默认预设从 `moderate` 改为 `relaxed` 即可。

**建议**：
1. 将默认预设改为 `relaxed` → **必须做**
2. Phase 7 归档确认保留（这是安全阀，不是冗余设计） → **保留**
3. 不需要 Codex 方案中的 `confirmation_policy: manual | guarded_auto | full_auto` 三态模型 → **过度**

### 2.3 上下文压缩恢复 ✅ 属实，但架构比 Codex 描述的更完善

**Codex 声称**：恢复是"摘要回灌"，不是"完整恢复"。

**核实结果**：

| 声称 | 是否属实 | 精确验证 |
|------|---------|---------|
| 每个 snapshot 截断到 1000 字符 | **是** | `save-state-before-compact.sh:171` `content[:1000]` |
| reinject 总 snapshot 限制 4000 字符 | **是** | `reinject-state-after-compact.sh:69` `MAX_TOTAL_CHARS=4000` |
| 恢复依赖自然语言再理解 | **部分是** | 有结构化元素（sed 提取关键字段），但主体是 Markdown 文本 |

**Codex 遗漏的架构层次**：

实际是一个五层架构，Codex 将其扁平化了：

| 层次 | 脚本 | 信息保真度 |
|------|------|-----------|
| L1 持久化 | `save-phase-context.sh` | **完整**（无截断，每 phase 结束时写入） |
| L2 压缩前保存 | `save-state-before-compact.sh` | 有损（1000 字/phase, 80 字 summary, 60 字 task） |
| L3 压缩后注入 | `reinject-state-after-compact.sh` | 进一步有损（4000 字总预算） + 确定性恢复指令 |
| L4 新会话扫描 | `scan-checkpoints-on-start.sh` | 最简（60 字 summary，无 snapshot） |
| L5 决策引擎 | `recovery-decision.sh` | 结构化 JSON，含 auto_continue_eligible 判定 |

**关键发现**：L1 层的原始 snapshot 文件**没有长度限制**。截断只发生在 L2/L3 层嵌入和注入时。这意味着 phase context 的完整信息始终保留在磁盘上，只是注入 AI 上下文时被压缩了。

**reinject 的确定性恢复指令**（`reinject-state-after-compact.sh:103-133`）通过 sed 提取 NEXT_PHASE、EXEC_MODE、CHANGE_NAME、IN_PROGRESS_PHASE、IN_PROGRESS_SUBSTEP，生成具体操作步骤。这不是纯"自然语言猜测"。

**独立判定**：Codex 的核心论点成立（恢复不是结构化状态重放），但严重性被夸大了。当前设计在实用性上是足够的，改进方向应该是增强结构化元素而非推翻现有架构。

**建议**：
1. 在 L2 层增加机器可读的 JSON 状态块（requirement packet hash、gate frontier、artifact manifest），与现有 Markdown 并存 → **建议做**
2. reinject 时先注入 JSON 状态块，再注入 Markdown 摘要 → **建议做**
3. 增加恢复后校验步骤：比对恢复前后的 checkpoint 数量、decision points 数量 → **建议做**
4. 不需要 Codex 方案中完整的 `context-ledger.json` + `recovery-state.json` 双工件体系 → **可以合并为单一 `state-snapshot.json`**

### 2.4 背景 Agent L2 校验 ❌ Codex 声称严重失实

**Codex 声称**：背景 agent bypass 真实存在，多个脚本对 background agent 直接 bypass。

**核实结果**：

| 声称 | 是否属实 | 关键证据 |
|------|---------|---------|
| `validate-json-envelope.sh` bypass | **仅存在于废弃代码** | 文件第 2 行标注 DEPRECATED，未注册到 hooks.json |
| `anti-rationalization-check.sh` bypass | **仅存在于废弃代码** | 文件第 1-7 行标注 DEPRECATED |
| `code-constraint-check.sh` bypass | **仅存在于废弃代码** | 文件第 2 行标注 DEPRECATED |
| `test_background_agent_bypass.sh` 把 bypass 当预期 | **测试的是废弃脚本** | 该测试验证遗留兼容性，不代表生产行为 |
| CLAUDE.md 第 59 行声称与实际冲突 | **不冲突** | 生产代码 `post-task-validator.sh:22-25` 已移除 bypass |

**精确证据**：

`hooks.json` 中 PostToolUse(Task) **仅注册了一个验证脚本**：
```
"command": "bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/post-task-validator.sh"
```

`post-task-validator.sh:22-25` 的注释明确记录了 v5.1 修复：
```bash
# --- v5.1 FIX: Background agents must undergo validation ---
# Previously: `is_background_agent && exit 0` — completely bypassed all validation.
# Now: Background tasks are validated (JSON envelope + anti-rationalization) when they
# complete, since PostToolUse fires after the agent produces output.
```

代码中**没有** `is_background_agent && exit 0`。`_post_task_validator.py` 全文无任何 `background`/`run_in_background` 跳过逻辑。

`check-predecessor-checkpoint.sh:49-58`（PreToolUse Hook）对背景 agent 也**没有 bypass**，只设置了 `IS_BACKGROUND=true` 标志用于后续日志区分。

**独立判定**：这是 Codex 报告中**最严重的误判**。将废弃代码（明确标注 DEPRECATED、未注册到 hooks.json）中的逻辑当作生产行为来报告，严重夸大了问题。

**建议**：
1. 清理废弃脚本文件或移动到 `_deprecated/` 目录 → **建议做**（减少误判风险）
2. `test_background_agent_bypass.sh` 重命名或添加注释说明测试目标是废弃脚本兼容性 → **建议做**
3. 不需要 Codex 方案中任何关于"背景 agent 闭环修复"的工作 → **无需修复，已在 v5.1 完成**

### 2.5 Phase 6.5 代码审查只是 advisory ✅ 属实，但这是有意的设计

**Codex 声称**：Phase 6.5 不是独立硬门禁，只是 advisory，这降低了 review 质量保障。

**核实结果**：

Phase 6.5 确实是 Advisory Gate，三个层面验证：
1. `autopilot-gate/SKILL.md:203` 明确标注 `[Advisory Gate — 不阻断 Phase 7]`
2. Phase 6.5 prompt 使用 `<!-- 代码审查 -->` 而非 `<!-- autopilot-phase:N -->`，所有 L2 Hook 跳过
3. Phase 7 收集 6.5 结果时，blocked 状态仅触发 AskUserQuestion 用户确认

**但这是有意设计**：
- `autopilot-gate/SKILL.md:215-222` 明确解释了 Advisory Gate 语义
- `block_on_critical` 配置项允许在有 critical findings 时要求用户显式确认（忽略/修复/暂不归档）
- Phase 6 和 Phase 6.5 是**并行执行**的（v3.2.2 三路并行），它们之间没有依赖关系

**独立判定**：这是一个合理的设计权衡。如果把 review 变成硬门禁，在 AI 生成 review 本身可能不准确的情况下，反而会创造大量误阻断。当前的 `block_on_critical` 软门禁 + 用户确认是实用的折中。

**建议**：
1. 增强 Phase 6.5 的 review 结构化输出（severity/evidence/blocking 字段），使 `block_on_critical` 更精确 → **建议做**
2. 将 review findings 关联到具体的代码 diff 和 test coverage，提升 review 的证据链 → **建议做**
3. 不建议将 Phase 6.5 变成完整的硬门禁 → **当前 advisory + block_on_critical 设计合理**

### 2.6 测试"文档即测试"与 Hack Reward ⚠️ 部分属实，但比例被严重夸大

**Codex 声称**："一部分测试直接 grep SKILL.md / 文档，而不是验证真实运行时行为"，存在"Hack Reward 风险"。

**核实结果**：

| 类别 | 文件数 | 断言数 | 占比 |
|------|-------|-------|------|
| A 类：端到端行为测试 | ~56 | ~500+ | **~80%** |
| B 类：源码静态检查 | ~9 | ~28 | ~4% |
| C 类：纯文档/文件检查 | **4** | ~17 | **~3%** |
| D 类：语法检查 | 1 | — | — |
| E 类：hooks.json 验证 | 1 | — | — |
| 混合类 | ~6 | ~89 | ~13% |

**100% 纯文档测试的文件**仅 4 个：
- `test_skill_lockfile_path.sh`
- `test_template_mapping.sh`
- `test_reference_files.sh`
- `test_references_dir.sh`

**Codex 引用的两个例子核实**：
- `test_fixup_commit.sh`：**2 个文档断言 + 3 个行为断言 = 40% 文档测试**。Codex 说"直接 grep SKILL.md"只描述了前 40%，后 60% 创建了真实 git 仓库做行为验证
- `test_search_policy.sh`：**13 个文档断言 + 13 个行为断言 = 50% 文档测试**。但后半段的行为断言测试了自行实现的模拟器而非生产代码，存在自证合格的风险

**独立判定**：Codex 声称"测试真实性：中"过于笼统。测试体系的主体（80% 断言）是货真价实的端到端行为测试，使用 `mktemp -d` 隔离、管道执行生产脚本、验证退出码和输出。真正的问题不是"文档即测试"的比例，而是：
1. `test_search_policy.sh` 的自实现模拟器模式（测试自己写的函数，不是生产代码）
2. 缺少产品级端到端仿真测试（三模式全流程自动贯通测试不存在）

**建议**：
1. 为 C 类纯文档测试添加分类标签，在 `run_all.sh` 中区分 `doc-compliance` 和 `behavioral` → **建议做**
2. 增加三模式全流程黑盒仿真测试（给定标准输入包，验证完整 phase 序列、artifact 产出、gate 通过） → **必须做**
3. 将 `test_search_policy.sh` 的模拟器替换为对生产脚本的实际调用 → **建议做**

### 2.7 fixup 完整性检查 ✅ 属实

**Codex 声称**：fixup 完整性检查只是 warning，不阻断。

**核实结果**：确认属实。`autopilot-phase7/SKILL.md:142` 明确写道"输出警告（不阻断）"。

但 Codex 遗漏了 `rebuild-anchor.sh` 的存在：
- `autopilot-phase7/SKILL.md:152-157`：anchor 无效时**先尝试 rebuild-anchor.sh 重建**
- 重建成功则继续 autosquash
- 重建失败才 AskUserQuestion 让用户选择"跳过/中止"
- 这优于 Codex 描述的"anchor 无效直接跳过"

**但 rebuild-anchor.sh 存在一个微妙问题**：新建的 anchor commit message 是 `autopilot: anchor (recovery)`，而原始 fixup commits 引用的是 `fixup! autopilot: start <name>`。`git rebase --autosquash` 依赖 commit message 匹配，新旧 message 不同会导致 autosquash 静默失败。

**建议**：
1. fixup 完整性检查从 warning 升级为 soft-block（AskUserQuestion 确认后可继续） → **必须做**
2. `rebuild-anchor.sh` 重建时使用原始 anchor 的 commit message 格式 → **必须做**
3. autosquash 失败后的归档流程增加显式警告和确认 → **建议做**

### 2.8 主窗口信息架构 ✅ 属实，且存在死代码

**Codex 声称**：主窗口信息优先级不合理，缺少编排信息，冗余调试信息。

**核实结果**：

信息重复确认：
- **mode**：Header(`App.tsx:160-164`) 和 PhaseTimeline 底部(`PhaseTimeline.tsx:122`) 代码完全相同
- **总耗时**：PhaseTimeline 底部(`107-108`) 和 TelemetryDashboard Card 1(`135-138`) 重复
- **门禁统计**：PhaseTimeline 底部、TelemetryDashboard Card 1、TelemetryDashboard Card 3 **三处重复**

缺失信息确认：
- 当前目标/需求摘要：**确实缺失**
- Gate frontier（下一个待通过 gate）：**确实缺失**
- 恢复来源：store 有 `recoverySource` 字段但 **UI 未展示**

**重大发现**：`OrchestrationPanel.tsx` 存在（158 行），包含了 Codex 建议的大部分编排信息：
- 当前 Phase + 名称（大字号展示）
- Gate 状态/阻塞原因
- 决策状态机（DecisionBadge）
- 活跃 Agent 数量
- 恢复来源（"崩溃恢复" / "全新启动"）

**但这个组件是死代码**——App.tsx 的 import 列表中完全没有引用它。注释标注为 "v5.2 编排控制面 — 修复 Codex P1-6"。

另外，store 中 `decisionLifecycle` 和 `recoverySource` 字段有类型定义和初始值，但 `addEvents` 中**没有写入逻辑**，运行时始终为 null。

**建议**：
1. 将 `OrchestrationPanel.tsx` 集成到 App.tsx 主布局中 → **必须做**
2. 在 `addEvents` 中补充 `decisionLifecycle` 和 `recoverySource` 的事件处理逻辑 → **必须做**
3. 去重 mode/总耗时/门禁统计的多处展示 → **建议做**
4. 将 cwd/transcript_path 降级到 LogWorkbench 中 → **建议做**

### 2.9 Agent 优先级管理 ✅ 属实

**Codex 声称**：rules-scanner 只扫描 `.claude/rules/` 和 `CLAUDE.md`，不扫描 `.claude/agents`；agent dispatch 没有优先级校验。

**核实结果**：

- `rules-scanner.sh:13-14` 确认扫描范围仅为 `.claude/rules` 和 `CLAUDE.md`
- `auto-emit-agent-dispatch.sh` 全文搜索 "priority"/"优先级" 结果为零匹配
- 脚本注释（第 5 行）明确标注 "never denies, purely observational"
- store 的 `AgentInfo` 接口没有 priority/queue_position/dependency 等调度字段

**独立判定**：Codex 此处声称完全属实。但需要评估"agent 优先级管理"在当前产品阶段的必要性。

**建议**：
1. `rules-scanner.sh` 扩展扫描 `.claude/agents/` 目录 → **必须做**
2. 在 dispatch 事件中记录 agent 选择理由（为什么选这个 agent 而非其他） → **建议做**
3. 暂不引入完整的 `agent-policy.json` 优先级校验体系（当前阶段 agent 种类有限，不需要） → **不急**

### 2.10 OpenSpec FF 跳过门禁风险 ❌ Codex 方案不准确

**Codex 方案声称**：需要显式定义 `openspec ff` 的前置条件和审计要求，防止 FF 越过门禁。

**核实结果**：

FF（Fast-Forward）是 Phase 3 子 Agent 一次性生成 proposal/design/specs/tasks 所有制品的操作。它**受三层门禁完整保护**：

1. **L2 Hook 保护**：`check-predecessor-checkpoint.sh:261-265` 对 Phase 3 在非 full 模式下硬阻断
2. **Predecessor 检查**：第 268-275 行要求 Phase 2 checkpoint 必须存在且 status 为 ok/warning
3. **Phase 4 门禁验证 Phase 3 产出**

FF 不是一个"跳过机制"，而是 Phase 3 的加速执行路径。它不绕过任何 gate。

**独立判定**：Codex 方案中关于 OpenSpec FF 的异常控制建议（4.6 节）大部分是解决不存在的问题。FF 在当前架构中已经安全。

## 三、Codex 遗漏的真实问题

### 3.1 OrchestrationPanel.tsx 死代码问题

**严重程度：高**

OrchestrationPanel.tsx 是一个 158 行的完整组件，标注为 "v5.2 编排控制面"，但从未被 App.tsx 引用。这意味着：
1. 开发投入被浪费
2. 用户看不到编排信息
3. store 中对应的字段（`decisionLifecycle`、`recoverySource`）也从未被写入

Codex 报告花大量篇幅建议"主窗口改为 orchestration first"，却未发现这个组件已经存在。

### 3.2 rebuild-anchor.sh 的 commit message 不匹配

**严重程度：中**

`rebuild-anchor.sh:30` 创建的新 anchor commit message 是 `autopilot: anchor (recovery)`，而原始 anchor message 格式是 `autopilot: start <name>`。fixup commits 的前缀是 `fixup! autopilot: start <name>`。`git rebase --autosquash` 通过 commit message 匹配进行 squash，message 不同会导致 autosquash **静默失效**。

### 3.3 Phase 0 与 Phase 7 文档不一致

**严重程度：低**

`autopilot-phase0/SKILL.md:245` 写着"anchor_sha 无效则跳过 autosquash 并警告用户"，但 `autopilot-phase7/SKILL.md:152-157` 的实际流程是"先重建、重建失败再由用户选择"。这是文档更新遗漏。

### 3.4 store addEvents 中缺失的字段写入

**严重程度：中**

store 声明了以下字段但 addEvents 中没有写入逻辑：
- `decisionLifecycle`（第 100-106 行声明，第 637 行仅在 reset 时清空）
- `recoverySource`（第 124 行声明，从未写入）

这意味着即使 OrchestrationPanel 被集成，这些字段也始终为 null。

### 3.5 save-state-before-compact.sh 未保存 checkpoint 的完整 JSON

**严重程度：中**

压缩前保存只提取 checkpoint 的 `status` 和 `summary`（截断到 80 字符），丢弃了 `artifacts`、`details`、`test_results` 等字段。虽然原始 checkpoint JSON 文件在磁盘上仍然存在，但如果 AI 上下文中丢失了这些信息的指针，恢复后可能不知道去哪里找这些文件。

### 3.6 test_background_agent_bypass.sh 测试目标不清晰

**严重程度：低**

该测试验证的是 DEPRECATED 脚本的行为，但测试名称暗示这是生产行为的测试。这导致了 Codex 的误判（将测试预期等同于生产行为）。

## 四、对 Codex 修复方案的评估

### 4.1 方案合理但需要裁减的部分

| Codex 方案 | 评估 | 建议 |
|-----------|------|------|
| Phase 1 拆成 1A/1B/1C/1D 四步 | 结构合理 | **可采纳**，但不需要引入新的 schema 体系 |
| 新增 `requirement-packet.json` | 有价值 | **采纳**，作为 Phase 1 最终产出的单一事实源 |
| 新增 `context-ledger.json` + `recovery-state.json` | 过度 | **合并为单一 `state-snapshot.json`** |
| 新增 `agent-policy.json` | 当前阶段过度 | **暂不引入**，优先扩展 rules-scanner 扫描范围 |
| 新增 `archive-readiness.json` | 有价值 | **采纳**，用于 fixup/review/anchor 状态的结构化校验 |
| Phase 6.5 升级为硬门禁 | 不建议 | **保留 advisory + block_on_critical**，增强 findings 结构化 |
| `confirmation_policy` 三态模型 | 过度 | **不需要**，现有 relaxed/moderate/strict 预设已够用 |
| 四层模型（Control/Artifact/Execution/Observation） | 架构描述有价值 | **作为文档参考**，不需要全量落地为代码 |

### 4.2 方案正确且应全量采纳的部分

| Codex 方案 | 理由 |
|-----------|------|
| fixup 完整性检查从 warning 改为阻断 | 当前 fail-open 违反产品承诺 |
| 主窗口改为 orchestration first | 编排信息缺失已被验证 |
| 测试体系区分 doc-compliance 和 behavioral | 防止 Hack Reward |
| Phase 1 子 agent 不允许主线程代写产出 | 清理 parallel-phase1.md:81 遗留描述 |
| 恢复增加结构化状态保存 | 当前纯 Markdown 恢复确实有信息丢失风险 |

### 4.3 方案错误或不需要的部分

| Codex 方案 | 原因 |
|-----------|------|
| 修复"背景 agent bypass" | **不存在的问题**，v5.1 已修复，废弃脚本未注册 |
| OpenSpec FF 异常控制 | **FF 已受完整门禁保护**，不存在越权风险 |
| 取消旧脚本对 background task 的默认 bypass | **已在 v5.1 完成**，无需再做 |

## 五、增强建议（基于原始产品目标）

以下建议以插件原始产品目标为核心，不做任何简化。

### 5.1 结构化恢复增强

在现有三层保存架构基础上，增加一个 JSON 状态块：

```json
// state-snapshot.json（每次 compact 前生成）
{
  "schema_version": 2,
  "requirement_packet_hash": "<sha256>",
  "gate_frontier": { "last_passed": 5, "next_pending": 6 },
  "checkpoint_manifest": [
    { "phase": 1, "status": "ok", "artifact_count": 3 },
    { "phase": 5, "status": "ok", "artifact_count": 7 }
  ],
  "decision_points_count": 4,
  "open_questions_count": 0,
  "fixup_count": 3,
  "anchor_sha": "abc123",
  "exec_mode": "full",
  "active_tasks": [
    { "id": "task-3", "status": "in_progress", "substep": "GREEN" }
  ]
}
```

reinject 时先注入此 JSON 摘要，再注入 Markdown 上下文。恢复后比对 `requirement_packet_hash` 和 `decision_points_count` 确保一致性。

### 5.2 Phase 1 需求包标准化

引入 `requirement-packet.json` 作为 Phase 1 的唯一输出：

```json
{
  "goal": "用户目标摘要",
  "scope": ["范围项1", "范围项2"],
  "non_goals": ["排除项"],
  "decisions": [
    { "topic": "...", "decision": "...", "source": "user_confirmed|repo_evidence|inference" }
  ],
  "open_questions": [],
  "acceptance_criteria": ["验收标准1"],
  "hash": "<canonical_hash>"
}
```

后续所有 phase 只读这个 packet，不再反复读散落的调研文档。

### 5.3 Phase 6.5 Review 增强（不升级为硬门禁）

保持 advisory gate 设计，但增强 review findings 的结构化：

```json
{
  "findings": [
    {
      "severity": "critical|high|medium|low",
      "category": "security|performance|correctness|style",
      "file": "path/to/file.ts",
      "line_range": [10, 25],
      "evidence": "具体问题描述",
      "suggestion": "建议修复方式",
      "blocking": true
    }
  ],
  "summary": { "critical": 0, "high": 1, "medium": 3, "low": 5 }
}
```

`block_on_critical` 触发时，将具体的 critical findings 展示给用户，而非只说"有 critical findings"。

### 5.4 归档闭环增强

引入 `archive-readiness.json`：

```json
{
  "checkpoint_count": 7,
  "fixup_count": 7,
  "fixup_complete": true,
  "anchor_valid": true,
  "review_gate": "passed|blocked|advisory",
  "blocking_findings": [],
  "worktree_clean": true,
  "ready": true
}
```

Phase 7 Step 4b 之前先生成此文件。`fixup_complete: false` 时阻断归档（而非只 warning）。

### 5.5 GUI 编排面板激活

1. 将 `OrchestrationPanel.tsx` 集成到 App.tsx 主布局
2. 在 server 事件模型中增加 `recovery_source`、`decision_lifecycle` 事件类型
3. 在 store 的 `addEvents` 中处理这些事件
4. 在 OrchestrationPanel 中展示 requirement-packet 摘要（来自 Phase 1 产出）

### 5.6 测试增强

新增以下黑盒测试：

1. **三模式自动贯通测试**：给定标准输入包，验证 full/lite/minimal 各自的 phase 序列、artifact 产出、gate 通过是否符合预期
2. **compact/restore hash 一致性测试**：压缩前后 `state-snapshot.json` 的关键字段比对
3. **fixup fail-closed 测试**：`FIXUP_COUNT < CHECKPOINT_COUNT` 时验证 Phase 7 被阻断
4. **Phase 1 上下文隔离测试**：验证调研 agent 结束后主线程只消费 JSON facts
5. **rebuild-anchor commit message 匹配测试**：验证重建后的 anchor 与 fixup commits 的 message 前缀一致

## 六、最终结论

### Codex 报告的价值

Codex 报告的核心贡献在于：
1. 准确识别了 fixup 完整性检查的 fail-open 问题
2. 准确识别了上下文恢复的有损性
3. 准确识别了 GUI 信息架构的问题
4. 准确识别了 agent 优先级管理的缺失
5. 提出了测试分层的有价值思路

### Codex 报告的偏差

1. **将废弃代码当作生产行为**（背景 agent bypass）→ 最严重的误判
2. **将设计决策误判为矛盾**（Phase 1 子任务无标记）→ 过度渲染
3. **遗漏关键缓解机制**（relaxed 预设、rebuild-anchor.sh、OrchestrationPanel.tsx）→ 调查不够深入
4. **夸大测试问题比例**（纯文档测试仅 3-5%，非 Codex 暗示的大比例）→ 结论偏颇
5. **修复方案过度工程化**（四层模型、十类工件）→ 超出实际需求

### Codex 修复方案的裁定

| 方案域 | 采纳 | 调整 | 拒绝 |
|--------|------|------|------|
| Phase 1 需求包标准化 | ✅ | 不需要完整的四步拆分 | — |
| 自动推进配置 | ✅ | 改默认预设即可，不需要新三态模型 | — |
| 结构化恢复 | ✅ | 合并为单一 state-snapshot.json | 不需要双工件体系 |
| fixup fail-closed | ✅ | — | — |
| GUI 编排面板 | ✅ | 激活已有死代码即可 | — |
| 测试分层 | ✅ | — | — |
| 背景 agent 修复 | — | — | ❌ 不存在的问题 |
| OpenSpec FF 控制 | — | — | ❌ 已有完整保护 |
| agent-policy.json | — | 暂缓 | — |
| Phase 6.5 硬门禁 | — | — | ❌ advisory 设计合理 |

### 真正需要做的事（按优先级）

**P0 — 必须立即修复**：
1. 将默认预设从 `moderate` 改为 `relaxed`
2. fixup 完整性检查从 warning 升级为 soft-block
3. 清理 `parallel-phase1.md:81` 遗留描述
4. `rebuild-anchor.sh` 使用原始 anchor 的 commit message 格式
5. 激活 `OrchestrationPanel.tsx` 并补充 store 事件处理

**P1 — 下一阶段实施**：
1. 引入 `requirement-packet.json` 作为 Phase 1 单一事实源
2. 引入 `state-snapshot.json` 增强结构化恢复
3. 引入 `archive-readiness.json` 增强归档校验
4. 增强 Phase 6.5 review findings 的结构化输出
5. `rules-scanner.sh` 扩展扫描 `.claude/agents/`
6. 新增三模式全流程黑盒仿真测试

**P2 — 持续改进**：
1. 清理废弃脚本到 `_deprecated/` 目录
2. 测试体系标签化（doc-compliance vs behavioral）
3. 更新 Phase 0 SKILL.md 第 245 行与 Phase 7 对齐
4. store `addEvents` 补充 `decisionLifecycle` 和 `recoverySource` 写入
5. `test_background_agent_bypass.sh` 重命名或添加注释
