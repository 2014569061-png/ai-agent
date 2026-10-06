# 外观与语言设置页 UI 审计（2026-09-26）

范围：`appearance_theme_page.dart`（外观与主题）、`language_page.dart`（语言）。
截图：`artifacts/ui-shots/appearance_shots_test.dart`（393 宽 @2x 长截图，动效关闭）。
两个页面都没有 WIP 改动。`appearance_theme_page.dart` 改前是 formatter-clean；`language_page.dart` 改前就不是（第 58–94 行缩进），因此不对它整文件格式化，只手工改动到的行。

截图环境说明：测试里没加载语言偏好，所以语言页选中的是「跟随系统」；动效诊断卡显示「关闭动效」，是因为截图时强制关闭了动效。两者都不是页面问题。

## 问题

| 编号 | 页面 | 问题 |
| --- | --- | --- |
| A1 | 外观、语言 | 同一个图标浅色模式是彩色（浅色模式图标琥珀色，简体中文琥珀色，English 绿色），深色模式却是灰色。原因：`normalizeIconTint` 只保留等于当前主题语义色的颜色，而 `AppPalette.warning` / `success` 常量只等于浅色主题的语义色。主题模式三个图标还是实心款，其余都是描边款 |
| A2 | 外观 | 「界面材质」说明文字缩进 20（分组标题和卡片是 16），颜色是正文色，比分组标题还醒目 |
| A3 | 外观 | 「聊天背景」三行前导宽度不一：默认行是 20 的图标，另两行是 28 的缩略图，标题一个在 48、一个在 56，分隔线（48）也对不齐 |
| A4 | 模型提供商（上一组补漏） | 已配置和预设列表的首字母方块是 28，文字从 56 开始，分隔线仍是默认 48，差 8 |

不改：动效诊断卡里的原始值（`full`、`off`、档位名）。这是给排查问题用的诊断信息，值可复制，保留原始枚举名更方便对照日志。

## 方案（顺序 R1→R4）

- R1：外观页主题模式、语言页的图标统一中性色；主题模式三个图标换描边款。（A1）
- R2：「界面材质」说明文字缩进改 16，改用次要色。（A2）
- R3：「聊天背景」默认行的前导改成与另两行相同的 28 方块（浅底 + 图标）；三行之间的分隔线缩进改 56。（A3）
- R4：服务商列表两组的分隔线缩进改 56。（A4）

不改：主题切换、动效等级、材质、背景选择和选图等逻辑。

## 交付（2026-09-26）

分支 `feat/harmony-motion`，未推送。每项都跑过 analyze、相关测试（motion_ui_regression / motion_diagnostics / ui_refactor_regression / settings_page / wired_pages_smoke / provider_settings_labels，共 48 个）和截图对比；只格式化外观页和服务商列表，语言页未整文件格式化。全部完成后跑了全量测试（1537 通过）和快速 APK 构建（通过）。

| 项 | 提交 | 内容 | 解决 |
| --- | --- | --- | --- |
| R1–R3 | 0bddf8c | 主题模式图标换描边款 `*_outlined`，浅色模式、简体中文、English 图标改中性色（两种主题一致），语言页去掉不再使用的 `AppPalette` 导入；「界面材质」说明文字缩进 16、次要色；「聊天背景」默认行前导改为 28 方块（浅底 + 图标），三行分隔线缩进 56 | A1、A2、A3 |
| R4 | 1ef0719 | 服务商列表已配置 / 预设两组分隔线缩进 56，对齐首字母方块后的文字 | A4 |
| R5 | d37fe44 | 服务商配置页「测试连接」结果图标改用 `AppTheme.semanticOf(context)` 的成功 / 危险色。原先用 `AppPalette` 常量，深色模式下被降成灰色，成功和失败无法区分；截图 `pv_detail_status_*` 确认两种主题都是红色失败图标 | A1 同因 |

同一轮还处理了存储权限（未提交，和你的清单 WIP 放在一起）：`AndroidManifest.xml` 加回 `WRITE_EXTERNAL_STORAGE`（`maxSdkVersion=29`），`docs/android_permission_review.md` 同步说明原因。已在 release 合并清单中确认生效。

其它页面的同类隐患：凡是把 `AppPalette.warning` / `success` 作为 `SettingsTile.iconColor` 的地方，都会出现“浅色彩色、深色灰色”的不一致（原因见 A1），后续页面组按同样方式处理。

已处理（3c35294）：「测试连接」失败时原来只显示一行错误原因，其余被省略。现在由本页 `ProviderConnectionStatus` 显示：标题只写结论，完整原因放在下方，最多 3 行，超出可滚动，可以选中复制；测试进行中用中性色沙漏图标，不再显示红色。`test/provider_settings_labels_test.dart` 新增 2 个组件测试。
