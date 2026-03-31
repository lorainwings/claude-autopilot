# 日报插件初始化引导

## 前置条件

- Node.js 已安装（lark-cli 依赖）
- 已有公司内控系统账号密码

## 一、lark-cli 安装与配置（必需）

飞书聊天记录是日报生成的必要数据来源。lark-cli 是飞书官方开源 CLI 工具，覆盖 11 大业务域、200+ 命令。

### 1.1 安装 CLI 本体

```bash
npm install -g @larksuite/cli
```

验证安装:

```bash
lark-cli --help
```

### 1.2 安装 Skill（接入 AI Agent 必需）

lark-cli 需要安装 skill 才能被 Claude Code 等 AI Agent 调用:

```bash
npx skills add larksuite/cli -y -g
```

安装完成后**必须重启 Claude Code**，使 skill 生效。

### 1.3 初始化飞书应用凭据

```bash
lark-cli config init --new
```

执行后终端会输出一个授权 URL。**必须将完整输出原样展示给用户，严禁折叠或省略**。使用 `open <URL>`（macOS）自动在浏览器中打开该链接:

1. 系统会自动通过 API 创建一个名为"飞书 CLI"的机器人应用
2. 页面会显示权限列表，**滚动到底部，把能开的权限都开启**
3. 点击【开通并授权】按钮
4. 授权成功后网页显示成功提示，终端同步收到确认并自动退出

### 1.4 授权飞书权限 (scope)

lark-cli 通过逐个 scope 授权的方式获取飞书 API 权限。每条授权命令执行后，终端会输出一个设备验证链接（形如 `https://accounts.feishu.cn/oauth/v1/device/verify?...`）。**必须将命令完整输出原样展示给用户，严禁折叠**。从输出中提取 URL，使用 `open <URL>`（macOS）自动在浏览器打开完成授权，终端自动确认。

日报插件所需的核心 scope:

```bash
lark-cli auth login --scope "im:message:readonly"
lark-cli auth login --scope "im:chat:readonly"
lark-cli auth login --scope "im:message.group_msg:get_as_user im:message.p2p_msg:get_as_user contact:user.base:readonly"
```

> 注意: 实际使用中 lark-cli skill 会自动检测缺失的 scope，并在错误信息的 `hint` 字段中给出修复命令。无需预先记忆所有 scope，按提示补充即可。

### 1.5 验证

安装完成后无需手动验证。daily-report 插件在阶段 1 环境检查中会自动验证 lark-cli 权限是否就绪。

## 二、飞书权限说明

日报插件依赖以下飞书 scope，在阶段 1.4 中逐个授权:

| scope | 用途 | 是否需要管理员审批 |
|-------|------|-------------------|
| `im:message:readonly` | 读取群聊消息 | 否 |
| `im:chat:readonly` | 读取群聊信息 | 否 |
| `im:message.group_msg:get_as_user` | 以用户身份获取群消息 | 否 |
| `im:message.p2p_msg:get_as_user` | 以用户身份获取单聊消息 | 否 |
| `contact:user.base:readonly` | 读取用户基本信息 | 否 |

如果后续使用中遇到 `missing_scope` 错误，lark-cli 会在错误的 `hint` 字段中给出修复命令，按提示执行 `lark-cli auth login --scope "..."` 即可补充授权。

## 三、内控日报 API 配置

### 3.1 提供账号信息

Claude 会依次询问以下信息:

| 配置项 | 说明 | 示例 |
|--------|------|------|
| 日报页面地址 | 浏览器中打开日报的 URL | `https://xxx.com/neikong/#/daily-report` |
| API 基础地址 | 内控系统 API 的完整前缀 | `https://xxx.com/prodneikong/server/admin-api` |
| 登录账号 | 内控系统用户名 | `lorain` |
| 登录密码 | 内控系统密码 | `xxx` |
| 租户 ID | 通常为 `"1"`，不确定可默认 | `1` |

> **API 基础地址如何获取**: 如果不确定，可在浏览器中打开内控系统任意页面，按 F12 打开 DevTools Network 面板，找到任一 API 请求，复制其 URL 中域名 + 路径前缀部分即可（不含具体接口路径和查询参数）。

### 3.2 自动登录

Claude 会用你提供的账号密码调用登录接口，自动获取:
- **Token**: 用于后续所有 API 调用的身份凭证
- **userId / deptId**: 从用户信息接口自动获取，无需手动提供

### 3.3 补充配置

Claude 还会询问:

- **Git 仓库路径**: 需要扫描提交记录的本地仓库路径列表
- **Git Author**: 你的 git 提交作者名 (支持 `|` 分隔多个别名，如 `lorain|廖员`)

飞书群聊消息由插件在运行时自动扫描用户所在的全部群聊，无需手动配置。

### 3.4 安全说明

配置文件 `~/.config/daily-report/config.json` 包含账号密码等敏感信息。初始化完成后，插件会自动设置文件权限为 `600`（仅本人可读写）。

## 四、Token 自动刷新

内控系统的 Token 通常有有效期。插件会在每次运行时自动检测 Token 是否有效:

1. 调用用户信息接口验证 Token
2. 若 Token 已过期，自动用 config 中的账号密码重新登录获取新 Token
3. 更新 config.json 中的 `token` 字段
4. **全程自动，无需用户干预**
