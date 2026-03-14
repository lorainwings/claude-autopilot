# v5.1.1 全局规约与记忆遵守度审计报告

**审计日期**: 2026-03-14
**插件版本**: v5.1.1
**审计方**: AI 合规审计 Agent 5 (Opus 4.6, 1M context)
**事实来源**: `plugins/spec-autopilot/CLAUDE.md` (65 行, Single Source of Truth)
**对比基线**: `docs/reports/v5.0.4/compliance-audit.md`

---

## 1. 审计摘要

### 1.1 总体评分

| 审计维度 | 评分 (1-100) | 等级 |
|----------|:----------:|:----:|
| TDD 阶段隔离确定性 | **82** | B+ |
| openspec 路径保护确定性 | **90** | A- |
| 代码质量门禁覆盖度 | **92** | A- |
| Anti-Rationalization 覆盖度 | **78** | B |
| 子 Agent 约束执行力 | **80** | B |
| 规约-代码一致性 | **85** | B+ |
| **总体合规评分** | **85** | **B+** |

### 1.2 确定性覆盖率对比

| 指标 | v5.0.4 基线 | v5.1.1 实态 | Delta |
|------|:----------:|:----------:|:-----:|
| CLAUDE.md 总规则数 | 40 | 40 | 0 |
| L2 确定性保障 | 34 | 34 | 0 |
| 仅 L3 AI 自觉 | 1 (SM-7) | 1 (SM-7) | 0 |
| 无任何保障 | 5 | 5 | 0 |
| **确定性覆盖率** | **85.0%** | **85.0%** | **0pp** |
| 综合合规评分 | 84/100 | 85/100 | +1 |

### 1.3 关键结论

v5.1.1 在 v5.0.4 基础上**无重大退化**。代码实态与 v5.0.4 报告描述的机制完全一致。主要发现：

1. **CLAUDE.md 文档不一致（CQ-3）**: 声称"10 种 excuse 模式"，实际实现 22 个加权模式 -- 积极超额但文档滞后
2. **TDD .tdd-stage 崩溃残留风险依旧**: Recovery 协议仍未增加清理步骤
3. **SA-1 仍无 L2 保障**: Claude Code 不支持 PreToolUse(Read) Hook，子 Agent 读取计划文件无法拦截
4. **hooks.json 结构正确**: 仅 2 个活跃 Hook 脚本注册（1 PreToolUse + 2 PostToolUse），废弃文件正确未注册
5. **Anti-Rationalization 模式存在绕过向量**: 时间借口、环境借口、隐式降级等未覆盖

---

## 2. TDD `.tdd-stage` 阶段隔离审查

### 2.1 机制架构

```
主线程 Bash → 写入 .tdd-stage ("red"/"green"/"refactor")
  ↓
unified-write-edit-check.sh CHECK 1 (L120-L152)
  ├── 读取 .tdd-stage 文件 (L126-L127)
  ├── 文件名模式判定 IS_TEST_FILE (L129-L135)
  ├── RED: IS_TEST_FILE=no → block (L138-L142)
  ├── GREEN: IS_TEST_FILE=yes → block (L144-L149)
  └── REFACTOR: 不拦截，由 L2 Bash 测试验证
```

### 2.2 逐行验证

| 检查项 | 代码位置 | 验证结果 |
|--------|---------|---------|
| .tdd-stage 文件路径正确 | L125: `$CHANGES_DIR/$CHANGE_NAME/context/.tdd-stage` | PASS - 与主线程写入路径一致 |
| 读取安全性 | L127: `cat + tr -d '[:space:]' + tr '[:upper:]' '[:lower:]'` | PASS - 规范化处理，容忍空白和大小写 |
| RED 阶段阻断实现文件 | L138-L142: `IS_TEST_FILE=no → block` | PASS - 确定性阻断 |
| GREEN 阶段阻断测试文件 | L144-L149: `IS_TEST_FILE=yes → block` | PASS - 确定性阻断 |
| REFACTOR 不拦截 | L137: `case "$TDD_STAGE"` 无 refactor 分支 | PASS - 设计如此 |
| .tdd-stage 在 CHECK 0 中被豁免 | L104-L106: `*context/.tdd-stage → PROTECTED_PATH_HIT="no"` | PASS - 防止 CHECK 0 误阻断主线程写入 |

### 2.3 测试文件名模式覆盖度

**文件名模式** (L130-L132):

| 模式 | 覆盖语言 | 评估 |
|------|---------|------|
| `*.test.*` | JS/TS (Jest, Vitest) | PASS |
| `*.spec.*` | JS/TS (Mocha, Jasmine), Ruby (RSpec) | PASS |
| `*_test.*` | Go, Python (部分) | PASS |
| `*_spec.*` | Ruby, Python (部分) | PASS |
| `*Test.*` | Java (JUnit), Kotlin | PASS |
| `*Spec.*` | Java (Spock), Kotlin | PASS |

**路径模式** (L133-L135):

| 模式 | 覆盖框架 | 评估 |
|------|---------|------|
| `*/__tests__/*` | Jest 默认 | PASS |
| `*/test/*` | 通用 | PASS |
| `*/tests/*` | Python (pytest), Rust | PASS |
| `*/spec/*` | Ruby (RSpec) | PASS |
| `*_test/*` | 非标准 | PASS |
| `*_spec/*` | 非标准 | PASS |

**未覆盖模式**:
- `*_tests/*` (某些 Python 项目) -- v5.0.4 报告已指出，仍未修复
- `**/check_*`, `**/verify_*` 等非标准命名 -- 影响极低
- Rust `#[cfg(test)]` 内联测试模块 -- 无法通过文件名匹配，需语义分析

### 2.4 IN_PHASE5 检测可靠性

`unified-write-edit-check.sh` L42-L76 的三级分支逻辑：

| 条件分支 | 路径 | 评估 |
|----------|------|------|
| Phase 4 CP 存在 → Phase 5 CP 不存在/非 ok | full 正常模式 | PASS |
| Phase 3 CP 存在 + tdd_mode=true → Phase 5 CP 不存在/非 ok | full TDD 模式 | PASS |
| Phase 1 CP 存在 + mode != full → Phase 5 CP 不存在/非 ok | lite/minimal 模式 | PASS |
| Phase 1 CP 存在 + mode = full | full 模式 Phase 2/3 期间 | PASS - 正确不设 IN_PHASE5 |

**与 write-edit-constraint-check.sh（废弃）对比**: 统一 Hook 版本新增了 mode 感知（L66: `read_lock_json_field "$LOCK_FILE" "mode"`），修复了废弃版本中 lite/minimal 模式下不检查 Phase 1 状态的遗漏。

### 2.5 风险项

| 风险 | 等级 | 说明 |
|------|:----:|------|
| 崩溃残留 | **中** | 主线程崩溃后 `.tdd-stage` 残留，后续非 TDD 写入可能被意外阻断。Recovery 协议仍未增加清理步骤 |
| 并行 TDD 无逐步验证 | **中** | `.tdd-stage` 仅用于串行 TDD。并行域 Agent 内部 RED-GREEN-REFACTOR 依赖 `tdd_metrics` 后置验证（L132-L146），可被虚报绕过 |
| REFACTOR 回滚无 L2 兜底 | **中** | TDD-5 仍依赖 L3 协议触发 `git checkout`，无 Hook 验证回滚是否执行 |

### 2.6 评分: 82/100

扣分明细:
- -5: .tdd-stage 崩溃残留未修复（v5.0.4 已提出）
- -5: 并行 TDD tdd_metrics 可被虚报
- -5: REFACTOR 回滚无 L2 兜底
- -3: `*_tests/*` 模式仍未补充

---

## 3. `openspec` 路径状态隔离审查

### 3.1 CHECK 0 子 Agent 状态隔离 (L88-L118)

```bash
# 保护路径匹配
case "$FILE_PATH" in
  *context/phase-results/*) PROTECTED_PATH_HIT="yes" ;;
  *openspec/changes/*/context/*.json) PROTECTED_PATH_HIT="yes" ;;
  *openspec/changes/*/.autopilot-active) PROTECTED_PATH_HIT="yes" ;;
esac

# 窄例外: .tdd-stage
case "$FILE_PATH" in
  *context/.tdd-stage) PROTECTED_PATH_HIT="no" ;;
esac
```

### 3.2 保护覆盖验证

| 路径类型 | 模式 | 阻断? | 评估 |
|----------|------|:-----:|------|
| Checkpoint 文件 | `*context/phase-results/*` | YES | PASS |
| 上下文 JSON | `*openspec/changes/*/context/*.json` | YES | PASS |
| 锁文件 | `*openspec/changes/*/.autopilot-active` | YES | PASS |
| TDD 阶段文件 | `*context/.tdd-stage` | NO (豁免) | PASS - 主线程通过 Bash 写入 |
| tasks.md | `*openspec/changes/*/tasks.md` | NO | PASS - 设计允许子 Agent 标记任务完成 |

### 3.3 潜在逃逸路径分析

| 逃逸向量 | 风险 | 说明 |
|----------|:----:|------|
| 子 Agent 通过 Bash 工具写入 openspec/ | **低** | PostToolUse(Write\|Edit) Hook 不拦截 Bash 工具。但子 Agent 使用 Bash 写文件是非典型行为，L3 prompt 禁止此操作 |
| `*openspec/changes/*/context/` 下非 .json 文件 | **极低** | 模式 `*.json` 不覆盖 `.txt` 等。实际 context/ 下仅有 JSON 和 .tdd-stage |
| `*openspec/` 根目录文件 | **极低** | 模式不覆盖 `openspec/schema.json` 等根文件。这些不是运行时状态文件 |

### 3.4 Checkpoint 写入通道验证

CLAUDE.md 声称 "checkpoint 写入仅限 Bash 工具"。验证：

- `check-predecessor-checkpoint.sh` 是 PreToolUse(Task) Hook，不写入 checkpoint
- Checkpoint 写入由主线程在 `autopilot-gate/SKILL.md` 中通过 `Bash("echo '...' > phase-N-*.json")` 执行
- PostToolUse(Write|Edit) Hook 不覆盖 Bash 工具调用 -- 这是设计意图，Bash 写入绕过是正确行为

### 3.5 评分: 90/100

扣分明细:
- -5: Bash 工具逃逸路径存在（低风险但非零）
- -3: 非 .json 文件在 context/ 下未被覆盖
- -2: 缺少对 openspec 根目录文件的保护（极低风险）

---

## 4. 代码质量门禁覆盖度审查

### 4.1 CHECK 2: TODO/FIXME/HACK 检测 (L155-L183)

| 检查项 | 实现 | 评估 |
|--------|------|------|
| 模式 | `grep -inE '(TODO:\|FIXME:\|HACK:)'` | PASS - 含冒号，减少误报 |
| 大小写不敏感 | `-i` 标志 | PASS |
| 排除文件类型 | `.md/.txt/.json/.yaml` 等 13 种 | PASS |
| 排除路径 | `CHANGELOG/LICENSE/README/openspec/context/phase-results` | PASS |
| 决策输出 | `decision: "block"` + `fix_suggestion` | PASS |

**已知限制**: 不含冒号的 `TODO`（如 `// TODO implement this`）不被检测。这是有意设计选择，v5.0.4 报告已确认。`XXX:` 模式也未覆盖。

### 4.2 CHECK 3: 恒真断言检测 (L188-L228)

| 语言 | 模式数 | 覆盖断言 | 评估 |
|------|:------:|---------|------|
| JavaScript/TypeScript | 2 | `expect(true).toBe(true)`, `expect(true).toBeTruthy()` | PASS |
| Python | 1 | `assert True`, `assertEqual(1, 1)` | PASS |
| Java/Kotlin | 1 | `assertEquals(1, 1)`, `assertTrue(true)` | PASS |
| 通用 | 1 | `assert.*true == true` 等 | PASS |

**总计**: 5 类模式，覆盖 4 大语言生态。

**遗漏的反模式**:
- `expect(x).toBeDefined()` 对非空值的恒真调用 -- 需语义分析，grep 无法检测
- `assert len(x) >= 0` -- 列表长度恒非负
- `assertNotNull(new Object())` -- 构造函数返回恒非空

### 4.3 CHECK 4: 代码约束检查 (L234-L263)

- 仅在 Phase 5 + python3 可用时触发
- 调用 `_constraint_loader.py` 的 `load_constraints()` 和 `check_file_violations()`
- 与 V3 (PostToolUse Task) 形成双重防线：CHECK 4 拦截直接写入，V3 拦截 Task 返回的 artifacts

### 4.4 _post_task_validator.py 代码质量验证矩阵

| Validator | 检查项 | Phase | L2 确定性 |
|:---------:|--------|:-----:|:---------:|
| V1 | JSON 信封结构 + status + phase 特定字段 | 全部 | YES |
| V1 | Phase 4 warning 阻断 | 4 | YES |
| V1 | Phase 5 zero_skip_check.passed=true | 5 | YES |
| V1 | Phase 5 TDD metrics (red_violations=0, cycles>=1) | 5 | YES |
| V1 | Phase 4/6 artifacts 非空 | 4, 6 | YES |
| V1 | test_pyramid 地板 (unit_pct/e2e_pct/total) | 4 | YES |
| V1 | change_coverage ≥ 80% | 4 | YES |
| V1 | sad_path_counts 比例 ≥ 20% | 4 | YES |
| V1 | test_traceability ≥ 80% | 4 | YES |
| V2 | 22 个加权反合理化模式 | 4/5/6 | YES |
| V3 | 代码约束 (forbidden_files/patterns) | 4/5/6 | YES |
| V4 | 并行合并守卫 (冲突+范围+类型检查) | 5 | YES |
| V5 | Phase 1 决策格式 (options>=2, recommended) | 1 | YES |

### 4.5 评分: 92/100

扣分明细:
- -3: 无冒号 TODO 逃逸（设计选择，但存在漏网风险）
- -3: 恒真断言模式有限（5 类 grep 模式无法覆盖语义层面的恒真）
- -2: XXX 模式未覆盖

---

## 5. Anti-Rationalization 覆盖度审查

### 5.1 活跃实现位置

Anti-Rationalization 检查的活跃代码位于 `_post_task_validator.py` V2（L316-L378），而非废弃的 `anti-rationalization-check.sh`。

### 5.2 模式清单（22 个加权模式）

#### 英文模式（11 个）

| # | 权重 | 模式正则 | 目标 excuse |
|---|:----:|---------|-----------|
| 1 | 3 | `skip(ped\|ping)?\s+(this\|the\|these\|because)\s` | 显式跳过 |
| 2 | 3 | `(tests?\|tasks?)\s+were\s+skip(ped\|ping)` | 被动跳过 |
| 3 | 3 | `(deferred?\|postponed?\|deprioritized?)\s+(to\|for\|until)` | 延迟处理 |
| 4 | 2 | `out\s+of\s+scope` | 范围外 |
| 5 | 2 | `(will\|can\|should)\s+(be\s+)?(done\|handled\|addressed\|fixed)\s+(later\|separately\|in\s+a?\s*future)` | 未来处理 |
| 6 | 1 | `already\s+(covered\|tested\|handled\|addressed)` | 已覆盖借口 |
| 7 | 1 | `not\s+(needed\|necessary\|required\|relevant\|applicable)` | 不需要 |
| 8 | 1 | `(works\|good)\s+enough` | 够好了 |
| 9 | 1 | `too\s+(complex\|difficult\|risky\|time[- ]consuming)` | 太复杂 |
| 10 | 1 | `(minimal\|low)\s+(impact\|priority\|risk)` | 低影响 |
| 11 | 1 | `pre[- ]existing\s+(issue\|bug\|problem\|defect)` | 既有问题 |

#### 中文模式（11 个）

| # | 权重 | 模式正则 | 目标 excuse |
|---|:----:|---------|-----------|
| 12 | 3 | `(?:测试\|任务\|功能\|用例)\s*(?:被\|已)?(?:跳过\|省略\|忽略)` | 任务跳过 |
| 13 | 3 | `跳过了?\|已跳过\|被跳过` | 直接跳过 |
| 14 | 3 | `(?:延后\|推迟\|暂缓)(?:处理\|实现\|开发)?` | 延迟处理 |
| 15 | 3 | `后续(?:再\|补充\|处理\|实现\|完善)` | 后续处理 |
| 16 | 2 | `(?:超出\|不在)(?:范围\|scope)` | 超出范围 |
| 17 | 2 | `(?:以后\|后面\|后续\|下[一个]?(?:阶段\|版本\|迭代))(?:再\|来\|处理\|实现)` | 未来迭代 |
| 18 | 2 | `(?:暂时\|先)?不(?:做\|处理\|实现\|考虑)` | 暂不处理 |
| 19 | 1 | `已[经被]?(?:覆盖\|测试\|处理\|实现\|验证)` | 已覆盖 |
| 20 | 1 | `(?:不\|无)(?:需要\|必要\|需\|必须)` | 不需要 |
| 21 | 1 | `(?:太\|过于)(?:复杂\|困难\|耗时)` | 太复杂 |
| 22 | 1 | `(?:影响\|优先级\|风险)\s*(?:较?低\|不大\|很小)` | 低影响 |

### 5.3 评分阈值验证

| 阈值 | 行为 | 代码位置 | 验证 |
|------|------|---------|------|
| score >= 5 | 硬阻断 `decision: "block"` | L354-L359 | PASS |
| score >= 3 且无 artifacts | 阻断 | L361-L366 | PASS |
| score >= 2 | stderr 警告（不阻断） | L368-L378 | PASS |
| score < 2 | 静默通过 | 隐式 | PASS |

### 5.4 CLAUDE.md 声称 vs 实现对比

| CLAUDE.md 声称 | 实际实现 | 一致性 |
|---------------|---------|:------:|
| "10 种 excuse 模式匹配" | 22 个加权模式 (11 EN + 11 CN) | **不一致** (积极超额) |
| "status 强制降级为 blocked" | `decision: "block"` 输出 | PASS |
| 触发 Phase: 未明确 | Phase 4/5/6 + status in (ok, warning) | PASS |

**文档不一致**: CLAUDE.md 第 28 行声称"10 种 excuse 模式"，但实际实现 22 个。这是积极超额（实际更严格），但违反了 Single Source of Truth 原则。应更新文档。

### 5.5 未覆盖的绕过向量

| # | 绕过模式 | 语言 | 示例 | 建议权重 |
|---|---------|:----:|------|:--------:|
| 1 | 时间/资源借口 | EN | "Due to time constraints" | 2 |
| 2 | 环境借口 | EN/CN | "Environment not configured" / "环境未配置" | 2 |
| 3 | 依赖借口 | EN/CN | "Blocked by external dependency" / "依赖外部组件" | 2 |
| 4 | 隐式降级 | EN | "Simplified the approach to ensure stability" | 2 |
| 5 | 委婉完成 | EN/CN | "Implemented the core functionality" / "核心功能已完成" | 1 |
| 6 | 覆盖率操纵 | EN/CN | "Coverage already sufficient at 81%" / "覆盖率已达标" | 1 |
| 7 | 被动语态规避 | EN | "The feature was determined to be non-essential" | 2 |
| 8 | 无标记范围缩减 | EN | "Focused on the highest-priority items" | 2 |

### 5.6 废弃文件 vs 活跃文件一致性

`anti-rationalization-check.sh`（废弃）中的模式列表与 `_post_task_validator.py` V2 **完全一致**（22 个模式，权重相同）。废弃文件未在 hooks.json 中注册。一致性 PASS。

### 5.7 评分: 78/100

扣分明细:
- -8: 8 种高价值绕过向量未覆盖
- -7: CLAUDE.md "10 种"声称与实际 22 种不一致（Single Source of Truth 违规）
- -4: tdd-cycle.md 13 种 TDD 借口中 5 种无对应正则匹配
- -3: `output_lower = output.lower()` 对中文无效（中文无大小写），但中文模式不依赖大小写转换，实际无影响

---

## 6. 子 Agent 约束执行力审查

### 6.1 六条约束逐条验证

#### SA-1: 禁止自行读取计划文件

| 维度 | 评估 |
|------|------|
| L2 保障 | **无** -- Claude Code 不支持 PreToolUse(Read) Hook |
| L3 保障 | dispatch prompt 指令 |
| 风险 | **中** -- 子 Agent 可自由读取 openspec/ 下任何文件 |
| v5.0.4 Delta | 不变 |

#### SA-2: 禁止修改 openspec/checkpoint

| 维度 | 评估 |
|------|------|
| L2 保障 | `unified-write-edit-check.sh` CHECK 0 (L88-L118): Phase 5 阻断 |
| 保护路径 | `*context/phase-results/*`, `*openspec/changes/*/context/*.json`, `*openspec/changes/*/.autopilot-active` |
| 豁免路径 | `*context/.tdd-stage` (正确) |
| 逃逸: Bash 工具 | **低风险** -- PostToolUse(Write\|Edit) 不覆盖 Bash |
| v5.0.4 Delta | 不变（v5.1 已修复逻辑反转） |

#### SA-3: 必须返回 JSON 信封

| 维度 | 评估 |
|------|------|
| L2 保障 | `_post_task_validator.py` V1 (L77-L97): 缺失信封/status 时阻断 |
| Phase 特定字段 | Phase 4: 5 必需字段; Phase 5: 3 必需字段; Phase 6: 3 必需字段 |
| 3 策略解析 | `_envelope_parser.py` extract_envelope: JSON 块提取/全文解析/宽松搜索 |
| v5.0.4 Delta | 不变 |

#### SA-4: 背景 Agent 产出必须 Write 到文件

| 维度 | 评估 |
|------|------|
| L2 保障 | **无** -- 仅 L3 prompt 指令 |
| 风险 | **低** -- 背景 Agent 全文灌入主窗口影响可读性但不影响正确性 |
| v5.0.4 Delta | 不变 |

#### SA-5: 文件所有权 ENFORCED (并行模式)

| 维度 | 评估 |
|------|------|
| L2 保障 | `_post_task_validator.py` V4 (L410-L549): 并行合并守卫 |
| 检查内容 | 冲突检测 + 范围验证 + 类型检查 |
| 触发条件 | Phase 5 + output 含 "worktree.*merge" |
| v5.0.4 Delta | 不变 |

#### SA-6: 背景 Agent 必须接受 L2 验证

| 维度 | 评估 |
|------|------|
| L2 保障 | `post-task-validator.sh` L22-25: 删除了 `is_background_agent && exit 0` 旁路 |
| PreToolUse | `check-predecessor-checkpoint.sh` L49-L58: 保留前驱 checkpoint 检查 |
| PostToolUse | 背景 Agent 完成后触发 V1+V2+V3 全套验证 |
| v5.0.4 Delta | 不变（v5.1 已修复） |

### 6.2 JSON 信封验证深度

`_post_task_validator.py` V1 的信封验证覆盖：

```
必需字段验证链:
  envelope 存在 → status 字段存在 → status 值合法 → phase 特定字段存在
  → Phase 4 warning 阻断
  → Phase 5 zero_skip_check.passed=true
  → Phase 5 TDD metrics
  → Phase 4/6 artifacts 非空
  → Phase 4 test_pyramid 地板
  → Phase 4 test_traceability 地板
  → Phase 4 change_coverage 地板
  → Phase 4 sad_path 比例
```

### 6.3 评分: 80/100

扣分明细:
- -10: SA-1 无 L2 保障（平台限制，但风险客观存在）
- -5: SA-4 无 L2 保障
- -3: Bash 工具逃逸路径（SA-2）
- -2: 文件所有权仅在并行合并时验证，非实时拦截

---

## 7. 规约-代码一致性审查

### 7.1 CLAUDE.md 逐条法则交叉验证

#### 状态机硬约束 (7 条)

| # | 法则 | L2 实现 | 一致性 |
|---|------|---------|:------:|
| SM-1 | Phase 顺序不可违反 | `check-predecessor-checkpoint.sh` L251+L277-L286: 模式感知前驱链 + deny() | PASS |
| SM-2 | 三层门禁联防 | hooks.json: 1 PreToolUse + 2 PostToolUse | PASS |
| SM-3 | 模式路径互斥 | `check-predecessor-checkpoint.sh` L218-L249: get_predecessor_phase() + L254-L274: 非法 Phase 拒绝 | PASS |
| SM-4 | 降级条件严格 | 无 L2 (仅 L3 prompt) | PASS (文档未声称 L2) |
| SM-5 | Phase 4 不接受 warning | `_post_task_validator.py` L157-L160: 确定性阻断 | PASS |
| SM-6 | Phase 5 zero_skip_check | `_post_task_validator.py` L124-L130 + `check-predecessor-checkpoint.sh` L365-L378 | PASS |
| SM-7 | 归档需用户确认 | 无 L2 (L3 AskUserQuestion) | PASS (设计如此) |

#### TDD Iron Law (5 条)

| # | 法则 | L2 实现 | 一致性 |
|---|------|---------|:------:|
| TDD-1 | 先测试后实现 | `unified-write-edit-check.sh` CHECK 1 L124-L152 | PASS |
| TDD-2 | RED 必须失败 | 主线程 Bash (exit_code != 0) | PASS |
| TDD-3 | GREEN 必须通过 | 主线程 Bash (exit_code == 0) | PASS |
| TDD-4 | 测试不可变 | `unified-write-edit-check.sh` CHECK 1 L144-L149 | PASS |
| TDD-5 | REFACTOR 回归保护 | 主线程 Bash git checkout (L3 协议驱动) | PASS (文档未声称 L2) |

#### 代码质量硬约束 (7 条)

| # | 法则 | L2 实现 | 一致性 |
|---|------|---------|:------:|
| CQ-1 | 禁止 TODO/FIXME/HACK | `unified-write-edit-check.sh` CHECK 2 | PASS |
| CQ-2 | 禁止恒真断言 | `unified-write-edit-check.sh` CHECK 3 | PASS |
| CQ-3 | Anti-Rationalization "10 种 excuse" | `_post_task_validator.py` V2: 22 个模式 | **FAIL** (文档滞后) |
| CQ-4 | 代码约束 | CHECK 4 + V3 双重保障 | PASS |
| CQ-5 | Test Pyramid 地板 | V1 L172-L234 | PASS |
| CQ-6 | Change Coverage ≥ 80% | V1 L259-L273 | PASS |
| CQ-7 | Sad Path ≥ 20%/类型 | V1 L275-L303 | PASS |

#### 子 Agent 约束 (6 条)

| # | 法则 | L2 实现 | 一致性 |
|---|------|---------|:------:|
| SA-1 | 禁止读取计划文件 | 无 L2 | PASS (文档未声称 L2) |
| SA-2 | 禁止修改 openspec/checkpoint | CHECK 0 | PASS |
| SA-3 | 必须返回 JSON 信封 | V1 | PASS |
| SA-4 | 背景 Agent 产出 Write 到文件 | 无 L2 | PASS (文档未声称 L2) |
| SA-5 | 文件所有权 ENFORCED | V4 | PASS |
| SA-6 | 背景 Agent 接受 L2 验证 | post-task-validator.sh 删除旁路 | PASS |

#### 发版纪律 (4 条)

| # | 法则 | 实现 | 一致性 |
|---|------|------|:------:|
| RD-1 | 唯一入口 bump-version.sh | `scripts/bump-version.sh` | PASS |
| RD-2 | 禁止散弹式修改 | 无强制机制 | PASS (文档未声称 L2) |
| RD-3 | 同步范围 4 文件 | bump-version.sh 更新 4 文件 | PASS |
| RD-4 | 验证闭环 | bump-version.sh 读回验证 | PASS |

### 7.2 不一致项汇总

| # | 不一致项 | 严重度 | 说明 |
|---|---------|:------:|------|
| 1 | CQ-3: "10 种" vs 22 种 | 低 | 积极超额，但违反 Single Source of Truth |
| 2 | 幽灵规则未声明 | 低 | 10 条 L2 强制规则在 CLAUDE.md 中未声明（见附录 A） |

### 7.3 评分: 85/100

扣分明细:
- -7: CQ-3 文档声称与实现数量不一致
- -5: 10 条幽灵规则未在 CLAUDE.md 中声明
- -3: CLAUDE.md 未声明需求路由的 L2 实现细节（routing_overrides 机制）

---

## 8. hooks.json 结构审计

### 8.1 注册清单

```json
{
  "PreToolUse": [
    {"matcher": "^Task$", "command": "check-predecessor-checkpoint.sh", "timeout": 30}
  ],
  "PostToolUse": [
    {"matcher": "^Task$", "command": "post-task-validator.sh", "timeout": 150},
    {"matcher": "^(Write|Edit)$", "command": "unified-write-edit-check.sh", "timeout": 15}
  ],
  "PreCompact": [{"command": "save-state-before-compact.sh", "timeout": 15}],
  "SessionStart": [
    {"command": "scan-checkpoints-on-start.sh", "timeout": 15, "async": true},
    {"command": "check-skill-size.sh", "timeout": 15},
    {"matcher": "compact", "command": "reinject-state-after-compact.sh", "timeout": 15}
  ]
}
```

### 8.2 废弃文件隔离验证

| 废弃文件 | hooks.json 注册 | 文件标记 | 状态 |
|----------|:--------------:|---------|:----:|
| anti-rationalization-check.sh | NO | 第 2 行 DEPRECATED | PASS |
| code-constraint-check.sh | NO | 第 2 行 DEPRECATED | PASS |
| validate-json-envelope.sh | NO | 第 2 行 DEPRECATED | PASS |
| banned-patterns-check.sh | NO | 第 2 行 DEPRECATED (v5.1) | PASS |
| assertion-quality-check.sh | NO | 第 2 行 DEPRECATED (v5.1) | PASS |
| write-edit-constraint-check.sh | NO | 第 2 行 DEPRECATED (v5.1) | PASS |

6 个废弃文件均正确标记且未在 hooks.json 中注册。

### 8.3 超时配置合理性

| Hook | Timeout | 评估 |
|------|--------:|------|
| check-predecessor-checkpoint.sh | 30s | 合理 -- python3 + git 操作 |
| post-task-validator.sh | 150s | 合理 -- 5 个 Validator + 潜在 typecheck |
| unified-write-edit-check.sh | 15s | 合理 -- 大部分为纯 bash/grep，python3 仅在 Phase 5 |

---

## 9. Delta 分析 (v5.0.4 → v5.1.1)

### 9.1 修复追踪

| v5.0.4 建议 | 优先级 | v5.1.1 状态 | 说明 |
|------------|:------:|:----------:|------|
| TDD-5 REFACTOR 回滚 L2 兜底 | P1 | **未修复** | 仍依赖 L3 协议 |
| SA-1 禁止读取计划文件 | P1 | **未修复** | Claude Code 平台限制 |
| 反合理化模式扩展 | P2 | **未修复** | 22 模式未增加 |
| CLAUDE.md "10 种" 更新 | P2 | **未修复** | 仍写 "10 种" |
| .tdd-stage 崩溃残留清理 | P3 | **未修复** | Recovery 协议未更新 |
| 测试文件名 `*_tests/*` 补充 | P3 | **未修复** | 仍缺少 |
| 废弃文件整理到 `_deprecated/` | P4 | **未修复** | 仍在 scripts/ 根目录 |

### 9.2 新增能力

v5.0.4 → v5.1.1 期间无新增 L2 能力。代码实态与 v5.0.4 报告时完全一致。

### 9.3 退化检查

**未发现退化**。所有 v5.0.4 报告确认的 L2 机制在 v5.1.1 中均保持正常。

### 9.4 评分变化

| 维度 | v5.0.4 | v5.1.1 | Delta | 原因 |
|------|:------:|:------:|:-----:|------|
| TDD 阶段隔离确定性 | 82 | 82 | 0 | 无变化 |
| openspec 路径保护确定性 | 90 | 90 | 0 | 无变化 |
| 代码质量门禁覆盖度 | 92 | 92 | 0 | 无变化 |
| Anti-Rationalization 覆盖度 | 78 | 78 | 0 | 无变化 |
| 子 Agent 约束执行力 | 80 | 80 | 0 | 无变化 |
| 规约-代码一致性 | 84 | 85 | +1 | 本次审计更完整的交叉验证确认一致性 |
| **总体合规评分** | **84** | **85** | **+1** | |

---

## 10. 修复建议（按优先级排序）

### P1: TDD-5 REFACTOR 回滚 L2 兜底

**风险**: 中
**当前状态**: 主线程执行 `git checkout` 由 L3 协议驱动，若遗漏则无 L2 兜底
**建议**: 在 `_post_task_validator.py` V1 Phase 5 检查中增加：当 `tdd_metrics.refactor_reverted_count > 0` 时，验证 git diff 确认回滚是否实际执行。或在主线程 TDD 流程中硬编码"REFACTOR Bash 失败 -> 自动 `git stash`"逻辑。

### P1: SA-1 禁止读取计划文件

**风险**: 中
**当前状态**: Claude Code 不支持 PreToolUse(Read) Hook
**建议**:
1. 等待 Claude Code 支持 PreToolUse(Read) 后立即添加
2. 临时方案：在 PostToolUse(Task) 中检查子 Agent output 是否引用了计划文件路径或内容摘要（启发式检测）

### P2: CLAUDE.md CQ-3 文档更新

**风险**: 低
**当前状态**: 声称"10 种 excuse 模式"，实际 22 种
**建议**: 更新第 28 行为 "22 种加权 excuse 模式匹配（11 EN + 11 CN）-> status 强制降级为 blocked"

### P2: 反合理化模式扩展

**风险**: 低-中
**建议**: 增加以下 8 个高价值模式到 `_post_task_validator.py` V2 和废弃文件（保持一致）：
```python
# 时间/环境/依赖借口（权重 2）
(2, r"due\s+to\s+(time|resource|environment)\s+(constraints?|limitations?)"),
(2, r"blocked\s+by\s+(external|upstream|dependency)"),
(2, r"environment\s+(not|isn't)\s+(configured|ready|available)"),
(2, r"simplified\s+(the\s+)?(approach|implementation|design)\s+(to|for)"),
# 中文时间/环境借口（权重 2）
(2, r"(?:由于|因为)(?:时间|资源|环境)(?:限制|不足|约束)"),
(2, r"(?:被|受)(?:外部|上游|依赖)(?:阻塞|限制)"),
(2, r"(?:简化|精简)了?(?:方案|实现|设计)"),
(2, r"(?:环境|配置)(?:未|没有?)(?:就绪|准备好|配置好)"),
```

### P3: .tdd-stage 崩溃残留清理

**风险**: 低
**建议**: 在 `autopilot-recovery/SKILL.md` Step 2.1 后增加：
```bash
rm -f openspec/changes/*/context/.tdd-stage 2>/dev/null
```

### P3: 测试文件名模式补充

**风险**: 低
**建议**: 在 `unified-write-edit-check.sh` L134 增加 `*_tests/*`：
```bash
*/__tests__/* | */test/* | */tests/* | */spec/* | *_test/* | *_spec/* | *_tests/*) IS_TEST_FILE="yes" ;;
```

### P3: 幽灵规则文档化

**风险**: 低
**建议**: 在 CLAUDE.md 中补充声明 10 条幽灵规则（详见附录 A），保持 Single Source of Truth 完整性。

### P4: 废弃文件整理

**风险**: 极低
**建议**: 将 6 个 DEPRECATED 文件移至 `scripts/_deprecated/` 子目录，减少目录杂乱度。

---

## 附录 A: 幽灵规则清单（有 L2 强制但 CLAUDE.md 未声明）

| # | Hook/脚本 | 强制内容 | 应声明位置 |
|---|----------|---------|-----------|
| 1 | `_post_task_validator.py` L106 | Phase 4 `sad_path_counts` 为必需字段 | CLAUDE.md CQ-7 |
| 2 | `_post_task_validator.py` L132-L146 | Phase 5 TDD metrics (red_violations=0, cycles>=1) | CLAUDE.md TDD |
| 3 | `_post_task_validator.py` L236-L257 | Phase 4 test_traceability >=80% | CLAUDE.md CQ 新条目 |
| 4 | `_post_task_validator.py` L410-L549 | 并行合并守卫 (冲突+范围+类型检查) | CLAUDE.md SA-5 补充 |
| 5 | `_post_task_validator.py` L556-L631 | Phase 1 决策格式验证 (options>=2, recommended) | CLAUDE.md 新条目 |
| 6 | `check-predecessor-checkpoint.sh` L401-L434 | Phase 5 wall-clock 超时 | CLAUDE.md SM 新条目 |
| 7 | `check-predecessor-checkpoint.sh` L381-L397 | Phase 6 tasks.md 全 [x] | CLAUDE.md SM 新条目 |
| 8 | `unified-write-edit-check.sh` CHECK 0 | 子 Agent 状态隔离（保护路径阻断） | CLAUDE.md SA-2 (已部分声明) |
| 9 | `unified-write-edit-check.sh` CHECK 1 | TDD 阶段隔离（RED/GREEN 文件类型限制） | CLAUDE.md TDD-1/TDD-4 (已部分声明) |
| 10 | `_post_task_validator.py` L176-L213 | routing_overrides 动态阈值调整 | CLAUDE.md 需求路由 |

---

## 附录 B: L2 确定性覆盖率计算

```
总规则数 = 40 (7 SM + 5 TDD + 7 CQ + 6 SA + 4 RD + 4 Routing + 4 Event + 3 GUI)

L2 确定性保障 = 34
  SM: 5 (SM-1,2,3,5,6)
  TDD: 4 (TDD-1,2,3,4)
  CQ: 7 (全部)
  SA: 4 (SA-2,3,5,6)
  RD: 3 (RD-1,3,4)
  Routing: 4 (全部通过 routing_overrides)
  Event: 4 (全部通过 emit 脚本)
  GUI: 3 (全部通过 store)

仅 L3 AI 自觉 = 1 (SM-7 归档确认)

无保障 = 5 (SM-4, TDD-5, SA-1, SA-4, RD-2)

确定性覆盖率 = 34 / 40 = 85.0%
有效覆盖率 = (34 + 1) / 40 = 87.5%
```

---

## 附录 C: 审计涉及文件

### Hook 脚本（活跃）
- `scripts/unified-write-edit-check.sh` (265 行) -- PostToolUse(Write|Edit) 统一入口
- `scripts/post-task-validator.sh` (36 行) -- PostToolUse(Task) 入口
- `scripts/_post_task_validator.py` (634 行) -- 5 合 1 验证器
- `scripts/check-predecessor-checkpoint.sh` (437 行) -- PreToolUse(Task) 门禁
- `scripts/_hook_preamble.sh` (39 行) -- 共享前导
- `scripts/_common.sh` (356 行) -- 共享工具函数

### Hook 脚本（已废弃，正确未注册）
- `scripts/anti-rationalization-check.sh` (151 行)
- `scripts/code-constraint-check.sh` (82 行)
- `scripts/validate-json-envelope.sh` (225 行)
- `scripts/banned-patterns-check.sh` (66 行)
- `scripts/assertion-quality-check.sh` (83 行)
- `scripts/write-edit-constraint-check.sh` (151 行)

### 配置
- `hooks/hooks.json` (80 行)

### 规约定义
- `CLAUDE.md` (65 行, Single Source of Truth)

### 基线报告
- `docs/reports/v5.0.4/compliance-audit.md` (593 行)
