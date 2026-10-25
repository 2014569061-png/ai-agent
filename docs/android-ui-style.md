# Android UI 规范

适用于当前 Android 实现。共享主题来自 lib/presentation/theme/mobile_theme.dart；桌面由独立布局与主题控制。

## 对话与导航

- 助手首页、会话与侧栏使用白底、浅灰输入区和简短文字建议。助手正文无头像，用户消息使用浅灰背景。
- 首页标识与欢迎语保持紧凑，不恢复旧光球、欢迎功能卡或多层装饰。
- 手机通过左侧抽屉导航，首页底部保留输入区。详情页提供返回，保留边缘滑动和每个入口的导航状态。
- 侧栏搜索按需展开；退出搜索时清空筛选并恢复导航入口。搜索期间避让键盘，不遮挡结果。
- 模型和执行选项使用轻量文字选择器。窄屏时可降级为图标，完整名称通过提示或面板查看。

## 公共组件

| 场景 | 组件或约定 |
|---|---|
| 页面 | NexusPageLayout / NexusPageHeader |
| 内容分组 | SectionCard |
| 设置 | SettingsGroupCard / SettingsTile |
| 列表 | NexusListTile |
| 搜索 | NexusSearchField |
| 异步状态 | AsyncStateView / NexusAsyncContent |
| 结果 | ResultCardView |
| 弹层 | showNexusSheet / showNexusDialog |
| 配色 | Theme.of(context).colorScheme / AppTheme.semanticOf(context) |
| 几何 | MobileTheme，避免复用旧桌面圆角 token |

普通页面沿用蓝白、实色圆角分组，语义状态色保留。主要触控目标至少 48dp；文字在窄屏与大字体下自然换行，必要路径、权限和操作后果可完整查看。长参数、诊断和原始 JSON 按需展开。

## 动效与专用画布

- 手机消息采用轻位移和淡入；助手只保留首 token 淡入，历史与流式追加不重播外层入场。
- 当前 MobileMotion 参数：按下 100ms、恢复或图标淡入 120ms、消息 180ms、Sheet 进入 240ms / 退出 160ms。
- 手机 Sheet 使用实色 Material，避免移动面板实时采样与模糊背景；仅在实际面板范围使用 RepaintBoundary。
- 尊重减少动态效果设置，复用并销毁动画对象。布局、键盘和滚动的稳定性优先于装饰循环。
- 终端、代码、Git 差异和网页可使用专用画布；页头、工具栏、列表和表单仍使用共享组件。自定义聊天背景保留。

## 信息与交互

每个页面突出一个主要操作。保留真实能力、授权说明、失败恢复、审批和结果入口；不以重复说明或装饰标签解释布局。状态不能只依赖颜色，长按操作应有可访问入口。

## 验证

1. 新页面登记 test/android_ui_inventory_test.dart，使用内存数据库和隔离文件。
2. 检查正常手机、360dp 窄屏、1.6 倍文字，以及涉及的键盘、审批和错误状态。
3. 涉及布局时在 Android 实际执行分支和模拟器中核对，确认热重载成功。
4. 动效检查关注发送、流式高度、键盘与滚动联动，并在目标设备核对帧开销；debug 模拟器不能替代 ARM64 真机 profile 验收。

```bash
flutter test --no-pub test/android_ui_inventory_test.dart
```

可通过 --dart-define=NEXUS_UI_GALLERY=true 生成页面截图，默认输出到本机 local/temp/android-ui-gallery/。
