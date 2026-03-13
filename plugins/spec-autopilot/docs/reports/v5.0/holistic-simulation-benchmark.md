# 全链路整体性真实业务仿真测试报告

**审计日期**: 2026-03-13
**插件版本**: v5.0.1
**审计方**: AI 首席工程审计师 (Claude Opus 4.6)
**报告类型**: 仿真场景设计 + 人机协同测试协议（实际数据待填充）

---

## 1. 执行摘要

本报告为 spec-autopilot 的两个高难度仿真场景设计完整的测试协议。场景 A 考核并发与容灾能力，场景 B 考核底层 IO 与 TDD 能力。当用户在 GUI 监控下完整运行这两个场景并提供数据后，本报告的评分矩阵将被填充为实际分数。

| 场景 | 需求复杂度 | 考核重点 | 预期模式 |
|------|-----------|---------|---------|
| A: ConfigCenter 分布式客户端 | Large | 并发+容灾+并行实施 | full + parallel.enabled=true |
| B: aliyun-oss-uploader | Medium-Large | 底层 IO + TDD + 架构扩展 | full + tdd_mode=true |

---

## 2. 场景 A: ConfigCenter 分布式客户端拉取模块

### 2.1 需求文档 (RAW_REQUIREMENT)

```
开发企业级 ConfigCenter 的分布式客户端拉取模块。要求：

1. 核心功能：
   - 多节点同时拉取配置（支持 10-100 客户端并发）
   - 配置变更实时通知（基于 Long Polling 或 WebSocket）
   - 本地缓存 + 降级策略（服务端不可用时使用本地快照）
   - 配置版本管理与灰度发布支持

2. 容灾要求：
   - 服务端宕机：客户端自动切换到本地缓存，不影响业务
   - 网络分区：指数退避重连 + 本地快照服务
   - 配置推送失败：至少一次交付保证 + 幂等性
   - 客户端启动：优先本地缓存，后台异步拉取最新配置

3. 技术约束：
   - TypeScript + Node.js 20+
   - 支持 YAML/JSON/TOML 多格式配置
   - 提供 SDK 级 API（支持 Namespace 隔离）
   - 单元测试覆盖率 ≥ 80%

4. 架构要求：
   - 客户端与 ConfigCenter 服务端解耦（面向接口编程）
   - 支持多种传输层（HTTP Long Polling / WebSocket / gRPC）
   - 可观测性：metrics 暴露 + 结构化日志
```

### 2.2 预期流程追踪

| Phase | 预期行为 | 关键检查点 |
|-------|---------|-----------|
| 0 | 创建锁文件, mode=full, parallel.enabled=true | 锁文件格式正确 |
| 1 | **Large 复杂度**, 三路并行调研, 苏格拉底模式激活 | 至少 5 个决策点, 3+ 轮 QA |
| 1 决策点 | 传输层选型(Long Polling vs WebSocket vs gRPC), 缓存策略(LRU vs 时间戳), 灰度策略, 配置格式优先级 | 决策卡片完整性 |
| 2 | OpenSpec 创建，design.md 覆盖全部功能 | 功能覆盖率 100% |
| 3 | tasks.md 拆分 5-8 个 task，按模块分区 | 每 task ≤ 3 文件 |
| 4 | 并行测试设计: unit(核心逻辑) + api(SDK接口) + e2e(端到端拉取) | sad_path ≥ 20%, 金字塔 unit ≥ 50% |
| 5 | **并行模式**: 按域分区(transport/cache/config-parser/sdk) | 4 个 worktree 并行, 合并成功 |
| 6 | 测试执行 + Allure 报告 | pass_rate ≥ 90%, zero_skip |
| 7 | 汇总 + 知识提取 | 归档成功 |

### 2.3 预期 GateBlock 触发场景

| 场景 | 触发条件 | 预期 Gate 行为 |
|------|---------|--------------|
| Phase 4 sad_path 不足 | sad_path_counts.unit < 20% | L2 Hook 阻断, 要求补充异常路径测试 |
| Phase 5 合并冲突 | 两个 worktree 同时修改 shared interface | 合并守卫检测, 尝试自动解决或降级 |
| Phase 5→6 zero_skip 失败 | 测试中有 skip 标记 | L2 阻断, 要求移除 skip |

### 2.4 评分矩阵

| 维度 | 权重 | 预期分 | 实际分 |
|------|------|--------|--------|
| Phase 1 需求理解深度 | 15% | 80-90 | _待填充_ |
| Phase 4 测试设计质量 | 15% | 75-85 | _待填充_ |
| Phase 5 并行实施效率 | 25% | 70-85 | _待填充_ |
| Phase 5 代码质量 | 20% | 75-85 | _待填充_ |
| Phase 6 测试通过率 | 15% | 80-95 | _待填充_ |
| GUI 监控流畅度 | 10% | 50-65 | _待填充_ |
| **综合** | **100%** | **73-85** | _待填充_ |

---

## 3. 场景 B: aliyun-oss-uploader 高性能命令行工具

### 3.1 需求文档 (RAW_REQUIREMENT)

```
开发 aliyun-oss-uploader 高性能命令行工具。要求：

1. 核心功能：
   - 分片上传：大文件自动分片（默认 5MB/片，可配置）
   - 断点续传：记录已上传分片，中断后从断点恢复
   - 并发控制：可配置并发上传数（默认 5，最大 20）
   - 进度展示：实时显示上传进度、速度、预计剩余时间
   - 批量上传：支持目录递归上传 + glob 模式匹配

2. 架构要求：
   - 插件化存储后端：OSS 为默认后端，预留 S3/GCS 接口
   - 配置文件：支持 ~/.ossrc YAML 配置 + 环境变量 + CLI 参数（优先级递增）
   - 日志系统：结构化 JSON 日志 + 人类可读终端输出

3. 性能要求：
   - 100MB 文件上传 ≤ 30s（100Mbps 网络）
   - 内存占用 ≤ 200MB（大文件流式处理，不全量加载）
   - CPU 空闲时让出（不阻塞其他进程）

4. 技术约束：
   - TypeScript + Node.js 20+ + Commander.js
   - 使用 ali-oss SDK
   - TDD 模式开发（先写测试后实现）
   - 单元测试覆盖率 ≥ 85%
```

### 3.2 预期流程追踪

| Phase | 预期行为 | 关键检查点 |
|-------|---------|-----------|
| 0 | mode=full, tdd_mode=true | TDD 模式正确检测 |
| 1 | **Medium-Large 复杂度**, Web 搜索: "aliyun oss sdk multipart upload" | 调研 ali-oss SDK API |
| 1 决策点 | 分片大小策略(固定 vs 自适应), 存储后端接口设计, 配置优先级实现, 日志库选型 | 至少 4 个决策点 |
| 2 | OpenSpec 含 design.md + tasks.md | 插件化架构设计 |
| 3 | tasks.md 拆分 6-10 个 task | 含 CLI 框架/OSS SDK/分片引擎/断点续传/进度条/测试 |
| 4 | **TDD 模式跳过** (Phase 4 skipped: TDD override) | checkpoint: phase-4-tdd-override.json |
| 5 | **TDD 模式**: 每 task RED→GREEN→REFACTOR | L2 Bash 验证 RED fail/GREEN pass |
| 5 TDD 验证 | RED: 测试必须失败 (exit_code ≠ 0) | 主线程 Bash 确定性验证 |
| 5 TDD 验证 | GREEN: 测试必须通过 (exit_code = 0) | 主线程 Bash 确定性验证 |
| 6 | 测试执行 + 覆盖率报告 | coverage ≥ 85%, zero_skip |
| 7 | 汇总 + TDD 指标展示 | tdd_metrics.red_violations = 0 |

### 3.3 预期 GateBlock 触发场景

| 场景 | 触发条件 | 预期 Gate 行为 |
|------|---------|--------------|
| TDD RED 通过（不应通过） | exit_code = 0 在 RED 阶段 | 主线程 Bash 检测, 删除测试重写 |
| TDD GREEN 失败 | exit_code ≠ 0 在 GREEN 阶段 | 修复实现代码，禁止修改测试 |
| Phase 5 代码含 TODO | 实现中遗留 `TODO:` 占位符 | L2 banned-patterns-check.sh 阻断 |
| Phase 5→6 zero_skip | 测试中有 .skip() 调用 | L2 阻断 |

### 3.4 评分矩阵

| 维度 | 权重 | 预期分 | 实际分 |
|------|------|--------|--------|
| Phase 1 技术调研深度 | 15% | 80-90 | _待填充_ |
| Phase 5 TDD 纪律遵守 | 25% | 70-85 | _待填充_ |
| Phase 5 代码架构质量 | 20% | 75-85 | _待填充_ |
| Phase 5 插件化扩展性 | 10% | 70-80 | _待填充_ |
| Phase 6 测试覆盖率 | 20% | 80-90 | _待填充_ |
| GUI 监控流畅度 | 10% | 50-65 | _待填充_ |
| **综合** | **100%** | **74-84** | _待填充_ |

---

## 4. 人机协同测试协议

### 4.1 驾驶员（人类）操作手册

#### 准备工作

```bash
# 1. 确保插件已安装
cd /Users/lorain/Coding/Huihao/claude-autopilot

# 2. 创建测试项目目录
mkdir -p /tmp/autopilot-benchmark-a  # 场景 A
mkdir -p /tmp/autopilot-benchmark-b  # 场景 B

# 3. 初始化 git 仓库
cd /tmp/autopilot-benchmark-a && git init && npm init -y
cd /tmp/autopilot-benchmark-b && git init && npm init -y

# 4. 启动 GUI 大盘
cd /Users/lorain/Coding/Huihao/claude-autopilot/plugins/spec-autopilot
bash scripts/start-gui-server.sh &

# 5. 打开浏览器访问 GUI
open http://localhost:5173  # 或 Vite 指定的端口
```

#### 场景 A 执行

```bash
# 1. 在测试项目中启动 Claude Code
cd /tmp/autopilot-benchmark-a
claude

# 2. 创建配置文件 .claude/autopilot.config.yaml
# 确保 parallel.enabled: true

# 3. 触发 autopilot
# 在 Claude Code 中输入:
# /spec-autopilot:autopilot full [粘贴场景 A 的 RAW_REQUIREMENT]

# 4. 在 Phase 1 中配合决策（选择推荐方案即可）
# 5. 全程保持 GUI 打开观测
```

#### 需要截图的关键时刻

| 时刻 | 截图内容 | 用途 |
|------|---------|------|
| Phase 1 开始 | PhaseTimeline 显示 Phase 1 running | 验证事件同步 |
| Phase 1 决策 | 终端中的决策卡片渲染 | 验证决策质量 |
| Phase 4 门禁 | GateBlockCard（如果触发） | 验证反控能力 |
| Phase 5 并行 | ParallelKanban 显示多任务 | 验证看板同步 |
| Phase 5→6 门禁 | Gate 通过事件 | 验证门禁精度 |
| Phase 7 汇总 | 最终汇总表 | 验证完整性 |

#### 需要提供的数据

1. `logs/events.jsonl` — 完整事件流
2. `openspec/changes/<name>/context/phase-results/` — 全部 checkpoint JSON
3. 终端完整输出日志（复制粘贴到 txt 文件）
4. 上述 6 个截图
5. 总运行时间（从启动到 Phase 7 完成）

### 4.2 AI 审计员分析模板

收到用户数据后，按以下步骤分析:

#### Step 1: 事件流分析
```bash
# 提取耗时分布
cat events.jsonl | jq 'select(.type == "phase_end") | {phase, duration: .payload.duration_ms}'

# 提取 Gate 事件
cat events.jsonl | jq 'select(.type | startswith("gate_"))'

# 检查事件序列完整性
cat events.jsonl | jq '.sequence' | sort -n | uniq -c
```

#### Step 2: Checkpoint 验证
- 逐个读取 phase-1 到 phase-7 的 checkpoint JSON
- 验证 status 是否全部为 ok/warning
- 验证 _metrics 中的 duration 数据
- 验证 Phase 5 的 tdd_metrics（场景 B）或 parallel_metrics（场景 A）

#### Step 3: GUI 截图分析
- PhaseTimeline 的状态是否与 events.jsonl 一致
- ParallelKanban 是否正确显示了并行任务
- GateBlockCard 的 Override/Retry 是否可操作

#### Step 4: 填充评分矩阵
- 基于实际数据替换"_待填充_"为实际分数
- 计算加权综合分

---

## 5. 综合评估框架

### 5.1 六维度协同能力矩阵

两个场景共同考核的 6 个维度:

| 维度 | 场景 A 权重 | 场景 B 权重 | 考核内容 |
|------|-----------|-----------|---------|
| 代码质量 | 25% | 25% | 架构清晰度、命名规范、无 TODO |
| 测试质量 | 15% | 25% | 覆盖率、sad-path 比例、TDD 纪律 |
| 需求理解 | 15% | 15% | 决策点完整性、隐藏约束挖掘 |
| 并行/TDD 效率 | 25% | 20% | 并行加速比(A) / TDD 循环效率(B) |
| GUI 监控 | 10% | 5% | 事件同步、看板渲染、终端保真 |
| 门禁精度 | 10% | 10% | Gate 正确阻断/放行率 |

### 5.2 最终评分方法论

```
场景 A 综合 = Σ(维度评分 × 场景A权重)
场景 B 综合 = Σ(维度评分 × 场景B权重)
全链路综合 = 场景A × 50% + 场景B × 50%
```

### 5.3 评分阈值

| 等级 | 分数范围 | 含义 |
|------|---------|------|
| 优秀 | 85-100 | 全维度协同完美，可投入生产 |
| 良好 | 70-84 | 核心能力稳定，边缘场景有待完善 |
| 及格 | 55-69 | 基本可用，但关键路径存在缺陷 |
| 不及格 | < 55 | 存在阻断性缺陷，需修复后重测 |

---

## 6. 当前状态

**本报告为仿真设计文档。** 实际评分需要用户在 GUI 监控下完整运行两个场景后提供数据。

待用户提供:
- [ ] 场景 A 的 events.jsonl + checkpoint JSONs + 终端日志 + GUI 截图
- [ ] 场景 B 的 events.jsonl + checkpoint JSONs + 终端日志 + GUI 截图

收到数据后，本报告的评分矩阵将被填充，并生成最终的全链路综合评分。

---

*报告结束。*
