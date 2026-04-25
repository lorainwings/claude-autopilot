# Adapter: MUI / Material UI(React)

## 1. Token 入口

唯一推荐:`createTheme` + `<ThemeProvider>`。

```tsx
import { createTheme, ThemeProvider } from '@mui/material/styles'

const theme = createTheme({
  palette: {
    primary: { main: '#FF6A00' },
    secondary: { main: '#0066FF' },
    mode: 'light', // 或 'dark'
  },
  typography: {
    fontFamily: 'PingFang SC, ...',
    button: { textTransform: 'none' }, // MUI 默认全大写,移动端常关
  },
  shape: { borderRadius: 8 },
  components: {
    MuiButton: {
      styleOverrides: {
        root: { borderRadius: 8, height: 36 },
      },
    },
  },
})

<ThemeProvider theme={theme}>
  <CssBaseline />
  <App />
</ThemeProvider>
```

## 2. 已知默认值落差

| 组件 | MUI 默认 | Figma 习惯值参考 | Override 入口 |
| --- | --- | --- | --- |
| `Button` 圆角 | 4px | 6 / 8 / round | `theme.shape.borderRadius` |
| `Button` 文本 | 全大写 `TEXT-TRANSFORM: uppercase` | 项目多保留原样 | `typography.button.textTransform: 'none'` |
| `Button` 高度 | 36/42/48 三档 | Figma 常自定义 | `components.MuiButton.styleOverrides.root.height` |
| `TextField` variant | outlined | 项目可能用 standard / filled | `<TextField variant="..."/>` |
| `Dialog` 遮罩 | `rgba(0,0,0,0.5)` | 项目可能更深 | `components.MuiBackdrop.styleOverrides.root` |
| 主题色 | MUI 蓝(#1976d2) | 品牌色 | `palette.primary.main` |

## 3. 样式落地选择

MUI 支持两种样式 API,**只能选一**避免双轨:

- **`sx` prop**:就近样式,适合一次性微调
- **`styled()` API**:复用样式,适合组件级
- **不要**用 v4 的 `makeStyles` / JSS(已废弃)

## 4. 组件复用映射

| Figma 类型 | MUI 组件 |
| --- | --- |
| 按钮 | `Button` 的 `variant=contained/outlined/text` |
| 输入框 | `TextField` |
| 对话框 | `Dialog` / `Drawer` |
| 表格 | `Table` 或 `DataGrid`(高级) |
| 选择器 | `Autocomplete` / `Select` |
| 通知 | `Snackbar` + `Alert` |

## 5. 反模式

| 反模式 | 正解 |
| --- | --- |
| 在 root 用 `!important` 强压样式 | 走 `theme.components.MuiXxx.styleOverrides` |
| 同一组件混用 `sx` + `styled` + `className` | 选一种 |
| 忘记 `<CssBaseline />` 导致默认样式漂移 | 一定挂载 |
| 用 v4 makeStyles | 升级到 styled / sx |
