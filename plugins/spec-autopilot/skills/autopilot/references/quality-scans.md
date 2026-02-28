# Phase 6→7 过渡: 并行质量扫描协议

> 本文件由 autopilot SKILL.md 引用，Phase 6 完成后进入 Phase 7 前按需读取。

Phase 6 完成后、Phase 7 之前，主线程**同时**派发多个后台质量扫描 Agent。这些 Agent 与 Phase 7 的汇总准备并行执行。

## 派发流程

读取 `config.async_quality_scans`，对每个扫描项：

1. **检查工具是否已安装**（通过 `command -v` 或 `npx --version` 验证）
2. **未安装 → 自动安装**（使用项目包管理器：pnpm add -D / pip install / Gradle plugin）
3. **安装失败 → 联网搜索安装方式，重试一次**
4. **仍失败 → 标记该扫描为 "install_failed"，继续其他扫描**

使用 `Task(run_in_background: true)` 并行派发所有扫描：

```
scan_agents = []
for scan in config.async_quality_scans:
  agent = Task(
    subagent_type: "general-purpose",
    run_in_background: true,
    prompt: "<!-- autopilot-quality-scan:{scan.name} -->
      1. 检查工具: {scan.check_command}
      2. 未安装则执行: {scan.install_command}
      3. 运行扫描: {scan.command}
      4. 阈值: {scan.threshold}
      返回 JSON: {status, summary, score, details, installed}"
  )
  scan_agents.append(agent)
```

## 结果收集

Phase 7 开始时，逐一检查后台 Agent 状态，并强制执行硬超时：

**硬超时机制**：
- 超时阈值：`config.async_quality_scans.timeout_minutes`（默认 10 分钟）
- 从 Phase 6 完成时间戳开始计算
- 超时后**自动**将该扫描标记为 `"timeout"` 状态，**不询问用户**是否继续等待
- 继续处理其余扫描和 Phase 7 后续步骤

**收集逻辑**：
- **已完成** → 读取结果，纳入质量汇总表
- **仍在运行 + 未超时** → 等待直到完成或超时
- **仍在运行 + 已超时** → 自动标记为 `"timeout"`，纳入汇总表，继续执行

## 质量汇总表（Phase 7 展示）

```
| 扫描项 | 状态 | 得分 | 阈值 | 结果 |
|--------|------|------|------|------|
| 核心测试 | ok | 95% | 90% | PASS |
| 契约测试 | ok | 3/3 | all | PASS |
| 性能审计 | warn | 76 | 80 | WARN |
| 视觉回归 | ok | 0 diff | 0 | PASS |
| 变异测试 | timeout | — | 60% | TIMEOUT |
```

> **注意**: 质量扫描的 prompt 不含 `<!-- autopilot-phase:N -->` 标记，因此不受 Hook 门禁校验。这些是信息性扫描，不是阶段门禁。扫描失败不阻断归档，但会在汇总表中标红警告。
