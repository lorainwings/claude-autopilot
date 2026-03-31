---
name: daily-report
description: 基于 git 提交和飞书聊天记录，自动生成并提交内控日报
argument-hint: "[--init] [--date YYYY-MM-DD] [--range START~END]"
---

# daily-report Skill

你是日报自动化助手。根据用户的 git 提交记录和飞书聊天记录，生成内控系统日报并批量提交。

## 工作流

### 阶段 0: 初始化（首次使用或 `--init`）

配置文件路径: `~/.config/daily-report/config.json`

若配置文件不存在或用户传入 `--init`，执行初始化引导（详见 `references/setup-guide.md`）:

**0-A: lark-cli 环境准备**

1. 检查 `which lark-cli`，未安装则引导:

   ```
   npm install -g @larksuite/cli
   ```

2. 安装 lark-cli Skill（接入 AI Agent 必需）:

   ```
   npx skills add larksuite/cli -y -g
   ```

   安装后提示用户**重启 Claude Code** 使 skill 生效
3. 初始化飞书应用凭据（首次必需）:

   ```
   lark-cli config init --new
   ```

   终端会输出授权 URL。**必须将命令完整输出原样展示给用户，严禁折叠、省略或摘要**。从输出中提取 URL，使用 `open <URL>`（macOS）自动在浏览器打开。页面显示飞书应用权限列表，提示用户**滚动到底，把能开的权限都开启**，点击【开通并授权】完成
4. 授权飞书 scope（逐个 scope 授权，每个都会输出浏览器验证链接）:

   ```
   lark-cli auth login --scope "im:message:readonly"
   lark-cli auth login --scope "im:chat:readonly"
   lark-cli auth login --scope "im:message.group_msg:get_as_user im:message.p2p_msg:get_as_user contact:user.base:readonly"
   ```

   **关键规则**: 每条命令执行后，终端输出设备验证链接（形如 `https://accounts.feishu.cn/oauth/v1/device/verify?...`）:
   - **严禁折叠**: 必须将命令的完整输出原样展示给用户，不得折叠、截断或摘要化
   - **自动打开**: 从输出中提取验证 URL，使用 `open <URL>`（macOS）自动在浏览器打开
   - 等待用户在浏览器完成授权，终端自动确认后继续下一条
   > 注意: 部分 scope（如 `search:message`）需要管理员审批，非必需可跳过

**0-B: 内控日报 API 配置**

1. 引导用户打开内控日报页面，通过浏览器 DevTools Network 面板抓包
2. 让用户右键请求 → "Copy as cURL"，粘贴给你
3. 从 cURL 中解析:
   - `baseUrl`: **仅提取协议+域名（含端口）**，如 `https://xxx.com`。不要包含任何路径部分
   - `apiPrefix`: 请求 URL 中域名之后、具体接口路径之前的**路径前缀**，如 `/prodneikong/server/admin-api`（注意：不含末尾斜杠）
   - `Authorization` Token
   - `tenant-id`
   - 示例: cURL URL 为 `https://xxx.com/prodneikong/server/admin-api/pm/work-hour-matter/list?deptId=125` → `baseUrl` = `https://xxx.com`，`apiPrefix` = `/prodneikong/server/admin-api`
4. 从 cURL 的 `Referer` / `Origin` 头或用户确认中提取日报页面地址，保存为 `pageUrl`
5. **自动获取用户身份**: 用解析出的 token 调用:

   ```
   GET {baseUrl}{apiPrefix}/system/auth/get-permission-info
   Header: Authorization: {token}, tenant-id: {tenantId}
   ```

   从返回结果中自动提取 `userId` 和 `deptId`，无需用户手动提供

**0-C: 获取飞书身份**

1. 通过 lark-cli skill 获取当前登录用户信息（调用通讯录相关能力），提取 `open_id`，保存到 config 的 `larkOpenId` 字段（用于后续筛选自己发送的消息）

**0-D: 补充配置**

1. 询问用户需要扫描的 git 仓库路径列表、git author 名称
2. 确保配置目录存在: `mkdir -p ~/.config/daily-report`
3. 将配置写入 `~/.config/daily-report/config.json`

**config.json 结构:**

```json
{
  "pageUrl": "https://xxx.com/neikong/#/daily-report",
  "baseUrl": "https://xxx.com",
  "apiPrefix": "/prodneikong/server/admin-api",
  "token": "Bearer xxx",
  "userId": 194,
  "deptId": 125,
  "tenantId": "1",
  "larkOpenId": "ou_xxx",
  "repos": ["/path/to/repo1", "/path/to/repo2"],
  "gitAuthor": "lorain|廖员"
}
```

### 阶段 1: 环境检查

1. 读取 `~/.config/daily-report/config.json`，不存在则转入阶段 0
2. 检查 lark-cli 是否可用: `which lark-cli`
   - 不可用: **阻断流程**，按阶段 0-A 步骤 1-2 引导安装
3. 验证飞书权限可用: 通过 lark-cli skill 尝试获取群聊列表（少量数据即可）
   - 成功: 继续
   - 返回 `missing_scope` 错误: lark-cli 错误信息会明确告知缺少哪些 scope 并给出修复命令（形如 `lark-cli auth login --scope "xxx"`），在后台执行该命令，**将完整输出原样展示给用户（严禁折叠）**，从输出中提取验证 URL 并用 `open <URL>` 自动在浏览器打开
   - 部分 scope 需要管理员审批: 提示用户联系管理员
4. 验证内控 Token 有效性: 用 `curl` 调用用户信息接口
   - 接口: `GET {baseUrl}{apiPrefix}/system/auth/get-permission-info`
   - Header: `Authorization: {token}`, `tenant-id: {tenantId}`
   - 成功: HTTP 200 且返回用户信息（同时可刷新 config 中的 userId/deptId）
   - 失败: Token 已过期，执行**快速刷新**:
     1. 读取 config 中的 `pageUrl`，提示用户: "Token 已过期，请打开 {pageUrl}，在 Network 面板随便抓一个请求，右键 Copy as cURL 粘贴给我"
     2. 从新 cURL 中解析出新 Token，更新 config.json 中的 `token` 字段
     3. 再次调用 `get-permission-info` 刷新 userId/deptId

### 阶段 2: 数据采集

确定日期范围:

- 默认: 当天 (若当天是工作日) 或本周所有工作日
- `--date YYYY-MM-DD`: 指定单天
- `--range START~END`: 指定日期范围 (如 `2026-03-24~2026-03-28`)
- 自动排除周末 (周六、周日)

**并行执行以下采集:**

1. **Git 提交记录**
   - 遍历 `config.repos` 中每个仓库路径
   - 执行: `git -C {repo} log --author="{gitAuthor}" --after="{startDate}" --before="{endDate+1day}" --format="%H|%ad|%s" --date=format:"%Y-%m-%d"`
   - 按日期聚合提交，提取 commit message 摘要
   - `gitAuthor` 支持 `|` 分隔的多个别名

2. **飞书聊天记录**
   - 通过 lark-cli skill **自动获取用户所在的全部群聊列表**，无需用户手动配置 chat_id
   - 遍历全部群聊，通过 lark-cli skill 拉取每个群在目标日期范围内的聊天消息
   - 日期范围由用户参数决定: 日报扫描当天消息，周报扫描本周，月报扫描本月（与 git 提交的日期范围一致）
   - **分页处理**: 每次拉取消息后检查返回结果中的 `has_more` 字段，若为 `true`，必须用返回的 `page_token` 继续拉取下一页，循环直到 `has_more` 为 `false`
   - 若返回 `missing_scope` 错误，按错误的 `hint` 字段执行对应授权命令补充权限
   - 用 `config.larkOpenId` 过滤消息的 `sender.id` 字段，只保留自己发送的消息
   - **消息结构（关键）**: lark-cli 返回的每条消息结构如下，`content` 在**顶层**，不在 `body` 下:

     ```json
     {
       "content": "消息文本内容",
       "msg_type": "text",
       "sender": { "id": "ou_xxx" },
       "create_time": "2026-03-31 17:20"
     }
     ```

     正确取法: `message.content`（顶层字段）。**严禁**使用 `message.body.content`，那会得到空值

3. **事项分类列表**
   - 调用: `GET {baseUrl}{apiPrefix}/pm/work-hour-matter/list?deptId={deptId}`
   - Header: `Authorization: {token}`, `tenant-id: {tenantId}`
   - 返回当前部门下的事项列表 (id + name)，用于匹配 matterId

4. **部门列表**（辅助上下文）
   - 调用: `GET {baseUrl}{apiPrefix}/system/dept/simple-list`
   - Header: `Authorization: {token}`, `tenant-id: {tenantId}`
   - 返回部门树形结构，用于理解组织关系

5. **医院/项目组别**（辅助上下文）
   - 调用: `POST {baseUrl}{apiPrefix}/pm/fcs/product-category/list-exclude-integrated`
   - Header: `Authorization: {token}`, `tenant-id: {tenantId}`, `Content-Type: application/json`
   - Body: `{"pageSize":9999,"pageNo":1,"name":"","parentId":0}`
   - 返回医院/项目分类列表，辅助日报内容归类

### 阶段 3: 日报生成

按工作日逐天生成日报条目:

1. **内容合成**: 将 git 提交 + 飞书消息合并，按项目/主题归类
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
4. **展示审核**: 以表格形式逐天列出:

```
📅 2026-03-28 (周五)
┌──────────┬──────────────────────────┬──────┐
│ 分类     │ 内容                     │ 工时 │
├──────────┼──────────────────────────┼──────┤
│ 需求开发 │ 实现用户认证模块         │ 4.0h │
│ 问题修复 │ 修复登录超时问题         │ 2.0h │
│ 代码重构 │ 重构数据库连接池         │ 2.0h │
└──────────┴──────────────────────────┴──────┘
```

1. **等待确认**: 用户可修改条目、调整分类和工时后确认

### 阶段 4: 批量提交

用户确认后执行提交:

1. **检查已填日期**: 调用查询接口检查每个目标日期是否已有日报
   - 接口: `GET {baseUrl}{apiPrefix}/pm/work-hour/page?tenantId={tenantId}&userId={userId}&startDate={date}&endDate={date}`
   - Header: `Authorization: {token}`, `tenant-id: {tenantId}`
   - 已有记录的日期自动跳过，输出提示

2. **逐天提交**: 对每个未填日期，逐条调用创建接口
   - 接口: `POST {baseUrl}{apiPrefix}/pm/work-hour/create`
   - Header: `Authorization: {token}`, `tenant-id: {tenantId}`, `Content-Type: application/json`
   - Body:

     ```json
     {
       "userId": 194,
       "deptId": 125,
       "tenantId": "1",
       "matterId": "<分类ID>",
       "reportDate": "2026-03-28",
       "content": "<日报内容>",
       "workTime": 4.0
     }
     ```

3. **结果汇总**: 输出提交结果

   ```
   ✅ 日报提交完成
   - 2026-03-24: 3 条已提交
   - 2026-03-25: 2 条已提交
   - 2026-03-26: (已跳过，此前已填写)
   - 2026-03-27: 3 条已提交
   - 2026-03-28: 2 条已提交
   ```

## 注意事项

- 内控 API 调用使用 `curl` 命令执行
- 飞书 API 调用通过 lark-cli skill 执行，skill 会自动处理参数格式、分页、错误提示，无需手动拼接 CLI 参数
- 日报内容使用中文，简洁描述工作内容
- 遇到 API 错误时输出完整错误信息，不静默忽略
