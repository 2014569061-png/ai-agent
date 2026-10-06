# NEXUS Agent 前端交接文档

日期：2026-09-25

## 目标

本文用于交给 Gemini，负责继续完成 `lib/presentation` 前端工作。当前任务已明确前后端分开处理；后端本轮没有重复修改已经完成的安全修复。

## 项目基线

- Flutter 3.47.2 / Dart 3.13.2。
- 项目是 Android-only Flutter 应用。
- 分层：
  - `lib/domain`：模型和领域规则
  - `lib/application`：用例、状态和 Agent 编排
  - `lib/infrastructure`：数据库、网络、工具、平台能力
  - `lib/presentation`：页面和组件
- 当前有效 Flutter SDK：
  - `C:\src\flutter\bin\flutter.bat`
- 不要假设 `flutter` 已经在 PATH 中。Windows 下可直接使用上面的完整路径。

## 当前验证结果

已验证：

```text
C:\src\flutter\bin\flutter.bat analyze
No issues found

C:\src\flutter\bin\flutter.bat test \
  test/chat_page_attachments_test.dart \
  test/chat_visual_hierarchy_test.dart \
  test/chat_state_matrix_test.dart \
  test/chat_rebuild_scope_test.dart
All tests passed
```

聊天页面专项测试共 77 项通过，覆盖附件、布局、大字体、深浅色、材质模式和流式重建范围。

## 前端主要文件

| 文件 | 职责 |
|---|---|
| `lib/presentation/chat/chat_page.dart` | 聊天主页，仍然偏大，包含页面布局和多个交互入口 |
| `lib/presentation/chat/widgets/chat_message_list.dart` | 消息列表和分页/滚动 |
| `lib/presentation/chat/widgets/message_bubble.dart` | 用户消息、助手回复、工具提示、暂停提示 |
| `lib/presentation/chat/widgets/floating_capsule_input.dart` | 底部输入区 |
| `lib/presentation/chat/widgets/tool_activity_section.dart` | 工具执行活动面板 |
| `lib/presentation/chat/widgets/session_metrics_bar.dart` | 会话指标 HUD |
| `lib/presentation/chat/widgets/session_metrics_sheet.dart` | 会话指标详情面板 |
| `lib/presentation/chat/widgets/context_budget_bar.dart` | 上下文预算展示 |
| `lib/presentation/chat/utils/keyboard_avoider.dart` | 聊天页键盘避让 |

## 已完成，不要重复实现

### 聊天页交互

- 流式回复时页面级重建已限制：
  - 顶栏不因 `liveReply` 重建。
  - 输入胶囊不因 `liveReply` 重建。
  - 消息列表局部重建。
- 附件扩展名来自单一策略来源。
- 拒绝不支持的音视频附件。
- 文件数量和单文件大小限制已有可见提示。
- 工具活动面板紧凑模式只展示最近项目和待确认项目。
- 运行暂停、预算暂停和继续执行入口已经接入。
- 聊天页键盘残留 inset 已有防护逻辑。
- 助手消息已采用更简洁的文本优先样式。
- 会话指标面板和详细诊断入口仍然保留。
- 上下文预算条已经区分：
  - 已使用输入
  - 输出预留
  - 真正剩余空间

### 视觉与可访问性

- 已覆盖 320/360/390dp 等小屏布局测试。
- 已覆盖大字体测试。
- 已覆盖浅色、深色和多种玻璃材质。
- 图标按钮已有部分 `Semantics` 和 `Tooltip`。
- 输入区主动作槽位尺寸已固定，避免发送/运行状态改变布局。

## Gemini 需要继续完成的工作

### P1：Provider 未配置时的引导条

目标：用户进入聊天页但没有可用模型服务商时，不要等到发送失败才提示。

建议位置：

- `lib/presentation/chat/chat_page.dart`
- `lib/presentation/chat/widgets/floating_capsule_input.dart`
- 可新建 `lib/presentation/chat/widgets/provider_setup_hint.dart`

行为要求：

1. 没有可用 Provider 时，在输入区上方显示一条轻量引导。
2. 提供明确的“去设置”入口。
3. 配置完成后自动消失。
4. 不要阻挡消息列表，也不要覆盖键盘。
5. 不要在每次流式 token 更新时重建引导条。
6. 引导条可以关闭，但关闭状态不要覆盖“未配置”事实；下次新建会话或重新打开页面可以再次出现。
7. 大字体和 320dp 宽度下不能溢出。

建议测试：

- 未配置 Provider 时显示。
- 已配置 Provider 时不显示。
- 点击设置入口能够触发已有设置导航。
- 360dp 宽度、1.3 或 2.0 字体不溢出。
- `liveReply` 更新时引导条不重复构建。

### P1：聊天页拆分

当前 `chat_page.dart` 仍然过大。只做边界清晰的拆分，不要顺手重构业务逻辑。

建议拆分顺序：

1. 会话指标 HUD。
2. 执行状态条。
3. 技能提示槽。
4. 底部输入区外围布局。

重要约束：

- 不要把 `liveReply` 订阅提升到整个 `ChatPage`。
- 不要改变 `ChatController` 的执行顺序。
- 不要改变暂停、审批、预算和压缩的状态语义。
- 每次只抽一个组件，抽完运行分析和相关测试。

### P2：工具活动面板真机体验

自动化测试已经覆盖基本布局，但还需要真机确认：

- 超过 3 条活动时，最新活动始终可见。
- 打开“查看全部”后完整列表可滚动。
- 手动上滑时，新活动不会强行抢回滚动位置。
- 返回最新入口可用。
- 320dp 和大字体下没有裁切。

涉及：

- `tool_activity_section.dart`
- `chat_page.dart`
- `test/tool_activity_compact_dock_test.dart`

### P2：上下文指标交互

检查并完善以下行为：

- 指标面板中的“输出预留”不能被显示为普通空闲空间。
- 压缩完成后工具活动应显示“已压缩”标记。
- 如果已有跳转到消息的回调，确认历史数据缺少锚点时不会崩溃。
- 压缩确认文案必须说明：只影响发送给模型的上下文，不删除聊天记录。

相关文件：

- `session_metrics_sheet.dart`
- `context_budget_bar.dart`
- `tool_activity_section.dart`
- `context_compression_planner.dart`

## 设计约束

- 不新增依赖。
- 不修改数据库 schema。
- 不改变 `AgentExecutor` 的上下文裁剪顺序。
- 不把后端服务、数据库和平台通道直接引入新的展示组件。
- 页面组件通过现有 Riverpod/application API 获取状态。
- 保持现有 Liquid Glass、主题、动效降级和中文文案体系。
- 不删除真机截图、测试证据或用户已有工作区文件。
- 不执行 `git clean -fd`、`git reset --hard` 或其他破坏性清理。

## 推荐验证命令

```bat
C:\src\flutter\bin\flutter.bat analyze

C:\src\flutter\bin\flutter.bat test ^
  test/chat_page_attachments_test.dart ^
  test/chat_visual_hierarchy_test.dart ^
  test/chat_state_matrix_test.dart ^
  test/chat_rebuild_scope_test.dart ^
  test/ui_refactor_regression_test.dart
```

如修改了聊天页面布局，还应运行：

```bat
C:\src\flutter\bin\flutter.bat test test/tool_activity_compact_dock_test.dart
```

## 当前工作区注意事项

当前工作区有用户或历史流程产生的未跟踪文件，包括 `device-check/`、`settings.txt` 等。不要删除或重置这些文件。

本轮仅修复了 `analysis_options.yaml` 的 `artifacts/**` 排除规则，使完整 `flutter analyze` 不再扫描历史源码备份。前端实现应基于当前 `lib/` 源码，而不是 `artifacts` 中的快照。

