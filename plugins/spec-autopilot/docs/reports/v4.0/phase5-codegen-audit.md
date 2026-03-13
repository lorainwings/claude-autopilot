# Phase 5 代码生成质量与规约遵从度评审报告

> **评审日期**: 2026-03-13
> **评审版本**: v4.0.0-wave4 (commit 08d346f)
> **评审范围**: spec-autopilot 插件 Phase 5（代码实现阶段）的代码生成机制
> **评审员**: Agent 3 — Phase 5 代码生成质量与规约遵从度评审员

---

## 1. 执行摘要

Phase 5 是 spec-autopilot 插件中最复杂的阶段，承担从任务清单到可运行代码的全部生成职责。本次评审深入审计了 Phase 5 的三种执行模式（串行/并行/TDD）、规约服从度机制、反偷懒检测、安全护栏和并行正确性保障。

**核心发现**:

- **规约服从度体系设计精良**: `rules-scanner.sh` 从 `.claude/rules/` 和 `CLAUDE.md` 自动提取约束，经 dispatch 协议注入子 Agent prompt，Phase 5 获得完整规则 + 实时 Hook 强制执行，形成 prompt 注入 + Hook 拦截的双重保障。
- **反偷懒检测体系完备**: `anti-rationalization-check.sh` 采用加权评分机制（中英双语 26 种模式），结合 `zero_skip_check` 确定性验证和 `validate-json-envelope.sh` 的字段强制要求，形成三层反偷懒防线。
- **并行实现的正确性保障扎实**: Union-Find 依赖分析 + 域级文件所有权分区 + `parallel-merge-guard.sh` 三层合并验证 + 自动降级策略，构成完整的并行安全体系。
- **存在若干改进空间**: brownfield 验证的执行方式为纯 AI 侧（L3 层），缺少 Hook 级确定性保障；`anti-rationalization-check.sh` 对后台 Agent 的跳过可能在并行 TDD 模式下产生覆盖盲区；部分安全检查依赖 `python3` 可用性，缺失时静默放行。

**综合评分: 8.5 / 10** — 架构设计成熟，机制层次分明，在同类编排系统中处于优秀水平。

---

## 2. 评审方法论

### 2.1 审计范围

本次评审覆盖以下文件和机制：

| 类别 | 审计文件 |
|------|---------|
| 主流程编排 | `SKILL.md` Phase 5 章节 |
| 实现细节 | `references/phase5-implementation.md` |
| TDD 协议 | `references/tdd-cycle.md` |
| 并行调度 | `references/parallel-dispatch.md`, `references/parallel-phase-dispatch.md` |
| 子 Agent 调度 | `autopilot-dispatch/SKILL.md` |
| 门禁验证 | `autopilot-gate/SKILL.md` |
| 护栏约束 | `references/guardrails.md`, `references/brownfield-validation.md` |
| Hook 脚本 | `anti-rationalization-check.sh`, `write-edit-constraint-check.sh`, `parallel-merge-guard.sh`, `rules-scanner.sh`, `code-constraint-check.sh`, `validate-json-envelope.sh` |
| 共享模块 | `_hook_preamble.sh`, `_common.sh`, `_envelope_parser.py`, `_constraint_loader.py` |
| 内置模板 | `templates/phase5-serial-task.md` |

### 2.2 审计方法

1. **静态分析**: 逐行阅读所有 Shell 脚本和 Python 模块，检查逻辑正确性、边界处理和错误恢复。
2. **链路追踪**: 从主流程 SKILL.md 出发，追踪规则注入链路（rules-scanner.sh -> dispatch -> prompt -> Hook 验证）的完整数据流。
3. **模式匹配**: 对照 OWASP 安全编码标准和 TDD 最佳实践，检验防御机制的覆盖度。
4. **对比分析**: 将串行/并行/TDD 三种模式的保障机制进行交叉比较，识别覆盖差异。

---

## 3. 规约服从度审计

### 3.1 CLAUDE.md 规则注入链路

Phase 5 的规约服从度通过一条完整的注入链路实现：

```
Phase 0 首次扫描 → rules-scanner.sh 缓存
    ↓
每次阶段切换 → Step 5.5 CLAUDE.md 变更检测（v4.0 新增）
    ↓ 修改时间变化则重新扫描
dispatch 构造 prompt → 优先级 2.5 注入 rules_scan_result
    ↓
子 Agent prompt 中包含完整规则（Phase 5 = 完整规则 + 实时 Hook）
    ↓
PostToolUse Hook 层：
  - write-edit-constraint-check.sh（Write/Edit 文件级拦截）
  - code-constraint-check.sh（Task 完成后 artifacts 检查）
```

**关键设计决策审查**:

1. **缓存策略合理**: Phase 0 首次运行 `rules-scanner.sh` 后缓存结果，同一会话内复用。v4.0 新增 Step 5.5 变更感知机制，比较 `CLAUDE.md` 修改时间与缓存时间戳，变化时自动重新扫描。这解决了运行中规则变更的场景。

2. **阶段差异化注入得当**: Phase 5 获得"完整规则 + 实时 Hook 强制执行"，这是所有阶段中约束最强的，符合代码生成阶段的高风险属性。Phase 2-3 仅注入紧凑摘要（critical_rules, <=5 条），Phase 6 也仅紧凑摘要，避免上下文膨胀。

3. **优先级体系清晰**: dispatch 协议定义了 7 层优先级（instruction_files > reference_files > Rules Auto-Scan > project_context > test_suites > services > Phase 1 Steering > 内置规则），项目自定义指令可覆盖内置规则，保证了灵活性。

### 3.2 规则扫描器有效性

`rules-scanner.sh` 的实现审查：

**优势**:
- 双源扫描: 同时扫描 `.claude/rules/*.md` 和 `CLAUDE.md`，覆盖完整。
- 多模式提取: 支持表格行格式（`| \`xxx\` | \`yyy\` |`）、禁止行（`禁止xxx` / `❌ xxx`）、必须使用（`必须xxx` / `✅ xxx`）、命名约定（kebab-case/camelCase 等）四类模式。
- 自动去重: 基于 `(type, pattern)` 组合去重。
- 紧凑摘要生成: 同时输出 `constraints`（完整列表）和 `compact_summary`（仅 critical 前 10 条），支持不同阶段的差异化注入需求。

**局限**:
- 正则提取覆盖度有限: 仅识别特定格式的禁止/必须规则。自由文本中的约束（如"请确保所有 API 使用 RESTful 风格"）无法被捕获。这是一个设计折衷——完全的自然语言理解需要 LLM，但 Hook 追求确定性。
- CLAUDE.md 扫描为降级策略: 仅在 `code_constraints` 配置不存在时才扫描 CLAUDE.md，意味着配置了 `code_constraints` 的项目中 CLAUDE.md 的额外约束可能被遗漏。不过 `rules-scanner.sh` 始终扫描 `.claude/rules/` 和 `CLAUDE.md`（与 `_constraint_loader.py` 不同），两者互补。

### 3.3 发现与评分

| 检查项 | 状态 | 说明 |
|--------|------|------|
| 规则注入链路完整性 | PASS | 从扫描到注入到 Hook 验证，闭环 |
| CLAUDE.md 变更感知 | PASS | v4.0 Step 5.5 机制有效 |
| 阶段差异化注入 | PASS | Phase 5 获得最强约束级别 |
| 双重保障（prompt + Hook） | PASS | 子 Agent 知悉规则 + Hook 确定性拦截 |
| 规则扫描器格式覆盖度 | WARN | 自由文本约束无法捕获（设计折衷，非缺陷） |
| 配置优先级与 CLAUDE.md 互补 | PASS | `_constraint_loader.py` 和 `rules-scanner.sh` 各司其职 |

**规约服从度评分: 9.0 / 10**

---

## 4. 上下文感知与防重复审计

### 4.1 项目上下文传递机制

Phase 5 的上下文传递遵循"控制器提取全文"模式：

```
主线程（控制器）:
  1. 一次性读取所有 task 完整文本和上下文
  2. 从 Phase 1 Steering Documents 提取项目结构
  3. 构造 context_injection 段落
  4. 注入到每个子 Agent 的 prompt

子 Agent:
  - 收到完整上下文（禁止自行读取计划文件）
  - 收到前序 task 摘要（只读参考）
  - 收到项目规则约束
```

**关键机制审查**:

1. **前序 task 摘要注入**: 串行模式中，每个 task 的 prompt 包含所有已完成 task 的摘要，确保后续 task 能感知已有实现。这有效防止了重复实现。

2. **Phase 1 Steering Documents 流转**: Auto-Scan 生成的 `existing-patterns.md` 记录现有代码模式，通过 dispatch 链注入到 Phase 5 子 Agent，使 Agent 能感知并复用已有 Utils/组件。

3. **context_injection 的内容**: 包含 project_context（项目结构、技术栈）、test_suites（测试命令）、services（服务地址），以及 Phase 1 调研结论。信息充分。

4. **并行模式的上下文隔离**: 每个域 Agent 收到该域所有 task 全文 + 域级文件所有权 + 其他域文件列表（禁止修改）。域 Agent 之间通过文件所有权实现隔离，通过共享 context_injection 保持一致性。

### 4.2 Brownfield 漂移检测

`brownfield-validation.md` 定义了三向一致性检查：

| 检查点 | 内容 | 执行时机 |
|--------|------|---------|
| 设计-测试对齐 | design spec API/模型 vs 测试覆盖 | Phase 4 -> Phase 5 |
| 测试-实现就绪 | 测试 import 路径 vs 项目结构 | Phase 5 启动 |
| 实现-设计一致性 | 实际代码 vs design spec + scope creep 检测 | Phase 5 -> Phase 6 |

**关键发现**:

1. **默认状态变迁**: 文档注释称"默认 false，opt-in"，但 gate SKILL.md 明确记载"v4.0 起默认开启，greenfield 项目 Phase 0 自动关闭"。这意味着当前版本已默认启用。

2. **执行层级为 L3（AI 侧）**: brownfield 验证在 `autopilot-gate` 的 8 步检查清单之后作为"可选 Layer 3 补充"执行。这意味着它依赖 AI 的正确执行，缺少 Hook 级确定性保障。这是一个有意识的设计选择——三向一致性检查涉及语义理解（如"API 端点签名是否一致"），难以用正则或 AST 确定性验证。

3. **strict_mode 控制**: `strict_mode: false`（默认）时仅 warning 不阻断，`true` 时直接 block。对大多数项目而言默认宽松模式是合理的。

4. **scope creep 检测**: 实现-设计一致性检查中包含"是否有 design spec 中未提及的额外实现"和"现有代码的公共 API 是否被意外修改（breaking change 检测）"。这对防重复和防越界非常重要。

### 4.3 发现与评分

| 检查项 | 状态 | 说明 |
|--------|------|------|
| 控制器提取全文模式 | PASS | 子 Agent 不自行读取计划文件，避免上下文膨胀 |
| 前序 task 摘要注入 | PASS | 有效防止重复实现 |
| existing-patterns.md 流转 | PASS | Phase 1 -> Phase 5 复用通路完整 |
| 并行模式上下文隔离 | PASS | 域级文件所有权 + 共享 context |
| Brownfield 默认状态文档不一致 | INFO | brownfield-validation.md 称"默认 false"，gate SKILL.md 称"v4.0 起默认开启"，以 gate 为准 |
| Brownfield 检测为纯 L3 层 | WARN | 无 Hook 级确定性保障，依赖 AI 正确执行 |
| Scope creep 检测 | PASS | 设计中明确包含越界检测 |

**上下文感知与防重复评分: 8.5 / 10**

---

## 5. 反偷懒检测审计

### 5.1 Anti-Rationalization 机制

`anti-rationalization-check.sh` 是 Phase 5 反偷懒的核心 Hook，其设计精巧：

**触发条件**:
- 仅 Phase 4/5/6（代码产出阶段）
- 仅 status 为 ok/warning（blocked/failed 视为合法停止）
- 输出包含合理化模式

**加权评分体系**:

| 权重 | 模式类型 | 示例 |
|------|---------|------|
| 3 (高) | 强跳过信号 | `skipped this because`, `deferred to future` |
| 2 (中) | 范围/延后信号 | `out of scope`, `will be done later` |
| 1 (低) | 弱信号 | `already covered`, `not necessary`, `too complex` |

**中文支持**: 包含完整的中文合理化模式（12 种），如"跳过"、"延后处理"、"后续再补充"、"超出范围"等。这对中文项目至关重要。

**评分阈值**:
- `>= 5`: 硬阻断（多个强跳过信号）
- `>= 3 且无 artifacts`: 阻断（疑似合理化且无交付物）
- `>= 2`: 仅 stderr 警告（有交付物但有弱信号）
- `< 2`: 静默通过

**关键发现**:

1. **后台 Agent 跳过**: `is_background_agent && exit 0` 表示后台 Agent（`run_in_background: true`）不受此检查。在并行模式下，所有域 Agent 都是后台 Agent（`run_in_background: true`），意味着并行模式的反合理化检测依赖其他机制（如后续的批量 review + 全量测试）。这是一个有意设计——后台 Agent 的输出不经过主线程的 PostToolUse Hook 处理管道。

2. **artifacts 双重检查**: 评分 >= 3 但有 artifacts 时仅警告不阻断，这避免了对合法使用相关词汇（如"this test already covers the edge case"）的误判。

3. **模式覆盖全面**: 26 种模式覆盖了常见的偷懒借口，包括"太简单不用测"、"后面补"、"超出范围"、"太复杂"等。

### 5.2 Zero-Skip 检查

`validate-json-envelope.sh` 中的 Phase 5 特殊验证：

```python
# Phase 5 special: zero_skip_check.passed must be true when status is ok
if phase_num == 5 and found_json.get('status') == 'ok':
    zsc = found_json.get('zero_skip_check', {})
    if isinstance(zsc, dict) and zsc.get('passed') is not True:
        → block
```

**机制分析**:

1. **确定性保障**: 这是 L2 层的确定性检查——Phase 5 子 Agent 的 JSON 信封必须包含 `zero_skip_check` 字段，且 `passed` 必须为 `true`。Hook 脚本直接验证字段值，不依赖 AI 判断。

2. **字段强制要求**: `validate-json-envelope.sh` 的 `phase_required` 定义中，Phase 5 要求 `['test_results_path', 'tasks_completed', 'zero_skip_check']`。缺少任一字段即 block。这确保子 Agent 无法通过省略字段来逃避检查。

3. **与 Phase 5->6 门禁联动**: `autopilot-gate` 的 Phase 5->6 特殊门禁额外验证 `zero_skip_check.passed === true`。即使 Hook 层被绕过，门禁层也会拦截。

4. **test-results.json 写入**: `phase5-serial-task.md` 模板要求子 Agent 写入 `test-results.json`，包含每个 suite 的 `total/passed/failed/skipped` 和 `zero_skip_check: { passed: true/false, violations: [] }`。

### 5.3 发现与评分

| 检查项 | 状态 | 说明 |
|--------|------|------|
| 反合理化加权评分机制 | PASS | 26 种模式，中英双语，三级阈值 |
| 误判防护 | PASS | 有 artifacts 时提高阈值至 5 |
| zero_skip_check L2 确定性验证 | PASS | Hook 直接校验字段值 |
| Phase 5 信封字段强制 | PASS | 3 个必填字段 + block on missing |
| 后台 Agent 反偷懒覆盖 | WARN | 并行模式域 Agent 为后台 Agent，跳过 anti-rationalization |
| tasks_completed 字段校验 | PASS | 信封必含 tasks_completed，可验证是否全部完成 |

**反偷懒检测评分: 8.5 / 10**

---

## 6. 安全性与健壮性审计

### 6.1 Guardrails 约束体系

`guardrails.md` 定义了 Phase 5 相关的核心约束清单：

**代码质量约束**:
- 任务拆分: 每次 <= 3 个文件，<= 800 行代码
- 测试不可变: 禁止修改测试以通过，只能修改实现代码
- 配置驱动: 所有项目路径从 `autopilot.config.yaml` 读取，禁止硬编码

**错误处理机制**:
- Phase 5 子 Agent 异常退出: 保存进度到 checkpoint，从上次完成的 task 恢复
- 连续 3 次失败: AskUserQuestion 决策（查看详情/跳过/中止）
- JSON 解析失败: 标记 failed
- 上下文压缩: PreCompact Hook 自动保存状态，SessionStart(compact) 自动注入恢复

**Wall-clock 超时机制**:
- 超过 2 小时强制暂停，AskUserQuestion 提供三个选项（继续/保存暂停/回退）
- 后台 Agent 硬超时 30 分钟（`config.background_agent_timeout_minutes`）

**崩溃恢复**:
- Phase 5 启动时扫描 `phase5-tasks/` 目录，找到最后一个 `status: "ok"` 的 task
- TDD 模式下扫描 `tdd_cycle` 字段确定 RED/GREEN/REFACTOR 恢复点
- Git tag `autopilot-phase5-start` 标记回退点

### 6.2 代码约束检查

**`code-constraint-check.sh`（PostToolUse(Task)，Phase 4/5/6）**:

- 从 `_constraint_loader.py` 加载约束（forbidden_files, forbidden_patterns, allowed_dirs, max_file_lines）
- 检查 Task 返回信封中的 artifacts 列表
- 违反任一约束 -> block

**`write-edit-constraint-check.sh`（PostToolUse(Write|Edit)，Phase 5 专属）**:

- 与 `code-constraint-check.sh` 互补: 后者检查 Task 返回的 artifacts，本脚本直接拦截 Write/Edit 工具调用
- 精确的 Phase 5 检测逻辑: 通过 checkpoint 文件的存在性推断当前阶段（支持 full/TDD/lite/minimal 模式）
- 三模式 Phase 5 检测完整: full（phase-4 存在 + phase-5 不存在）、TDD（phase-3 存在 + tdd_mode=true）、lite/minimal（phase-1 ok + 无 phase-4）

**`_constraint_loader.py` 共享模块**:

- 双优先级约束源: config.yaml `code_constraints` > CLAUDE.md 降级
- 四维检查: 禁止文件名、目录范围、文件行数、禁止模式
- 文件内容检查: 实际读取文件内容检查 forbidden_patterns，不仅检查文件名

**关键发现**:

1. **python3 依赖的软降级**: 所有 Hook 在 `python3` 不可用时静默退出（`exit 0`）。`validate-json-envelope.sh` 是唯一例外——通过 `require_python3` 函数输出 block JSON。其他 Hook 的注释明确说明这是"secondary check"的设计选择，但 `write-edit-constraint-check.sh` 和 `code-constraint-check.sh` 作为代码约束检查的核心 Hook，静默放行可能导致约束失效。

2. **文件行数检查的实际执行**: `_constraint_loader.py` 读取文件内容（最多 100KB）计算行数，超过 `max_file_lines`（默认 800）即报违规。这确保了"每次 <= 800 行"的约束通过确定性检查而非 AI 自律。

3. **forbidden_patterns 的正则转义**: `_constraint_loader.py` 使用 `re.escape(pat)` 将模式转为精确匹配（非正则），避免配置中的特殊字符导致误判。

### 6.3 发现与评分

| 检查项 | 状态 | 说明 |
|--------|------|------|
| 任务粒度约束（3 文件/800 行） | PASS | Hook 确定性检查文件行数 |
| 测试不可变约束 | PASS | TDD 模式 Iron Law + GREEN 阶段禁止修改测试 |
| 配置驱动禁硬编码 | PASS | 所有路径从 config 读取 |
| 崩溃恢复完整性 | PASS | task 级 checkpoint + TDD cycle 级恢复点 |
| Wall-clock 超时 | PASS | 2 小时强制暂停 + 30 分钟后台 Agent 超时 |
| python3 缺失时约束 Hook 静默放行 | WARN | `write-edit-constraint-check.sh` 和 `code-constraint-check.sh` 在无 python3 时退出 0 |
| 错误处理覆盖度 | PASS | 连续失败/JSON 异常/压缩恢复全覆盖 |
| Git 安全检查点 | PASS | `autopilot-phase5-start` tag |

**安全性与健壮性评分: 8.5 / 10**

---

## 7. 并行实现正确性审计

### 7.1 Union-Find 依赖分析

`parallel-dispatch.md` 定义的依赖图构建算法：

```
1. 解析 tasks.md 中每个 task 的 affected_files[]
2. 构建邻接矩阵: task_i -> task_j 有边 iff affected_files 有交集
3. Union-Find 连通分量分组
4. 组间按最小 task 编号排序
5. cross_cutting_tasks 移入最后一组串行执行
```

**v3.4.0 域级快速分区**（Phase 5 专用）：

当任务按顶级目录自然分离时，跳过 Union-Find，直接三步域检测：

1. **最长前缀匹配**: 从 `config.domain_agents` 读取路径前缀，最长前缀优先
2. **auto 发现**: 未匹配任务按顶级目录归域，带祖先冲突检测（防止 `services/` 与 `services/auth/` 冲突）
3. **溢出合并**: 域数超过 `max_agents`（默认 8）时，同 Agent 类型的域合并

**正确性分析**:

1. **Union-Find 算法正确**: 标准的连通分量算法，通过 affected_files 交集建边，确保有共享文件的 task 不会被并行执行。

2. **域级分区的安全性**: 三步检测中的祖先冲突检测（`no_child_prefix`）防止了将跨域 task 错误归入祖先域。例如 task 跨 `services/auth/` 和 `services/payment/` 时，不会被归入 `services/`（因为有已配置的子前缀），而是正确归入 `cross_cutting`。

3. **溢出合并的合理性**: 同 Agent 类型的域合并不影响文件所有权隔离——合并后的逻辑域仍有完整的 `owned_files` 列表。

4. **cross_cutting 串行执行**: 跨域 task 在所有并行域完成后串行执行，避免了跨域冲突。

### 7.2 并行合并保护

`parallel-merge-guard.sh` 提供三层合并验证：

**检查 1: 合并冲突残留检测**
```bash
git diff --check          # 工作区冲突标记
git diff --cached --check # 暂存区冲突标记
```
- 使用 Git 原生命令，输出完全确定性
- 同时检查工作区和暂存区两个层面
- 超时 15 秒，避免大仓库阻塞

**检查 2: Task scope 校验**
```python
# 对比实际变更文件 vs 信封 artifacts
changed_files = git diff --name-only {diff_base} HEAD
out_of_scope = [f for f in changed_files if not in_artifacts_scope(f)]
```
- 优先使用 `anchor_sha`（Phase 0 锚定 commit），降级到 `HEAD~1`
- 使用 `merge-base --is-ancestor` 验证 anchor_sha 有效性
- 宽松匹配: 允许 artifact 路径的子目录文件

**检查 3: 快速类型检查**
```python
# 从 config.test_suites 读取 typecheck 命令
typecheck_cmds = [cmd for suite if suite.type == 'typecheck']
# 每次 merge 后立即执行，超时 120 秒
```
- 从 config 动态读取（不硬编码命令）
- 每次 merge 后立即执行（早期拦截）
- 单次 120 秒超时

**正确性分析**:

1. **触发条件精准**: 仅在 Phase 5 + worktree merge 相关输出时触发（双重过滤: bash grep + python regex）。

2. **diff_base 选择的健壮性**: 先验证 anchor_sha 是 HEAD 的祖先（防止在 rebase/reset 后使用无效 SHA），再降级到 HEAD~1，最后如果都无效则跳过 scope 检查（不误阻断）。

3. **config YAML 解析的脆弱性**: `parallel-merge-guard.sh` 使用正则解析 YAML（非 PyYAML），对复杂 YAML 格式（嵌套引号、多行值）可能失败。但这仅影响 typecheck 命令的提取，失败时跳过检查（不误阻断），并在 stderr 输出警告。

4. **降级策略完整**: SKILL.md 定义的降级决策树覆盖了所有失败场景：
   - worktree 创建失败 -> 立即降级串行
   - 域级合并冲突 > 3 文件 -> 回退该域串行执行
   - 2 个域合并失败 -> 全面降级串行
   - 用户选择 -> 全面降级

5. **文件所有权强制**: `write-edit-constraint-check.sh` 在并行模式下额外检查 `phase5-ownership/agent-{N}.json`，越权写入直接 block。这从 Hook 层面保证了域间隔离。

### 7.3 发现与评分

| 检查项 | 状态 | 说明 |
|--------|------|------|
| Union-Find 依赖分析算法 | PASS | 标准连通分量，正确 |
| 域级快速分区 | PASS | 三步检测 + 祖先冲突检测 |
| 合并冲突确定性检测 | PASS | git diff --check，不依赖 AI |
| Task scope 校验 | PASS | anchor_sha 优先 + 降级策略 |
| 快速类型检查 | PASS | 每次 merge 后立即执行 |
| 文件所有权 Hook 强制 | PASS | write-edit-constraint-check 越权 block |
| 降级决策树 | PASS | 4 种场景全覆盖 |
| YAML 解析鲁棒性 | WARN | 正则解析可能对复杂格式失败（但安全降级） |
| 后台 Agent 与 merge-guard 的交互 | INFO | merge-guard 跳过后台 Agent（`is_background_agent && exit 0`），但合并操作在主线程执行，不受此影响 |

**并行实现正确性评分: 9.0 / 10**

---

## 8. 综合评分表

| 评审维度 | 评分 | 权重 | 加权分 |
|---------|------|------|-------|
| 规约服从度 | 9.0 | 25% | 2.25 |
| 上下文感知与防重复 | 8.5 | 20% | 1.70 |
| 反偷懒检测 | 8.5 | 20% | 1.70 |
| 安全性与健壮性 | 8.5 | 20% | 1.70 |
| 并行实现正确性 | 9.0 | 15% | 1.35 |
| **综合** | **8.7** | **100%** | **8.70** |

---

## 9. 关键缺陷清单 (P0/P1/P2)

### P0 (阻断级 — 无)

未发现 P0 级缺陷。

### P1 (重要 — 建议优先修复)

| ID | 缺陷 | 位置 | 影响 | 建议 |
|----|------|------|------|------|
| P1-1 | 并行模式域 Agent 跳过 anti-rationalization 检查 | `anti-rationalization-check.sh` L20 `is_background_agent && exit 0` | 并行模式下域 Agent 的偷懒行为无法被 Hook 检测，仅靠后续批量 review 和全量测试间接保障 | 考虑在域 Agent 合并后、批量 review 前，对合并后的 git diff 执行一次 anti-rationalization 扫描；或在合并后的 checkpoint 写入时检查 `tasks_completed` 数组完整性 |
| P1-2 | python3 缺失时约束 Hook 静默放行 | `write-edit-constraint-check.sh` L77, `code-constraint-check.sh` L18 | 无 python3 环境下，禁止文件/模式/行数约束全部失效 | 对核心约束检查（至少 forbidden_files）增加纯 bash 降级路径，或将 python3 检查提升为 Phase 0 硬前置条件 |
| P1-3 | brownfield-validation.md 默认状态描述与 gate SKILL.md 不一致 | `brownfield-validation.md` L63 vs `autopilot-gate/SKILL.md` L177 | brownfield-validation.md 称"默认 false"，gate SKILL.md 称"v4.0 起默认开启"，可能导致实施者误解 | 统一 `brownfield-validation.md` 中的默认值描述为"v4.0 起默认 true" |

### P2 (改进级 — 可在后续迭代处理)

| ID | 缺陷 | 位置 | 影响 | 建议 |
|----|------|------|------|------|
| P2-1 | parallel-merge-guard 使用正则解析 YAML 提取 typecheck 命令 | `parallel-merge-guard.sh` L166-183 | 复杂 YAML 格式（嵌套引号、多行值、锚点引用）可能解析失败，导致 typecheck 被跳过 | 复用 `_envelope_parser.py` 的 `read_config_value` 方法提取 typecheck 命令，或使用 PyYAML 优先策略 |
| P2-2 | Brownfield 三向一致性检查缺少 Hook 级确定性保障 | `brownfield-validation.md` + `autopilot-gate/SKILL.md` | 完全依赖 AI（L3 层）执行，可能被跳过或执行不完整 | 对最关键的检查项（如"git diff 中修改的文件是否都在 tasks.md 范围内"）增加 Hook 级脚本实现 |
| P2-3 | rules-scanner.sh 无法提取自由文本约束 | `rules-scanner.sh` | 以散文形式描述的约束（如"所有 API 必须使用 RESTful 风格"）不会被捕获 | 可考虑在 compact_summary 中增加"未结构化约束"提示，引导用户将约束写为结构化格式 |
| P2-4 | 串行 TDD 模式中 REFACTOR 阶段回滚使用 `git checkout` | `tdd-cycle.md` L108 | `git checkout -- {modified}` 仅回滚工作区，如果 REFACTOR Agent 已经 commit（通过 Bash 工具），则无法回滚 | 建议使用 `git stash` 或在 REFACTOR 前创建 git tag 作为回滚点 |
| P2-5 | `_constraint_loader.py` 的 CLAUDE.md 降级扫描模式较窄 | `_constraint_loader.py` L100-116 | 仅匹配 backtick/pipe 包围的文件名 + "禁" 字组合，覆盖面有限 | 复用 `rules-scanner.sh` 的更丰富的模式匹配逻辑 |

---

## 10. 改进建议

### 10.1 短期改进（1-2 周）

1. **P1-3 文档一致性修复**: 更新 `brownfield-validation.md` 中默认值描述，与 `autopilot-gate/SKILL.md` 保持一致。工作量: 1 行修改。

2. **P1-2 python3 硬前置条件**: 在 Phase 0 环境检查中增加 `python3` 可用性验证，不满足则阻断 autopilot 启动。这比在每个 Hook 中处理降级更为简洁。工作量: 约 10 行。

3. **P2-1 YAML 解析统一**: 将 `parallel-merge-guard.sh` 中的 typecheck 命令提取逻辑替换为复用 `_envelope_parser.py` 的 `read_config_value`。工作量: 约 20 行重构。

### 10.2 中期改进（1-2 月）

4. **P1-1 并行模式反偷懒增强**: 设计一个合并后的反偷懒检查点。可在主线程合并域 Agent 结果后、写入 checkpoint 前，对 `tasks_completed` 数组做完整性校验（是否覆盖该域所有 task），并对合并后的 `git diff` 内容执行简化的 rationalization 扫描。

5. **P2-2 Brownfield scope 检查 Hook 化**: 将"git diff 中修改的文件是否都在 tasks.md/owned_files 范围内"这一检查从 L3 层下沉到 `parallel-merge-guard.sh` 的检查 2（Task scope 校验），利用已有的基础设施。

### 10.3 长期改进（3-6 月）

6. **语义约束检测增强**: 探索使用轻量级 AST 分析（如 `tree-sitter`）对 Phase 5 生成的代码进行结构化验证，补充正则无法覆盖的语义约束（如"所有公共方法必须有 JSDoc 注释"）。

7. **反偷懒指标体系**: 建立 Phase 5 产出质量的量化指标（如每 task 平均修改文件数、代码/测试比、重复代码比率），纳入 Phase 7 报告，为持续改进提供数据支撑。

---

> **评审结论**: Phase 5 的代码生成质量保障体系设计成熟，层次分明。规约服从度链路（扫描-注入-Hook 拦截）、反偷懒三层防线（anti-rationalization + zero_skip + 信封字段强制）、并行安全体系（Union-Find + 文件所有权 + merge-guard + 降级策略）均达到了工程级质量标准。建议优先修复 P1 级缺陷以进一步提升系统的鲁棒性。
