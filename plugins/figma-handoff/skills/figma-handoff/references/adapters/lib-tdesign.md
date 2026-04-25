# Adapter: TDesign(Vue 3 / React,腾讯)

## 1. Token 入口

CSS Variable 体系(推荐)或 SCSS 变量。

```css
:root {
  --td-brand-color: #FF6A00;
  --td-brand-color-hover: #E65A00;
  --td-radius-default: 8px;
  --td-font-family: PingFang SC, ...;
}
```

或 ConfigProvider:

```vue
<t-config-provider :global-config="{ classPrefix: 'mt' }">
  <app />
</t-config-provider>
```

## 2. 已知默认值落差

| 组件 | TDesign 默认 | Figma 习惯值 | Override |
| --- | --- | --- | --- |
| `t-button` 圆角 | 3px | 4 / 8 / round | `--td-radius-default` |
| `t-button` 高度 | small=24 medium=32 large=40 | Figma 多 36 | `--td-comp-size-m` |
| 主题色 | TDesign 蓝(#0052D9) | 品牌色 | `--td-brand-color` 全色阶 |

## 3. 反模式

| 反模式 | 正解 |
| --- | --- |
| 主题色只改一档 | 全色阶(1-10)走 token |
| `.t-button { ... }` 全局压样式 | 走 CSS Variable |

## 4. 组件映射(简表)

| Figma | TDesign |
| --- | --- |
| 按钮 | `t-button` / `Button` |
| 输入 | `t-input` / `Input` |
| 对话框 | `t-dialog` / `Dialog` |
| 表格 | `t-table` / `Table` |
