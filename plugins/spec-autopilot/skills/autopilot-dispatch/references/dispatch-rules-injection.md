# Dispatch Project Rules 自动注入协议

> 本文件从 `autopilot-dispatch/SKILL.md` 提取，供 dispatch 构造子 Agent 时按需读取。

### 优先级 2.5: Project Rules Auto-Scan（全阶段注入）

dispatch 任何阶段的子 Agent 时，自动运行 `rules-scanner.sh` 扫描项目 `.claude/rules/` 目录和 `CLAUDE.md`，提取所有约束并注入到子 Agent prompt 中。

**触发条件**：所有通过 Task 派发的阶段（Phase 2-6）

**缓存策略**：Phase 0 首次运行 rules-scanner.sh 后缓存结果，后续阶段复用缓存（同一 autopilot 会话内项目规则不变）。

**阶段差异化注入**：

| 阶段 | 注入内容 |
|------|---------|
| Phase 2-3 | 紧凑摘要（仅 critical_rules，≤5 条） |
| Phase 4 | 完整规则（测试需验证代码符合约束） |
| Phase 5 | 完整规则 + 实时 Hook 强制执行 |
| Phase 6 | 紧凑摘要（报告中引用约束合规状态） |

**执行流程**：

1. 主线程在构造子 Agent prompt 前执行（Phase 0 缓存，后续复用）：

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/rules-scanner.sh "$(pwd)"
   ```

2. 解析返回的 JSON，检查 `rules_found === true`
3. 如果有约束，将 `constraints` 数组格式化为 prompt 段落注入

**注入模板**：

```markdown
{if rules_scan.rules_found === true}
## 项目规则约束（自动扫描）

以下约束从项目 `.claude/rules/` 和 `CLAUDE.md` 自动提取，**必须严格遵守**：

### 禁止项
{for each c in constraints where c.type === "forbidden"}
- `{c.pattern}` → 使用 `{c.replacement}`（来源: {c.source}）
{end for}

### 必须使用
{for each c in constraints where c.type === "required"}
- `{c.pattern}`（来源: {c.source}）
{end for}

### 命名约定
{for each c in constraints where c.type === "naming"}
- {c.pattern}（来源: {c.source}）
{end for}

> 违反以上约束将被 PostToolUse Hook 拦截并 block。

{if config.code_constraints.semantic_rules 非空}
### 语义规则（项目特定，必须遵守）
{for each rule in config.code_constraints.semantic_rules where rule.scope matches current_phase_domain}
- **[{rule.severity}]** {rule.rule}（适用范围: `{rule.scope}`）
{end for}

> required/naming 类规则已通过 `_constraint_loader.py:load_scanner_constraints()` 合并进 L2 Hook 检测链。
> `semantic_rules` 中若有路径可限定的规则，建议转为 `code_constraints.required_patterns` 以获得 L2 确定性检测。
> 纯语义规则仍依赖 AI 遵守 + Phase 6.5 审查。
{end if}
{end if}
```

**注入位置**：在 Prompt 模板中，插入在 `## Phase 1 项目分析` 之前、`### Playwright 登录流程` 之后。
