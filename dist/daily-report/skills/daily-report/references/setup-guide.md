# 日报插件初始化引导

## 前置条件

- Node.js 已安装（lark-cli 依赖）
- Chrome / Edge 或其他支持 DevTools 的浏览器
- 已登录公司内控系统日报页面

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

## 三、内控日报 API 抓包

### 3.1 打开内控日报页面

在浏览器中打开公司内控系统的日报填写页面。

### 3.2 打开 DevTools Network 面板

- 快捷键: `F12` 或 `Cmd+Option+I` (macOS) / `Ctrl+Shift+I` (Windows/Linux)
- 切换到 **Network** 标签页
- 勾选 **Preserve log** (保留日志)

### 3.3 触发一次 API 请求

在日报页面执行一次操作以产生网络请求，例如:

- 查看日报分类列表
- 查看某天的日报记录
- 打开日报填写表单

### 3.4 找到目标请求

在 Network 面板中找到包含以下关键词的请求:

- `daily-report-matter/list` (分类列表)
- `daily-report/page` (日报查询)
- `daily-report/create` (日报创建)

### 3.5 复制 cURL 命令

- 右键点击目标请求
- 选择 **Copy** → **Copy as cURL**
- 将复制的内容粘贴给 Claude

### 3.6 Claude 自动解析

Claude 会从 cURL 命令中自动提取以下信息:

| 字段 | 来源 |
|------|------|
| `pageUrl` | cURL 的 `Referer` / `Origin` 头，或由用户确认的日报页面地址 |
| `baseUrl` | 请求 URL 的**协议+域名（含端口）**，不含任何路径部分 |
| `apiPrefix` | 请求 URL 中域名之后、具体接口路径之前的**路径前缀** |
| `token` | `Authorization` 请求头 |
| `tenantId` | `tenant-id` 请求头或 URL 参数 |
| `userId` | 自动通过 API 获取（调用 `get-permission-info` 接口） |
| `deptId` | 自动通过 API 获取（调用 `get-permission-info` 接口） |

示例: cURL URL 为 `https://xxx.com/prodneikong/server/admin-api/pm/work-hour-matter/list?deptId=125` → `baseUrl` = `https://xxx.com`，`apiPrefix` = `/prodneikong/server/admin-api`

其中 `pageUrl` 会保存到 config.json，后续 Token 过期时插件会直接提示你打开这个地址，无需再解释完整抓包流程。

### 3.7 补充配置

Claude 还会询问:

- **Git 仓库路径**: 需要扫描提交记录的本地仓库路径列表
- **Git Author**: 你的 git 提交作者名 (支持 `|` 分隔多个别名，如 `lorain|廖员`)

飞书群聊消息由插件在运行时自动扫描用户所在的全部群聊，无需手动配置。

## 四、Token 过期处理

内控系统的 Token 通常有有效期。初始化时已将日报页面地址保存为 `pageUrl`，因此后续刷新 Token 非常简单:

1. daily-report 检测到 Token 过期，会直接提示: "请打开 {pageUrl}，抓一个请求的 cURL 粘贴给我"
2. 粘贴 cURL 后，Claude 仅更新 `token` 字段，其他配置保持不变
3. 继续执行日报流程，**无需重新初始化**
