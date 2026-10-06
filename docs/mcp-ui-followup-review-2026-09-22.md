# UI 修改接续检查（2026-09-22）

## 范围和边界

本轮按用户选择执行检查与验证，没有修改应用源码。工作树混合了大量既有功能、安全、UI 改动；`git --no-pager diff --stat` 返回 155 个已跟踪文件修改、12807 行新增、4842 行删除，不包含未跟踪文件，不能将全部差异归为最近一批 UI 修改。不执行重置、清理、提交或安装 APK。

## 已确认的接续基础

- `lib/presentation/motion/motion_preferences.dart` 已有 full/reduced/off 策略，系统 disableAnimations 优先。
- `lib/presentation/theme/app_presentation_preferences.dart` 已在 Navigator 上层传播动效偏好，并用 AppTextScaler 保留系统字体缩放曲线。
- `lib/presentation/motion/nexus_page_route_factory.dart` 已读取有效转场时长。
- `lib/presentation/settings/appearance_theme_page.dart` 已去掉旧玻璃强度滑块；材质选中态统一调用 `AppAppearanceController.materialForValue`。
- `lib/presentation/chat/widgets/floating_capsule_input.dart:132` 的 AnimatedPadding 已使用 NexusMotion.durationBase。
- `device-check/20260922-ui-implementation/motion-green2.log` 和对应 `.exit` 记录上一轮 41 项测试通过、退出码 0。这是历史记录，不替代当前验证。

## 尚存问题

### P1：关闭动效未覆盖聊天程序性滚动

`lib/presentation/chat/chat_scroll_coordinator.dart:111-119,146-149` 仍固定 260/180ms，协调器没有偏好输入。`lib/presentation/chat/widgets/chat_message_list.dart:143-168` 的回底与 ensureVisible 仍固定 NexusMotion.base。

建议将有效策略传入协调器；关闭模式采用 jumpTo 或零时长 ensureVisible，避免向 animateTo 传入零时长。保留用户上翻阅读位置、历史分页和会话 epoch 守护。补 full/reduced/off 与系统 disableAnimations 的滚动行为测试。

### P2：缓存卡片仍为空交互

`lib/presentation/dashboard/widgets/kpi_card_grid.dart:65` 仍是 `onTap: () {}`。`lib/presentation/widgets/nexus_metric_tile.dart:129-146` 据非空回调启用交互外观。

建议移除空回调并保留 explanation，或接入真实详情。补不可点击语义/交互测试。

## 推荐下一批顺序

1. 先修滚动动效偏好遗漏，补程序性滚动回归。
2. 移除缓存卡片空交互，补仪表盘回归。
3. 补三档动效与系统减弱动态效果组合、动态切换和非线性字体缩放测试。
4. 再进行 320/360/390dp、大字体、深浅色、键盘和长聊天真机验证；Profile 帧耗时与性能仍需实测。

旧 `docs/ui-improvement-handoff.md` 的待办属于较早基线，应与当前源码核对；本轮没有据此重复实施 C4 或推翻既有视觉方案。

## 本轮实际验证

- `flutter test --no-pub test/motion_ui_regression_test.dart test/nexus_motion_and_widgets_test.dart test/route_transition_paint_test.dart test/glass_surface_test.dart test/liquid_glass_test.dart`：41 项通过，退出码 0。
- `flutter analyze --no-pub`：退出码 1，共 4 条 info（不是编译错误，但未达到零问题门槛）：
  - `lib/presentation/motion/motion_lifecycle.dart:2:8`：unnecessary_import。
  - `lib/presentation/motion/motion_lifecycle.dart:30:27`：TickerMode.of 已弃用，建议 TickerMode.valuesOf。
  - `lib/presentation/widgets/liquid_glass.dart:147:44,158:55`：if 语句缺少花括号。
- 编辑器 get_diagnostics 在检查时返回零 error/warning；它没有覆盖上述 info，不能代替命令行分析。
- Git 差异统计已成功读取。初始远端终端无输出的命令已请求强制取消，后续新终端成功完成命令。
- 本轮未跑全量测试、构建 APK、安装真机或采集 Profile；不宣称这些已经通过。

实际执行下一批前，优先清理以上 4 条分析问题并复跑 analyze，然后按上述 UI 剩余项推进。检查报告完成不代表 UI 问题已经修复。
