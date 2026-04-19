# daily-report Plugin CLAUDE.md

> 此文件为 daily-report 插件的工程法则。
> 所有 AI Agent 在执行期间必须遵守。
> 版本: 1.3.0 <!-- x-release-please-version -->

## 插件定位

纯 Skill 型插件，无 TypeScript runtime、无 hooks。
基于 git 提交 + lark-cli 聊天记录，自动生成并提交内控日报。

## 核心约束

1. **配置不入 git**: API 地址、Token、userId 等敏感信息存放于 `~/.config/daily-report/config.json`，绝不硬编码在插件中
2. **Token 有效性优先**: 每次执行前必须验证 Token 有效性，过期则立即引导用户重新获取
3. **用户确认后提交**: 日报生成后必须展示给用户审核，确认后才调用 API 提交
4. **跳过已填日期**: 提交前检查目标日期是否已有日报，已填写的自动跳过
5. **工时固定 8h**: 每天总工时固定 8 小时，按条目数量比例分配

## 数据来源优先级

1. **Git 提交记录** (必需): 从配置的仓库路径中按 author + 日期提取
2. **飞书聊天记录** (必需): 通过 lark-cli 拉取工作群消息，lark-cli 未安装时阻断流程并引导安装
3. **日报分类接口** (必需): 调用内控系统分类列表获取可用 matterId

## 触发方式

- Skill 触发词: `/daily-report`
- 自然语言: "填写日报"、"写日报"、"生成日报"

