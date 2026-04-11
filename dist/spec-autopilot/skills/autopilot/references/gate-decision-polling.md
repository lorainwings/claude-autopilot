# Gate 双向反控 — 决策轮询协议

> 本文件从 `autopilot-gate/SKILL.md` 提取，供 gate 阻断时按需读取。

当门禁阻断时，在输出 `[GATE] BLOCKED` 日志 **之后**，必须启动 GUI 决策轮询循环，使 GUI 用户可通过 `decision.json` 发送 Override/Retry/Fix 指令。

**v6.0 自动推进语义**: 门禁通过时，默认自动推进到下一阶段，不弹出用户确认。用户确认点（`config.gates.user_confirmation.after_phase_{N}`）仅在配置为 `true` 时才中断——所有预设默认为 `false`，确保 requirement packet 确认后全链路自动推进。

**流程：**

1. 发射 `gate_block` 事件（已有逻辑）
2. 调用决策轮询脚本：

   ```bash
   DECISION=$(bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/poll-gate-decision.sh "${change_dir}/" "${PHASE}" "${MODE}" '{"blocked_step":M,"error_message":"..."}')
   POLL_EXIT=$?
   ```

3. 根据轮询结果分支处理：

| `POLL_EXIT` | `action` | 处理 |
|-------------|----------|------|
| 0 | `override` | 记录日志 `[GATE] Override accepted: {reason}` → 视为通过，继续下一阶段 |
| 0 | `retry` | 记录日志 `[GATE] Retry requested: {reason}` → 重新执行完整 8 步检查清单 |
| 0 | `fix` | 记录日志 `[GATE] Fix requested` → 将 `fix_instructions` 展示给用户，等待修复后重新执行 8 步检查清单 |
| 0 | `auto_continue` | 记录日志 `[GATE] Auto-continue` → 自动推进到下一阶段 |
| 1 | `timeout` | 轮询超时（默认 300 秒），回退到原有行为：向用户展示阻断信息，通过 AskUserQuestion 请求决策 |

**v8.1 GUI 不可达异步拉起**: 轮询前先检查 GUI 可达性，并校验 `/api/info.projectRoot` 是否属于当前项目。如果 GUI 不可达，或端口上是别的项目实例，**必须先异步启动 GUI 可视化大盘前端服务**（fire-and-forget，不等待 health ready），然后**立即返回 `auto_continue`（exit 0）**，并在返回 JSON 中附带 `dashboard_url` / `health_url` / `ws_url`。主流程继续执行，GUI 大盘在后台自行完成启动。

**返回示例**：

```json
{
  "action": "auto_continue",
  "phase": 3,
  "elapsed_seconds": 0,
  "reason": "gui_dashboard_bootstrap",
  "gui_status": "starting",
  "dashboard_url": "http://localhost:9527",
  "health_url": "http://localhost:9527/api/health",
  "ws_url": "ws://localhost:9528"
}
```

**decision.json 格式**（由 GUI 写入 `openspec/changes/<name>/context/decision.json`）：

```json
{
  "action": "override | retry | fix",
  "phase": 4,
  "timestamp": "ISO-8601",
  "reason": "用户/GUI 提供的说明",
  "fix_instructions": "仅 fix 动作时填写 — 具体修复指导"
}
```

**安全约束**：

- `override` 不可在 Phase 4→5 和 Phase 5→6 特殊门禁中使用（这些门禁的失败条件涉及测试质量底线，不允许绕过）
- 决策文件在读取后立即删除，防止重复消费
- 轮询超时可通过 `config.gui.decision_poll_timeout` 配置（单位：秒，默认 300）
