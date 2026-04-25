# Adapter: Mantine(React)

## 1. Token 入口

`createTheme` + `<MantineProvider>`(v7+)。

```tsx
import { createTheme, MantineProvider } from '@mantine/core'

const theme = createTheme({
  primaryColor: 'brand',
  colors: {
    brand: ['#FFF1E8', '#FFE0CC', /* ... 必须 10 档 */ '#FF6A00', /* ... */],
  },
  fontFamily: 'PingFang SC, ...',
  defaultRadius: 'md',
  radius: { md: '8px' },
  components: {
    Button: {
      defaultProps: { size: 'md' },
      styles: { root: { height: 36 } },
    },
  },
})

<MantineProvider theme={theme} defaultColorScheme="light">
  <App />
</MantineProvider>
```

**注意**:Mantine 自定义颜色**必须**提供 10 档色阶(0-9),否则 hover/active 衍生色失真。Figma 提供单色时需用 `@mantine/colors-generator` 或手工生成。

## 2. 已知默认值落差

| 组件 | Mantine 默认 | Figma 习惯值 | Override |
| --- | --- | --- | --- |
| `Button` 圆角 | 4px(sm) | 6 / 8 / round | `defaultRadius` 或 `components.Button.styles.root.borderRadius` |
| `Button` 高度 | xs=30 sm=36 md=42 lg=50 xl=60 | 项目多自定义 | `components.Button.styles.root.height` |
| `TextInput` 边框色 | gray.4 | 设计稿可能更浅 | `theme.colors.gray[4]` 或 `components.Input.styles.input.borderColor` |
| `Modal` 遮罩 | `rgba(0,0,0,0.55)` | 同 | `components.Modal.styles.overlay.bg` |
| 主题色 | blue | 品牌色 | `primaryColor` + `colors.brand` |

## 3. 样式落地

Mantine 推荐顺序:

1. `theme` 全局
2. 组件 `styles={{ root: ... }}` prop
3. CSS Module(`*.module.css`)+ Mantine 提供的 `:where(...)` 选择器避免特异性
4. **避免**使用 Emotion(v6 旧方案,v7 已切换到 CSS Module)

## 4. 组件复用映射

| Figma 类型 | Mantine 组件 |
| --- | --- |
| 按钮 | `Button` + `variant=filled/light/outline/subtle/transparent` |
| 输入 | `TextInput` / `NumberInput` / `PasswordInput` |
| 对话框 | `Modal` / `Drawer` |
| 表格 | `Table`(基础)/ `mantine-react-table`(高级) |
| 通知 | `notifications.show()` |

## 5. 反模式

| 反模式 | 正解 |
| --- | --- |
| 单色定义就用 | 提供 10 档或用 `colors-generator` |
| v6 Emotion + v7 CSS Module 混用 | 升级到 v7 单轨 |
| 滥用 `styles={{...}}` 行内覆盖 | 抽到 theme |
| 自己写 `<Button>` 而项目已装 Mantine | 复用 |
