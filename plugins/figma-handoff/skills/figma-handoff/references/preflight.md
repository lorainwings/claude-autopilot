# 阶段 -1 — Preflight 能力探测协议

> SKILL 启动的**第一步**:在拉 Figma 数据之前先确认本地依赖就绪。Figma MCP 工具可用性由 Agent 工具层最终确认;shell preflight 只做本地能力探测与显式环境变量识别。

## 1. 三段式输出契约

每次 preflight 必须产出如下 JSON(默认落到 `.cache/figma-handoff/preflight.json`),供后续阶段读取与降级决策:

```json
{
  "ready": ["playwright"],
  "degraded": [
    {"capability": "figma-mcp", "reason": "shell 无法 introspect Agent 工具层; 请在 Agent 工具层确认 mcp__figma__* 可用", "fallback": "manual-tool-check"},
    {"capability": "chrome-devtools-mcp", "reason": "未在本机检测到 MCP server", "fallback": "playwright-cli"}
  ],
  "blocking": [],
  "framework": "vue",
  "componentLibrary": "element-plus",
  "packageManager": "pnpm",
  "figmaMcpMode": "unknown"
}
```

| 段位 | 语义 | 主流程行为 |
| --- | --- | --- |
| `ready` | 能力满足主路径 | 直接走标准流程 |
| `degraded` | 主路径不可由 shell 确认,但有降级或人工确认路径 | 提示用户后走 fallback,**不阻断** |
| `blocking` | 缺关键本地能力且无降级 | **abort 并输出 fix 命令**,等用户修复后重跑 |

## 2. Figma MCP 探测边界

Figma 官方 Remote MCP 与 Desktop MCP 是 Agent 工具层能力,shell 脚本无法可靠 introspect `mcp__figma__*` 工具是否已经注入。因此:

- `FIGMA_MCP_READY=1`:调用方已在 Agent 工具层确认 Figma MCP 可用,preflight 标记 `figma-mcp` 为 `ready`。
- `FIGMA_MCP_MODE=remote|desktop|local|unknown`:声明预期来源;默认 `unknown`。`remote` 表示官方远程 MCP URL,`desktop` 表示 Figma Desktop 提供的 MCP,`local` 表示本地 `figma-developer-mcp`。
- 未设置 `FIGMA_MCP_READY=1` 且未检测到本地 `figma-developer-mcp` 时,preflight 只能输出 `degraded/manual-tool-check`,**不得**把 `figma-mcp` 放入 `blocking`。
- SKILL 主线程进入阶段 0 前必须在 Agent 工具层实际确认 `mcp__figma__get_metadata`、`mcp__figma__get_variable_defs`、`mcp__figma__get_design_context`、`mcp__figma__get_screenshot` 等工具可调用。
- 若 Agent 工具层最终也没有 Figma MCP 工具,主线程才可以中止并给出注册 Remote/Desktop/local MCP 的修复命令;这个阻断不由 shell preflight 决定。

## 3. 必检能力清单

| Capability | 检测方式 | 缺失等级 | Fix / Fallback |
| --- | --- | --- | --- |
| `figma-mcp` | shell: `FIGMA_MCP_READY=1`、`FIGMA_MCP_MODE`、本地 `figma-developer-mcp`;Agent: `mcp__figma__*` 工具列表 | shell 仅 `degraded/manual-tool-check`;Agent 最终确认 | Remote: `claude mcp add figma --transport http https://mcp.figma.com/mcp`;Desktop:确认 Figma Desktop 已开启 MCP;Local: `claude mcp add figma -- npx -y figma-developer-mcp --figma-api-key=$FIGMA_TOKEN` |
| `chrome-devtools-mcp` | 工具列表中含 `mcp__chrome-devtools__take_screenshot` 或本机 server | degraded → playwright | `claude mcp add chrome-devtools -- npx -y chrome-devtools-mcp@latest` |
| `playwright` | 能从项目实际解析 `@playwright/test`/`playwright`,或 `playwright` 命令可用;仅 package.json 声明但未安装不算 ready | 与 `pixelmatch + pngjs` 都缺时 blocking | `<pm> add -D @playwright/test && npx playwright install chromium` |
| `pixelmatch + pngjs` | 两者都能从项目实际解析;仅 package.json 声明但未安装不算 ready | 与 `playwright` 都缺时 blocking | `<pm> add -D pixelmatch pngjs` |
| `visual-diff-engine` | `playwright` 或 `pixelmatch + pngjs` 至少一个可用 | **blocking** | `<pm> add -D @playwright/test && npx playwright install chromium` 或 `<pm> add -D pixelmatch pngjs sharp` |
| `sharp` | 项目依赖含 `sharp` | degraded → 跳过预处理 | `<pm> add -D sharp` |
| `odiff`(可选) | `which odiff` 或项目依赖含 `odiff-bin` | 仅高敏模式开启 | `<pm> add -D odiff-bin` |

## 4. 包管理器嗅探优先级

按 lockfile 存在顺序判定,首个命中即采用;无 lockfile 默认 npm:

```text
bun.lock          → bun / bunx
pnpm-lock.yaml    → pnpm / pnpm dlx
yarn.lock         → yarn / yarn dlx
package-lock.json → npm / npx
(none)            → npm / npx
```

`corepack` 启用时优先尊重 `package.json#packageManager`。

## 5. 框架 / 组件库探测

| 字段 | 探测顺序 |
| --- | --- |
| `framework` | ① 用户参数 `[target-stack]` ② `package.json` deps 含 `react`/`vue`/`@angular/core`/`svelte` ③ 文件后缀统计(`.tsx` vs `.vue`) |
| `componentLibrary` | ① **Code Connect 命中**(`get_code_connect_map` 非空)→ 直接采用映射库 ② `package.json` deps 显式匹配(antd/@mui/material/@chakra-ui/react/@mantine/core/vant/element-plus/naive-ui/...) ③ 用户参数 ④ fallback `tailwind`(对应 `lib-tailwind.md`) |

脚本层不能调用 Code Connect,因此 `scripts/preflight.sh` 只执行 `componentLibrary` 第 ②-④ 步;阶段 0 若 Code Connect 命中,以 Code Connect 结果覆盖 preflight 的组件库猜测。

**禁止**:在 framework 未确定时进入阶段 1。

## 6. 阻断处理范式

输出格式必须满足三件:

1. **可复制**:fix 命令独占代码块,不夹杂解释
2. **声明前置变量**:如需 `FIGMA_TOKEN`,先输出 `export FIGMA_TOKEN=...` 提示
3. **无降级即拒绝继续**:不允许"假装继续",必须等用户修复后重跑

shell preflight 的典型 blocking 只应来自本地关键能力,例如视觉 diff 引擎全部缺失:

```text
Blocking: visual-diff-engine 未就绪

请执行(任选其一):

  pnpm add -D @playwright/test
  pnpm exec playwright install chromium

  pnpm add -D pixelmatch pngjs sharp
```

Figma MCP 是例外:在 shell 层缺失时输出 `degraded/manual-tool-check`;只有 Agent 工具层实际调用失败时,主线程才输出 Figma MCP 的修复命令并中止。

## 7. 降级路径明示

当某能力进入 `degraded`,主流程必须在该阶段开头打印一行可见提示,例如:

```text
Figma MCP 无法由 shell 确认,本次将由 Agent 工具层检查 mcp__figma__* 工具可用性
```

```text
chrome-devtools MCP 未注册,本次截图改用 Playwright CLI(viewport=375×812 dpr=2)
```

避免用户误以为走的是主路径。

## 8. 执行入口

参考实现 `scripts/preflight.sh`(项目可自行重写)。SKILL 主流程在 §0 通过 Bash 调用,读取 stdout JSON 后据此分流。
