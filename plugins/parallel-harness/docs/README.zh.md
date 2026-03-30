> [English](README.md) | 中文

# parallel-harness 文档

parallel-harness Claude Code 插件完整文档。

## 快速入门

| 文档 | 说明 |
|------|------|
| [架构概览](architecture/overview.zh.md) | 系统架构、分层、数据流 |
| [Claude 二次修复执行方案](architecture_and_research/08_claude_followup_remediation_execution_plan.md) | 基于最新 review 结果整理的详细施工单，可直接交给 Claude |
| [Claude 二次修复提示词](architecture_and_research/09_claude_followup_remediation_prompt.md) | 从二次修复执行方案中提炼出的可直接投喂 Claude 的提示词 |
| [Claude 修复结果 Review](architecture_and_research/10_claude_remediation_review.md) | 对最新一轮 Claude 修复结果的正式评审，列出未闭环项、主链接线缺口与关联问题 |
| [Claude 第三轮精确返修提示词](architecture_and_research/11_claude_precision_remediation_prompt.md) | 面向第三轮 Claude 返修的精确施工提示词，重点收口主链接线、durable truth 与治理闭环 |
| [运维指南](operator-guide.zh.md) | 安装、配置、日常运维 |
| [基本流程示例](examples/basic-flow.zh.md) | 分步使用示例 |

## 配置

| 文档 | 说明 |
|------|------|
| [策略配置指南](policy-guide.zh.md) | 策略规则配置与执行 |
| [管理员指南](admin-guide.zh.md) | RBAC 管理、审批工作流、预算控制 |

## 集成

| 文档 | 说明 |
|------|------|
| [集成指南](integration-guide.zh.md) | GitHub PR/CI、EventBus、自定义 Gate、Hook |
| [能力注册](capabilities/capability-registry.zh.md) | Skill/Hook/Instruction 扩展体系 |

## 运维

| 文档 | 说明 |
|------|------|
| [故障排查](troubleshooting.zh.md) | 常见错误与解决方案 |
| [FAQ](FAQ.zh.md) | 常见问题 |
| [安全与合规](security-compliance.zh.md) | 安全架构与合规检查清单 |

## 发布

| 文档 | 说明 |
|------|------|
| [发布检查清单](release-checklist.zh.md) | 发布前验证步骤 |
| [市场接入准备](marketplace-readiness.zh.md) | 市场集成检查清单 |
