# spec-autopilot 插件源码分析

> 版本: v5.4.3 | 分支: feature/spec-autopilot  
> 本文基于 `plugins/spec-autopilot/` 全部源码进行深度技术分析。

---

## 目录

1. [整体架构设计](#1-整体架构设计)
2. [工程化原理](#2-工程化原理)
3. [阶段流水线详解](#3-阶段流水线详解)
4. [三层门禁系统](#4-三层门禁系统)
5. [运行时脚本引擎](#5-运行时脚本引擎)
6. [GUI 可视化系统](#6-gui-可视化系统)
7. [崩溃恢复机制](#7-崩溃恢复机制)
8. [模型路由与调度](#8-模型路由与调度)
9. [质量保障体系](#9-质量保障体系)
10. [CI/CD 与版本管理](#10-cicd-与版本管理)
11. [稳定性分析](#11-稳定性分析)

---

## 1. 整体架构设计

### 1.1 设计理念

spec-autopilot 是一个基于 Droid（Claude CLI 工具）的**规范驱动自动化交付插件**，其核心设计理念是：

- **Spec-Driven**: 从需求出发，经过结构化规范（OpenSpec），到实现和测试，全流程自动化
- **Fail-Closed**: 所有质量关卡默认阻断，而非放行。宁可停下来，也不产出低质量制品
- **Deterministic + AI Hybrid**: 确定性脚本（Shell/Python）处理可验证逻辑，AI 处理需要推理的任务
- **Context-Protective**: 主线程上下文窗口是稀缺资源，通过子 Agent 和后台 Task 严格隔离

### 1.2 系统分层架构

```
┌──────────────────────────────────────────────────────────────┐
│                     用户接口层 (User Interface)                │
│  ┌────────────┐  ┌───────────────┐  ┌──────────────────────┐ │
│  │ /autopilot │  │ GUI Dashboard │  │  Claude Statusline    │ │
│  │ Skill 入口  │  │ React Web App │  │  实时状态显示         │ │
│  └─────┬──────┘  └───────┬───────┘  └──────────┬───────────┘ │
├────────┼─────────────────┼──────────────────────┼────────────┤
│        │          编排层 (Orchestration)         │            │
│  ┌─────▼──────────────────────────────────────────────────┐  │
│  │  主编排器 (autopilot/SKILL.md)                          │  │
│  │  ├─ Phase 0-1: 主线程直接执行（Skill 注入）             │  │
│  │  ├─ Phase 2-6: Task 子 Agent 调度（单层，禁止嵌套）     │  │
│  │  └─ Phase 7: 主线程汇总 + 归档                         │  │
│  └─────┬──────────────────────────────────────────────────┘  │
│        │                                                      │
│  ┌─────▼──────────────────────────────────────────────────┐  │
│  │  协议技能族 (Protocol Skills)                           │  │
│  │  ├─ autopilot-gate      (门禁 + Checkpoint 管理)       │  │
│  │  ├─ autopilot-dispatch  (子 Agent 调度构造)             │  │
│  │  ├─ autopilot-recovery  (崩溃恢复)                     │  │
│  │  └─ autopilot-setup     (配置初始化)                   │  │
│  └────────────────────────────────────────────────────────┘  │
├──────────────────────────────────────────────────────────────┤
│                     运行时层 (Runtime)                         │
│  ┌────────────────────────┐  ┌─────────────────────────────┐ │
│  │  Shell 脚本引擎 (~60)   │  │  WebSocket 聚合服务器        │ │
│  │  ├─ 门禁验证脚本        │  │  ├─ Bun/TypeScript 运行时   │ │
│  │  ├─ 事件发射脚本        │  │  ├─ 快照构建 + 增量广播     │ │
│  │  ├─ 状态管理脚本        │  │  ├─ REST API + 静态文件     │ │
│  │  └─ Python 验证器       │  │  └─ 决策服务（双向反控）    │ │
│  └────────────────────────┘  └─────────────────────────────┘ │
├──────────────────────────────────────────────────────────────┤
│                     数据层 (Data)                              │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────────┐   │
│  │ Checkpoint   │  │ Event Bus    │  │ State Snapshot    │   │
│  │ JSON 文件     │  │ events.jsonl │  │ 结构化控制态       │   │
│  └──────────────┘  └──────────────┘  └───────────────────┘   │
└──────────────────────────────────────────────────────────────┘
```

### 1.3 关键设计约束

| 约束 | 说明 | 执行者 |
|------|------|--------|
| 子 Agent 单层扁平 | 子 Agent 内无 Task 工具，禁止嵌套调度 | 架构限制 |
| 主线程上下文节制 | 主线程禁止 Read 子 Agent 产出全文 | CLAUDE.md 规则 |
| 配置驱动不硬编码 | 所有阈值和行为从 `autopilot.config.yaml` 读取 | dispatch 模板 |
| JSON 信封契约 | 子 Agent 必须返回 `{status, summary, artifacts}` | Hook L2 验证 |
| Checkpoint 仅 Bash 写入 | 防止 Write 工具 Hook 误触发约束检查 | CLAUDE.md 规则 |

### 1.4 文件组织结构

```
plugins/spec-autopilot/
├── .claude-plugin/plugin.json     # 插件清单：名称、版本、关键词
├── CLAUDE.md                      # 工程法则（AI Agent 必须遵守的硬约束）
├── version.txt                    # 版本号单点来源
├── hooks/hooks.json               # Droid Hook 注册（事件 → 脚本映射）
├── skills/                        # 12 个 SKILL.md（编排协议定义）
│   ├── autopilot/                 # 主编排器 + 34 个参考文档 + 4 个模板
│   ├── autopilot-dispatch/        # 子 Agent 调度协议
│   ├── autopilot-gate/            # 三层门禁 + Checkpoint 管理
│   ├── autopilot-phase{0-7}-*/    # 各阶段专属协议
│   ├── autopilot-recovery/        # 崩溃恢复
│   └── autopilot-setup/           # 配置初始化向导
├── runtime/
│   ├── scripts/                   # ~60 个 Shell/Python 脚本（确定性运行时）
│   └── server/                    # Bun/TypeScript WebSocket 服务器
├── gui/                           # React/Vite GUI 源码
├── gui-dist/                      # GUI 预构建产物
├── tests/                         # ~110 个 Shell 测试文件
├── tools/                         # 构建/工具脚本
├── docs/                          # 双语文档（EN/ZH）
└── logs/                          # 运行时日志
```

---

## 2. 工程化原理

### 2.1 插件注册机制

插件通过 `.claude-plugin/plugin.json` 向 Claude 声明身份：

```json
{
  "name": "spec-autopilot",
  "version": "5.4.3",
  "description": "Spec-driven autopilot with ...",
  "keywords": ["autopilot", "orchestration", ...]
}
```

Claude 在启动时扫描 `~/.claude/plugins/` 目录（或 `.claude/settings.json` 中的 `enabledPlugins`），加载匹配的插件。插件的 Skills 自动注册为 `/autopilot` 等斜杠命令。

### 2.2 Hook 系统 — 确定性行为注入

`hooks/hooks.json` 是插件与 Droid 运行时的核心接口。它将 Shell 脚本绑定到 Claude 生命周期事件：

```
hooks.json 事件映射:

SessionStart ─→ capture-hook-event.sh        (事件捕获)
             ─→ scan-checkpoints-on-start.sh (async, 扫描 checkpoint)
             ─→ auto-install-statusline.sh   (async, 安装状态栏)
             ─→ check-skill-size.sh          (技能大小检查)
             ─→ [compact] reinject-state-after-compact.sh (上下文压缩恢复)

PreToolUse[Bash]             ─→ guard-no-verify.sh          (禁止 --no-verify)
PreToolUse[AskUserQuestion]  ─→ guard-ask-user-phase.sh     (阻止非法阶段提问)
PreToolUse[Task]             ─→ capture-hook-event.sh
                             ─→ check-predecessor-checkpoint.sh (前置 checkpoint 验证)
                             ─→ auto-emit-agent-dispatch.sh    (自动发射 Agent 事件)

PostToolUse[*]               ─→ capture-hook-event.sh       (全局事件捕获)
                             ─→ emit-tool-event.sh          (工具事件发射)
PostToolUse[Task]            ─→ post-task-validator.sh      (JSON 信封验证)
                             ─→ auto-emit-agent-complete.sh (Agent 完成事件)
PostToolUse[Write|Edit]      ─→ unified-write-edit-check.sh (代码质量检查)

PreCompact                   ─→ save-state-before-compact.sh (压缩前保存状态)
Stop/SessionEnd              ─→ capture-hook-event.sh
SubagentStart/SubagentStop   ─→ capture-hook-event.sh
UserPromptSubmit             ─→ capture-hook-event.sh
```

**关键设计**: Hook 脚本通过 `_hook_preamble.sh` 实现**零成本旁路 (Layer 0 bypass)**——当检测到无活跃 autopilot 会话时（`has_active_autopilot()` 返回 false），脚本在 ~1ms 内退出，不影响普通 Claude 使用。

### 2.3 共享基础设施 (`_common.sh`)

所有运行时脚本的公共函数库，约 600 行 Shell 代码：

| 函数 | 职责 | 性能特征 |
|------|------|----------|
| `has_active_autopilot()` | 检测锁文件是否存在 | 纯 Bash，~1ms |
| `resolve_project_root()` | 解析项目根目录 | 三级 fallback |
| `parse_lock_file()` | 解析 JSON/纯文本锁文件 | 调用 python3 |
| `find_active_change()` | 查找活跃 change 目录 | 锁文件 → checkpoint → mtime |
| `find_checkpoint()` | 查找指定阶段 checkpoint | glob 匹配 |
| `scan_all_checkpoints()` | 按序扫描全部 checkpoint | 循环遍历 |
| `read_config_value()` | 读取 YAML 配置值 | PyYAML → regex fallback |
| `read_lock_json_field()` | 提取锁文件字段 | python3 JSON 解析 |
| `validate_checkpoint_integrity()` | 验证 checkpoint 完整性 | python3 JSON 验证 |
| `get_phase_sequence()` | 按模式返回阶段序列 | 纯 Bash 查表 |

### 2.4 构建系统 (`tools/build-dist.sh`)

将 `plugins/spec-autopilot/` 源码构建为 `dist/spec-autopilot/` 发布包：

```
构建流程:
1. 恢复 gui-dist（fresh-clone fallback）
2. 清空 dist/ 目录
3. 重建 GUI（bun build，版本号注入）
4. 按 .dist-include 清单复制运行时脚本
5. 复制 skills/、hooks/、.claude-plugin/
6. 复制 gui-dist/ 到 dist/assets/gui/
7. 排除 tests/、node_modules/、.ruff_cache/
8. 验证 dist/ 完整性
```

**`.dist-include` 清单**: `runtime/scripts/.dist-include` 列出所有需要进入发布包的脚本文件。新增脚本必须在此注册，否则不会被打包。

---

## 3. 阶段流水线详解

### 3.1 全景流程图

```
/autopilot <需求描述>
         │
         ▼
  ┌──────────────┐
  │  Phase 0     │  主线程 Skill 注入
  │  环境检查     │  ├─ 版本读取 + 配置验证
  │  崩溃恢复     │  ├─ GUI 服务器启动 + Banner 渲染
  │  锁文件管理   │  ├─ 崩溃恢复扫描（recovery-decision.sh）
  │              │  ├─ Task 依赖链创建（按模式）
  │              │  └─ 锁文件 + 锚定 Commit
  └──────┬───────┘
         │
         ▼
  ┌──────────────┐
  │  Phase 1     │  主线程 Skill 注入
  │  需求理解     │  ├─ 并行调研（Auto-Scan + 技术 + 联网）
  │  多轮决策     │  ├─ BA Agent 需求分析
  │              │  ├─ 多轮 AskUserQuestion 决策（弹性收敛）
  │              │  │   └─ 挑战代理（第 4/6/8 轮自动激活）
  │              │  └─ 输出: requirement_packet + change_name
  └──────┬───────┘
         │
    ┌────┴──── [mode=full only] ────┐
    │                                │
    ▼                                │
  ┌──────────────┐                   │
  │  Phase 2-3   │  联合调度快速路径  │
  │  OpenSpec    │  ├─ Phase 2: 创建 OpenSpec（后台 Task）
  │  + FF 生成   │  └─ Phase 3: FF 生成制品（后台 Task）
  └──────┬───────┘                   │
         │                           │
    ┌────┴──── [mode=full only] ────┤
    │                                │
    ▼                                │
  ┌──────────────┐                   │
  │  Phase 4     │  后台 Task        │
  │  测试用例     │  ├─ TDD 模式 → 跳过（Phase 5 吸收）
  │  设计        │  └─ 非 TDD → qa-expert 设计测试用例
  └──────┬───────┘                   │
         │◄──────────────────────────┘
         ▼
  ┌──────────────┐
  │  Phase 5     │  三路互斥
  │  实施        │  ├─ 路径 A: 并行（worktree 隔离，按域分区）
  │              │  ├─ 路径 B: 串行（逐个前台 Task）
  │              │  └─ 路径 C: TDD（RED→GREEN→REFACTOR 循环）
  └──────┬───────┘
         │
    ┌────┴──── [mode≠minimal] ──────┐
    │                                │
    ▼                                │
  ┌──────────────┐                   │
  │  Phase 6     │  三路并行          │
  │  测试报告     │  ├─ A: 测试执行（主路径）
  │              │  ├─ B: 代码审查（可选）
  │              │  └─ C: 质量扫描（异步）
  └──────┬───────┘                   │
         │◄──────────────────────────┘
         ▼
  ┌──────────────┐
  │  Phase 7     │  主线程 Skill 注入
  │  汇总 + 归档 │  ├─ Summary Box 渲染
  │              │  ├─ 三路结果收集 + 知识提取
  │              │  ├─ Allure 预览启动
  │              │  ├─ Archive Readiness 自动判定
  │              │  ├─ git autosquash（fixup → squash）
  │              │  └─ 锁文件清理
  └──────────────┘
```

### 3.2 执行模式

| 模式 | 阶段序列 | 跳过内容 | 适用场景 |
|------|---------|---------|---------|
| **full** | 0→1→2→3→4→5→6→7 | 无 | 中大型功能 |
| **lite** | 0→1→5→6→7 | Phase 2/3/4（OpenSpec） | 小功能，需求明确 |
| **minimal** | 0→1→5→7 | Phase 2/3/4/6（OpenSpec + 报告） | 极简需求 |

**核心约束**: 模式只控制阶段跳过，**不影响**阶段内部质量。Phase 1 和 Phase 5 在所有模式下完全相同。

### 3.3 Phase 0: 环境检查 + 崩溃恢复

**执行位置**: 主线程（Skill 注入）  
**对应 Skill**: `autopilot-phase0-init/SKILL.md`  
**不写 Checkpoint**

#### 步骤分解

| Step | 操作 | 关键实现 |
|------|------|---------|
| 1 | 读取插件版本 | `cat plugin.json` → 提取 version |
| 2 | 配置验证 | `validate-config.sh` → `_config_validator.py` (Schema 校验) |
| 3 | 模式解析 | $ARGUMENTS 关键词 → config.default_mode → "full" |
| 4 | GUI 服务器 + Banner | `start-gui-server.sh` → 守护进程启动 |
| 4.5 | Event Bus 初始化 | `emit-phase-event.sh phase_start 0` |
| 5 | 已启用插件检查 | 读取 `.claude/settings.json` |
| 6 | 崩溃恢复 | `recovery-decision.sh` → 三路恢复选择 |
| 7 | 创建阶段 Task 链 | TaskCreate × N（按模式 + blockedBy） |
| 8 | 锁文件 gitignore | 确保 `.autopilot-active` 被忽略 |
| 9 | 创建锁文件 | `create-lockfile.sh` → python3 原子写入 |
| 10 | 锚定 Commit | `git commit --allow-empty` + `update-anchor-sha.sh` |

**输出**: version、mode、session_id、ANCHOR_SHA、config、recovery_phase

#### 锁文件机制

锁文件 `openspec/changes/.autopilot-active` 是会话级互斥锁：

```json
{
  "change": "feature-login",
  "pid": "12345",
  "started": "2026-04-01T10:00:00Z",
  "session_cwd": "/path/to/project",
  "anchor_sha": "abc1234",
  "session_id": "1711936800000",
  "mode": "full"
}
```

PID 冲突检测: 同 PID + 同 session_id → 冲突；PID 存活但 session_id 不同 → PID 回收，自动覆盖。

#### 锚定 Commit 机制

锚定 Commit 是一个空 commit，作为后续所有 `--fixup` commit 的 rebase 目标：

```
autopilot: start feature-login    ← 锚定 Commit (ANCHOR_SHA)
  fixup! autopilot: Phase 1       ← Phase 1 checkpoint
  fixup! autopilot: Phase 2       ← Phase 2 checkpoint
  ...
```

Phase 7 归档时通过 `git rebase --autosquash` 将所有 fixup 合并为一个干净的提交。

### 3.4 Phase 1: 需求理解与多轮决策

**执行位置**: 主线程（Skill 注入）  
**对应 Skill**: `autopilot-phase1-requirements/SKILL.md`  
**写入 Checkpoint**: `phase-1-requirements.json`

这是**唯一需要用户主动交互**的阶段。

#### 并行调研（3 路自适应）

```
复杂度路由:
  低（bugfix/chore）  → Auto-Scan only
  中（小 feature）    → Auto-Scan + 技术调研
  高（大 feature）    → Auto-Scan + 技术调研 + 联网搜索

所有调研 Task 必须在同一消息中同时发起:
  Task(run_in_background: true, prompt: "Auto-Scan...")
  Task(run_in_background: true, prompt: "技术调研...")
  Task(run_in_background: true, prompt: "联网搜索...")
```

#### 弹性收敛决策系统（v7.1）

- **清晰度评分**: 混合评分 = 规则评分 × 0.6 + AI 评分 × 0.4
- **退出条件**: 评分 ≥ 阈值（非硬性轮数上限）
- **一次一问**: Medium/Large 每轮只问 1 个决策点
- **挑战代理**: 第 4/6/8 轮激活反面论证/简化/本体论
- **安全阀**: 8 轮软提醒 + 15 轮硬上限

#### 上下文隔离红线

```
主线程禁止 Read 的文件:
  ✗ context/research-findings.md
  ✗ context/web-research-findings.md  
  ✗ context/requirements-analysis.md

主线程只消费 JSON 信封中的结构化字段:
  ✓ decision_points
  ✓ tech_constraints
  ✓ complexity
  ✓ requirements_summary
```

### 3.5 Phase 2-3: OpenSpec 创建与 FF 生成

**执行位置**: 后台 Task 子 Agent  
**对应 Skill**: `autopilot-phase2-3-openspec/SKILL.md`  
**写入 Checkpoint**: `phase-2-openspec.json` + `phase-3-ff.json`

v8.0 引入**联合调度快速路径**，将 Phase 2 和 3 合并为单次流水：

```
Fast-Step 0: emit phase_start 2
Fast-Step 1: 简化 Gate（仅验证 Phase 1 checkpoint）
Fast-Step 2: 单次 resolve-model-routing.sh（Phase 2+3 共享）
Fast-Step 3-4: Phase 2 Task → 等待 → JSON 信封
Fast-Step 5-6: Phase 2 Checkpoint → Phase 3 Task（复用路由）
Fast-Step 7-8: Phase 3 完成 → Checkpoint
Fast-Step 9: 继续下一 Phase

消除的冗余: 1× Gate Skill + 5× Read + 1× routing + 2× GUI 检查
```

### 3.6 Phase 4: 测试用例设计

**执行位置**: 后台 Task 子 Agent  
**对应 Skill**: `autopilot-phase4-testcase/SKILL.md`  
**写入 Checkpoint**: `phase-4-testing.json` 或 `phase-4-tdd-override.json`

```
TDD 模式检测（确定性脚本）:
  check-tdd-mode.sh → TDD_SKIP | TDD_DISPATCH

TDD_SKIP（tdd_mode=true + full）:
  → 写入 phase-4-tdd-override.json → 直接跳到 Phase 5

TDD_DISPATCH（非 TDD）:
  → qa-expert Agent 设计测试用例
  → 门禁: 只接受 ok 或 blocked（warning 被 Hook 强制阻断）
  → 每类测试 ≥ min_test_count_per_type
  → 测试金字塔: unit ≥ 30%, e2e ≤ 40%
```

### 3.7 Phase 5: 实施编排

**执行位置**: Task 子 Agent  
**对应 Skill**: `autopilot-phase5-implement/SKILL.md`  
**写入 Checkpoint**: `phase-5-implement.json` + `phase5-tasks/task-N.json`

最复杂的阶段，三条**互斥**执行路径：

#### 路径 A: 并行模式

```
generate-parallel-plan.sh（确定性调度器）
  → parallel_plan.json（文件域分区 + 依赖 DAG）
  → 按 batch 创建 git worktree
  → 域 Agent 在 worktree 内并行实施
  → 按编号顺序合并 worktree
  → 全量测试验证

降级条件（确定性触发，禁止 AI 自主降级）:
  1. generate-parallel-plan.sh 输出 fallback_to_serial=true
  2. worktree 创建失败
  3. 单组合并冲突 > 3 文件
  4. 连续 2 组合并失败
  5. 用户显式选择
```

#### 路径 B: 串行模式

```
FOR each task IN parallel_plan.batches:
  [L2 RED 验证] → 运行 Phase 4 测试（应失败）
  dispatch Task（前台同步阻塞）
  [L2 GREEN 验证] → 运行 Phase 4 测试（应通过）
  写入 phase5-tasks/task-N.json
END FOR
```

#### 路径 C: TDD 模式

```
串行 TDD:
  FOR each task:
    RED Task   → 只写测试（exit_code ≠ 0 验证）
    GREEN Task → 只写实现（exit_code = 0 验证）
    REFACTOR Task → 重构（回归保护：失败则 git checkout 回滚）
  END FOR

并行 TDD:
  域 Agent prompt 注入完整 TDD 纪律
  合并后主线程全量测试验证
```

### 3.8 Phase 6: 测试报告与三路并行

**执行位置**: 后台 Task 子 Agent  
**对应 Skill**: `autopilot-phase6-report/SKILL.md`  
**写入 Checkpoint**: `phase-6-report.json`

三路在同一消息中全部后台派发：

| 路径 | 内容 | Agent | 阻断性 |
|------|------|-------|--------|
| A | 测试执行 | qa-expert | 主路径 |
| B | 代码审查 | general-purpose | 不阻断 A |
| C | 质量扫描 | general-purpose | 不阻断 A |

Allure 集成: 当 `config.phases.reporting.format === "allure"` 时自动统一输出目录、生成报告。

### 3.9 Phase 7: 汇总 + Archive Readiness 自动归档

**执行位置**: 主线程（Skill 注入）  
**对应 Skill**: `autopilot-phase7-archive/SKILL.md`  
**写入 Checkpoint**: `phase-7-summary.json`

#### Archive Readiness 检查（fail-closed）

```json
{
  "checks": {
    "all_checkpoints_ok": true,       // 所有 checkpoint status ok/warning
    "fixup_completeness": true,        // fixup_count >= checkpoint_count
    "anchor_valid": true,              // git rev-parse $ANCHOR_SHA 成功
    "worktree_clean": true,            // git status --porcelain 为空
    "review_findings_clear": true,     // 无未解决 critical findings
    "zero_skip_passed": true           // Phase 5 zero_skip_check 通过
  },
  "overall": "ready|blocked"
}
```

全部通过 → 自动归档 | 任一失败 → 硬阻断（无"忽略继续"选项）

#### Git Autosquash

`autosquash-archive.sh` 封装完整流程：

```
1. 验证 ANCHOR_SHA 有效
2. 检测非 autopilot fixup 提交 → needs_confirmation
3. git rebase --autosquash $ANCHOR_SHA
4. 修改 commit message → "feat(autopilot): <change_name>"
5. 返回 JSON: {status, anchor_sha, squash_count}
```

---

## 4. 三层门禁系统

### 4.1 架构

```
┌─────────────────────────────────────────────────┐
│  Layer 1: 任务依赖（TaskCreate + blockedBy）     │ ← 任务系统自动执行
│  ── 确保 Phase N+1 不能在 Phase N 完成前开始 ── │
├─────────────────────────────────────────────────┤
│  Layer 2: 确定性 Hook 验证                       │ ← Shell/Python 脚本
│  ── check-predecessor-checkpoint.sh ──           │
│  ── unified-write-edit-check.sh ──              │
│  ── post-task-validator.sh ──                   │
│  ── guard-no-verify.sh ──                       │
│  ── guard-ask-user-phase.sh ──                  │
├─────────────────────────────────────────────────┤
│  Layer 3: AI Gate 8-Step 清单                    │ ← autopilot-gate Skill
│  ── 8 步切换检查 + 特殊门禁 + 可选验证 ──        │
└─────────────────────────────────────────────────┘

任一层阻断 → 整体阻断（联防原则）
```

### 4.2 Layer 2 关键脚本

#### `check-predecessor-checkpoint.sh`

在 `PreToolUse[Task]` 时触发，验证前置阶段 checkpoint 存在且状态有效：

```
输入: stdin JSON（含 tool_input.prompt 的 <!-- autopilot-phase:N --> 标记）
逻辑:
  1. 解析 phase marker → 当前阶段 N
  2. 从 _phase_graph.py 计算前驱阶段
  3. 查找前驱 checkpoint 文件
  4. 验证 status ∈ {ok, warning}
  5. 失败 → exit 2（Claude 阻断 Task 执行）
```

#### `unified-write-edit-check.sh`

在 `PostToolUse[Write|Edit]` 时触发，统一执行代码质量检查：

```
检查项:
  1. TODO/FIXME/HACK 占位符检测
  2. 恒真断言检测（expect(true).toBe(true)）
  3. Checkpoint 文件保护（禁止 Write 工具修改）
  4. 子 Agent 文件所有权验证
  5. Anti-Rationalization（10+6 种 excuse 模式匹配）
```

#### `post-task-validator.sh`

在 `PostToolUse[Task]` 时触发，验证子 Agent 返回的 JSON 信封：

```
验证流程:
  1. 提取 Task 输出最后的 JSON 行
  2. 调用 _envelope_parser.py 解析
  3. 检查必需字段: status, summary
  4. Anti-Rationalization 检查
  5. 失败 → 标记 warning/blocked
```

### 4.3 Layer 3: 8-Step 检查清单

```
Step 1: 确认阶段 N 子 Agent 已返回 JSON 信封
Step 2: 验证 JSON status ∈ {ok, warning}
Step 3: 将 JSON 写入 phase-results/phase-N-*.json
Step 4: TaskUpdate 阶段 N → completed
Step 5: TaskGet 阶段 N+1，确认 blockedBy 为空
Step 5.5: CLAUDE.md 变更检测（运行时规则热更新）
Step 6: 读取 phase-N checkpoint 确认存在且可解析
Step 7: TaskUpdate 阶段 N+1 → in_progress
Step 8: 准备 dispatch 子 Agent

任何 Step 失败 → 硬阻断
```

### 4.4 特殊门禁

| 切换点 | 额外验证 |
|--------|---------|
| Phase 4→5（非 TDD） | test_counts + artifacts + dry_run 全部通过 |
| Phase 4→5（TDD） | tdd-override.json 存在 |
| Phase 5→6 | test-results.json + zero_skip_check.passed + 所有 task [x] |
| Phase 6.5 | 代码审查 findings（advisory，不硬阻断 Phase 7） |

### 4.5 双向反控：Gate 阻断后决策轮询

当门禁阻断时，启动 GUI 决策轮询（`poll-gate-decision.sh`）：

```
CLI 端:
  每 N 秒轮询 GUI 服务器 /api/decision/{request_id}
  接受 override / retry / fix / timeout 决策

GUI 端:
  展示 GateBlockCard 组件
  用户点击按钮 → POST /api/decision
  决策推送到 CLI 端
```

---

## 5. 运行时脚本引擎

### 5.1 脚本分类

| 类别 | 数量 | 代表脚本 | 职责 |
|------|------|---------|------|
| **门禁验证** | ~8 | check-predecessor-checkpoint.sh, guard-no-verify.sh | L2 确定性阻断 |
| **事件发射** | ~10 | emit-phase-event.sh, emit-tool-event.sh | Event Bus 写入 |
| **状态管理** | ~6 | save-state-before-compact.sh, reinject-state-after-compact.sh | 上下文压缩恢复 |
| **质量检查** | ~8 | unified-write-edit-check.sh, anti-rationalization-check.sh | 代码质量门卫 |
| **并行调度** | ~5 | generate-parallel-plan.sh, parallel-merge-guard.sh | 并行任务编排 |
| **恢复机制** | ~4 | recovery-decision.sh, clean-phase-artifacts.sh | 崩溃恢复 |
| **配置验证** | ~3 | validate-config.sh, _config_validator.py | Schema 校验 |
| **工具检测** | ~3 | check-allure-install.sh, check-security-tools-install.sh | 环境检测 |
| **模型路由** | ~3 | resolve-model-routing.sh, emit-model-routing-event.sh | 智能模型选择 |
| **其他** | ~10 | autosquash-archive.sh, create-lockfile.sh, rules-scanner.sh | 杂项 |

### 5.2 Python 验证器

4 个 Python 模块提供复杂验证逻辑：

| 模块 | 行数 | 职责 |
|------|------|------|
| `_config_validator.py` | ~800 | autopilot.config.yaml 完整 Schema 验证 |
| `_post_task_validator.py` | ~1400 | 子 Agent JSON 信封全面验证 |
| `_constraint_loader.py` | ~350 | 代码约束配置加载 |
| `_phase_graph.py` | ~350 | 阶段依赖图计算（模式感知 + TDD 覆盖） |
| `_envelope_parser.py` | ~160 | JSON 信封提取（两遍解析策略） |

`_config_validator.py` 验证的维度：

```
1. missing_keys: 必需配置项缺失检查
2. type_errors: 配置值类型验证
3. enum_errors: 枚举值合法性（含 deprecated/forbidden）
4. range_errors: 数值范围校验
5. model_routing_errors: 模型路由配置合法性
6. cross_ref_warnings: 交叉引用警告（信息性）
```

### 5.3 事件总线 (Event Bus)

所有事件写入 `logs/events.jsonl`，格式为 JSON Lines：

```json
{
  "type": "phase_start",
  "phase": 5,
  "mode": "full",
  "timestamp": "2026-04-01T10:30:00.000Z",
  "change_name": "feature-login",
  "session_id": "1711936800000",
  "phase_label": "Implementation",
  "total_phases": 7,
  "sequence": 42,
  "payload": {"status": "ok", "duration_ms": 120000}
}
```

事件类型:
- `phase_start` / `phase_end`: 阶段生命周期
- `gate_pass` / `gate_block`: 门禁判定
- `task_progress`: Phase 5 任务细粒度进度
- `agent_dispatch` / `agent_complete`: Agent 生命周期
- `model_routing` / `model_effective` / `model_fallback`: 模型路由
- `tool_use`: 工具调用事件
- `decision_ack`: GUI 决策确认（WebSocket-only）
- `report_ready`: 报告就绪

### 5.4 上下文压缩恢复

Claude 在上下文窗口接近容量限制时自动执行 Compact。插件通过 PreCompact/SessionStart(compact) Hook 对实现恢复：

```
PreCompact:
  save-state-before-compact.sh
    → 将当前状态写入 state-snapshot.json
    → 包含: mode, current_phase, gate_frontier, phase_results, ...
    → 计算 snapshot_hash 确保一致性

SessionStart[compact]:
  reinject-state-after-compact.sh
    → 读取 state-snapshot.json
    → 验证 snapshot_hash
    → 将关键状态注入新的上下文窗口
    → 恢复 phase context snapshots
```

---

## 6. GUI 可视化系统

### 6.1 技术栈

```
前端: React 18 + TypeScript + Vite
状态: Zustand Store（36K 行）
字体: JetBrains Mono + Space Grotesk + Orbitron
通信: WebSocket (ws-bridge.ts)
构建: Bun + Vite（输出到 gui-dist/）
```

### 6.2 组件架构

| 组件 | 文件 | 职责 |
|------|------|------|
| `OrchestrationPanel` | 18K | 编排概览：目标、子步骤、门禁前沿、Archive Readiness |
| `ParallelKanban` | 22K | 并行任务看板：batch → 域 → task 三级展示 |
| `TelemetryDashboard` | 20K | 遥测面板：模型路由、事件统计、性能指标 |
| `VirtualTerminal` | 20K | 虚拟终端：日志流、事件过滤 |
| `PhaseTimeline` | 5.3K | 阶段时间线：Phase 0-7 进度可视化 |
| `ReportCard` | 9.1K | 测试报告卡片：套件结果、Allure 链接 |
| `GateBlockCard` | 7.5K | 门禁阻断卡片：双向反控决策界面 |
| `ToolTracePanel` | 4.7K | 工具追踪：Tool 调用链可视化 |
| `TranscriptPanel` | 3.0K | 对话面板：Agent 对话查看 |
| `RawInspectorPanel` | 2.7K | 原始检查器：JSON 数据调试 |
| `LogWorkbench` | 1.8K | 日志工作台：多视图切换 |

### 6.3 WebSocket 服务器

```
runtime/server/
├── autopilot-server.ts        # 入口
├── src/
│   ├── bootstrap.ts           # 启动编排：刷新循环 + 文件监听
│   ├── config.ts              # 配置（端口、路径）
│   ├── state.ts               # 全局状态
│   ├── types.ts               # 类型定义（380 行）
│   ├── api/routes.ts          # HTTP API + 静态文件
│   ├── ws/
│   │   ├── ws-server.ts       # WebSocket 服务
│   │   └── broadcaster.ts     # 增量事件广播
│   ├── snapshot/
│   │   ├── snapshot-builder.ts # 快照构建（聚合多源）
│   │   ├── phase-lookup.ts    # Phase 标签查询
│   │   └── journal-writer.ts  # 日志写入
│   ├── ingest/
│   │   ├── hook-events.ts     # Hook 事件摄取
│   │   ├── legacy-events.ts   # 旧版事件兼容
│   │   ├── status-events.ts   # 状态栏事件
│   │   └── transcript-events.ts # 对话转写
│   ├── session/
│   │   ├── session-context.ts # 会话上下文
│   │   └── file-cache.ts      # 文件缓存（游标管理）
│   ├── decision/
│   │   └── decision-service.ts # 决策服务（双向反控）
│   └── security/
│       └── sanitize.ts        # 输入净化
```

**数据流**:

```
events.jsonl ──→ 快照构建器 ──→ Session Snapshot
state-snapshot.json ─┘              │
archive-readiness.json ─┘           │
                                    ▼
                           WebSocket 广播 ──→ GUI Store ──→ React 组件
                           HTTP API ────────→ 按需查询
```

### 6.4 API 端点

| 端点 | 方法 | 说明 |
|------|------|------|
| `/api/health` | GET | 健康检查 |
| `/api/events` | GET | 事件列表（支持 offset 分页） |
| `/api/info` | GET | 服务器信息（版本、会话、状态） |
| `/api/snapshot` | GET | 完整快照 |
| `/api/decision` | POST | 接收 GUI 决策 |
| `/api/decision/:id` | GET | 查询决策状态 |
| `/*` | GET | 静态文件（gui-dist/） |

---

## 7. 崩溃恢复机制

### 7.1 恢复数据层级

```
优先级 1: state-snapshot.json（结构化控制态 + hash 校验）
  → gate_frontier, next_action, requirement_packet_hash
  → recovery_confidence: high

优先级 2: checkpoint 文件扫描
  → scan_all_checkpoints() → last_valid_phase
  → recovery_confidence: medium

优先级 3: phase context snapshots
  → phase-context-snapshots/phase-*-context.json
  → recovery_confidence: medium

优先级 4: 无数据
  → fresh_start, recovery_phase = 1
```

### 7.2 recovery-decision.sh 输出结构

```json
{
  "has_checkpoints": true,
  "changes": [{
    "name": "feature-login",
    "last_valid_phase": 5,
    "total_checkpoints": 5,
    "has_gaps": false,
    "interim": null,
    "progress": {"phase": 5, "step": "task_3_complete"},
    "state_snapshot": {
      "exists": true,
      "hash_valid": true,
      "gate_frontier": 5
    }
  }],
  "selected_change": "feature-login",
  "recommended_recovery_phase": 6,
  "recovery_options": {
    "continue": {"phase": 6, "label": "Test Report"},
    "specify_range": [1, 2, 3, 4, 5],
    "fresh_start": true
  },
  "git_state": {
    "rebase_in_progress": false,
    "merge_in_progress": false,
    "uncommitted_changes": false,
    "worktree_residuals": []
  },
  "auto_continue_eligible": true,
  "git_risk_level": "none",
  "recovery_confidence": "high",
  "recovery_reason": "state_snapshot_resume"
}
```

### 7.3 三路恢复选择

| 路径 | 操作 | 适用场景 |
|------|------|---------|
| A: 从断点继续 | 不清理制品，从 last_valid + 1 继续 | 常见崩溃恢复 |
| B: 从指定阶段 | clean-phase-artifacts.sh + git 回退 | 需要重做某阶段 |
| C: 从头开始 | 清空所有制品（保留 git 历史） | 完全重启 |

### 7.4 自动继续条件

当同时满足以下条件时，跳过用户交互直接恢复：
- `auto_continue_eligible == true`
- 单候选 change
- 无危险 git 状态 (rebase/merge)
- `recovery_confidence != "low"`

---

## 8. 模型路由与调度

### 8.1 路由策略

`resolve-model-routing.sh` 按 Phase 选择最佳模型：

| Phase | 默认 Tier | 默认 Model | 理由 |
|-------|----------|-----------|------|
| 1 | deep | opus | 需求分析需要深度推理 |
| 2 | fast | haiku | OpenSpec 创建是机械性操作 |
| 3 | fast | haiku | FF 生成是模板化操作 |
| 4 | deep | opus | 测试设计需要创造力 |
| 5 | deep | opus | 代码实施需要最强推理能力 |
| 6 | fast | haiku | 报告生成是机械性操作 |
| 7 | fast | haiku | 汇总与归档较简单 |

### 8.2 升级策略

```
fast → (失败1次) → standard → (失败2次) → deep → (仍失败) → 人工决策
```

### 8.3 可观测性

模型路由事件链：
```
model_routing  → 路由器请求（dispatch 前）
model_effective → 运行时确认实际模型
model_fallback  → 降级触发（如有）
```

GUI TelemetryDashboard 展示完整模型路由状态。

### 8.4 Dispatch 模板注入

子 Agent prompt 按优先级注入上下文：

```
优先级 1: config.phases[phase].instruction_files（用户自定义）
优先级 2: config.phases[phase].reference_files
优先级 2.5: Project Rules Auto-Scan（rules-scanner.sh）
优先级 3: config.project_context
优先级 4: config.test_suites
优先级 5: config.services
优先级 6: Phase 1 Steering Documents
优先级 7: 插件内置模板（templates/phase4-testing.md 等）
```

---

## 9. 质量保障体系

### 9.1 测试架构

```
tests/
├── run_all.sh               # 测试运行器（分层 + 过滤）
├── _fixtures.sh             # 共享 fixture（只增不改）
├── _test_helpers.sh         # 辅助函数（只增不改）
├── test_*.sh (×100+)        # 单元/行为测试
├── integration/
│   ├── test_e2e_checkpoint_recovery.sh
│   └── test_e2e_hook_chain.sh
└── smoke_release.sh         # 发布烟雾测试
```

**分层机制**: 每个测试文件可声明 `# TEST_LAYER: contract|behavior|docs_consistency`，运行时通过 `--layer` 过滤。

### 9.2 测试覆盖范围

| 测试类别 | 文件数 | 覆盖内容 |
|---------|--------|---------|
| Hook 契约 | ~15 | JSON 信封验证、predecessor 检查、Hook 链 |
| 阶段行为 | ~25 | Phase 1-7 各阶段逻辑、checkpoint 读写 |
| 门禁验证 | ~10 | Gate 通过/阻断、特殊门禁、TDD 门禁 |
| 并行调度 | ~10 | parallel plan 生成、merge guard、降级 |
| 模型路由 | ~8 | 路由解析、升级策略、可观测性 |
| 配置验证 | ~5 | Schema 校验、类型检查、枚举验证 |
| 恢复机制 | ~5 | checkpoint 扫描、auto-continue、制品清理 |
| GUI 服务器 | ~8 | 健康检查、快照构建、WebSocket、存储上限 |
| 状态管理 | ~5 | state-snapshot hash、phase context |
| 代码质量 | ~5 | banned patterns、assertion quality、anti-rationalization |
| 其他 | ~15 | 语法检查、构建验证、发布纪律、锁文件 |

### 9.3 测试纪律铁律

从 CLAUDE.md 提取的硬约束：

```
1. 新功能 → 必须新增 test case（≥3: 正常 + 边界 + 错误路径）
2. Bug 修复 → 先写复现测试，再修实现
3. 测试失败 → 修 assert/fixture，禁止修编排逻辑
4. 重构 → 所有测试保持通过，禁止修改测试逻辑
5. 单文件原则 → 一次 commit 测试修改限 1 个 test_*.sh
6. 禁止反向适配、弱化断言、删除测试、跳过测试
7. 基础设施不可变 → _fixtures.sh / _test_helpers.sh 只增不改
```

### 9.4 代码质量检查链

每次 Write/Edit 操作触发 `unified-write-edit-check.sh`：

```
检查链:
  1. TODO/FIXME/HACK 扫描 → 阻断
  2. 恒真断言检测 → 阻断
  3. Checkpoint 文件保护 → 阻断（禁止 Write 工具修改）
  4. 文件所有权验证（并行模式）→ 阻断
  5. Anti-Rationalization（16 种 excuse 模式）→ status 降级
  6. 代码约束（config.code_constraints）→ 阻断
```

### 9.5 需求路由（v4.2）

自动分类需求类型并调整门禁阈值：

| 类型 | sad_path | change_coverage | 特殊要求 |
|------|----------|----------------|---------|
| Feature | ≥ 20% | ≥ 80% | 无 |
| Bugfix | ≥ 40% | 100% | 必须含复现测试 |
| Refactor | ≥ 20% | 100% | 必须含行为保持测试 |
| Chore | ≥ 10% | ≥ 60% | typecheck 即可 |

---

## 10. CI/CD 与版本管理

### 10.1 版本号管理

```
单点来源: version.txt → 5.4.3
同步点:
  - .claude-plugin/plugin.json.version
  - gui-dist/ 内 JS bundle 中的 __PLUGIN_VERSION__
  - CHANGELOG.md

管理方式:
  主入口: release-please（自动管理版本号 + CHANGELOG）
  Fallback: tools/release.sh <patch|minor|major>
  禁止: 人工或 AI 单独修改任何版本号
```

### 10.2 Conventional Commits

```
feat:     新功能（触发 minor 版本升级）
fix:      Bug 修复（触发 patch 版本升级）
refactor: 重构（不触发版本升级）
chore:    杂项维护
docs:     文档更新
test:     测试更新
```

### 10.3 推送前流程

```
git push 前必须执行:
  1. bash tools/build-dist.sh  → 构建 dist/（含 GUI rebuild）
  2. bash tests/run_all.sh     → 全量测试
  两者均 exit 0 后才允许推送
```

### 10.4 构建纪律

```
1. 修改运行时文件 → 必须重新 build-dist.sh
2. dist/ 禁止手动修改
3. 新增脚本 → 必须在 .dist-include 注册
4. tests/ 永不进入 dist/
```

---

## 11. 稳定性分析

### 11.1 各阶段稳定性评估

| Phase | 稳定性 | 风险点 | 缓解措施 |
|-------|--------|--------|---------|
| 0 | **高** | 配置文件格式变化 | Schema 验证器 + 迁移指南 |
| 1 | **中** | AI 决策质量依赖模型能力 | 弹性收敛 + 挑战代理 + 15 轮硬上限 |
| 2-3 | **高** | 机械性操作，失败率低 | 联合快速路径减少故障点 |
| 4 | **高** | TDD 跳过逻辑确定性 | check-tdd-mode.sh 脚本验证 |
| 5 | **中** | 并行合并冲突 + worktree 管理 | 自动降级 + merge-guard + 残留清理 |
| 6 | **高** | 三路并行互不阻断 | 超时兜底 + JSON 解析失败降级 |
| 7 | **高** | Archive Readiness fail-closed | 6 项检查 + 自动 autosquash |

### 11.2 系统级稳定性保障

| 机制 | 说明 | 故障场景 |
|------|------|---------|
| **崩溃恢复** | state-snapshot.json + checkpoint 双保险 | 进程意外终止 |
| **上下文压缩恢复** | PreCompact 保存 + PostCompact 注入 | 长任务上下文溢出 |
| **锁文件互斥** | PID + session_id 冲突检测 | 多实例并发 |
| **Hook Layer 0 bypass** | 无 autopilot 会话时 ~1ms 退出 | 普通 Claude 使用不受影响 |
| **JSON 两遍解析** | _envelope_parser.py 宽松 + 严格双策略 | 子 Agent 输出格式偏差 |
| **确定性脚本** | 所有关键判断由 Shell/Python 执行 | 消除 AI 幻觉风险 |
| **Anti-Rationalization** | 16 种 excuse 模式匹配 | AI 找借口跳过质量检查 |
| **Git 锚定 + Autosquash** | 空 commit + fixup + rebase | 归档时一键合并 |
| **GUI 服务器保活** | 守护进程 + 健康检查自动重启 | 长任务期间 GUI 断连 |

### 11.3 已知限制

| 限制 | 影响 | 现状 |
|------|------|------|
| python3 强依赖 | 无 python3 无法运行 Hook 验证 | Phase 0 硬检查 |
| macOS/Linux 双适配 | stat 命令语法不同 | _common.sh 按 uname 分支 |
| 单进程锁文件 | 同一项目不支持多 autopilot 并行 | 设计选择，非 bug |
| GUI 仅 localhost | 远程开发环境需端口转发 | 安全考虑 |
| 模型路由非实时 | 实际模型可能因平台限制无法确认 | model_status: "unknown" |

### 11.4 性能特征

| 操作 | 耗时 | 说明 |
|------|------|------|
| Hook Layer 0 bypass | ~1ms | 纯 Bash，无 python3 |
| Hook 完整执行 | 5-60ms | 含 python3 fork |
| Gate 8-step 检查 | ~500ms | AI 执行 + 磁盘 I/O |
| GUI 快照构建 | ~100ms | 文件聚合 + JSON 解析 |
| 事件发射 | ~5ms | JSONL append |
| recovery-decision.sh | ~200ms | 全量 checkpoint 扫描 |

---

## 附录 A: 数据流总览

```
用户输入 "/autopilot 实现登录功能"
  │
  ▼
Phase 0: 配置 → 恢复 → 锁文件 → 锚定
  │  产出: config, mode, session_id, ANCHOR_SHA
  │
  ▼
Phase 1: 调研[3路并行] → BA → 多轮决策[弹性收敛]
  │  产出: requirement_packet.json, change_name
  │  checkpoint: phase-1-requirements.json
  │
  ▼
Phase 2-3: [联合快速路径] OpenSpec → FF
  │  产出: openspec/changes/<name>/proposal.md, design.md, ...
  │  checkpoint: phase-2-openspec.json, phase-3-ff.json
  │
  ▼
Phase 4: [TDD → skip | 正常 → 测试设计]
  │  产出: 测试文件 + traceability matrix
  │  checkpoint: phase-4-testing.json
  │
  ▼
Phase 5: [并行/串行/TDD] 实施循环
  │  产出: 实现代码 + test-results.json
  │  checkpoint: phase-5-implement.json + phase5-tasks/task-N.json
  │
  ▼
Phase 6: [三路并行] 测试执行 + 代码审查 + 质量扫描
  │  产出: 测试报告 + review findings + 质量得分
  │  checkpoint: phase-6-report.json + phase-6.5-code-review.json
  │
  ▼
Phase 7: 汇总 → Archive Readiness → Autosquash → 清理
  │  产出: Summary Box + archive-readiness.json
  │  checkpoint: phase-7-summary.json
  │
  ▼
完成: 一个干净的 feat(autopilot) commit
```

## 附录 B: 配置参考

核心配置文件 `.claude/autopilot.config.yaml` 结构：

```yaml
# 执行模式
default_mode: full|lite|minimal

# 阶段配置
phases:
  requirements:
    agent: general-purpose
    min_qa_rounds: 2
    research:
      enabled: true
      agent: general-purpose
    search_policy:
      default: search
  openspec:
    agent: Plan
  testing:
    agent: qa-expert
    gate:
      min_test_count_per_type: 3
      required_test_types: [unit, integration, e2e]
    parallel:
      enabled: false
  implementation:
    parallel:
      enabled: false
    tdd_mode: false
    tdd_refactor: false
    serial_task:
      max_parallel_tasks: 1
  reporting:
    format: allure|custom
    coverage_target: 80
    zero_skip_required: true
    parallel:
      enabled: true
  code_review:
    enabled: true
    block_on_critical: false

# 门禁配置
gates:
  user_confirmation:
    after_phase_1: false
    after_phase_3: false

# 测试配置
test_suites:
  unit: {command: "npm test", type: unit}
  e2e: {command: "npx playwright test", type: e2e}
test_pyramid:
  min_unit_pct: 30
  max_e2e_pct: 40
  min_total_cases: 10

# 上下文管理
context_management:
  squash_on_archive: true
  auto_compact_threshold: 80

# 模型路由
model_routing:
  enabled: true
  default_session_model: opus
  phases:
    "2": {tier: fast, model: haiku}
    "5": {tier: deep, model: opus}

# 服务
services:
  backend: http://localhost:8080
  frontend: http://localhost:3000
```

---

> 本文档由源码分析自动生成，基于 spec-autopilot v5.4.3 全部源文件。
