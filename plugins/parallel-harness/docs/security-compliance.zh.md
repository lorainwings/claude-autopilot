> [English](security-compliance.md) | 中文

# parallel-harness 安全与合规说明

> 版本: v1.4.0 (GA) | 适用角色: 安全工程师、合规审计人员

## 安全架构概览

parallel-harness 从设计之初就将安全作为核心考量，实现了多层安全控制：

```
RBAC 层 → 策略引擎 → 路径沙箱 → 工具管控 → 审计追踪
```

## 访问控制

### RBAC 角色隔离

- 4 个内置角色，12 项细粒度权限
- 最小权限原则：viewer 仅有 run.view + audit.view
- 系统和 CI 类型 actor 具有完全权限（仅限自动化场景）
- 支持自定义角色满足组织需求

### 审批工作流

- 敏感操作（模型升级、敏感目录写入、autofix 推送）需要审批
- 审批绑定具体动作，不做笼统批准
- 支持自动审批规则，减少低风险操作的人工开销
- 所有审批决策记录到审计日志

## 数据安全

### 密钥管理

- `ConnectorConfig.secret_ref` 使用引用而非明文存储密钥
- 配置中不直接包含 API key、token 等敏感信息
- 建议使用环境变量或密钥管理服务

### 敏感文件保护

- Security Gate 自动检测以下敏感文件模式的修改：
  - `.env`、`credentials`、`secret`、`password`
  - `.pem`、`.key`、`token`、`apikey`
- 匹配的修改会产生 critical 级别发现并阻断流程

### 路径沙箱

- Worker 执行受 `allowed_paths` 和 `forbidden_paths` 约束
- 输出路径经过 `isPathInSandbox()` 二次验证
- 越界写入会触发 `OwnershipViolation` 并阻断

### 数据保留

- 审计日志默认保留在本地文件系统
- 支持 JSON/CSV 格式导出用于外部审计系统
- 事件总线默认保留最近 10000 条事件

## 策略即代码

### Policy Engine

- 所有约束通过 `PolicyEngine` 声明式定义
- 支持 5 种条件类型（路径、预算、风险、模型等级、动作类型）
- 4 种执行动作（block/warn/approve/log）
- 策略规则支持优先级排序

### 安全相关默认策略

| 规则 | 说明 | 默认动作 |
|------|------|---------|
| 敏感目录保护 | 匹配 config/secrets 等路径 | block |
| 高模型等级限制 | tier-3 模型使用需审批 | approve |
| 预算超限 | 单次 Run 超过配置预算 | block |

## 审计能力

### 审计事件类型

系统记录 30+ 种审计事件，覆盖：

- **Run 生命周期**: 创建、规划、开始、完成、失败、取消
- **任务执行**: 派发、完成、失败、重试
- **模型决策**: 路由、升级、降级
- **策略与审批**: 策略评估、违规、审批请求、审批决策
- **所有权**: 检查、违规
- **预算**: 消耗、超限
- **PR/CI**: 创建、审查、合并

### 审计记录结构

每条审计事件包含：

- `event_id`: 唯一事件 ID
- `type`: 事件类型
- `timestamp`: ISO-8601 时间戳
- `actor`: 触发者（ID、类型、名称、角色）
- `run_id / task_id / attempt_id`: 关联标识
- `payload`: 事件详情
- `scope`: 影响范围（组织/项目/仓库/环境）

### 导出与集成

```typescript
// 导出特定 Run 的审计日志
const jsonReport = await auditTrail.export("json", { run_id: "run_xxx" });

// 按时间范围导出
const rangeReport = await auditTrail.export("csv", {
  from: "2026-03-01T00:00:00Z",
  to: "2026-03-31T23:59:59Z",
});
```

## 工具管控

### Tool Allowlist/Denylist

```typescript
const DEFAULT_TOOL_POLICY = {
  allowlist: [],           // 空 = 允许所有
  denylist: ["TaskStop", "EnterWorktree"],  // 禁止危险操作
};
```

### 网络治理

- Worker 执行环境通过 `WorkerExecutionConfig` 控制
- 超时控制：默认 5 分钟
- 心跳监控：默认 30 秒间隔

## 合规清单

| 项目 | 状态 | 说明 |
|------|------|------|
| RBAC 角色隔离 | ✅ | 4 角色 12 权限 |
| 审批工作流 | ✅ | 绑定具体动作 |
| 审计追踪 | ✅ | 30+ 事件类型 |
| 密钥引用 | ✅ | secret_ref 非明文 |
| 敏感文件检测 | ✅ | Security Gate |
| 路径沙箱 | ✅ | 双重验证 |
| 策略即代码 | ✅ | PolicyEngine |
| 成本控制 | ✅ | 预算 + 自动停止 |
| 数据导出 | ✅ | JSON/CSV |
| 回放能力 | ✅ | ReplayEngine |

## 已知限制

1. **本地持久化**: 当前仅支持文件系统存储，生产环境建议接入数据库
2. **单进程审计**: 审计缓冲在单进程内，进程重启可能丢失未 flush 的事件
3. **静态密钥引用**: secret_ref 需要外部密钥管理服务支持
4. **审计数据加密**: 当前审计日志为明文 JSON，建议传输层加密
