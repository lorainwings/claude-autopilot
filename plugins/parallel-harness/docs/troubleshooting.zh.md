# parallel-harness 故障排查

> 版本: v1.0.0 (GA) | 最后更新: 2026-03-20

## 常见错误和解决方案

### 1. TaskContract 缺少必要字段

**错误信息**：
```
Error: TaskContract 缺少 task_id
Error: TaskContract 缺少 goal
Error: TaskContract 缺少 allowed_paths
```

**原因**：Worker 接收的 `TaskContract` 不完整。每个 contract 必须包含 `task_id`、`goal`、`allowed_paths`。

**解决方案**：
1. 检查 `Context Packager` 输出的 contract 是否完整
2. 确认 `buildTaskContract()` 调用时传入了正确的 TaskNode
3. 确认 OwnershipPlan 中该任务有分配到路径

### 2. Worker 执行超时

**错误信息**：
```
Error: Worker 执行超时 (300000ms)
```

**原因**：Worker 执行时间超过配置的超时限制。

**解决方案**：
1. 增加超时时间：在 `default-config.json` 中调整 `timeout_ms`
2. 拆分大任务为更小的子任务
3. 检查任务是否卡在某个工具调用上
4. 考虑使用更高 tier 的模型（tier-3 通常更快完成复杂任务）

### 3. gh CLI 未安装或未认证

**错误信息**：
```
Error: gh pr create 失败:
```

**原因**：GitHub CLI 未安装或未完成 OAuth 认证。

**解决方案**：
```bash
# 安装 gh
brew install gh  # macOS

# 认证
gh auth login

# 验证
gh auth status
```

### 4. DAG 有环

**错误信息**：
```
Error: 任务图存在循环依赖
```

**原因**：Task Graph Builder 构建了有环的依赖图。

**解决方案**：
1. 检查任务间的 `depends_on` 关系
2. 移除循环依赖
3. 考虑将循环依赖的任务合并为一个任务

---

## 状态机迁移错误

### Run 状态迁移异常

**合法的 Run 状态迁移路径**：

```
pending → planned → awaiting_approval → scheduled → running → verifying → succeeded
                                                                        → failed
                                                                        → blocked
                                                      → cancelled（任何阶段可触发）
```

**常见问题**：

| 症状 | 原因 | 解决方案 |
|------|------|---------|
| 停留在 `pending` | 意图分析失败 | 检查用户输入是否可解析 |
| 停留在 `planned` | 等待审批 | 检查是否有 pending 的审批请求 |
| 停留在 `awaiting_approval` | 审批未处理 | 手动审批或配置 `auto_approve_rules` |
| 停留在 `running` | Worker 无响应 | 检查超时设置，查看 Worker 日志 |
| 直接到 `failed` | 规划阶段就失败 | 查看 `status_history` 中的失败原因 |

**查看状态历史**：

每个 RunExecution 和 TaskAttempt 都记录完整的 `status_history`：

```typescript
// 每条状态迁移包含：
{
  from: "running",
  to: "failed",
  reason: "Worker 执行失败: 类型检查错误",
  timestamp: "2026-03-20T10:30:00Z",
  actor: "system"
}
```

### Task Attempt 状态迁移

**合法的 Attempt 迁移路径**：

```
pending → pre_check → executing → post_check → succeeded
                                              → failed
                    → failed (pre_check 失败)
                                              → timed_out
                                              → cancelled
```

**Pre-Check 检查项**（5 类）：

| 检查类型 | 标识 | 说明 |
|---------|------|------|
| 所有权 | `ownership` | 验证任务有权修改目标文件 |
| 策略 | `policy` | 评估策略规则是否允许 |
| 预算 | `budget` | 检查剩余预算是否充足 |
| 审批 | `approval` | 检查是否需要且已获得审批 |
| 能力 | `capability` | 检查 Worker 是否具备所需能力 |

---

## 策略阻断排查

### Policy Gate 阻断

**症状**：Gate 结果中 policy gate 未通过，阻断执行。

**排查步骤**：

1. **查看 Gate 结论**：检查 `GateResult.conclusion.findings` 中的具体发现

2. **查看匹配的规则**：
   ```typescript
   // PolicyViolation 包含：
   {
     rule_id: "path-001",
     category: "sensitive_directory",
     severity: "critical",
     message: "修改了敏感文件: .env",
     blocked: true
   }
   ```

3. **确认规则配置**：检查 `config/default-policy.json` 中对应 `rule_id` 的配置

4. **解决方案选择**：
   - 修改任务，避免触及受限资源
   - 调整策略规则的 `enforcement`（如从 `block` 改为 `warn`）
   - 禁用特定规则（设置 `enabled: false`）
   - 请求 admin 角色 override（需要 `gate.override` 权限）

### Security Gate 阻断

**症状**：Security gate 检测到敏感文件修改。

**检测模式**：
- `.env` 文件
- `credentials`（不区分大小写）
- `secret`（不区分大小写）
- `password`（不区分大小写）
- `.pem` 文件
- `.key` 文件
- `token`（不区分大小写）
- `apikey`（不区分大小写）

**解决方案**：
1. 确认该修改是否必要
2. 确保文件不包含明文密钥
3. 如确需修改，由 admin 角色 override gate

---

## 预算耗尽处理

### 症状

- `budget_exceeded` 审计事件触发
- Run 状态迁移到 `failed`，原因为 `budget_exhausted`
- CostLedger 中 `remaining_budget <= 0`

### 失败分类

预算耗尽的 FailureClass 为 `budget_exhausted`，推荐动作为：
- **retry**: 否（不自动重试）
- **escalate**: 否
- **downgrade**: 是（降级策略）
- **human**: 是（需要人工介入）

### 解决方案

1. **增加预算**：在 `default-config.json` 中增大 `budget_limit`

2. **降低成本**：
   - 限制最高模型 Tier（如设置 `max_model_tier: "tier-2"`）
   - 减少并行度（降低 `max_concurrency`）
   - 简化任务（减少任务数量或复杂度）

3. **查看成本分布**：
   ```typescript
   // CostLedger.tier_distribution 显示各 tier 的消耗：
   {
     "tier-1": { tokens: 5000, cost: 5, count: 3 },
     "tier-2": { tokens: 30000, cost: 150, count: 5 },
     "tier-3": { tokens: 80000, cost: 2000, count: 2 }
   }
   ```

4. **优化策略**：
   - 为简单任务强制使用 tier-1
   - 减少不必要的重试（重试会自动升级 tier，增加成本）

---

## 所有权冲突解决

### 症状

- Merge Guard 报告 `ownership_violations`
- Worker 抛出 `Worker 修改了沙箱外的路径` 错误
- 多个 Worker 修改同一文件导致 `file_conflicts`

### 所有权违规类型

| 违规类型 | 说明 | 严重程度 |
|---------|------|---------|
| 越界写入 | Worker 修改了 `allowed_paths` 之外的文件 | critical |
| 共享路径冲突 | 多个 Worker 同时修改同一文件 | high |
| 禁止路径访问 | Worker 修改了 `forbidden_paths` 中的文件 | critical |

### 排查步骤

1. **查看 OwnershipPlan**：
   ```typescript
   // 每个 OwnershipAssignment 包含：
   {
     task_id: "task_1",
     exclusive_paths: ["src/module-a/**"],
     shared_read_paths: ["src/shared/**"],
     forbidden_paths: [".env", "config/production/**"]
   }
   ```

2. **查看 MergeGuard 结果**：
   - `ownership_violations`: 所有权违规列表
   - `file_conflicts`: 文件冲突列表
   - `blocking_reasons`: 阻断原因

3. **解决方案**：
   - **拆分任务**：将冲突的文件修改分到不同任务中
   - **串行化**：将冲突任务设为依赖关系，顺序执行
   - **手动降级**：触发 `downgrade_triggered` 事件，降级为半串行模式

### 降级触发条件

系统自动降级的条件（来自 `decideDowngrade()`）：

| 条件 | 降级策略 |
|------|---------|
| 冲突率 > 30% | `serialize`（半串行） |
| Gate 连续 3 次阻断 | `serialize` + tier-3 |
| 关键路径被阻塞 | `serialize`（优先处理） |

---

## 其他常见问题

### EventBus 事件丢失

**原因**：EventBus 默认保留最近 10,000 条事件，超出后旧事件被丢弃。

**解决方案**：
1. 连接 `PersistentEventBusAdapter`，将事件持久化到 AuditTrail
2. 增大 `maxLogSize` 参数

### Gate 评估器未注册

**症状**：某类 gate 未出现在评估结果中。

**排查**：
```typescript
// 检查已注册的评估器
const types = gateSystem.getRegisteredTypes();
// 默认注册：test, lint_type, review, security, coverage, policy, documentation, release_readiness
```

注意：`perf` gate 没有默认评估器实现，需要自行注册。

### RBAC 权限不足

**症状**：操作被拒绝。

**内置角色权限表**：

| 权限 | admin | developer | reviewer | viewer |
|------|-------|-----------|----------|--------|
| run.create | o | o | - | - |
| run.cancel | o | o | - | - |
| run.retry | o | o | - | - |
| run.view | o | o | o | o |
| task.approve_model_upgrade | o | - | o | - |
| task.approve_sensitive_write | o | - | o | - |
| task.approve_autofix_push | o | - | - | - |
| gate.override | o | - | o | - |
| policy.manage | o | - | - | - |
| config.manage | o | - | - | - |
| audit.view | o | o | o | o |
| audit.export | o | - | - | - |

注意：`system` 和 `ci` 类型的 Actor 自动获得全部权限。
