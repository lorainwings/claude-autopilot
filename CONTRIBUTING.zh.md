> [English](CONTRIBUTING.md) | 中文

# 贡献指南

感谢你对本项目的关注！本指南将帮助你快速上手。

## 开始

### 前置条件

- Claude Code CLI (v1.0.0+)
- python3 (3.8+)
- bash (4.0+)
- bun (1.0+) 用于 parallel-harness
- git

### 初始化

```bash
git clone https://github.com/lorainwings/claude-autopilot.git
cd claude-autopilot

# 一键初始化：激活 git hooks（必需）
make setup
```

### 运行测试

```bash
make test
```

## 开发工作流

### 1. 创建分支

```bash
git checkout -b feature/my-feature
```

### 2. 修改代码

- 在 `plugins/spec-autopilot/` 中编辑 spec-autopilot 插件源文件
- 在 `plugins/parallel-harness/` 中编辑 parallel-harness 插件源文件
- **禁止直接编辑** `dist/` 中的文件 — 它们是自动生成的

### 3. 测试修改

```bash
# 运行完整测试套件
make test

# 运行 parallel-harness 测试
make ph-test
```

### 4. 重新构建分发包

```bash
make build

# 构建 parallel-harness
make ph-build
```

### 5. 提交并推送

```bash
git add -A
git commit -m "feat: 变更描述"
git push origin feature/my-feature
```

### 6. 创建 Pull Request

向 `main` 分支提交 PR，附上清晰的变更说明。

## 编码规范

### Shell 脚本

- 所有脚本必须通过 `bash -n` 语法检查（包含在 `make test` 中）
- 适当使用 `set -euo pipefail`
- 所有 Hook 必须配置超时
- Hook 退出码：始终 `exit 0`（通过 stdout JSON 传递决策）

### TypeScript (parallel-harness)

- 所有 TypeScript 必须通过 `bunx tsc --noEmit`
- 使用 strict 模式，ESNext 目标
- 测试使用 `bun test`
- 必须维持最低 219 个测试基线

### 测试纪律

- 每个新功能必须在 `tests/test_*.sh` 中包含对应测试
- 每个功能至少 3 个测试用例：正常 + 边界 + 错误路径
- 禁止弱化已有断言
- 删除现有测试必须在 commit message 中说明理由

### 文档

- 所有文档支持双语（英文 + 中文）
- 英文为默认版本（`.md`），中文为伴随版本（`.zh.md`）
- 两个版本顶部都必须有语言切换链接
- 共享内容（代码块、图表）在两个版本中必须一致

### 版本升级

- 版本号变更**必须**通过 `tools/bump-version.sh` 执行
- 禁止手动编辑 plugin.json、marketplace.json、README.md 或 CHANGELOG.md 中的版本号

### 构建纪律

- 修改任何运行时文件后运行 `make build`
- `dist/` 是自动生成的 — 所有修改在源码中进行
- 测试文件不会进入 `dist/`

## Commit Message 规范

遵循 [Conventional Commits](https://www.conventionalcommits.org/) 格式：

```
feat: 添加新功能
fix: 修复 bug
docs: 更新文档
test: 添加或更新测试
refactor: 代码重构
chore: 维护任务
```

## 提交 Issue

- 使用 [GitHub Issues](https://github.com/lorainwings/claude-autopilot/issues)
- 包含：复现步骤、预期行为、实际行为
- Hook 相关问题：包含 stderr 输出（Claude Code 中按 Ctrl+O）

## 许可证

通过贡献，你同意你的贡献将在 [MIT 许可证](LICENSE) 下发布。
