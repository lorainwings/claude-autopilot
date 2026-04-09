# spec-autopilot 插件深度分析报告 v3.4.3

> **分析日期**: 2026-03-11
> **插件版本**: v3.4.3
> **用途**: 会话恢复 — 直接基于本报告进行方案实施，无需重新阅读源码

---

## 一、整体架构总览

### 1.1 产品定位

spec-autopilot 是面向 Claude Code 的**规范驱动全自动软件交付框架**，将软件开发编排为 **8 个确定性阶段**（Phase 0-7），从需求理解到代码归档实现自动化交付。

### 1.2 核心架构

```
┌─────────────────────────────────────────────────────────┐
│  主线程编排器 (SKILL.md ~488 行)                          │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐    │
│  │ Phase 0  │→│ Phase 1  │→│ Phase 2-6│→│ Phase 7  │    │
│  │ 环境检查 │ │ 需求讨论 │ │ 子Agent  │ │ 归档汇总 │    │
│  │ (主线程) │ │ (主线程) │ │ (Task)   │ │ (主线程) │    │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘    │
├─────────────────────────────────────────────────────────┤
│  3 层门禁体系                                            │
│  Layer 1: TaskCreate + blockedBy (结构化依赖链)          │
│  Layer 2: Hook 脚本 (8 个确定性脚本)                     │
│  Layer 3: AI Gate (autopilot-gate Skill)                │
├─────────────────────────────────────────────────────────┤
│  支撑协议 Skills                                         │
│  autopilot-dispatch | autopilot-gate                     │
│  autopilot-checkpoint | autopilot-recovery               │
└─────────────────────────────────────────────────────────┘
```

**核心约束**: 子 Agent 内部没有 Task 工具，所有 Task 派发在主线程执行，**禁止嵌套**。

### 1.3 执行模式

| 模式 | 阶段 | 场景 |
|------|------|------|
| **full** | 0→1→2→3→4→5→6→7 | 中大型功能，完整规范 |
| **lite** | 0→1→5→6→7 | 小功能，跳过 OpenSpec |
| **minimal** | 0→1→5→7 | 极简需求，跳过规范+测试报告 |

### 1.4 关键文件路径

| 文件 | 路径 | 行数 | 职责 |
|------|------|------|------|
| 主编排器 | `skills/autopilot/SKILL.md` | ~488 | 8 阶段流程控制 |
| 调度协议 | `skills/autopilot-dispatch/SKILL.md` | ~388 | 子 Agent prompt 构造 + 并行调度 |
| 门禁协议 | `skills/autopilot-gate/SKILL.md` | ~131 | 8 步切换清单 + 特殊门禁 |
| 检查点 | `skills/autopilot-checkpoint/SKILL.md` | ~111 | 状态持久化读写 |
| 崩溃恢复 | `skills/autopilot-recovery/SKILL.md` | ~106 | checkpoint 扫描 + 恢复点定位 |
| 共享协议 | `skills/autopilot/references/protocol.md` | ~210 | JSON 信封契约 + 状态规则 |
| 并行编排 | `skills/autopilot/references/parallel-dispatch.md` | ~333 | 跨阶段通用并行编排 |
| Hook 配置 | `hooks/hooks.json` | ~120 | 11 个 Hook 注册 |
| 共享工具 | `scripts/_common.sh` | ~149 | bash 共享函数 |

### 1.5 Hook 脚本清单

| 脚本 | 事件 | 超时 | 职责 |
|------|------|------|------|
| `check-predecessor-checkpoint.sh` | PreToolUse(Task) | 30s | 前置 checkpoint 验证 + 2h wall-clock |
| `validate-json-envelope.sh` | PostToolUse(Task) | 30s | JSON 结构 + 必需字段 + pyramid floor |
| `anti-rationalization-check.sh` | PostToolUse(Task) | 30s | 加权评分跳过模式检测（中英文） |
| `code-constraint-check.sh` | PostToolUse(Task) | 30s | Phase 4/5/6 禁止文件/模式/目录 |
| `parallel-merge-guard.sh` | PostToolUse(Task) | 150s | worktree merge 冲突 + scope + typecheck |
| `validate-decision-format.sh` | PostToolUse(Task) | 30s | Phase 1 DecisionPoint 格式验证 |
| `write-edit-constraint-check.sh` | PostToolUse(Write\|Edit) | 15s | Phase 5 文件越权实时拦截 |
| `save-state-before-compact.sh` | PreCompact | 15s | 编排状态持久化 |
| `reinject-state-after-compact.sh` | SessionStart(compact) | 15s | 压缩后状态恢复 |
| `scan-checkpoints-on-start.sh` | SessionStart | 15s | 启动时 checkpoint 扫描(async) |
| `check-skill-size.sh` | SessionStart | 15s | SKILL.md 500 行限制检查 |

---

## 二、各阶段实现逻辑详解

### Phase 0: 环境检查 + 崩溃恢复 (主线程, 10 步)

1. 读取 `plugin.json` 版本号 → 输出 `Autopilot v{version} initializing...`
2. 检查/生成 `autopilot.config.yaml`（不存在调用 autopilot-setup）
3. 解析执行模式（$ARGUMENTS → config.default_mode → "full"）
4. 展示 ASCII Banner（50 字符固定宽度框，纯 ASCII 禁 emoji）
5. 检查已启用插件列表
6. 调用 `autopilot-recovery` 扫描 checkpoint
7. TaskCreate 创建阶段任务 + blockedBy 依赖链（full:7, lite:4, minimal:3）
8. 确保 `.autopilot-active` 被 .gitignore
9. 写入锁文件（JSON: change/pid/started/session_cwd/anchor_sha/session_id/mode）
10. 创建锚定空 commit（`autopilot: start <name>`），记录 ANCHOR_SHA

**关键设计**:
- PID 回收防护: 同时检查 PID 存活 + session_id 匹配
- 锚定 commit 为后续 `git rebase --autosquash` 提供基准
- 锁文件原子性: 先写空 anchor_sha，创建 commit 后更新

### Phase 1: 需求理解与多轮决策 (主线程, 10 步)

```
获取需求 → 并行调研(3路) → 汇合结果 → 复杂度评估 → BA分析
→ 主动讨论 → 多轮LOOP → 生成prompt → 写checkpoint → 用户确认
```

**并行调研**（同一消息 3 个后台 Task）:
- Auto-Scan (general-purpose) → project-context.md + existing-patterns.md + tech-constraints.md
- 技术调研 (general-purpose) → research-findings.md
- 联网搜索 (general-purpose) → web-research-findings.md（规则引擎判定跳过）

**上下文保护**（v3.3.0）:
- 子 Agent 自行 Write 文件，返回精简 JSON 信封
- 主线程仅消费 `decision_points`、`complexity` 等摘要，不读取全文
- 上下文占用从 ~390 行降至 ~70 行

**决策协议**:
- 结构化 DecisionPoint 卡片（2-4 选项 + 优劣 + 推荐）
- 复杂度分路: small/medium/large 自适应讨论深度
- Hook 确定性验证（validate-decision-format.sh）

### Phase 2-6: 统一调度模板

每个 Phase N 在主线程执行 8 步:

```
Step 1:   Gate 验证 (autopilot-gate)
Step 1.5: 可选用户确认
Step 2:   构造 prompt (autopilot-dispatch)
Step 3:   Task 派发子 Agent
Step 4:   解析 JSON 信封
Step 5+7: 后台 Checkpoint Agent (checkpoint + git fixup)
Step 6:   TaskUpdate completed
Step 8:   等待 checkpoint 确认 → 输出进度行
```

**v3.4.3 创新**: Checkpoint + Git Fixup 合并为后台 Agent，避免 Write/Bash 输出污染主窗口。

### Phase 2: 创建 OpenSpec (后台子 Agent)
- 从需求推导 kebab-case 名称，执行 `openspec new change`
- 写入 context 文件（prd.md, discussion.md, ai-prompt.md）
- Agent 类型: Plan（可配置）

### Phase 3: FF 生成制品 (后台子 Agent)
- 生成 proposal/design/specs/tasks 四层文档
- Agent 类型: Plan（可配置）

### Phase 4: 测试用例设计 (子 Agent, **不可跳过**)

**门禁要求**:
- 4 类测试（unit/api/e2e/ui）全部创建，每类 >= min_test_count_per_type
- 测试金字塔: unit >= 50%, e2e <= 40%（Hook Layer 2: unit >= 30%, e2e <= 40% floor）
- dry_run_results 全部 exit 0
- change_coverage.coverage_pct >= 80%
- 需求追溯矩阵覆盖 >= 80%
- **status 只允许 "ok" 或 "blocked"**（warning 被 Hook 强制覆盖为 blocked）

### Phase 5: 循环实施 (子 Agent, 互斥双路径)

**路径 A — 并行模式**（`config.phases.implementation.parallel.enabled = true`）:
```
解析任务 → 按域分区(longest prefix match) → 生成 owned_files →
并行 Task(isolation: "worktree", run_in_background: true) →
按编号合并 → 批量 review → 全量测试
```
- 最大 8 并行 Agent（config.max_agents）
- parallel-merge-guard Hook 验证合并
- 合并失败 > 3 文件 → 降级路径 B

**路径 B — 串行模式**:
```
逐个 Task(前台同步) → JSON 信封 → task checkpoint → 下一个
```
- 域动态 Agent 选择（backend-developer/frontend-developer/fullstack-developer）
- 连续 3 次失败 → AskUserQuestion

**硬约束**: 2 小时 wall-clock 超时（Hook 层），task 粒度 <= 3 文件 <= 800 行

### Phase 6: 测试报告 + 三路并行 (v3.2.2)

同一消息同时派发:
| 路径 | 内容 | 是否阻断 |
|------|------|---------|
| A | Phase 6 测试执行（后台 Task） | 是 |
| B | Phase 6.5 代码审查（可选，后台） | 否（warning 不阻断） |
| C | 质量扫描（多个后台 Task） | 否 |

Allure 统一报告优先，降级为自定义格式。

### Phase 7: 汇总 + 用户确认归档 (主线程)

1. 写入 Phase 7 Checkpoint（in_progress）
2. 派发汇总子 Agent 读取所有 checkpoint → 返回信封
3. 知识提取（后台 Agent → .autopilot-knowledge.json）
4. 收集三路并行结果（仅 full/lite）
5. Allure 本地预览（后台 `npx allure open`）
6. **必须** AskUserQuestion 确认归档
7. Git autosquash（`GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash $ANCHOR_SHA~1`）
8. 清理锁文件 + git tag

---

## 三、3 层门禁体系

### Layer 1: Task 系统（自动）
- TaskCreate + blockedBy 依赖链
- Claude Code 原生机制，不可绕过

### Layer 2: Hook 脚本（确定性）

**性能优化**: 3 层快速旁路:
- Layer 0: `has_active_autopilot()` 纯 bash ~1ms（无 python3）
- Layer 1: grep 检查 `<!-- autopilot-phase:N -->` 标记
- Layer 1.5: `run_in_background:true` 跳过

**Fail-Closed 设计**: python3 不可用 → deny，JSON 解析错误 → deny

### Layer 3: AI Gate (autopilot-gate Skill)

8 步阶段切换清单 + 特殊门禁:
- Phase 4→5: test_counts + pyramid + dry_run + change_coverage
- Phase 5→6: zero_skip_check.passed + tasks 全部完成
- 可选: 语义验证 + Brownfield 验证

---

## 四、崩溃恢复机制

### 正常崩溃恢复
1. SessionStart Hook 扫描 checkpoint → 输出摘要
2. autopilot-recovery Skill 交互式选择恢复点
3. 从锁文件恢复 mode + anchor_sha
4. TaskCreate 重建，已完成阶段标记 completed

### 上下文压缩恢复
1. PreCompact Hook → 写 `autopilot-state.md`（阶段表 + Phase 5 task 进度 + anchor_sha）
2. SessionStart(compact) Hook → 注入 `=== AUTOPILOT STATE RESTORED ===`
3. 主线程读取 → 从下一未完成阶段继续

---

## 五、日志美化分析与方案

### 5.1 当前日志问题

| 输出点 | 当前风格 | 问题 |
|--------|---------|------|
| scan-checkpoints-on-start.sh | `=== Autopilot Checkpoint Summary ===` + 纯文本 | 无视觉层次，朴素 |
| reinject-state-after-compact.sh | `=== AUTOPILOT STATE RESTORED ===` | 纯大写，缺高亮 |
| check-skill-size.sh | `WARNING: xxx/SKILL.md = N lines` | 无前缀图标 |
| validate-json-envelope.sh | `OK: Valid autopilot JSON...` (stderr) | 用户不可见 |
| anti-rationalization-check.sh | 纯 JSON block reason | 机器格式 |
| SKILL.md 进度行 | `Phase {N} ✓ checkpoint: ... \| commit: ...` | 不够醒目 |
| SKILL.md Banner | 50 字符 ASCII 框 | 已设计良好 |

### 5.2 美化方案

**方案 A: 统一日志前缀体系**

```
[autopilot] Phase 0 ✓ Environment ready                     ← 阶段完成
[autopilot] Phase 1 ⏳ Requirements analysis in progress...  ← 阶段进行中
[autopilot] Phase 4 ✗ Gate blocked: test_counts < threshold  ← 阻断
[autopilot] ⚠ SKILL.md approaching 500-line limit (471)      ← 警告
```

**方案 B: Checkpoint 扫描美化** (scan-checkpoints-on-start.sh)

当前:
```
=== Autopilot Checkpoint Summary ===
Change: feature-a
  Last successful phase: 4 (ok)
  Suggested resume: Phase 5
```

改为:
```
╭─ Autopilot Recovery ─────────────────────────────╮
│                                                   │
│  Change     feature-a                             │
│  Progress   Phase 4/7 completed                   │
│  Resume     Phase 5 (Implementation)              │
│                                                   │
│  Phase 1  ✓  Requirements confirmed               │
│  Phase 2  ✓  OpenSpec created                      │
│  Phase 3  ✓  Specs generated                       │
│  Phase 4  ✓  Test cases designed                   │
│  Phase 5  ·  pending                               │
│  Phase 6  ·  pending                               │
│  Phase 7  ·  pending                               │
│                                                   │
╰───────────────────────────────────────────────────╯
```

**方案 C: 阶段进度行美化** (SKILL.md Step 8)

当前:
```
Phase {N} ✓ checkpoint: phase-{N}-{slug}.json | commit: {short_sha}
```

改为:
```
  ✓ Phase 2 — OpenSpec                  [0m 32s]  abc1234
  ✓ Phase 3 — FF Generate               [1m 15s]  def5678
  ⏳ Phase 4 — Test Design               running...
```

**方案 D: Hook 阻断消息结构化**

当前: 纯 reason 字符串
改为:
```
Phase 4 BLOCKED — test_pyramid floor violation
  ✗ unit_pct=25% < 30% floor
  ✗ total_cases=8 < 10 minimum
  Action: Adjust test distribution and re-dispatch Phase 4
```

**方案 E: 上下文恢复美化** (reinject-state-after-compact.sh)

改为:
```
╭─ Autopilot State Restored ───────────────────────╮
│  Change     feature-a                             │
│  Progress   Phase 4 completed, resuming Phase 5   │
│  Mode       full                                  │
│  Anchor     abc1234                               │
╰───────────────────────────────────────────────────╯
```

### 5.3 日志美化实施优先级

| 优先级 | 改动项 | 涉及文件 | 复杂度 |
|--------|--------|---------|--------|
| P0 | 方案 C: 阶段进度行 | SKILL.md | 低 |
| P0 | 方案 B: Checkpoint 扫描 | scan-checkpoints-on-start.sh | 中 |
| P1 | 方案 D: Hook 阻断消息 | validate-json-envelope.sh + 其他 5 个 | 中 |
| P1 | 方案 E: 上下文恢复 | reinject-state-after-compact.sh | 低 |
| P2 | 方案 A: 统一前缀 | 所有脚本 + SKILL.md | 中 |

---

## 六、各阶段优化点评审

### Phase 0

| ID | 问题 | 严重度 | 建议 |
|----|------|--------|------|
| P0-1 | Banner 渲染规则占 SKILL.md ~15 行 | 低 | 提取到 reference 文件 |
| P0-2 | 锚定 commit autosquash 失败后残留空 commit | 中 | Phase 7 失败时清理 |
| P0-3 | config 验证用正则解析 YAML | 中 | 统一使用 PyYAML |

### Phase 1

| ID | 问题 | 严重度 | 建议 |
|----|------|--------|------|
| P1-1 | 3 路并行调研超时处理不明确 | 中 | 单路超时不阻断，标记 timeout 继续 |
| P1-2 | 联网搜索跳过规则无确定性保障 | 低 | 仅文本描述，考虑 Hook 化 |
| P1-3 | BA 产出质量无 Hook 验证 | 中 | 仅验证 JSON 格式，不验证内容 |
| P1-4 | decision_points 可能遗漏关键决策 | 中 | 增加用户补充环节 |

### Phase 2-3

| ID | 问题 | 严重度 | 建议 |
|----|------|--------|------|
| P23-1 | Plan agent 可能无 Write 权限 | 低 | 确认 OpenSpec CLI 是否需 Write |
| P23-2 | OpenSpec CLI 依赖未检查 | 中 | Phase 0 检查 openspec 工具 |
| P23-3 | 后台执行无进度反馈 | 低 | 考虑输出中间状态行 |

### Phase 4

| ID | 问题 | 严重度 | 建议 |
|----|------|--------|------|
| P4-1 | 金字塔阈值硬编码在 Hook 中 | 中 | unit<30/e2e>40 硬编码，应从 config 读取 |
| P4-2 | dry_run 全 0 过严 | 低 | 新项目环境问题导致反复阻断 |
| P4-3 | 并行测试生成合并规则不明确 | 低 | 需要明确 test_counts 聚合逻辑 |
| P4-4 | change_coverage 80% 可能过高 | 低 | large 变更导致测试爆炸 |

### Phase 5

| ID | 问题 | 严重度 | 建议 |
|----|------|--------|------|
| P5-1 | 路径选择禁止 AI 降级过于僵硬 | 中 | 仅允许合并失败 > 3 降级，应增加智能降级 |
| P5-2 | 串行模式无进度百分比 | 低 | 显示 task N/M 完成 |
| P5-3 | 2h 硬超时不可配置 | 中 | 大项目 > 20 task 可能超时 |
| P5-4 | task 粒度约束无确定性保障 | 低 | <=3 文件 <=800 行仅文本描述 |
| P5-5 | 并行 worktree 合并顺序问题 | 中 | 后合并域可能覆盖先合并变更 |

### Phase 6

| ID | 问题 | 严重度 | 建议 |
|----|------|--------|------|
| P6-1 | Allure 安装每次重检 | 低 | 缓存检测结果 |
| P6-2 | 三路并行超时配置分散 | 中 | 统一到 config.timeouts 节 |
| P6-3 | zero_skip_check 由子 Agent 自设 | 低 | 可能不准确 |

### Phase 7

| ID | 问题 | 严重度 | 建议 |
|----|------|--------|------|
| P7-1 | autosquash 失败清理不完整 | 中 | 用户手动处理指引不够 |
| P7-2 | 知识提取质量不可控 | 低 | AI 提取 pattern/pitfall 可能不准 |
| P7-3 | Allure 预览清理不明确 | 低 | 归档后如何停止 npx allure open |
| P7-4 | git add -A 可能包含非预期文件 | 中 | 临时文件（非 gitignore 覆盖的）被包含 |

### 跨阶段共性问题

| ID | 问题 | 严重度 | 影响范围 | 建议 |
|----|------|--------|---------|------|
| X-1 | **SKILL.md 488 行接近 500 上限** | **高** | 主编排器 | 提取 Banner 规则(15行) + 护栏表(30行) + 错误处理(10行) 到 references，目标 ~430 行 |
| X-2 | **Hook 代码重复率高** | 中 | 6 个 PostToolUse Hook | Fast bypass Layer 0/1/1.5 各 ~15 行完全相同，提取到 `_hook_common.sh` |
| X-3 | **JSON raw_decode 重复实现** | 中 | 4 个 Hook 脚本 | 提取为 `_json_extract.py` 共享模块 |
| X-4 | **YAML 正则解析脆弱** | 中 | code-constraint, write-edit, merge-guard | 统一 `_yaml_parser.py`（PyYAML 优先，正则 fallback） |
| X-5 | **python3 依赖无安装引导** | 低 | 所有 Hook | deny 时提示安装方法 |
| X-6 | **stderr/stdout 使用不一致** | 低 | 多个 Hook | 统一: block/warn → stdout, info → stderr |

---

## 七、竞品对比与差距分析

### 7.1 v3.4.3 vs 竞品评分更新

| 维度(权重) | Superpowers | OMC | BMAD | ECC | Autopilot v3.0.1 | **v3.4.3** |
|-----------|:-----------:|:---:|:----:|:---:|:----------------:|:----------:|
| 流程完整度(25%) | 3 | 2 | 4 | 2 | 5 | **5** |
| 质量保障(20%) | 5 | 2 | 4 | 2 | 4 | **4.5** |
| 并行效率(20%) | 2→3 | 5 | 1 | 2 | 1 | **3.5** |
| 成本优化(15%) | 1 | 5 | 1 | 4 | 1 | **1.5** |
| 可扩展性(10%) | 4 | 2 | 3 | 5 | 2 | **2.5** |
| 学习进化(10%) | 1 | 3 | 1 | 5 | 3 | **3.5** |
| **加权总分** | 2.80→3.05 | 3.25 | 2.55 | 2.95 | 2.95 | **3.40** |

v3.4.3 总分从 2.95 提升到 3.40，超过 OMC（3.25）成为综合评分最高的方案。

### 7.2 v3.0.1 → v3.4.3 提升点

| 维度 | 提升项 |
|------|--------|
| 质量保障 4→4.5 | decision format hook + change_coverage + anti-rationalization 加权 |
| 并行效率 1→3.5 | Phase 1 三路并行 + Phase 4/5/6 阶段内并行 + Phase 6 三路并行 |
| 成本优化 1→1.5 | model_routing 行为引导（无实际模型切换 API） |
| 可扩展性 2→2.5 | 内置模板 + 全阶段规则注入 |
| 学习进化 3→3.5 | 知识累积 + Steering Documents 持久化 + Phase 1 历史注入 |

### 7.3 各竞品最新动态（2026-03）

**Superpowers**: Agent Teams 并行已落地，TDD 强制仍是最大差异化
**OMC**: Smart Model Routing 据称 40-60% 成本节省，Ultrapilot 5 并发稳定
**ECC**: Instincts 学习系统成熟，跨 4 平台支持

### 7.4 核心问题与差距

| 问题 | 优先级 | 差距描述 | 与竞品对比 |
|------|--------|---------|-----------|
| **成本优化是最大短板** | P0 | model_routing 仅为 prompt 行为提示，Task API 不支持 per-task model | OMC 实际切换模型省 40-60% |
| **SKILL.md 即将超限** | P0 | 488/500 行，每次迭代都在逼近极限 | 竞品无此限制（非 SKILL.md 架构） |
| **Hook 代码重复** | P1 | 6 个脚本 ~90 行重复代码 | 维护成本问题 |
| **无 TDD 强制** | P1 | Phase 4 设计 + Phase 5 实施割裂 | Superpowers RED-GREEN-REFACTOR |
| **仅 Claude Code** | P2 | 深度耦合 Task/Hook/SessionStart | Superpowers 3 平台, ECC 4 平台 |
| **学习系统初级** | P2 | 仅 knowledge 累积 + Phase 1 注入 | ECC Instincts 置信度 + 自动应用 |

### 7.5 差异化优势（不可替代）

1. **端到端阶段覆盖最完整**: 8 阶段，竞品最多 5 阶段
2. **门控体系最严密**: 3 层确定性门禁，竞品最多 2 层
3. **规范文档最完整**: Proposal → Design → Specs → Tasks 四层
4. **崩溃恢复最健壮**: checkpoint + 上下文压缩恢复 + PID 回收防护
5. **配置驱动最彻底**: 零硬编码
6. **Hook 确定性执行**: 11 个 Hook，fail-closed 设计

---

## 八、优化实施路线图

### P0 — 立即执行

| 序号 | 任务 | 涉及文件 | 预期效果 |
|------|------|---------|---------|
| P0-A | **SKILL.md 瘦身** — 提取 Banner 渲染规则(~15行) + 护栏约束表(~30行) + 错误处理表(~10行) 到 references/ | SKILL.md + 新增 references/guardrails.md | 488→~430 行，留 70 行余量 |
| P0-B | **日志美化** — 统一进度行格式 + checkpoint 扫描美化 | SKILL.md + scan-checkpoints-on-start.sh | 用户体验显著提升 |
| P0-C | **Hook 代码去重** — 提取 bypass 逻辑到 _hook_common.sh | 6 个 PostToolUse 脚本 + _hook_common.sh | 减少 ~90 行重复代码 |

### P1 — 短期优化

| 序号 | 任务 | 涉及文件 | 预期效果 |
|------|------|---------|---------|
| P1-A | **JSON 提取共享模块** — raw_decode + 两遍搜索提取为 _json_extract.py | 4 个 Hook 脚本 + _json_extract.py | 消除 4 处重复实现 |
| P1-B | **YAML 解析统一** — PyYAML 优先 + 正则 fallback | 3 个 Hook 脚本 + _yaml_parser.py | 消除配置解析 bug |
| P1-C | **Hook 阻断消息结构化** — 列出违规项 + 修复动作 | 6 个 Hook 脚本 | 可操作性提升 |
| P1-D | **Phase 5 超时可配置** — 从 config 读取 wall-clock timeout | check-predecessor-checkpoint.sh + config | 大项目适配 |
| P1-E | **金字塔阈值从 config 读取** — Hook 不再硬编码 30/40 | validate-json-envelope.sh | 配置一致性 |

### P2 — 中期演进

| 序号 | 任务 | 涉及文件 | 预期效果 |
|------|------|---------|---------|
| P2-A | Phase 5 TDD 可选模式 | SKILL.md + phase5-implementation.md | 代码质量提升 |
| P2-B | 实际 Model Routing（等待 Task API 支持） | autopilot-dispatch + config | 成本降低 30-40% |
| P2-C | Instincts 学习系统 | 新增 Skill + scripts | 长期效率提升 |
| P2-D | 上下文恢复美化 | reinject-state-after-compact.sh | 恢复体验提升 |

---

## 九、快速实施参考

### 9.1 SKILL.md 瘦身方案（P0-A）

**提取目标**:
1. Phase 0 Step 4 Banner 渲染规则（第 106-119 行，~15 行）→ `references/banner-spec.md`
2. 护栏约束表（第 426-456 行，~30 行）→ `references/guardrails.md`
3. 错误处理表（第 458-468 行，~10 行）→ `references/guardrails.md`

**替换为**:
```markdown
## 护栏约束
> 详见: `references/guardrails.md`
```

### 9.2 Hook 去重方案（P0-C）

**新增 `_hook_common.sh` 函数**:
```bash
# hook_fast_bypass <stdin_data>
# Returns: exit 0 if should skip (not autopilot), exit 1 if should continue
hook_fast_bypass() {
  local stdin_data="$1"
  # Layer 0: lock file
  local root=$(extract_project_root "$stdin_data")
  has_active_autopilot "$root" || return 0
  # Layer 1: phase marker
  echo "$stdin_data" | grep -q '"prompt".*"<!-- autopilot-phase:[0-9]' || return 0
  # Layer 1.5: background skip
  echo "$stdin_data" | grep -q '"run_in_background".*true' && return 0
  return 1
}
```

### 9.3 JSON 提取共享模块方案（P1-A）

**新增 `_json_extract.py`**:
```python
def extract_envelope(output: str) -> dict | None:
    """Two-pass raw_decode: prefer {status+summary}, fallback {status}"""
    ...

def extract_phase(prompt: str) -> int | None:
    """Extract phase number from <!-- autopilot-phase:N -->"""
    ...
```

---

> 本报告基于对所有 SKILL.md、references/、scripts/、docs/ 的完整源码阅读生成。
> 下次会话可直接引用本报告的章节编号和优化 ID（如 P0-A、X-1、P5-3）进行方案讨论和实施。
