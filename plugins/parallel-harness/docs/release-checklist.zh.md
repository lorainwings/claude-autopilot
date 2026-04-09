> [English](release-checklist.md) | 中文

# parallel-harness 发布检查清单

> 版本: v1.5.0 (GA) | 最后更新: 2026-03-20

## 代码检查项

- [ ] 所有 runtime 模块编译通过（`bunx tsc --noEmit`）
- [ ] 无 TypeScript 严格模式错误
- [ ] 所有公开 API 有 JSDoc 注释
- [ ] 无 `console.log` 调试语句残留（允许 `console.error` 用于错误日志）
- [ ] 所有 TODO/FIXME 已处理或记录到 issue
- [ ] 无硬编码的密钥、token 或绝对路径
- [ ] Schema 版本号与 `SCHEMA_VERSION` 常量一致（当前: `"1.0.0"`）
- [ ] `package.json` 版本号与发布版本一致
- [ ] `generateId()` 前缀命名规范一致（run_, plan_, att_, gate_, appr_, evt_, hfb_, fb_）
- [ ] 所有状态机迁移路径已文档化

## 测试检查项

- [ ] `bun test tests/unit/` 全部通过
- [ ] 测试数量 >= 216（当前基线）
- [ ] 0 个失败测试
- [ ] 每个 runtime 模块至少有对应测试文件
- [ ] Happy path 测试覆盖完整
- [ ] 关键 failure path 测试覆盖：
  - [ ] 超时处理
  - [ ] 预算耗尽
  - [ ] 所有权冲突
  - [ ] 策略阻断
  - [ ] Gate 阻断
  - [ ] 重试升级
  - [ ] 降级触发
- [ ] Edge case 测试：
  - [ ] 空任务图
  - [ ] 单任务图
  - [ ] 全冲突任务
  - [ ] 零预算

## 文档检查项

- [ ] README.zh.md 版本号更新
- [ ] README.md（英文）版本号更新
- [ ] CLAUDE.md 版本号和测试基线更新
- [ ] 运维指南（docs/operator-guide.zh.md）
- [ ] 策略配置指南（docs/policy-guide.zh.md）
- [ ] 集成指南（docs/integration-guide.zh.md）
- [ ] 故障排查（docs/troubleshooting.zh.md）
- [ ] 基本流程示例（docs/examples/basic-flow.zh.md）
- [ ] 市场接入准备（docs/marketplace-readiness.zh.md）状态更新
- [ ] 所有 Skills 的 SKILL.md 文档完整
- [ ] 架构图包含全部 15 个 runtime 模块

## 配置检查项

- [ ] `config/default-config.json` 参数合理
  - [ ] `max_concurrency` <= 10
  - [ ] `budget_limit` 有合理默认值
  - [ ] `enabled_gates` 包含必要的阻断性 gate（test, lint_type, policy）
  - [ ] `timeout_ms` >= 60000
- [ ] `config/default-policy.json` 规则完整
  - [ ] 敏感文件保护规则已启用（.env, credentials）
  - [ ] 预算警告规则已启用
  - [ ] 高风险审批规则已启用
- [ ] Gate 默认合同配置合理
  - [ ] 阻断性 gate: test, lint_type, security, policy, release_readiness
  - [ ] 非阻断性 gate: review, perf, coverage, documentation
  - [ ] 阈值设置合理

## 兼容性检查项

- [ ] Bun >= 1.0 运行正常
- [ ] TypeScript >= 5.0 编译通过
- [ ] macOS / Linux 平台测试
- [ ] Claude Code CLI 最新版本兼容
- [ ] gh CLI >= 2.0 集成测试（如启用 PR 功能）
- [ ] 无对 Node.js 特有 API 的依赖（纯 Bun 运行时）
- [ ] 无硬编码的平台特定路径分隔符
- [ ] Schema 版本向后兼容（或有迁移策略）

## 构建和分发检查项

- [ ] `bash tools/build-dist.sh` 构建成功
- [ ] dist/ 目录包含所有必要文件
- [ ] plugin.json 配置正确
- [ ] 无 node_modules 包含在 dist 中
- [ ] 无测试文件包含在 dist 中
- [ ] 无 .env 或密钥文件包含在 dist 中

## 安全检查项

- [ ] SecurityGateEvaluator 敏感文件模式列表完整
- [ ] 工具策略默认禁止危险操作（TaskStop, EnterWorktree）
- [ ] RBAC 权限划分合理
- [ ] 审计日志覆盖所有关键操作
- [ ] 无明文密钥存储
- [ ] `secret_ref` 使用引用而非明文

## 发布前最终确认

- [ ] 版本号三处一致：package.json、README.zh.md、SCHEMA_VERSION
- [ ] CHANGELOG 或 commit history 包含本版本变更摘要
- [ ] 标记 git tag（如 `v1.0.0`）
- [ ] marketplace.json 版本号更新
- [ ] 通知相关团队成员
