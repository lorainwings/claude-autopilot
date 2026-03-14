# spec-autopilot UI Redesign PRD

> **Full Title**: 全局功能与 UI 重构产品需求文档
> **Version**: v5.3
> **Target Consumer**: v0 / Stitch / Bolt 等 AI UI 生成工具
> **Design Philosophy**: Cyberpunk Autonomous Driving Dashboard — 赛博朋克自动驾驶大盘

---

## 1. 视觉风格与交互定义 (Design System & Vibe)

### 1.1 视觉基调: "Deep Space Command Center"

融合三大美学体系:

| 层次 | 风格 | 参考 |
|------|------|------|
| **底层** | Deep Space IDE — 太空站指挥中心的冷峻纵深感 | 深空黑背景 + 微星点噪声纹理 |
| **中层** | Cyberpunk Neon — 霓虹流光勾勒数据边界 | Cyan/Magenta 双色辉光描边 |
| **表层** | Hacker Terminal — 黑客终端的极客信息密度 | 等宽字体 + ANSI 色彩 + 扫描线 |

### 1.2 色彩系统

#### 基础色板 (Background & Structure)

```css
--void:       #06080c;    /* 最深背景 — 宇宙虚空 */
--abyss:      #0a0e14;    /* 主背景 — 深渊 */
--deep:       #0d1117;    /* 次级面板背景 */
--surface:    #161b22;    /* 浮起面板/卡片背景 */
--elevated:   #1c2333;    /* 高亮面板 / hover 态 */
--border:     #21262d;    /* 默认边框 */
--border-glow:#2d333b;    /* 聚焦态边框 */
--text-muted: #484f58;    /* 辅助文字 */
--text:       #c9d1d9;    /* 主文字 */
--text-bright:#e6edf3;    /* 强调文字 */
```

#### 语义色 (Semantic Colors)

| 语义 | 色值 | 用途 | Glow 辐射 |
|------|------|------|----------|
| **Cyan** (主色) | `#00d9ff` | 当前阶段高亮、连接指示、主按钮 | `0 0 20px rgba(0,217,255,0.4)` |
| **Emerald** (通过) | `#10b981` | Phase 通过、Gate Pass、测试成功 | `0 0 15px rgba(16,185,129,0.3)` |
| **Amber** (警告) | `#fbbf24` | Warning 状态、人工介入等待、TDD Yellow | `0 0 15px rgba(251,191,36,0.3)` |
| **Rose** (阻断) | `#f43f5e` | Blocked/Failed、Gate Block、错误 | `0 0 20px rgba(244,63,94,0.5)` |
| **Violet** (进行中) | `#8b5cf6` | Running 动画、Phase 进行中 | `0 0 15px rgba(139,92,246,0.3)` |
| **Blue** (信息) | `#3b82f6` | 中性信息、链接、次要操作 | `0 0 10px rgba(59,130,246,0.2)` |

#### TDD 专用色

| 阶段 | 色值 | 含义 |
|------|------|------|
| RED | `#ef4444` | 编写失败测试 |
| GREEN | `#22c55e` | 最小实现通过 |
| REFACTOR | `#6366f1` | 重构优化 |

### 1.3 字体系统

```css
--font-mono:    "JetBrains Mono", "Fira Code", "SF Mono", "Menlo", monospace;
--font-display: "Orbitron", "Rajdhani", "Exo 2", sans-serif;  /* 标题/数字 */
--font-body:    "Inter", "SF Pro", system-ui, sans-serif;
```

| 场景 | 字体 | 大小 | 字重 |
|------|------|------|------|
| Phase 编号 | display | 32px | 700 |
| 阶段名称 | display | 14px | 500 |
| 数据数值 | mono | 24px | 700 |
| 正文/日志 | mono | 13px | 400 |
| 标签/Badge | body | 11px | 600 |

### 1.4 动效规范

#### 核心动效

| 动效名称 | 触发条件 | 描述 | 持续时间 |
|----------|----------|------|----------|
| **Scanline** | 全局常驻 | 半透明水平扫描线从上至下循环移动 (opacity 0.03) | 8s loop |
| **Grid Pulse** | 全局常驻 | 50x50px 网格背景以 0.5Hz 频率微弱呼吸 | 2s ease-in-out |
| **Phase Glow** | Phase `running` | 当前阶段节点 Cyan 辉光脉冲扩散 | 1.5s infinite |
| **Gate Alert** | Gate Block 触发 | 全屏边缘 Rose 脉冲闪烁 (vignette 效果) + 卡片抖动 | 0.6s × 3 |
| **Data Stream** | 新事件到达 | Terminal 文字打字机逐字显示 + 光标闪烁 | 30ms/char |
| **Task Spawn** | task_progress 首次出现 | Kanban 卡片从底部滑入 + scale(0.95→1) | 300ms ease-out |
| **Task Complete** | task status=passed | 卡片边框 Emerald 闪光 + checkmark 动画 | 500ms |
| **Task Fail** | task status=failed | 卡片 Rose 震动 (translateX ±3px) | 200ms × 2 |
| **Connection** | WebSocket 连接/断开 | 右上角信号点: 连接=Emerald 脉冲, 断开=Rose 闪烁 | 1s |
| **Phase Transition** | phase_end → phase_start | Timeline 连接线上的流光粒子从完成节点滑向新节点 | 800ms |
| **Decision Popup** | gate_decision_pending | 弹窗从中心 scale(0.8→1) + 背景 blur(8px) | 400ms spring |
| **Override Ripple** | Override 按钮点击 | 按钮中心向外扩散的 Amber 波纹 | 600ms |

#### 动效节制原则

- 所有装饰性动效支持 `prefers-reduced-motion` 媒体查询自动关闭
- 信息性动效 (Phase 切换、Gate 弹窗) 保留但简化为 opacity fade
- Terminal 打字机效果在高频事件 (>5/s) 时降级为批量渲染

---

## 2. 全局布局架构 (Global Layout Structure)

### 2.1 大屏仪表盘布局 (1920×1080 基准)

```
┌──────────────────────────────────────────────────────────────────────┐
│  ▌HEADER BAR (h: 48px)                                              │
│  [⬡ AUTOPILOT v5.3]  change: feature-add-auth  session: a1b2c3     │
│  mode: FULL ●                                              🟢 Live  │
├────────┬─────────────────────────────────────────────┬───────────────┤
│        │                                             │               │
│  LEFT  │          CENTER MAIN AREA                   │    RIGHT      │
│ PANEL  │                                             │   PANEL       │
│(w:220) │  ┌───────────────────────────────────────┐  │  (w: 360)     │
│        │  │                                       │  │               │
│ Phase  │  │     <ParallelKanban>                  │  │  <Telemetry   │
│ Time-  │  │     并发任务看板 (h: 45%)              │  │   Dashboard>  │
│ line   │  │                                       │  │               │
│        │  │                                       │  │  ┌─────────┐  │
│ ▼ P0   │  ├───────────────────────────────────────┤  │  │Token消耗│  │
│ ✓ P1   │  │                                       │  │  │Ring图   │  │
│ ✓ P2   │  │     <HackerTerminal>                  │  │  └─────────┘  │
│ ● P3   │  │     实时日志终端 (h: 55%)              │  │  ┌─────────┐  │
│ ○ P4   │  │                                       │  │  │Phase耗时│  │
│ ○ P5   │  │                                       │  │  │Bars     │  │
│ ○ P6   │  │                                       │  │  └─────────┘  │
│ ○ P7   │  │                                       │  │  ┌─────────┐  │
│        │  │                                       │  │  │Gate统计 │  │
│ ──────── │  └───────────────────────────────────────┘  │  │Pie      │  │
│ 00:12:34 │                                             │  └─────────┘  │
│ elapsed  │                                             │               │
│        │                                             │  ┌─────────┐  │
│        │                                             │  │测试金字塔│  │
│        │                                             │  └─────────┘  │
└────────┴─────────────────────────────────────────────┴───────────────┘
```

### 2.2 区域说明

| 区域 | 定位 | 尺寸 | 核心职责 |
|------|------|------|----------|
| **Header Bar** | 顶部固定 | 100% × 48px | 全局元信息: 版本、change_name、session_id、mode badge、连接状态 |
| **Left Panel** (PhaseTimeline) | 左侧固定 | 220px × (vh-48px) | 纵向 Phase 0-7 时间轴 + 总耗时 + 阶段状态 |
| **Center Main** | 中央弹性 | flex-1 × 100% | 上半 (45%): ParallelKanban; 下半 (55%): HackerTerminal |
| **Right Panel** | 右侧固定 | 360px × (vh-48px) | TelemetryDashboard: 环形图 + 柱状图 + 统计面板 |
| **Overlay** (InterventionModal) | 全局浮层 | 居中 520px | Gate Block 弹窗 — 触发时覆盖全屏 |

### 2.3 响应式策略

| 断点 | 布局调整 |
|------|----------|
| **≥1920px** | 标准三栏 (220 + flex + 360) |
| **1280-1919px** | Right Panel 收窄至 280px, Telemetry 切换为紧凑模式 |
| **768-1279px** | Left Panel 折叠为顶部水平 Tab, Right Panel 折叠为底部抽屉 |
| **<768px** | 单栏, PhaseTimeline 变为顶部水平滚动条, 其余垂直堆叠 |

---

## 3. 全局生命周期与模块清单 (Comprehensive Feature List)

### 3.1 核心流转: Phase 0 — Phase 7

| Phase | 名称 | 中文 | 描述 | UI 呈现 | 关键数据 |
|-------|------|------|------|---------|----------|
| **0** | Environment Setup | 环境初始化 | 版本检查、配置验证、崩溃恢复扫描、锁文件创建、锚点 commit | Timeline 节点: 齿轮图标, 快速闪过 | `version`, `mode`, `session_id`, `recovery_phase` |
| **1** | Requirements | 需求理解 | 三路并行研究 (Auto-Scan + Tech Research + Web Search) → 复杂度评估 → 多轮决策 → 结构化 Prompt | Timeline 节点: 脑图标, 最长驻留 | `complexity`, `decisions[]`, `requirement_type`, `routing_overrides`, `web_research` |
| **2** | OpenSpec | OpenSpec 创建 | 提取 kebab-case 名称, 创建 OpenSpec change 结构 (prd/discussion/ai-prompt) | Timeline 节点: 文件夹图标, 背景运行 | `change_name`, `artifacts[]` |
| **3** | Fast-Forward | 快速生成 | OpenSpec FF 流: 生成 proposal/specs/design/tasks 制品 | Timeline 节点: 火箭图标, 背景运行 | `artifacts[]` (4 documents) |
| **4** | Test Design | 测试设计 | 创建 unit/api/e2e/ui 测试用例, 验证测试金字塔, dry-run 语法检查 | Timeline 节点: 盾牌图标, **warning 不允许** | `test_counts{}`, `test_pyramid{}`, `change_coverage{}`, `sad_path_counts{}`, `dry_run_results{}` |
| **5** | Implementation | 代码实施 | 三条互斥路径: 并行 (Worktree) / 串行 / TDD (RED-GREEN-REFACTOR) | Timeline 节点: 代码图标, **最核心阶段** — Kanban 全面展示 | `tasks_completed`, `zero_skip_check`, `parallel_metrics{}`, `tdd_metrics{}` |
| **6** | Test Report | 测试报告 | 三路并行: 测试执行 + 代码审查 + 质量扫描 → Allure 报告 | Timeline 节点: 图表图标 | `pass_rate`, `suite_results[]`, `anomaly_alerts[]`, `code_review_findings[]` |
| **7** | Archive | 归档清理 | 用户确认 → Git Squash → OpenSpec 归档 → 锁文件删除 → 知识提取 | Timeline 节点: 归档图标, **需用户确认** | `archived_change`, `knowledge_extracted`, `phase_summary[]` |

#### Mode 路径差异 (UI 需动态隐藏 skip 的阶段)

| 模式 | 活跃阶段 | 跳过阶段 | Total Phases |
|------|----------|----------|-------------|
| **full** | 0→1→2→3→4→5→6→7 | 无 | 8 |
| **lite** | 0→1→5→6→7 | 2, 3, 4 | 5 |
| **minimal** | 0→1→5→7 | 2, 3, 4, 6 | 4 |

### 3.2 微观并发: Task/Agent 层

Phase 5 (Implementation) 是并发的核心阶段。UI 必须展示以下 Task 粒度数据:

#### Task 属性

| 字段 | 类型 | 描述 | UI 呈现 |
|------|------|------|---------|
| `task_name` | string | 任务标识 (如 "task-1-add-login") | Kanban 卡片标题 |
| `status` | enum | `running` \| `passed` \| `failed` \| `retrying` | 状态 Badge + 左边框颜色 |
| `task_index` | number | 当前序号 (1-based) | 进度: "3/10" |
| `task_total` | number | 总任务数 | 进度分母 |
| `tdd_step` | enum? | `red` \| `green` \| `refactor` (仅 TDD 模式) | TDD 步骤图标 (🔴🟢🔵) |
| `retry_count` | number? | 重试次数 | 橙色重试 Badge |
| `timestamp` | ISO-8601 | 最后更新时间 | 相对时间 ("12s ago") |

#### 并行模式额外展示

| 字段 | 来源 | UI 呈现 |
|------|------|---------|
| `parallel_metrics.mode` | phase-5 checkpoint | Badge: "PARALLEL" / "SERIAL" |
| `parallel_metrics.groups_count` | phase-5 checkpoint | "3 域并行" |
| `parallel_metrics.fallback_reason` | phase-5 checkpoint | 若降级, 显示原因 |
| `tdd_metrics.total_cycles` | phase-5 checkpoint | TDD 总循环数 |
| `tdd_metrics.red_violations` | phase-5 checkpoint | 必须=0, 否则红色告警 |
| `tdd_metrics.refactor_reverts` | phase-5 checkpoint | 重构回滚次数 |

### 3.3 拦截门禁: Gate System

#### 三层防线展示

| 层级 | 名称 | 类型 | UI 需展示 | 触发时机 |
|------|------|------|----------|----------|
| **L1** | Task Dependency | 自动 | 灰色锁图标 — Phase N+1 节点被锁定直到 N 完成 | Phase dispatch 前 |
| **L2** | Hook Validation | 确定性 | 橙色挡板 — 显示 Hook 脚本名 + 拦截原因 | Task 执行前/后 |
| **L3** | AI Gate 8-Step | AI 语义 | 门禁得分卡 (如 "6/8 PASSED") + 每步 ✓/✗ 清单 | Phase 转换时 |

#### Gate Block 弹窗必须包含的字段

| 字段 | 来源 | 描述 |
|------|------|------|
| `phase` | 事件 phase 字段 | 被阻断的目标 Phase 编号 |
| `phase_label` | 事件 phase_label 字段 | 人可读阶段名 |
| `gate_score` | payload.gate_score | 门禁通过得分 (如 "5/8") |
| `error_message` | payload.error_message | 阻断原因详情 (可多行) |
| `status` | payload.status | blocked / failed |
| `blocked_step` | payload.blocked_step (决策请求) | 具体失败步骤编号 |
| `fix_instructions` | 用户输入 | 修复指令 (多行文本框, 仅 fix 动作) |

#### Gate 决策按钮

| 动作 | 按钮文案 | 颜色 | 行为 |
|------|----------|------|------|
| `retry` | 🔄 Retry (重新验证) | Cyan/Blue | 重新执行 8-step 门禁检查 |
| `fix` | 🔧 Fix (修复后重试) | Amber | 展开 fix_instructions 输入框, 用户填写后提交 |
| `override` | ⚡ Override (强制通过) | Rose/Orange | 跳过门禁检查继续 (高危操作, 需二次确认) |

#### Anti-Rationalization 展示 (当被触发时)

在 Gate Block 弹窗中额外显示:

| 字段 | 描述 |
|------|------|
| 匹配模式 | 命中的 excuse pattern (高亮显示) |
| 权重得分 | 每条模式的权重 (3/2/1 分) + 总分 |
| 阻断阈值 | 当前分值 vs 阻断阈值 (≥5 硬阻断, ≥3 无制品阻断) |

---

## 4. 核心 UI 组件蓝图 (Core Component Blueprints)

### 4.1 `<PhaseTimeline>` — 阶段时间轴

**位置**: 左侧面板 (220px 宽, 全高)

**视觉**: 纵向时间轴, 每个节点是一个六角形 (hexagonal clip-path) 图标, 节点间由发光连接线串联。

**节点状态映射**:

| 状态 | 节点样式 | 连接线样式 |
|------|----------|-----------|
| `pending` | 空心灰色六角形, 灰色图标 | 灰色虚线 |
| `running` | Cyan 辉光脉冲六角形, 白色图标 + 旋转粒子环 | Cyan 实线, 流光粒子动画 |
| `ok` | 实心 Emerald 六角形, 白色 ✓ | Emerald 实线 |
| `warning` | 实心 Amber 六角形, 黑色 ⚠ | Amber 实线 |
| `blocked` | 实心 Rose 六角形, 白色 ✗, 震动动画 | Rose 实线 |
| `failed` | 实心 Rose 六角形 (更暗), 白色 💀 | Rose 虚线 |
| `skipped` | 半透明灰色 (mode skip), 斜线穿透 | 灰色点线 (跨越连接) |

**节点数据卡 (hover/展开)**:

```
┌─────────────────────┐
│  ⬡ Phase 5          │  ← 六角形图标 + Phase 编号
│  Implementation      │  ← 阶段名称
│  ─────────────────  │
│  Status: ● RUNNING   │  ← 状态 Badge
│  Duration: 00:03:42  │  ← 持续时间 (实时计时)
│  Tasks: 7/10         │  ← 子任务进度
│  Mode: PARALLEL      │  ← 执行模式
└─────────────────────┘
```

**底部统计区**:

```
──────────────
Total Elapsed
  00:12:34
──────────────
 Phases: 5/8
 Gates: 4 ✓ 1 ✗
```

### 4.2 `<ParallelKanban>` — 并发任务看板

**位置**: 中央上半区 (flex, 45% 高度)

**视觉**: 类似赛车仪表盘的并行车道布局。每个 Task 是一条独立的"赛道"。

**全局进度条 (顶部)**:

```
┌─────────────────────────────────────────────────────────┐
│  ■■■■■■■■■■■■■■■□□□□□  7/10 Tasks  │  PARALLEL  │  TDD │
└─────────────────────────────────────────────────────────┘
```

**单任务卡片**:

```
┌─ Emerald ──────────────────────────────────────────────────┐
│                                                             │
│  task-3-database-schema                          ✓ PASSED   │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━ 100%                           │
│                                                             │
│  🟢 GREEN  │  ⏱ 01:23  │  Retry: 0  │  Task 3/10          │
│                                                             │
└─────────────────────────────────────────────────────────────┘

┌─ Violet ───────────────────────────────────────────────────┐
│                                                             │
│  task-5-frontend-auth                            ● RUNNING  │
│  ━━━━━━━━━━━━━━━━━░░░░░░░░░ 60%                            │
│                                                             │
│  🔴 RED    │  ⏱ 00:45  │  Retry: 0  │  Task 5/10          │
│                                                             │
└─────────────────────────────────────────────────────────────┘

┌─ Rose ─────────────────────────────────────────────────────┐
│                                                             │
│  task-7-api-endpoints                            ✗ FAILED   │
│  ━━━━━━━━━━━━━━━━━━━━━░░░░░ 80%                            │
│                                                             │
│  🟢 GREEN  │  ⏱ 02:10  │  Retry: 1 ⟲  │  Task 7/10       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**卡片视觉规则**:

| 状态 | 左边框色 | 背景 | 进度条色 | 特效 |
|------|---------|------|---------|------|
| `running` | Violet | `--deep` | Cyan 动态 | 进度条脉冲 |
| `passed` | Emerald | `--deep` | Emerald 静态 | 完成闪光 |
| `failed` | Rose | `--surface` + Rose tint | Rose 静态 | 震动效果 |
| `retrying` | Amber | `--surface` + Amber tint | Amber 动态 | 旋转 ⟲ 图标 |

**TDD 步骤指示器**:

```
┌─────────────────────────────┐
│  🔴 RED  →  🟢 GREEN  →  🔵 REFACTOR  │
│  ████       ░░░░         ░░░░░░░      │  ← 当前步骤高亮
└─────────────────────────────┘
```

**空状态**: 当 currentPhase ≠ 5 且无 task 数据时:
```
     ┌─────────────────────┐
     │  ◇ Awaiting Phase 5 │
     │  Tasks will appear   │
     │  here when running   │
     └─────────────────────┘
```

### 4.3 `<InterventionModal>` — 拦截阻断弹窗

**位置**: 全屏居中浮层 (520px 宽)
**触发**: `gate_block` 事件到达 或 `gate_decision_pending` 事件

**视觉**: 深色毛玻璃背景 (backdrop-filter: blur(8px)) + Rose 边框脉冲 + 顶部红色警示条

**布局**:

```
┌──────────────────────────────────────────────────────┐
│  ⚠ GATE BLOCKED                          Phase 5→6  │  ← Rose header
├──────────────────────────────────────────────────────┤
│                                                      │
│  Gate Score:  ████████░░  6/8                        │  ← 进度条 + 分数
│                                                      │
│  ┌────────────────────────────────────────────────┐  │
│  │ Error Details                                  │  │  ← Rose 背景框
│  │                                                │  │
│  │ Phase 5 → Phase 6 gate failed at Step 4:      │  │
│  │ zero_skip_check.passed = false                │  │
│  │ 3 tests were skipped in test-results.json     │  │
│  │                                                │  │
│  └────────────────────────────────────────────────┘  │
│                                                      │
│  ┌────────────────────────────────────────────────┐  │
│  │ 🔧 Fix Instructions (optional)                │  │  ← Amber 边框
│  │                                                │  │
│  │  [多行文本输入框, placeholder:                  │  │
│  │   "输入修复指令, 如: 移除 test.skip()..."]     │  │
│  │                                                │  │
│  └────────────────────────────────────────────────┘  │
│                                                      │
│  ┌────────────────────────────────────────────────┐  │
│  │ Anti-Rationalization Alert (条件显示)           │  │  ← 仅当触发时
│  │ Score: 5/5 (HARD BLOCK)                       │  │
│  │ Matched: "will be done later" (3pts)          │  │
│  │          "not necessary" (2pts)               │  │
│  └────────────────────────────────────────────────┘  │
│                                                      │
│  ┌──────────┐  ┌──────────┐  ┌───────────────────┐  │
│  │ 🔄 Retry │  │ 🔧 Fix   │  │ ⚡ Override       │  │  ← 三个按钮
│  │  (Cyan)   │  │ (Amber)  │  │ (Rose + 二次确认) │  │
│  └──────────┘  └──────────┘  └───────────────────┘  │
│                                                      │
│  Timeout: 04:32 remaining                            │  ← 倒计时 (300s)
└──────────────────────────────────────────────────────┘
```

**Override 二次确认**:

点击 Override 后, 按钮变为:
```
┌──────────────────────────────────┐
│  ⚠ Confirm Override? [Yes] [No] │  ← 3秒后自动恢复
└──────────────────────────────────┘
```

**Decision ACK 反馈**:

决策发送后, 弹窗显示:
```
  ✓ Decision sent: retry
  Waiting for acknowledgment...  ← Spinner
```

收到 `decision_ack` → 弹窗 500ms 后 fade out 消失。

### 4.4 `<TelemetryDashboard>` — 遥测数据面板

**位置**: 右侧面板 (360px 宽, 全高)

**布局** (4 个堆叠的数据卡):

#### Card 1: Token/耗时 环形图

```
┌─────────────────────────────────┐
│  ◉ Session Metrics              │
│                                 │
│      ╭───────────╮              │
│     ╱  00:12:34   ╲             │  ← 环形图中心: 总耗时
│    │   Total Time   │            │
│     ╲             ╱             │  ← 环形分段: 每 Phase 占比
│      ╰───────────╯              │
│                                 │
│  Phases Completed: 5/8          │
│  Retries: 2                     │
│  Gates Passed: 4                │
│  Gates Blocked: 1               │
└─────────────────────────────────┘
```

#### Card 2: Phase 耗时柱状图

```
┌─────────────────────────────────┐
│  ◉ Phase Duration               │
│                                 │
│  P0 ████░░░░░░░░░  0:02        │
│  P1 ████████████░░  0:08        │
│  P2 ██░░░░░░░░░░░  0:01        │
│  P3 ███░░░░░░░░░░  0:02        │
│  P4 ████████░░░░░  0:05        │
│  P5 █████████████████  0:12     │  ← 最长阶段高亮
│  P6 ██████░░░░░░░  0:04        │
│  P7 ░░░░░░░░░░░░░  --:--       │  ← pending 灰色
└─────────────────────────────────┘
```

#### Card 3: Gate 统计

```
┌─────────────────────────────────┐
│  ◉ Gate Statistics              │
│                                 │
│  ┌─────┐  Pass: 4  ████████    │
│  │ Pie │  Block: 1 ██          │  ← 扇形图
│  │Chart│  Pending: 3 ██████    │
│  └─────┘                        │
│                                 │
│  Last Block:                    │
│  Phase 5→6, Score 6/8          │
│  "zero_skip_check failed"      │
└─────────────────────────────────┘
```

#### Card 4: 测试金字塔 (仅 Phase 4+ 显示)

```
┌─────────────────────────────────┐
│  ◉ Test Pyramid                 │
│                                 │
│         ╱╲         E2E: 6 (24%)│
│        ╱  ╲                    │
│       ╱────╲       API: 6 (24%)│
│      ╱      ╲                  │
│     ╱────────╲     Unit: 13(52%)│  ← 颜色编码: 达标=Emerald, 未达=Rose
│                                 │
│  Coverage: 90%  ████████░░      │
│  Sad Path: 22%  █████░░░░░      │
│  Total: 25 cases               │
│                                 │
│  Requirement Type: BUGFIX       │  ← 路由类型 Badge
│  Thresholds: sad≥40% cov=100%  │  ← 动态阈值
└─────────────────────────────────┘
```

### 4.5 `<HackerTerminal>` — 极客终端

**位置**: 中央下半区 (flex, 55% 高度)

**视觉**: 全黑背景 xterm.js 终端, 顶部有闪烁光标标题栏。

**标题栏**:

```
┌──────────────────────────────────────────────────────────┐
│  ● EVENT STREAM  │  Events: 142  │  Filter: [All ▾]     │
├──────────────────────────────────────────────────────────┤
```

**事件格式** (ANSI 色彩):

```ansi
[09:15:23] PHASE_START  │ Phase 5 (Implementation) ─── mode: full
[09:15:24] TASK_PROGRESS │ Phase 5 ─── task-1-frontend-auth: RUNNING [1/10]
[09:15:30] TASK_PROGRESS │ Phase 5 ─── task-1-frontend-auth: 🔴 RED
[09:16:02] TASK_PROGRESS │ Phase 5 ─── task-1-frontend-auth: 🟢 GREEN
[09:16:15] TASK_PROGRESS │ Phase 5 ─── task-1-frontend-auth: ✓ PASSED [1/10]
[09:16:16] TASK_PROGRESS │ Phase 5 ─── task-2-backend-api: RUNNING [2/10]
[09:18:30] GATE_BLOCK    │ Phase 5→6 ─── score: 6/8, zero_skip_check failed
[09:18:31] GATE_PENDING  │ Phase 5→6 ─── awaiting decision (timeout: 300s)
[09:19:05] GATE_DECISION │ Phase 5→6 ─── action: retry (elapsed: 34s)
[09:19:10] GATE_PASS     │ Phase 5→6 ─── score: 8/8 ✓
[09:19:11] PHASE_END     │ Phase 5 (Implementation) ─── status: ok, duration: 3m47s
```

**ANSI 颜色映射**:

| 事件类型 | 前景色 | 样式 |
|----------|--------|------|
| `phase_start` | Blue (#3b82f6) | Normal |
| `phase_end` | Emerald (#10b981) | Normal |
| `gate_pass` | Emerald (#10b981) | Bold |
| `gate_block` | Rose (#f43f5e) | Bold + 全行高亮 |
| `task_progress` | Cyan (#00d9ff) | Normal |
| `error` | Bright Rose (#ff6b6b) | Bold |
| `gate_decision_pending` | Amber (#fbbf24) | Normal |
| `gate_decision_received` | Violet (#8b5cf6) | Normal |

**过滤器下拉**:

```
[All] [Phases Only] [Gates Only] [Tasks Only] [Errors Only]
```

**功能要求**:
- 支持 ANSI 256 色 + 部分 TrueColor
- 自动滚动到底部 (可手动暂停/恢复)
- 增量渲染: 仅追加 `sequence > lastRenderedSequence` 的事件
- 高频保护: 事件 >5/s 时切换为批量渲染 (100ms 缓冲)

### 4.6 `<HeaderBar>` — 顶部信息栏

**位置**: 顶部固定 48px

```
┌──────────────────────────────────────────────────────────────────────────┐
│  ⬡ AUTOPILOT v5.3.0    │   change: feature-add-auth                    │
│                          │   session: a1b2c3d4                           │
│  [FULL] mode             │                                    🟢 Live    │
└──────────────────────────────────────────────────────────────────────────┘
```

**组成元素**:

| 元素 | 数据源 | 样式 |
|------|--------|------|
| Logo + Version | plugin.json version | Orbitron 字体, Cyan |
| Mode Badge | `event.mode` | `FULL`=Cyan, `LITE`=Amber, `MINIMAL`=灰色 |
| Change Name | `event.change_name` | mono 字体, truncate 20ch |
| Session ID | `event.session_id` | mono 字体, 显示前 8 字符 |
| Connection | WebSocket 状态 | 🟢 Live (脉冲) / 🔴 Disconnected (闪烁) |

---

## 5. Mock 数据结构 (State Interface for UI Gen)

### 5.1 TypeScript 接口定义

```typescript
// ===== 核心事件接口 =====

interface AutopilotEvent {
  type: EventType;
  phase: number;                    // 0-7
  mode: "full" | "lite" | "minimal";
  timestamp: string;                // ISO-8601
  change_name: string;
  session_id: string;
  phase_label: string;
  total_phases: number;             // 8 | 5 | 4
  sequence: number;                 // 全局自增
  payload: EventPayload;
}

type EventType =
  | "phase_start"
  | "phase_end"
  | "gate_pass"
  | "gate_block"
  | "task_progress"
  | "error"
  | "gate_decision_pending"
  | "gate_decision_received";

interface EventPayload {
  status?: "ok" | "warning" | "blocked" | "failed";
  duration_ms?: number;
  error_message?: string;
  artifacts?: string[];
  gate_score?: string;              // e.g., "8/8"
  task_name?: string;
  task_index?: number;
  task_total?: number;
  tdd_step?: "red" | "green" | "refactor";
  retry_count?: number;
  awaiting_decision?: boolean;
  timeout_seconds?: number;
  action?: "retry" | "fix" | "override";
  elapsed_seconds?: number;
}

// ===== Task 进度 =====

interface TaskProgress {
  task_name: string;
  status: "running" | "passed" | "failed" | "retrying";
  tdd_step?: "red" | "green" | "refactor";
  retry_count?: number;
  task_index: number;
  task_total: number;
  timestamp: string;
}

// ===== Phase 状态 =====

interface PhaseState {
  phase: number;
  label: string;
  status: "pending" | "running" | "ok" | "warning" | "blocked" | "failed" | "skipped";
  start_time?: string;
  end_time?: string;
  duration_ms?: number;
  artifacts?: string[];
}

// ===== Gate 记录 =====

interface GateRecord {
  phase: number;
  type: "pass" | "block";
  gate_score?: string;
  error_message?: string;
  timestamp: string;
  decision?: {
    action: "retry" | "fix" | "override";
    elapsed_seconds: number;
  };
}

// ===== Checkpoint 数据 (遥测) =====

interface TelemetryData {
  session_id: string;
  change_name: string;
  mode: "full" | "lite" | "minimal";
  total_elapsed_ms: number;
  phases: PhaseState[];
  gates: GateRecord[];
  test_pyramid?: {
    unit: number;
    unit_pct: number;
    api: number;
    api_pct: number;
    e2e: number;
    e2e_pct: number;
    total: number;
  };
  change_coverage?: {
    coverage_pct: number;
    change_points: number;
    tested_points: number;
  };
  sad_path_ratio?: number;
  requirement_type?: "feature" | "bugfix" | "refactor" | "chore";
  pass_rate?: number;
}

// ===== 决策请求 =====

interface DecisionRequest {
  phase: number;
  blocked_step: number;
  error_message: string;
  gate_score: string;
  timestamp: string;
  timeout_seconds: number;
}

// ===== 全局 Store =====

interface AppState {
  events: AutopilotEvent[];
  connected: boolean;
  currentPhase: number | null;
  sessionId: string | null;
  changeName: string | null;
  mode: "full" | "lite" | "minimal";
  taskProgress: Map<string, TaskProgress>;
  decisionAcked: boolean;
  telemetry: TelemetryData;
}
```

### 5.2 完整 Mock JSON 数据样例

以下 Mock 数据模拟一个 **Full 模式、TDD 开启、Phase 5 并行执行中、遭遇一次 Gate Block** 的真实场景:

```json
{
  "metadata": {
    "session_id": "1710403200042",
    "change_name": "feature-user-authentication",
    "mode": "full",
    "total_phases": 8,
    "version": "5.3.0"
  },
  "events": [
    {
      "type": "phase_start",
      "phase": 0,
      "mode": "full",
      "timestamp": "2026-03-14T09:00:00.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Environment Setup",
      "total_phases": 8,
      "sequence": 1,
      "payload": {}
    },
    {
      "type": "phase_end",
      "phase": 0,
      "mode": "full",
      "timestamp": "2026-03-14T09:00:02.150Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Environment Setup",
      "total_phases": 8,
      "sequence": 2,
      "payload": {
        "status": "ok",
        "duration_ms": 2150
      }
    },
    {
      "type": "phase_start",
      "phase": 1,
      "mode": "full",
      "timestamp": "2026-03-14T09:00:03.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Requirements",
      "total_phases": 8,
      "sequence": 3,
      "payload": {}
    },
    {
      "type": "phase_end",
      "phase": 1,
      "mode": "full",
      "timestamp": "2026-03-14T09:08:15.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Requirements",
      "total_phases": 8,
      "sequence": 4,
      "payload": {
        "status": "ok",
        "duration_ms": 492000,
        "artifacts": [
          "openspec/changes/feature-user-authentication/context/phase-1-requirements.json"
        ]
      }
    },
    {
      "type": "gate_pass",
      "phase": 2,
      "mode": "full",
      "timestamp": "2026-03-14T09:08:16.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "OpenSpec",
      "total_phases": 8,
      "sequence": 5,
      "payload": {
        "gate_score": "8/8",
        "status": "ok"
      }
    },
    {
      "type": "phase_start",
      "phase": 2,
      "mode": "full",
      "timestamp": "2026-03-14T09:08:17.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "OpenSpec",
      "total_phases": 8,
      "sequence": 6,
      "payload": {}
    },
    {
      "type": "phase_end",
      "phase": 2,
      "mode": "full",
      "timestamp": "2026-03-14T09:09:30.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "OpenSpec",
      "total_phases": 8,
      "sequence": 7,
      "payload": {
        "status": "ok",
        "duration_ms": 73000,
        "artifacts": [
          "openspec/changes/feature-user-authentication/proposal.md",
          "openspec/changes/feature-user-authentication/context/prd.md"
        ]
      }
    },
    {
      "type": "gate_pass",
      "phase": 3,
      "mode": "full",
      "timestamp": "2026-03-14T09:09:31.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Fast-Forward",
      "total_phases": 8,
      "sequence": 8,
      "payload": {
        "gate_score": "8/8",
        "status": "ok"
      }
    },
    {
      "type": "phase_start",
      "phase": 3,
      "mode": "full",
      "timestamp": "2026-03-14T09:09:32.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Fast-Forward",
      "total_phases": 8,
      "sequence": 9,
      "payload": {}
    },
    {
      "type": "phase_end",
      "phase": 3,
      "mode": "full",
      "timestamp": "2026-03-14T09:11:45.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Fast-Forward",
      "total_phases": 8,
      "sequence": 10,
      "payload": {
        "status": "ok",
        "duration_ms": 133000,
        "artifacts": [
          "openspec/changes/feature-user-authentication/proposal.md",
          "openspec/changes/feature-user-authentication/design.md",
          "openspec/changes/feature-user-authentication/specs.md",
          "openspec/changes/feature-user-authentication/tasks.md"
        ]
      }
    },
    {
      "type": "gate_pass",
      "phase": 4,
      "mode": "full",
      "timestamp": "2026-03-14T09:11:46.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Test Design",
      "total_phases": 8,
      "sequence": 11,
      "payload": {
        "gate_score": "8/8",
        "status": "ok"
      }
    },
    {
      "type": "phase_start",
      "phase": 4,
      "mode": "full",
      "timestamp": "2026-03-14T09:11:47.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Test Design",
      "total_phases": 8,
      "sequence": 12,
      "payload": {}
    },
    {
      "type": "phase_end",
      "phase": 4,
      "mode": "full",
      "timestamp": "2026-03-14T09:16:50.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Test Design",
      "total_phases": 8,
      "sequence": 13,
      "payload": {
        "status": "ok",
        "duration_ms": 303000,
        "artifacts": [
          "tests/unit/test_auth_service.py",
          "tests/api/test_auth_endpoints.py",
          "tests/e2e/test_login_flow.py",
          "tests/ui/test_login_form.py"
        ]
      }
    },
    {
      "type": "gate_pass",
      "phase": 5,
      "mode": "full",
      "timestamp": "2026-03-14T09:16:51.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Implementation",
      "total_phases": 8,
      "sequence": 14,
      "payload": {
        "gate_score": "8/8",
        "status": "ok"
      }
    },
    {
      "type": "phase_start",
      "phase": 5,
      "mode": "full",
      "timestamp": "2026-03-14T09:16:52.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Implementation",
      "total_phases": 8,
      "sequence": 15,
      "payload": {}
    },
    {
      "type": "task_progress",
      "phase": 5,
      "mode": "full",
      "timestamp": "2026-03-14T09:16:53.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Implementation",
      "total_phases": 8,
      "sequence": 16,
      "payload": {
        "task_name": "task-1-auth-service",
        "status": "running",
        "task_index": 1,
        "task_total": 10,
        "tdd_step": "red"
      }
    },
    {
      "type": "task_progress",
      "phase": 5,
      "mode": "full",
      "timestamp": "2026-03-14T09:16:54.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Implementation",
      "total_phases": 8,
      "sequence": 17,
      "payload": {
        "task_name": "task-2-jwt-middleware",
        "status": "running",
        "task_index": 2,
        "task_total": 10,
        "tdd_step": "red"
      }
    },
    {
      "type": "task_progress",
      "phase": 5,
      "mode": "full",
      "timestamp": "2026-03-14T09:16:55.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Implementation",
      "total_phases": 8,
      "sequence": 18,
      "payload": {
        "task_name": "task-3-password-hashing",
        "status": "running",
        "task_index": 3,
        "task_total": 10,
        "tdd_step": "red"
      }
    },
    {
      "type": "task_progress",
      "phase": 5,
      "mode": "full",
      "timestamp": "2026-03-14T09:17:30.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Implementation",
      "total_phases": 8,
      "sequence": 19,
      "payload": {
        "task_name": "task-1-auth-service",
        "status": "running",
        "task_index": 1,
        "task_total": 10,
        "tdd_step": "green"
      }
    },
    {
      "type": "task_progress",
      "phase": 5,
      "mode": "full",
      "timestamp": "2026-03-14T09:18:00.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Implementation",
      "total_phases": 8,
      "sequence": 20,
      "payload": {
        "task_name": "task-1-auth-service",
        "status": "running",
        "task_index": 1,
        "task_total": 10,
        "tdd_step": "refactor"
      }
    },
    {
      "type": "task_progress",
      "phase": 5,
      "mode": "full",
      "timestamp": "2026-03-14T09:18:15.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Implementation",
      "total_phases": 8,
      "sequence": 21,
      "payload": {
        "task_name": "task-1-auth-service",
        "status": "passed",
        "task_index": 1,
        "task_total": 10,
        "tdd_step": "refactor"
      }
    },
    {
      "type": "task_progress",
      "phase": 5,
      "mode": "full",
      "timestamp": "2026-03-14T09:18:30.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Implementation",
      "total_phases": 8,
      "sequence": 22,
      "payload": {
        "task_name": "task-2-jwt-middleware",
        "status": "running",
        "task_index": 2,
        "task_total": 10,
        "tdd_step": "green"
      }
    },
    {
      "type": "task_progress",
      "phase": 5,
      "mode": "full",
      "timestamp": "2026-03-14T09:19:00.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Implementation",
      "total_phases": 8,
      "sequence": 23,
      "payload": {
        "task_name": "task-3-password-hashing",
        "status": "failed",
        "task_index": 3,
        "task_total": 10,
        "tdd_step": "green",
        "retry_count": 1
      }
    },
    {
      "type": "task_progress",
      "phase": 5,
      "mode": "full",
      "timestamp": "2026-03-14T09:19:10.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Implementation",
      "total_phases": 8,
      "sequence": 24,
      "payload": {
        "task_name": "task-3-password-hashing",
        "status": "retrying",
        "task_index": 3,
        "task_total": 10,
        "tdd_step": "green",
        "retry_count": 1
      }
    },
    {
      "type": "task_progress",
      "phase": 5,
      "mode": "full",
      "timestamp": "2026-03-14T09:19:45.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Implementation",
      "total_phases": 8,
      "sequence": 25,
      "payload": {
        "task_name": "task-2-jwt-middleware",
        "status": "passed",
        "task_index": 2,
        "task_total": 10,
        "tdd_step": "green"
      }
    },
    {
      "type": "task_progress",
      "phase": 5,
      "mode": "full",
      "timestamp": "2026-03-14T09:20:00.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Implementation",
      "total_phases": 8,
      "sequence": 26,
      "payload": {
        "task_name": "task-4-session-store",
        "status": "running",
        "task_index": 4,
        "task_total": 10,
        "tdd_step": "red"
      }
    },
    {
      "type": "task_progress",
      "phase": 5,
      "mode": "full",
      "timestamp": "2026-03-14T09:20:30.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Implementation",
      "total_phases": 8,
      "sequence": 27,
      "payload": {
        "task_name": "task-3-password-hashing",
        "status": "passed",
        "task_index": 3,
        "task_total": 10,
        "tdd_step": "green",
        "retry_count": 1
      }
    },
    {
      "type": "task_progress",
      "phase": 5,
      "mode": "full",
      "timestamp": "2026-03-14T09:21:00.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Implementation",
      "total_phases": 8,
      "sequence": 28,
      "payload": {
        "task_name": "task-5-login-controller",
        "status": "running",
        "task_index": 5,
        "task_total": 10,
        "tdd_step": "red"
      }
    },
    {
      "type": "task_progress",
      "phase": 5,
      "mode": "full",
      "timestamp": "2026-03-14T09:21:30.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Implementation",
      "total_phases": 8,
      "sequence": 29,
      "payload": {
        "task_name": "task-4-session-store",
        "status": "running",
        "task_index": 4,
        "task_total": 10,
        "tdd_step": "green"
      }
    },
    {
      "type": "task_progress",
      "phase": 5,
      "mode": "full",
      "timestamp": "2026-03-14T09:22:00.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Implementation",
      "total_phases": 8,
      "sequence": 30,
      "payload": {
        "task_name": "task-6-logout-handler",
        "status": "running",
        "task_index": 6,
        "task_total": 10,
        "tdd_step": "red"
      }
    },
    {
      "type": "task_progress",
      "phase": 5,
      "mode": "full",
      "timestamp": "2026-03-14T09:22:30.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Implementation",
      "total_phases": 8,
      "sequence": 31,
      "payload": {
        "task_name": "task-4-session-store",
        "status": "passed",
        "task_index": 4,
        "task_total": 10,
        "tdd_step": "refactor"
      }
    },
    {
      "type": "task_progress",
      "phase": 5,
      "mode": "full",
      "timestamp": "2026-03-14T09:23:00.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Implementation",
      "total_phases": 8,
      "sequence": 32,
      "payload": {
        "task_name": "task-7-rbac-permissions",
        "status": "running",
        "task_index": 7,
        "task_total": 10,
        "tdd_step": "red"
      }
    },
    {
      "type": "task_progress",
      "phase": 5,
      "mode": "full",
      "timestamp": "2026-03-14T09:23:30.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Implementation",
      "total_phases": 8,
      "sequence": 33,
      "payload": {
        "task_name": "task-5-login-controller",
        "status": "passed",
        "task_index": 5,
        "task_total": 10,
        "tdd_step": "green"
      }
    },
    {
      "type": "phase_end",
      "phase": 5,
      "mode": "full",
      "timestamp": "2026-03-14T09:28:52.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Implementation",
      "total_phases": 8,
      "sequence": 40,
      "payload": {
        "status": "ok",
        "duration_ms": 720000,
        "artifacts": [
          "src/services/auth-service.ts",
          "src/middleware/jwt.ts",
          "src/utils/password.ts",
          "src/stores/session-store.ts",
          "src/controllers/login.ts",
          "src/controllers/logout.ts",
          "src/middleware/rbac.ts"
        ]
      }
    },
    {
      "type": "gate_block",
      "phase": 6,
      "mode": "full",
      "timestamp": "2026-03-14T09:28:53.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Test Report",
      "total_phases": 8,
      "sequence": 41,
      "payload": {
        "gate_score": "6/8",
        "status": "blocked",
        "error_message": "Phase 5→6 gate failed at Step 4:\nzero_skip_check.passed = false\n3 tests were skipped in test-results.json:\n  - test_session_expiry (skip reason: 'environment')\n  - test_concurrent_login (skip reason: 'flaky')\n  - test_oauth_callback (skip reason: 'external dependency')"
      }
    },
    {
      "type": "gate_decision_pending",
      "phase": 6,
      "mode": "full",
      "timestamp": "2026-03-14T09:28:54.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Test Report",
      "total_phases": 8,
      "sequence": 42,
      "payload": {
        "awaiting_decision": true,
        "timeout_seconds": 300
      }
    },
    {
      "type": "gate_decision_received",
      "phase": 6,
      "mode": "full",
      "timestamp": "2026-03-14T09:29:30.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Test Report",
      "total_phases": 8,
      "sequence": 43,
      "payload": {
        "action": "retry",
        "elapsed_seconds": 36
      }
    },
    {
      "type": "gate_pass",
      "phase": 6,
      "mode": "full",
      "timestamp": "2026-03-14T09:29:45.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Test Report",
      "total_phases": 8,
      "sequence": 44,
      "payload": {
        "gate_score": "8/8",
        "status": "ok"
      }
    },
    {
      "type": "phase_start",
      "phase": 6,
      "mode": "full",
      "timestamp": "2026-03-14T09:29:46.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Test Report",
      "total_phases": 8,
      "sequence": 45,
      "payload": {}
    },
    {
      "type": "phase_end",
      "phase": 6,
      "mode": "full",
      "timestamp": "2026-03-14T09:33:20.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Test Report",
      "total_phases": 8,
      "sequence": 46,
      "payload": {
        "status": "ok",
        "duration_ms": 214000,
        "artifacts": [
          "allure-report/index.html",
          "test-results.json"
        ]
      }
    },
    {
      "type": "gate_pass",
      "phase": 7,
      "mode": "full",
      "timestamp": "2026-03-14T09:33:21.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Archive",
      "total_phases": 8,
      "sequence": 47,
      "payload": {
        "gate_score": "8/8",
        "status": "ok"
      }
    },
    {
      "type": "phase_start",
      "phase": 7,
      "mode": "full",
      "timestamp": "2026-03-14T09:33:22.000Z",
      "change_name": "feature-user-authentication",
      "session_id": "1710403200042",
      "phase_label": "Archive",
      "total_phases": 8,
      "sequence": 48,
      "payload": {}
    }
  ],
  "currentState": {
    "currentPhase": 7,
    "connected": true,
    "decisionAcked": false,
    "taskProgress": {
      "task-1-auth-service": {
        "task_name": "task-1-auth-service",
        "status": "passed",
        "task_index": 1,
        "task_total": 10,
        "tdd_step": "refactor",
        "timestamp": "2026-03-14T09:18:15.000Z"
      },
      "task-2-jwt-middleware": {
        "task_name": "task-2-jwt-middleware",
        "status": "passed",
        "task_index": 2,
        "task_total": 10,
        "tdd_step": "green",
        "timestamp": "2026-03-14T09:19:45.000Z"
      },
      "task-3-password-hashing": {
        "task_name": "task-3-password-hashing",
        "status": "passed",
        "task_index": 3,
        "task_total": 10,
        "tdd_step": "green",
        "retry_count": 1,
        "timestamp": "2026-03-14T09:20:30.000Z"
      },
      "task-4-session-store": {
        "task_name": "task-4-session-store",
        "status": "passed",
        "task_index": 4,
        "task_total": 10,
        "tdd_step": "refactor",
        "timestamp": "2026-03-14T09:22:30.000Z"
      },
      "task-5-login-controller": {
        "task_name": "task-5-login-controller",
        "status": "passed",
        "task_index": 5,
        "task_total": 10,
        "tdd_step": "green",
        "timestamp": "2026-03-14T09:23:30.000Z"
      },
      "task-6-logout-handler": {
        "task_name": "task-6-logout-handler",
        "status": "running",
        "task_index": 6,
        "task_total": 10,
        "tdd_step": "green",
        "timestamp": "2026-03-14T09:22:00.000Z"
      },
      "task-7-rbac-permissions": {
        "task_name": "task-7-rbac-permissions",
        "status": "running",
        "task_index": 7,
        "task_total": 10,
        "tdd_step": "red",
        "timestamp": "2026-03-14T09:23:00.000Z"
      }
    },
    "telemetry": {
      "session_id": "1710403200042",
      "change_name": "feature-user-authentication",
      "mode": "full",
      "total_elapsed_ms": 2002000,
      "phases": [
        { "phase": 0, "label": "Environment Setup", "status": "ok", "duration_ms": 2150 },
        { "phase": 1, "label": "Requirements", "status": "ok", "duration_ms": 492000 },
        { "phase": 2, "label": "OpenSpec", "status": "ok", "duration_ms": 73000 },
        { "phase": 3, "label": "Fast-Forward", "status": "ok", "duration_ms": 133000 },
        { "phase": 4, "label": "Test Design", "status": "ok", "duration_ms": 303000 },
        { "phase": 5, "label": "Implementation", "status": "ok", "duration_ms": 720000 },
        { "phase": 6, "label": "Test Report", "status": "ok", "duration_ms": 214000 },
        { "phase": 7, "label": "Archive", "status": "running", "duration_ms": null }
      ],
      "gates": [
        { "phase": 2, "type": "pass", "gate_score": "8/8", "timestamp": "2026-03-14T09:08:16.000Z" },
        { "phase": 3, "type": "pass", "gate_score": "8/8", "timestamp": "2026-03-14T09:09:31.000Z" },
        { "phase": 4, "type": "pass", "gate_score": "8/8", "timestamp": "2026-03-14T09:11:46.000Z" },
        { "phase": 5, "type": "pass", "gate_score": "8/8", "timestamp": "2026-03-14T09:16:51.000Z" },
        {
          "phase": 6,
          "type": "block",
          "gate_score": "6/8",
          "error_message": "zero_skip_check.passed = false",
          "timestamp": "2026-03-14T09:28:53.000Z",
          "decision": { "action": "retry", "elapsed_seconds": 36 }
        },
        { "phase": 6, "type": "pass", "gate_score": "8/8", "timestamp": "2026-03-14T09:29:45.000Z" },
        { "phase": 7, "type": "pass", "gate_score": "8/8", "timestamp": "2026-03-14T09:33:21.000Z" }
      ],
      "test_pyramid": {
        "unit": 13,
        "unit_pct": 52,
        "api": 6,
        "api_pct": 24,
        "e2e": 4,
        "e2e_pct": 16,
        "ui": 2,
        "ui_pct": 8,
        "total": 25
      },
      "change_coverage": {
        "coverage_pct": 92,
        "change_points": 25,
        "tested_points": 23
      },
      "sad_path_ratio": 24,
      "requirement_type": "feature",
      "pass_rate": 96.0,
      "parallel_metrics": {
        "mode": "parallel",
        "groups_count": 3,
        "fallback_reason": null
      },
      "tdd_metrics": {
        "total_cycles": 10,
        "red_violations": 0,
        "green_retries": 2,
        "refactor_reverts": 0
      }
    }
  }
}
```

---

> **End of PRD** — 本文档包含了 spec-autopilot 插件全部 8 个阶段的底层数据结构、3 层门禁系统、6 大核心 UI 组件蓝图、完整色彩/动效设计系统，以及一份包含 48 个事件的完整 Mock 数据。可直接输入 v0 / Stitch / Bolt 等 AI UI 生成工具进行界面生成。
