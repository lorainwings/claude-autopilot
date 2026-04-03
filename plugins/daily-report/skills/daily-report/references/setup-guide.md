# 日报插件初始化引导

```
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║   🔔  首次配置说明                                         ║
║                                                            ║
║   以下引导仅在首次使用时执行（约 3-5 分钟）。              ║
║   ✅ 配置完成后保存在本地，后续使用直接跳过，秒级启动！    ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
```

## 前置条件

- Node.js 已安装（lark-cli 依赖）
- 已有公司内控系统账号密码

## 一、lark-cli 安装与配置（必需）

飞书聊天记录是日报生成的必要数据来源。lark-cli 是飞书官方开源 CLI 工具，覆盖 11 大业务域、200+ 命令。

> **幂等原则**: 每个步骤执行前先检查是否已完成，已完成则跳过，禁止重复执行。

### 1.1 安装 CLI 本体

先检查: `which lark-cli`，已安装则跳过。

```bash
npm install -g @larksuite/cli
```

验证安装:

```bash
lark-cli --help
```

### 1.2 安装 Skill（接入 AI Agent 必需）

**检测是否已安装**（按优先级）:
1. 当前会话的可用 skill 列表中存在 lark-* 系列 skill → 已安装且已加载，跳过
2. 文件系统 `~/.claude/skills/lark-im` 存在 → 已安装但当前会话未加载，执行 `/reload-plugins` 热重载
3. 都不存在 → 未安装，执行安装后 `/reload-plugins` 热重载

lark-cli 需要安装 skill 才能被 Claude Code 等 AI Agent 调用（自动执行，无需用户确认）:

```bash
npx skills add larksuite/cli -y -g
```

安装完成后执行 `/reload-plugins` 即可在当前会话中热重载 skill，无需重启 Claude Code。

### 1.3 初始化飞书应用凭据

先检查: `lark-cli auth status`，exit code 0 表示已配置，跳过此步。

```bash
lark-cli config init --new
```

执行后终端会输出授权 URL 和终端二维码。**处理规则**:

- **禁止原样输出二维码**: 终端二维码在 Claude 窗口中会被折叠导致无法扫描，不要展示
- **提取 URL**: 从输出中提取 `https://` 开头的授权链接
- **自动打开浏览器**: 立即执行 `open <URL>`（macOS）在用户默认浏览器中打开，无需用户手动复制

**自动开浏览器脚本模板**（所有授权命令统一使用，Bash timeout 设为 600000）:

```bash
_T=$(mktemp)
{CMD} > "$_T" 2>&1 &
_P=$!
_URL=""
for _i in $(seq 1 60); do
  _URL=$(grep -oE 'https://[^ ]+' "$_T" 2>/dev/null | head -1)
  [ -n "$_URL" ] && break
  kill -0 $_P 2>/dev/null || break
  sleep 0.5
done
[ -n "$_URL" ] && open "$_URL"
wait $_P
cat "$_T"
rm -f "$_T"
```

将 `{CMD}` 替换为实际命令。URL 提取后立即通过 `open` 在默认浏览器打开，命令在后台等待用户完成授权。

用户在浏览器中完成以下操作:

1. 系统会自动创建一个名为"飞书 CLI"的机器人应用
2. 页面显示权限列表，**滚动到底部，把能开的权限都开启**
3. 点击【开通并授权】按钮
4. 授权成功后网页显示成功提示，终端同步收到确认并自动退出

### 1.4 授权飞书权限 (scope)

先检查: `lark-cli im chats list --page-size 1 --format json`，成功返回数据则跳过全部授权。

lark-cli 通过逐个 scope 授权的方式获取飞书 API 权限。每条授权命令执行后，终端会输出设备验证链接和二维码。**处理规则**与 1.3 相同:

- **禁止原样输出二维码**: 在 Claude 窗口中会折叠显示不完整
- 使用上述「自动开浏览器脚本模板」执行授权命令，URL 自动在浏览器打开
- 仅以文字告知用户"已在浏览器打开授权页面，请完成授权"

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

> **幂等原则**: 先读取 `~/.config/daily-report/config.json`，已存在的字段直接复用，仅收集缺失项。所有字段都齐全时跳过整个配置收集流程。

### 3.1 提供账号信息

Claude 会**逐步引导**你填入**缺失的**配置（对应内控系统登录页面的表单字段）:

1. **日报页面地址**: 浏览器中打开日报的 URL（如 `https://xxx.com/neikong/#/daily-report`），系统自动推导 API 地址
2. **公司名称**: 对应登录页顶部的"租户/公司"选择框
3. **用户名**: 对应登录页"账号"输入框
4. **密码**: 对应登录页"密码"输入框（明文存本地，传输时自动加密）

以上已配置过的项会自动跳过，不会重复询问。

```
┌──────────────────────────────────────────────────────┐
│ 💡 以上信息仅首次填写，安全保存在本地配置文件中，    │
│    后续运行自动读取，无需再次输入。                  │
└──────────────────────────────────────────────────────┘
```

### 3.2 自动登录

Claude 会用你提供的账号密码调用登录接口，自动获取:

- **Token**: 用于后续所有 API 调用的身份凭证
- **userId / deptId**: 从用户信息接口自动获取，无需手动提供

### 3.3 补充配置

Claude 还会询问**缺失的**配置项（已配置过的自动跳过）:

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
