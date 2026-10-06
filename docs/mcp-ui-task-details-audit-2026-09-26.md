# 任务详情页 UI 审计（2026-09-26）

截图：`artifacts/ui-shots/task_details_shots_test.dart`（393×2600 @2x 长截图，动效关闭）。示例为一条已完成的代码审查任务，含摘要、结构化产物、执行步骤和恢复 1 次；测试用内存数据库。
`task_details_page.dart` 无 WIP 改动；`section_card.dart` 属 WIP，只能传参。

截图伪影：底部操作栏两个按钮文字显示为方块（样式未指定字体族），真机正常。

## 问题

| 编号 | 问题 |
| --- | --- |
| X1 | 总览卡顶部显示内部标识：「类型：development:code_review」「来源：manual」 |
| X2 | 指标格「执行状态」显示英文 `completed`，与页头「已完成」徽标重复；浅色模式指标格没有底色，深色有描边，两套样式（同仪表盘 D4） |
| X3 | 执行流水线步骤标签是英文「Step 1 / Step 2 / Step 3」 |
| X4 | 工作区、更新时间两行用固定的浅色主题次要色，深色模式对比度偏低 |
| X5 | 各卡片圆角 12，其余已改页面为 16 |

## 方案（顺序 Y1→Y5）

- Y1：总览卡标签中文化——类型用 `taskTypeLabel`，来源映射为中文（未知值原样显示），胶囊改为无描边浅填充。（X1）
- Y2：指标格——「执行状态」改为中文状态名；浅色 / 深色统一为浅填充小格、去描边（优先在本页传参或包一层，不改共享组件；若必须改 `NexusMetricTile`，先说明影响范围）。（X2）
- Y3：流水线步骤标签改为「步骤 1」等中文。（X3）
- Y4：工作区 / 时间行改用主题次要色（`onSurfaceVariant`），两种主题都清晰。（X4）
- Y5：本页卡片圆角统一 16（只给 `SectionCard` 传参）。（X5）

## 交付（2026-09-26）

分支 `feat/harmony-motion`，未推送。每项都跑过 format（本文件是 formatter-clean）、analyze、全量测试（1535 通过）和快速 APK 构建。

| 项 | 提交 | 内容 | 解决 |
| --- | --- | --- | --- |
| Y1 | 0bd190f | 类型改用 `taskTypeLabel` 中文名；来源映射为中文（manual→手动发起、verification_repair→验证修复、scheduled→定时任务，未知值原样显示）；标签改为胶囊 | X1 |
| Y2 | dc8b684 | 执行状态显示中文（与页头徽标同一套文案）；三格改用本页局部 `_OverviewStat` 浅填充小格（不再在卡片内嵌套玻璃 / 描边卡），并排一行；共享 `NexusMetricTile` 未改 | X2 |
| Y3 | 4ca723d | 流水线「Step N」改为「步骤 N」 | X3 |
| Y4 | 45be94b | 工作区 / 更新时间行改用 `onSurfaceVariant`，深色模式对比度改善 | X4 |
| Y5 | ab2fecb | 本页 11 处 `SectionCard` 统一传入 16 圆角（文件级常量 `_kCardRadius`），组件未改 | X5 |

未处理：审计条目的回退状态色仍用 `AppTheme.textSecondary`（第 1121 行附近），属审计区块的状态配色，不在本轮范围。
