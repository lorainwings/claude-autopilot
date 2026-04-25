# vendor: Vant 4(移动端 H5)

## 1. 已知默认值落差(必须 override)

Vant 4 的部分默认值偏离 Figma 移动端常见设计习惯。下表是高频 override 入口,具体值由项目设计稿决定。

| 组件 | Vant 默认 | Figma 习惯值参考 | Override 入口 |
| --- | --- | --- | --- |
| `van-button` 圆角 | 2px | 8 / 12 / round | `--van-button-border-radius` |
| `van-popup` 遮罩透明度 | `rgba(0,0,0,0.7)` | 项目设计稿可能更浅 | `:overlay-style` 或 `--van-popup-overlay-bg` |
| `van-popup` z-index | 2000 | 多层弹窗时易冲突 | `--van-popup-z-index` |
| `van-checkbox` 选中色 | Vant 蓝 | 品牌色 | `--van-checkbox-checked-icon-color` |
| `van-tag` 圆角 / padding | 2px / 0 4px | 多为 4-8px | `--van-tag-border-radius` / `--van-tag-padding` |
| `van-cell` 默认 padding | 10px 16px | 多为 12-16px | `--van-cell-vertical-padding` / `--van-cell-horizontal-padding` |
| `:hover` 反馈 | 不生效(移动端) | 点击态 | `--van-active-color` 或 `.van-hairline--surround` |
| `van-skeleton` 行高 | 16px | 项目自定义 | `--van-skeleton-row-height` |

## 2. 主题入口

推荐使用 `van-config-provider` + CSS Variable 集中覆盖,而不是逐组件 `:deep()`。理由:

- 主题切换可一键
- 与 Figma `tokens.md` 形成单一映射点
- 避免选择器特异性混战

## 3. rem 适配陷阱

`postcss-pxtorem` 对 Vant **内联 px** 不会转换(组件库已编译产物)。两种解法:

- 用 `van-config-provider` 设 CSS Variable(推荐)
- `propList` 配置避开字体相关属性,与 `lib-flexible` 协作

## 4. SFC Traceback 注释模板

```
<!-- figma: fileKey=XXX nodeId=YYY golden=docs/figma-spec/{state}/golden.png -->
```

放在 `<template>` 之前。审查脚本可 grep 此前缀,统计节点溯源覆盖率。

## 5. 切图协作

装饰类节点(渐变背景 / 复杂插画)由 Figma 导出 SVG 或 PNG,放到项目约定的 assets 目录(如 `src/assets/imgs/<feature>/`)。**禁止** Vant 项目用代码 `linear-gradient` 复刻 Figma 多色阶混合渐变,失真率高且不可维护。

## 6. 已知反模式

- 用 `:deep(.van-button) { border-radius: 8px }` 散落覆盖,而不是改 CSS Variable
- 把 Vant 组件的 `:disabled` 样式硬覆盖成 Figma 禁用色,而不走 token
- `van-popup` 内嵌 `van-popup` 时不调 z-index,层级错乱
