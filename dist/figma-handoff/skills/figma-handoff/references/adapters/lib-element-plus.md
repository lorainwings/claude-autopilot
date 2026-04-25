# vendor: Element Plus(PC 端)

## 1. 已知默认值落差

| 组件 | Element Plus 默认 | Figma 习惯值参考 | Override 入口 |
| --- | --- | --- | --- |
| `el-button` 圆角 | 4px | 6 / 8 / round | `--el-border-radius-base` 或 `--el-button-border-radius` |
| `el-button` 默认 size | default(40px 高) | Figma 多为 32 / 36 / 44 | `size` prop 或 `--el-component-size` |
| `el-input` 边框色 | `--el-border-color` | 设计稿常用更浅或品牌色 | `--el-border-color` / `--el-input-border-color` |
| `el-dialog` 遮罩 | `rgba(0,0,0,0.5)` | 项目可能更深 | `--el-overlay-color` |
| `el-table` 行高 | 48px | Figma 常用 40 / 56 | `--el-table-row-hover-bg-color` 等 |
| `el-tag` 圆角 | 4px | 多为 round / 2 | `--el-tag-border-radius` |
| `el-message` 持续时间 | 3000ms | 项目可能 2000 | `duration` prop |
| 主题色 | Element 蓝(#409EFF) | 品牌色 | SCSS 变量覆盖 + `--el-color-primary` |

## 2. 主题入口

两种方式,**只能选一**避免双轨:

- **CSS Variable**(运行时主题切换):`--el-color-primary` 等
- **SCSS 变量**(编译时定制):`@use "element-plus/theme-chalk/src/index.scss" with (...)`

推荐:有主题切换需求 → CSS Variable;固定主题 → SCSS。

## 3. SFC Traceback 注释模板

同 `vendor-vant.md` § 4。

## 4. 切图协作

PC 端同样禁止用代码复刻 Figma 复杂渐变 / 模糊背景。Hero 区、品牌图形、复杂 illustration 一律切图。

## 5. 已知反模式

- 主题色用 `:root { --el-color-primary: ... }` 覆盖,但忘了改 light/dark 衍生值,hover/active 失真
- 用 `:deep()` 覆盖 `el-table` 行高,忽略 `--el-table-row-padding`
- 把 Figma 中的 outline 按钮硬写成 `<button>` 而不复用 `el-button plain`
