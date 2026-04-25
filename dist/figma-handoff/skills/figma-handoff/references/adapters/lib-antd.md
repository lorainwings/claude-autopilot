# Adapter: Ant Design(React,PC 端)

## 1. Token 入口

唯一推荐:`<ConfigProvider theme={...}>` 全局配置。**禁止**散落 `:global()` 覆盖 `.ant-*` 类名。

```tsx
import { ConfigProvider, theme } from 'antd'

<ConfigProvider
  theme={{
    token: {
      colorPrimary: '#FF6A00',
      borderRadius: 8,
      fontFamily: 'PingFang SC, ...',
    },
    components: {
      Button: { borderRadius: 8, controlHeight: 36 },
      Input: { borderRadius: 6 },
    },
    algorithm: theme.defaultAlgorithm, // 或 darkAlgorithm
  }}
>
  <App />
</ConfigProvider>
```

## 2. 已知默认值落差

| 组件 | AntD 默认 | Figma 习惯值参考 | Override 入口 |
| --- | --- | --- | --- |
| `Button` 圆角 | 6px | 4 / 8 / round | `token.borderRadius` 或 `components.Button.borderRadius` |
| `Button` 高度 | 32px | 36 / 40 / 44 | `components.Button.controlHeight` |
| `Input` 边框色 | 灰 | 设计稿常用更浅或品牌色 | `token.colorBorder` |
| `Modal` 遮罩 | `rgba(0,0,0,0.45)` | 项目可能更深 | `token.colorBgMask` |
| `Table` 行高 | 56px | Figma 常用 48 / 64 | `components.Table.cellPaddingBlock` |
| 主题色 | AntD 蓝(#1677FF) | 品牌色 | `token.colorPrimary` |

## 3. 组件复用映射

| Figma 类型 | AntD 组件 |
| --- | --- |
| 按钮(实心/虚线/文字) | `Button` 的 `type=primary/default/link/text` |
| 输入框 + label | `Form.Item` + `Input` |
| 对话框 | `Modal` / `Drawer` |
| 表格 | `Table` |
| 选择器 | `Select` / `Cascader` / `TreeSelect` |
| 通知 | `notification` / `message` |

## 4. 反模式

| 反模式 | 正解 |
| --- | --- |
| 用 `.ant-btn { border-radius: 8px }` 全局覆盖 | 走 `ConfigProvider` token |
| 同时维护多个 `ConfigProvider` 互相覆盖 | 单一根 Provider + 局部 override 子 Provider |
| 用 v4 写法(less variable)在 v5 项目 | v5 起 CSS-in-JS,所有 token 走 JS 对象 |
| 自己实现 `<Button>` 而项目已装 antd | 复用 `Button` |
