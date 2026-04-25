# 阶段 3 — 像素 diff 协议(探测优先)

## 1. 引擎选择决策树

**禁止**写死引擎。preflight 输出中的 capability 决定本阶段走哪条路:

```
preflight.ready 含 playwright?
  ├─ Y → 用 Playwright `toHaveScreenshot`(自带 baseline 管理 + 跨平台抗锯齿处理)  [首选]
  └─ N → preflight.ready 含 pixelmatch?
          ├─ Y → 用内置 `references/scripts/visual-diff.mjs`(pixelmatch + pngjs)
          └─ N → 走 odiff(若 ready 含 odiff)
                  └─ N → blocking,回 preflight 修复
```

**何时强制 odiff**:`docs/figma-handoff-review.md` 中标注"高敏视觉(品牌主页/跨端 hero)"时,即便 Playwright 可用也强制叠加 odiff 二次校验(odiff 抗锯齿更稳)。

## 2. 三图协议(引擎无关)

每个状态产出三张图,落到统一目录(默认 `docs/visual-diff/{state}/`):

| 文件 | 来源 |
| --- | --- |
| `figma.png` | 阶段 0 的 `golden.png` 拷贝 |
| `local.png` | 本地 dev server 渲染后的截图 |
| `diff.png` | 引擎输出的可视化差异图 |

## 3. 截图参数(项目级固化)

由项目 CLAUDE.md / SKILL 调用方指定,**禁止每次手填**。常见组合:

| 项目类型 | viewport | DPR | 等待策略 |
| --- | --- | --- | --- |
| 移动端 H5(375 设计稿) | 375 × 812 | 2 | networkidle + 关闭动画 |
| 移动端 H5(750 设计稿) | 750 × 1624 | 1 | 同上 |
| PC 1280 设计稿 | 1280 × 800 | 1 | networkidle |
| PC 1440 设计稿 | 1440 × 900 | 2 | networkidle |

**关闭动画**:截图前注入样式禁用 `transition` 与 `animation`,避免抖动伪差异。Playwright 用 `animations: 'disabled'` 内置开关。

## 4. 阻断指标

| 指标 | 阈值 | 不通过动作 |
| --- | --- | --- |
| 总 diff 像素比 | **≤ 0.5%** | 回阶段 2 修复 |
| 关键 token 零偏差(品牌色 / 主字号 / 主圆角) | 必须 | 回阶段 1 校验 token 映射 |
| 图标位置偏差 | ≤ 2px | 回阶段 2 |
| N 个目标状态全部通过 | 必须 | 任一 Fail 阻断阶段 4 |
| 暗色 / 多语言 mode 状态(若存在) | 全部独立通过 | Figma MCP 拿不到 mode 时,改用阶段 0 双截图(亮/暗 各自 golden.png) |

## 5. 容差白名单

以下不计入 diff(可在引擎 ignore mask 中配置):

- 滚动条、光标
- 时间/日期文本(若设计稿用占位)
- 字体抗锯齿 1px 漂移(由 `threshold` 参数控制,推荐 0.1)

| 引擎 | mask 配置入口 |
| --- | --- |
| Playwright | `mask: [page.locator('.scrollbar')]` |
| pixelmatch | 内置脚本 `--mask x,y,w,h`,可重复或用逗号连续传多组 |
| odiff | `--diff-mask` flag |

## 6. 失败回路

diff 超阈值时**禁止**直接降阈值或跳过状态,必须按以下顺序排查:

1. token 映射表是否 100% 覆盖(回阶段 1)
2. 是否有 Tailwind 残留 / 绝对定位 / emoji 替代(回阶段 2 R1/R2/R6)
3. 框架 adapter 是否选错(React 项目误用 Vue adapter 等)
4. 组件库 adapter 默认值是否 override(回 `lib-*.md`)
5. 切图是否应该改为代码 / 反之(回 `component-policy.md`)
6. Figma 截图与本地视口尺寸是否一致

只有这 6 步都核对完且通过仍超阈值,才允许人工 review 后写入"已知差异豁免清单"(`docs/figma-handoff-review.md`)。

## 7. 引擎参考(非模板,仅说明 API 形态)

### Playwright(首选)

```ts
await expect(page).toHaveScreenshot('default.png', {
  maxDiffPixelRatio: 0.005,
  animations: 'disabled',
  mask: [page.locator('[data-testid="timestamp"]')],
})
```

baseline 由 Playwright `--update-snapshots` 一次性写入(用阶段 0 的 `golden.png`)。

### pixelmatch + pngjs

当 Playwright 不可用但 `pixelmatch` ready 时,使用内置兜底脚本,不要再让项目自行临时封装:

```bash
node plugins/figma-handoff/skills/figma-handoff/references/scripts/visual-diff.mjs \
  --project-root . \
  --figma docs/visual-diff/default/figma.png \
  --local docs/visual-diff/default/local.png \
  --diff docs/visual-diff/default/diff.png \
  --threshold 0.1 \
  --max-diff-ratio 0.005 \
  > docs/visual-diff/default/diff-report.json
```

有白名单区域时传 `--mask x,y,w,h`;可重复,也可在一个参数里按 4 个数字一组连续传入:

```bash
node plugins/figma-handoff/skills/figma-handoff/references/scripts/visual-diff.mjs \
  --project-root . \
  --figma docs/visual-diff/default/figma.png \
  --local docs/visual-diff/default/local.png \
  --diff docs/visual-diff/default/diff.png \
  --threshold 0.1 \
  --max-diff-ratio 0.005 \
  --mask 0,0,24,24 \
  --mask 320,0,55,20
```

脚本会读取 `figma.png` / `local.png`,生成 `diff.png`,并向 stdout 输出 JSON;正式交付时应重定向为 `diff-report.json`。exit 0 表示通过,exit 1 表示失败或阻断错误。默认阈值为 `--threshold 0.1` 与 `--max-diff-ratio 0.005`。Figma/local 尺寸不一致会判定失败,但仍会生成 padding 后的 diff 图用于排查视口问题。

依赖必须由目标项目安装;脚本默认从当前工作目录解析依赖,跨仓库调用时传 `--project-root <target-project>`。缺失时脚本会在 JSON 中返回安装命令:

```bash
npm install -D pixelmatch pngjs
```

### odiff(高敏)

```bash
odiff figma.png local.png diff.png --threshold=0.01 --antialiasing
```
