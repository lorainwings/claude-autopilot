# Part A：Phase 1 Agent 名称解析 BUG 修复设计

## 1. 根因复盘（已确认）

### 现象

`logs/events.jsonl` 中 Phase 1 的 `task_dispatch` 事件出现：

```json
{"event":"task_dispatch","phase":1,"subagent_type":"Explore","description":"分析项目结构..."}
```

而 `.claude/autopilot.config.yaml` 实际配置：

```yaml
phases:
  requirements:
    agent: general-purpose
    research:
      agent: general-purpose
```

### 根因

`plugins/spec-autopilot/skills/autopilot/references/parallel-phase1.md` 第 53/62/71 行模板：

```markdown
Task(subagent_type: config.phases.requirements.agent, run_in_background: true,
  prompt: "分析项目结构...")
```

这段文字在主线程看来是**字面量描述**而非**解析指令**。LLM 执行 Task 时：

1. 不会自动对 `config.phases.requirements.agent` 做 YAML lookup；
2. 缺少 fallback 规则时，LLM 按 description（"分析项目结构"）启发式匹配 Claude 内置 agent，落到 `Explore` 或 `general-purpose`；
3. 内置 agent 不带 owned_files / JSON 信封约束，Phase 1 上下文隔离红线形同虚设。

## 2. 修复方案（A1–A5）

### A1 · 模板硬解析（主修复）

**改哪个文件**：
- `plugins/spec-autopilot/skills/autopilot/references/parallel-phase1.md`
- `plugins/spec-autopilot/skills/autopilot-dispatch/SKILL.md`

**怎么改**：
1. 在 parallel-phase1.md 顶部新增「**预解析协议**」章节，主线程必须在发出 Task 前先执行：
   ```bash
   # 伪代码：主线程执行
   AGENT_REQ=$(yq '.phases.requirements.agent // "general-purpose"' .claude/autopilot.config.yaml)
   AGENT_RESEARCH=$(yq '.phases.requirements.research.agent // "general-purpose"' .claude/autopilot.config.yaml)
   ```
2. 将所有 `subagent_type: config.phases.X` 占位符替换为 `subagent_type: "{{AGENT_REQ}}"` 并在模板上方显式标注「此处必须先替换为字符串字面量再发 Task」。
3. 在 autopilot-dispatch skill 中补充「Agent 解析顺序」：config → registry → `general-purpose` fallback。

**如何验证**：`tests/test_phase1_agent_resolution.sh` 用 mock harness 捕获 Task 调用的 `subagent_type` 字段，断言为已注册字符串。

### A2 · 注册表校验（二道防线）

**改哪个文件**：
- `plugins/spec-autopilot/runtime/scripts/validate-agent-registry.sh`（新增）
- `plugins/spec-autopilot/runtime/hooks/pre-task-validator.sh`（扩展）

**怎么改**：
1. 新增脚本读取 `.claude/autopilot.config.yaml` 与 `.claude/agents/` 目录，汇总合法 agent 名集合，写入 `.claude/autopilot-agent-registry.json`。
2. pre-task-validator 在每次 Task 前比对 `subagent_type` 是否 ∈ registry ∪ {`general-purpose`}，否则返回 `{"permissionDecision":"deny","reason":"unregistered agent: X"}`。

**如何验证**：构造一次故意传 `Explore` 的测试，断言 PreToolUse hook stdout JSON 含 `deny`。

### A3 · dispatch 显式禁令

**改哪个文件**：`plugins/spec-autopilot/skills/autopilot-dispatch/SKILL.md`

**怎么改**：在「禁用 Agent 名单」章节显式列出：

```markdown
### 禁用 subagent_type（硬规则）
- `Explore`、`Research`、`Code`、`Write`：Claude 内置通用类型，禁止在 autopilot 编排中使用
- 未在 `.claude/autopilot-agent-registry.json` 中登记的任意字符串
- 任何以 `config.` 或 `{{` 开头的字面量（说明未完成模板解析）
```

**如何验证**：grep 检查 skill 文本。

### A4 · 回归 testcase

**改哪个文件**：`plugins/spec-autopilot/tests/test_phase1_agent_resolution.sh`（新增）

**覆盖**：
1. 正常路径：config 设 `requirements.agent: requirements-analyst`，Task 捕获 subagent_type == `requirements-analyst`。
2. 缺省 fallback：config 未设时，落到 `general-purpose`。
3. 非法值阻断：注入 `Explore`，PreToolUse hook 拒绝。

### A5 · PostToolUse 阻断（兜底）

**改哪个文件**：`plugins/spec-autopilot/runtime/hooks/post-task-validator.sh`

**怎么改**：新增分支：读取 Task 返回事件中的实际 subagent_type，若不在 registry，则 stdout 输出：

```json
{"decision":"block","reason":"agent_identity_drift: expected registered agent, got <X>"}
```

退出码保持 0（符合 `MEMORY.md` 约定：`exit 0` 表示 hook 自身执行成功）。

## 3. 变更触点总览

| 文件 | 动作 | 所属方案 |
|------|------|---------|
| `skills/autopilot/references/parallel-phase1.md` | 改 | A1 |
| `skills/autopilot-dispatch/SKILL.md` | 改 | A1, A3 |
| `runtime/scripts/validate-agent-registry.sh` | 新增 | A2 |
| `runtime/hooks/pre-task-validator.sh` | 改 | A2 |
| `runtime/hooks/post-task-validator.sh` | 改 | A5 |
| `tests/test_phase1_agent_resolution.sh` | 新增 | A4 |

## 4. 上线顺序

1. A4（先写失败测试，锁定 RED）
2. A2 + A3（非侵入性，先部署防线）
3. A1（主修复，RED → GREEN）
4. A5（兜底）
5. 回归 `bash tests/run_all.sh` + `bash tools/build-dist.sh`。
