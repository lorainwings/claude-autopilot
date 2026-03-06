# Phase 6→7 过渡: 并行质量扫描协议

> 本文件由 autopilot SKILL.md 引用，Phase 6 完成后进入 Phase 7 前按需读取。v3.1.0 compatible.

Phase 6 完成后、Phase 7 之前，主线程**同时**派发多个后台质量扫描 Agent。这些 Agent 与 Phase 7 的汇总准备并行执行。

## 派发流程

读取 `config.async_quality_scans`，对每个扫描项：

1. **检查工具是否已安装**（通过 `command -v` 或 `npx --version` 验证）
2. **未安装 → 自动安装**（使用项目包管理器：pnpm add -D / pip install / Gradle plugin）
3. **安装失败 → 联网搜索安装方式，重试一次**
4. **仍失败 → 标记该扫描为 "install_failed"，继续其他扫描**

### 与并行实现的协调 (v3.1)

质量扫描在 Phase 5 完成后派发，与并行执行模式无关：

- 如果 Phase 5 使用并行执行：`file-locks.json` 已清理，worktrees 已合并 → 扫描从干净状态开始
- 如果 Phase 5 降级为串行：扫描正常运行，无锁注册表影响
- 扫描不包含 `autopilot-phase` 标记 → Hook bypass 生效（纯信息收集扫描）

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

### 与并行实现的协调 (v3.1)

质量扫描在 Phase 5 完成后派发，与并行执行模式无关：

- 如果 Phase 5 使用并行执行：file-locks.json 已清理，worktrees 已合并 → 扫描从干净状态开始
- 如果 Phase 5 降级为串行：扫描正常运行，无锁注册表影响
- 扫描不包含 autopilot-phase 标记 → Hook bypass 生效（纯信息收集扫描）

---

## 安全审计扫描（v2.4.0 新增）

### 工具检测

运行 `bash <plugin_scripts>/check-security-tools-install.sh "$(pwd)"`，获取已安装的安全工具清单。

### 扫描类型

| 扫描 | 工具 | 检测内容 | 阈值 |
|------|------|---------|------|
| dependency_audit | pnpm audit / npm audit | 依赖漏洞（high/critical） | 0 high/critical |
| secret_detection | gitleaks | 硬编码凭证/API Key/密钥 | 0 findings |
| static_analysis | semgrep | OWASP Top 10 漏洞模式 | 0 critical |
| container_scan | trivy | 容器/文件系统漏洞 | 0 critical |

### 安全扫描 Task Prompt 模板

```
<!-- autopilot-quality-scan:security -->
你是安全审计 Agent。执行以下安全扫描：

1. **工具检测**:
   运行: bash <plugin_scripts>/check-security-tools-install.sh "$(pwd)"
   读取 recommended_scans 列表

2. **按检测到的工具逐个执行**:
   - npm_audit: `pnpm audit --audit-level=high` 或 `npm audit --audit-level=high`
   - gitleaks: `gitleaks detect --source . --no-git --report-format json`
   - semgrep: `semgrep scan --config auto --severity ERROR --json`
   - trivy: `trivy fs . --severity HIGH,CRITICAL --format json`

3. **工具未安装时**:
   将该工具标记为 skipped，不阻断其他扫描。
   在 summary 中说明哪些工具因未安装被跳过。

4. **返回 JSON**:
   {
     "status": "ok | warning",
     "summary": "安全扫描汇总: X critical, Y high, Z medium",
     "findings": [
       {"tool": "gitleaks", "severity": "critical", "file": "...", "line": 42, "detail": "..."},
       {"tool": "npm_audit", "severity": "high", "package": "lodash", "cve": "CVE-...", "fix": "..."}
     ],
     "tools_executed": ["npm_audit", "gitleaks"],
     "tools_skipped": ["semgrep", "trivy"],
     "audit_score": 92
   }
```

### 安全扫描结果在质量汇总表中的展示

```
| 安全审计 | ok | 0 critical, 2 medium | 0 critical | PASS |
```

### 阻断配置

- 默认：安全扫描失败不阻断归档（仅在汇总表中标红警告）
- 可选：设置 `async_quality_scans.security_audit.block_on_critical: true` → critical 发现时阻断归档
