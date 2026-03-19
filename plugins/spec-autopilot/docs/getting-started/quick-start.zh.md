> [English](quick-start.md) | 中文

# 5 分钟快速开始

> 从安装到第一次自动交付，只需 3 步。

## 1. 安装插件（30 秒）

```bash
claude plugins install spec-autopilot
```

或从 GitHub 直接安装：
```bash
claude plugins install https://github.com/lorainwings/claude-autopilot
```

## 2. 初始化项目（1 分钟）

在项目根目录运行：

```
/autopilot-init
```

向导会自动检测你的项目结构（语言、框架、测试工具），然后提供 3 个预设模板：

| 预设 | 适合场景 | 特点 |
|------|---------|------|
| **Strict** | 企业级项目 | 全部门禁开启，TDD 模式 |
| **Moderate**（推荐） | 大多数项目 | 平衡质量与效率 |
| **Relaxed** | 快速原型 | 最少约束，快速迭代 |

选择后自动生成 `.claude/autopilot.config.yaml`。

## 3. 开始第一个任务（3 分钟）

```
/autopilot 实现用户登录功能
```

autopilot 会自动：
1. **Phase 1**: 和你讨论需求（回答 3-5 个确认问题）
2. **Phase 2-3**: 生成规范文档
3. **Phase 4**: 设计测试用例
4. **Phase 5**: 编写代码
5. **Phase 6**: 运行测试 + 代码审查
6. **Phase 7**: 汇总结果，等你确认归档

## 执行模式

根据任务大小选择不同模式：

```
/autopilot 实现完整用户系统          # full 模式（默认）— 8 阶段完整流程
/autopilot lite 添加导出按钮         # lite 模式 — 跳过 OpenSpec，适合小功能
/autopilot minimal 修复日期格式 bug  # minimal 模式 — 最精简，适合 bug 修复
```

## GUI 实时大盘 (v5.0.8)

启动 GUI 大盘查看实时执行状态：

```bash
# 启动双模服务器 (HTTP:9527 + WebSocket:8765)
bun run plugins/spec-autopilot/runtime/server/autopilot-server.ts
```

打开浏览器访问 `http://localhost:9527`，可查看：

| 栏位 | 内容 |
|------|------|
| 左栏 — Phase 时间轴 | 各阶段进度 + 状态指示灯（ok/warning/blocked） |
| 中栏 — 事件流 | 实时事件 (phase_start, gate_block, task_progress 等) |
| 右栏 — 门禁决策 | 门禁阻断时的决策浮层 (retry / fix / override) |

> 门禁阻断时，GUI 提供可视化决策按钮，无需切回 CLI 操作。

## 常见问题

**Q: 中途崩溃/断开怎么办？**
重新运行 `/autopilot`，自动从断点恢复（checkpoint 机制）。

**Q: 如何跳过测试设计阶段？**
使用 `lite` 模式：`/autopilot lite <需求>`

**Q: 如何查看详细执行日志？**
按 `Ctrl+O` 切换 verbose 模式，可看到 Hook stderr 输出。

**Q: 配置文件在哪里？**
`.claude/autopilot.config.yaml`，详见 [配置文档](configuration.zh.md)。

**Q: 如何启用 TDD 模式？**
在配置文件中设置：
```yaml
phases:
  implementation:
    tdd_mode: true
```

**Q: Hook 阻断了怎么办？**
阻断消息会告诉你原因和修复建议。常见阻断：
- `test_pyramid floor violation` → 增加单元测试数量
- `zero_skip_check` → 修复跳过的测试
- `Anti-rationalization` → 子 Agent 试图跳过工作，会自动重新派发

**Q: 如何查看实时可视化执行状态？**
启动 GUI 大盘：`bun run plugins/spec-autopilot/runtime/server/autopilot-server.ts`，然后打开 `http://localhost:9527`。所有 Phase 进度、门禁判定、任务进度实时推送到浏览器。

**Q: 如何启用并行执行？**
在配置文件中设置：
```yaml
phases:
  implementation:
    parallel:
      enabled: true
      max_agents: 3   # 建议 2-4
```
并行模式按域（backend/frontend/node）分组执行，适合全栈 Monorepo 项目。

**Q: Event Bus 事件存储在哪里？**
事件以 JSON Lines 格式追加到 `logs/events.jsonl`。可通过 `tail -f logs/events.jsonl | jq .` 实时监听，或通过 WebSocket (`ws://localhost:8765`) 消费。

## 下一步

- [配置调优指南](../operations/config-tuning-guide.zh.md) — 按项目类型优化配置
- [架构总览](../architecture/overview.zh.md) — 理解 8 阶段流水线 + 三层门禁 + 事件总线 + GUI V2
- [故障排查](../operations/troubleshooting.zh.md) — 常见错误与恢复方案
