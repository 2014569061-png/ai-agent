# 设置页 UI 审计（2026-09-26）

截图：`artifacts/ui-shots/settings_shots_test.dart`（393×852 @2x，动效关闭）。
可改文件：`lib/presentation/settings/settings_page.dart`（干净）。
不可改：`lib/presentation/widgets/section_card.dart`（WIP），卡片描边因此保留。

## 问题

| 编号 | 问题 | 原因 |
| --- | --- | --- |
| G1 | 右侧值与箭头停在行中间，有值/无值两类行的箭头不在同一竖线 | `_buildRow` 里值用 `Flexible` 与标题 `Expanded` 平分剩余宽度 |
| G2 | 搜索框 8 圆角 + 描边，像表单输入框而非搜索胶囊 | 使用 OutlineInputBorder |
| G3 | 分组卡片 12 圆角，与消息区卡片 16 不统一 | `SectionCard` 默认 radiusCard |
| G4 | 分组标题缩进 4，和卡片内容起点（16）不对齐 | `_buildSectionHeader` padding |
| G5 | 图标粗细不一：数据管理 / 字体大小 / 自动化为实心，其余为描边 | 选用的 Material 图标变体 |

## 方案（顺序 T1→T5，每项前后对比，确认后提交）

- T1：值改为右对齐（最大宽度约 45%，超出省略），箭头统一贴右。
- T2：搜索框改为无描边浅底胶囊（高 40，圆角半高），聚焦时品牌色细描边。
- T3：`_buildCard` 传 `borderRadius: 16`（不改 SectionCard 本身）。
- T4：分组标题左缩进 16、上方留白统一。
- T5：换成同一套描边风格图标（仅图标常量）。

## 交付（2026-09-26）

| 项 | 提交 | 内容 |
| --- | --- | --- |
| T1 | 60439ee | 行尾值右对齐（最多约 42% 屏宽），箭头统一贴右 |
| T2 | c6e53ea | 搜索框改为无描边浅底胶囊，聚焦时品牌色细描边 |
| T3+T4 | f273917 | 分组卡片 16 圆角；分组标题缩进 16，分组间距 24 |
| T5 | 2919fd7 | 数据管理 dataset_outlined、设备自动化 auto_mode_rounded |

每项均通过 format / analyze / 全量 1535 测试 / fast APK 构建。
限制：卡片描边来自 `SectionCard`（WIP 文件），WIP 合并后可再改为浅底无描边。
字体大小图标保持不变（文字字形无描边版本）。
