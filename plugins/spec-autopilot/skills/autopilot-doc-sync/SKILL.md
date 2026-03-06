---
name: autopilot-doc-sync
description: "Sync documentation with code changes for spec-autopilot plugin"
user-invocable: true
argument-hint: "[可选: 版本号，如 3.2.0]"
---

# Autopilot Documentation Sync

自动检测插件代码变更并更新相关技术文档。

## 执行流程

### Step 1: 读取变更内容

1. 读取 `CHANGELOG.md` 最新版本（第一个 `## [X.X.X]` 章节）
2. 提取变更类型：
   - **Added**: 新增功能
   - **Changed**: 修改功能
   - **Fixed**: 修复问题
   - **Breaking Changes**: 破坏性变更

### Step 2: 识别影响范围

根据变更类型确定需要更新的文档：

| 变更类型 | 影响文档 |
|---------|---------|
| 新增 Hook 脚本 | README.md (Hook Scripts 表格), architecture.md (Hook 执行流程), gates.md (Layer 2 章节) |
| 新增配置字段 | configuration.md (字段表格), integration-guide.md (配置示例) |
| Phase 流程变更 | phases.md (对应 Phase 章节), protocol.md (checkpoint 格式) |
| 新增特性 | README.md (Key Features), CHANGELOG.md |
| 性能优化 | architecture.md (Performance Considerations), troubleshooting.md |
| 新增 Skill | README.md (Components 表格) |
| 配置默认值变更 | configuration.md (Default 列), integration-guide.md (示例) |

### Step 3: 检查文档覆盖

对每个影响的文档：
1. 检查是否提及新版本号（如 `v3.2.0` 或 `3.2.0`）
2. 检查是否包含新特性关键词
3. 生成缺失内容清单

### Step 4: 生成更新清单

输出格式：

```markdown
## 文档更新清单

### 必须更新（缺失新特性）
- [ ] README.md: 新增 Hook Scripts 表格条目
- [ ] architecture.md: 新增 Hook 执行流程图
- [ ] gates.md: 新增 Layer 2 章节

### 建议更新（版本号未提及）
- [ ] configuration.md: 更新版本标记
- [ ] integration-guide.md: 更新配置示例

### 无需更新
- ✅ phases.md: 已包含新特性
- ✅ troubleshooting.md: 已包含新特性
```

### Step 5: 询问用户

AskUserQuestion:
- 选项 1: 立即更新所有文档（推荐）
- 选项 2: 仅更新必须项
- 选项 3: 生成更新指令，稍后手动执行
- 选项 4: 跳过（不推荐）

### Step 6: 执行更新

如果用户选择更新：
1. 使用并行 Agent 分批更新文档（每批 2-3 个文档）
2. 每个 Agent 负责：
   - 读取文档当前内容
   - 根据 CHANGELOG 生成新增内容
   - 使用 Edit 工具精确插入
3. 更新完成后生成验证报告

## 文档映射矩阵

| 文档 | Hook | Config | Phase | Feature | Performance | Skill |
|------|------|--------|-------|---------|-------------|-------|
| README.md | ✅ | ⚠️ | ⚠️ | ✅ | ⚠️ | ✅ |
| architecture.md | ✅ | ⚠️ | ⚠️ | ⚠️ | ✅ | ⚠️ |
| configuration.md | ⚠️ | ✅ | ⚠️ | ⚠️ | ⚠️ | ⚠️ |
| gates.md | ✅ | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ |
| phases.md | ⚠️ | ⚠️ | ✅ | ⚠️ | ⚠️ | ⚠️ |
| integration-guide.md | ⚠️ | ✅ | ⚠️ | ✅ | ⚠️ | ⚠️ |
| troubleshooting.md | ✅ | ⚠️ | ⚠️ | ✅ | ✅ | ⚠️ |
| protocol.md | ⚠️ | ⚠️ | ✅ | ⚠️ | ⚠️ | ⚠️ |
| semantic-validation.md | ⚠️ | ⚠️ | ✅ | ⚠️ | ⚠️ | ⚠️ |
| knowledge-accumulation.md | ⚠️ | ⚠️ | ⚠️ | ✅ | ⚠️ | ⚠️ |
| quality-scans.md | ⚠️ | ⚠️ | ⚠️ | ✅ | ⚠️ | ⚠️ |

图例: ✅ 必须更新, ⚠️ 可能需要更新

## 触发方式

### 手动触发
```
/spec-autopilot:doc-sync
/spec-autopilot:doc-sync 3.2.0
```

### 自动触发（已集成）
- Phase 7 归档前检查（在 Step 1 后）
- Git pre-commit Hook 警告

## 实施示例

```
用户: /spec-autopilot:doc-sync

Claude:
📚 读取 CHANGELOG.md 最新版本...
✅ 检测到版本 3.2.0，包含以下变更:
  - Added: 新增 parallel-merge-guard.sh Hook
  - Changed: max_agents 默认值从 3 改为 5
  - Fixed: 约束缓存 TTL 从 5 分钟改为 10 分钟

🔍 分析影响范围...
  - Hook 变更 → README.md, architecture.md, gates.md
  - 配置变更 → configuration.md, integration-guide.md
  - 性能优化 → architecture.md

📋 检查文档覆盖...
  ❌ README.md: 未提及 parallel-merge-guard.sh
  ❌ gates.md: 未提及 parallel-merge-guard.sh
  ⚠️ configuration.md: 未提及 max_agents=5
  ✅ architecture.md: 已包含约束缓存说明

## 文档更新清单

### 必须更新
- [ ] README.md: Hook Scripts 表格新增 parallel-merge-guard.sh
- [ ] gates.md: 新增 PostToolUse Parallel Merge Guard 章节

### 建议更新
- [ ] configuration.md: max_agents 默认值改为 5
- [ ] integration-guide.md: 配置示例更新

### 无需更新
- ✅ architecture.md: 已包含相关内容

AskUserQuestion: 如何处理?
1. 立即更新所有文档（推荐）
2. 仅更新必须项
3. 生成更新指令，稍后手动执行
4. 跳过

用户选择: 1

🚀 启动并行更新...
  Agent 1: 更新 README.md + gates.md
  Agent 2: 更新 configuration.md + integration-guide.md

✅ 更新完成！
  - README.md: +3 行
  - gates.md: +25 行
  - configuration.md: 修改 1 处
  - integration-guide.md: 修改 2 处

📊 验证报告:
  ✅ 所有文档版本号一致: 3.2.0
  ✅ 所有新特性均有文档覆盖
  ✅ 配置示例与代码一致

建议执行:
  git add plugins/spec-autopilot/README.md plugins/spec-autopilot/docs/
  git commit -m "docs: sync documentation for v3.2.0"
```
