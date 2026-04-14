# LSP 插件推荐

> 本文件由 `autopilot-setup/SKILL.md` 通过 `**执行前读取**` 引用。
> 包含 Step 5.5 的 LSP 插件推荐映射表、检测逻辑和用户交互。

## 推荐映射表

| 检测到的技术栈 | 推荐的 LSP 插件 | 安装命令 |
|---------------|---------------|---------
| Java/Gradle 或 Java/Maven | `jdtls-lsp` | `claude plugin install jdtls-lsp@claude-plugins-official` |
| TypeScript/Vue/React | `typescript-lsp` | `claude plugin install typescript-lsp@claude-plugins-official` |
| Python | `pyright-lsp` | `claude plugin install pyright-lsp@claude-plugins-official` |
| Rust | `rust-analyzer-lsp` | `claude plugin install rust-analyzer-lsp@claude-plugins-official` |
| Go | `gopls-lsp` | `claude plugin install gopls-lsp@claude-plugins-official` |
| Kotlin | `kotlin-lsp` | `claude plugin install kotlin-lsp@claude-plugins-official` |
| PHP | `php-lsp` | `claude plugin install php-lsp@claude-plugins-official` |
| Swift | `swift-lsp` | `claude plugin install swift-lsp@claude-plugins-official` |
| C/C++ | `clangd-lsp` | `claude plugin install clangd-lsp@claude-plugins-official` |

## 检测逻辑

```
detected_stacks = []  # 从 Step 1 的检测结果中获取

LSP_MAP = {
  "java": {"name": "jdtls-lsp", "desc": "Java 语言服务支持"},
  "typescript": {"name": "typescript-lsp", "desc": "实时类型检查和自动补全"},
  "python": {"name": "pyright-lsp", "desc": "Python 类型检查和智能提示"},
  "rust": {"name": "rust-analyzer-lsp", "desc": "Rust 语言服务"},
  "go": {"name": "gopls-lsp", "desc": "Go 语言服务"},
  ...
}

lsp_recommendations = []
for stack in detected_stacks:
  if stack in LSP_MAP:
    lsp = LSP_MAP[stack]
    # 检查 .claude/settings.json 中 enabledPlugins 是否已包含该 LSP
    installed = check_plugin_installed(lsp["name"])
    if not installed:
      lsp_recommendations.append(lsp)
```

## 用户交互

如果有推荐的 LSP 插件且未安装，通过 AskUserQuestion 展示：

```
"检测到以下技术栈可以安装 LSP 插件以提升代码编辑质量："

推荐列表:
- TypeScript LSP — 提供实时类型检查和自动补全
- Java JDTLS — 提供 Java 语言服务支持

选项:
- "全部安装 (Recommended)" → 逐个执行安装命令
- "选择性安装" → 展示多选列表
- "跳过，稍后手动安装" → 继续后续步骤
```

## 写入配置

安装的 LSP 插件信息记录到配置的 `lsp_plugins` 字段（信息性，不影响功能）：

```yaml
lsp_plugins:                    # 信息性字段，记录已推荐的 LSP 插件
  - name: typescript-lsp
    status: installed            # installed | skipped | failed
  - name: jdtls-lsp
    status: skipped
```

> LSP 推荐是可选步骤，跳过不影响配置生成和 autopilot 功能。
