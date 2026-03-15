> [English](v4-to-v5.md) | 中文

# v4 → v5 迁移指南

> 本文档涵盖 spec-autopilot 从 v4.x 升级到 v5.x 的所有破坏性变更和迁移步骤。

## 1. 配置 Schema 变更

### 1.1 新增必填字段

以下字段在 v5.0+ 变为必填，缺少将导致 `_config_validator.py` 报 `valid: false`：

| 字段 | 类型 | 说明 | 默认值建议 |
|------|------|------|-----------|
| `phases.reporting.coverage_target` | int | 代码覆盖率阈值 | `80` |
| `phases.reporting.zero_skip_required` | bool | 零跳过检查 | `true` |
| `phases.implementation.serial_task.max_retries_per_task` | int | 单 task 最大重试数 | `3` |

### 1.2 新增推荐字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `test_pyramid.hook_floors.*` | int | L2 Hook 门禁地板值（min_unit_pct/max_e2e_pct/min_total_cases/min_change_coverage_pct） |
| `context_management.git_commit_per_phase` | bool | 每阶段自动 git fixup commit |
| `default_mode` | str | 执行模式默认值（full/lite/minimal） |
| `background_agent_timeout_minutes` | int | 后台 Agent 超时（分钟） |

### 1.3 枚举值变更

| 字段 | v4 允许值 | v5 允许值 |
|------|----------|----------|
| `default_mode` | 无此字段 | `full`, `lite`, `minimal` |
| `phases.reporting.format` | 无此字段 | `allure`, `custom` |

### 1.4 迁移操作

```yaml
# 在 autopilot.config.yaml 中追加以下字段（如缺失）：
phases:
  reporting:
    coverage_target: 80
    zero_skip_required: true
  implementation:
    serial_task:
      max_retries_per_task: 3

# 推荐追加：
default_mode: "full"
test_pyramid:
  hook_floors:
    min_unit_pct: 30
    max_e2e_pct: 40
    min_total_cases: 10
    min_change_coverage_pct: 80
```

## 2. Hook 协议变更

### 2.1 统一 Hook 架构（v5.1）

v4 使用 5 个独立 PostToolUse(Task) Hook 脚本（串行执行 ~420ms）。v5.1 合并为单一 Python 验证器：

| v4 (已废弃) | v5.1+ (统一) |
|-------------|-------------|
| `json-envelope-check.sh` | `_post_task_validator.py` Validator 1 |
| `anti-rationalization-check.sh` (Task) | `_post_task_validator.py` Validator 2 |
| `code-constraint-check.sh` (Task) | `_post_task_validator.py` Validator 3 |
| `parallel-merge-guard.sh` | `_post_task_validator.py` Validator 4 |
| `decision-format-check.sh` | `_post_task_validator.py` Validator 5 |

**迁移操作**：更新 `hooks.json`，将上述 5 个独立 hook 替换为 `_post_task_validator.py` 单一入口。

### 2.2 统一 Write/Edit Hook（v5.1）

| v4 | v5.1+ |
|----|-------|
| `banned-patterns-check.sh` + `assertion-quality-check.sh` | `unified-write-edit-check.sh`（合并） |

### 2.3 Hook 协议约定

所有 Hook 遵循统一协议：

```
PostToolUse Hook:
  阻断: stdout → {"decision": "block", "reason": "..."}
  通过: stdout 为空或非 JSON
  退出码: 始终 exit 0（非零表示 hook 自身崩溃）

PreToolUse Hook:
  拒绝: stdout → {"hookSpecificOutput": {"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"..."}}
  允许: stdout 为空
  退出码: 始终 exit 0
```

### 2.4 共享前导脚本

v5.0+ 新增 `_hook_preamble.sh`，所有 PostToolUse hook 统一使用：

```bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_hook_preamble.sh"
# 提供: STDIN_DATA, SCRIPT_DIR, PROJECT_ROOT_QUICK
# 自动跳过: 非 autopilot 会话 (Layer 0 bypass, ~1ms)
```

## 3. Event Bus（v4.2 新增）

### 3.1 事件类型

v5.0+ 引入 Event Bus 机制，事件写入 `logs/events.jsonl`：

| 事件类型 | 脚本 | 触发时机 |
|---------|------|---------|
| `phase_start` / `phase_end` | `emit-phase-event.sh` | Phase 生命周期 |
| `gate_pass` / `gate_block` | `emit-gate-event.sh` | Gate 判定 |
| `task_progress` | `emit-task-progress.sh` | Phase 5 task 完成（v5.2） |
| `agent_dispatch` / `agent_complete` | `emit-agent-event.sh` | Agent 生命周期（v5.3） |
| `tool_use` | `emit-tool-event.sh` | 全量工具调用日志（v5.3） |
| `decision_ack` | WebSocket-only | GUI 决策确认（v5.2） |

### 3.2 事件格式

```json
{
  "type": "phase_start",
  "sequence": 1,
  "timestamp": "2026-03-15T10:00:00.000Z",
  "phase": 1,
  "mode": "full",
  "payload": { ... }
}
```

### 3.3 迁移操作

Event Bus 为新增功能，无需迁移。v4 项目升级后自动可用。如需 GUI 可视化，启动 autopilot-server.ts。

## 4. 其他重要变更

### 4.1 Checkpoint 原子写入（v5.1）

v5.1 所有 checkpoint 写入改为原子模式：先写 `.tmp` → 验证 → `mv` 重命名。崩溃恢复时自动清理 `.tmp` 残留。

### 4.2 TDD 阶段状态文件（v5.1）

TDD 模式新增 `.tdd-stage` 文件（`context/.tdd-stage`），值为 `red`/`green`/`refactor`。L2 Write/Edit Hook 读取此文件确定性拦截。

### 4.3 测试纪律（v5.0.7）

新增 CLAUDE.md 测试纪律铁律：

- 禁止反向适配（测试失败时修改 hook 逻辑让测试通过）
- 禁止弱化断言
- 禁止删除/跳过现有测试

### 4.4 构建纪律（v5.0.7）

新增 `build-dist.sh` 白名单构建：

- 运行时文件通过白名单复制到 `dist/`
- CLAUDE.md DEV-ONLY 段落自动裁剪
- `tests/`、`docs/`、`gui/` 不进入 dist

## 5. 版本兼容性矩阵

| 特性 | v4.0 | v4.2 | v5.0 | v5.1 | v5.2 | v5.3 |
|------|------|------|------|------|------|------|
| 基础编排 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Event Bus | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 统一 Hook | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ |
| 原子 Checkpoint | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ |
| GUI 控制台 | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ |
| Agent 生命周期事件 | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| 子步骤进度恢复 | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
