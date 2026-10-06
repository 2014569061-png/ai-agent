# UI 后续修复实施记录（2026-09-22）

## 范围

接续 `docs/mcp-ui-followup-review-2026-09-22.md`。本轮仅修改 6 个应用源码文件，新增 1 个回归测试文件；保留既有工作树，不重置、不清理、不提交、不安装 APK。

## 修改

- `lib/presentation/motion/motion_lifecycle.dart`：删除多余 foundation import，用 `TickerMode.valuesOf(context).enabled` 替代弃用接口。
- `lib/presentation/widgets/liquid_glass.dart`：为两处跨行 if 补齐花括号。
- `lib/presentation/chat/chat_scroll_coordinator.dart`：增加可注入的时长解析回调；回到底部及排队追尾在实际执行时解析偏好。零时长走 jumpTo，非零时长保留 animateTo，避免零时长断言。原有用户上翻、未读、分页和 epoch 防串会话逻辑保持。
- `lib/presentation/chat/chat_page.dart`：向协调器注入 MotionPreferences.adjustDuration，事件回调使用非监听读取，避免固定缓存旧偏好。
- `lib/presentation/chat/widgets/chat_message_list.dart`：无锚点/找不到消息时的回底和有效锚点的 ensureVisible 均接入有效动效策略。关闭模式直接定位，节能模式缩短时长，完整模式保留原有时长。
- `lib/presentation/dashboard/widgets/kpi_card_grid.dart`：移除缓存命中率的空 onTap，保留解释信息。

## 回归

新增 `test/ui_followup_regression_test.dart`，14 项：

- 三档应用偏好 × 系统 disableAnimations 开关，6 项回到底部测试。
- 同一矩阵，6 项消息定位回退测试。
- 排队追尾执行前切换至零时长，验证读取最新偏好且即时到达底部。
- 缓存命中率卡片没有点击回调，解释信息保留。

本轮新增消息列表测试覆盖的是缺失锚点回退，不声称新增了有效锚点定位专项测试或真实设备验证。

## 实际验证结果

- 对本轮 7 个 Dart 文件执行 dart format：成功，最终输出 7 files / 0 changed。
- `flutter analyze --no-pub`：退出码 0，No issues found。
- 对本轮已跟踪源码执行 `git -c core.safecrlf=false diff --check -- <paths>`：退出码 0。
- 运行以下 8 个测试文件：共 64 项通过，退出码 0。
  - `test/ui_followup_regression_test.dart`
  - `test/chat_scroll_coordinator_test.dart`
  - `test/dashboard_presentation_test.dart`
  - `test/motion_ui_regression_test.dart`
  - `test/nexus_motion_and_widgets_test.dart`
  - `test/route_transition_paint_test.dart`
  - `test/glass_surface_test.dart`
  - `test/liquid_glass_test.dart`

未执行全量测试、覆盖率、APK 构建、真机安装或 Profile 性能测量。不能由 widget 测试推断真机帧率与功耗。后续可推进大字体、键盘、长聊天和深浅色真机验收。
