# `list` 模式

```
读取 .claude/autopilot.config.yaml 各 phase 的 agent 字段
检查 .claude/agents/ 下已安装的 Agent
展示完整表格:

Phase-Agent 映射:
  Phase → Agent → 安装状态 → Model → 工具限制

域级 Agent 映射 (Phase 5 并行):
  域路径前缀 → Agent → 安装状态

  IF config.phases.implementation.parallel.enabled == false:
    附加提示: "⚠ parallel 模式未启用，域级 Agent 在启用 parallel.enabled: true 后生效"
  IF 所有 domain_agents.*.agent 均为 general-purpose:
    附加提示: "💡 运行 /autopilot-agents install 安装域级专业 Agent"
```
