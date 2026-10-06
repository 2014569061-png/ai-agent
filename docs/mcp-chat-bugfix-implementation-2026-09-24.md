# 聊天页 5 个问题修复实施记录（2026-09-24）

> 方案见 `docs/mcp-chat-bugfix-plan-2026-09-24.md`。本文记录实际落地的改动、验证结果和遗留事项。
> 实施顺序：#5 暂停 → #2 续跑入口 → #4 执行面板 → #1 键盘 → #2 预算策略与存储挂载 → #3 样式。

## 总览

| # | 问题 | 根因 | 修复要点 |
|---|---|---|---|
| 5 | 暂停按钮无效，模型继续工作 | `pause()` 不设 `paused`；暂停只在步骤开头的检查点生效，模型流式输出期间不中断；工具检查点静默阻塞、不发 paused 事件；停止只能长按 | 暂停立即中断当前模型请求（按步取消令牌）；工具在当前命令结束后停下并发出 paused；暂停态同时显示「停止」和「继续」 |
| 2a | 「已达到单次执行步数预算」显示成未知错误，只能从头重试 | 预算暂停经 `formatErrorForMessage` 写成错误段落；续跑入口只接在计划面板 | 正文写入暂停标记，气泡渲染暂停提示卡：继续执行 / 从头重试 / 切换模型；兼容旧消息 |
| 4 | 顶部执行面板被裁切，最后一条滚不到 | 面板外层滚动里又嵌了时间线内层 280dp 滚动 | compact 只显示最近 3 条和所有待确认项，其余进「查看全部」；面板限高 min(可用高度 38%, 320dp)，内容超高时默认停在最新一步 |
| 1 | 底部白块、输入框悬在半空 | Scaffold 按 `viewInsets` 缩小整个 body，部分 ROM 会残留过期的键盘 inset | 关闭 Scaffold 缩放；`KeyboardInsetScope` 按输入焦点门控键盘高度、识别残留 inset；`KeyboardSpacer` 只把输入区顶到键盘上方 |
| 2b | 模型中途停止 | 默认聊天只有 16 轮；PRoot 没挂载共享存储，模型反复 `ls /storage/emulated/0` 空转到预算耗尽 | 默认 40 轮 + 有进展时自动续跑 2 次；连续失败熔断；授予「所有文件访问」后挂载 `/sdcard` |
| 3 | 聊天样式改成 DeepSeek 风格 | — | AI 回复去掉头像、卡片和标题，纯文本铺满；模型名 · 耗时放到操作行右侧；用户气泡浅色无描边 |

## 各项改动

### #5 暂停

- `run_controller.dart`：新增 `onPauseInterrupt` 钩子，`pause()` 触发，`cancel()` / `seal()` 清空。
- `agent_executor.dart`：
  - 每一步使用独立的 `CancelToken`，并与整次运行的取消令牌联动（停止仍然有效）。
  - 模型流式输出期间暂停：取消本步请求，已输出的部分保留为一条 assistant 消息，再补一条系统提示「从中断处继续，不要重复」；恢复后接着写。
  - `pausePoint()` 先发出 paused 事件再等待检查点，同时用于步骤开头和每个工具执行前。
- `chat_controller.dart`：`pause()` 立即设置 `paused: true`，并记录「正在暂停：当前步骤结束后停下」。
- `floating_capsule_input.dart`：运行中且已暂停时，在「继续」旁边增加「停止」按钮（`trailing_action_stop_when_paused`）。
- `chat_page.dart`：当前任务不支持暂停时（后台开发任务）给出提示，不再无反应。

### #2a 续跑入口

- `error_humanizer.dart`：`kRunPauseMarker`、`RunPauseKind`（budget / repeatedFailures）、`formatRunPauseForMessage`、`splitRunPauseNotice`、`stripRunPauseMarker`。旧消息只有在技术细节标记后面紧跟「已达到单次执行步数预算」时才识别为暂停，回复正文里单纯引用这句话不会被误判。
- `chat_run_execution.dart`：预算暂停写入暂停标记，不再写成错误。
- `message_bubble.dart`：`_RunPauseNoticeCard`。只有最后一条、且不在运行中时显示按钮，历史里的旧提示只保留文字。
- `chat_message_list.dart` / `chat_page.dart`：接入 `onResumeRun`。优先从内存里的断点续跑；断点已失效（例如应用重启过）时，把续跑指令填进输入框，由用户确认发送。
- 复制、朗读、分享都会去掉标记里的元数据。

### #4 执行面板

- `tool_activity_section.dart`：compact 模式只渲染最近 3 条和所有「等待确认」条目，不再内嵌滚动；「查看全部 N 条」打开底部抽屉，列出全部步骤（打开时的快照）。
- `chat_page.dart`：面板改为 `ConstrainedBox(maxHeight: min(可用高度 × 0.38, 320))`，`reverse: true` 让内容超高时默认停在底部；顶部状态文字只在运行中显示。
- `chat_run_execution.dart`：状态文字不再一律写「等待确认」，分别是「准备执行：工具」「正在执行：工具」「等待你的确认：工具」「已暂停，可继续或追加指令」。

### #1 键盘

- `utils/keyboard_avoider.dart`（新增）：
  - `KeyboardInsetScope`：订阅 `didChangeMetrics` 和焦点变化；有文本输入焦点时如实跟随键盘；失焦后先跟随收起动画，超过 `AppTokens.durationImeSettle`（400ms）仍未归零，就按 0 处理并调用 `TextInput.hide`；应用切到后台时释放输入焦点。
  - `KeyboardSpacer`：放在输入区最底部，键盘弹出时占位键盘高度，收起时占位底部安全区。
- `chat_page.dart`：`resizeToAvoidBottomInset: false`；主 Column 外包 `KeyboardInsetScope`，末尾加 `KeyboardSpacer`；空态用 `Builder` 放进 scope 内。
- `floating_capsule_input.dart`：新增 `bottomPadding` 参数，聊天页传 8；不传时保持原来的自适应逻辑。
- `keyboard_insets.dart`：在 scope 内时返回有效键盘高度。
- `app_tokens.dart`：新增 `durationImeSettle` token。

### #2b 预算策略与存储挂载

- 默认聊天 40 轮（`chat_controller.dart`）。
- `agent_executor.dart`：
  - `autoContinueLimit`：轮数用完时，如果最近有进展（最近有工具成功，且最后 4 次不全是失败），就在同一次运行里再追加一轮预算，发出 `AgentBudgetExtendedEvent`。默认聊天传 2；选了 Agent 时传 0，严格遵守 Agent 自己设定的最大步数上限。
  - `failurePauseThreshold`（默认 4）：连续 4 次工具失败、中间没有任何成功，就提前暂停（`AgentPauseReason.repeatedFailures`），显示「连续多次操作失败」暂停卡。
  - 同一调用（工具名 + 参数）失败 2 次后，在这一步的全部工具结果之后注入系统提示，要求换方法或向用户说明。
  - 环境说明新增「共享存储」规则：访问 `/sdcard` 报错说明没有授权，直接请用户开启「所有文件访问」，不要换路径反复重试。
- `chat_run_execution.dart`：区分两种暂停原因；自动续跑时记录运行事件，并在状态文字里显示「已自动续跑（n/2）」。
- Agent：步数范围 1–100，新建默认 40（`agent_editor_page.dart`、`agent_draft_service.dart`、`agent_draft.dart`）。已有 Agent 保存的值不变。
- `BuiltinLinuxRunner.kt`：Android 11+ 且已授予「所有文件访问」时，追加绑定 `-b /storage/emulated/0` 和 `-b /storage/emulated/0:/sdcard`。

### #3 样式

- `message_bubble.dart`：
  - AI 回复：去掉 `MascotAvatar`、卡片（白底、描边、阴影）和「模型名 • 耗时」标题；正文与列表 16dp 边距对齐并铺满宽度。
  - 操作行（`_ReplyActionRow`）：左侧复制 / 朗读（平台支持时）/ 分享（share_plus），右侧是小号弱化的「模型名 · 耗时」，最后一条回复末尾是「重新生成」。
  - 思考块沿用「已思考（用时 X 秒）」。
  - 工具消息改成行内提示（小图标 + 浅底）；错误详情和暂停卡同样是行内提示。
  - 用户气泡：浅色品牌底、无描边，圆角 20 / 20 / 6 / 20（右下角收小）。
- 没有加 👍 / 👎：现有的「有帮助」反馈（`TaskFeedbackService`）按开发任务的 taskId 存储，普通聊天消息接不上，为避免出现点了没反应的按钮，这次不加。

## 验证

- `flutter analyze`（全项目）：No issues found。原有的 3 条 info（`project_settings.dart:83` 的 `if` 缺花括号、`motion_ui_regression_test.dart` 两处可加 `const`）已顺手修掉，不改变行为。
- 新增测试：
  - `test/agent_pause_interrupt_test.dart`：流式输出中暂停、停止联动每步令牌、工具执行中暂停、暂停态输入框（320dp、2 倍字号）。
  - `test/run_pause_notice_test.dart`：暂停标记往返、旧消息兼容、引用不误判、暂停卡按钮。
  - `test/tool_activity_compact_dock_test.dart`：最近 3 条、待确认保留、查看全部抽屉、短列表。
  - `test/keyboard_avoider_test.dart`：聚焦跟随、残留超时回落并收起输入法、切后台释放焦点；聊天页上残留 inset 时输入框回到底部，聚焦时被顶起、收起后回位。
  - `test/agent_budget_policy_test.dart`：自动续跑 2 次、没有进展不续跑、连续失败熔断、同一调用失败提示。
  - `test/deepseek_style_bubble_test.dart`：无头像和标题、操作行元信息、历史回复的按钮、用户气泡无描边。
- 更新测试：`test/run_controller_test.dart`（暂停钩子）、`test/agent_draft_service_test.dart`（上限 32 → 100）。
- 全量测试：1392 个全部通过。第一轮全量时有 2 个原有的失败，都不是这次修复引入的，已一并修好：
  - `automation_fallback_test`（上一轮「非 Root 设备控制」工作留下的）：用户同意后，智能体带 `acknowledgeFallback: true` 重新调用；只要此前探测过执行通道，审批卡片仍显示确认前的「批准即表示知悉」。已改为：只要带了确认就写「用户已知悉」，并保留具体的降级动作列表（`lib/application/android_automation_tool.dart`）。
  - `layering_test`（交接文档里记录过的预存失败，79 > 78）：`chat_page.dart` 直接依赖 `notification_service` 只为申请通知权限。改为调用 `ChatController.ensureNotificationPermissionOnce()`，展示层少一条基础设施导入，回到 78。
- Debug APK 构建成功，Kotlin 编译通过：`build/app/outputs/flutter-apk/app-debug.apk`（21:58，包含以上全部改动）。
- 真机回归：没有执行。`adb devices` 没有检测到设备，电脑上也没有安装 Android 模拟器。

## 真机验证清单

1. 键盘：点输入框 → 输入框紧贴键盘上方，中间没有空隙；点空白处收起 → 输入框回到底部；键盘弹出时切到别的应用再回来 → 底部没有白块，输入框在底部。
2. 暂停：模型输出过程中点暂停 → 输出立即停下，按钮变成「继续」+「停止」；点继续 → 从中断处接着写；工具执行中点暂停 → 当前命令结束后停下；暂停时点停止 → 任务结束。
3. 预算：让模型做一个需要很多步的任务 → 有进展时状态文字出现「已自动续跑（1/2）」；最终暂停时显示暂停卡（不是「未知错误」），点「继续执行」从断点接着做。
4. 执行面板：工具步骤超过 3 条 → 只显示最近 3 条和「查看全部 N 条」，最新一步始终可见，面板不会顶满屏幕。
5. 样式：AI 回复没有头像和卡片；操作行右侧显示「模型名 · 耗时」；用户气泡没有描边。
6. 共享存储：授予「所有文件访问」后，让模型执行 `ls /sdcard` → 能列出文件；没有授权时，模型直接提示去开启权限，不会反复重试。

## 遗留事项

- 有一个孤儿进程 `flutter_tester.exe`（PID 51488，管理员权限，19:21 启动）一直占用旧的 `sqlite3.dll`，导致测试无法清理 `build/native_assets/windows`。这个 dll 已经挪到 `build/.locked_dll_51488/`，测试恢复正常。重启电脑或用管理员权限结束该进程后，可以删掉这个目录。
- 真机回归待做：连上手机（开启 USB 调试）后，安装上面的 APK，按「真机验证清单」逐项验证。
- 构建和测试日志在 `build/nexus_verify_build.log`、`build/nexus_full_tests.log`。

## 改动文件

- `lib/application/`：`run_controller.dart`、`agent_executor.dart`、`chat_controller.dart`、`chat_run_execution.dart`、`error_humanizer.dart`、`agent_draft_service.dart`、`android_automation_tool.dart`、`project_settings.dart`
- `lib/domain/agent_draft.dart`
- `lib/presentation/chat/`：`chat_page.dart`、`chat_message_actions.dart`、`widgets/floating_capsule_input.dart`、`widgets/message_bubble.dart`、`widgets/chat_message_list.dart`、`widgets/tool_activity_section.dart`
- `lib/presentation/agents/agent_editor_page.dart`
- `lib/presentation/utils/`：`keyboard_insets.dart`、`keyboard_avoider.dart`（新增）
- `lib/presentation/theme/app_tokens.dart`
- `android/app/src/main/kotlin/com/nexusagent/app/BuiltinLinuxRunner.kt`
- `test/`：6 个新增测试文件；更新 `run_controller_test.dart`、`agent_draft_service_test.dart`、`motion_ui_regression_test.dart`
