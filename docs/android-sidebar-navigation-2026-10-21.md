# Android 侧栏导航调整

用户反馈底部导航突兀，明确希望移入侧边展开页。本次保留蓝白、柔光、圆角视觉，并取消手机底部导航，首页底部仅保留输入区。

## 入口与行为

- 左上角菜单或左侧边缘滑动打开统一抽屉；助手、任务、工作区、我的保留各自的导航栈和未发送草稿。
- 抽屉包含新建对话、主入口、默认收起的“助手与工具”、最近会话与搜索；历史重命名、置顶、收藏和删除继续复用原有实现。
- Agent、模型与运行、MCP、提示词、运行与费用、会话与工具保留明确入口。会话切换、新建等操作委托给聊天页原有逻辑，继续处理草稿与附件。
- 任务角标来自 JobBoard.attentionJobs；与收件箱未读数保持独立。
- 系统返回先关闭抽屉，再处理子页面返回；非助手根页面返回助手。抽屉打开期间暂停消费助手外部输入，避免浮层期间误处理分享或语音输入。附件面板与抽屉分别响应返回，不会一起关闭。
- 桌面原有导航保持原有路径。

## 验证

- 全项目 flutter analyze --no-pub：No issues found。
- 导航、键盘、返回、深链和附件 5 组测试共 29 项通过。
- 助手、任务、工作区、我的普通手机与 360dp / 1.6 倍字体页面清单测试 8 项通过。
- 已有 Nexus_Preview_API_36（emulator-5554）成功热重启；实际核对四个主入口、侧栏开关、工具折叠与系统返回。
- 调试预览保持运行。

模拟器截图：

- [首页](design-previews/android-sidebar-2026-10-21/home-sidebar.png)
- [侧栏](design-previews/android-sidebar-2026-10-21/sidebar-open.png)
- [工具展开](design-previews/android-sidebar-2026-10-21/sidebar-tools.png)
- [任务](design-previews/android-sidebar-2026-10-21/tasks-sidebar.png)
- [工作区](design-previews/android-sidebar-2026-10-21/workspace-sidebar.png)
- [我的](design-previews/android-sidebar-2026-10-21/settings-sidebar.png)
