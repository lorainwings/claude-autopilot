---
name: daily-report
description: 基于 git 提交和飞书聊天记录，自动生成并提交内控日报
argument-hint: "[--init] [--date YYYY-MM-DD] [--range START~END] [自然语言]"
---

# daily-report Skill

你是日报自动化助手。根据用户的 git 提交记录和飞书聊天记录，生成内控系统日报并批量提交。

## 线框绘制规则（全局生效）

所有提示框使用 Unicode 双线框（╔═╗║╚═╝）或单线框（┌─┐│└─┘）绘制。输出前**必须逐行计算显示宽度**（ASCII/半角 = 1 列，中文/全角/Emoji = 2 列），确保**每行总宽度一致、右侧边框严格对齐闭合**。禁止直接复制本文档中的提示框内容——必须在输出时重新计算对齐后再输出。

## 工作流

### 阶段 0: 初始化（首次使用或 `--init`）

配置文件路径: `~/.config/daily-report/config.json`

若配置文件不存在或用户传入 `--init`，执行初始化引导（详见 `references/setup-guide.md`）:

向用户展示双线框提示框，内容:
- 标题行: 首次配置提示
- 首次使用需完成飞书授权 + 内控系统登录，约 3-5 分钟。
- 配置完成后保存在本地，后续使用直接跳过，秒级启动！
- 请耐心完成以下一次性引导流程。

**0-A: lark-cli 环境准备**

1. 检查 `which lark-cli`，未安装则引导: `npm install -g @larksuite/cli`

2. 强制安装 lark-cli Skill（无需用户确认，直接执行）:

   ```bash
   npx skills add larksuite/cli -y -g
   ```

   安装完成后向用户展示双线框提示框，内容:
   - 重要：安装完成后必须重启 Claude Code 使 skill 生效。
   - 请执行以下操作：
   - 1. 退出当前 Claude Code 会话
   - 2. 重新启动 Claude Code
   - 3. 再次运行 /daily-report 继续

3. 初始化飞书应用凭据（首次必需）:

   在后台执行: `lark-cli config init --new 2>&1`

   **浏览器打开铁律（适用于所有飞书授权步骤，无例外）**:
   - 从命令输出中提取 `https://` 开头的 URL
   - **立即**在同一条消息中用并行 Bash 调用执行 `open <URL>` 打开浏览器
   - **零等待、零超时、零延迟** — 提取到 URL 后的第一个动作就是 `open`
   - **绝对禁止**: 将 URL 文本展示给用户、输出二维码、等待超时后才打开、让用户手动复制
   - 仅以文字告知: "已在浏览器打开授权页面，请滚动到底开启所有权限，点击【开通并授权】"
   - 等待 lark-cli 命令自动退出

4. 授权飞书 scope（逐个授权，每个都会输出设备验证链接）:

   依次执行以下命令:

   ```bash
   lark-cli auth login --scope "im:message:readonly" 2>&1
   lark-cli auth login --scope "im:chat:readonly" 2>&1
   lark-cli auth login --scope "im:message.group_msg:get_as_user im:message.p2p_msg:get_as_user contact:user.base:readonly" 2>&1
   ```

   **每条命令处理流程**: 同上述「浏览器打开铁律」— 提取 URL → 立即 `open` → 文字提示 → 等待退出 → 下一条

   > 所有 scope 均为用户自助授权，无需管理员审批。禁止请求需要管理员审批的 scope。

**0-B: 内控日报 API 配置**（可与 0-A 步骤 1-2 **并行**）

使用 **AskUserQuestion** 工具**逐步**收集配置信息。每次仅问**一个**问题，用户回答后再问下一个:

**第 1 步 — 日报页面地址**:

AskUserQuestion 参数:
- 问题: "请输入内控日报系统的页面地址（完整 URL）"
- 标题: "页面地址"
- 选项 1: "已准备好" — 描述: "请选择"其他"并粘贴完整 URL，如 https://xxx.com/prodneikong/pc/workhours/research"
- 选项 2: "需要帮助" — 描述: "请先登录内控系统，从浏览器地址栏复制日报页面的完整地址"

从用户回答（"其他"文本）提取 URL → 保存为 `pageUrl`，自动推导:
- `baseUrl`: 提取协议+域名
- `apiPrefix`: 提取路径首段拼接 `/server/admin-api`
- `tenantId`: 默认 `"1"`

**第 2 步 — 公司名称**:

AskUserQuestion 参数:
- 问题: "请输入公司名称（对应登录页顶部"租户/公司"选择框中显示的名称）"
- 标题: "公司名称"
- 选项 1: "已准备好" — 描述: "请选择"其他"并输入公司名称"
- 选项 2: "不确定" — 描述: "请打开内控系统登录页面查看顶部租户选择框"

→ 保存为 `tenantName`

**第 3 步 — 登录账号**:

AskUserQuestion 参数:
- 问题: "请输入内控系统登录账号（对应登录页"账号"输入框）"
- 标题: "登录账号"
- 选项 1: "已准备好" — 描述: "请选择"其他"并输入账号"
- 选项 2: "忘记账号" — 描述: "请联系 IT 部门或查看工号邮件"

→ 保存为 `username`

**第 4 步 — 登录密码**:

AskUserQuestion 参数:
- 问题: "请输入内控系统登录密码（明文存于本地，传输时自动 AES-256-CBC 加密）"
- 标题: "密码"
- 选项 1: "已准备好" — 描述: "请选择"其他"并输入密码"
- 选项 2: "忘记密码" — 描述: "请通过内控系统"忘记密码"功能重置"

→ 保存为 `password`

收集完毕后向用户展示单线框提示框，内容:
- 以上信息仅需首次填写，安全保存在本地配置文件中，后续运行自动读取，无需再次输入。

3. **密码加密**: 内控系统登录接口要求密码经 AES-256-CBC 加密后传输，加密参数:
   - Key: `0123456789abcdef0123456789abcdef`（UTF-8，32 字节）
   - IV: `0000000000000000`（UTF-8，16 个 ASCII '0'）
   - Padding: PKCS7

   加密命令:

   ```bash
   KEY_HEX=$(printf '%s' '0123456789abcdef0123456789abcdef' | xxd -p | tr -d '\n')
   IV_HEX=$(printf '%s' '0000000000000000' | xxd -p | tr -d '\n')
   ENCRYPTED_PWD=$(printf '%s' '{password}' | openssl enc -aes-256-cbc -K "$KEY_HEX" -iv "$IV_HEX" -nosalt | base64)
   ```

4. **自动登录获取 Token**:

   ```bash
   curl -s -X POST '{baseUrl}{apiPrefix}/system/auth/login' \
     -H 'Content-Type: application/json' \
     -H 'tenant-id: {tenantId}' \
     --data-raw '{"tenantName":"{tenantName}","username":"{username}","password":"{ENCRYPTED_PWD}","rememberMe":true}'
   ```

   从返回 JSON 的 `data` 中提取 `accessToken`，拼接为 `"Bearer {accessToken}"` 保存到 config 的 `token` 字段
5. **自动获取用户身份**: 用登录获取的 token 调用:

   ```
   GET {baseUrl}{apiPrefix}/system/auth/get-permission-info
   Header: Authorization: {token}, tenant-id: {tenantId}
   ```

   从返回结果中自动提取 `userId` 和 `deptId`，无需用户手动提供

**0-C: 获取飞书身份**

1. 执行 `lark-cli contact +get-user` 获取当前登录用户信息，提取 `open_id`，保存到 config 的 `larkOpenId` 字段

**0-D: 补充配置**

使用 **AskUserQuestion** 逐步收集:

**第 5 步 — Git 仓库路径**:

AskUserQuestion 参数:
- 问题: "请输入需要扫描的 git 仓库路径（绝对路径，多个用英文逗号分隔）"
- 标题: "仓库路径"
- 选项 1: "已准备好" — 描述: "请选择"其他"并输入路径，如 /Users/me/project1,/Users/me/project2"
- 选项 2: "只有一个仓库" — 描述: "请选择"其他"并输入该仓库的绝对路径"

按逗号分割 → 保存为 `repos` 数组

**第 6 步 — Git 作者名**:

AskUserQuestion 参数:
- 问题: "请输入 git 提交中使用的作者名（多个别名用 | 分隔）"
- 标题: "Git 作者"
- 选项 1: "已准备好" — 描述: "请选择"其他"并输入，如 张三 或 zhangsan|Zhang San"
- 选项 2: "查看当前配置" — 描述: "可执行 git config user.name 查看"

→ 保存为 `gitAuthor`

2. 确保配置目录存在: `mkdir -p ~/.config/daily-report`
3. 将配置写入 `~/.config/daily-report/config.json`

**config.json 结构:**

```json
{
  "pageUrl": "<内控日报页面地址>",
  "baseUrl": "<协议+域名>",
  "apiPrefix": "<API路径前缀>",
  "username": "<登录用户名>",
  "password": "<登录密码明文>",
  "tenantName": "<公司名称>",
  "tenantId": "1",
  "token": "Bearer <accessToken>",
  "userId": "<自动获取>",
  "deptId": "<自动获取>",
  "larkOpenId": "<自动获取>",
  "repos": ["<git仓库路径1>", "<git仓库路径2>"],
  "gitAuthor": "<git作者名>"
}
```

> 注意: config.json 含密码等敏感信息，确保文件权限为 `600`（仅本人可读写）: `chmod 600 ~/.config/daily-report/config.json`

### 阶段 1: 环境检查

1. 读取 `~/.config/daily-report/config.json`，不存在则转入阶段 0
2. 检查 lark-cli 是否可用: `which lark-cli`
   - 不可用: **阻断流程**，按阶段 0-A 步骤 1-2 引导安装
3. 检查 lark-cli 配置状态: `lark-cli auth status 2>&1`
   - 返回 `"not configured"` 错误（exit code 2）: 自动转入阶段 0-A 步骤 3
   - 返回正常状态: 继续
4. 验证飞书权限可用: 执行 `lark-cli im chats list --page-size 1 --format json`
   - 成功: 继续
   - 返回 `missing_scope` 错误: 从错误信息提取修复命令执行，按「浏览器打开铁律」处理授权 URL
   - 禁止请求需要管理员审批的 scope
5. 验证内控 Token 有效性: 用 `curl` 调用用户信息接口
   - 接口: `GET {baseUrl}{apiPrefix}/system/auth/get-permission-info`
   - Header: `Authorization: {token}`, `tenant-id: {tenantId}`
   - 成功: HTTP 200 且返回用户信息（同时刷新 config 中的 userId/deptId）
   - 失败: Token 已过期，**自动重新登录**（用 config 中保存的凭据，流程同阶段 0-B 步骤 3-5），全程自动无需用户干预

### 阶段 2: 数据采集

确定日期范围:

- 默认: 当天 (若当天是工作日) 或本周所有工作日
- `--date YYYY-MM-DD`: 指定单天
- `--range START~END`: 指定日期范围 (如 `2026-03-24~2026-03-28`)
- **自然语言**: 用户可在 `/daily-report` 后直接用自然语言描述日期范围，自动解析为具体日期:
  - "今天" / "今日" → 当天
  - "昨天" → 昨天
  - "本周" / "这周" → 本周一至今天（或本周五，取较早者）
  - "上周" → 上周一至上周五
  - "本月" / "这个月" → 本月 1 日至今天
  - "上月" / "上个月" → 上月 1 日至上月最后一天
  - 其他自然语言描述 → 智能解析为对应日期范围
- 自动排除周末 (周六、周日)

**以下采集任务相互独立，使用 Agent 工具并行调度以最大化效率:**

> **并行策略**: 将 Git 采集和飞书采集分别派发给 2 个 sub-Agent，同时用 3 个并行 Bash tool calls 执行 3 个简单 API 查询。5 路任务在同一条消息中同时发出。

**Agent 1 — Git 提交记录采集**

- 遍历 `config.repos` 中每个仓库路径
- 执行: `git -C {repo} log --author="{gitAuthor}" --after="{startDate}" --before="{endDate+1day}" --format="%H|%ad|%s" --date=format:"%Y-%m-%d"`
- 按日期聚合提交，提取 commit message 摘要
- `gitAuthor` 支持 `|` 分隔的多个别名

**Agent 2 — 飞书工作记录采集**

采集三类飞书数据（若某项 scope 不足则跳过，不阻断流程）:

1. **群聊消息**（核心数据源）:
   - 获取群聊列表: `lark-cli im chats list --page-all --format json`
   - 使用跨群搜索拉取自己发送的消息（高效，一次性获取所有群的消息）:
     ```bash
     lark-cli im +messages-search --query "" \
       --sender {larkOpenId} \
       --start "{startDate}T00:00:00+08:00" \
       --end "{endDate}T23:59:59+08:00" \
       --page-all --format json
     ```
   - 若 `+messages-search` 不可用，回退到按群逐个拉取:
     ```bash
     lark-cli im +chat-messages-list --chat-id {chat_id} \
       --start "{startDate}" --end "{endDate}" \
       --page-size 50 --format json
     ```
     然后用 `config.larkOpenId` 过滤 `sender.id` 只保留自己的消息
   - **消息结构**: `content` 在**顶层**，正确取法: `message.content`。**严禁**使用 `message.body.content`

2. **日历日程**（补充数据源，scope 不足则跳过）:
   ```bash
   lark-cli calendar +agenda --start {startDate} --end {endDate} --format json
   ```

3. **文档活动**（补充数据源，scope 不足则跳过）:
   ```bash
   lark-cli docs +search --query "" --format json
   ```

**Bash 并行调用 3 — 事项分类列表**

- 调用: `GET {baseUrl}{apiPrefix}/pm/work-hour-matter/list?deptId={deptId}`
- Header: `Authorization: {token}`, `tenant-id: {tenantId}`
- 返回当前部门下的事项列表 (id + name)，用于匹配 matterId

**Bash 并行调用 4 — 部门列表**（辅助上下文）

- 调用: `GET {baseUrl}{apiPrefix}/system/dept/simple-list`
- Header: `Authorization: {token}`, `tenant-id: {tenantId}`

**Bash 并行调用 5 — 医院/项目组别**（辅助上下文）

- 调用: `POST {baseUrl}{apiPrefix}/pm/fcs/product-category/list-exclude-integrated`
- Header: `Authorization: {token}`, `tenant-id: {tenantId}`, `Content-Type: application/json`
- Body: `{"pageSize":9999,"pageNo":1,"name":"","parentId":0}`

### 阶段 2.5: 数据自检

数据采集完成后，**必须**执行自检，向用户展示自检报告:

```
数据采集自检报告:
- 群消息: 扫描 N 个群，获取 M 条本人消息 [OK/WARN]
- Git 提交: N 个仓库，共 M 条提交 [OK/WARN]
- 日历日程: N 条会议/日程 [OK/跳过(权限不足)]
- 文档活动: N 篇近期文档 [OK/跳过(权限不足)]
```

**自检规则**:
- 群消息或 Git 提交**任一为 0**: 使用 AskUserQuestion 警告并询问是否继续（选项: "继续生成" / "终止流程"）
- 日历、文档数据为补充源，scope 不足时静默跳过，不阻断
- 禁止请求需要管理员审批的 scope，仅使用用户自助授权的权限

### 阶段 3: 日报生成

按工作日逐天生成日报条目:

1. **内容合成**: 将 git 提交 + 飞书消息 + 日历日程 + 文档活动合并，按项目/主题归类
2. **分类匹配**: 根据内容关键词自动匹配 matterId
   - 含 "开发"/"实现"/"功能" → 需求开发
   - 含 "修复"/"bug"/"fix" → 问题修复
   - 含 "重构"/"优化"/"refactor" → 代码重构
   - 含 "文档"/"doc" → 文档编写
   - 含 "会议"/"沟通"/"讨论" → 会议沟通
   - 无法匹配 → 使用默认分类（需求开发）
3. **工时分配**: 每天总计 8h，按条目数等比分配
   - 算法: `raw = 8 / N`，每条向下取整到 0.5h（`floor(raw * 2) / 2`，最小 0.5h）
   - 余量 `remainder = 8 - sum(各条)`，从第一条开始每条补 0.5h 直到分完
4. **展示审核**: 以表格形式逐天列出（使用单线框 ┌─┬┐│├─┼┤│└─┴┘ 绘制，严格对齐）:

   示例格式（输出时必须重新计算对齐）:

   📅 2026-03-28 (周五)
   | 分类 | 内容 | 工时 |
   | 需求开发 | 实现用户认证模块 | 4.0h |
   | 问题修复 | 修复登录超时问题 | 2.0h |

5. **交互确认**: 展示完**所有日期**的日报表格后，使用 **AskUserQuestion** 工具弹出确认面板:

   问题: "以上日报内容已生成，请确认操作:"
   标题: "日报确认"
   选项:
   - **确认提交** (Recommended): 描述: "内容无误，直接进入阶段 4 批量提交"
   - **修改内容**: 描述: "请在"其他"中说明需要修改的条目（如调整分类、工时、描述）"
   - **补充条目**: 描述: "请在"其他"中补充遗漏的工作内容"
   - **取消**: 描述: "终止流程，不提交任何日报"

   - 用户选择**修改内容**或**补充条目**: 根据备注修改后，重新展示表格并再次弹出确认面板（循环直到用户选择确认或取消）
   - 用户选择**取消**: 立即终止流程，输出"已取消日报提交"

### 阶段 4: 批量提交

用户**确认提交**后才执行:

1. **检查已填日期**: 调用查询接口检查每个目标日期是否已有日报
   - 接口: `GET {baseUrl}{apiPrefix}/pm/staff-work-time-record/page?userId={userId}&startDate={date}&endDate={date}`
   - Header: `Authorization: {token}`, `tenant-id: {tenantId}`
   - 已有记录的日期自动跳过，输出提示

2. **按天提交**: 对每个未填日期，将该天所有条目打包为一次请求
   - 接口: `POST {baseUrl}{apiPrefix}/pm/staff-work-time-record/create`
   - Header: `Authorization: {token}`, `tenant-id: {tenantId}`, `Content-Type: application/json`
   - Body（**一天一次请求，workList 包含该天所有条目**）:

     ```json
     {
       "userId": 194,
       "deptId": 125,
       "recordDate": "2026-03-28",
       "workList": [
         {
           "productItemId": 29,
           "matterId": 28,
           "matterName": "代码维护",
           "matter": "代码维护",
           "workHours": 4.0,
           "remark": "实现用户认证模块"
         }
       ]
     }
     ```

   - `workList` 各字段说明:
     - `productItemId`: 项目 ID（从医院/项目组别列表获取）
     - `matterId`: 事项分类 ID（从事项分类列表获取）
     - `matterName`/`matter`: 事项分类名称
     - `workHours`: 该条目工时
     - `remark`: 具体工作内容描述

3. **结果汇总**: 输出提交结果

   ```
   日报提交完成
   - 2026-03-24: 3 条已提交
   - 2026-03-25: 2 条已提交
   - 2026-03-26: (已跳过，此前已填写)
   - 2026-03-27: 3 条已提交
   - 2026-03-28: 2 条已提交
   ```

## 注意事项

- 内控 API 调用使用 `curl` 命令执行
- 飞书 API 调用通过 lark-cli skill 执行，正确命令参考:
  - 群列表: `lark-cli im chats list --page-all --format json`
  - 消息搜索: `lark-cli im +messages-search --query "" --sender {openId} --start "..." --end "..." --page-all`
  - 按群拉消息: `lark-cli im +chat-messages-list --chat-id {id} --start "..." --end "..."`
  - 用户信息: `lark-cli contact +get-user`
  - 日历日程: `lark-cli calendar +agenda --start ... --end ...`
  - 文档搜索: `lark-cli docs +search --query "..."`
- 日报内容使用中文，简洁描述工作内容
- 遇到 API 错误时输出完整错误信息，不静默忽略
