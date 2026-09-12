# Mobile Agent 视觉体系规范 (DeepSeek 极简风格)

本规范定义了 `mobile_agent` 的视觉体系标准，全面采用对标 DeepSeek App 的极简设计语言：**简洁克制、内容优先**。
核心原则为**做减法**：移除渐变、高斯模糊、彩色光晕、多层阴影与大圆角，改用留白、字重与灰阶建立层级，全站只保留一个强调色。

---

## 1. 色彩规范 (Color Palette)

全站严格遵循以下语义色表，禁止在业务组件中硬编码散落色值。

| 语义 Token | 浅色 (Light) | 深色 (Dark) | 用途说明 |
| :--- | :--- | :--- | :--- |
| `canvas` | `#FFFFFF` | `#0A0A23` | 全局画布背景 |
| `surface` | `#F5F7FB` | `#1A1A3A` | 分组底色、悬停底色、卡片默认底色 |
| `surfaceHover` | `#EEF1F8` | `#22224A` | 按压底色、次级强调表面 |
| `hairline` | `#E2E7F1` | `rgba(255,255,255,.12)` | 1px 分隔线与描边边框 |
| `text` | `#1A1A1A` | `#E6E8EF` | 正文与标题主文本 |
| `textMuted` | `#6B7280` | `#A8B0C4` | 次要说明、次级图标、辅助文本 |
| `textFaint` | `#6B7280` | `#8A90A4` | 标签说明、占位符文字；须满足 WCAG 对比度 |
| `brand` | `#4D6BFE` | `#4D6BFE` | **全站唯一强调色** |
| `brandHover` | `#3A55E5` | `#5F7BFF` | 强调色悬停态 |
| `brandActive` | `#2A44CC` | `#3A55E5` | 强调色按下态 |
| `brandSoft` | `#EAEEFE` | `#1A234A` | 用户气泡底色、功能 chip 选中底色 |
| `brandFaint` | `#F3F5FE` | `#141B38` | 提示条底色、输入框聚焦外环底色 |
| `success` | `#2BA471` | `#2BA471` | 成功、已完成状态 |
| `warning` | `#F5A623` | `#F5A623` | 警告、待确认状态 |
| `danger` | `#E5484D` | `#E5484D` | 错误、破坏性操作状态 |

### 强调色使用铁律
`#4D6BFE` 只允许出现在以下四类场景，禁止用作大面积背景、正文颜色或纯装饰填充：
1. **主操作按钮** (Primary Action Button)
2. **输入框聚焦描边** (Input Focus Border)
3. **进行中状态指示点** (Running Status Dot)
4. **可点击的功能 Chip 选中态** (Selectable Functional Chip)

---

## 2. 几何圆角 (Border Radius)

圆角严格收敛为 4 档，消除过于夸张的圆润气泡感：

| Token | 新值 | 适用场景 |
| :--- | :--- | :--- |
| `radiusControl` | `8.0` | 按钮、输入框、下拉框、小控件 |
| `radiusCard` | `12.0` | 设置分组卡、提示卡、代码块容器 |
| `radiusModal` | `16.0` | 底部弹层、居中对话框、输入胶囊外壳 |
| `radiusPill` | `999.0` | Chip 标签、搜索框、胶囊微徽标 |

> **用户气泡特殊规则**：用户气泡圆角采用 `16 16 8 16`（右下收窄），彻底废弃 `radiusBubbleTail = 4` 的尖角尾巴写法。

---

## 3. 字号与字重排版 (Typography)

字号收敛为 5 档，**字重严格限定为 400 (Regular) 与 500 (Medium)**，标题层级靠字号与灰阶解决，禁止使用 600 / 700 字重。

| 用途 | 字号 / 字重 | 行高 (Height) | 备注说明 |
| :--- | :--- | :--- | :--- |
| 空态主文案 | `22 / 500` | `1.35` | 全站仅此一处使用 22px |
| 页面标题、内容小标题 | `17 / 500` | `1.40` | 顶栏标题、卡片/回答段落小标题 |
| 正文 | `15 / 400` | `1.60` | 对话正文、列表主标题 (原有 13/13.5 已全部放大) |
| 次要信息 | `13 / 400` | `1.55` | 时间戳、折叠行、状态说明、右侧值 |
| 标签 / 徽标 | `11 / 500` | `1.40` | 状态标签、分组标题、`letterSpacing: 0.04` |

- **正文字体族**：`"Inter", "PingFang SC", "Microsoft YaHei", "Noto Sans SC", sans-serif` 串联。
- **等宽代码字体族**：`"JetBrains Mono", monospace`。

---

## 4. 间距基栅 (Spacing Grid)

严格遵循 **4px 基栅**，锁定以下标准数值：
`4 / 8 / 12 / 16 / 24 / 32 / 48 / 64` (`sp1` 到 `sp16`)

- **判定口诀**：同一组内 `≤ 12px`，跨组 `≥ 24px`。
- **禁止**：任何非 4 倍数的间距 (如 5, 7, 10, 14, 18, 22 等)。

---

## 5. 结构高度与动效 (Structure & Motion)

- **结构高度**：
  - 顶栏 (TopBar)：`56px`
  - 列表行 (ListRow)：`52px`
  - 控件/按钮 (Control)：`44px`
  - 搜索框 (SearchBox)：`36px`
  - Chip 标签：`32px`
- **动效时长**：收敛为 `90ms` (`durationInstant`), `150ms` (`durationFast`), `220ms` (`durationBase`), `300ms` (`durationExpand`)。
- **缓动曲线**：全站统一 `Curves.easeOutCubic`，彻底废弃回弹感曲线 (`Curves.easeOutBack`)。
- **投影体系**：仅保留 2 级极轻量阴影：
  - 卡片级：`0 1px 2px rgba(16, 24, 40, 0.04)`
  - 浮层级：`0 8px 24px rgba(16, 24, 40, 0.08)`

---

## 6. 绝对禁用清单 (Strict Constraints)

以下视觉与实现方式在全站范围内绝对禁用，不允许任何例外：
1. ❌ **背景渐变** (Radial / Linear Gradients as background)
2. ❌ **高斯模糊** (`BackdropFilter`, `ImageFilter.blur`, `ImageFiltered`)
3. ❌ **彩色光晕与彩色投影** (Colored glow / shadows)
4. ❌ **三级以上重阴影**
5. ❌ **大于 16px 的卡片圆角** (除 Pill 外)
6. ❌ **彩色或发光图标**
7. ❌ **回弹缓动曲线** (`Curves.easeOutBack` 等)
8. ❌ **非 4 倍数间距**
9. ❌ **600 / 700 字重**
10. ❌ **纯装饰性的边框和底色填充**
