# Adapter: Arco Design(Vue 3 / React)

## 1. Token 入口

### Vue3

```vue
<a-config-provider :theme="{ token: { colorPrimary: '#FF6A00', borderRadius: 8 } }">
  <app />
</a-config-provider>
```

或 CSS Variable:`--color-primary-6: #FF6A00;`

### React

```tsx
import { ConfigProvider } from '@arco-design/web-react'
<ConfigProvider componentConfig={{ Button: { type: 'primary' } }}>
  <App />
</ConfigProvider>
```

主题定制走 less 变量:`@arco-cyan-6: #FF6A00;` 或 CSS Variable。

## 2. 已知默认值落差

| 组件 | Arco 默认 | Figma 习惯值 | Override |
| --- | --- | --- | --- |
| `Button` 圆角 | 2px | 4 / 8 / round | `token.borderRadius` 或 `--border-radius-medium` |
| `Button` 高度 | 32px | 36 | `token.controlHeight` |
| 主题色 | Arco 蓝/绿 | 品牌色 | `--color-primary-6`(并需调整 1-10 全色阶) |

## 3. 反模式

| 反模式 | 正解 |
| --- | --- |
| 只改 `--color-primary-6` 不改其他色阶 | 1-10 全配,或用 Arco 主题工具生成 |
| 全局 `.arco-btn { ... }` 覆盖 | 走 ConfigProvider / less variable |

## 4. 组件映射(简表)

| Figma | Arco |
| --- | --- |
| 按钮 | `a-button` / `Button` |
| 输入 | `a-input` / `Input` |
| 对话框 | `a-modal` / `Modal` |
| 表格 | `a-table` / `Table` |
