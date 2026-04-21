# `swap` 模式

用法: `/autopilot-agents swap phase4 test-engineer`

```
Step 1: 解析参数 — phase 编号 + 新 agent 名称
Step 2: 检查 .claude/agents/{agent}.md 是否存在
  存在 → 继续
  不存在 → 检查是否为内置类型（general-purpose/Plan/Explore）
  都不是 → 提示安装对应 Agent
Step 3: 读取 .claude/autopilot.config.yaml
Step 4: 更新对应 phase 的 agent 字段
Step 5: 工具权限适配（必须）
  Bash('python3 ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/adapt-agent-tools.py --project-root "$(pwd)"')
  → 对新交换进来的 agent 执行 disallowedTools 冲突检测 + 自动 fork
Step 6: 输出新映射
```

Phase → config key 映射:

```
phase1                → phases.requirements.agent (BA)
phase1-autoscan       → phases.requirements.auto_scan.agent
phase1-research       → phases.requirements.research.agent
phase1-websearch      → phases.requirements.research.web_search.agent  # [DEPRECATED] 仅热交换旧 config 时使用
phase1-synthesizer    → phases.requirements.synthesizer.agent  # 专职汇总者
phase2 → phases.openspec.agent
phase3 → phases.openspec.agent (共享 Phase 2)
phase4 → phases.testing.agent
phase5 → phases.implementation.parallel.default_agent
phase5-review → phases.implementation.review_agent
phase5.5 / redteam    → phases.redteam.agent
phase6 → phases.reporting.agent
phase6-review → phases.code_review.agent
phase7 → phases.archive.agent
```

## 域 Agent 热交换

用法: `/autopilot-agents swap backend/ backend-developer`

```
判断规则: 若第一参数包含 "/" → 视为域 swap；否则视为 Phase swap

Step 1: 解析路径前缀（确保以 / 结尾）+ 新 agent 名称
Step 2: 检查 .claude/agents/{agent}.md 是否存在
  存在 → 继续
  不存在 → 检查是否为内置类型（general-purpose/Plan/Explore）
  都不是 → 提示安装: "Agent '{agent}' 未安装。运行 /autopilot-agents install 或手动下载到 .claude/agents/"
Step 3: 读取 .claude/autopilot.config.yaml
Step 4: 更新 phases.implementation.parallel.domain_agents."{prefix}".agent
  IF 该前缀在 domain_agents 中不存在 → 新增条目
Step 5: 输出新域映射

示例:
  /autopilot-agents swap backend/ backend-developer
  → phases.implementation.parallel.domain_agents."backend/".agent: "backend-developer"

  /autopilot-agents swap services/auth/ java-architect
  → phases.implementation.parallel.domain_agents."services/auth/".agent: "java-architect"
```
