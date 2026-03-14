# 护栏约束清单

> 本文件由 autopilot SKILL.md 引用，包含所有护栏约束规则。仅在阶段切换或需要查阅时加载。

## 核心约束

| 约束 | 规则 |
|------|------|
| 主线程编排 | 所有 Task 派发在主线程执行，禁止嵌套 Task |
| 配置驱动 | 所有项目路径从 autopilot.config.yaml 读取，禁止硬编码 |
| 阶段门禁 | Hook 确定性 + autopilot-gate 检查清单 |
| 阶段跳过阻断 | Hook + TaskCreate blockedBy 确定性阻断 |
| 任务系统 | Phase 0 创建阶段任务（full: Phase 1-7, lite: Phase 1/5/6/7, minimal: Phase 1/5/7）+ blockedBy 链 |
| 崩溃恢复 | autopilot-recovery Skill 扫描 checkpoint |
| 结构化标记 | 子 Agent prompt 开头包含 `<!-- autopilot-phase:N -->` |
| 结构化返回 | 子 Agent 必须返回 JSON 信封 |
| 测试不可变 | 禁止修改测试以通过；只能修改实现代码 |
| 零跳过 | Phase 6 零跳过门禁 |
| 任务拆分 | 每次 ≤3 个文件，≤800 行代码 |
| 归档确认 | Phase 7 必须经用户确认后才能归档 |

## 上下文与 Agent 约束

| 约束 | 规则 |
|------|------|
| 上下文保护 | 每 Phase 完成后通过后台 Checkpoint Agent 写入 checkpoint + git fixup commit（v3.4.3）；子 Agent 回传精简摘要，不传原始输出；Phase 7 归档时 autosquash 合并 |
| PID 回收防护 | 锁文件同时检查 PID 存活 + session_id 匹配，防止 PID 被系统回收导致误判 |
| 质量扫描超时 | 硬超时（默认 10 分钟），超时自动标记 timeout，不询问用户 |
| **后台 Agent 通用超时** | 所有 `run_in_background: true` 的 Agent 硬超时 30 分钟（`config.background_agent_timeout_minutes`），超时标记 `"timeout"` 并展示警告 |
| **全面后台化** | Phase 2/3/4（非并行）/6 路径 A 全部使用 `run_in_background: true`；Checkpoint + Git Fixup 合并为后台 Agent。仅 Phase 1 主线程交互和 Phase 5 串行模式在前台执行 |
| **后台 Agent 轮询禁令** | **禁止使用 TaskOutput 检查后台 Agent 进度**。TaskOutput 仅适用于 Bash 后台命令。后台 Agent 完成时 Claude Code 自动通知 |

## 测试与质量约束

| 约束 | 规则 |
|------|------|
| 代码约束 | Phase 4/5/6 PostToolUse Hook 自动检测项目规则违反（禁止文件/模式/目录范围） |
| 知识累积 | Phase 7 自动提取知识到 openspec/.autopilot-knowledge.json，Phase 1 自动注入 |
| 结构化决策 | 所有决策点以结构化卡片呈现（选项/优劣/推荐），所有复杂度级别均展示决策卡片 |
| 执行模式 | 支持 full/lite/minimal 三种模式；模式仅控制跳过哪些阶段，Phase 1 和 Phase 5 在所有模式下执行质量完全一致 |
| 并行编排 | Phase 1/4/5/6 支持阶段内并行执行；Phase 6+6.5+质量扫描三路并行；Phase 7 知识提取后台化 |
| 测试追溯 | Phase 4 测试用例必须追溯到 Phase 1 需求点（traceability matrix），覆盖率 ≥ `traceability_floor`（默认 80%，L2 blocking） |
| Allure 报告 | Phase 6 优先使用 Allure 生成统一测试报告，降级为自定义格式 |
| 需求调研并行 | Phase 1 Auto-Scan + 技术调研 + 联网搜索三者并行执行 |
| 代码约束增强 | Phase 4/5/6 注入 required_patterns + style_guide，强制合规 |

## 错误处理

| 场景 | 处理方式 |
|------|----------|
| 配置文件缺失 | 调用 autopilot-init 自动生成 |
| 工具未安装 | 主动安装，失败则联网搜索 |
| Phase 5 子 Agent 异常退出 | 保存进度到 phase-results checkpoint，从上次完成的 task 恢复 |
| 测试全部失败 | 分析根因，不盲目修改 |
| 子 Agent 返回异常 | JSON 解析失败 → 标记 failed |
| 阶段状态文件缺失 | 视为未完成，重新执行 |
| **上下文压缩** | PreCompact Hook 自动保存状态 → SessionStart(compact) 自动注入恢复 |

## 上下文压缩恢复协议

### 自动机制（Hook 驱动）

1. **PreCompact Hook**：压缩前自动将编排状态写入 `context/autopilot-state.md`
2. **SessionStart(compact) Hook**：压缩后自动注入状态回 Claude 上下文

### 主线程恢复行为

收到 `=== AUTOPILOT STATE RESTORED ===` 标记后：
1. 读取 `autopilot-state.md` 获取进度（last completed phase、next phase、execution mode、anchor SHA）
2. 重新加载 `autopilot.config.yaml` 配置
3. 读取 `context/phase-results/` 确认 checkpoint 一致性
4. 从下一个未完成阶段继续执行，调用 `autopilot-gate` 验证后 dispatch
5. 如果 next_phase == 5 且 Phase 5 状态为 in_progress，扫描 `phase5-tasks/` 目录确定 task 级恢复点

> **禁止**：恢复后重复执行已标记 `ok`/`warning` 的阶段。
